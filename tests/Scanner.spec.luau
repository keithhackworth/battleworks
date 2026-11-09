-- Exercise production cone geometry and scanner with real analytic box/ellipsoid
-- intersections. Engine broad-phase, filtering and raycasts are stand-ins here.
local Config=require("ScannerConfig")
local G=require("ScannerGeometry")
local Values=require("BWValue")
local Scanner=require("DirectionalScanner")
local Parser=require("BWParser")
local Runtime=require("BWRuntime")
local Sim=require("TankSimulation")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local function near(a,b,t) return math.abs(a-b)<(t or 1e-6) end
local function frame(position,yaw)
 local c,s=math.cos(yaw or 0),math.sin(yaw or 0)
 return {Position=position,PointToWorldSpace=function(_,v) return position+Vector3.new(c*v.X+s*v.Z,v.Y,-s*v.X+c*v.Z) end,
  localPoint=function(v) local d=v-position; return Vector3.new(c*d.X-s*d.Z,d.Y,s*d.X+c*d.Z) end,
  localDirection=function(d) return Vector3.new(c*d.X-s*d.Z,d.Y,s*d.X+c*d.Z) end}
end
local function part(name,position,size,yaw,shape)
 local p=Instance.new("Part"); p.Name=name; p.Size=size; p.CFrame=frame(position,yaw); p.Shape=shape; p.CanQuery=true
 return p
end
local function intersection(p,origin,direction)
 local a,d=p.CFrame.localPoint(origin),p.CFrame.localDirection(direction)
 local h=p.Size/2
 if p.Shape==Enum.PartType.Ball then
  local q=Vector3.new(a.X/h.X,a.Y/h.Y,a.Z/h.Z); local v=Vector3.new(d.X/h.X,d.Y/h.Y,d.Z/h.Z)
  local aa,bb,cc=G.dot(v,v),2*G.dot(q,v),G.dot(q,q)-1
  local disc=bb^2-4*aa*cc
  if disc<0 then return nil end
  local t=(-bb-math.sqrt(disc))/(2*aa)
  return if t>=0 and t<=1 then t else nil
 end
 local low,high=0,1
 for _,axis in {"X","Y","Z"} do
  if math.abs(d[axis])<1e-12 then if math.abs(a[axis])>h[axis]+1e-8 then return nil end
  else
   local lo,hi=(-h[axis]-a[axis])/d[axis],(h[axis]-a[axis])/d[axis]
   if lo>hi then lo,hi=hi,lo end
   low=math.max(low,lo); high=math.min(high,hi)
   if low>high+1e-9 then return nil end
  end
 end
 return low
end
local function setup()
 local parts,records={},{}
 local world={casts=0,overlaps=0}
 function world:GetPartBoundsInRadius(origin,radius,params)
  self.overlaps+=1; local found={}
  for _,p in params.FilterDescendantsInstances do
   local a=p.CFrame.localPoint(origin); local h=p.Size/2
   local closest=Vector3.new(math.clamp(a.X,-h.X,h.X),math.clamp(a.Y,-h.Y,h.Y),math.clamp(a.Z,-h.Z,h.Z))
   if p.CanQuery and (a-closest).Magnitude<=radius then table.insert(found,p) end
  end
  return found
 end
 function world:Raycast(origin,direction,params)
  self.casts+=1; local best,distance=nil,math.huge
  for _,p in params.FilterDescendantsInstances do
   if p.CanQuery then
    local t=intersection(p,origin,direction)
    if t and t<distance then best,distance=p,t end
   end
  end
  if best then return {Instance=best,Position=origin+direction*distance,Distance=direction.Magnitude*distance} end
 end
 local source={state=Sim.new(Vector3.zero),id="source"}
 source.hitbox=part("self",Vector3.new(0,2.5,0),Vector3.new(8,5,10)); table.insert(parts,source.hitbox)
 local service=Scanner.new(world,function() return parts,records end)
 local function add(name,position,size,tank,yaw,shape)
  local p=part(name,position,size or Vector3.new(4,5,6),yaw,shape); table.insert(parts,p)
  if tank then records[p]={state=Sim.new(position),id=name,playerName=name} end
  return p
 end
 return service,source,add,world,parts,records
end
for _,sample in {{-721,359},{-45,315},{360,0},{765.5,45.5},{-1e-300,0}} do check(near(G.normalize(sample[1]),sample[2]),"angle normalization") end
for _,source in {"Scanner(-720)","Scanner(-45)","Scanner(1e3 - 10)","Scanner(360)","Scanner(45, best_effort=false)"} do
 local parsed=assert(Parser.parse(source)); check(parsed[1].value>=0 and parsed[1].value<360,"finite scanner literals normalized without movement-angle limit")
end
for _,source in {"scanner(45)","Scanner()","Scanner(to=0)","Scanner(1e999)","Scanner(0/0)","Scanner(1,2)","Scanner(1, best_effort=1)"} do
 local p,e=Parser.parse("# test\n"..source); check(not p and e.line==2,"invalid scanner syntax has source line")
end
local service,source,add,world,parts,records=setup()
local target=add("player3",G.direction(0,39.6)*58+Vector3.new(0,2.5,0),Vector3.new(1,5,1),true)
local observation=assert(service:execute(source,45,1))
local result=observation.value
check(Values.isDictionary(result) and result.type=="tank" and result.player=="player3.Boomer#player3" and result.relation=="enemy","dictionary tank observation")
check(result.distance>57 and result.distance<58 and result.relative_direction>39 and result.relative_direction<40,"actual surface bearing/range differ from requested 45 degrees")
check(observation.timestamp==1 and observation.origin.Y==2.5 and observation.chassisYaw==0,"measurement timestamp and own pose captured at observation")
check(not pcall(function() result.distance=999 end) and not pcall(function() observation.timestamp=100 end),"observations and values are immutable")
local oldDistance=result.distance
source.state.position=Vector3.new(10,1,0); source.state.yaw=0.2; source.state.speed=-10; source.state.firing=true
local updated=assert(service:execute(source,45,1.2))
check(observation.value.distance==oldDistance and observation.origin.X==0,"moving/firing cannot mutate previous snapshot")
check(updated.origin.X==10 and updated.origin.Y==3.5 and updated.timestamp==1.2,"new measurement uses current authoritative pose while reversing/firing")
local rejected,reason=service:execute(source,45,1.21)
check(not rejected and reason=="sensorCooldown","reusing the same physical sensor is rate bounded")
check(world.overlaps==2 and world.casts<=Config.MaxRaycasts*2,"no background scans and bounded queries per observation")
check(service:execute(source,90,1.21)~=nil,"cooling sensor cannot block a different directional sensor")
check(not service:execute(source,50,1.22),"neighboring angles assigned to the same physical sensor share its cooldown")
source.state.health=0; check(not service:execute(source,45,2),"destroyed tank cannot scan")
service,source,add,world,parts,records=setup()
source.state.yaw=math.pi/2
add("north",Vector3.new(0,2.5,-40),Vector3.new(2,5,2),true)
result=assert(service:execute(source,90,1)).value
check(result.type=="tank" and near(result.distance,39) and near(result.relative_direction,90),"rotated chassis makes world north its right and reports chassis-relative bearing")
service,source,add,world,parts,records=setup()
add("edge",G.direction(0,9)*50+Vector3.new(0,2.5,0),Vector3.new(6,5,5),true,0.3)
result=assert(service:execute(source,0,1)).value
check(result.type=="tank" and result.relative_direction<=7.5+1e-6,"partial tank body detected with center outside cone, including rotated collision bounds")
service,source,add,world,parts,records=setup()
local far=add("far",Vector3.new(0,2.5,-60),nil,true)
local wall=add("wall",Vector3.new(0,3,-30),Vector3.new(20,6,2))
result=assert(service:execute(source,0,1)).value
check(result.type=="wall" and near(result.distance,29) and result.player==Values.Null and result.relation==Values.Null,"wall blocks hidden tank and returns its visible surface")
local nearTank=add("near",Vector3.new(0,2.5,-20),nil,true)
result=assert(service:execute(source,0,1.2)).value
check(result.type=="tank" and result.player=="near.Boomer#near" and near(result.distance,17),"near tank blocks farther objects in same cone")
local before=result.distance
table.clear(parts); table.insert(parts,nearTank); table.insert(parts,wall); table.insert(parts,far); table.insert(parts,source.hitbox)
check(assert(service:execute(source,0,1.4)).value.distance==before,"nearest result independent of part iteration order")
source.teamId="blue"; records[nearTank].teamId="blue"
check(assert(service:execute(source,0,1.6)).value.relation=="teammate","explicit shared team relationship recognized")
records[nearTank].playerName=nil
check(assert(service:execute(source,0,1.8)).value.player=="AI.Boomer#near","unowned tank uses stable identifier")
nearTank.CanQuery=false; wall.CanQuery=false
check(assert(service:execute(source,0,2)).value.player=="far.Boomer#far","non-solid wreck/dead cover does not block scanning")
service,source,add,world,parts,records=setup()
local cosmetic=add("smoke",Vector3.new(0,2.5,-5),Vector3.new(9,5,9)); cosmetic.CanQuery=false
-- A projectile not in the authoritative geometry allowlist cannot be queried.
local projectile=part("shell",Vector3.new(0,2.5,-10),Vector3.new(2,2,2)); projectile.CanQuery=true
result=assert(service:execute(source,0,1)).value
check(result.status=="success" and result.type==Values.Null and result.point==Values.Null,"empty scan ignores self, cosmetic volumes and out-of-allowlist projectiles")
service,source,add,world,parts,records=setup()
add("limit",Vector3.new(0,2.5,-151),Vector3.new(2,5,2))
check(near(assert(service:execute(source,0,1)).value.distance,150),"visible surface at maximum range detected")
check(assert(service:execute(source,180,1.2)).value.type==Values.Null,"opposite scan has no result")
service,source,add,world,parts,records=setup()
add("round",G.direction(0,10)*50+Vector3.new(0,2.5,0),Vector3.new(4.2,4.2,4.2),false,0,Enum.PartType.Ball)
check(assert(service:execute(source,0,1)).value.type==Values.Null,"bounds clipping never invents visibility through empty corners of curved cover")
service,source,add,world,parts,records=setup()
source.state.position=Vector3.new(0,6,0)
add("ground",Vector3.new(0,2.5,-40),nil,true)
result=assert(service:execute(source,0,1)).value
check(result.type=="tank" and result.distance>37,"horizontal scan cone uses true 3D surface distance and LOS while airborne")
service,source,add,world,parts,records=setup()
add("round-visible",G.direction(0,9)*50+Vector3.new(0,2.5,0),Vector3.new(4.2,4.2,4.2),false,0,Enum.PartType.Ball)
local rounded=assert(service:execute(source,0,1)).value
local delta=math.rad(1.5)
local expectedSurface=50*math.cos(delta)-math.sqrt(2.1^2-(50*math.sin(delta))^2)
check(rounded.type=="wall" and near(rounded.distance,expectedSurface,0.01),"partially visible rounded cover reports actual curved surface near cone edge")
-- Global and scene budgets reject requests rather than inventing an empty reading.
service,source,add,world,parts,records=setup()
for _=1,Config.ServerBurst do
 local independent={state=Sim.new(Vector3.zero),hitbox=source.hitbox}
 check(service:execute(independent,0,1)~=nil,"initial global scanner token")
end
local exhausted,reason=service:execute({state=Sim.new(Vector3.zero),hitbox=source.hitbox},0,1)
check(not exhausted and reason=="scannerBusy","server-wide scanner throughput bounded across independent tanks")
service,source,add,world,parts,records=setup()
for i=1,Config.MaxSpatialParts do add("crowded"..i,Vector3.new(0,2.5,-30),Vector3.new(1,1,1)) end
-- Include one extra object beyond the spatial cap (own body is excluded).
add("overflow",Vector3.new(0,2.5,-31),Vector3.new(1,1,1))
local overflow,why=service:execute(source,0,1)
check(not overflow and why=="scannerBusy","crowded scenes fail explicitly rather than leaking a false visibility claim")
-- Human-readable identifiers remain unique with multiple same-type tanks.
do
 local first={playerName="pilot",state=Sim.new(Vector3.zero,"Rattler"),id="tank-17"}
 local second={playerName="pilot",state=Sim.new(Vector3.zero,"Rattler"),id="tank-18"}
 local identity=Scanner.identity(first)
 check(identity=="pilot.Rattler#tank-17" and identity~=Scanner.identity(second),"same player can own distinguishable tanks with identical names/types")
 first.state=Sim.new(Vector3.new(30,0,0),"Rattler")
 check(Scanner.identity(first)==identity,"identity survives tank reset/movement")
 first.tankName="TinyTerror"
 check(Scanner.identity(first)=="pilot.TinyTerror#tank-17","optional instance tank name keeps stable unique suffix")
 first.playerName=nil
 check(Scanner.identity(first)=="AI.TinyTerror#tank-17","unowned tanks retain readable name and stable identity")
end
-- Manual sensors keep independent timers and cover their local 45-degree arcs.
do
 local Manual=require("ManualScanner")
 local service,source,add,world=setup()
 local time,angles=0,{}
 local function scan(angle) return service:execute(source,angle,time) end
 local function publish(angle,reading)
  table.insert(angles,angle)
  Manual.record(source,angle,{angle=angle,kind="none",proximity=0,remaining=Config.ManualVisualDuration,serial=#angles})
 end
 Manual.step(source,false,time,1/60,scan,publish)
 check(world.overlaps==0 and not source.state.manualScannerActive,"unselected/BW-controlled tank never auto-scans")
 for i=0,2 do
  time=i*Config.ManualSensorInterval
  Manual.step(source,true,time,if i==0 then 0 else Config.ManualSensorInterval-0.01,scan,publish)
  Manual.step(source,true,time+0.01,0.01,scan,publish)
 end
 local directions={}; for _,angle in angles do directions[angle]=true end
 check(#angles==24 and source.manualSensors[1].phase==0,"each sensor scans all three local sub-cones independently")
 for angle=0,345,15 do check(directions[angle],"independent sensors collectively cover complete circle without cone gaps") end
 check(world.overlaps==24,"each sensor respects its own automatic interval")
 local entries=0; for _ in source.state.scanManual do entries+=1 end
 check(entries==8,"manual reaction replication stays bounded to eight physical indicators")
 Manual.record(source,0,{angle=0,kind="tank",affiliation="enemy",proximity=1,remaining=3,serial=100})
 Manual.record(source,15,{angle=15,kind="none",proximity=0,remaining=3,serial=101})
 check(source.state.scanManual["1"].kind=="tank","neighboring empty cone does not erase recent enemy warning")
 Manual.record(source,0,{angle=0,kind="none",proximity=0,remaining=3,serial=102})
 check(source.state.scanManual["1"].kind=="none","rescan of original cone clears an enemy that is no longer visible")
 local before=#angles
 source.manualSensors[1].nextTime=time+Config.ManualSensorInterval*3
 time+=Config.ManualSensorInterval
 Manual.step(source,true,time,Config.ManualSensorInterval,scan,publish)
 check(#angles==before+7,"one sensor cooling down never blocks the other seven")
 Manual.step(source,false,time+0.02,1/60,scan,publish)
 check(source.state.scanManual==nil and not source.state.manualScannerActive and world.overlaps==31,"switching to BW/unselecting clears manual reactions without any free query")
 source.state.health=0
 Manual.step(source,true,time+1,1/60,scan,publish)
 check(world.overlaps==31 and not source.state.manualScannerActive,"destroyed tank cannot run automatic scans")
 source.state.health=100; source.manualSensors=nil
 local before=#angles
 Manual.step(source,true,time+2,1/60,function() return nil,"busy" end,publish)
 check(#angles==before and source.manualSensors[1].phase==1,"busy sensor does not fabricate readings or freeze neighboring channels")
end
-- All eight channels can be invoked at the same timestamp; wraparound cannot
-- create a ninth channel and circumvent a particular sensor's cooldown.
do
 local scanner,source=setup()
 for i=0,7 do check(scanner:execute(source,i*45,1)~=nil,"independent directional channel available immediately") end
 check(not scanner:execute(source,360,1.01),"normalized zero aliases same sensor cooldown")
 check(scanner:execute(source,0,1+Config.SensorCooldown)~=nil,"sensor resumes at its own cooldown deadline")
end
-- Runtime values are separate from public status text, and scanning is explicit.
local runtimeState=Sim.new(Vector3.zero)
local calls,charged,emitted=0,0,{}
local frozen=Values.observation(Values.scan("tank",58,39.6,"player3","enemy"),12.75,Vector3.zero,0)
local runtime=Runtime.new(assert(Parser.parse("Scanner(45)\nforward(1)")),runtimeState,{
 scan=function(angle) calls+=1; check(angle==45,"exactly requested direction supplied once"); return frozen end,
 chargeCycles=function(cost) charged+=cost end,
 onValue=function(value,line) table.insert(emitted,{value=value,line=line}) end})
runtime:step(runtimeState,1/60)
check(calls==1 and runtime.index==2 and runtime.lastValue==frozen.value and runtime.lastObservation.timestamp==12.75,"Scanner executes once and returns structured immutable runtime value")
check(runtime.results[1]==frozen and emitted[1].line==1 and charged==Config.ScannerCost and runtime.cyclesSpent==Config.ScannerCost,"result history/timestamp and configurable cycle-charge integration")
for _=1,10 do runtime:step(runtimeState,1/60) end
check(calls==1,"movement ticks do not refresh scanner result")
local canceled=Runtime.new(assert(Parser.parse("Scanner(0)")),runtimeState,{scan=function() calls+=1; return frozen end})
canceled:stop(); canceled:step(runtimeState,1/60)
check(calls==1,"Stop before instruction cancels scan without querying")
local missing=Runtime.new(assert(Parser.parse("Scanner(0, best_effort=false)")),runtimeState)
missing:step(runtimeState,1/60)
check(missing.status=="error" and missing.message:find("Scanner",1,true),"scanner failures use line-numbered strict runtime errors")
local skipped=Runtime.new(assert(Parser.parse("Scanner(0)\nfire()")),runtimeState,{scan=function() return nil,"Scanner busy" end})
skipped:step(runtimeState,1/60)
check(skipped.index==2 and skipped.skipped==1,"best-effort handles bounded query rejection without false empty readings")
local destroyed=Runtime.new(assert(Parser.parse("Scanner(0)")),runtimeState,{scan=function() calls+=1; return frozen end})
runtimeState.health=0; destroyed:step(runtimeState,1/60)
check(calls==1 and destroyed.status=="stopped","destruction cancels not-yet-executed scanner instruction")
local IDE=require("BWIDE")
local ui=IDE.new(Instance.new("PlayerGui"),function() return 3 end,function() return 2 end)
ui:bind("own")
ui:receiveScan("own",0,1,{timestamp=12.75,text=Values.format(frozen.value),line=1})
ui:update({generation=0,bwRequestId=1,bwStatus="completed",tankType="Boomer"})
check(ui.output.Text:find('["tank", 58',1,true) and ui.output.Text:find('t=12.750',1,true),"standalone scanner result and measurement timestamp shown privately in IDE")
ui:receiveScan("own",0,1,{timestamp=12.9,text='["wall", 22, 90, null, null]',line=2})
ui:receiveScan("own",0,1,{timestamp=13.1,text='[null, null, null, null, null]',line=3})
ui:update({generation=0,bwRequestId=2,bwRunRequestId=1,bwStatus="stopped",tankType="Boomer"})
local printed=ui.output.Text
check(printed:find('"player3"',1,true)<printed:find('"wall"',1,true) and printed:find('"wall"',1,true)<printed:find('[null, null, null, null, null]',1,true),"tank, wall and empty readings all remain in chronological order after Stop")
for i=4,require("BWConfig").MaxInstructions do ui:receiveScan("own",0,1,{timestamp=13+i,text='["wall", '..i..', 0, null, null]',line=i}) end
ui:update({generation=0,bwRequestId=2,bwRunRequestId=1,bwStatus="stopped",tankType="Boomer"})
check(#ui.scanOutputs.own.readings==128 and ui.scanOutputs.own.text:find('"player3"',1,true) and ui.output.Text:find('"wall", 128',1,true),"full retained history survives while latest page shows recent scans")
check(ui.outputScroll.CanvasSize.Y.Offset>ui.outputScroll.AbsoluteSize.Y and ui.outputScroll.CanvasPosition.Y>0 and not ui.output.TextWrapped,"history scrolls vertically/horizontally and follows new results at bottom")
ui.outputScroll.CanvasPosition=Vector2.new(0,40)
ui:update({generation=0,bwRequestId=2,bwRunRequestId=1,bwStatus="stopped",bwMessage="Stopped by player.",tankType="Boomer"})
check(ui.outputScroll.CanvasPosition.Y==40,"status updates do not pull reader away from older results")
ui.run.Activated:Fire()
check(ui.scanOutputs.own==nil,"new Run clears previous run's scan history")
ui:receiveScan("own",0,1,{timestamp=14,text=Values.format(frozen.value),line=1})
check(ui.scanOutputs.own==nil,"late previous-run output cannot repopulate new history")
ui:receiveScan("own",0,3,{timestamp=15,text='["wall", 10, 0, null, null]',line=1})
ui:update({generation=0,bwRequestId=3,bwRunRequestId=3,bwStatus="completed",tankType="Boomer"})
check(ui.output.Text:find('"wall", 10',1,true) and not ui.output.Text:find('"player3"',1,true),"new run starts its own independent output log")
ui:bind("other"); ui:update({generation=0,bwRequestId=1,bwStatus="idle"})
check(not ui.output.Text:find("player3",1,true),"other tank editor never shows first tank's observation")
ui:bind("own"); ui:update({generation=1,bwRequestId=1,bwStatus="stopped"})
check(ui.scanOutputs.own==nil and not ui.output.Text:find("player3",1,true),"battle reset clears old generation's private scan output")
ui:destroy()
-- A single cone reports every visible object, rather than pruning behind its nearest surface.
do
 local service,source,add,world,parts,records=setup()
 add("left",G.direction(0,-5)*40+Vector3.new(0,2.5,0),Vector3.new(1,3,1),true)
 add("right",G.direction(0,5)*70+Vector3.new(0,2.5,0),Vector3.new(1,3,1),true)
 add("cover",Vector3.new(0,2.5,-55),Vector3.new(1,3,1))
 local scan=assert(service:execute(source,0,1)).value
 check(scan.count==3 and #scan.detections==3 and scan.range==150,"all separate visible tanks/walls returned at full range")
 check(scan.detections[1].player=="left.Boomer#left" and scan.detections[2].type=="wall" and scan.detections[3].player=="right.Boomer#right","detections nearest-first regardless of object type")
 check(scan.detections[1].distance==scan.distance and scan.detections[1].relative_direction==scan.relative_direction,"nearest convenience fields retained")
 check(not pcall(function() scan.detections[1].distance=0 end) and not pcall(function() scan.detections[1]=scan end),"list and individual detections immutable")
 check(not pcall(function() scan.detections[1].point.x=0 end),"nested observed points immutable")
 local before=scan.detections[3].distance
 local reversed={}; for index=#parts,1,-1 do table.insert(reversed,parts[index]) end; table.clear(parts); for _,p in reversed do table.insert(parts,p) end
 local again=assert(service:execute(source,0,1.2)).value
 check(again.count==3 and again.detections[3].distance==before,"multi-hit order independent of scene iteration")
end
do
 local service,source,add=setup()
 add("cover",Vector3.new(0,2.5,-25),Vector3.new(20,10,2))
 add("hidden",Vector3.new(0,2.5,-45),Vector3.new(2,3,2),true)
 local scan=assert(service:execute(source,0,1)).value
 check(scan.count==1 and scan.detections[1].type=="wall","all-object scan never reveals fully occluded tanks")
end
do
 local service,source,add=setup()
 add("far",Vector3.new(0,2.5,-201),Vector3.new(2,3,2),true)
 check(assert(service:execute(source,0,1)).value.count==0,"default range is 150")
 local upgraded=assert(service:execute(source,0,1.2,{range=250,distancePercent=100})).value
 check(upgraded.count==1 and upgraded.range==250 and upgraded.distance>150,"hardware range extends both probes and actual ray queries")
 local reduced=assert(service:execute(source,0,1.4,{range=250,distancePercent=50})).value
 check(reduced.count==0 and reduced.range==125,"future distance effectiveness applied independently of bus performance")
 check(not service:execute(source,0,1.6,{range=0/0}) and not service:execute(source,0,1.6,{range=150,distancePercent=101}),"invalid hardware distance rejected")
 local empty=assert(service:execute(source,180,1.8)).value
 check(empty.status=="success" and empty.count==0 and Values.isArray(empty.detections),"empty scan returns an empty list successfully")
end
-- Compass bearings use the observed surface and acquisition pose, not a cursor
-- or the requested sensor centerline. The renamed keys are present everywhere.
do
 for _,heading in {0,90,180,270,350} do
  local service,source,add=setup()
  source.state.yaw=-math.rad(heading)
  add("hit",G.direction(source.state.yaw,45)*60+Vector3.new(0,2.5,0),Vector3.new(2,4,2),true)
  local observation=assert(service:execute(source,45,1))
  local result=observation.value; local hit=result.detections[1]
  check(result.count==1 and result.direction==nil and hit.direction==nil,"old direction key removed from snapshot and detection")
  local delta=Vector3.new(hit.point.x,hit.point.y,hit.point.z)-observation.origin
  check(near(hit.world_direction,G.worldBearing(delta)) and near(hit.relative_direction,G.bearing(source.state.yaw,delta)),"each bearing calculated from same observed point")
  check(near((hit.world_direction-hit.relative_direction-heading+180)%360-180,0),"world bearing includes chassis compass rotation")
  check(result.world_direction==hit.world_direction and result.relative_direction==hit.relative_direction,"nearest convenience bearings match first detection")
  check(hit.world_direction>=0 and hit.world_direction<360 and hit.relative_direction>=0 and hit.relative_direction<360,"both bearings normalized")
  local frozen=result.world_direction; source.state.yaw+=1; source.state.position=Vector3.new(10,3,8)
  check(result.world_direction==frozen and observation.chassisYaw==-math.rad(heading),"snapshot bearings and acquisition orientation remain immutable")
 end
 local service,source=setup()
 local empty=assert(service:execute(source,0,1)).value
 check(empty.relative_direction==Values.Null and empty.world_direction==Values.Null and empty.direction==nil,"empty scan has null named bearings and no old alias")
 for _,sample in {{Vector3.new(0,0,-1),0},{Vector3.new(1,0,0),90},{Vector3.new(0,0,1),180},{Vector3.new(-1,0,0),270}} do
  check(near(G.worldBearing(sample[1]),sample[2]),"world bearings match compass cardinal directions")
 end
end
-- End-to-end: an actual acquired surface bearing feeds the existing absolute
-- turret command directly on both tank types; no chassis-offset math in BW.
do
 local Concurrent=require("BWExecution"); local Hardware=require("BWChassis"); local Adapter=require("BWTankAdapter")
 for _,kind in {"Boomer","Rattler"} do
  local service,source,add=setup()
  local state=source.state; state.tankType=kind; state.yaw=-math.pi/2; state.turretYaw=0
  add("enemy",Vector3.new(40,2.5,2),Vector3.new(2,4,2),true)
  local config=Hardware.forTank(kind)
  state.turretPerformance=Hardware.performance(config.devices.turret.allocation)
  local program=assert(Parser.parse('facing = get_facing_direction()\nscan = Scanner(position=0)\nif scan.status == "success" and scan.count > 0:\n    aim = turret_right(to=scan.detections[0].world_direction)'))
  local runtime=Concurrent.new(program,state,{scan=function(angle,performance,time,hardware) return service:execute(source,angle,time,hardware) end},config)
  for _=1,420 do local input=runtime:step(state,1/60); Sim.step(state,input,1/60); if runtime.status~="running" then break end end
  check(runtime.status=="completed" and near(runtime.variables.facing.world_direction,90),"facing getter uses chassis orientation on "..kind)
  local target=runtime.variables.scan.detections[1]
  local actual=Adapter.heading(Adapter.angle(state,true))
  check(math.abs((actual-target.world_direction+180)%360-180)<=0.81,"scan world bearing directly aims existing turret on "..kind)
  check(math.abs(target.relative_direction)<7.5 and target.world_direction>80,"relative and world headings remain distinct on "..kind)
 end
end
-- The user's exact threaded scan guards print when a close opponent's body
-- intersects any cone; sensor mounting direction is not a shared cooldown.
do
 local Concurrent=require("BWExecution"); local Hardware=require("BWChassis")
 local blocks={}
 for position=0,7 do table.insert(blocks,string.format('with thread(%d):\n    while true:\n        scan%d = Scanner(position=%d)\n        if scan%d.status == "success" and scan%d.count > 0:\n            print(scan%d.detections[0])',position+1,position,position,position,position,position)) end
 local instructions=assert(Parser.parse(table.concat(blocks,"\n\n")))
 for _,bearing in {0,22.5,90,180,270,337.5} do
  local service,source,add=setup(); source.state.tankType="Rattler"
  add("adjacent",G.direction(0,bearing)*12+Vector3.new(0,2.5,0),Vector3.new(8,5,10),true)
  local prints=0
  local runtime=Concurrent.new(instructions,source.state,{scan=function(angle,performance,time,hardware) return service:execute(source,angle,time,hardware) end,onPrint=function() prints+=1 end},Hardware.forTank("Rattler"))
  for _=1,90 do runtime:step(source.state,1/60) end
  check(runtime.status=="running" and prints>0,"close tank is detected and explicitly printed at bearing "..bearing)
 end
 -- Fixed 15-degree cones intentionally leave gaps between their 45-degree mounts.
 local service,source,add=setup()
 add("between-cones",G.direction(0,22.5)*40+Vector3.new(0,2.5,0),Vector3.new(2,4,2),true)
 for position=0,7 do check(assert(service:execute(source,position*45,1)).value.count==0,"empty scan between narrow cones is not a cooldown failure") end
end
print(string.format("Directional scanner/value/runtime suite passed: %d assertions",count))

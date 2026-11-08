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
for _,source in {"Scanner(-721.5)","Scanner(-1e-300)","Scanner(1e3)","Scanner(1e300)","Scanner(.25, best_effort=false)"} do
 local parsed=assert(Parser.parse(source)); check(parsed[1].value>=0 and parsed[1].value<360,"finite scanner literals normalized without movement-angle limit")
end
for _,source in {"scanner(45)","Scanner()","Scanner(to=0)","Scanner(1e999)","Scanner(0/0)","Scanner(1,2)","Scanner(1, best_effort=1)"} do
 local p,e=Parser.parse("# test\n"..source); check(not p and e.line==2,"invalid scanner syntax has source line")
end
local service,source,add,world,parts,records=setup()
local target=add("player3",G.direction(0,39.6)*58+Vector3.new(0,2.5,0),Vector3.new(1,5,1),true)
local observation=assert(service:execute(source,45,1))
local result=observation.value
check(#result==5 and Values.get(result,0)=="tank" and result[4]=="player3.Boomer#player3" and result[5]=="enemy","five-element structured tank observation and logical zero indexing")
check(result[2]>57 and result[2]<58 and result[3]>39 and result[3]<40,"actual surface bearing/range differ from requested 45 degrees")
check(observation.timestamp==1 and observation.origin.Y==2.5 and observation.chassisYaw==0,"measurement timestamp and own pose captured at observation")
check(not pcall(function() result[2]=999 end) and not pcall(function() observation.timestamp=100 end),"observations and values are immutable")
local oldDistance=result[2]
source.state.position=Vector3.new(10,1,0); source.state.yaw=0.2; source.state.speed=-10; source.state.firing=true
local updated=assert(service:execute(source,45,1.2))
check(observation.value[2]==oldDistance and observation.origin.X==0,"moving/firing cannot mutate previous snapshot")
check(updated.origin.X==10 and updated.origin.Y==3.5 and updated.timestamp==1.2,"new measurement uses current authoritative pose while reversing/firing")
local rejected,reason=service:execute(source,45,1.21)
check(not rejected and reason:find("rate limit",1,true),"reusing the same physical sensor is rate bounded")
check(world.overlaps==2 and world.casts<=Config.MaxRaycasts*2,"no background scans and bounded queries per observation")
check(service:execute(source,90,1.21)~=nil,"cooling sensor cannot block a different directional sensor")
check(not service:execute(source,50,1.22),"neighboring angles assigned to the same physical sensor share its cooldown")
source.state.health=0; check(not service:execute(source,45,2),"destroyed tank cannot scan")
service,source,add,world,parts,records=setup()
source.state.yaw=math.pi/2
add("north",Vector3.new(0,2.5,-40),Vector3.new(2,5,2),true)
result=assert(service:execute(source,90,1)).value
check(result[1]=="tank" and near(result[2],39) and near(result[3],90),"rotated chassis makes world north its right and reports chassis-relative bearing")
service,source,add,world,parts,records=setup()
add("edge",G.direction(0,9)*50+Vector3.new(0,2.5,0),Vector3.new(6,5,5),true,0.3)
result=assert(service:execute(source,0,1)).value
check(result[1]=="tank" and result[3]<=7.5+1e-6,"partial tank body detected with center outside cone, including rotated collision bounds")
service,source,add,world,parts,records=setup()
local far=add("far",Vector3.new(0,2.5,-60),nil,true)
local wall=add("wall",Vector3.new(0,3,-30),Vector3.new(20,6,2))
result=assert(service:execute(source,0,1)).value
check(result[1]=="wall" and near(result[2],29) and result[4]==Values.Null and result[5]==Values.Null,"wall blocks hidden tank and returns its visible surface")
local nearTank=add("near",Vector3.new(0,2.5,-20),nil,true)
result=assert(service:execute(source,0,1.2)).value
check(result[1]=="tank" and result[4]=="near.Boomer#near" and near(result[2],17),"near tank blocks farther objects in same cone")
local before=Values.format(result)
table.clear(parts); table.insert(parts,nearTank); table.insert(parts,wall); table.insert(parts,far); table.insert(parts,source.hitbox)
check(Values.format(assert(service:execute(source,0,1.4)).value)==before,"nearest result independent of part iteration order")
source.teamId="blue"; records[nearTank].teamId="blue"
check(assert(service:execute(source,0,1.6)).value[5]=="teammate","explicit shared team relationship recognized")
records[nearTank].playerName=nil
check(assert(service:execute(source,0,1.8)).value[4]=="AI.Boomer#near","unowned tank uses stable identifier")
nearTank.CanQuery=false; wall.CanQuery=false
check(assert(service:execute(source,0,2)).value[4]=="far.Boomer#far","non-solid wreck/dead cover does not block scanning")
service,source,add,world,parts,records=setup()
local cosmetic=add("smoke",Vector3.new(0,2.5,-5),Vector3.new(9,5,9)); cosmetic.CanQuery=false
-- A projectile not in the authoritative geometry allowlist cannot be queried.
local projectile=part("shell",Vector3.new(0,2.5,-10),Vector3.new(2,2,2)); projectile.CanQuery=true
result=assert(service:execute(source,0,1)).value
check(Values.format(result)=="[null, null, null, null, null]" and #result==5,"empty scan ignores self, cosmetic volumes and out-of-allowlist projectiles")
service,source,add,world,parts,records=setup()
add("limit",Vector3.new(0,2.5,-151),Vector3.new(2,5,2))
check(near(assert(service:execute(source,0,1)).value[2],150),"visible surface at maximum range detected")
check(Values.format(assert(service:execute(source,180,1.2)).value)=="[null, null, null, null, null]","opposite scan has no result")
service,source,add,world,parts,records=setup()
add("round",G.direction(0,10)*50+Vector3.new(0,2.5,0),Vector3.new(4.2,4.2,4.2),false,0,Enum.PartType.Ball)
check(assert(service:execute(source,0,1)).value[1]==Values.Null,"bounds clipping never invents visibility through empty corners of curved cover")
service,source,add,world,parts,records=setup()
source.state.position=Vector3.new(0,6,0)
add("ground",Vector3.new(0,2.5,-40),nil,true)
result=assert(service:execute(source,0,1)).value
check(result[1]=="tank" and result[2]>37,"horizontal scan cone uses true 3D surface distance and LOS while airborne")
service,source,add,world,parts,records=setup()
add("round-visible",G.direction(0,9)*50+Vector3.new(0,2.5,0),Vector3.new(4.2,4.2,4.2),false,0,Enum.PartType.Ball)
local rounded=assert(service:execute(source,0,1)).value
local delta=math.rad(1.5)
local expectedSurface=50*math.cos(delta)-math.sqrt(2.1^2-(50*math.sin(delta))^2)
check(rounded[1]=="wall" and near(rounded[2],expectedSurface,0.01),"partially visible rounded cover reports actual curved surface near cone edge")
-- Global and scene budgets reject requests rather than inventing an empty reading.
service,source,add,world,parts,records=setup()
for _=1,Config.ServerBurst do
 local independent={state=Sim.new(Vector3.zero),hitbox=source.hitbox}
 check(service:execute(independent,0,1)~=nil,"initial global scanner token")
end
local exhausted,reason=service:execute({state=Sim.new(Vector3.zero),hitbox=source.hitbox},0,1)
check(not exhausted and reason:find("budget",1,true),"server-wide scanner throughput bounded across independent tanks")
service,source,add,world,parts,records=setup()
for i=1,Config.MaxSpatialParts do add("crowded"..i,Vector3.new(0,2.5,-30),Vector3.new(1,1,1)) end
-- Include one extra object beyond the spatial cap (own body is excluded).
add("overflow",Vector3.new(0,2.5,-31),Vector3.new(1,1,1))
local overflow,why=service:execute(source,0,1)
check(not overflow and why:find("budget",1,true),"crowded scenes fail explicitly rather than leaking a false visibility claim")
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
check(#ui.scanOutputs.own.readings==128 and ui.output.Text:find('"player3"',1,true) and ui.output.Text:find('"wall", 128',1,true),"all possible scans in a bounded 128-instruction program are retained")
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
print(string.format("Directional scanner/value/runtime suite passed: %d assertions",count))

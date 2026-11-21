local Scanner=require("DirectionalScanner")
local Sim=require("TankSimulation")
local Config=require("ScannerConfig")
local Components=require("VehicleComponents")
local Value=require("BWValue")
local Parser=require("BWParser")
local VM=require("BWExecution")
local Hardware=require("BWChassis")
local count=0
local function check(ok,m)count+=1;assert(ok,m)end
local function near(a,b)return type(a)=="number"and math.abs(a-b)<.001 end
local function plane(y,z0,z1,slope,width,water)
 local p=Instance.new("Part");p.CanQuery=true;p.Size=Vector3.new(width or 100,1,200);p.CFrame=CFrame.new(0,y,0)
 p.Material=Enum.Material.Grass
 if water then p:SetAttribute("ScannerSurface","Water")end
 return {part=p,y=y,z0=z0 or -200,z1=z1 or 200,slope=slope or 0,width=width or 100}
end
local function fixture(planes,options)
 options=options or{};local rays=0
 local world={}
 function world:GetPartBoundsInRadius()return{}end
 function world:Raycast(origin,delta,params)
  rays+=1;local nearest=2;local found
  for _,p in planes do
   local divisor=delta.Y-p.slope*delta.Z
   if table.find(params.FilterDescendantsInstances,p.part) and math.abs(divisor)>1e-8 then
    local t=(p.y+p.slope*origin.Z-origin.Y)/divisor
    local hit=origin+delta*t
    if t>=-1e-8 and t<=1+1e-8 and t<nearest and hit.Z>=p.z0 and hit.Z<=p.z1 and math.abs(hit.X)<=p.width/2 then
     nearest=t;found={Instance=p.part,Position=hit,Normal=Vector3.new(0,1,-p.slope).Unit,Material=p.part.Material}
    end
   end
  end
  return found
 end
 local state=Sim.new(Vector3.new(0,options.height or 0,0),"Boomer")
 if options.noGround or options.noSensors then
  local assembly=Components.copy(require("VehicleAssemblies").Boomer)
  if options.noSensors then assembly.Sensors={} else
   local profile=Components.resolve(assembly);profile=table.clone(profile);profile.Sensors=table.clone(profile.Sensors)
   for angle,s in profile.Sensors do local copy=table.clone(s);copy.GroundObservations=false;profile.Sensors[angle]=copy end
   Components.bind(state,profile)
  end
  if options.noSensors then Components.bind(state,Components.resolve(assembly))end
 end
 local tank={state=state,id="own"}
 local parts={};for _,p in planes do table.insert(parts,p.part)end
 local scene
 if options.cached then
  local arena=Instance.new("Folder");arena.children=parts
  for _,part in parts do part:SetAttribute("ScannerTerrainOnly",true) end
  function world:FindFirstChild() return nil end
  scene=require("ScannerScene").new(arena,world,{CanQuery=false},{},{})
 end
 local scanner=Scanner.new(world,function()
  if scene then return scene:read() end
  return {},{},parts
 end)
 local function scan(angle,hardware,time)
  return scanner:execute(tank,angle or 0,time or 10,hardware or{coneWidth=90})
 end
 return scan,scanner,tank,function()return rays end
end
local scan,scanner,tank,rays=fixture({plane(0)})
local observed=assert(scan());local ground=observed.value.terrain
check(observed.value.count==0 and observed.value.type==Value.Null and ground.supported,"old detections preserved, additive terrain enabled by actual equipment")
check(ground.continuity=="sampled"and ground.distance_to_edge==Value.Null,"flat sampled ground is not mislabeled a cliff")
check(ground.count>8 and rays()<=Config.TerrainMaxRaycasts and scanner.lastRaycasts==rays(),"bounded footprint lanes and total query accounting")
for _,sample in ground.samples do
 check(sample.confidence=="observed"and sample.ground_detected and near(sample.elevation,0)and near(sample.relative_elevation_change,0),"flat physical elevations")
 check(near(sample.elevation_rate,0)and near(sample.slope_angle,0),"flat slope units")
end
check(table.isfrozen(ground)and table.isfrozen(ground.samples[1]),"terrain returns deeply immutable BW values")
local uncachedRamp=fixture({plane(0,-200,200,.25)})
local cachedRamp=fixture({plane(0,-200,200,.25)},{cached=true})
local expectedRamp=assert(uncachedRamp()).value.terrain
local actualRamp=assert(cachedRamp()).value.terrain
check(actualRamp.count==expectedRamp.count and actualRamp.continuity==expectedRamp.continuity,"cache preserves terrain sample count and continuity")
for i,expected in expectedRamp.samples do
 local actual=actualRamp.samples[i]
 check(actual.elevation==expected.elevation and actual.slope_angle==expected.slope_angle and actual.surface_type==expected.surface_type,"cached samples preserve elevation, slope, and material")
end
for _,slope in {-.25,.25}do
 local ramp=fixture({plane(0,-200,200,slope)})
 local record=assert(ramp()).value.terrain
 local found=false
 for _,sample in record.samples do if sample.confidence=="observed"then
  check(near(sample.elevation_rate,-slope)and near(sample.slope_angle,math.deg(math.atan(-slope))),"signed uphill/downhill local normal slope")
  check(near(sample.elevation,-sample.forward_distance*slope),"world elevation measured rather than smoothed")
  found=true
 end end
 check(found,"slope observable within vertical/range bounds")
end
local cliff=fixture({plane(0,-7,200),plane(-18)})
local edge=assert(cliff()).value.terrain
check(edge.continuity=="discontinuity"and edge.edge_near~=Value.Null and edge.edge_near<=7 and edge.edge_far>=7,"observable cliff bracket preserves abrupt edge")
check(edge.drop_depth==Value.Null,"hidden cliff depth not fabricated from column probe")
local gap=fixture({plane(0,-7,200),plane(0,-200,-12)})
local gapResult=assert(gap()).value.terrain
check(gapResult.edge_near~=Value.Null,"gap between adjacent platforms observed")
local steps=fixture({plane(0,-7,200),plane(2,-200,-7)})
local stepResult=assert(steps()).value.terrain
local abrupt=false
for _,s in stepResult.samples do if s.transition=="discontinuity"then
 check(s.interval_elevation_rate==Value.Null and near(s.elevation_rate,0),"abrupt steps preserve local flat slope and do not average across discontinuity")
 abrupt=true
end end
check(abrupt,"sharp elevation changes remain distinct observations")
local shallow=fixture({plane(0,-6.1,200),plane(-.6)})
local shallowResult=assert(shallow()).value.terrain
check(shallowResult.drop_depth~=Value.Null and near(shallowResult.drop_depth,.6),"visible shallow drop depth is measured where line of sight permits")
local raised=fixture({plane(10)},{height=10})
local bridge=assert(raised()).value.terrain
check(near(bridge.samples[1].elevation,10)and near(bridge.samples[1].relative_elevation_change,0),"elevated bridge uses physical top, not world-zero floor")
local narrow=fixture({plane(10,-200,200,0,4)},{height=10})
local narrowResult=assert(narrow()).value.terrain
local unknownSides=false;local center=false
for _,s in narrowResult.samples do
 if s.lane~=1 and s.ground_detected==Value.Null then unknownSides=true end
 if s.lane==1 and s.ground_detected==true then center=true end
end
check(center and unknownSides,"narrow bridge reports footprint lane uncertainty without declaring traversable")
local wet=fixture({plane(0,-200,200,0,100,true)})
local water=assert(wet()).value.terrain
check(water.samples[1].surface_type=="Water"and water.samples[1].ground_detected==false,"queryable water identified from explicit physical surface, not inferred from color")
local limited=fixture({plane(0)})
local small=assert(limited(0,{range=7,coneWidth=15})).value.terrain
for _,s in small.samples do check(s.horizontal_distance<=7 and s.lane==1,"short narrow cone cannot observe outside footprint lanes or actual range")end
local back=fixture({plane(0)})
local rear=assert(back(180)).value.terrain
check(rear.count>0,"existing chassis-relative rear mounting works")
local unsupported=fixture({plane(0)},{noGround=true})
check(assert(unsupported()).value.terrain.status=="unsupported","sensor without capability reports unsupported")
local missing=fixture({plane(0)},{noSensors=true})
local none,reason=missing();check(none==nil and reason=="deviceUnavailable","absent sensor retains existing failure")
local invalid=fixture({plane(0)})
check(invalid(0,{range=-1})==nil,"invalid sensor arguments retain safe validation")
check(require("BWChassis").Costs.Scanner==1 and not require("BWCommands").known("scan_ground"),"same Scanner CPU cost and no second language command")
local program=assert(Parser.parse('s = Scanner(0)\nif s.terrain.edge_near != null:\n    stop()\nelse:\n    forward()'))
local readCliff,_,source=fixture({plane(0,-7,200),plane(-18)})
local cfg=Hardware.forTank(source.state)
local calls=0
local vm=VM.new(program,source.state,{scan=function()calls+=1;return readCliff(0,{coneWidth=90},10+calls)end},cfg)
for _=1,180 do vm:step(source.state,1/60);if vm.status~="running"then break end end
check(vm.status=="completed"and not vm.devices:busy(),"ordinary BW program can react to observed edge with explicit stop")
local direct=Sim.new(Vector3.zero)
local input=require("InputCommand").neutral();input.throttle=1
for _=1,60 do Sim.step(direct,input,1/60)end
check(direct.position.Z< -7,"observation adds no invisible movement barrier or automatic steering")
local disabled=Hardware.copy(cfg);disabled.devices.sensor0.allocation=0
local off=VM.new(assert(Parser.parse('s = Scanner(0)')),source.state,{},disabled)
for _=1,60 do off:step(source.state,1/60)end
check(off.variables.s.reason=="deviceDisabled","zero scanner bus cannot acquire ground data")
local slopeConsumer=Parser.parse('function slope(const scan):\n    return scan.terrain.samples[0].slope_angle\ns = Scanner(0)\na = slope(s)')
check(slopeConsumer~=nil,"terrain scalar fields work through existing const/function type conventions")
local budgetScan,_,budgetTank=fixture({plane(0)})
local budgetCalls=0
local limitedWorld={Raycast=function()budgetCalls+=1;return nil end}
local record,used=require("ScannerTerrain").observe(limitedWorld,{}, {},budgetTank.state,0,150,90,Vector3.new(0,2.5,0),Components.get(budgetTank.state).Sensors[0],2)
check(used==2 and budgetCalls==2 and record.status=="partial_budget","terrain cannot exceed remaining shared ray budget")
local tinyStep=fixture({plane(0,-7,200),plane(.1,-200,-7)})
local tinyRecord=assert(tinyStep()).value.terrain
local smallDiscontinuity=false
for _,s in tinyRecord.samples do if s.transition=="discontinuity"then smallDiscontinuity=true;check(s.interval_elevation_rate==Value.Null,"small sharp step is not smoothed")end end
check(smallDiscontinuity,"no arbitrary half-stud smoothing threshold")
local env=require("Environment").create(Vector2.new(230,230))
env.rocks={};env.logs={};env.trees={};env.zones={};env.playground=require("PlaygroundTerrain").create(Vector2.new(230,230))
local unrestricted=Sim.new(Vector3.zero,"Boomer")
for _=1,130 do Sim.step(unrestricted,input,1/60,Vector2.new(230,230),env)end
check(unrestricted.position.Y< -27 and require("PlaygroundTerrain").hazard(env.playground,unrestricted.position),"existing footprint-aware Playground physics still permits genuine bridge falls")
local sphereOrigin=Vector3.new(0,2.5,0)
local clippedRays=0
local clippedWorld={Raycast=function(_,from,delta)
 clippedRays+=1
 check((from-sphereOrigin).Magnitude<=5.000001 and(from+delta-sphereOrigin).Magnitude<=5.000001,"internal terrain probes stay inside actual scanner range sphere")
 return nil
end}
require("ScannerTerrain").observe(clippedWorld,{}, {},budgetTank.state,0,5,90,sphereOrigin,Components.get(budgetTank.state).Sensors[0],64)
check(clippedRays>0,"short-range sampling remains bounded but operational")
local floorPart=Instance.new("Part");local thinWall=Instance.new("Part")
local candidate
local occludedWorld={Raycast=function(_,from,delta)
 if delta.X==0 and delta.Z==0 then
  candidate=Vector3.new(from.X,0,from.Z)
  return {Instance=floorPart,Position=candidate,Normal=Vector3.new(0,1,0),Material=Enum.Material.Grass}
 end
 return {Instance=thinWall,Position=candidate-delta.Unit*.001,Normal=Vector3.new(0,1,0),Material=Enum.Material.Grass}
end}
local concealed=require("ScannerTerrain").observe(occludedWorld,{floorPart,thinWall}, {},budgetTank.state,0,150,90,sphereOrigin,Components.get(budgetTank.state).Sensors[0],64)
check(concealed.samples[1].point==Value.Null and concealed.status=="unknown","even a thin foreground occluder cannot reveal a different hidden surface")
print("Scanner terrain/elevation passed: "..count.." assertions")

local Materials=require("TerrainMaterials")
local Surface=require("SurfacePhysics")
local E=require("Environment")
local T=require("PlaygroundTerrain")
local Sim=require("TankSimulation")
local C=require("VehicleComponents")
local Motion=require("VehicleMotion")
local Input=require("InputCommand")
local Hardware=require("BWChassis")
local Controller=require("BWController")
local Read=require("BWSelfState")
local count=0
local function check(ok,m)count+=1;assert(ok,m)end
local function near(a,b,epsilon)return math.abs(a-b)<(epsilon or .01)end
local function environment(profile)
 local env=E.create(T.ReferenceSize);T.configure(env,T.ReferenceSize)
 env.trees={};env.playground.staticBoxes={};env.playground.course=nil;env.playground.configurationZones=nil
 env.physicsSurfaces=Surface.prepare({{id="uniform",shape="box",x=0,z=0,rx=1000,rz=1000,surface=profile}})
 return env
end
local function tank(kind,position)
 local assembly=C.copy(require("VehicleAssemblies").Rattler)
 assembly.Mobility=if kind=="Tracked"then "mobility.tracks"else "mobility.wheels"
 return Sim.new(position or Vector3.new(150,0,0),"Rattler",13579,assembly)
end
local drive=Input.neutral();drive.throttle=1
local function run(kind,profile,seconds,extra)
 local state=tank(kind);if extra then extra(state)end
 local env=environment(profile)
 for _=1,seconds*60 do Sim.step(state,drive,1/60,T.ReferenceSize,env)end
 return state
end
for _,kind in {"Pavement","Dirt","Grass","Snow","Ice"}do
 local dry=Materials.profile(kind,0,.4,.8)
 local wet=Materials.profile(kind,1,.4,.8)
 check(wet.wheelSpeed<dry.wheelSpeed and wet.kineticFriction<dry.kineticFriction,"wet surface reduces speed/grip: "..kind)
 for _,mobility in {"Wheeled","Tracked"}do
  local a=run(mobility,dry,5);local b=run(mobility,wet,5)
  check(a.speed>b.speed and b.speed>0,"real drivetrain obeys dry/wet tuning: "..kind.." "..mobility)
 end
end
local grass=Materials.profile("Grass",0,0,1)
local wheels=run("Wheeled",grass,5)
local tracks=run("Tracked",grass,5)
check(near(tracks.speed/wheels.speed,.90,.0001),"approved tracked base speed multiplier exactly once on equivalent hardware")
check(C.get(tracks).Drivetrain.Speed==C.get(wheels).Drivetrain.Speed,"base rule does not corrupt nominal drivetrain equipment rating")
local mixed=Surface.prepare({{id="grass",shape="box",x=0,z=0,rx=1000,rz=1000,surface=grass}})
local _,_,_,_,blended=Surface.contact(mixed,Vector3.zero,0,C.get(tracks).Chassis,"Tracked")
check(blended==1,"footprint surface blending does not repeatedly apply tracked base")
for _,material in {"Snow","Mud"}do
 local shallow=Materials.profile(material,1,.2,.8)
 local deep=Materials.profile(material,1,1.5,.25)
 for _,mobility in {"Wheeled","Tracked"}do
  local a=run(mobility,shallow,5);local b=run(mobility,deep,5)
  check(a.speed>b.speed and b.speed>.1,"depth/softness penalizes without terrain-only immobilization: "..material..mobility)
 end
 check(deep.trackSpeed>deep.wheelSpeed,"tracks receive central soft-material benefit before base speed factor")
end
local low=tank("Tracked")
local cfg=Hardware.forTank(low);cfg.devices.drivetrain.allocation=20
local record={state=low,hardware=cfg};Controller.applyHardware(record)
local env=environment(grass)
for _=1,300 do Sim.step(low,drive,1/60,T.ReferenceSize,env)end
local limit=C.get(low).Drivetrain.Speed*Hardware.devicePerformance("drivetrain",20,C.get(low))*.9
check(near(low.speed,limit),"terrain never overrides/doubles existing bus-power constraint")
local snapshot=Read.read("get_tank_state",low,cfg,5,{})
check(near(snapshot.motion.ground_max_speed,limit)and near(snapshot.motion.terrain_speed_scale,.9),"own-state exposes last applied terrain scale separately from nominal bus limit")
check(near(snapshot.motion.effective_max_speed,C.get(low).Drivetrain.Speed*low.drivePerformance),"existing bus-limited field semantics preserved")
local disabled=run("Wheeled",grass,4,function(s)s.drivePerformance=0 end)
check(disabled.speed==0,"terrain floor cannot grant movement to unpowered drivetrain")
-- Legacy direct/Classic simulation unchanged by the opt-in rule.
local legacy=tank("Tracked")
for _=1,300 do Sim.step(legacy,drive,1/60,T.ReferenceSize)end
check(near(legacy.speed,C.get(legacy).Drivetrain.Speed),"Classic and old custom worlds retain existing movement baseline")
local function braking(profile)
 local state=tank("Wheeled");Motion.setVelocity(state,Vector3.new(0,0,-15))
 local env=environment(profile);local start=state.position.Z
 for _=1,360 do Sim.step(state,Input.neutral(),1/60,T.ReferenceSize,env)end
 return start-state.position.Z
end
check(braking(Materials.profile("Ice",1,0,1))>braking(Materials.profile("Pavement",0,0,1))*2,"traction consistently changes braking/sliding rather than teleport-clamping")
local function steering(profile)
 local state=tank("Wheeled");local command=Input.neutral();command.throttle=1;command.steer=.7
 local env=environment(profile)
 for _=1,180 do Sim.step(state,command,1/60,T.ReferenceSize,env)end
 return state
end
local road=steering(Materials.profile("Pavement",0,0,1));local ice=steering(Materials.profile("Ice",1,0,1))
check(math.abs(road.yaw)>math.abs(ice.yaw)and ice.motionSlipping,"steering uses actual traction budget and retains wheeled limitations")
for _,mobility in {"Wheeled","Tracked"}do
 local slope=tank(mobility,Vector3.new(-100,0,-32));local slopeEnv=environment(grass)
 for _=1,240 do Sim.step(slope,drive,1/60,T.ReferenceSize,slopeEnv)end
 check(slope.position.Y>5 and slope.position.Z< -60,"existing ramp driving works with terrain traction and base rule")
end
local minimum=Materials.profile("Mud",1,5,0)
for _,mobility in {"Wheeled","Tracked"}do
 local crawling=run(mobility,minimum,8)
 check(crawling.speed>0 and crawling.position.Z< -2,"worst supported solid material still permits powered progress")
end
for _,strip in T.create(T.ReferenceSize).strips do check(strip.rz*2==160 and strip.rx*2==22,"equal-length twin-vehicle comparison lanes")end
check(not pcall(Materials.profile,"Water",0,0,1),"water stays a separate hazard, never a traversable material profile")
for _,args in {{"Snow",-1,0,1},{"Mud",1,-1,.5},{"Grass",0,0,2}}do check(not pcall(Materials.profile,table.unpack(args)),"invalid terrain definitions rejected")end
for _,extra in {{wheelSpeed=0},{trackSpeed=2},{trackedStaticFriction=0/0}}do
 local bad=table.clone(Surface.Profiles.Normal)
 for k,v in extra do bad[k]=v end
 check(not pcall(Surface.prepare,{{id="bad",x=0,z=0,rx=1,rz=1,surface=bad}}),"new material fields validated at prepare time")
end
-- Exact curve anchors and actual powered movement, including fractional low bus.
for _,kind in {"Boomer","Rattler"}do
 local state=Sim.new(Vector3.new(150,0,0),kind);local vehicle=C.get(state)
 local previous=0
 for _,allocation in {0,1,2.5,5,9.09,25,50,75,100}do
  local p=Hardware.devicePerformance("drivetrain",allocation,vehicle)
  check(p>=previous and p<=1,"drivetrain curve is monotonic and capped at existing rating");previous=p
  if allocation==0 then check(p==0,"zero bus grants no propulsion")end
  if allocation==5 then check(near(p*vehicle.Drivetrain.Speed,15),"five percent gives15 rated forward studs/sec before terrain")end
  if allocation==100 then check(p==1,"full power keeps existing maximum")end
 end
 for _,name in {"turret","weapon","sensor0"}do
  check(Hardware.devicePerformance(name,5,vehicle)==Hardware.performance(5,vehicle.Bus),"other device curves are unchanged")
 end
 local record={state=state,hardware=Hardware.forTank(state)}
 record.hardware.devices.drivetrain.allocation=5;Controller.applyHardware(record)
 local env=environment(grass)
 for _=1,300 do Sim.step(state,drive,1/60,T.ReferenceSize,env)end
 check(near(state.speed,15*(if vehicle.Mobility.Kind=="Tracked"then .9 else 1)),"real drive obeys five-percent curve and single tracked terrain factor")
 local read=Read.read("get_tank_state",state,record.hardware,5,{})
 check(near(read.motion.effective_max_speed,15),"BW own-state reports exact physical bus limit")
 local vm=require("BWDevices").new(record.hardware,state,{})
 check(near(vm.devices.drivetrain.performance,state.drivePerformance),"AI command scheduling and actual movement share one curve")
end
-- Diagnose the shipped public configuration through actual production drive.
local Auto=require("PlaygroundAutonomy")
for _,kind in {"Boomer","Rattler"}do
 local state=Sim.new(Vector3.new(150,0,0),kind)
 local record={state=state,hitbox=Instance.new("Part")};Auto.attach(record,1,1)
 local config=C.get(state);local profile=Materials.profile("Grass",0,0,1)
 local env=environment(profile)
 for _=1,300 do Sim.step(state,drive,1/60,T.ReferenceSize,env)end
 local expected=config.Drivetrain.Speed*Hardware.devicePerformance("drivetrain",record.hardware.devices.drivetrain.allocation,config)*(if config.Mobility.Kind=="Tracked"then .9 else 1)
 check(near(state.speed,expected),"actual public speed matches bus and terrain factors, independent of tank population")
 check(near(state.terrainSpeedScale,if config.Mobility.Kind=="Tracked"then .9 else 1),"dry grass has no hidden terrain speed penalty")
 print(string.format("Public movement diagnostic: %s bus %.2f%% -> %.3f studs/sec (rated %.1f)",kind,record.hardware.devices.drivetrain.allocation,state.speed,config.Drivetrain.Speed))
end
print("Terrain material/drivetrain physics passed: "..count.." assertions")

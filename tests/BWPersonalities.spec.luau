local Parser=require("BWParser")
local VM=require("BWExecution")
local Sim=require("TankSimulation")
local Hardware=require("BWChassis")
local Components=require("VehicleComponents")
local Controller=require("BWController")
local Value=require("BWValue")
local Heat=require("RattlerWeapon")
local Windup=require("WeaponWindup")
local Geometry=require("ScannerGeometry")
local count=0
local function check(ok,message)count+=1;assert(ok,message)end
local tiers=personalityTiers
local function simulate(id,kind,options)
 options=options or {}
 local state=Sim.new(Vector3.zero,kind)
 local cfg=Hardware.default(tiers[id]or"Quad",Components.get(state))
 if id=="P03"then cfg.devices.drivetrain.allocation=0 end
 if id=="P02"then for name,d in cfg.devices do if name:sub(1,6)=="sensor"then d.allocation=0 end end end
 if options.noDrive then cfg.devices.drivetrain.allocation=0 end
 if options.noSensors then for name,d in cfg.devices do if name:sub(1,6)=="sensor"then d.allocation=0 end end end
 local tank={state=state,hardware=cfg,rattler=Heat.new(Components.get(state).Weapon)}
 Controller.applyHardware(tank)
 local clock,scans,shots,overheats,maxTravel=0,0,0,0,0
 local phases={};local visitDirections={};local yawTravel=0;local leadSeen=false;local lastCommand=0;local lastShotTime=0
 local target=Vector3.new(0,3.6,-(options.targetDistance or 45))
 local function scan(angle,performance,time,spec)
  scans+=1
  if options.busyEvery and scans%options.busyEvery==0 then return nil,"scannerBusy"end
  local direction=target-state.position
  local bearing=Geometry.worldBearing(direction)
  local heading=(-math.deg(state.yaw)+angle)%360
  local delta=(bearing-heading+180)%360-180
  local detections={}
  if not options.empty and time<(options.visibleUntil or 1000)and math.abs(delta)<(spec.coneWidth or 15)/2 and direction.Magnitude<(spec.range or 150)then
   table.insert(detections,Value.dictionary({type="tank",relation="enemy",player="fixture#2",point=Value.dictionary({x=target.X,y=target.Y,z=target.Z},true),distance=direction.Magnitude,world_direction=bearing},true))
  end
  if options.wall then
   local wall=Vector3.new(options.wall=="side"and 12 or 0,2.5,options.wall=="side"and 0 or -10)
   local delta=wall-state.position;local wb=Geometry.worldBearing(delta)
   if math.abs((wb-heading+180)%360-180)<(spec.coneWidth or 15)/2 then
    table.insert(detections,Value.dictionary({type="wall",relation=Value.Null,player=Value.Null,point=Value.dictionary({x=wall.X,y=wall.Y,z=wall.Z},true),distance=delta.Magnitude,world_direction=wb},true))
   end
  end
  local terrain=Value.Null
  if options.edge then terrain=Value.dictionary({supported=true,operational=true,edge_near=4,edge_far=6,count=0,samples=Value.array({})},true)end
  local hit=detections[1]or{}
  return Value.observation(Value.result(nil,{terrain=terrain,sensor=angle,timestamp=time,count=#detections,detections=Value.array(detections),type=hit.type or Value.Null,point=hit.point or Value.Null,distance=hit.distance or Value.Null,world_direction=hit.world_direction or Value.Null}),time,state.position,state.yaw)
 end
 local services={getOwnTank=function()return tank,clock,math.floor(clock*60),1/60 end,scan=scan}
 local parsed,err=Parser.parse(personalitySources[id]);check(parsed~=nil,id..": "..tostring(err and err.message))
 local vm=VM.new(parsed,state,services,cfg)
 local maxSeconds=options.seconds or 60
 for step=1,maxSeconds*60 do
  clock=step/60
  if options.moving then target=Vector3.new(clock*1.5,3.6,-(options.targetDistance or 45))end
  if options.pushAt and step==options.pushAt*60 then require("VehicleMotion").impulse(state,Vector3.new(80,0,0))end
  local lastYaw=state.yaw
  local input=vm:step(state,1/60)
  Sim.step(state,input,1/60,Vector2.new(2000,2000),options.environment)
  if options.blocked then state.position=Vector3.zero;state.motionForwardTravel=0 end
  if Components.get(state).Weapon.Operation=="Heat"then
   local cooldown=tank.rattler.cooldown
   if Heat.step(tank.rattler,true,input.fire,1/60,state.weaponPerformance)then
    shots+=1;state.weaponActivationSerial=(state.weaponActivationSerial or 0)+1;state.weaponShotSerial=(state.weaponShotSerial or 0)+1
   end
   if cooldown==0 and tank.rattler.cooldown>0 then overheats+=1 end
  else
   if tank.pendingShot then
    local done,origin=Windup.step(tank.pendingShot,state,1/60)
    if done then tank.pendingShot=nil;if origin then shots+=1;state.weaponShotSerial=(state.weaponShotSerial or 0)+1 end end
   end
   if not tank.pendingShot then
    tank.pendingShot=Windup.begin(state,input)
    if tank.pendingShot then state.weaponActivationSerial=(state.weaponActivationSerial or 0)+1 end
   end
  end
  maxTravel=math.max(maxTravel,state.position.Magnitude)
  yawTravel+=math.abs(state.yaw-lastYaw)
  if vm.variables.phase then phases[vm.variables.phase]=true end
  for index,visits in vm.variables.visits or{}do if visits>0 then visitDirections[index]=true end end
  for commandId=lastCommand+1,vm.devices.nextId do
   local c=vm.devices.commands[commandId]
   if c and c.instruction.op=="aim_at"and c.instruction.x>target.X+.25 then leadSeen=true end
  end
  lastCommand=vm.devices.nextId
  if shots>0 and (state.weaponShotSerial or 0)>0 then
   local serial=state.weaponShotSerial
   if serial~=(tank.lastTestShot or 0)then lastShotTime=clock;tank.lastTestShot=serial end
  end
  if options.damageAt and clock>options.damageAt then state.health=20 end
  check(vm.status~="error",id.." "..kind..": "..vm.message)
  if vm.status~="running"then break end
 end
 local ticks=Hardware.Tiers[cfg.tier].ticks
 check(vm.cyclesSpent<=(math.floor(clock*10)+2)*ticks*Hardware.Tiers[cfg.tier].threads+1,"CPU accounting bounded by real tier grants")
 return {vm=vm,state=state,scans=scans,shots=shots,overheats=overheats,maxTravel=maxTravel,phases=phases,visitDirections=visitDirections,yawTravel=yawTravel,leadSeen=leadSeen,lastShotTime=lastShotTime}
end
if not failureOnly then
for id,source in personalitySources do
 local budget=Hardware.default(tiers[id])
 for name,d in budget.devices do d.allocation=personalityMinimums[id][if name:sub(1,6)=="sensor"then "sensor*"else name]end
 check(Hardware.validate(budget)==true,id.." actual installed bus topology supports profile minimums")
 local parsed,err=Parser.parse(source);check(parsed~=nil,id..": "..tostring(err and err.message))
 for _,kind in {"Boomer","Rattler"}do
  local result=simulate(id,kind)
  check(result.vm.status=="running",id.." remains independently executing")
  check(result.vm.variables.phase~=nil,id.." exposes phase diagnostic")
 end
end
local crazy=simulate("P02","Rattler",{empty=true,seconds=25})
check(crazy.scans==0 and crazy.shots>10 and crazy.overheats>=2,"Crazy fires without enemies, empties native burst and resumes after overheat with zero scanners")
local tower=simulate("P03","Boomer",{seconds=30})
check(tower.maxTravel<.01 and tower.shots>0,"Tower stationary native projectile firing at visible target")
local marauder=simulate("P01","Boomer",{seconds=15,empty=true})
check(marauder.maxTravel>=19,"Marauder makes actual twenty-stud advance")
check(Parser.parse(hunterSource)~=nil,"Hunter now uses approved general source capacity with ordinary compiler safety")
for id in personalitySources do
 local noSensors=simulate(id,"Boomer",{noSensors=true,seconds=6})
 check(id=="P02"or noSensors.shots==0,"no scanner bypass or invented enemies with absent scanner power")
 local immobile=simulate(id,"Boomer",{noDrive=true,seconds=6})
 check(immobile.maxTravel<.01,"zero drive uses stationary fallback without movement advantage")
end
local c1=simulate("P02","Rattler",{empty=true,seconds=12})
local c2=simulate("P02","Rattler",{empty=true,seconds=12})
check(c1.state.position.X==c2.state.position.X and c1.state.position.Y==c2.state.position.Y and c1.state.position.Z==c2.state.position.Z and c1.shots==c2.shots and c1.vm.variables.seed==c2.vm.variables.seed,"fixed seed and identical hardware reproduce Crazy navigation and firing")
local hidden=simulate("P03","Boomer",{empty=true,seconds=12})
check(hidden.shots==0,"Tower cannot fire at unseen enemy state")
-- Distinct behavioral regression scenarios use production VM and physical devices.
local movingTower=simulate("P03","Boomer",{moving=true,seconds=25})
check(movingTower.leadSeen,"Tower's player-written predictor leads legally observed moving contact")
local sentinel=simulate("P07","Boomer",{empty=true,seconds=25})
check(sentinel.yawTravel>math.rad(10),"Sentinel fills fixed scanner gaps with real chassis sweep")
local skirmisher=simulate("P08","Boomer",{targetDistance=90,seconds=25})
check(skirmisher.phases.approach,"Skirmisher approaches distant visible contact")
local corner=simulate("P09","Boomer",{wall="front",empty=true,seconds=20})
check(corner.phases.inside_corner,"Wallflower responds to legal front-wall observation")
local prospector=simulate("P10","Boomer",{empty=true,seconds=25})
local explored=0
for _ in prospector.visitDirections do explored+=1 end
check(explored>1,"Prospector's bounded age/visit memory chooses multiple directions")
local gatekeeper=simulate("P11","Rattler",{empty=true,pushAt=2,seconds=30})
check(gatekeeper.phases.return_home,"Gatekeeper reacts to real external displacement with home tether")
local duelist=simulate("P12","Boomer",{seconds=25})
check(duelist.vm.variables.identity=="fixture#2"or duelist.phases.duel,"Duelist retains an observed opponent identity")
local survivor=simulate("P13","Boomer",{damageAt=2,blocked=true,seconds=40})
check(survivor.phases.escape and survivor.phases.cornered_fight and survivor.state.health==20,"critical Survivor attempts escape, fights when blocked and never assumes healing")
local ambusher=simulate("P14","Boomer",{visibleUntil=25,seconds=45})
check(ambusher.phases.watch_traffic and ambusher.lastShotTime<=27,"Ambusher learns traffic but never prefires at a hidden remembered contact: "..tostring(ambusher.phases.watch_traffic).." lastShot="..ambusher.lastShotTime.." counts="..Value.format(ambusher.vm.variables.counts))
local trail=simulate("P15","Boomer",{edge=true,empty=true,seconds=15})
check(trail.phases.observed_missing_ground and trail.maxTravel<.2,"Trailblazer's own BW logic responds to terrain; no engine cliff barrier")
local mapped=simulate("P06","Boomer",{edge=true,empty=true,seconds=25})
local blockedCell=false
for _,v in mapped.vm.variables.cells do if v==-1 then blockedCell=true end end
check(blockedCell and mapped.phases.observed_edge,"Hunter learns observed edge in its private bounded BW map")
local freshMap=simulate("P06","Boomer",{empty=true,seconds=1})
local oldBlocked=false
for _,v in freshMap.vm.variables.cells do if v==-1 then oldBlocked=true end end
check(not oldBlocked,"new Hunter runtime resets previous map knowledge")
local boundary=assert(personalitySources.P06:find("# P06",1,true))
local functions=personalitySources.P06:sub(1,boundary-1)
local routeSource=functions..[[
map = [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]
a = route(map, 12, 2)
map[7] = -1
b = route(map, 12, 2)
map[11] = -1
map[13] = -1
map[17] = -1
c = route(map, 12, 2)
]]
local routeCode,routeError=Parser.parse(routeSource);check(routeCode~=nil,tostring(routeError and routeError.message))
local routeState=Sim.new(Vector3.zero)
local routeVM=VM.new(routeCode,routeState,nil,Hardware.default("Octa"))
for _=1,3000 do routeVM:step(routeState,1/60);if routeVM.status~="running"then break end end
check(routeVM.status=="completed"and routeVM.variables.a==0 and routeVM.variables.b~=0 and routeVM.variables.b~=Value.Null and routeVM.variables.c==Value.Null,"Hunter's actual editable BFS routes around observed walls and reports enclosed frontier")
end
if failureOnly then
for id in personalitySources do
 local transient=simulate(id,"Boomer",{busyEvery=2,seconds=12})
 check(transient.vm.status=="running",id.." handles transient scannerBusy without invalid missing-field arithmetic")
end
end
print((if failureOnly then "BW personality scanner failures passed: "else "BW personalities passed: ")..count.." assertions")

-- Exercise the actual player-written heading helper against both drivetrain
-- solvers. Wheels must steer while rolling, tracks keep their turning command.
if not failureOnly then
 for _,kind in {"Boomer","Rattler"}do
  local state=Sim.new(Vector3.zero,kind);local hardware=Hardware.default("Bunny",Components.get(state))
  local tank={state=state,hardware=hardware};Controller.applyHardware(tank)
  local clock=0;local usedSteer,usedTurn=false,false
  local vm=VM.new(assert(Parser.parse(steeringSource)),state,{getOwnTank=function()return tank,clock,math.floor(clock*60),1/60 end},hardware)
  for i=1,2100 do
   clock=i/60;local input=vm:step(state,1/60)
   local active=vm.devices.devices.drivetrain.active
   if active then
    local op=active.instruction.op
    if op=="turn_left"or op=="turn_right"then usedTurn=true end
   end
   usedSteer=usedSteer or state.steeringAngle~=nil and math.abs(state.steeringAngle)>.001
   Sim.step(state,input,1/60,Vector2.new(2000,2000))
   if vm.status~="running"then break end
  end
  local error=math.abs((-math.deg(state.yaw)-90+180)%360-180)
  check(vm.status=="completed"and error<8,"shared BW helper reaches requested heading with actual "..kind.." physics, error="..error)
  if kind=="Rattler"then check(usedSteer and not usedTurn,"wheeled heading helper uses actual steering with no turn command")
  else check(usedTurn,"tracked heading helper retains normal turn command")end
 end
 print("Personality drivetrain steering tests passed: "..count.." assertions")
end

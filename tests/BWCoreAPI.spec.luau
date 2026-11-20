local Read=require("BWSelfState")
local Parser=require("BWParser")
local VM=require("BWExecution")
local Legacy=require("BWRuntime")
local Hardware=require("BWChassis")
local Value=require("BWValue")
local Components=require("VehicleComponents")
local Sim=require("TankSimulation")
local Input=require("InputCommand")
local Motion=require("VehicleMotion")
local Controller=require("BWController")
local Heat=require("RattlerWeapon")
local Windup=require("WeaponWindup")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local function near(a,b)return math.abs(a-b)<1e-6 end
local state=Sim.new(Vector3.new(1,4,2),"Boomer")
local tank={state=state,hardware=Hardware.forTank(state),rattler=Heat.new(Components.get(state).Weapon)}
local clock,tick,reads=5,300,0
local services={getOwnTank=function()reads+=1;return tank,clock,tick,1/60 end,getClock=function()return clock end}
local function read(name)return Read.read(name,state,tank.hardware,clock,services)end
Controller.applyHardware(tank)
for _,example in coreApiExamples do local parsed,err=Parser.parse(example);check(parsed~=nil,"API spec example uses actual BW syntax: "..tostring(err and err.message))end
local first=read("get_tank_state")
check(first.status=="success"and first.coordinates.x==1 and first.coordinates.y==4 and first.simulation.tick==300,"snapshot uses fresh own entity and coherent server timestamp")
check(first.weapon.id=="weapon.cannon"and first.weapon.projectile_model=="projectile"and first.weapon.projectile_speed==24,"actual canonical equipment and physical projectile speed")
check(first.weapon.ammo.mode=="unlimited"and first.weapon.ammo.remaining==Value.Null,"unlimited ammunition is explicit, never invented counts")
check(near(first.motion.effective_max_speed,first.motion.max_speed*Hardware.devicePerformance("drivetrain",40,Components.get(state)))and near(first.turret.effective_rotation_speed,first.turret.max_rotation_speed*.36),"physical ratings distinguish actual nonlinear bus-limited performance")
check(first.motion.steering_angle==Value.Null and first.motion.max_steering_angle==Value.Null,"tracks do not invent a front wheel steering angle")
check(first.motion.drivetrain_type=="Tracked"and first.motion.can_pivot and first.motion.min_turning_radius==0 and first.motion.wheel_count==Value.Null,"tracks expose real capabilities without cosmetic wheel counts")
check(first.scanner_count==8 and first.bus.bus_count==1 and #first.scanners==8,"counts allow BW traversal without a language extension")
check(first.scanners[1].cone_degrees==15 and first.scanners[1].mounting_degrees==0 and first.scanners[2].mounting_degrees==45 and first.scanners[1].reference=="chassis","actual narrow cones/discrete chassis mounting, not a freely steerable scan")
check(first.scanners[1].max_range==150 and first.scanners[1].effective_range==150 and first.scanners[1].performance<1,"bus sharing does not secretly shrink scanner range")
local function immutable(value)
 if value==Value.Null or type(value)~="table"then return end
 check(Value.isDictionary(value)or Value.isArray(value),"all nested snapshot containers are consumable BW values")
 check(table.isfrozen(value),"snapshot recursively immutable")
 for _,v in value do immutable(v)end
end
immutable(first)
check(not pcall(function()first.coordinates.x=99 end)and state.position.X==1,"snapshot cannot mutate engine state")
-- Same tick/clock, but changed dynamic state and hardware MUST be observed.
state.position=Vector3.new(12,9,-4);state.yaw=-math.pi/2;state.turretYaw=-math.pi/3;state.turretPitch=.15;state.health=65;state.cooldown=.4
Motion.setVelocity(state,Vector3.new(10,2,0));Motion.setYawVelocity(state,.25)
tank.hardware.devices.drivetrain.allocation=10;Controller.applyHardware(tank)
local second=read("get_tank_state")
check(second.coordinates.x==12 and second.coordinates.y==9 and first.coordinates.x==1 and first.health.current==100,"same-tick reads are fresh and earlier snapshot stays independent")
check(second.simulation.tick==first.simulation.tick and second.simulation.time==first.simulation.time,"no once-per-tick cache masquerades as freshness")
check(second.health.current==65 and second.health.max==100 and second.health.damage==35,"health and damage are coherent")
check(near(second.motion.speed,10)and near(second.motion.forward_speed,10)and second.motion.vertical_speed==2,"velocity-derived speed/direction is authoritative and fresh")
check(near(second.chassis.world_direction,90)and near(second.chassis.turn_rate,-math.deg(.25)),"heading and clockwise angular rate conventions")
check(near(second.bus.devices.drivetrain.allocation,10)and near(second.motion.effective_max_speed,second.motion.max_speed*Hardware.devicePerformance("drivetrain",10,Components.get(state))),"fresh actual bus allocation and matching performance")
check(near(second.scanners[2].world_direction,135)and second.turret.mount_pitch==math.deg(.15),"scanner reference follows chassis, actual turret elevation is separate")
check(read("get_tank_direction").world_direction==90 and read("get_weapon_type").weapon_type=="weapon.cannon"and read("get_drivetrain_type").drivetrain_id==Components.get(state).Installed.Drivetrain,"individual reads agree with full own snapshot")
check(read("get_current_coordinates").x==12 and read("get_turret_direction").mount_pitch==math.deg(.15),"individual dynamic metadata is live")
local ready=read("is_weapon_ready")
check(not ready.ready and ready.state=="cooldown"and ready.remaining_seconds==.4,"readiness reads actual cooldown, not a cached ready bit")
state.cooldown=0;state.health=100;tank.pendingShot={remaining=.12}
check(read("is_weapon_ready").state=="preparing","windup reports preparing separately from cooldown")
tank.pendingShot=nil;tank.requireFireRelease=true
check(read("is_weapon_ready").state=="release_required","required trigger release is not mislabeled ready")
tank.requireFireRelease=false;tank.hardware.devices.weapon.allocation=0;Controller.applyHardware(tank)
check(read("is_weapon_ready").state=="disabled","zero bus allocation disables readiness")
tank.hardware.devices.weapon=nil
check(read("is_weapon_ready").state=="unavailable"and read("get_weapon_speed").speed==24,"absent bus device does not erase installed projectile hardware")
tank.hardware=Hardware.forTank(state);Controller.applyHardware(tank)
check(read("is_weapon_ready").ready==true,"normal cannon becomes ready again without forced reload/ammo fiction")
local fire=Input.neutral();fire.fire=true;tank.pendingShot=Windup.begin(state,fire)
check(tank.pendingShot~=nil and read("is_weapon_ready").state=="preparing","real Windup.begin is visible immediately to own state")
local done=Windup.step(tank.pendingShot,state,10);tank.pendingShot=nil
check(done and read("is_weapon_ready").state=="cooldown","actual released cannon retains interval cooldown")
state.cooldown=0;Sim.step(state,Input.neutral(),1/60)
check(read("is_weapon_ready").ready,"physics/readiness refresh after cooldown")
-- Read metadata after trusted installed-component replacement (no BW mutation API).
local assembly=Components.copy(require("VehicleAssemblies").Rattler)
local profile=Components.resolve(assembly);Components.bind(state,profile);state.weaponId=profile.Installed.Weapon
state.tankType="Rattler";tank.hardware=Hardware.forTank(state);tank.rattler=Heat.new(profile.Weapon);Controller.applyHardware(tank)
local changed=read("get_tank_state")
check(changed.weapon.id=="weapon.gatling"and changed.weapon.projectile_speed==85 and first.weapon.id=="weapon.cannon","equipment and speed metadata are refreshed after binding changes")
check(changed.motion.drivetrain_type=="Wheeled"and not changed.motion.can_pivot and changed.motion.steering_mode=="front_wheel"and changed.motion.wheelbase==5.2,"wheeled state never implies tracked pivot steering")
state.steeringAngle=.25;Motion.setVelocity(state,Vector3.new(12,0,0))
local moving=read("get_tank_state")
check(near(moving.motion.turning_radius,5.2/math.tan(.25))and moving.motion.min_turning_radius>0,"wheel turning geometry derives from real wheelbase/steer/yaw cap")
check(read("is_weapon_ready").ready,"cold enabled Gatling is ready")
Heat.step(tank.rattler,true,true,1/60,state.weaponPerformance)
check(read("is_weapon_ready").state=="cooldown"and read("is_weapon_ready").remaining_seconds>0,"real Gatling shotClock is visible despite replicated weaponCooldown being zero")
local heatMetadata=read("is_weapon_ready")
check(heatMetadata.heat==tank.rattler.heat and heatMetadata.burst_seconds==tank.rattler.burst and heatMetadata.max_heat==profile.Weapon.MaxHeat and heatMetadata.max_burst_seconds==profile.Weapon.MaxBurst,"G3 reports live native own heat and burst, not replicated estimates")
check(heatMetadata.preparation_seconds==Value.Null and near(heatMetadata.effective_fire_interval_seconds,profile.Weapon.Cooldown/state.weaponPerformance),"G3 Gatling has no invented windup and uses real effective interval")
tank.rattler.cooldown=1.5;tank.rattler.shotClock=0
check(read("is_weapon_ready").state=="overheated","overheat is distinct from shot pacing")
check(read("is_weapon_ready").overheat_seconds==1.5 and heatMetadata.overheat_seconds==0,"G3 lockout is fresh while older immutable reads stay independent")
state.health=0;check(read("is_weapon_ready").state=="destroyed","destroyed tanks cannot claim readiness")
state.health=100;tank.rattler.cooldown=0;tank.rattler.heat=0;tank.rattler.burst=0
local standalone=Read.read("is_weapon_ready",state,tank.hardware,2,{})
check(standalone.ready==Value.Null and standalone.state=="unknown","standalone heat state gaps are explicit, not a false-ready claim")
local private=Read.read("get_tank_state",state,tank.hardware,2,{getOwnTank=function()return {state=Sim.new(Vector3.new(999,0,999))}end})
check(private.status=="fail"and private.reason=="stateUnavailable","mismatched own-context provider cannot expose another tank")
state.enemyPositions={secret=999};tank.otherTank={privateHealth=99}
check(read("get_tank_state").enemyPositions==nil and read("get_tank_state").otherTank==nil,"whitelist excludes arbitrary world/enemy/private record fields")
assembly.Sensors={};profile=Components.resolve(assembly);Components.bind(state,profile);tank.hardware=Hardware.forTank(state);Controller.applyHardware(tank)
local bare=read("get_tank_state")
check(bare.scanner_count==0 and #bare.scanners==0,"absent equipment yields a truthful empty scanner array")
-- Actual scanner override semantics, allocation-independent range, disabled lens.
assembly.Sensors=nil;profile=Components.resolve(assembly);Components.bind(state,profile);tank.hardware=Hardware.forTank(state)
local lens=tank.hardware.devices.sensor0;lens.range=240;lens.distancePercent=50;lens.coneWidth=36;lens.allocation=10
local lenses=read("get_tank_state").scanners
check(lenses[1].max_range==240 and lenses[1].catalog_range==150 and lenses[1].effective_range==120 and lenses[1].cone_degrees==36,"scanner metadata mirrors real configured ratings and distance percentage")
lens.allocation=0
check(read("get_tank_state").scanners[1].effective_range==0 and read("get_tank_state").scanners[1].acquisition_seconds==Value.Null,"disabled lens has no operating range or fabricated acquisition")
check(not Parser.parse('Scanner(36)'),"metadata does not authorize arbitrary unsupported sensor headings")
local none=Read.read("get_tank_state",state,tank.hardware,2,{})
check(none.simulation.time==2 and none.simulation.tick==Value.Null and none.simulation.step_seconds==Value.Null,"standalone runtime does not fabricate server ticks")
-- There are no hitscan weapons: reject misleading infinite/zero shell speed.
for _,id in {"weapon.cannon","weapon.gatling"}do
 local installed=Components.forWeapon("Boomer",id);local s=Sim.new(Vector3.zero,"Boomer",nil,installed)
 local speed=Read.read("get_weapon_speed",s,Hardware.forTank(s),0,{})
 check(speed.kind=="projectile"and speed.speed>0 and speed.speed<math.huge,"all actual weapons expose finite projectile model, never fake hitscan speed")
end
local catalog=Components.copy(require("ComponentCatalog"));local a=Components.copy(require("VehicleAssemblies").Boomer)
catalog["weapon.cannon"].Properties.ShellSpeed=math.huge
check(not pcall(Components.resolve,a,catalog),"unsupported infinite-speed hardware cannot be disguised as hitscan")
catalog["weapon.cannon"].Properties.ShellSpeed=24;catalog["weapon.cannon"].Properties.Operation="Hitscan"
check(not pcall(Components.resolve,a,catalog),"unimplemented hitscan operation is rejected rather than reporting a misleading projectile speed")
for name in Read.Names do
 check(Parser.parse(name.."()")~=nil,"all documented no-argument signatures parse")
 check(not Parser.parse(name.."(1)")and not Parser.parse(name.."(tank=1)"),"own reads never accept enemy selectors or extra arguments")
end
-- Exact CPU accounting through real production parser/scheduler/values.
local function vm(source,tier,customServices,s)
 local instructions,err=Parser.parse(source);assert(instructions,err and err.message)
 local state=s or Sim.new(Vector3.zero,"Boomer")
 Components.withComputer(state,tier or "Bunny")
 return VM.new(instructions,state,customServices,Hardware.default(tier or "Bunny")),state
end
local function run(runtime,s,frames)
 for _=1,frames or 360 do runtime:step(s,1/60);if runtime.status~="running"then break end end
end
for tier,spec in Hardware.Tiers do
 local r,s=vm('a = is_weapon_ready()\nb = get_tank_state()\nx = b.coordinates.x',tier)
 run(r,s,120)
 check(r.status=="completed",r.message)
 check(r.variables.b.bus.tier==tier and r.variables.b.equipment.Computer=="computer."..tier,"snapshot computer and actual execution bus tier remain coherent")
 check(near(r.threads[1].costs.is_weapon_ready,spec.ticks)and near(r.threads[1].costs.get_tank_state,2*spec.ticks),"cycle-cost reads charge tier-relative tick budgets exactly")
 check(near(r.cyclesSpent,3*spec.ticks+.9),"snapshot field access has only ordinary read/access/write fees")
end
local cheapCalls={}
for name in Read.Names do if not Hardware.IntrospectionCycles[name]and name~="get_tank_direction"then table.insert(cheapCalls,name.."()")end end
table.sort(cheapCalls)
local cheap,cheapState=vm(table.concat(cheapCalls,"\n"));run(cheap,cheapState,120)
check(cheap.status=="completed"and near(cheap.cyclesSpent,6),"all inexpensive individual operations charge exactly one tick without assignment overhead")
for _,source in cheapCalls do local name=source:sub(1,-3);check(cheap.threads[1].costs[name]==1,"metadata call is charged once: "..name)end
local calls=0;local lateState=Sim.new(Vector3.zero,"Boomer")
local lateTank={state=lateState,hardware=Hardware.forTank(lateState)}
local r,s=vm('snap = get_tank_state()','Bunny',{getOwnTank=function()calls+=1;return lateTank,5,300,1/60 end},lateState)
r:step(s,1/60);check(calls==0 and r.variables.snap==nil,"CPU-starved snapshot cannot read before its call is affordable")
s.position=Vector3.new(7,8,9)
for _=1,6 do r:step(s,1/60)end
check(calls==0,"two grants do not silently waive assignment overhead")
s.position=Vector3.new(21,22,23);run(r,s,60)
check(calls==1 and r.variables.snap.coordinates.x==21,"snapshot reads AFTER budget wait exactly once, not when coroutine/AST was started")
local printed,ps=vm('print(get_tank_state())','Bunny');run(printed,ps,60)
check(near(printed.cyclesSpent,20)and printed.threads[1].costs.get_tank_state==20,"debug print cannot waive introspection fee")
local short,ss=vm('a = false and is_weapon_ready().ready');run(short,ss,60)
check(short.status=="completed"and not short.threads[1].costs.is_weapon_ready,"short-circuited queries are not charged or executed")
local fields,fs=vm('a = get_tank_state().coordinates.x');run(fields,fs,60)
check(near(fields.cyclesSpent,20.4),"nested snapshot field reads do not pay extra introspection charge")
local used=0;local fresh=Sim.new(Vector3.zero,"Boomer");local own={state=fresh,hardware=Hardware.forTank(fresh)}
local repeated,rs=vm('a = get_current_coordinates()\nb = get_current_coordinates()','Bunny',{getOwnTank=function()
 used+=1;fresh.position=Vector3.new(used,0,0);return own,0,0,1/60
end},fresh)
run(repeated,rs,60)
check(used==2 and repeated.variables.a.x==1 and repeated.variables.b.x==2,"same-cycle repeated reads invoke fresh context, not a tick memoization")
local traversed,ts=vm('s = get_tank_state()\ni = 0\nwhile i < s.scanner_count:\n    heading = s.scanners[i].mounting_degrees\n    i = i + 1')
run(traversed,ts,600)
check(traversed.status=="completed"and traversed.variables.i==8 and traversed.variables.heading==315,"existing BW while/index syntax can consume all scanner metadata")
local consume,cs=vm('function x(const snapshot):\n    return snapshot.coordinates.x\ns = get_tank_state()\nresult = x(s)')
run(consume,cs,120)
check(consume.status=="completed"and consume.variables.result==0,"existing const parameters consume immutable snapshots without language changes")
local scalarProgram,scalarState=vm('function plus(value):\n    return value + 1\nfunction echo(value):\n    return value\ns = get_tank_state()\nallocation = plus(s.bus.devices.drivetrain.allocation)\npart = echo(s.equipment.Weapon)\nx = plus(s.coordinates.x)\ny = plus(get_current_coordinates().y)\ni = 0\nwhile i < s.scanner_count:\n    arc = plus(s.scanners[i].cone_degrees)\n    i = i + 1')
run(scalarProgram,scalarState,360)
check(scalarProgram.status=="completed"and scalarProgram.variables.x==1 and scalarProgram.variables.y==1 and scalarProgram.variables.arc==16 and scalarProgram.variables.allocation==41 and scalarProgram.variables.part=="weapon.cannon","static result shapes allow scalar fields and dynamic array elements in ordinary functions")
check(not Parser.parse('function change(value):\n    value.x = 1\ns = get_tank_state()\nchange(s.coordinates)'),"known result shapes do not permit immutable containers through mutable parameters")
local function conforms(value,schema)
 if value==Value.Null then return end
 for key,item in value do
  local child=schema[if Value.isArray(value)then "*"else key]or schema["*"]
  check(child~=nil,"static result shape covers every emitted field")
  if child==true then check(type(item)~="table"or item==Value.Null,"scalar contract never hides mutable/structured data")else conforms(item,child)end
 end
end
conforms(first,Read.Shapes.get_tank_state)
local mutator,ms=vm('s = get_tank_state()\ns.coordinates.x = 42');run(mutator,ms,120)
check(mutator.status=="error"and ms.position.X==0,"BW field writes cannot mutate snapshot or simulation")
local legacy=Legacy.new(assert(Parser.parse('s = get_tank_state()')),Sim.new(Vector3.zero,"Boomer"))
check(legacy.threads~=nil,"serial entry delegates new calls to production CPU instead of implementing a parallel API")
local old,os=vm('old = get_facing_direction()\nnew = get_tank_direction()\nclock = get_clock()')
run(old,os,60)
check(old.status=="completed"and old.variables.old.world_direction==old.variables.new.world_direction and near(old.cyclesSpent,.8),"old heading/clock signatures and fees remain compatible")
-- Actual motion/turret/device execution, then supported configure/restart.
local liveState=Sim.new(Vector3.zero,"Boomer")
local liveClock=0
local live={state=liveState,owner=1,hitbox=Instance.new("Part"),hardware=Hardware.forTank(liveState),rattler=Heat.new(Components.get(liveState).Weapon)}
live.bwServices={getClock=function()return liveClock end,getOwnTank=function()return live,liveClock,math.floor(liveClock*60+.5),1/60 end}
check(Controller.start(live,'before = get_tank_state()\nforward(3)\nturret_right(10)\nturret_up(5)\nwait_for_clock(get_clock().time + 1.2)\nafter = get_tank_state()'),"production controller accepts self queries with existing device commands")
local changedHardware=Hardware.copy(live.hardware);changedHardware.devices.drivetrain.allocation=10
local changedOk,reason=Controller.configure(live,changedHardware)
check(not changedOk and reason=="programRunning","new read API does not bypass live hardware-reconfiguration prohibition")
for i=1,240 do
 liveClock=i/60
 Controller.applyHardware(live)
 local command=Controller.input(live,1/60)or Input.neutral();Sim.step(liveState,command,1/60)
 if live.bw.status~="running"then break end
end
check(live.bw.status=="completed",live.bw.message)
local before,after=live.bw.variables.before,live.bw.variables.after
check(after.coordinates.z<before.coordinates.z-2 and after.turret.mount_yaw>before.turret.mount_yaw and after.turret.mount_pitch>before.turret.mount_pitch,"fresh snapshots follow actual BW movement and both turret axes")
check(after.simulation.time>before.simulation.time and after.simulation.tick>before.simulation.tick,"production-style clock/tick advance coherently across real motion")
check(Controller.configure(live,changedHardware),"supported stopped-program bus reconfiguration remains available")
local configured=Read.read("get_tank_state",liveState,live.hardware,liveClock,live.bwServices)
check(configured.bus.devices.drivetrain.allocation==10 and near(configured.motion.effective_max_speed,configured.motion.max_speed*Hardware.devicePerformance("drivetrain",10,Components.get(liveState))),"post-configure read observes real controller hardware and effective speed")
local enemy={owner=2,state=Sim.new(Vector3.zero,"Boomer")}
check(require("LocalBattle").damage({multiplayer=true},live,enemy,25,"Cannon",Vector3.zero),"damage freshness fixture uses real authoritative damage path")
local injured=Read.read("get_tank_state",liveState,live.hardware,liveClock,live.bwServices)
check(injured.health.current==75 and injured.health.damage==25 and configured.health.current==100,"damage read is fresh while earlier immutable snapshots retain their values")
local pieces={};for _=1,64 do table.insert(pieces,'get_tank_state()')end
local huge,hs=vm('a = ['..table.concat(pieces,',')..']')
huge:step(hs,1/60)
check(huge.status=="error"and string.find(huge.message,"maximum CPU reservation",1,true),"oversized introspection expressions respect existing maximum reservation bound")
-- Stage2 approved geometry, timing and mechanical coordinate aiming.
local pose=read("get_turret_direction")
local origin,dir=Sim.shotPose(state)
check(near(pose.muzzle_position.x,(origin+dir*Components.get(state).Weapon.MuzzleOffset).X)and near(pose.direction.y,dir.Y),"G1 authoritative shot origin and direction, not catalog estimates")
check(table.isfrozen(pose.direction)and table.isfrozen(pose.pivot),"G1 vector records immutable")
local timing=Read.read("is_weapon_ready",liveState,live.hardware,liveClock,live.bwServices)
check(timing.operation=="Windup"and timing.heat==Value.Null and timing.max_burst_seconds==Value.Null,"G3 never invents cannon heat or magazines")
check(near(timing.effective_preparation_seconds,Components.get(liveState).Weapon.FireWindup/liveState.weaponPerformance),"G3 actual bus-limited windup")
check(Hardware.cost("aim_at","Bunny")==1,"G2 submission fee is one tick")
for _,bad in {'aim_at(1, 2)','aim_at(1, 2, 3, 4)','aim_at(x=1, 2, 3)','aim_at(100001, 2, 3)'}do
 local parsed=Parser.parse(bad);check(parsed==nil,"invalid coordinate aim rejected: "..bad)
end
local legacyAim=Legacy.new(assert(Parser.parse('aim_at(0, 4, -20)')),Sim.new(Vector3.zero,"Boomer"))
check(legacyAim.threads~=nil,"legacy source entry routes coordinate aim through normal production CPU/queues, without recursive physical delegation")
local aimState=Sim.new(Vector3.zero,"Boomer")
local cfg=Hardware.forTank(aimState)
local aimServices={getOwnTank=function()return {state=aimState,hardware=cfg}end}
local aimed=VM.new(assert(Parser.parse('a = aim_at(30, 12, -60)')),aimState,aimServices,cfg)
local startYaw,startPitch=aimState.turretYaw,aimState.turretPitch
local both=false
for _=1,600 do
 local input=aimed:step(aimState,1/60)
 local y,p=aimState.turretYaw,aimState.turretPitch
 aimState.turretPerformance=Hardware.performance(cfg.devices.turret.allocation,Components.get(aimState).Bus)
 Sim.step(aimState,input,1/60)
 local limit=Components.get(aimState).Turret.TraverseSpeed*aimState.turretPerformance/60+1e-6
 check(math.abs(aimState.turretYaw-y)<=limit and math.abs(aimState.turretPitch-p)<=limit,"G2 both axes bounded by actual bus-limited angular speed")
 if aimState.turretYaw~=y and aimState.turretPitch~=p then both=true end
 if aimed.status~="running"then break end
end
check(aimed.status=="completed"and both and aimState.turretYaw~=startYaw and aimState.turretPitch~=startPitch,"G2 simultaneous mechanical axes complete")
check(aimed.devices:status(aimed.variables.a.commandId).completionReason==Value.Null,"reachable coordinate completes normally")
local limited=VM.new(assert(Parser.parse('a = aim_at(0, -100, -1)')),aimState,aimServices,cfg)
for _=1,600 do local input=limited:step(aimState,1/60);Sim.step(aimState,input,1/60);if limited.status~="running"then break end end
check(limited.status=="completed"and limited.devices:status(limited.variables.a.commandId).completionReason=="mountLimited","G2 unreachable depression yields actionable mountLimited feedback")
cfg.devices.turret.allocation=0
local disabled=VM.new(assert(Parser.parse('a = aim_at(0, 0, -20)')),aimState,aimServices,cfg)
for _=1,60 do disabled:step(aimState,1/60)end
check(disabled.variables.a.reason=="deviceDisabled","G2 cannot bypass zero turret allocation")

print(string.format("BW core own-state API passed: %d assertions",count))

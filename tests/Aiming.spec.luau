local Aim=require("TurretAim")
local Sim=require("TankSimulation")
local Input=require("InputCommand")
local Components=require("VehicleComponents")
local Projectiles=require("ProjectileSimulation")
local Path=require("ProjectileTrajectory")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local function near(a,b)return math.abs(a-b)<1e-5 end
local function world(point)local c=Input.neutral();c.aimMode="World";c.aim=point;return c end
local function settle(state,target)
 for _=1,180 do Sim.step(state,world(target),1/60)end
end
check(Input.validate(world(Vector3.new(1,22,3))).aim.Y==22,"validated World intent retains elevation")
for _,bad in {0/0,math.huge,-math.huge,1000001}do check(not Input.validate(world(Vector3.new(0,bad,1))),"invalid target height rejected")end
for _,performance in {0,.2,.5,1}do
 local s=Sim.new(Vector3.zero,"Boomer");s.turretPerformance=performance
 local c=Input.neutral();c.turretX=1;c.turretY=1;Sim.step(s,c,.1)
 local expected=Components.get(s).Turret.TraverseSpeed*performance*.1
 check(near(-s.turretYaw,expected)and near(s.turretPitch,expected),"simultaneous axes share exact speed and hardware multiplier")
 check(near(Components.get(s).Turret.PitchSpeed,Components.get(s).Turret.TraverseSpeed),"legacy pitch speed is derived, never independent")
end
for _,kind in {"Boomer","Rattler"}do
 for _,scenario in {
  {Vector3.new(-45,0,0),Vector3.new(40,18,-10)}, -- uphill target
  {Vector3.new(-50,9,-75),Vector3.new(48,3,-35)}, -- overlook downhill
  {Vector3.new(-50,0,30),Vector3.new(50,3,30)}, -- across ravine
  {Vector3.new(0,12,0),Vector3.new(80,3,-30)}, -- raised bridge to low bank
 }do
  local s=Sim.new(scenario[1],kind);local target=scenario[2];settle(s,target)
  local pivot,direction=Sim.shotPose(s);local desired=(target-pivot).Unit
  check((direction-desired).Magnitude<.001,kind.." aligns yaw/pitch at different elevations")
  local weapon=Components.get(s).Weapon
  local empty={GetPartBoundsInRadius=function()return {}end,Spherecast=function()return nil end}
  local shell=Projectiles.launch(empty,pivot,direction,{},weapon,scenario[1].Y,{physical=true,airborne=false})
  check((shell.position-(pivot+direction*weapon.MuzzleOffset)).Magnitude<1e-5,"muzzle sweep reaches actual three-dimensional barrel tip")
  check((shell.direction-direction).Magnitude<1e-5,"release tangent follows aligned barrel")
  -- Native spherecast boundary stand-in, fed by actual server projectile steps.
  local targetPart={}
  local hitWorld={GetPartBoundsInRadius=function()return {}end,Spherecast=function(_,origin,radius,delta)
   local offset=target-origin;local t=math.clamp((offset.X*delta.X+offset.Y*delta.Y+offset.Z*delta.Z)/(delta.Magnitude^2),0,1)
   if (origin+delta*t-target).Magnitude<=2+radius then return {Instance=targetPart,Position=origin+delta*t,Distance=delta.Magnitude*t}end
  end}
  local shot=Projectiles.launch(hitWorld,pivot,direction,{},weapon,scenario[1].Y,{physical=true,airborne=false});local hit
  for _=1,900 do hit=Projectiles.step(hitWorld,shot,1/60);if hit or shot.done then break end end
  check(hit and hit.Instance==targetPart,"server swept shot reaches elevated/downhill target")
 end
end
local tilted=Sim.new(Vector3.new(0,10,0),"Boomer");tilted.yaw=.8;tilted.bodyPitch=.3;tilted.bodyRoll=-.18
local v=Vector3.new(.3,.2,-.8)
check((Aim.toMount(tilted,Aim.toWorld(tilted,v))-v).Magnitude<1e-6,"mount transforms invert chassis slope, roll and yaw")
local target=Aim.pivot(tilted)+Aim.toWorld(tilted,Sim.forward(.6,.2))*100
local yaw,pitch=Aim.target(tilted,target)
check(near(yaw,tilted.yaw+.6)and near(pitch,.2),"target solve compensates actual tilted mount geometry")
local early=Sim.new(Vector3.zero,"Boomer")
Sim.step(early,world(Vector3.new(100,20,0)),1/60)
local c=Input.neutral();c.fire=true
local pivot,dir=Sim.tryFire(early,c)
check(dir.Z<-.99 and dir.X>0 and dir.X<.1,"shot fired during traverse follows current barrel, not cursor target")
check(not Sim.tryFire(early,c),"three-dimensional aiming does not bypass cooldown")
local high=Sim.new(Vector3.zero);settle(high,Vector3.new(0,100,-1))
check(near(high.turretPitch,Components.get(high).Turret.MaxPitch),"mechanical upper stop enforced")
settle(high,Vector3.new(0,-100,-1))
check(near(high.turretPitch,Components.get(high).Turret.MinPitch),"mechanical lower stop enforced")
local moving=Sim.new(Vector3.zero)
for i=1,240 do
 local oldYaw,oldPitch=moving.turretYaw,moving.turretPitch
 Sim.step(moving,world(Vector3.new(math.sin(i*.03)*50,10+math.sin(i*.07)*10,-90)),1/60)
 local bound=Components.get(moving).Turret.TraverseSpeed/60+1e-6
 check(math.abs(moving.turretYaw-oldYaw)<=bound and math.abs(moving.turretPitch-oldPitch)<=bound,"moving XYZ target cannot exceed either angular rate")
end
-- Production airborne Gatling preserves tangent, including upward and near-plane shots.
local tuning=Components.get("Rattler").Weapon
for _,p in {-.2,0,.25}do
 local s=Sim.new(Vector3.new(0,6,0),"Rattler");s.lift=6;s.turretPitch=p
 local origin,direction=Sim.shotPose(s)
 check(near(direction.Y,math.sin(p)),"altitude cannot manufacture barrel depression")
 local flight=Projectiles.launch({GetPartBoundsInRadius=function()return {}end,Spherecast=function()return nil end},origin,direction,{},tuning,0,{physical=true,airborne=true})
 check((flight.direction-direction).Magnitude<1e-5,"airborne release does not flatten or retarget current direction")
end
local extreme=Path.new(Vector3.new(0,3.61,0),Vector3.new(0,-.2,-1).Unit,3.6,tuning.Trajectory,true)
check((select(2,Path.sample(extreme,0))-Vector3.new(0,-.2,-1).Unit).Magnitude<1e-5,"near-plane leveling preserves release tangent")
-- BW uses existing parser, queue, hardware, executor and simulation.
local Parser=require("BWParser");local Execution=require("BWExecution");local Hardware=require("BWChassis")
local applied={state=Sim.new(Vector3.zero,"Boomer"),hardware=Hardware.default("Bunny")}
local Controller=require("BWController")
for _,allocation in {0,10,20}do
 applied.hardware.devices.turret.allocation=allocation;Controller.applyHardware(applied)
 applied.state.turretYaw=0;applied.state.turretPitch=0
 local c=Input.neutral();c.turretX=1;c.turretY=1;Sim.step(applied.state,c,.1)
 local expected=Components.get(applied.state).Turret.TraverseSpeed*Hardware.performance(allocation,Components.get(applied.state).Bus)*.1
 check(near(-applied.state.turretYaw,expected)and near(applied.state.turretPitch,expected),"real hardware allocation bounds both axes identically")
end
local cannon=Components.get("Boomer");local gatling=Components.forWeapon("Boomer","weapon.gatling")
check(near(math.deg(cannon.Turret.MinPitch),-12)and near(math.deg(gatling.Turret.MinPitch),-15),"weapon clearance gives Gatling slightly more depression than cannon")
for _,weapon in {"weapon.cannon","weapon.gatling"}do
 local installed=Components.forWeapon("Boomer",weapon)
 local s=Sim.new(Vector3.zero,"Boomer",nil,installed)
 settle(s,Vector3.new(0,-100,-1))
 local _,direction=Sim.shotPose(s)
 check(near(s.turretPitch,installed.Turret.MinPitch)and near(direction.Y,math.sin(installed.Turret.MinPitch)),"World aim and firing respect the installed weapon depression stop")
end
for _,weapon in {"weapon.cannon","weapon.gatling"}do
 local installed=Components.forWeapon("Boomer",weapon)
 for _,slope in {-.4,.4}do
  local s=Sim.new(Vector3.zero,"Boomer",nil,installed)
  s.yaw=.7;s.turretYaw=.7;s.bodyPitch=slope;s.bodyRoll=.15;s.turretPitch=installed.Turret.MinPitch
  local _,direction=Sim.shotPose(s)
  local localDirection=Aim.toMount(s,direction)
  local localPitch=math.atan2(localDirection.Y,math.sqrt(localDirection.X^2+localDirection.Z^2))
  check(near(localPitch,installed.Turret.MinPitch),"depression stop is mount-relative on uphill/downhill, yawed and rolled chassis")
  if slope<0 then check(math.asin(direction.Y)<installed.Turret.MinPitch,"downhill barrel may point below world-relative stop without exceeding its mount stop")end
  local point=Aim.pivot(s)+Aim.toWorld(s,Sim.forward(0,-1))*100
  local _,desired=Aim.target(s,point)
  check(near(desired,installed.Turret.MinPitch),"World target clamp is measured in tilted mount frame")
 end
end
local catalog=Components.copy(require("ComponentCatalog"));local assembly=Components.copy(require("VehicleAssemblies").Boomer)
catalog["turret.standard"].Properties.MinPitch=math.rad(-45)
catalog["weapon.cannon"].Properties.MinPitch=math.rad(-40)
check(near(math.deg(Components.resolve(assembly,catalog).Turret.MinPitch),-40),"future weapon can depress farther when mount supports it")
catalog["turret.standard"].Properties.MinPitch=math.rad(-20)
check(near(math.deg(Components.resolve(assembly,catalog).Turret.MinPitch),-20),"a weapon never bypasses its mount's stricter stop")
local state=Sim.new(Vector3.zero,"Boomer");local hw=Hardware.default("Dual")
local program=assert(Parser.parse('a = turret_up(to=20)\nwait_for_clock(1)\nb = turret_down(10)\nwait_for_clock(2)\nc = turret_right(45)'))
local r=Execution.new(program,state,nil,hw)
for _=1,240 do Sim.step(state,r:step(state,1/60),1/60)end
check(r.status=="completed"and math.abs(math.deg(state.turretPitch)-10)<1,"queued BW absolute and relative elevation complete on turret device")
check(math.abs(math.deg(state.turretYaw)+45)<1,"legacy BW horizontal command remains compatible and retains elevation")
check(r.variables.a.status=="success"and r.variables.b.status=="success","BW elevation retains ordinary accepted command results")
local limited=Sim.new(Vector3.zero,"Boomer");local p=assert(Parser.parse('turret_up(to=80)'))
local lr=Execution.new(p,limited,nil,hw)
for _=1,120 do Sim.step(limited,lr:step(limited,1/60),1/60)end
check(lr.status=="completed"and near(limited.turretPitch,Components.get(limited).Turret.MaxPitch),"BW mount stop is clamped without bypass or stuck queue")
check(not Parser.parse('turret_up(to=100)') and not Parser.parse('turret_down(-10)'),"invalid BW elevation arguments rejected")
print(string.format("3D aiming/physical fire/BW passed: %d assertions",count))

local Definitions=require("TankDefinitions")
local Weapon=require("RattlerWeapon")
local Flight=require("RecoilFlight")
local Simulation=require("TankSimulation")
local Selection=require("TankSelection")
local Config=require("TankConfig")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
check(Definitions.Boomer.Weapon==Config,"Boomer uses unchanged original weapon tuning")
check(not Definitions.valid("Unknown") and not Definitions.valid({}) and Definitions.valid("Rattler"),"selection allowlist")
local function state() return Simulation.new(Vector3.zero,"Rattler") end
local command={throttle=1,steer=0.2,fire=true,aimMode="Rate",turretX=0.1,turretY=0.05}
for _,dt in {1/30,1/60,1/120} do
 local weapon=Weapon.new()
 local tank=state()
 local shots=0
 local lockAt
 local heights={}
 for i=1,math.floor(3/dt+0.5) do
  local shot=Weapon.step(weapon,true,true,dt)
  tank.firing=weapon.firing; tank.heat=weapon.heat
  Simulation.step(tank,command,dt)
  if shot then Flight.kick(tank,weapon.heat); shots+=1 end
  if weapon.cooldown>0 and not lockAt then lockAt=i*dt end
  if i==math.floor(1/dt+0.5) or i==math.floor(2/dt+0.5) then table.insert(heights,tank.lift) end
  check((tank.lift or 0)>=0 and tank.lift<=Definitions.Rattler.Recoil.MaxLift,"flight stays bounded")
  check(math.abs(tank.verticalSpeed or 0)<=Definitions.Rattler.Recoil.MaxFallSpeed,"vertical speed stays bounded")
 end
 check(lockAt and lockAt<=3+1e-6 and lockAt>=3-dt-1e-6,"continuous fire stops within three seconds")
 check(shots>=28 and shots<=30,"rapid fire stays at approximately ten shots per second")
 check(heights[1]>=0 and heights[2]<=6,"continuous firing remains low instead of accumulating altitude")
 check(math.abs(tank.position.X)+math.abs(tank.position.Z)>1 and tank.turretYaw~=0,"initial ground momentum and turret aiming remain available")
 local lockedFor=0
 while weapon.cooldown>0 do
  check(not Weapon.step(weapon,true,true,dt),"held trigger cannot fire during mandatory cooldown")
  tank.firing=weapon.firing; tank.heat=weapon.heat; Simulation.step(tank,command,dt)
  lockedFor+=dt
 end
 check(lockedFor>=2-1e-5,"cooldown lasts at least two seconds")
 check(tank.lift==0,"gravity returns tank to ground during overheat")
 check(Weapon.step(weapon,true,true,dt),"held trigger may resume only after full lockout")
end
-- Early release falls, lands and injects suspension compression/rebound.
do
 local tank=state(); local w=Weapon.new(); local peak=0
 for _=1,70 do
  local shot=Weapon.step(w,true,true,1/60); tank.firing=w.firing; tank.heat=w.heat; Simulation.step(tank,command,1/60)
  if shot then Flight.kick(tank,w.heat) end
  peak=math.max(peak,tank.lift or 0)
 end
 local high=tank.lift
 local landing=false; local compression,rebound=false,false
 for _=1,240 do
  check(not Weapon.step(w,true,false,1/60),"release stops rapid projectiles immediately")
  tank.firing=w.firing; command.throttle=0; command.steer=0
  Simulation.step(tank,command,1/60)
  if (tank.landingSerial or 0)>0 then
   landing=true; compression=compression or tank.bounce < -0.05
   rebound=rebound or (compression and tank.bounce>0.01)
  end
 end
 check(peak>3 and tank.lift==0 and tank.verticalSpeed==0,"early-release flight returns to ground and rests")
 check(landing and compression and rebound,"landing compresses and rebounds suspension")
 check(w.heat==0,"idle recovery eventually clears heat")
end
-- Tapping does not reset heat; forced cooldown cannot be evaded by another tank.
do
 local w=Weapon.new(); local locked=false
 for i=1,600 do
  Weapon.step(w,true,i%2==0,1/60)
  if w.cooldown>0 then locked=true; break end
 end
 check(locked,"rapid trigger tapping still reaches heat lockout")
 local tank={state=state(),command=command,rattler=w,lastInput=4,pendingShot={remaining=0.1}}
 tank.state.health=55; tank.state.lift=4; tank.state.verticalSpeed=6
 local position=tank.state.position
 check(Selection.switch(tank,"Boomer",10),"switch to Boomer succeeds")
 check(tank.pendingShot==nil and not tank.command.fire and tank.requireFireRelease,"switch clears pending weapon and held intent")
 check(tank.state.health==55 and tank.state.position==position and tank.state.lift==4 and tank.state.verticalSpeed==6,"switch preserves health and flight instead of teleport/heal exploit")
 check(tank.rattler==w and tank.rattler.cooldown>0,"heat ledger survives switching")
 check(not Selection.switch(tank,"Rattler",10.1),"switch requests are rate limited")
 check(Selection.switch(tank,"Rattler",10.6),"switch back succeeds")
 check(not Weapon.step(tank.rattler,true,true,1/60),"switching back cannot clear lockout")
 check(not Selection.switch(tank,"Invalid",12),"server rejects unknown tank type")
 tank.state.health=0
 check(not Selection.switch(tank,"Boomer",12),"selection cannot revive a dead tank")
end
-- Idle recovery begins only after a pause; short taps receive no free cooling.
do
 local w=Weapon.new(); w.heat=2
 Weapon.step(w,true,false,0.3)
 check(w.heat==2,"short release retains accumulated heat")
 Weapon.step(w,true,false,0.2)
 check(math.abs(w.heat-1.94)<1e-5,"only idle time after recovery delay cools weapon")
end
-- Rattler's car handling is distinct from Boomer's skid steering.
do
 local Drive=require("RattlerDrive")
 local car=state()
 local turn={throttle=0,steer=1}
 for _=1,60 do Drive.step(car,turn,1/60,1) end
 check(car.yaw==0 and car.speed==0,"Rattler cannot pivot turn while stationary")
 turn.throttle=1
 Drive.step(car,turn,1/60,1)
 check(car.speed>0 and car.speed<1,"Rattler accelerates rather than jumping to full speed")
 for _=1,180 do Drive.step(car,turn,1/60,1) end
 check(math.abs(car.speed-30)<1e-5,"Rattler has its own forward speed tuning")
 local forwardYaw=car.yaw
 Drive.step(car,turn,1/60,1)
 check(car.yaw>forwardYaw,"forward steering turns into the selected direction")
 turn.throttle=-1
 for _=1,180 do Drive.step(car,turn,1/60,1) end
 local reverseYaw=car.yaw
 Drive.step(car,turn,1/60,1)
 check(car.speed<0 and car.yaw<reverseYaw,"reverse steering follows a car's signed wheel motion")
 turn.throttle=0
 for _=1,180 do Drive.step(car,turn,1/60,1) end
 check(car.speed==0,"Rattler coasts to a stop")
 local boomer=Simulation.new(Vector3.zero,"Boomer")
 Simulation.step(boomer,{throttle=0,steer=1,aimMode="Rate",turretX=0,turretY=0},1/60)
 check(math.abs(boomer.yaw-Config.TurnSpeed/60)<1e-6,"Boomer retains its stationary pivot steering")
 turn.throttle=1; turn.steer=0
 for _=1,180 do Drive.step(car,turn,1/60,0.75) end
 check(math.abs(car.speed-22.5)<1e-5,"car target speed respects mud slowdown")
end
-- Both weapons use their own speed/radius/damage through the same collision path.
do
 local Projectiles=require("ProjectileSimulation")
 local Targets=require("PracticeTargets")
 local world={GetPartBoundsInRadius=function() return {} end,Spherecast=function() return nil end}
 for _,id in {"Boomer","Rattler"} do
  local tuning=Definitions.get(id).Weapon
  local shell=Projectiles.launch(world,Vector3.zero,Vector3.new(0,0,-1),{},tuning)
  check(math.abs(shell.position.Z+tuning.MuzzleOffset)<1e-5,"both weapons launch at checked muzzle")
  local before=shell.position
  Projectiles.step(world,shell,0.1)
  check(math.abs((shell.position-before).Magnitude-tuning.ShellSpeed*0.1)<1e-5,"each projectile retains configured speed")
  check(shell.radius==tuning.ShellRadius and shell.damage==tuning.Damage,"server records weapon-specific collision radius and damage")
  local p=Instance.new("Part"); local target=Targets.new(p)
  Targets.impact({Instance=p},{[p]=target},0,shell.damage)
  check(target.health==100-tuning.Damage,"target damage uses originating weapon")
 end
end
-- Renderer ownership is replaced once, rather than accumulating models/connections.
do
 local Registry=require("TankRenderers")
 local live,created,destroyed={},0,0
 local function create(id,kind)
  created+=1
  return {tankType=kind,resetPose=function(self,s) self.state=s end,destroy=function() destroyed+=1 end}
 end
 local states={one=Simulation.new(Vector3.zero)}
 Registry.sync(live,states,create); Registry.sync(live,states,create)
 check(created==1 and destroyed==0,"unchanged snapshots reuse existing renderer")
 for i=1,20 do
  states.one.tankType=if i%2==0 then "Boomer" else "Rattler"; states.one.generation=i
  Registry.sync(live,states,create)
  check(created-destroyed==1,"rapid switching leaves exactly one active renderer")
 end
 Registry.sync(live,{},create)
 check(created==destroyed and next(live)==nil,"departure destroys last renderer")
end
-- Selector sends intent only and cleans up its own two connections.
do
 local Selector=require("TankSelector")
 local selected
 local ui=Selector.new(Instance.new("ScreenGui"),function(id) selected=id end)
 ui.buttons.Rattler.Activated:Fire()
 check(selected=="Rattler" and ui.selected=="Boomer","selector waits for server snapshot to change active choice")
 ui:update({tankType="Rattler"}); ui.buttons.Boomer.Activated:Fire()
 check(selected=="Boomer","both selection choices work")
 ui:destroy(); selected=nil; ui.buttons.Boomer.Activated:Fire()
 check(selected==nil and ui.frame.destroyed,"destroyed selector has no stale button connections")
end
-- Recoil changes the real replicated turret pose, not hidden bullet spread.
do
 local Aim=require("TurretRecoil")
 local tank=state(); local weapon=Weapon.new(); weapon.heat=2; weapon.aimSeed=101
 local originalTarget=tank.turretYaw
 local _,previous=Simulation.shotPose(tank)
 local negative,positive=false,false
 for i=1,90 do
  Aim.kick(tank,weapon)
  local yaw,pitch=Simulation.turretAngles(tank)
  local _,direction=Simulation.shotPose(tank)
  check((direction-previous).Magnitude>1e-5,"every bullet kicks turret to a new actual direction")
  local expected=require("ProjectileTrajectory").launchDirection(tank.position+Vector3.new(0,Config.MuzzleHeight,0),Simulation.forward(yaw,pitch),Config.MuzzleHeight,Definitions.Rattler.Weapon.MuzzleOffset,Definitions.Rattler.Weapon.Trajectory)
  check((direction-expected).Magnitude<1e-6,"shot follows weapon-constrained actual displaced barrel")
  check(tank.turretYaw==originalTarget,"cursor target remains separate from recoil direction")
  check(math.abs(tank.aimRecoilYaw)<=Definitions.Rattler.Aim.MaxYaw and math.abs(tank.aimRecoilPitch)<=Definitions.Rattler.Aim.MaxPitch,"turret kicks remain bounded")
  negative=negative or tank.aimRecoilYaw<0; positive=positive or tank.aimRecoilYaw>0
  previous=direction
  Aim.step(tank,0.1)
 end
 check(negative and positive,"recoil can wander either side of desired aim")
 for _=1,360 do Aim.step(tank,1/60) end
 check(math.abs(tank.aimRecoilYaw)<1e-8 and math.abs(tank.aimRecoilPitch)<1e-8,"turret settles to desired aim after firing")
 local boomer=Simulation.new(Vector3.zero,"Boomer")
 local _,before=Simulation.shotPose(boomer); Aim.kick(boomer,weapon)
 local _,after=Simulation.shotPose(boomer)
 check((before-after).Magnitude>0.03,"Boomer now receives a stronger actual-turret kick")
 local firstYaw,firstPitch=boomer.aimRecoilYaw,boomer.aimRecoilPitch
 check(math.abs(firstYaw)>math.rad(3.9) and math.abs(firstPitch)>math.rad(2.9),"Boomer recoil is stronger than Rattler recoil")
 for _=1,39 do Aim.step(boomer,1/60) end
 check(math.abs(boomer.aimRecoilYaw)<math.abs(firstYaw)*0.05 and math.abs(boomer.aimRecoilPitch)<math.abs(firstPitch)*0.05,"Boomer recovers over 95 percent during its reload")
 local _,settled=Simulation.shotPose(boomer)
 check((settled-before).Magnitude<0.01,"Boomer is nearly re-aimed before its next shell")
end
print(string.format("Tank types suite passed: %d assertions",count))

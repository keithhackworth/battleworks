local DamageEffects=require(script.Parent.DamageEffects)
-- Pure state math: no Instances, input devices, rendering, or physics ownership.
local Components = require(script.Parent.VehicleComponents)
local Drive = require(script.Parent.RattlerDrive)
local Motion = require(script.Parent.VehicleMotion)
local Surface = require(script.Parent.SurfacePhysics)
local Trajectory = require(script.Parent.ProjectileTrajectory)
local Config = require(script.Parent.TankConfig)
local Environment = require(script.Parent.Environment)
local TurretRecoil = require(script.Parent.TurretRecoil)
local Recoil = require(script.Parent.RattlerRecoil)
local Simulation = {}
function Simulation.new(position, tankType, seed, assembly)
    local c=if assembly then (if assembly.Resolved then assembly else Components.resolve(assembly)) else Components.get(tankType)
    local state=Components.bind({ recoilSeed = seed or c.Recoil.DefaultSeed, tankType = tankType or "Boomer", weaponId=c.Installed.Weapon, generation = 0, position = position, yaw = 0, turretYaw = 0, turretPitch = 0, speed = 0, health = c.Chassis.Health, maxHealth=c.Chassis.Health, cooldown = 0, bounce = 0, bounceVelocity = 0, movement = 0, bounceClock = 0, bodyPitch = 0, bodyRoll = 0 },c)
    Motion.configure(state,c.Chassis.Mass,c.Chassis.YawInertia)
    return state
end
function Simulation.forward(yaw, pitch)
	pitch = pitch or 0
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end
-- Player aim is the target orientation; actual turret pose also includes recoil.
function Simulation.turretAngles(state)
 local turret=Components.get(state).Turret
	return state.turretYaw+(state.aimRecoilYaw or 0),
		math.clamp((state.turretPitch or 0)+(state.aimRecoilPitch or 0),turret.MinPitch,turret.MaxPitch)
end
-- World-space barrel direction after chassis pitch/roll and actual turret aim.
function Simulation.shotPose(state)
	local yaw,pitch = Simulation.turretAngles(state)
	local direction = Simulation.forward(yaw,pitch)
	local c, s = math.cos(state.yaw), math.sin(state.yaw)
	local x, y, z = c*direction.X-s*direction.Z, direction.Y, s*direction.X+c*direction.Z
	local cr, sr = math.cos(state.bodyRoll or 0), math.sin(state.bodyRoll or 0)
	x, y = cr*x-sr*y, sr*x+cr*y
	local cp, sp = math.cos(state.bodyPitch or 0), math.sin(state.bodyPitch or 0)
	y, z = cp*y-sp*z, sp*y+cp*z
	local vehicle=Components.get(state)
	local pivot=state.position+Vector3.new(0,vehicle.Turret.MuzzleHeight+(state.bounce or 0),0)
	local actual=Vector3.new(c*x+s*z,y,-s*x+c*z).Unit
	local weapon=vehicle.Weapon
	if weapon.Trajectory then
		actual=Trajectory.launchDirection(pivot,actual,(state.groundPlaneY or 0)+Config.MuzzleHeight,weapon.MuzzleOffset,weapon.Trajectory)
	end
	return pivot,actual
end
local function suspension(state, dt)
 local tuning=Components.get(state).Mobility.Suspension
	local remaining = math.max(dt,0)
	while remaining > 0 do
		local step = math.min(remaining,1/120)
		local moving = if state.health > 0 then math.min(math.abs(state.speed)/tuning.Speed,1) else 0
		state.movement = (state.movement or 0)+(moving-(state.movement or 0))*(1-math.exp(-tuning.Response*step))
		state.bounceClock = (state.bounceClock or 0)+step*tuning.Frequency
		local target = math.sin(state.bounceClock)*tuning.Bob*state.movement
		state.bounceVelocity = (state.bounceVelocity or 0)+((target-(state.bounce or 0))*tuning.Spring-(state.bounceVelocity or 0)*tuning.Damping)*step
		state.bounce = (state.bounce or 0)+state.bounceVelocity*step
		remaining -= step
	end
	state.bodyPitch = (math.sin(state.bounceClock or 0)*tuning.Pitch*(state.movement or 0))+(state.flightPitch or 0)
	state.bodyRoll = (math.cos((state.bounceClock or 0)*tuning.RollFrequency)*tuning.Roll*(state.movement or 0))+(state.flightRoll or 0)
end
function Simulation.moveBody(state,command,dt,mapSize,environment)
 local c=Components.get(state)
 Motion.beginStep(state,dt)
 local support=state.groundPlaneY or 0
 if environment then support+=Environment.pose(environment,state.position,state.yaw,c.Chassis) end
 if state.position.Y>support+0.001 then state.lift=math.max(state.lift or 0,state.position.Y-support) end
 local airborne=Recoil.airborne(state)
 local speedScale=if environment then select(3,Environment.sample(environment,state.position.X,state.position.Z)) else 1
 local static,kinetic,resistance=Surface.contact(environment and environment.physicsSurfaces,state.position,state.yaw,c.Chassis)
 if not airborne then Drive.ground(state,command,dt,speedScale,static,kinetic,resistance) end
 -- No traction, steering, coasting or ground damping is applied in the air.
 local previous=state.position
 Motion.integrateHorizontal(state,dt)
 local edgeX=(if mapSize then mapSize.X/2 else Config.ArenaLimit)-c.Chassis.Radius
 local edgeZ=(if mapSize then mapSize.Y/2 else Config.ArenaLimit)-c.Chassis.Radius
 local x,z=math.clamp(state.position.X,-edgeX,edgeX),math.clamp(state.position.Z,-edgeZ,edgeZ)
 local v=Motion.ensure(state)
 if x~=state.position.X or z~=state.position.Z then Motion.setVelocity(state,Vector3.new(if x~=state.position.X then 0 else v.X,v.Y,if z~=state.position.Z then 0 else v.Z)) end
 if environment and Environment.blocked(environment,x,z,c.Chassis.Radius) then
  x=previous.X; z=previous.Z; v=Motion.ensure(state); Motion.setVelocity(state,Vector3.new(0,v.Y,0))
 end
 local ground,pitch,roll,kind=0,0,0,"Grass"
 if environment then ground,pitch,roll,kind=Environment.pose(environment,Vector3.new(x,0,z),state.yaw,c.Chassis) end
 ground+=(state.groundPlaneY or 0)
 state.position=Vector3.new(x,state.position.Y,z)
 state.groundPitch=pitch; state.groundRoll=roll; state.surface=kind
 Recoil.step(state,dt,ground)
 Motion.sync(state)
end
function Simulation.step(state, command, dt, mapSize, environment)
 local c=Components.get(state); local turret=c.Turret
	command=DamageEffects.input(state,command)
    if state.drivePerformance==0 or state.turretPerformance==0 then
        command=table.clone(command)
        if state.drivePerformance==0 then command.throttle=0; command.steer=0 end
        if state.turretPerformance==0 then command.aimMode="Rate"; command.turretX=0; command.turretY=0 end
    end
	state.cooldown = math.max(0, state.cooldown - dt)
	TurretRecoil.step(state,dt)
	if state.health<=0 then state.firing=false end
    Simulation.moveBody(state,command,dt,mapSize,environment)
    suspension(state,dt)
    state.bodyPitch+=state.groundPitch or 0; state.bodyRoll+=state.groundRoll or 0
    if state.health<=0 then return end
	if command.aimMode == "Rate" then
		-- Positive X aims right; positive Y elevates the cannon.
		state.turretYaw -= command.turretX * turret.TraverseSpeed * (state.turretPerformance or 1) * dt
		state.turretPitch = math.clamp(state.turretPitch + command.turretY * turret.PitchSpeed * (state.turretPerformance or 1) * dt,
			turret.MinPitch, turret.MaxPitch)
	else
		local delta = command.aim - state.position
		if delta.Magnitude > 0.01 then
			local desired = math.atan2(-delta.X, -delta.Z)
			local difference = math.atan2(math.sin(desired - state.turretYaw), math.cos(desired - state.turretYaw))
			state.turretYaw += math.clamp(difference, -turret.TraverseSpeed * (state.turretPerformance or 1) * dt, turret.TraverseSpeed * (state.turretPerformance or 1) * dt)
		end
		-- Desktop retains its original horizontal mouse aiming.
		state.turretPitch = 0
	end
end
function Simulation.tryFire(state, command)
	if state.health <= 0 or not command.fire or state.cooldown > 0 or (state.weaponPerformance or 1)<=0 then return nil end
	state.cooldown = Components.get(state).Weapon.Cooldown / (state.weaponPerformance or 1)
	return Simulation.shotPose(state)
end
return Simulation

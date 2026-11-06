-- Pure state math: no Instances, input devices, rendering, or physics ownership.
local Config = require(script.Parent.TankConfig)
local Environment = require(script.Parent.Environment)
local Simulation = {}
function Simulation.new(position)
	return { position = position, yaw = 0, turretYaw = 0, turretPitch = 0, speed = 0, health = Config.Health, cooldown = 0, bounce = 0, bounceVelocity = 0, movement = 0, bounceClock = 0, bodyPitch = 0, bodyRoll = 0 }
end
function Simulation.forward(yaw, pitch)
	pitch = pitch or 0
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end
-- World-space barrel direction after chassis pitch/roll and independent turret aim.
function Simulation.shotPose(state)
	local direction = Simulation.forward(state.turretYaw, state.turretPitch)
	local c, s = math.cos(state.yaw), math.sin(state.yaw)
	local x, y, z = c*direction.X-s*direction.Z, direction.Y, s*direction.X+c*direction.Z
	local cr, sr = math.cos(state.bodyRoll or 0), math.sin(state.bodyRoll or 0)
	x, y = cr*x-sr*y, sr*x+cr*y
	local cp, sp = math.cos(state.bodyPitch or 0), math.sin(state.bodyPitch or 0)
	y, z = cp*y-sp*z, sp*y+cp*z
	return state.position+Vector3.new(0,3.6+(state.bounce or 0),0), Vector3.new(c*x+s*z,y,-s*x+c*z).Unit
end
local function suspension(state, dt)
	local remaining = math.max(dt,0)
	while remaining > 0 do
		local step = math.min(remaining,1/120)
		local moving = if state.health > 0 then math.min(math.abs(state.speed)/24,1) else 0
		state.movement = (state.movement or 0)+(moving-(state.movement or 0))*(1-math.exp(-8*step))
		state.bounceClock = (state.bounceClock or 0)+step*8
		local target = math.sin(state.bounceClock)*0.38*state.movement
		state.bounceVelocity = (state.bounceVelocity or 0)+((target-(state.bounce or 0))*150-(state.bounceVelocity or 0)*12)*step
		state.bounce = (state.bounce or 0)+state.bounceVelocity*step
		remaining -= step
	end
	state.bodyPitch = math.sin(state.bounceClock or 0)*0.05*(state.movement or 0)
	state.bodyRoll = math.cos((state.bounceClock or 0)*0.8)*0.035*(state.movement or 0)
end
function Simulation.step(state, command, dt, mapSize, environment)
	state.cooldown = math.max(0, state.cooldown - dt)
	if state.health <= 0 then state.speed = 0; suspension(state,dt); return end
	state.yaw += command.steer * Config.TurnSpeed * dt
	local speedScale = if environment then select(3,Environment.sample(environment,state.position.X,state.position.Z)) else 1
	state.speed = command.throttle * Config.Speed * speedScale
	suspension(state,dt)
	local nextPosition = state.position + Simulation.forward(state.yaw) * state.speed * dt
	local edgeX = (if mapSize then mapSize.X/2 else Config.ArenaLimit) - Config.Radius
	local edgeZ = (if mapSize then mapSize.Y/2 else Config.ArenaLimit) - Config.Radius
	local x,z = math.clamp(nextPosition.X,-edgeX,edgeX),math.clamp(nextPosition.Z,-edgeZ,edgeZ)
	if environment and Environment.blocked(environment,x,z,Config.Radius) then x=state.position.X; z=state.position.Z; state.speed=0 end
	local height,pitch,roll,kind = 0,0,0,"Grass"
	if environment then height,pitch,roll,kind = Environment.pose(environment,Vector3.new(x,0,z),state.yaw) end
	local blend=1-math.exp(-12*dt)
	state.groundHeight=(state.groundHeight or 0)+(height-(state.groundHeight or 0))*blend
	state.groundPitch=(state.groundPitch or 0)+(pitch-(state.groundPitch or 0))*blend
	state.groundRoll=(state.groundRoll or 0)+(roll-(state.groundRoll or 0))*blend
	state.bodyPitch += state.groundPitch; state.bodyRoll += state.groundRoll
	state.surface=kind
	state.position = Vector3.new(x,state.groundHeight,z)
	if command.aimMode == "Rate" then
		-- Positive X aims right; positive Y elevates the cannon.
		state.turretYaw -= command.turretX * Config.TurretSpeed * dt
		state.turretPitch = math.clamp(state.turretPitch + command.turretY * Config.TurretPitchSpeed * dt,
			Config.MinPitch, Config.MaxPitch)
	else
		local delta = command.aim - state.position
		if delta.Magnitude > 0.01 then
			local desired = math.atan2(-delta.X, -delta.Z)
			local difference = math.atan2(math.sin(desired - state.turretYaw), math.cos(desired - state.turretYaw))
			state.turretYaw += math.clamp(difference, -Config.TurretSpeed * dt, Config.TurretSpeed * dt)
		end
		-- Desktop retains its original horizontal mouse aiming.
		state.turretPitch = 0
	end
end
function Simulation.tryFire(state, command)
	if state.health <= 0 or not command.fire or state.cooldown > 0 then return nil end
	state.cooldown = Config.Cooldown
	return Simulation.shotPose(state)
end
return Simulation

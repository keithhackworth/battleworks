-- Pure state math: no Instances, input devices, rendering, or physics ownership.
local Config = require(script.Parent.TankConfig)
local Simulation = {}
function Simulation.new(position)
	return { position = position, yaw = 0, turretYaw = 0, turretPitch = 0, speed = 0, health = Config.Health, cooldown = 0 }
end
function Simulation.forward(yaw, pitch)
	pitch = pitch or 0
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end
function Simulation.step(state, command, dt, mapSize)
	state.cooldown = math.max(0, state.cooldown - dt)
	if state.health <= 0 then state.speed = 0; return end
	state.yaw += command.steer * Config.TurnSpeed * dt
	state.speed = command.throttle * Config.Speed
	local nextPosition = state.position + Simulation.forward(state.yaw) * state.speed * dt
	local edgeX = (if mapSize then mapSize.X/2 else Config.ArenaLimit) - Config.Radius
	local edgeZ = (if mapSize then mapSize.Y/2 else Config.ArenaLimit) - Config.Radius
	state.position = Vector3.new(math.clamp(nextPosition.X, -edgeX, edgeX), 0, math.clamp(nextPosition.Z, -edgeZ, edgeZ))
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
	local direction = Simulation.forward(state.turretYaw, state.turretPitch)
	return state.position + Vector3.new(0, 3.6, 0), direction
end
return Simulation

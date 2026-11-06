-- Server-owned shot preparation; cooldown begins when the swell starts.
local Config = require(script.Parent.TankConfig)
local Simulation = require(script.Parent.TankSimulation)
local Windup = {}
function Windup.begin(state, command)
	local origin = Simulation.tryFire(state, command)
	if not origin then return nil end
	return { remaining = Config.FireWindup }
end
function Windup.step(pending, state, dt)
	if state.health <= 0 then return true end
	pending.remaining -= math.max(dt, 0)
	if pending.remaining > 1e-6 then return false end
	-- Aim and cover checks use the current pose when the prepared shot releases.
	return true, state.position + Vector3.new(0, 3.6, 0), Simulation.forward(state.turretYaw, state.turretPitch)
end
return Windup

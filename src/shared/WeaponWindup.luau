-- Server-owned shot preparation; cooldown begins when the swell starts.
local Components = require(script.Parent.VehicleComponents)
local Simulation = require(script.Parent.TankSimulation)
local Windup = {}
function Windup.begin(state, command)
	local origin = Simulation.tryFire(state, command)
	if not origin then return nil end
	state.bounceVelocity = (state.bounceVelocity or 0)-Components.get(state).Weapon.PreparationImpulse
	return { remaining = Components.get(state).Weapon.FireWindup / math.max(state.weaponPerformance or 1,0.0001) }
end
function Windup.step(pending, state, dt)
	if state.health <= 0 then return true end
	pending.remaining -= math.max(dt, 0)
	if pending.remaining > 1e-6 then return false end
	-- Aim and cover checks use the current pose when the prepared shot releases.
	local origin, direction = Simulation.shotPose(state)
	return true, origin, direction
end
return Windup

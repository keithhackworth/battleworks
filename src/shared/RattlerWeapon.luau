-- Pure server-stepped heat state; it persists when switching to another tank.
local Config = require(script.Parent.TankDefinitions).Rattler.Weapon
local Weapon = {}
function Weapon.new()
	return { heat = 0, burst = 0, cooldown = 0, shotClock = 0, idle = 0, firing = false }
end
function Weapon.step(weapon, enabled, trigger, dt, performance)
 performance=performance or 1
 enabled=enabled and performance>0
	dt = math.max(dt, 0)
	weapon.firing = false
	weapon.shotClock = math.max(0, weapon.shotClock-dt)
	if weapon.cooldown > 0 then
		weapon.cooldown = math.max(0, weapon.cooldown-dt)
		weapon.heat = math.max(0, weapon.heat-Config.MaxHeat/Config.OverheatCooldown*dt)
		weapon.burst = 0
		if weapon.cooldown < 1e-6 then weapon.cooldown = 0; weapon.heat = 0 end
		return false -- even the last cooldown tick cannot launch a shot
	end
	if not enabled or not trigger then
		weapon.burst = 0
		local previous = weapon.idle
		weapon.idle += dt
		local recovery = math.max(0, weapon.idle-Config.RecoveryDelay)-math.max(0, previous-Config.RecoveryDelay)
		weapon.heat = math.max(0, weapon.heat-recovery*Config.RecoveryRate)
		return false
	end
	weapon.idle = 0
	weapon.burst += dt
	weapon.heat = math.min(Config.MaxHeat, weapon.heat+dt)
	if weapon.burst >= Config.MaxBurst-1e-6 or weapon.heat >= Config.MaxHeat-1e-6 then
		weapon.cooldown = Config.OverheatCooldown
		weapon.burst = 0
		return false
	end
	weapon.firing = true
	if weapon.shotClock > 1e-6 then return false end
	weapon.shotClock = Config.Cooldown/math.max(performance,0.0001)
	return true
end
return Weapon

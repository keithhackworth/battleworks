-- Server-owned target health and first-hit ray resolution. No client damage input.
local Config = require(game.ReplicatedStorage.Shared.TankConfig)
local Targets = {}
Targets.Health = 100
Targets.Damage = 25
Targets.RespawnDelay = 5
Targets.RespawnRetryInterval = 0.25
local orange = Color3.fromRGB(210, 102, 60)
function Targets.sync(part, target, now)
	local alive = target.health > 0
	part:SetAttribute("Health", target.health)
	part:SetAttribute("MaxHealth", Targets.Health)
	part.Transparency = if alive then 0 else 1
	part.CanCollide = alive
	part.CanTouch = alive
	part.CanQuery = alive
	part.Material = if alive and now < target.flashUntil then Enum.Material.Neon else Enum.Material.Plastic
	part.Color = if now < target.flashUntil then Color3.fromRGB(255, 245, 190)
		else Color3.fromRGB(210, 40 + 62 * target.health / Targets.Health, 35 + 25 * target.health / Targets.Health)
	if target.label then
		target.label.Text = string.format("%d / %d", target.health, Targets.Health)
		target.label.Parent.Enabled = alive
	end
end
function Targets.new(part)
	local target = { health = Targets.Health, resetAt = 0, flashUntil = 0 }
	part.Color = orange
	Targets.sync(part, target, 0)
	return target
end
function Targets.damage(part, target, now)
	if target.health <= 0 then return false end
	target.health = math.max(0, target.health - Targets.Damage)
	target.flashUntil = now + 0.15
	if target.health == 0 then target.resetAt = now + Targets.RespawnDelay end
	-- Update queries immediately, before another shot in the same simulation step.
	Targets.sync(part, target, now)
	return true
end
function Targets.occupied(part, tanks)
	-- Match the movement solver's conservative XZ footprint, including corners.
	-- Center-only or circular checks could restore a target where movement's
	-- expanded rectangle still blocks the tank. Boundary contact also waits.
	for _, tank in tanks do
		local state = tank.state
		if state.health > 0 then
			local delta = state.position - part.Position
			if math.abs(delta.X) <= part.Size.X / 2 + Config.Radius
				and math.abs(delta.Z) <= part.Size.Z / 2 + Config.Radius then
				return true
			end
		end
	end
	return false
end
function Targets.update(part, target, now, tanks)
	if target.health == 0 and now >= target.resetAt then
		if Targets.occupied(part, tanks) then
			target.resetAt = now + Targets.RespawnRetryInterval
		else
			target.health = Targets.Health; target.resetAt = 0; target.flashUntil = 0
		end
	end
	Targets.sync(part, target, now)
end
function Targets.impact(hit, targets, now)
	local target = if hit then targets[hit.Instance] else nil
	local before = if target then target.health else nil
	if target then Targets.damage(hit.Instance, target, now) end
	return hit, before, if target then target.health else nil
end
return Targets

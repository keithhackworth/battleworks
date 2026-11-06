local Targets = require("PracticeTargets")
local Simulation = require("TankSimulation")
local Command = require("InputCommand")
local count = 0
local function check(ok, message) assert(ok, message); count += 1 end
local part = Instance.new("Part")
local target = Targets.new(part)
local label = Instance.new("TextLabel"); label.Parent = Instance.new("BillboardGui"); target.label = label
local targets = { [part] = target }
local shooter = Instance.new("Part")
local state = Simulation.new(Vector3.new(0,0,35))
local command = Command.neutral(); command.fire = true
local origin, direction = Simulation.tryFire(state, command)
check(origin.Y == 3.6 and direction.Z == -1, "server horizontal shot crosses target height 0..7")
check(origin.X >= -3.5 and origin.X <= 3.5, "straight center shot aligned with center practice target")
check(Simulation.tryFire(state, command) == nil, "cooldown prevents repeat damage without simulation time")
local nextHit = { Instance = part, Position = Vector3.new(0,3.6,-62.5) }
for i = 1, 4 do
	local hit, before, after = Targets.impact(nextHit, targets, i)
	check(hit == nextHit and before == 125 - i*25 and after == 100 - i*25, "first-hit identity resolves exact 25 damage")
	check(part:GetAttribute("Health") == after and label.Text == tostring(after) .. " / 100", "health and visible readout replicated together")
	if i < 4 then
		check(part.Transparency == 0 and part.Material == Enum.Material.Neon and part.CanQuery, "surviving target flashes and remains queryable")
	else
		check(part.Transparency == 1 and not part.CanQuery and not part.CanCollide and not label.Parent.Enabled,
			"fourth hit immediately disappears and stops blocking shots")
	end
end
check(target.resetAt == 9, "respawn scheduled five seconds from lethal hit")
check(not Targets.damage(part, target, 8) and target.resetAt == 9, "dead target cannot take damage or postpone reset")
Targets.update(part, target, 8.999, {})
check(target.health == 0, "does not respawn early")
Targets.update(part, target, 9, {})
check(target.health == 100 and part.Transparency == 0 and part.CanQuery and part.CanCollide and label.Parent.Enabled,
	"respawn restores health appearance and query state")
Targets.damage(part, target, 10)
Targets.update(part, target, 10.16, {})
check(part.Material == Enum.Material.Plastic and target.health == 75, "flash expires without resetting damage")
local wall = Instance.new("Part")
nextHit = { Instance = wall, Position = Vector3.new(0,3.6,0) }
local hit, before, after = Targets.impact(nextHit, targets, 11)
check(hit.Instance == wall and before == nil and after == nil and target.health == 75, "wall first hit prevents damage behind cover")
nextHit = nil
hit = Targets.impact(nextHit, targets, 12)
check(hit == nil and target.health == 75, "miss causes no target damage")
-- Respawn occupancy uses authoritative states for all players, not visuals.
local spawn = Instance.new("Part")
spawn.Position = Vector3.new(18, 3.5, -65); spawn.Size = Vector3.new(7,7,5)
local blocked = Targets.new(spawn)
blocked.label = Instance.new("TextLabel"); blocked.label.Parent = Instance.new("BillboardGui")
for _ = 1,4 do Targets.damage(spawn, blocked, 0) end
local function tank(x, z, hp)
	return { state = { position = Vector3.new(x,0,z), health = hp or 100 } }
end
local tanks = { [101] = tank(100,100), [202] = tank(18,-65) }
check(Targets.occupied(spawn,tanks), "any living player occupying target center blocks respawn")
Targets.update(spawn,blocked,5,tanks)
check(blocked.health == 0 and blocked.resetAt == 5.25, "occupied deadline schedules periodic retry")
check(spawn.Transparency == 1 and not spawn.CanCollide and not spawn.CanQuery and not blocked.label.Parent.Enabled
	and spawn:GetAttribute("Health") == 0, "occupied target stays completely destroyed")
tanks[202].state.position = Vector3.new(26,-0,-65)
check(Targets.occupied(spawn,tanks), "center outside target but tank footprint overlaps")
tanks[202].state.position = Vector3.new(26,0,-58)
check(Targets.occupied(spawn,tanks), "conservative diagonal footprint matches movement rectangle")
tanks[202].state.position = Vector3.new(26.5,0,-57.5)
check(Targets.occupied(spawn,tanks), "exact boundary contact postpones restoration")
Targets.update(spawn,blocked,5.25,tanks)
check(blocked.health == 0 and blocked.resetAt == 5.5, "continued occupancy delays again")
tanks[202].state.position = Vector3.new(26.51,0,-65)
check(not Targets.occupied(spawn,tanks), "full footprint outside expanded X bound is clear")
Targets.update(spawn,blocked,5.49,tanks)
check(blocked.health == 0, "clear space waits until next scheduled retry")
Targets.update(spawn,blocked,5.5,tanks)
check(blocked.health == 100 and spawn.Transparency == 0 and spawn.CanQuery and spawn.CanCollide
	and blocked.label.Parent.Enabled and spawn:GetAttribute("Health") == 100, "clear retry restores all target state together")
tanks[202] = tank(18,-65,0)
check(not Targets.occupied(spawn,tanks), "dead tank inside spawn does not block")
tanks[303] = tank(18,-72)
check(Targets.occupied(spawn,tanks), "another living player's footprint still blocks when center tank is dead")
tanks[303] = nil
check(not Targets.occupied(spawn,tanks), "departed player cannot leave stale occupancy")
tanks[202] = tank(18,-72.51)
check(not Targets.occupied(spawn,tanks), "full footprint outside expanded Z bound is clear")
check(not Targets.occupied(spawn,{}), "empty server has clear spawn")
print(string.format("Combat suite passed: %d assertions", count))

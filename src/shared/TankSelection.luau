-- Selection changes the existing player-owned state; no duplicate simulation/model.
local Definitions = require(script.Parent.TankDefinitions)
local Command = require(script.Parent.InputCommand)
local Selection = {}
function Selection.switch(tank, id, now)
	if not Definitions.valid(id) or tank.state.health <= 0 or tank.state.tankType == id then return false end
	if now-(tank.lastSwitch or -math.huge) < 0.5 then return false end
	tank.lastSwitch = now
	tank.state.tankType = id
	tank.state.generation = (tank.state.generation or 0)+1
	tank.state.firing = false; tank.state.speed = 0
	tank.pendingShot = nil; tank.command = Command.neutral(); tank.lastInput = 0
	tank.requireFireRelease = true
	-- Health, cooldown, heat ledger, current pose and recoil-flight velocity survive.
	return true
end
return Selection

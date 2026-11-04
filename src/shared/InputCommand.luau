-- One intent contract for desktop, touch, gamepad, and future server controllers.
-- World aim preserves desktop behavior; Rate uses normalized turretX/Y axes.
local Command = {}
function Command.neutral()
	return { throttle = 0, steer = 0, aim = Vector3.new(0, 0, -1), fire = false,
		aimMode = "Rate", turretX = 0, turretY = 0 }
end
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < 1e6
end
function Command.validate(value)
	if type(value) ~= "table" or not finite(value.throttle) or not finite(value.steer)
		or type(value.fire) ~= "boolean" then return nil end
	local result = Command.neutral()
	result.throttle = math.clamp(value.throttle, -1, 1)
	result.steer = math.clamp(value.steer, -1, 1)
	result.fire = value.fire
	-- Missing mode remains compatible with the original world-aim contract.
	local mode = if value.aimMode == nil then "World" else value.aimMode
	if mode == "Rate" then
		if not finite(value.turretX) or not finite(value.turretY) then return nil end
		result.turretX = math.clamp(value.turretX, -1, 1)
		result.turretY = math.clamp(value.turretY, -1, 1)
	elseif mode == "World" then
		if typeof(value.aim) ~= "Vector3" or not finite(value.aim.X)
			or not finite(value.aim.Y) or not finite(value.aim.Z) then return nil end
		result.aimMode = "World"
		result.aim = Vector3.new(value.aim.X, 0, value.aim.Z)
	else
		return nil
	end
	return result
end
return Command

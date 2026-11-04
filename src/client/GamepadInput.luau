local UIS = game:GetService("UserInputService")
local Command = require(game.ReplicatedStorage.Shared.InputCommand)
local Analog = require(script.Parent.Analog)
local Gamepad = {}
Gamepad.__index = Gamepad
function Gamepad.new()
	local self = setmetatable({ active = false, drive = Vector2.zero, turret = Vector2.zero, fire = false }, Gamepad)
	local function update(input)
		if not self.active or input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then self.drive = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then self.turret = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then self.fire = input.Position.Z > 0.2 end
	end
	UIS.InputChanged:Connect(update)
	UIS.InputBegan:Connect(function(input, processed) if not processed then update(input) end end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.ButtonR2 then self.fire = false
			elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then self.drive = Vector2.zero
			elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then self.turret = Vector2.zero end
		end
	end)
	UIS.GamepadDisconnected:Connect(function(gamepad) if gamepad == Enum.UserInputType.Gamepad1 then self:reset() end end)
	return self
end
function Gamepad:reset() self.drive = Vector2.zero; self.turret = Vector2.zero; self.fire = false end
function Gamepad:setActive(active) self.active = active; self:reset() end
function Gamepad:sample()
	local command = Command.neutral()
	if not self.active then return command end
	local drive, turret = Analog.normalize(self.drive, 0.15), Analog.normalize(self.turret, 0.15)
	command.throttle = drive.Y; command.steer = -drive.X
	command.turretX = turret.X; command.turretY = turret.Y; command.fire = self.fire
	return command
end
return Gamepad

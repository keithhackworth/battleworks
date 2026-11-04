local UserInputService = game:GetService("UserInputService")
local Command = require(game.ReplicatedStorage.Shared.InputCommand)
local Provider = {}
Provider.__index = Provider
function Provider.new()
	local self = setmetatable({ held = {}, focused = true, active = false }, Provider)
	UserInputService.InputBegan:Connect(function(input, processed)
		if self.active and not processed then self.held[input.KeyCode] = true; self.held[input.UserInputType] = true end
	end)
	UserInputService.InputEnded:Connect(function(input)
		self.held[input.KeyCode] = nil; self.held[input.UserInputType] = nil
	end)
	UserInputService.WindowFocusReleased:Connect(function() self.held = {}; self.focused = false end)
	UserInputService.WindowFocused:Connect(function() self.focused = true end)
	UserInputService.TextBoxFocused:Connect(function() self.held = {} end)
	return self
end
function Provider:reset() self.held = {} end
function Provider:setActive(active)
	self.active = active; self:reset()
end
function Provider:sample(camera)
	local command = Command.neutral()
	if not self.active or not self.focused or UserInputService:GetFocusedTextBox() then return command end
	command.aimMode = "World"
	local function down(key) return if self.held[key] then 1 else 0 end
	command.throttle = down(Enum.KeyCode.W) - down(Enum.KeyCode.S)
	command.steer = down(Enum.KeyCode.A) - down(Enum.KeyCode.D)
	command.fire = self.held[Enum.UserInputType.MouseButton1] == true
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) > 0.001 then
		local distance = (3.6 - ray.Origin.Y) / ray.Direction.Y
		if distance > 0 then command.aim = ray.Origin + ray.Direction * distance end
	end
	return command
end
return Provider

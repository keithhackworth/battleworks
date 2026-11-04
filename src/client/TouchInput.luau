local UIS = game:GetService("UserInputService")
local Command = require(game.ReplicatedStorage.Shared.InputCommand)
local Analog = require(script.Parent.Analog)
local Touch = {}
Touch.__index = Touch
local function round(object)
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = object
end
local function widget(parent, name)
	local frame = Instance.new("Frame")
	frame.Name = name; frame.Active = true; frame.BackgroundColor3 = Color3.fromRGB(33, 45, 53)
	frame.BackgroundTransparency = 0.2; frame.AnchorPoint = Vector2.new(0.5, 1); frame.Parent = parent
	round(frame)
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(157, 188, 163); stroke.Thickness = 2; stroke.Parent = frame
	return frame
end
local function text(parent, value)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1)
	label.Text = value; label.TextColor3 = Color3.fromRGB(242, 242, 223)
	label.TextSize = 14; label.Font = Enum.Font.GothamBold; label.Parent = parent
	return label
end
function Touch.new(gui, options)
	local self = setmetatable({ active = false, captures = {}, sticks = {}, fireTouch = nil,
		deadZones = { Turret = (options and options.turretDeadZone) or 0.15,
			Drive = (options and options.driveDeadZone) or 0.15 } }, Touch)
	self.root = Instance.new("Frame")
	self.root.Name = "TouchControls"; self.root.BackgroundTransparency = 1
	self.root.Size = UDim2.fromScale(1, 1); self.root.Visible = false; self.root.Parent = gui
	for _, name in { "Turret", "Drive" } do
		local frame = widget(self.root, name)
		local title = text(frame, if name == "Turret" then "TURRET" else "DRIVE")
		title.Size = UDim2.new(1, 0, 0, 20); title.Position = UDim2.fromOffset(0, -24)
		local knob = widget(frame, "Knob"); knob.Active = false
		knob.AnchorPoint = Vector2.new(0.5, 0.5); knob.Size = UDim2.fromScale(0.4, 0.4)
		knob.Position = UDim2.fromScale(0.5, 0.5); knob.BackgroundColor3 = Color3.fromRGB(124, 159, 123)
		local stick = { frame = frame, knob = knob, value = Vector2.zero, touch = nil, name = name }
		self.sticks[name] = stick
		local function beginStick(input)
			if not self.active or input.UserInputType ~= Enum.UserInputType.Touch or stick.touch or self.captures[input] then return end
			local center = frame.AbsolutePosition + frame.AbsoluteSize / 2
			local point = Vector2.new(input.Position.X, input.Position.Y)
			if (point - center).Magnitude > frame.AbsoluteSize.X / 2 then return end
			stick.touch = input
			self:capture(input, stick)
			self:move(input)
		end
		frame.InputBegan:Connect(beginStick)
		knob.InputBegan:Connect(beginStick)
	end
	self.fire = widget(self.root, "Fire")
	self.fire.BackgroundColor3 = Color3.fromRGB(164, 65, 44)
	local fireLabel = text(self.fire, "FIRE")
	local function beginFire(input)
		if self.active and input.UserInputType == Enum.UserInputType.Touch and not self.fireTouch and not self.captures[input] then
			self.fireTouch = input; self:capture(input, "Fire")
			self.fire.BackgroundColor3 = Color3.fromRGB(245, 119, 59)
		end
	end
	self.fire.InputBegan:Connect(beginFire)
	fireLabel.InputBegan:Connect(beginFire)
	self.debug = text(self.root, "INPUT: Touch")
	self.debug.Name = "InputRelay"; self.debug.AnchorPoint = Vector2.new(0.5, 1)
	self.debug.BackgroundTransparency = 0.2; self.debug.BackgroundColor3 = Color3.fromRGB(20, 28, 33)
	self.debug.Font = Enum.Font.Code; self.debug.TextXAlignment = Enum.TextXAlignment.Left
	self.debug.TextYAlignment = Enum.TextYAlignment.Center
	UIS.TouchMoved:Connect(function(input) self:move(input) end)
	UIS.TouchEnded:Connect(function(input) self:release(input) end)
	self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:layout() end)
	self:layout()
	return self
end
function Touch:layout()
	-- Releasing on resize prevents held fingers jumping across a rotated layout.
	self:reset()
	local size = self.root.AbsoluteSize
	local diameter = math.max(1, math.min(170, size.X * 0.23, size.Y * 0.42))
	local fireSize = math.min(96, diameter * 0.72)
	for name, stick in self.sticks do
		stick.frame.Size = UDim2.fromOffset(diameter, diameter)
		stick.frame.Position = if name == "Turret" then UDim2.new(0, 16 + diameter / 2, 1, -16)
			else UDim2.new(1, -16 - diameter / 2, 1, -16)
	end
	self.fire.Size = UDim2.fromOffset(fireSize, fireSize)
	self.fire.Position = UDim2.new(0.5, 0, 1, -16)
	local debugHeight = math.max(1, math.min(116, size.Y - fireSize - 80))
	self.debug.Size = UDim2.fromOffset(math.min(194, math.max(1, size.X - 2 * diameter - 56)), debugHeight)
	self.debug.Position = UDim2.new(0.5, 0, 1, -fireSize - 26)
	self.debug.TextSize = math.min(16, debugHeight / 7)
end
function Touch:capture(input, owner)
	-- Each InputObject owns exactly one control; no global pointer state.
	local capture = { owner = owner }
	self.captures[input] = capture
	capture.connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			self:release(input)
		end
	end)
end
function Touch:move(input)
	local capture = self.captures[input]
	if not capture or capture.owner == "Fire" then return end
	local stick = capture.owner
	local radius = stick.frame.AbsoluteSize.X / 2
	if radius <= 0 then return end
	local point = Vector2.new(input.Position.X, input.Position.Y)
	local raw = (point - (stick.frame.AbsolutePosition + stick.frame.AbsoluteSize / 2)) / radius
	stick.value = Analog.normalize(raw, self.deadZones[stick.name])
	local clamped = if raw.Magnitude > 1 then raw.Unit else raw
	stick.knob.Position = UDim2.fromScale(0.5 + clamped.X * 0.3, 0.5 + clamped.Y * 0.3)
end
function Touch:release(input)
	local capture = self.captures[input]
	if not capture then return end
	capture.connection:Disconnect(); self.captures[input] = nil
	if capture.owner == "Fire" then
		self.fireTouch = nil; self.fire.BackgroundColor3 = Color3.fromRGB(164, 65, 44)
	else
		local stick = capture.owner
		stick.touch = nil; stick.value = Vector2.zero; stick.knob.Position = UDim2.fromScale(0.5, 0.5)
	end
end
function Touch:reset()
	local inputs = {}
	for input in self.captures do table.insert(inputs, input) end
	for _, input in inputs do self:release(input) end
end
function Touch:setActive(active)
	self:reset(); self.active = active; self.root.Visible = active
end
function Touch:sample()
	local command = Command.neutral()
	if self.active then
		local drive, turret = self.sticks.Drive.value, self.sticks.Turret.value
		command.throttle = -drive.Y; command.steer = -drive.X
		command.turretX = turret.X; command.turretY = -turret.Y
		command.fire = self.fireTouch ~= nil
	end
	return command
end
function Touch:showDebug(command, mode)
	self.debug.Text = string.format("INPUT: %s\nTHROTTLE:  %+.2f\nSTEERING:  %+.2f\nTURRET X:  %+.2f\nTURRET Y:  %+.2f\nFIRE:      %s",
		mode, command.throttle, command.steer, command.turretX, command.turretY, if command.fire then "TRUE" else "FALSE")
end
return Touch

-- Studio-only controls. All framing and tracking remain in BattlefieldCamera/CameraMath.
local UIS = game:GetService("UserInputService")
local Panel = {}
Panel.__index = Panel
local MIN_SIZE, MAX_SIZE = 25, 2000
local function label(parent, name, y, height)
	local item = Instance.new("TextLabel")
	item.Name = name; item.BackgroundTransparency = 1
	item.Position = UDim2.fromOffset(12, y); item.Size = UDim2.new(1, -24, 0, height)
	item.Font = Enum.Font.GothamMedium; item.TextSize = 13
	item.TextColor3 = Color3.fromRGB(237, 235, 218)
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end
function Panel.new(playerGui, controller)
	if not game:GetService("RunService"):IsStudio() then return nil end
	local self = setmetatable({ controller = controller, connections = {}, sliders = {} }, Panel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CameraTestPanel"; gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets; gui.DisplayOrder = 20
	gui.Parent = playerGui; self.gui = gui
	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"; toggle.Text = "Camera Tests (Studio)"
	toggle.Size = UDim2.fromOffset(190, 28); toggle.Position = UDim2.fromOffset(8, 50)
	toggle.Parent = gui; self.toggle = toggle
	local frame = Instance.new("ScrollingFrame")
	frame.Name = "Controls"; frame.Position = UDim2.fromOffset(8, 82)
	frame.Size = UDim2.new(1, -16, 1, -90)
	frame.CanvasSize = UDim2.fromOffset(0, 284); frame.ScrollBarThickness = 4
	frame.ClipsDescendants = true
	frame.BackgroundColor3 = Color3.fromRGB(24, 31, 35); frame.Active = true
	frame.Visible = false; frame.Parent = gui; self.frame = frame
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(310, 284); constraint.Parent = frame
	local function connect(event, callback)
		table.insert(self.connections, event:Connect(callback))
	end
	local function cancel() self.drag = nil end
	connect(toggle.Activated, function() frame.Visible = not frame.Visible; cancel() end)
	for index, axis in { "Width", "Depth" } do
		local y = (index - 1) * 62
		local text = label(frame, "Map" .. axis, y + 8, 20)
		local track = Instance.new("TextButton")
		track.Name = axis .. "Slider"; track.Text = ""; track.AutoButtonColor = false
		track.Position = UDim2.fromOffset(12, y + 34); track.Size = UDim2.new(1, -24, 0, 22)
		track.BackgroundColor3 = Color3.fromRGB(65, 75, 91); track.Parent = frame
		local thumb = Instance.new("Frame")
		thumb.Name = "Thumb"; thumb.Size = UDim2.new(0, 10, 1, 0)
		thumb.BackgroundColor3 = Color3.fromRGB(255, 153, 24); thumb.Parent = track
		local slider = { label = text, track = track, thumb = thumb, axis = index }
		self.sliders[index] = slider
		connect(track.InputBegan, function(input)
			if self.drag then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
			self.drag = { input = input, slider = slider }
			self:setFromPosition(slider, input.Position.X)
		end)
	end
	local reset = Instance.new("TextButton")
	reset.Name = "ResetToActualMap"; reset.Text = "Reset to Actual Map"
	reset.Position = UDim2.fromOffset(12, 132); reset.Size = UDim2.new(1, -24, 0, 28)
	reset.Parent = frame; self.reset = reset
	connect(reset.Activated, function() cancel(); controller:setMapSizeOverride(nil); self:refresh() end)
	local redraw = Instance.new("TextButton")
	redraw.Name = "RedrawMap"; redraw.Text = "Redraw Map (resets tanks)"
	redraw.Position = UDim2.fromOffset(12, 166); redraw.Size = UDim2.new(1, -24, 0, 28)
	redraw.Parent = frame; self.redraw = redraw
	connect(redraw.Activated, function() cancel(); controller:requestMapRedraw() end)
	self.status = label(frame, "CameraStatus", 202, 74)
	self.status.TextWrapped = true
	connect(UIS.InputChanged, function(input)
		local drag = self.drag
		if not drag then return end
		if input == drag.input or (drag.input.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement) then
			self:setFromPosition(drag.slider, input.Position.X)
		end
	end)
	connect(UIS.InputEnded, function(input)
		if self.drag and input == self.drag.input then cancel() end
	end)
	connect(UIS.WindowFocusReleased, cancel)
	connect(game:GetService("GuiService").MenuOpened, cancel)
	connect(gui:GetPropertyChangedSignal("AbsoluteSize"), cancel)
	self:refresh()
	return self
end
function Panel:setFromPosition(slider, x)
	local width = slider.track.AbsoluteSize.X
	if width <= 0 then return end
	local fraction = math.clamp((x - slider.track.AbsolutePosition.X) / width, 0, 1)
	local value = math.floor(MIN_SIZE + fraction * (MAX_SIZE - MIN_SIZE) + 0.5)
	local size = self.controller.mapSizeOverride or self.controller.config.MapSize
	self.controller:setMapSizeOverride(Vector2.new(if slider.axis == 1 then value else size.X,
		if slider.axis == 2 then value else size.Y))
	self:refresh()
end
function Panel:refresh()
	local controller = self.controller
	local size = controller.mapSizeOverride or controller.config.MapSize
	for index, slider in self.sliders do
		local value = if index == 1 then size.X else size.Y
		slider.label.Text = string.format("Map %s: %.0f studs", if index == 1 then "Width" else "Depth", value)
		local fraction = math.clamp((value - MIN_SIZE) / (MAX_SIZE - MIN_SIZE), 0, 1)
		slider.thumb.Position = UDim2.new(fraction, -10 * fraction, 0, 0)
	end
	local layout = controller.layout
	self.status.Text = string.format("%s | %s\nDistance: %s studs\nActive map: %.0f x %.0f",
		if controller.mapSizeOverride then "Simulated" else "Actual",
		if layout then (if layout.wholeMap then "Whole Map" else "Follow") else "Waiting",
		if layout then string.format("%.2f", layout.distance) else "--", size.X, size.Y)
end
function Panel:destroy()
	self.drag = nil
	for _, connection in self.connections do connection:Disconnect() end
	self.gui:Destroy()
end
return Panel

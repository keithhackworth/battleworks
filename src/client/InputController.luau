local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Command = require(game.ReplicatedStorage.Shared.InputCommand)
local Controller = {}
Controller.__index = Controller
local modes = { "Auto", "KeyboardMouse", "Touch", "Gamepad" }
function Controller.new(gui, onRelease)
	local self = setmetatable({ preference = "Auto", mode = nil, suspended = false, focused = true,
		menuOpen = false, onRelease = onRelease, hiddenTouchGuis = {}, controls = nil, restoreMovement = false }, Controller)
	self.providers = {
		KeyboardMouse = require(script.Parent.KeyboardMouseInput).new(),
		Touch = require(script.Parent.TouchInput).new(gui, { turretDeadZone = 0.15, driveDeadZone = 0.15 }),
		Gamepad = require(script.Parent.GamepadInput).new(),
	}
	local button = Instance.new("TextButton")
	button.Name = "InputMode"; button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -8, 0, 4); button.Size = UDim2.fromOffset(194, 40)
	button.BackgroundColor3 = Color3.fromRGB(44, 63, 67); button.TextColor3 = Color3.fromRGB(242, 242, 223)
	button.TextSize = 14; button.TextScaled = true; button.Selectable = true
	button.Font = Enum.Font.GothamMedium; button.Parent = gui
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize = 10; textLimit.MaxTextSize = 14; textLimit.Parent = button
	self.button = button
	button.Activated:Connect(function()
		local index = table.find(modes, self.preference)
		self:setPreference(modes[index % #modes + 1])
	end)
	UIS:GetPropertyChangedSignal("PreferredInput"):Connect(function() self:refreshMode() end)
	UIS.WindowFocusReleased:Connect(function() self.focused = false; self:refreshSuspension() end)
	UIS.WindowFocused:Connect(function() self.focused = true; self:refreshSuspension() end)
	UIS.TextBoxFocused:Connect(function() self:refreshSuspension() end)
	UIS.TextBoxFocusReleased:Connect(function() task.defer(function() self:refreshSuspension() end) end)
	GuiService.MenuOpened:Connect(function() self.menuOpen = true; self:refreshSuspension() end)
	GuiService.MenuClosed:Connect(function() self.menuOpen = false; self:refreshSuspension() end)
	local player = Players.LocalPlayer
	self.playerGui = player:WaitForChild("PlayerGui")
	self.playerGui.ChildAdded:Connect(function(child)
		if self.mode == "Touch" then self:hideDefaultTouch(child) end
	end)
	self:refreshMode()
	-- PlayerModule may arrive after our LocalScript. Never block tank startup on it.
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if not module then warn("BattleWorks: PlayerModule unavailable; default TouchGui is still suppressed in Touch mode"); return end
		local ok, controls = pcall(function() return require(module):GetControls() end)
		if ok then
			self.controls = controls
			if self.mode == "Touch" then self:disableDefaultMovement() end
		else
			warn("BattleWorks: could not access default movement controls", controls)
		end
	end)
	return self
end
function Controller:hideDefaultTouch(child)
	-- TouchGui contains the default thumbstick/jump controls, not Roblox menus/chat.
	if child.Name == "TouchGui" and child:IsA("ScreenGui") then
		if self.hiddenTouchGuis[child] == nil then self.hiddenTouchGuis[child] = child.Enabled end
		child.Enabled = false
	end
end
function Controller:disableDefaultMovement()
	if self.controls then
		self.restoreMovement = self.controls.controlsEnabled ~= false
		self.controls:Disable()
	end
	for _, child in self.playerGui:GetChildren() do self:hideDefaultTouch(child) end
end
function Controller:restoreDefaultMovement()
	if self.controls and self.restoreMovement then self.controls:Enable() end
	self.restoreMovement = false
	for gui, enabled in self.hiddenTouchGuis do
		if gui.Parent then gui.Enabled = enabled end
	end
	table.clear(self.hiddenTouchGuis)
end
function Controller:setPreference(preference)
	assert(table.find(modes, preference), "Unknown control preference")
	self.preference = preference
	-- Explicit mode changes release even when the resolved mode is unchanged.
	self:release()
	self:refreshMode()
end
function Controller:release()
	for _, provider in self.providers do provider:reset() end
	self.onRelease(Command.neutral())
end
function Controller:setExternalControl(enabled)
	self.externalControl=enabled==true
	self:refreshSuspension()
end
function Controller:refreshSuspension()
	local suspended = self.externalControl or not self.focused or self.menuOpen or UIS:GetFocusedTextBox() ~= nil
	if suspended ~= self.suspended then
		self.suspended = suspended
		self:release()
		for name, provider in self.providers do provider:setActive(name == self.mode and not suspended) end
	end
end
function Controller:refreshMode()
	local resolved = self.preference
	if resolved == "Auto" then
		if UIS.PreferredInput == Enum.PreferredInput.Touch then resolved = "Touch"
		elseif UIS.PreferredInput == Enum.PreferredInput.Gamepad then resolved = "Gamepad"
		else resolved = "KeyboardMouse" end
	end
	if resolved ~= self.mode then
		self:release()
		if self.mode == "Touch" then self:restoreDefaultMovement() end
		self.mode = resolved
		for name, provider in self.providers do provider:setActive(name == resolved and not self.suspended) end
		if resolved == "Touch" then self:disableDefaultMovement() end
	end
	self.button.Text = "Input: " .. self.preference .. (if self.preference == "Auto" then " / " .. self.mode else "") .. "  ›"
end
function Controller:sample(camera)
	local command = if self.suspended then Command.neutral() else self.providers[self.mode]:sample(camera)
	self.providers.Touch:showDebug(command, self.mode)
	return command
end
return Controller

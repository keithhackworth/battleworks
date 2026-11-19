local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local Actions=game:GetService("ContextActionService")
local Command = require(game.ReplicatedStorage.Shared.InputCommand)
local Controller = {}
Controller.__index = Controller
local modes = { "Auto", "KeyboardMouse", "Touch", "Gamepad" }
function Controller.new(gui, onRelease)
	local self = setmetatable({ preference = "Auto", mode = nil, suspended = false, focused = true,
		menuOpen = false, onRelease = onRelease, hiddenTouchGuis = {}, controls = nil, restoreMovement = false, textEntryOwners = {} }, Controller)
	self.providers = {
		KeyboardMouse = require(script.Parent.KeyboardMouseInput).new(),
		Touch = require(script.Parent.TouchInput).new(gui, { turretDeadZone = 0.15, driveDeadZone = 0.15 }),
		Gamepad = require(script.Parent.GamepadInput).new(),
	}
 self.mouseView=require(script.Parent.MouseAimView).new(gui,function(mode)self:setMouseMode(mode)end,function(blocked)
  self.providers.KeyboardMouse:setUIBlocked(blocked)
  self.onRelease(Command.neutral())
 end)
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
  if self.textEntryActive or self.characterControl==false or (self.mode == "Touch" and not self.characterControl) then self:hideDefaultTouch(child) end
	end)
	self:refreshMode()
	-- PlayerModule may arrive after our LocalScript. Never block tank startup on it.
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if not module then warn("BattleWorks: PlayerModule unavailable; default TouchGui is still suppressed in Touch mode"); return end
		local ok, controls = pcall(function() return require(module):GetControls() end)
		if ok then
			self.controls = controls
			if self.textEntryActive or self.characterControl==false or (self.mode == "Touch" and not self.characterControl) then self:disableDefaultMovement() end
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
		if not self.movementDisabled then self.restoreMovement = self.controls.controlsEnabled ~= false;self.movementDisabled=true end
		self.controls:Disable()
	end
	for _, child in self.playerGui:GetChildren() do self:hideDefaultTouch(child) end
end
function Controller:restoreDefaultMovement()
	if self.controls and self.restoreMovement then self.controls:Enable() end
	self.restoreMovement = false;self.movementDisabled=false
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
function Controller:setMouseMode(mode)
 self:release();self.providers.KeyboardMouse:setMode(mode);self.mouseView:select(mode)
end
function Controller:release()
	for _, provider in self.providers do provider:reset() end
	self.onRelease(Command.neutral())
end
function Controller:setCharacterControl(enabled)
 self.characterControl=enabled==true
 if self.characterControl and not self.textEntryActive then self:restoreDefaultMovement()else self:disableDefaultMovement()end
 self:setExternalControl(self.characterControl)
end
function Controller:setExternalControl(enabled)
	self.externalControl=enabled==true
	self:refreshSuspension()
end
function Controller:refreshSuspension()
	local suspended = self.textEntryActive or self.externalControl or not self.focused or self.menuOpen or UIS:GetFocusedTextBox() ~= nil
	if suspended ~= self.suspended then
		self.suspended = suspended
  if suspended and self.mouseView then self.mouseView:open(false)end
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
		if self.mode == "Touch" and not self.textEntryActive then self:restoreDefaultMovement() end
		self.mode = resolved
		for name, provider in self.providers do provider:setActive(name == resolved and not self.suspended) end
		if self.textEntryActive or self.characterControl==false or (resolved == "Touch" and not self.characterControl) then self:disableDefaultMovement() end
	end
 self.mouseView:setVisible(resolved=="KeyboardMouse")
	self.button.Text = "Input: " .. self.preference .. (if self.preference == "Auto" then " / " .. self.mode else "") .. "  ›"
end
-- Shared modal focus bridge, including native chat fields in CoreGui which
-- need not appear in UserInputService:GetFocusedTextBox(). No aim-mode changes.
function Controller:setTextEntryFocus(owner,focused)
 local was=self.textEntryActive==true
 self.textEntryOwners[owner]=if focused then true else nil
 self.textEntryActive=next(self.textEntryOwners)~=nil
 if was==self.textEntryActive then return end
 self:release()
 if self.textEntryActive then
  self.promptService=game:GetService("ProximityPromptService")
  if self.promptService then self.savedPromptEnabled=self.promptService.Enabled;self.promptService.Enabled=false end
  self:disableDefaultMovement()
 elseif self.characterControl==true or (self.characterControl==nil and self.mode~="Touch")then self:restoreDefaultMovement()end
 if not self.textEntryActive and self.promptService then self.promptService.Enabled=self.savedPromptEnabled;self.promptService=nil end
 self:refreshSuspension()
end
function Controller:bindTextEntry(name,callbacks)
 local action="BattleWorksTextEntry_"..name
 Actions:BindActionAtPriority(action,function(_,state,input)
  if state~=Enum.UserInputState.Begin or not callbacks.enabled()or not self.focused or self.menuOpen then return Enum.ContextActionResult.Pass end
  if input.KeyCode==Enum.KeyCode.Escape then
   if callbacks.focused()then callbacks.cancel()end
  elseif not UIS:GetFocusedTextBox()and not callbacks.focused()then callbacks.open()end
  -- Roblox owns focus, sending and cancellation for the promoted TextBox.
  -- Opening happens before the native Return hotkey; never swallow that key.
  return Enum.ContextActionResult.Pass
 end,false,3000,Enum.KeyCode.Return,Enum.KeyCode.KeypadEnter,Enum.KeyCode.Escape)
 return function()Actions:UnbindAction(action);self:setTextEntryFocus(name,false)end
end
function Controller:sample(camera,context,dt)
	local command = if self.suspended then Command.neutral() else self.providers[self.mode]:sample(camera,context,dt)
 self.mouseView:update(self.providers.KeyboardMouse,self.mode=="KeyboardMouse"and not self.suspended)
	self.providers.Touch:showDebug(command, self.mode)
	return command
end
return Controller

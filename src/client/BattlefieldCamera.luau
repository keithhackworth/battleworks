local GuiService = game:GetService("GuiService")
local Math = require(script.Parent.CameraMath)
local TestPanel = require(script.Parent.CameraTestPanel)
local DefaultConfig = require(script.Parent.BattlefieldCameraConfig)
local Battlefield = {}
Battlefield.__index = Battlefield
function Battlefield.new(playerGui, config)
	local self = setmetatable({ config = config or DefaultConfig }, Battlefield)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BattlefieldCameraBars"; gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None; gui.ClipToDeviceSafeArea = false
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.DisplayOrder = -10 -- HUD and touch controls stay above masks and remain usable
	gui.Parent = playerGui
	self.gui, self.bars = gui, {}
	if game:GetService("RunService"):IsStudio() then
		gui:SetAttribute("DebugEnabled", false)
		gui:SetAttribute("PauseCamera", false)
		gui:SetAttribute("HideMasks", false)
	end
	for i = 1, 4 do
		local bar = Instance.new("Frame")
		bar.Name = "Mask" .. i; bar.BorderSizePixel = 0; bar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		bar.Active = true -- starting a mouse click on a bar must not start firing
		bar.Parent = gui; self.bars[i] = bar
	end
	self.testPanel = TestPanel.new(playerGui, self)
	return self
end
-- Client-local Studio override. Never mutate frozen tuning or actual arena Instances.
function Battlefield:setMapSizeOverride(size)
	if not game:GetService("RunService"):IsStudio() then return false end
	if size ~= nil then
		if typeof(size) ~= "Vector2" then return false end
		for _, value in { size.X, size.Y } do
			if value ~= value or value <= 0 or value == math.huge then return false end
		end
	end
	self.mapSizeOverride = size
	self.layoutKey = nil -- next render uses the same production layout calculation
	return true
end
function Battlefield:requestMapRedraw()
	if not game:GetService("RunService"):IsStudio() or not self.redrawMap then return false end
	self.redrawMap(self.mapSizeOverride or self.config.MapSize)
	return true
end
function Battlefield:setActualMapSize(size)
	if typeof(size) ~= "Vector2" then return false end
	for _, value in {size.X,size.Y} do
		if value ~= value or value < 25 or value > 2000 or value % 1 ~= 0 then return false end
	end
	self.config = table.clone(self.config); self.config.MapSize = size
	self.mapSizeOverride = nil; self.layoutKey = nil; self.focus = nil; self.lastState = nil
	if self.testPanel then self.testPanel:refresh() end
	return true
end
function Battlefield:observe(state)
	if not state then self.lastState = nil; return false end
	local snap = Math.shouldSnap(self.lastState, state, self.config.SnapDistance)
	self.lastState = state
	return snap
end
function Battlefield:update(camera, _dt, state)
	-- Only Studio may bypass ownership/masks. Live clients retain fixed policy.
	local studio = game:GetService("RunService"):IsStudio()
	self.gui.Enabled = not (studio and self.gui:GetAttribute("HideMasks") == true)
	if studio and self.gui:GetAttribute("PauseCamera") == true then
		return -- no CFrame, Focus, FOV or CameraType writes while paused
	end
	local deviceViewport = camera.ViewportSize
	if deviceViewport.X <= 1 or deviceViewport.Y <= 1 then return end
	-- Use device cutouts, not the top-bar UI reservation: reserving that
	-- space symmetrically needlessly shrinks short Studio battlefield windows.
	-- GetInsetArea uses core-safe coordinates. Differences convert safe margins
	-- to full-screen pixels; symmetric padding preserves the optical center.
	local safe = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
	local full = GuiService:GetInsetArea(Enum.ScreenInsets.None)
	-- Camera.ViewportSize excludes device cutouts, while FieldOfView describes
	-- the fullscreen render area. Use the full inset rectangle for projection
	-- and masks, not the smaller device-safe ViewportSize on notched phones.
	local viewport = full.Max - full.Min
	local padding = Vector2.new(math.max(0, safe.Min.X - full.Min.X, full.Max.X - safe.Max.X),
		math.max(0, safe.Min.Y - full.Min.Y, full.Max.Y - safe.Max.Y))
	local key = string.format("%.3f:%.3f:%.3f:%.3f:%.3f:%.3f", viewport.X, viewport.Y, padding.X, padding.Y, deviceViewport.X, deviceViewport.Y)
	if key ~= self.layoutKey or camera ~= self.camera then
		local config = self.config
		if studio and self.mapSizeOverride then
			config = table.clone(config)
			config.MapSize = self.mapSizeOverride
		end
		local layout = Math.layout(viewport, config, padding)
		if not layout then return end -- ViewportSize can be zero during camera startup
		self.layout, self.layoutKey, self.camera = layout, key, camera
		-- ProjectionType is a newer Studio feature. Classic clients already use
		-- perspective; do not require an orthographic-camera beta to play.
		pcall(function() camera.ProjectionType = Enum.ProjectionType.Perspective end)
		local w = layout.lens
		local rectangles = {
			{ 0, 0, viewport.X, w.y }, { 0, w.y + w.height, viewport.X, viewport.Y - w.y - w.height },
			{ 0, w.y, w.x, w.height }, { w.x + w.width, w.y, viewport.X - w.x - w.width, w.height },
		}
		for i, rect in rectangles do
			self.bars[i].Position = UDim2.fromOffset(rect[1], rect[2])
			self.bars[i].Size = UDim2.fromOffset(math.max(0, rect[3]), math.max(0, rect[4]))
		end
	end
	local layout = self.layout
	local tank = if state then state.position else (self.focus or layout.map.center)
	self.focus, self.edgeOverflow = Math.track(layout, tank, self.focus)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
	camera.FieldOfView = layout.lens.fov
	camera.CFrame = CFrame.lookAt(self.focus - layout.basis.forward * layout.distance, self.focus, Vector3.new(0, 1, 0))
	camera.Focus = CFrame.new(self.focus)
	if self.testPanel then self.testPanel:refresh() end
end
function Battlefield:destroy()
	if self.testPanel then self.testPanel:destroy() end
	self.gui:Destroy()
end
return Battlefield

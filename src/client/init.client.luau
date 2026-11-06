local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local network = game.ReplicatedStorage:WaitForChild("TankNetwork")
local input = network:WaitForChild("Input")
local snapshot = network:WaitForChild("Snapshot")
local shot = network:WaitForChild("Shot")
local prepareShot = network:WaitForChild("PrepareShot")
local InputController = require(script.InputController)
local Renderer = require(script.TankRenderer)
local BattlefieldCamera = require(script.BattlefieldCamera)
local CameraDebug = require(script.CameraDebug)
local states, renderers = {}, {}
local player = Players.LocalPlayer
local battlefieldCamera = BattlefieldCamera.new(player:WaitForChild("PlayerGui"))
if RunService:IsStudio() then
	local redraw = network:WaitForChild("RedrawMap")
	battlefieldCamera.redrawMap = function(size) redraw:FireServer(size) end
	local arena = workspace:WaitForChild("Arena")
	local function syncMap()
		local width, depth = arena:GetAttribute("MapWidth"), arena:GetAttribute("MapDepth")
		if width and depth then battlefieldCamera:setActualMapSize(Vector2.new(width,depth)) end
	end
	arena:GetAttributeChangedSignal("MapRevision"):Connect(syncMap)
	syncMap()
end
local gui = Instance.new("ScreenGui")
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.Name = "TankHUD"; gui.ResetOnSpawn = false; gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -210, 0, 44); label.BackgroundColor3 = Color3.fromRGB(24, 31, 35)
label.BackgroundTransparency = 0.15; label.TextColor3 = Color3.fromRGB(237, 235, 218)
label.Font = Enum.Font.GothamMedium; label.TextSize = 14; label.TextWrapped = true; label.Parent = gui
label.Text = "BATTLEWORKS  /  Connecting to tank server…"
local controller = InputController.new(gui, function(command) input:FireServer(command) end)
snapshot.OnClientEvent:Connect(function(nextStates)
	states = nextStates
	for id, renderer in renderers do
		if not states[id] then renderer:destroy(); renderers[id] = nil end
	end
	for id in states do
		if not renderers[id] then renderers[id] = Renderer.new(id) end
	end
	local ownId = tostring(player.UserId)
	if battlefieldCamera:observe(states[ownId]) and renderers[ownId] then
		renderers[ownId]:resetPose(states[ownId])
	end
end)
prepareShot.OnClientEvent:Connect(function(id)
	local renderer = renderers[tostring(id)]
	if renderer then renderer:fire() end
end)
shot.OnClientEvent:Connect(function(_, origin)
	Renderer.shot(origin)
end)
local elapsed, debugElapsed = 0, 0
RunService:BindToRenderStep("BattleWorksFrame", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	for id, state in states do renderers[id]:update(state, dt) end
	local own = states[tostring(player.UserId)]
	battlefieldCamera:update(camera, dt, own)
	if RunService:IsStudio() and battlefieldCamera.gui:GetAttribute("DebugEnabled") == true then
		debugElapsed += dt
		if debugElapsed >= 2 then
			debugElapsed = 0
			CameraDebug.report(camera, own, battlefieldCamera.layout, battlefieldCamera.gui, workspace, tostring(player.UserId))
			print("[BattleWorks insets] None=", game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.None),
				"DeviceSafe=", game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets),
				"CoreUI=", game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets))
		end
	else debugElapsed = 0 end
	if own then
		label.Text = string.format("BATTLEWORKS  /  HP %d  /  %s", own.health,
			if own.health <= 0 then "Respawning…" elseif own.cooldown > 0 then "Reloading" else "Ready")
	end
	local command = controller:sample(camera)
	elapsed += dt
	if elapsed >= 1 / 30 then
		elapsed %= 1 / 30
		input:FireServer(command)
	end
end)

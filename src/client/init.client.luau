local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local network = game.ReplicatedStorage:WaitForChild("TankNetwork")
local input = network:WaitForChild("Input")
local snapshot = network:WaitForChild("Snapshot")
local shot = network:WaitForChild("Shot")
local InputController = require(script.InputController)
local Renderer = require(script.TankRenderer)
local states, renderers = {}, {}
local player = Players.LocalPlayer
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
end)
shot.OnClientEvent:Connect(function(id, origin, endpoint)
	local renderer = renderers[tostring(id)]
	if renderer then renderer.recoil = 1 end
	Renderer.shot(origin, endpoint)
end)
local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	for id, state in states do renderers[id]:update(state, dt) end
	local own = states[tostring(player.UserId)]
	if own then
		camera.CameraType = Enum.CameraType.Scriptable
		local focus = renderers[tostring(player.UserId)].position
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, 68, 48), focus)
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

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local network = game.ReplicatedStorage:WaitForChild("TankNetwork")
local input = network:WaitForChild("Input")
local snapshot = network:WaitForChild("Snapshot")
local shot = network:WaitForChild("Shot")
local selectTank = network:WaitForChild("SelectTank")
local prepareShot = network:WaitForChild("PrepareShot")
local bwRun,bwStop=network:WaitForChild("BWRun"),network:WaitForChild("BWStop")
local BWIDE = require(script.BWIDE)
local InputController = require(script.InputController)
local Renderer = require(script.TankRenderer)
local TankRenderers = require(script.TankRenderers)
local SpeedDebugHud = require(script.SpeedDebugHud)
local TankSelector = require(script.TankSelector)
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
local speedDebug=SpeedDebugHud.new(gui)
local controller = InputController.new(gui, function(command) input:FireServer(command) end)
local selector = TankSelector.new(gui,function(id)
	controller:release()
	selectTank:FireServer(id)
end)
local bwRequest=0
local ide=BWIDE.new(player:WaitForChild("PlayerGui"),function(source)
	controller:release(); bwRequest+=1
	bwRun:FireServer(source,bwRequest)
	return bwRequest
end,function()
	bwRequest+=1; bwStop:FireServer(bwRequest)
	return bwRequest
end)
snapshot.OnClientEvent:Connect(function(nextStates)
	states = nextStates
	TankRenderers.sync(renderers,states,Renderer.new)
	local ownId = tostring(player.UserId)
	local own=states[ownId]
	if own then bwRequest=math.max(bwRequest,own.bwRequestId or 0) end
	controller:setExternalControl(own~=nil and own.bwRunning==true)
	if battlefieldCamera:observe(states[ownId]) and renderers[ownId] then
		renderers[ownId]:resetPose(states[ownId])
	end
end)
prepareShot.OnClientEvent:Connect(function(id, tankType, generation)
	local renderer = renderers[tostring(id)]
	if renderer and renderer.tankType == (tankType or "Boomer") and renderer.generation == (generation or 0) then renderer:fire() end
end)
shot.OnClientEvent:Connect(function(id, origin, direction, tankType, generation, rock)
	local renderer = renderers[tostring(id)]
	if renderer and (generation or 0)<renderer.generation then return end
	local matches = renderer and renderer.tankType == (tankType or "Boomer") and renderer.generation == (generation or 0)
	if matches and renderer.tankType == "Rattler" then renderer:fire(rock) end
	if matches and renderer.position and renderer.muzzleFrame then
		-- Use the rendered barrel tip, including its bounce and recoil, so the
		-- sparks stay attached to the opening despite snapshot smoothing.
		if renderer.tankType == "Rattler" then
			direction = renderer.muzzleFrame.LookVector; origin = renderer.muzzleFrame.Position
		else
			direction = renderer.cannon.CFrame.RightVector
			origin = renderer.cannon.CFrame.Position + direction*3
		end
	end
	Renderer.shot(origin, direction, tankType)
end)
local elapsed, debugElapsed = 0, 0
RunService:BindToRenderStep("BattleWorksFrame", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	for id, state in states do renderers[id]:update(state, dt) end
	local own = states[tostring(player.UserId)]
	if speedDebug then speedDebug:update(own) end
	ide:update(own)
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
		selector:update(own)
		local status
		if own.health <= 0 then status = "Respawning…"
		elseif own.tankType == "Rattler" then
			status = if (own.weaponCooldown or 0)>0 then string.format("COOLING %.1fs",own.weaponCooldown)
				else string.format("HEAT %d%%%s",math.floor((own.heat or 0)/3*100),if own.firing then " / BRRR!" else "")
		else status = if own.cooldown>0 then "Reloading" else "Ready" end
		label.Text = string.format("%s / HP %d / %s",own.tankType or "Boomer",own.health,status)
	end
	local command = controller:sample(camera)
	elapsed += dt
	if elapsed >= 1 / 30 then
		elapsed %= 1 / 30
		input:FireServer(command)
	end
end)

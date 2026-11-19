-- Existing simulator wiring, hosted by the application shell or Royale client.
local BattleClient={}
function BattleClient.new(onMenu,options)
options=options or {}
local royale=options.royale==true
local controlEpoch,controlRevision=nil,-1
local driving=not royale
local active=false
local savedCamera
local self={}
local Components=require(game.ReplicatedStorage.Shared.VehicleComponents)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local network = game.ReplicatedStorage:WaitForChild("TankNetwork")
local input = network:WaitForChild("Input")
local snapshot = network:WaitForChild("Snapshot")
local shot = network:WaitForChild("Shot")
local selectTank = network:WaitForChild("SelectTank")
local prepareShot = network:WaitForChild("PrepareShot")
local bwRun,bwStop=network:WaitForChild("BWRun"),network:WaitForChild("BWStop")
local resetBattle=network:WaitForChild("ResetBattle")
local bwOutput=network:WaitForChild("BWOutput")
local bwHardware=network:WaitForChild("BWHardware")
local bwRuntimeState=network:WaitForChild("BWRuntimeState")
local BWIDE = require(script.Parent.BWIDE)
local InputController = require(script.Parent.InputController)
local Renderer = require(script.Parent.TankRenderer)
local TankRenderers = require(script.Parent.TankRenderers)
local SpeedDebugHud = require(script.Parent.SpeedDebugHud)
local TankSelector = require(script.Parent.TankSelector)
local BattlefieldCamera = require(script.Parent.BattlefieldCamera)
local CameraDebug = require(script.Parent.CameraDebug)
local states, renderers = {}, {}
local player = Players.LocalPlayer
local selectedId=if royale then nil else tostring(player.UserId)
local battleState={}
local battlefieldCamera = BattlefieldCamera.new(player:WaitForChild("PlayerGui"))
if RunService:IsStudio() then
 -- Team Test can pair a Studio client with a non-Studio cloud server.
 -- Optional development tools must never block snapshots/tank rendering.
 local function discoverRedraw(child)
  if child.Name=="RedrawMap" and child:IsA("RemoteEvent")then
   battlefieldCamera.redrawMap=function(size)child:FireServer(size)end
  end
 end
 network.ChildAdded:Connect(discoverRedraw)
 local redraw=network:FindFirstChild("RedrawMap")
 if redraw then discoverRedraw(redraw)end
end
	do
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
gui.Enabled=false
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -210, 0, 44); label.BackgroundColor3 = Color3.fromRGB(24, 31, 35)
label.BackgroundTransparency = 0.15; label.TextColor3 = Color3.fromRGB(237, 235, 218)
label.Font = Enum.Font.GothamMedium; label.TextSize = 14; label.TextWrapped = true; label.Parent = gui
label.Text = "BATTLEWORKS  /  Connecting to tank server…"
local speedDebug=SpeedDebugHud.new(gui)
local controller = InputController.new(gui, function(command) if active and driving then input:FireServer(command,selectedId,controlEpoch) end end)
controller:setExternalControl(true)
if royale then controller:setCharacterControl(true)end
local ide
local selector = TankSelector.new(gui,function(id)
    if not active or royale then return end
	if ide then ide:close() end
	controller:release(); controller:setExternalControl(true)
	selectTank:FireServer(id)
end)
local bwRequest=0
ide=BWIDE.new(player:WaitForChild("PlayerGui"),function(source)
    if not active or not driving then return bwRequest end
	controller:release(); bwRequest+=1
	bwRun:FireServer(source,bwRequest,selectedId,controlEpoch)
	return bwRequest
end,function()
    if not active or not driving then return bwRequest end
	bwRequest+=1; bwStop:FireServer(bwRequest,selectedId,controlEpoch)
	return bwRequest
end,function(configuration) if active and driving then bwHardware:FireServer(configuration,selectedId,controlEpoch) end end)
ide.gui.Enabled=false
bwRuntimeState.OnClientEvent:Connect(function(id,reading) if active and (not royale or (driving and id==selectedId and reading.controlEpoch==controlEpoch)) then ide:receiveRuntime(id,reading) end end)
local resetButton=Instance.new("TextButton")
resetButton.Name="ResetBattle"; resetButton.Text="Reset Battle"
resetButton.AnchorPoint=Vector2.new(1,0); resetButton.Position=UDim2.new(1,-8,0,204)
resetButton.Size=UDim2.fromOffset(194,28); resetButton.Font=Enum.Font.GothamMedium; resetButton.TextSize=14
resetButton.BackgroundColor3=Color3.fromRGB(153,62,39); resetButton.TextColor3=Color3.fromRGB(255,249,222)
resetButton.Selectable=true; resetButton.Parent=gui
resetButton.Activated:Connect(function() if active and not royale then controller:release(); resetBattle:FireServer() end end)
local menuButton=Instance.new("TextButton"); menuButton.Name="ReturnToMainMenu"; menuButton.Text=if royale then "Exit Tank (F / B)" else "Main Menu"
menuButton.AnchorPoint=Vector2.new(.5,0); menuButton.Position=UDim2.new(.5,0,0,50); menuButton.Size=UDim2.fromOffset(120,44)
menuButton.Font=Enum.Font.GothamMedium; menuButton.TextSize=14; menuButton.TextColor3=Color3.fromRGB(237,239,224)
menuButton.BackgroundColor3=Color3.fromRGB(32,47,52); menuButton.Selectable=true; menuButton.Parent=gui
menuButton.Activated:Connect(function() if active then onMenu() end end)
snapshot.OnClientEvent:Connect(function(nextStates,battles)
	states = nextStates
	battleState=(battles or {})[tostring(player.UserId)] or {}
 resetButton.Visible=not royale and not battleState.multiplayer
	if not royale then selectedId=battleState.selected or selectedId end
    if not active then return end
    TankRenderers.sync(renderers,states,Renderer.new)
	local ownId=selectedId
	local own=states[ownId]
 if royale and (not driving or not own or own.controlEpoch~=controlEpoch)then own=nil end
 if ownId then ide:bind(ownId)end
	if own then bwRequest=math.max(bwRequest,own.bwRequestId or 0) end
	controller:setExternalControl(not own or own.bwRunning==true or own.health<=0)
	if battlefieldCamera:observe(states[ownId]) and renderers[ownId] then
		renderers[ownId]:resetPose(states[ownId])
	end
end)
bwOutput.OnClientEvent:Connect(function(id,generation,requestId,reading,epoch)
	if active and (not royale or (driving and id==selectedId and epoch==controlEpoch)) then ide:receiveOutput(id,generation,requestId,reading) end
end)
prepareShot.OnClientEvent:Connect(function(id, tankType, generation, weaponId)
 if not active then return end
	local renderer = renderers[tostring(id)]
	if renderer and renderer.tankType == (tankType or "Boomer") and renderer.generation == (generation or 0) and (not weaponId or renderer.weaponId==weaponId) then renderer:fire() end
end)
shot.OnClientEvent:Connect(function(id, origin, direction, tankType, generation, rock, weaponId)
 if not active then return end
	local renderer = renderers[tostring(id)]
	if renderer and (generation or 0)<renderer.generation then return end
	local matches = renderer and renderer.tankType == (tankType or "Boomer") and renderer.generation == (generation or 0) and (not weaponId or renderer.weaponId==weaponId)
	if matches and renderer.gatling then renderer:fire(rock) end
	if matches and renderer.position and renderer.muzzleFrame then
		-- Use the rendered barrel tip, including its bounce and recoil, so the
		-- sparks stay attached to the opening despite snapshot smoothing.
		if renderer.gatling then
			direction = renderer.muzzleFrame.LookVector; origin = renderer.muzzleFrame.Position
		else
			direction = renderer.cannon.CFrame.RightVector
			origin = renderer.cannon.CFrame.Position + direction*3
		end
	end
	Renderer.shot(origin, direction, tankType,weaponId)
end)
local elapsed, debugElapsed = 0, 0
RunService:BindToRenderStep("BattleWorksFrame", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if not active then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	for id, state in states do renderers[id]:update(state, dt) end
	local own = states[selectedId]
 if royale and (not driving or not own or own.controlEpoch~=controlEpoch)then own=nil end
	if speedDebug then speedDebug:update(own) end
	ide:update(own)
	if not royale or driving then battlefieldCamera:update(camera, dt, own)end
	if RunService:IsStudio() and battlefieldCamera.gui:GetAttribute("DebugEnabled") == true then
		debugElapsed += dt
		if debugElapsed >= 2 then
			debugElapsed = 0
			CameraDebug.report(camera, own, battlefieldCamera.layout, battlefieldCamera.gui, workspace, selectedId)
			print("[BattleWorks insets] None=", game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.None),
				"DeviceSafe=", game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets),
				"CoreUI=", game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets))
		end
	else debugElapsed = 0 end
	if own then
		selector:update(own)
		local status
		if own.waitingForSpawn then status = "Waiting for a clear spawn…"
  elseif own.health <= 0 then status = if battleState.multiplayer then "WRECKED • Respawning…" else "WRECKED • Reset Battle to retry"
		elseif Components.forWeapon(own.tankType,own.weaponId).Weapon.Operation=="Heat" then
			status = if (own.weaponCooldown or 0)>0 then string.format("COOLING %.1fs",own.weaponCooldown)
				else string.format("HEAT %d%%%s",math.floor((own.heat or 0)/Components.forWeapon(own.tankType,own.weaponId).Weapon.MaxHeat*100),if own.firing then " / BRRR!" else "")
		else status = if own.cooldown>0 then "Reloading" else "Ready" end
		if own.immobilized then status..=string.format(" / RATTLED %.1fs",own.immobilizedRemaining or 0) end
		if own.smokeBurst then status..=" / SMOKE" end
		label.Text = string.format("%s / HP %d / %s",own.tankType or "Boomer",own.health,status)..(if battleState.winner=="Draw" then " / DRAW!" elseif battleState.winner then " / "..battleState.winner.." WINS!" else "")
	end
	local command = controller:sample(camera)
	elapsed += dt
	if elapsed >= 1 / 30 then
		elapsed %= 1 / 30
		if own and driving then input:FireServer(command,selectedId,controlEpoch) end
	end
end)

function self:setActive(enabled)
 if active==enabled then return end
 active=enabled
 gui.Enabled=enabled and driving; ide.gui.Enabled=enabled and driving
 battlefieldCamera.gui.Enabled=enabled and driving
 if battlefieldCamera.testPanel and battlefieldCamera.testPanel.gui then battlefieldCamera.testPanel.gui.Enabled=enabled and driving end
 if enabled then
  if royale then controller:setCharacterControl(not driving)end
  local camera=workspace.CurrentCamera
  if camera and not royale then savedCamera={camera=camera,CameraType=camera.CameraType,CameraSubject=camera.CameraSubject,CFrame=camera.CFrame,Focus=camera.Focus,FieldOfView=camera.FieldOfView,FieldOfViewMode=camera.FieldOfViewMode} end
  battlefieldCamera.layoutKey=nil; battlefieldCamera.lastState=nil; battlefieldCamera.focus=nil
  battlefieldCamera.gui:SetAttribute("PauseCamera",false)
  TankRenderers.sync(renderers,states,Renderer.new)
  local own=states[selectedId]
  controller:setExternalControl(not own or own.bwRunning==true or own.health<=0)
 else
  controller:setExternalControl(true); controller:release(); ide:close()
  local focused=game:GetService("UserInputService"):GetFocusedTextBox()
  if focused then focused:ReleaseFocus() end
  if battlefieldCamera.testPanel then
   battlefieldCamera.testPanel.drag=nil
   if battlefieldCamera.testPanel.frame then battlefieldCamera.testPanel.frame.Visible=false end
  end
  TankRenderers.sync(renderers,{},Renderer.new)
  states={}; battleState={}; selectedId=if royale then nil else tostring(player.UserId)
  if royale then driving=false;controlEpoch=nil;controller:setCharacterControl(false);controller:setExternalControl(true)end
  if savedCamera then
   local camera=savedCamera.camera
   camera.CameraType=savedCamera.CameraType; camera.CameraSubject=savedCamera.CameraSubject
   camera.CFrame=savedCamera.CFrame; camera.Focus=savedCamera.Focus; camera.FieldOfView=savedCamera.FieldOfView; camera.FieldOfViewMode=savedCamera.FieldOfViewMode
   savedCamera=nil
  end
 end
 elapsed=0; debugElapsed=0
end
local function restoreCharacterCamera()
 if savedCamera then
  local camera=savedCamera.camera
  camera.CameraType=savedCamera.CameraType;camera.CameraSubject=savedCamera.CameraSubject
  camera.CFrame=savedCamera.CFrame;camera.Focus=savedCamera.Focus;camera.FieldOfView=savedCamera.FieldOfView;camera.FieldOfViewMode=savedCamera.FieldOfViewMode
  savedCamera=nil
 end
 local camera=workspace.CurrentCamera
 local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 if camera then camera.CameraType=Enum.CameraType.Custom;if humanoid then camera.CameraSubject=humanoid end end
end
function self:setControl(reading)
 if not royale or type(reading)~="table" or type(reading.revision)~="number" or reading.revision~=reading.revision or reading.revision%1~=0 or reading.revision<1 or reading.revision<=controlRevision then return false end
 if reading.mode~="Tank" and reading.mode~="OnFoot" then return false end
 if reading.mode=="Tank" and (type(reading.selected)~="string" or type(reading.epoch)~="number" or reading.epoch~=reading.epoch or reading.epoch%1~=0 or reading.epoch<1)then return false end
 controlRevision=reading.revision
 controller:setExternalControl(true);controller:release();ide:close()
 if driving then restoreCharacterCamera()end
 selectedId=if reading.mode=="Tank" then reading.selected else nil
 controlEpoch=if selectedId then reading.epoch else nil;driving=selectedId~=nil
 controller:setCharacterControl(not driving)
 if driving then
  local camera=workspace.CurrentCamera
  if camera then savedCamera={camera=camera,CameraType=camera.CameraType,CameraSubject=camera.CameraSubject,CFrame=camera.CFrame,Focus=camera.Focus,FieldOfView=camera.FieldOfView,FieldOfViewMode=camera.FieldOfViewMode}end
  ide:bind(selectedId) -- request IDs stay monotonic across this client's leases
  battlefieldCamera.layoutKey=nil;battlefieldCamera.lastState=nil;battlefieldCamera.focus=nil
 else restoreCharacterCamera()end
 gui.Enabled=active and driving;ide.gui.Enabled=active and driving;battlefieldCamera.gui.Enabled=active and driving
 if battlefieldCamera.testPanel and battlefieldCamera.testPanel.gui then battlefieldCamera.testPanel.gui.Enabled=active and driving end
 local own=states[selectedId]
 controller:setExternalControl(not driving or not own or own.controlEpoch~=controlEpoch or own.bwRunning==true or own.health<=0)
 elapsed=0
 return true
end
if royale then selector.frame.Visible=false;resetButton.Visible=false end
-- Constructors create persistent widgets; shell entry starts with all gameplay
-- layers hidden and all providers suspended, including delayed PlayerModule setup.
battlefieldCamera.gui.Enabled=false
if battlefieldCamera.testPanel and battlefieldCamera.testPanel.gui then battlefieldCamera.testPanel.gui.Enabled=false end
return self
end
return BattleClient

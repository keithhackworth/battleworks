-- One simulator client, with the existing shell for leaving/rejoining the arena.
local Client={}
function Client.start()
 local Players=game:GetService("Players")
 local UIS=game:GetService("UserInputService")
 local Actions=game:GetService("ContextActionService")
 local GuiService=game:GetService("GuiService")
 local network=game.ReplicatedStorage:WaitForChild("TankNetwork")
 local remote=network:WaitForChild("RoyaleControl")
 local sprintRemote=network:WaitForChild("RoyaleSprint")
 require(script.Parent.PlaygroundPresentation).start(workspace:WaitForChild("Arena"))
 local reading,shell,gameplay
 local session=require(script.Parent.shell.GameplaySession).new(function(action,requestId)
  remote:FireServer(if action=="Enter"then "Join"else "Menu",requestId,reading and reading.selected,reading and reading.epoch)
 end)
 session.mode="Battle" -- first admission is automatic; tank leases still require acknowledgments
 local function request(action)
  session.requestId+=1;remote:FireServer(action,session.requestId,reading and reading.selected,reading and reading.epoch)
 end
 local battle=require(script.Parent.BattleClient).new(function()request("Exit")end,{royale=true})
 local playerGui=Players.LocalPlayer:WaitForChild("PlayerGui")
 local gui=Instance.new("ScreenGui");gui.Name="RoyaleOnFoot";gui.ResetOnSpawn=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.Parent=playerGui
 local hint=Instance.new("TextLabel");hint.Size=UDim2.new(1,-40,0,48);hint.Position=UDim2.new(0,20,0,8);hint.BackgroundColor3=Color3.fromRGB(24,31,35);hint.BackgroundTransparency=.2;hint.TextColor3=Color3.fromRGB(237,239,224);hint.TextSize=16;hint.TextWrapped=true;hint.Font=Enum.Font.GothamMedium;hint.Parent=gui
 hint.Text="THE PLAYGROUND • Hold Shift to run • E / controller X / touch prompt to enter a nearby tank"
 local chat=require(script.Parent.PlaygroundChat).new(playerGui,battle.inputController,"BattleRoyale")
 local navigation=Instance.new("ScreenGui");navigation.Name="RoyaleNavigation";navigation.ResetOnSpawn=false;navigation.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;navigation.Parent=playerGui
 gameplay={}
 local shifts={}
 local function stopSprint()
  if next(shifts)==nil then return end
  table.clear(shifts)
  if reading and reading.mode=="OnFoot" then sprintRemote:FireServer(false,reading.revision)end
 end
 function gameplay:setActive(enabled)
  if not enabled then stopSprint()end
  battle:setActive(enabled)
  chat:setActive(enabled)
  navigation.Enabled=enabled;gui.Enabled=enabled and (not reading or reading.mode=="OnFoot")
 end
 local function garageRequest(...)
 local garage=network:FindFirstChild("GarageConfiguration")
 if not garage then return {ok=false,message="Garage unavailable in this session."} end
 return garage:InvokeServer(...)
end
local function worldRequest(action,payload)
  local worlds=network:FindFirstChild("PlayerWorlds");assert(worlds,"Saved worlds are unavailable in this build")
  return worlds:InvokeServer(action,payload)
 end
 local function ensureShell()
  if not shell then
   shell=require(script.Parent.shell.ApplicationShell).new(playerGui,workspace:WaitForChild("Arena"),session,gameplay,nil,function()return game.ReplicatedStorage:FindFirstChild("BattleWorksEditorAssets")end,worldRequest,{royale=true,garageRequest=garageRequest})
  end
  return shell
 end
 local function home()
  gameplay:setActive(false)
  session:leave()
  ensureShell().home()
 end
 local menu=Instance.new("TextButton");menu.Name="RoyaleMainMenu";menu.Text="Main Menu";menu.Position=UDim2.fromOffset(12,60);menu.Size=UDim2.fromOffset(120,44);menu.BackgroundColor3=Color3.fromRGB(32,47,52);menu.TextColor3=Color3.fromRGB(237,239,224);menu.Font=Enum.Font.GothamMedium;menu.TextSize=15;menu.Parent=navigation
 local execution=network:FindFirstChild("PlaygroundBWExecution")
 if execution then
  local toggle=Instance.new("TextButton")
  toggle.Name="PlaygroundBWExecution";toggle.Position=UDim2.fromOffset(12,108);toggle.Size=UDim2.fromOffset(120,44)
  toggle.BackgroundColor3=menu.BackgroundColor3;toggle.TextColor3=menu.TextColor3;toggle.Font=menu.Font;toggle.TextSize=14
  toggle.Selectable=true;toggle.Parent=navigation
  local function refresh()
   toggle.Text="BW Execution: "..(if execution:GetAttribute("Enabled") then "ON" else "OFF")
  end
  execution:GetAttributeChangedSignal("Enabled"):Connect(refresh)
  toggle.Activated:Connect(function() execution:FireServer(not execution:GetAttribute("Enabled")) end)
  refresh()
 end
 local scoreboard=Instance.new("Frame")
 scoreboard.Name="PlaygroundScoreboard";scoreboard.Position=UDim2.fromOffset(12,if execution then 158 else 110)
 scoreboard.Size=UDim2.new(0,246,.25,0);scoreboard.BackgroundColor3=menu.BackgroundColor3
 scoreboard.BackgroundTransparency=.15;scoreboard.BorderSizePixel=0;scoreboard.Visible=false;scoreboard.Parent=navigation
 local scoreSize=Instance.new("UISizeConstraint");scoreSize.MaxSize=Vector2.new(246,146);scoreSize.Parent=scoreboard
 local function scoreLabel(parent,name)
  local label=Instance.new("TextLabel")
  label.Name=name;label.BackgroundTransparency=1;label.Font=Enum.Font.Code;label.TextSize=12
  label.TextColor3=menu.TextColor3;label.TextXAlignment=Enum.TextXAlignment.Left
  label.TextYAlignment=Enum.TextYAlignment.Top;label.Parent=parent
  return label
 end
 local heading=scoreLabel(scoreboard,"ScoreboardHeading")
 heading.Position=UDim2.fromOffset(8,5);heading.Size=UDim2.new(1,-16,0,18)
 heading.Text=string.format("%-17s %5s %6s","Tank / Player","Kills","Deaths")
 local scroll=Instance.new("ScrollingFrame")
 scroll.Position=UDim2.fromOffset(0,24);scroll.Size=UDim2.new(1,0,1,-24)
 scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=4
 scroll.ScrollingDirection=Enum.ScrollingDirection.Y;scroll.Parent=scoreboard
 local scores=scoreLabel(scroll,"ScoreboardRows")
 scores.Position=UDim2.fromOffset(8,0)
 local scoreRevision
 local function showScores(battles,revision,tankScores)
  if revision==nil or revision==scoreRevision or not battles then return end
  scoreRevision=revision
  local roster={}
  for _,score in tankScores or {} do table.insert(roster,score)end
  for _,battleState in battles do
   local score=battleState.score
   if score then table.insert(roster,{name="@"..score.name,kills=score.kills,deaths=score.deaths})end
  end
  table.sort(roster,function(a,b)
   if a.kills~=b.kills then return a.kills>b.kills end
   if a.deaths~=b.deaths then return a.deaths<b.deaths end
   return a.name<b.name
  end)
  local lines={}
  for i,score in roster do lines[i]=string.format("%-17s %5d %6d",score.name:sub(1,17),score.kills,score.deaths)end
  scores.Text=table.concat(lines,"\n")
  local height=#lines*17+3
  scores.Size=UDim2.new(1,-16,0,height);scroll.CanvasSize=UDim2.fromOffset(0,height)
  scoreboard.Visible=#lines>0
 end
 local notice=Instance.new("TextLabel");notice.Name="RoyaleNotice";notice.Position=UDim2.fromOffset(144,60);notice.Size=UDim2.new(1,-164,0,60);notice.BackgroundColor3=Color3.fromRGB(32,47,52);notice.TextColor3=Color3.fromRGB(255,224,163);notice.Font=Enum.Font.GothamMedium;notice.TextSize=16;notice.TextWrapped=true;notice.Visible=false;notice.Parent=navigation
 local modeSwitch=Instance.new("TextButton");modeSwitch.Name="PlaygroundControlMode";modeSwitch.AnchorPoint=Vector2.new(.5,1);modeSwitch.Position=UDim2.new(.5,0,1,-12);modeSwitch.Size=UDim2.new(.42,0,0,56);modeSwitch.BackgroundColor3=Color3.fromRGB(32,81,69);modeSwitch.TextColor3=Color3.fromRGB(245,246,229);modeSwitch.Font=Enum.Font.GothamBold;modeSwitch.TextSize=18;modeSwitch.TextWrapped=true;modeSwitch.Visible=false;modeSwitch.Parent=navigation
 local currentMode="Manual"
 local inConfigurationZone=false
 local modePending=false
 local function showMode(mode,zone)
  currentMode=mode or "Manual"
  inConfigurationZone=zone~=nil
  modeSwitch.Visible=reading~=nil and reading.mode=="Tank"and reading.personality~=nil
  modeSwitch.Text=(if currentMode=="Auto"then "AUTO  ●  |  Manual"else "Auto  |  ●  MANUAL").."\n"..(reading and reading.personality or "")
  if inConfigurationZone then modeSwitch.Text="MANUAL\nDrive clear for Auto" end
  modeSwitch.BackgroundColor3=if currentMode=="Auto"then Color3.fromRGB(37,96,64)else Color3.fromRGB(35,67,93)
 end
 modeSwitch.Activated:Connect(function()
  if modePending or inConfigurationZone or not reading or reading.mode~="Tank"or not reading.personality then return end
  modePending=true
  battle.inputController:release()
  request(if currentMode=="Auto"then "Manual"else "Auto")
 end)
 network:WaitForChild("Snapshot").OnClientEvent:Connect(function(states,battles,revision,tankScores)
  showScores(battles,revision,tankScores)
  local own=reading and reading.selected and states[reading.selected]
  if own and own.controlEpoch==reading.epoch then showMode(own.controlMode,own.configurationZone)end
 end)
 menu.Activated:Connect(home)
 gameplay:setActive(true)
 remote.OnClientEvent:Connect(function(nextReading)
  if type(nextReading)~="table" or type(nextReading.revision)~="number" or nextReading.revision~=nextReading.revision or (reading and nextReading.revision<=reading.revision)then return end
  local requestId=nextReading.requestId
  -- Shared request IDs fence canceled menu/join transitions independently of
  -- the tank's control lease and occupancy revision.
  if requestId~=session.requestId or (session.mode=="Menu" and nextReading.mode~="Menu")then return end
  local control=nextReading
  if nextReading.mode=="Menu"then control=table.clone(nextReading);control.mode="OnFoot"end
  if not battle:setControl(control)then return end
  notice.Text=nextReading.message or "";notice.Visible=notice.Text~=""
  reading=nextReading
  if reading.mode~="OnFoot"then stopSprint()end
  modePending=false
  showMode(reading.controlMode)
  if not session:receive(requestId,nextReading.mode~="Menu",nextReading.message)then return end
  if nextReading.mode=="Menu"then gameplay:setActive(false)else gameplay:setActive(true)end
  gui.Enabled=nextReading.mode=="OnFoot";navigation.Enabled=nextReading.mode~="Menu"
 end)
 Actions:BindActionAtPriority("BattleWorksSprint",function(_,state,input)
  if state==Enum.UserInputState.Cancel then stopSprint();return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.End and shifts[input.KeyCode] then
   shifts[input.KeyCode]=nil
   if next(shifts)==nil and reading and reading.mode=="OnFoot" then sprintRemote:FireServer(false,reading.revision)end
   return Enum.ContextActionResult.Sink
  end
  local controls=battle.inputController
  if state~=Enum.UserInputState.Begin or not gui.Enabled or not reading or reading.mode~="OnFoot"
   or UIS:GetFocusedTextBox() or controls.textEntryActive or controls.menuOpen then return Enum.ContextActionResult.Pass end
  local wasSprinting=next(shifts)~=nil
  shifts[input.KeyCode]=true
  if not wasSprinting then sprintRemote:FireServer(true,reading.revision)end
  return Enum.ContextActionResult.Sink
 end,false,3000,Enum.KeyCode.LeftShift,Enum.KeyCode.RightShift)
 UIS.WindowFocusReleased:Connect(stopSprint)
 UIS.TextBoxFocused:Connect(stopSprint)
 GuiService.MenuOpened:Connect(stopSprint)
 Actions:BindAction("BattleWorksExitTank",function(_,state)
  if session.mode~="Battle" or not reading or not reading.selected or UIS:GetFocusedTextBox()or battle.inputController.textEntryActive then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then request("Exit")end
  return Enum.ContextActionResult.Sink
 end,false,Enum.KeyCode.F,Enum.KeyCode.ButtonB)
 request("Sync")
 return {battle=battle,request=request,gui=gui,navigation=navigation,chat=chat,session=session,home=home,getShell=function()return shell end,modeSwitch=modeSwitch}
end
return Client

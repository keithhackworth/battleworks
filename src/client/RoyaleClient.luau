-- One simulator client, with the existing shell for leaving/rejoining the arena.
local Client={}
function Client.start()
 local Players=game:GetService("Players")
 local UIS=game:GetService("UserInputService")
 local Actions=game:GetService("ContextActionService")
 local network=game.ReplicatedStorage:WaitForChild("TankNetwork")
 local remote=network:WaitForChild("RoyaleControl")
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
 hint.Text="THE PLAYGROUND • Approach a public tank • E / controller X / touch prompt to enter"
 local navigation=Instance.new("ScreenGui");navigation.Name="RoyaleNavigation";navigation.ResetOnSpawn=false;navigation.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;navigation.Parent=playerGui
 gameplay={}
 function gameplay:setActive(enabled)
  battle:setActive(enabled)
  navigation.Enabled=enabled;gui.Enabled=enabled and (not reading or reading.mode=="OnFoot")
 end
 local function worldRequest(action,payload)
  local worlds=network:FindFirstChild("PlayerWorlds");assert(worlds,"Saved worlds are unavailable in this build")
  return worlds:InvokeServer(action,payload)
 end
 local function ensureShell()
  if not shell then
   shell=require(script.Parent.shell.ApplicationShell).new(playerGui,workspace:WaitForChild("Arena"),session,gameplay,nil,function()return game.ReplicatedStorage:FindFirstChild("BattleWorksEditorAssets")end,worldRequest,{royale=true})
  end
  return shell
 end
 local function home()
  gameplay:setActive(false)
  session:leave()
  ensureShell().home()
 end
 local menu=Instance.new("TextButton");menu.Name="RoyaleMainMenu";menu.Text="Main Menu";menu.Position=UDim2.fromOffset(12,60);menu.Size=UDim2.fromOffset(120,44);menu.BackgroundColor3=Color3.fromRGB(32,47,52);menu.TextColor3=Color3.fromRGB(237,239,224);menu.Font=Enum.Font.GothamMedium;menu.TextSize=15;menu.Parent=navigation
 local notice=Instance.new("TextLabel");notice.Name="RoyaleNotice";notice.Position=UDim2.fromOffset(144,60);notice.Size=UDim2.new(1,-164,0,60);notice.BackgroundColor3=Color3.fromRGB(32,47,52);notice.TextColor3=Color3.fromRGB(255,224,163);notice.Font=Enum.Font.GothamMedium;notice.TextSize=16;notice.TextWrapped=true;notice.Visible=false;notice.Parent=navigation
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
  if not session:receive(requestId,nextReading.mode~="Menu",nextReading.message)then return end
  if nextReading.mode=="Menu"then gameplay:setActive(false)else gameplay:setActive(true)end
  gui.Enabled=nextReading.mode=="OnFoot";navigation.Enabled=nextReading.mode~="Menu"
 end)
 Actions:BindAction("BattleWorksExitTank",function(_,state)
  if session.mode~="Battle" or not reading or not reading.selected or UIS:GetFocusedTextBox()then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then request("Exit")end
  return Enum.ContextActionResult.Sink
 end,false,Enum.KeyCode.F,Enum.KeyCode.ButtonB)
 request("Sync")
 return {battle=battle,request=request,gui=gui,navigation=navigation,session=session,home=home,getShell=function()return shell end}
end
return Client

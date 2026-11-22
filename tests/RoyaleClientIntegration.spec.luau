-- Exercise the extracted production client with real input and BW UI modules.
-- Render geometry is replaced at its established factory boundary.
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local originalService=game.GetService
local savedNew=Instance.new
local created={}
Instance.new=function(class) local p=savedNew(class);table.insert(created,p);return p end
local function named(name)
 for _,p in created do if p.Name==name then return p end end
 error("Missing UI "..name)
end
local remotes={}
local requests={}
for _,name in {"RoyaleControl","RoyaleSprint","Input","Snapshot","Shot","SelectTank","PrepareShot","BWRun","BWStop","ResetBattle","BWOutput","BWHardware","BWRuntimeState"} do
 local remote={OnClientEvent=signal()}
 remote.FireServer=function(_,...) table.insert(requests,{name=name,args={...}}) end
 remotes[name]=remote
end
local courseActions={}
remotes.ProvingGroundsAction={FireServer=function(_,...)table.insert(courseActions,{...})end}
local network={WaitForChild=function(_,name) return assert(remotes[name],name) end,FindFirstChild=function(_,name)return remotes[name]end,ChildAdded=signal()}
remotes.GarageConfiguration={InvokeServer=function(_,action,id,draft,epoch)
 table.insert(requests,{name=action,args={id,epoch}})
 if action=="SaveZone" then return {ok=true,draft=draft} end
 return {ok=true,choices={{id=id,kind="Boomer",weapon="weapon.cannon",tier="Bunny",
  draft={allocations={drivetrain=25,turret=25,weapon=25,scanners=25},tuning={weapon=.5,scanners=.5}}}}}
end}
local arena=Instance.new("Folder")
arena:SetAttribute("MapWidth",160);arena:SetAttribute("MapDepth",120)
workspace.WaitForChild=function(_,name) assert(name=="Arena");return arena end
game.ReplicatedStorage.WaitForChild=function(_,name) assert(name=="TankNetwork");return network end
local bindings={}
local actions={BindAction=function(_,name,fn)bindings[name]=fn end,BindActionAtPriority=function(_,name,fn)bindings[name]=fn end,UnbindAction=function(_,name)bindings[name]=nil end}
local frame
local run={IsStudio=function() return false end,BindToRenderStep=function(_,_,_,callback) frame=callback end}
if run:IsStudio() then
 local execution=Instance.new("RemoteEvent")
 execution:SetAttribute("Enabled",true)
 function execution:FireServer(value)table.insert(requests,{name="PlaygroundBWExecution",args={value}})end
 remotes.PlaygroundBWExecution=execution
end
local chatService=Instance.new("TextChatService");chatService.ChatVersion=Enum.ChatVersion.TextChatService;chatService.MessageReceived=signal()
local chatBar=Instance.new("ChatInputBarConfiguration");chatBar.Enabled=true;chatBar.IsFocused=false
local chatHistory=Instance.new("ChatWindowConfiguration");chatHistory.Enabled=true
local chatChannels=Instance.new("Folder");chatChannels.Name="TextChannels"
local chatChannel=Instance.new("TextChannel");chatChannel.Name="RBXGeneral";chatChannel.ChildRemoved=signal()
local chatSource=Instance.new("TextSource");chatSource.UserId=101;chatSource.CanSend=true;chatChannel.children={chatSource}
function chatService:FindFirstChildOfClass(name)return if name=="ChatInputBarConfiguration"then chatBar elseif name=="ChatWindowConfiguration"then chatHistory else nil end
function chatService:FindFirstChild(name)return if name=="TextChannels"then chatChannels else nil end
function chatChannels:FindFirstChild(name)return if name=="RBXGeneral"then chatChannel else nil end
function chatService:CanUserChatAsync()return true end
Players.PlayerRemoving=signal()
local prompts={Enabled=true}
game.GetService=function(self,name)
 if name=="RunService" then return run elseif name=="ContextActionService"then return actions elseif name=="TextChatService"then return chatService end
 if name=="ProximityPromptService" then return prompts end
 return originalService(self,name)
end
Enum.RenderPriority.Camera={Value=200}
player.UserId=101
workspace.CurrentCamera={CameraType="Custom",CameraSubject="Original",CFrame=CFrame.new(Vector3.new(0,20,40)),Focus=CFrame.new(Vector3.zero),FieldOfView=70,FieldOfViewMode="Diagonal",ViewportSize=Vector2.new(1280,720)}
workspace.CurrentCamera.ScreenPointToRay=function() return {Origin=Vector3.new(0,20,0),Direction=Vector3.new(0,-1,0)} end
UIS.GetMouseLocation=function() return Vector2.new(100,100) end
local Renderer=require("TankRenderer")
local renderers={}
local effects=0
local effectOrigin,effectDirection
Renderer.new=function(id,kind,weapon)
 local renderer={tankType=kind,weaponId=weapon,update=function() end,resetPose=function(self,state) self.position=state.position end,destroy=function(self) self.destroyed=true end}
 table.insert(renderers,renderer);return renderer
end
Renderer.shot=function(origin,direction)effects+=1;effectOrigin=origin;effectDirection=direction end
local humanoid={Health=100}
player.Character={FindFirstChildOfClass=function()return humanoid end}
local client=require("RoyaleClient").start()
local fireControl=remotes.RoyaleControl.OnClientEvent.Fire
remotes.RoyaleControl.OnClientEvent.Fire=function(event,value)
 if value.requestId==nil then value.requestId=client.session.requestId end
 fireControl(event,value)
end
check(requests[#requests].name=="RoyaleControl" and requests[#requests].args[1]=="Sync","default Royale client requests authoritative admission state")
if run:IsStudio() then
 local toggle=named("PlaygroundBWExecution")
 check(toggle.Text=="BW Execution: ON","diagnostic button renders the server's initial state")
 toggle.Activated:Fire()
 check(requests[#requests].name=="PlaygroundBWExecution" and requests[#requests].args[1]==false and toggle.Text=="BW Execution: ON","click requests OFF without optimistic state changes")
 local execution=remotes.PlaygroundBWExecution
 execution:SetAttribute("Enabled",false);execution:GetAttributeChangedSignal("Enabled"):Fire()
 check(toggle.Text=="BW Execution: OFF","server replication updates the diagnostic button")
else
 for _,widget in created do assert(widget.Name~="PlaygroundBWExecution","published HUD has no diagnostic toggle")end
end
remotes.RoyaleControl.OnClientEvent:Fire({revision=1,mode="OnFoot"})
local shift={KeyCode=Enum.KeyCode.LeftShift}
local sprint=bindings.BattleWorksSprint
check(sprint(nil,Enum.UserInputState.Begin,shift)==Enum.ContextActionResult.Sink
 and requests[#requests].name=="RoyaleSprint" and requests[#requests].args[1]==true,"on-foot Shift requests sprint")
sprint(nil,Enum.UserInputState.End,shift)
check(requests[#requests].args[1]==false,"Shift release requests normal walking")
local state=require("TankSimulation").new(Vector3.zero,"Boomer");state.public=true;state.controlEpoch=2
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{
 ["101"]={royale=true,selected="public:1",score={name="Driver",kills=0,deaths=1}},
 ["102"]={royale=true,score={name="Leader",kills=1,deaths=0}},
},1,{{name="Duelist",kills=2,deaths=0},{name="Wallflower",kills=0,deaths=0}})
local scoreText=named("ScoreboardRows").Text
check(named("PlaygroundScoreboard").Visible and scoreText:find("Duelist")==1
 and scoreText:find("@Leader",1,true) and scoreText:find("Wallflower",1,true),"scoreboard ranks personalities and players together and includes zero scores")
local initial=workspace.CurrentCamera.CFrame
frame(1/30)
check(#renderers==1 and not named("TankHUD").Enabled and workspace.CurrentCamera.CameraType=="Custom","on-foot players see public tank art without activating its HUD/camera")
check(defaultControls.controlsEnabled and defaultTouchGui.Enabled,"on-foot native movement and touch controls remain available")
local function inputCount()local n=0;for _,r in requests do if r.name=="Input"then n+=1 end end;return n end
local function lastInput()for i=#requests,1,-1 do if requests[i].name=="Input"then return requests[i]end end end
local before=inputCount()
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false);frame(1/30)
check(inputCount()==before,"on-foot held keys cannot send tank input, even when a stale snapshot selects a tank")
remotes.RoyaleControl.OnClientEvent:Fire({revision=2,mode="Tank",selected="public:1",epoch=2})
check(sprint(nil,Enum.UserInputState.Begin,shift)==Enum.ContextActionResult.Pass,"tank controls retain Shift")
frame(1/30)
check(named("TankHUD").Enabled and not client.gui.Enabled and not defaultControls.controlsEnabled,"server occupancy activates tank HUD and disables native character controls")
check(not prompts.Enabled,"entering a tank hides local proximity prompts")
check(lastInput().args[1].throttle==0 and lastInput().args[3]==2,"entry clears held keys and stamps authoritative control lease")
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false);frame(1/30)
check(lastInput().args[1].throttle==1 and workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable,"existing keyboard path and battle camera drive occupied tank")
named("Run").Activated:Fire()
local firstRun=requests[#requests]
check(firstRun.name=="BWRun" and firstRun.args[3]=="public:1" and firstRun.args[4]==2,"BW editor Run carries the occupied public tank lease")
state.bwRequestId=firstRun.args[2];state.bwRunRequestId=firstRun.args[2];frame(1/30)
local function exitAndEnter(revision,epoch)
 remotes.RoyaleControl.OnClientEvent:Fire({revision=revision,mode="OnFoot"})
 check(defaultControls.controlsEnabled and defaultTouchGui.Enabled and not named("TankHUD").Enabled and client.gui.Enabled,"exit restores native movement, touch UI and on-foot presentation")
 check(prompts.Enabled,"exiting restores on-foot proximity prompts")
 check(workspace.CurrentCamera.CameraType=="Custom" and workspace.CurrentCamera.CameraSubject==humanoid,"exit restores character camera subject/type")
 local total=inputCount();frame(1/30);check(total==inputCount(),"abandoned tank receives no more input")
 remotes.RoyaleControl.OnClientEvent:Fire({revision=revision-1,mode="Tank",selected="public:1",epoch=epoch-2})
 check(not named("TankHUD").Enabled,"out-of-order occupancy cannot reactivate a stale tank")
 state.controlEpoch=epoch
 state.bwRequestId=0;state.bwRunRequestId=0
 remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{["101"]={royale=true}})
 remotes.RoyaleControl.OnClientEvent:Fire({revision=revision+1,mode="Tank",selected="public:1",epoch=epoch})
 frame(1/30)
 check(not lastInput().args[1].fire and lastInput().args[1].throttle==0,"re-entry starts with released controls")
 check(workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable,"a replacement Tank lease restores the tank camera without input")
end
exitAndEnter(3,4)
named("Run").Activated:Fire()
local secondRun=requests[#requests]
check(secondRun.name=="BWRun" and secondRun.args[2]>firstRun.args[2] and secondRun.args[4]==4,"BW request IDs remain monotonic across leases so old log/Stop fences cannot suppress a new program")
state.bwRequestId=secondRun.args[2];state.bwRunRequestId=secondRun.args[2];frame(1/30)
UIS.PreferredInput=Enum.PreferredInput.Gamepad;UIS.preferredSignal:Fire()
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Gamepad1,KeyCode=Enum.KeyCode.Thumbstick1,Position=Vector3.new(0,1,0)})
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Gamepad1,KeyCode=Enum.KeyCode.ButtonR2,Position=Vector3.new(0,0,1)})
frame(1/30)
check(lastInput().args[1].throttle==1 and lastInput().args[1].fire,"gamepad drives/fires through existing provider")
exitAndEnter(5,6)
UIS.PreferredInput=Enum.PreferredInput.Touch;UIS.preferredSignal:Fire()
local drive=named("Drive");drive.AbsoluteSize=Vector2.new(160,160);drive.AbsolutePosition=Vector2.zero
local function finger(x,y)return {UserInputType=Enum.UserInputType.Touch,Position=Vector3.new(x,y,0),GetPropertyChangedSignal=function()return signal()end}end
drive.InputBegan:Fire(finger(80,8));named("Fire").InputBegan:Fire(finger(200,100));frame(1/30)
check(lastInput().args[1].throttle>.5 and lastInput().args[1].fire,"touch drive/fire paths remain usable in occupied tank")
exitAndEnter(7,8)
state.course={phase="Complete",elapsed=28.5,hits=3,required=3}
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{["101"]={royale=true}})
check(named("ProvingGroundsHUD").Visible and named("Restart Course").Text=="Replay","a completed run offers Replay")
named("Restart Course").Activated:Fire()
check(courseActions[1][1]=="Restart" and courseActions[1][2]=="public:1" and courseActions[1][3]==8,"replay uses the current possession lease")
state.course=nil
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{["101"]={royale=true}})
check(not named("ProvingGroundsHUD").Visible,"the course HUD only shows for an active run")
UIS.WindowFocusReleased:Fire();frame(1/30)
check(not lastInput().args[1].fire and lastInput().args[1].throttle==0,"window focus loss releases all tank intent")
UIS.WindowFocused:Fire();frame(1/30)
check(not lastInput().args[1].fire,"focus restoration cannot revive a held trigger")
named("ReturnToMainMenu").Activated:Fire()
check(requests[#requests].name=="RoyaleControl" and requests[#requests].args[1]=="Exit" and requests[#requests].args[3]=="public:1" and requests[#requests].args[4]==8,"touch/mouse Exit action requests current server occupancy release")
bindings.BattleWorksExitTank(nil,Enum.UserInputState.Begin)
check(requests[#requests].args[1]=="Exit","F/controller B use the same explicit exit request")
remotes.RoyaleControl.OnClientEvent:Fire({revision=9,mode="OnFoot"})
local total=#created
for i=1,6 do exitAndEnter(9+i*2,8+i*2)end
check(#created==total,"rapid switching reuses one renderer/input/HUD/camera instead of duplicating listeners or widgets")
remotes.RoyaleControl.OnClientEvent:Fire({revision=99,mode="OnFoot"})
local effectsBefore=effects
remotes.Shot.OnClientEvent:Fire("public:1",Vector3.zero,Vector3.new(0,0,-1),"Boomer",0)
check(effects==effectsBefore+1,"on-foot clients continue seeing shared battle firing effects")
check(effectOrigin==Vector3.zero and effectDirection.Z== -1,"shot effects retain authoritative release origin/direction")
check(#renderers==1,"public tank renderer persists through all occupancy changes")
if run:IsStudio()then
 local redraw={Name="RedrawMap",IsA=function(_,kind)return kind=="RemoteEvent"end,FireServer=function(_,...)table.insert(requests,{name="RedrawMap",args={...}})end}
 remotes.RedrawMap=redraw;network.ChildAdded:Fire(redraw)
 named("RedrawMap").Activated:Fire()
 check(requests[#requests].name=="RedrawMap","a late optional Studio tool binds without delaying gameplay startup")
end
-- The actual existing shell is created once, and its first action returns to
-- the same Royale session without allocating a second battle client.
local background=require("MenuBackground")
local createBackground=background.new
local previousRequest=client.session.requestId
background.new=function() error("injected menu startup failure") end
named("RoyaleMainMenu").Activated:Fire()
check(client.session.mode=="Battle" and client.session.requestId==previousRequest and client.navigation.Enabled,
 "menu startup failure leaves the current Playground session and navigation active")
background.new=createBackground
local labScreen=Shell.ShellInnovationLab
Shell.ShellInnovationLab=nil
named("RoyaleMainMenu").Activated:Fire()
Shell.ShellInnovationLab=labScreen
local shell=client.getShell()
local menuRequest=client.session.requestId
check(shell and shell.manager.current=="MainMenu" and requests[#requests].args[1]=="Menu","battlefield Main Menu opens the existing shell and requests server departure")
check(shell.gui.Enabled and shell.manager:get("MainMenu").frame.Visible,"Playground menu is visible without requiring the Lab screen module")
check(not client.navigation.Enabled and not defaultControls.controlsEnabled and not named("TankHUD").Enabled,"menu suspends native movement and every battlefield control layer")
remotes.RoyaleControl.OnClientEvent:Fire({revision=100,mode="Menu",requestId=menuRequest})
remotes.RoyaleControl.OnClientEvent:Fire({revision=101,mode="Tank",selected="public:1",epoch=20,requestId=menuRequest-1})
check(shell.manager.current=="MainMenu" and not named("TankHUD").Enabled,"late occupancy from before menu departure cannot reopen controls")
local main=shell.manager:get("MainMenu")
check(main.buttons[1].Text=="The Playground","main screen clearly offers the shared running Royale")
main.buttons[1].Activated:Fire()
check(requests[#requests].args[1]=="Join" and client.session.mode=="Joining","main screen The Playground requests authoritative re-entry")
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=102,mode="OnFoot"})
check(shell.manager.current=="Battle" and client.navigation.Enabled and defaultControls.controlsEnabled and not named("TankHUD").Enabled,"return to Royale resumes on foot with native controls and shared tank rendering")
check(bindings.BattleWorksShellNavigation(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.ButtonB})==Enum.ContextActionResult.Pass,"shell does not steal Royale's controller-B tank exit binding")
state.controlEpoch=22
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=103,mode="Tank",selected="public:1",epoch=22})
check(named("TankHUD").Enabled and client.navigation.Enabled,"Main Menu action remains available while driving")
named("RoyaleMainMenu").Activated:Fire()
remotes.RoyaleControl.OnClientEvent:Fire({revision=104,mode="Menu"})
check(shell.manager.current=="MainMenu" and not named("TankHUD").Enabled,"leaving while driving closes tank controls before returning home")
main.buttons[1].Activated:Fire()
local canceledJoin=client.session.requestId
shell.home()
remotes.RoyaleControl.OnClientEvent:Fire({revision=105,mode="OnFoot",requestId=canceledJoin})
check(shell.manager.current=="MainMenu" and not client.navigation.Enabled,"canceling re-entry fences the delayed Join acknowledgment")
remotes.RoyaleControl.OnClientEvent:Fire({revision=106,mode="Menu"})
shell.manager:show("Garage");shell.home()
local widgets=#created
main.buttons[1].Activated:Fire()
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=107,mode="OnFoot"})
named("RoyaleMainMenu").Activated:Fire()
remotes.RoyaleControl.OnClientEvent:Fire({revision=108,mode="Menu"})
check(client.getShell()==shell and #created==widgets,"menu/battle round trips reuse the existing shell, HUD, camera and input providers")
main.buttons[1].Activated:Fire()
remotes.RoyaleControl.OnClientEvent:Fire({revision=109,mode="Tank",selected="public:1",epoch=22,message="Cannot exit here: move onto safe ground away from the cliff edge."})
check(named("RoyaleNotice").Visible and string.find(named("RoyaleNotice").Text,"Cannot exit"),"unsafe-exit reason is visible in battlefield UI")
remotes.RoyaleControl.OnClientEvent:Fire({revision=110,mode="OnFoot"})
check(not named("RoyaleNotice").Visible,"next control acknowledgment clears old hazard feedback")
remotes.RoyaleControl.OnClientEvent:Fire({revision=111,mode="Tank",selected="public:1",epoch=22})
named("MouseAimSelector").Activated:Fire();named("Mouse Direct").Activated:Fire()
check(named("MouseAimSelector"):GetAttribute("MouseAimMode")=="Mouse Direct","in-game selector changes mouse preference")
exitAndEnter(112,24)
check(named("MouseAimSelector"):GetAttribute("MouseAimMode")=="Mouse Direct","mouse preference persists across public tank lease/death-style control changes")
named("MouseAimSelector").Activated:Fire();named("Mouse Points").Activated:Fire()
local editorToggle=named("ToggleBW")
local touchProvider=client.battle.inputController.providers.Touch
check(editorToggle.AnchorPoint.Y==1 and editorToggle.Position.Y.Scale==1 and editorToggle.Position.Y.Offset==-12,"BW Editor is docked along the bottom of the tank HUD")
touchProvider.root.Visible=true;touchProvider.root:GetPropertyChangedSignal("Visible"):Fire()
check(-editorToggle.Position.Y.Offset>16+touchProvider.sticks.Drive.frame.Size.Y.Offset,"editor dock clears the touch drive stick")
touchProvider.root.Visible=false;touchProvider.root:GetPropertyChangedSignal("Visible"):Fire()
check(editorToggle.Position.Y.Offset==-12,"editor dock returns to the bottom when touch controls hide")
-- Chat persists across real RoyaleClient control acknowledgments, not a second HUD.
UIS.PreferredInput=Enum.PreferredInput.KeyboardAndMouse;UIS.preferredSignal:Fire()
check(client.chat.ready and client.chat.gui.Enabled and client.chat.window.Target==chatChannel,"production Playground client mounts native global chat both on foot/in tank")
local chatWindow=client.chat.window;local chatWidgets=#created
client.chat:setExpanded(true)
chatBar.IsFocused=true;chatBar:GetPropertyChangedSignal("IsFocused"):Fire()
local beforeExit=#requests
bindings.BattleWorksExitTank(nil,Enum.UserInputState.Begin)
check(#requests==beforeExit,"typing F/B cannot eject through the separate Royale action binding")
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false)
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.C,UserInputType=Enum.UserInputType.Keyboard},false)
frame(1/30)
check(lastInput().args[1].throttle==0 and not lastInput().args[1].fire and lastInput().args[1].turretX==0 and lastInput().args[1].turretY==0,"chat focus emits only neutral gameplay intent through real client routing")
remotes.RoyaleControl.OnClientEvent:Fire({revision=114,mode="OnFoot"})
check(client.chat.gui.Enabled and not defaultControls.controlsEnabled,"death/respawn-style on-foot ACK cannot restore movement through active chat")
state.controlEpoch=26;remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=115,mode="Tank",selected="public:1",epoch=26})
check(client.chat.window==chatWindow and client.battle.inputController.textEntryActive,"switching tanks retains singleton chat/history and native focus lease")
chatBar.IsFocused=false;chatBar:GetPropertyChangedSignal("IsFocused"):Fire()
client.chat:setExpanded(false)
check(not client.battle.inputController.textEntryActive and named("MouseAimSelector"):GetAttribute("MouseAimMode")=="Mouse Points","chat blur restores existing input mode without changing aim preference")
check(not prompts.Enabled,"closing chat while in a tank keeps prompts hidden")
remotes.RoyaleControl.OnClientEvent:Fire({revision=116,mode="OnFoot"})
check(defaultControls.controlsEnabled and client.chat.gui.Enabled,"on-foot native controls and chat resume after text entry")
check(prompts.Enabled,"on-foot prompts return after the tank and chat both release suppression")
named("RoyaleMainMenu").Activated:Fire();remotes.RoyaleControl.OnClientEvent:Fire({revision=117,mode="Menu"})
check(not client.chat.gui.Enabled and not chatBar.Enabled,"menu and its World Editor do not retain active chat input")
main.buttons[1].Activated:Fire();remotes.RoyaleControl.OnClientEvent:Fire({revision=118,mode="OnFoot"})
check(client.chat.window==chatWindow and #created==chatWidgets,"returning to Playground reuses chat across menu transitions without duplicate UI")
state.controlEpoch=30;state.controlMode="Manual";state.bwRunning=false
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=119,mode="Tank",selected="public:1",epoch=30,controlMode="Manual",personality="Marauder"})
check(client.modeSwitch.Visible and client.modeSwitch.Text:find("MANUAL",1,true),"large bottom switch reflects automatic Manual entry")
local gear=named("ZoneConfigurationGear")
check(not gear.Visible,"gear is hidden while manually driving outside a zone")
state.configurationZone="config:west"
client.battle.inputController:setMouseMode("Mouse Direct")
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
check(gear.Visible and UIS.MouseIconEnabled,"server zone snapshot displays the gear and releases Mouse Direct cursor")
gear.Activated:Fire()
local zoneGui=named("ZoneGarage")
local zoneRequest=requests[#requests]
check(zoneGui.Enabled and zoneRequest.name=="ReadZone" and zoneRequest.args[1]=="public:1" and zoneRequest.args[2]==30,"gear opens the existing Garage for the current lease")
for _,widget in created do
 if widget.Name=="SaveBus" and widget.Parent.Parent.Name=="Tank Configuration" then widget.Activated:Fire() end
end
check(requests[#requests].name=="SaveZone" and requests[#requests].args[2]==30,"Apply sends the draft through the live lease route")
local beforeAuto=#requests
client.modeSwitch.Activated:Fire()
check(#requests==beforeAuto,"Auto button is inhibited in the protected zone")
state.configurationZone=nil
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
check(not gear.Visible and not zoneGui.Enabled and not client.battle.inputController.externalControl and not UIS.MouseIconEnabled,"leaving closes Garage, resumes manual input, and restores Mouse Direct capture")
client.modeSwitch.Activated:Fire()
check(requests[#requests].name=="RoyaleControl"and requests[#requests].args[1]=="Auto"and requests[#requests].args[4]==30,"switch requests Auto using current authoritative lease")
local sourceRequested=false
for _,request in requests do if request.name=="BWRuntimeState"and request.args[1]=="Source"then sourceRequested=true end end
check(sourceRequested,"authoritative control ACK requests source after client begins accepting tank packets")
local pendingRequests=#requests;client.modeSwitch.Activated:Fire()
check(#requests==pendingRequests,"rapid duplicate toggle waits for authoritative acknowledgment")
state.controlEpoch=31;state.controlMode="Auto";state.bwRunning=true
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=120,mode="Tank",selected="public:1",epoch=31,controlMode="Auto",personality="Marauder"})
frame(1/30)
check(client.modeSwitch.Text:find("AUTO",1,true)and client.battle.inputController.externalControl,"Auto mode suspends manual providers while keeping tank camera")
client.modeSwitch.Activated:Fire()
check(requests[#requests].args[1]=="Manual"and requests[#requests].args[4]==31,"same touch/click button requests Manual with refreshed lease")
state.controlEpoch=32;state.controlMode="Manual";state.bwRunning=false
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{})
remotes.RoyaleControl.OnClientEvent:Fire({revision=121,mode="Tank",selected="public:1",epoch=32,controlMode="Manual",personality="Marauder"})
local hardwareButton=named("Hardware")
local hardwareBox=named("HardwareConfiguration")
hardwareBox.ReleaseFocus=function(self)
 if UIS.focusedTextBox==self then UIS.focusedTextBox=nil end
end
local function focusHardware()
 UIS.focusedTextBox=hardwareBox
 UIS.TextBoxFocused:Fire(hardwareBox)
 check(client.battle.inputController.suspended,"hardware typing suspends gameplay")
end
editorToggle.Activated:Fire()
hardwareButton.Activated:Fire()
focusHardware()
hardwareButton.Activated:Fire()
check(UIS.focusedTextBox==nil,"leaving the hardware panel releases its hidden text box")
hardwareButton.Activated:Fire()
focusHardware()
named("CloseEditor").Activated:Fire()
frame(1/30)
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false)
frame(1/30)
check(UIS.focusedTextBox==nil and lastInput().args[1].throttle==1,"closing editor restores keyboard motion even without a focus-release signal")
bindings.BattleWorksExitTank(nil,Enum.UserInputState.Begin)
check(requests[#requests].name=="RoyaleControl" and requests[#requests].args[1]=="Exit","F exits the tank without an alt-tab after closing the editor")
remotes.RoyaleControl.OnClientEvent:Fire({revision=122,mode="OnFoot"})
check(not client.modeSwitch.Visible,"switch hides outside occupancy")
Players.PlayerRemoving:Fire(player)
check(client.chat.destroyed and not bindings.BattleWorksTextEntry_PlaygroundChat,"production departure cleans chat input route and native wrapper")
Instance.new=savedNew;game.GetService=originalService
print(string.format("Battle Royale production client transitions passed: %d assertions",count))

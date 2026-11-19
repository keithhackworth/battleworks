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
for _,name in {"RoyaleControl","Input","Snapshot","Shot","SelectTank","PrepareShot","BWRun","BWStop","ResetBattle","BWOutput","BWHardware","BWRuntimeState"} do
 local remote={OnClientEvent=signal()}
 remote.FireServer=function(_,...) table.insert(requests,{name=name,args={...}}) end
 remotes[name]=remote
end
local network={WaitForChild=function(_,name) return assert(remotes[name],name) end,FindFirstChild=function(_,name)return remotes[name]end,ChildAdded=signal()}
local arena=Instance.new("Folder")
arena:SetAttribute("MapWidth",160);arena:SetAttribute("MapDepth",120)
workspace.WaitForChild=function(_,name) assert(name=="Arena");return arena end
game.ReplicatedStorage.WaitForChild=function(_,name) assert(name=="TankNetwork");return network end
local bindings={}
local actions={BindAction=function(_,name,fn)bindings[name]=fn end,BindActionAtPriority=function(_,name,fn)bindings[name]=fn end,UnbindAction=function(_,name)bindings[name]=nil end}
local frame
local run={IsStudio=function() return false end,BindToRenderStep=function(_,_,_,callback) frame=callback end}
game.GetService=function(self,name)
 if name=="RunService" then return run elseif name=="ContextActionService"then return actions end
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
remotes.RoyaleControl.OnClientEvent:Fire({revision=1,mode="OnFoot"})
local state=require("TankSimulation").new(Vector3.zero,"Boomer");state.public=true;state.controlEpoch=2
remotes.Snapshot.OnClientEvent:Fire({["public:1"]=state},{["101"]={royale=true,selected="public:1"}})
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
frame(1/30)
check(named("TankHUD").Enabled and not client.gui.Enabled and not defaultControls.controlsEnabled,"server occupancy activates tank HUD and disables native character controls")
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
named("RoyaleMainMenu").Activated:Fire()
local shell=client.getShell()
local menuRequest=client.session.requestId
check(shell and shell.manager.current=="MainMenu" and requests[#requests].args[1]=="Menu","battlefield Main Menu opens the existing shell and requests server departure")
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
Instance.new=savedNew;game.GetService=originalService
print(string.format("Battle Royale production client transitions passed: %d assertions",count))

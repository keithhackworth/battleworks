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
for _,name in {"Input","Snapshot","Shot","SelectTank","PrepareShot","BWRun","BWStop","ResetBattle","BWOutput","BWHardware","BWRuntimeState"} do
 local remote={OnClientEvent=signal()}
 remote.FireServer=function(_,...) table.insert(requests,{name=name,args={...}}) end
 remotes[name]=remote
end
local network={WaitForChild=function(_,name) return assert(remotes[name],name) end}
local arena=Instance.new("Folder")
arena:SetAttribute("MapWidth",160);arena:SetAttribute("MapDepth",120)
workspace.WaitForChild=function(_,name) assert(name=="Arena");return arena end
game.ReplicatedStorage.WaitForChild=function(_,name) assert(name=="TankNetwork");return network end
local frame
local run={IsStudio=function() return false end,BindToRenderStep=function(_,_,_,callback) frame=callback end}
game.GetService=function(self,name)
 if name=="RunService" then return run end
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
Renderer.new=function(id,kind,weapon)
 local renderer={tankType=kind,weaponId=weapon,update=function() end,resetPose=function(self,state) self.position=state.position end,destroy=function(self) self.destroyed=true end}
 table.insert(renderers,renderer);return renderer
end
Renderer.shot=function() effects+=1 end
local menus=0
local client
client=require("BattleClient").new(function() menus+=1;client:setActive(false) end)
check(not named("TankHUD").Enabled and not named("BWEditor").Enabled and not named("BattlefieldCameraBars").Enabled,"all existing gameplay layers start hidden")
local initial=workspace.CurrentCamera.CFrame
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false)
frame(1/30)
check(#requests==0 and workspace.CurrentCamera.CFrame==initial,"menu input and render tick never transmit or take camera ownership")
local state=require("TankSimulation").new(Vector3.zero,"Boomer")
remotes.Snapshot.OnClientEvent:Fire({["101"]=state},{["101"]={selected="101"}})
remotes.Shot.OnClientEvent:Fire("101",Vector3.zero,Vector3.new(0,0,-1),"Boomer",0)
check(#renderers==0 and effects==0 and #requests==0,"menu snapshots and shot events create no live battle presentation")
client:setActive(true)
UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false)
frame(1/30)
check(named("TankHUD").Enabled and named("BWEditor").Enabled and #renderers==1,"admitted gameplay enables existing HUD, editor and renderer")
check(requests[#requests].name=="Input" and requests[#requests].args[1].throttle==1,"existing keyboard path works after entry")
check(workspace.CurrentCamera.CameraType==Enum.CameraType.Scriptable,"battle camera owns gameplay view")
remotes.Shot.OnClientEvent:Fire("101",Vector3.zero,Vector3.new(0,0,-1),"Boomer",0)
check(effects==1,"battle effects work while active")
client:setActive(false)
check(renderers[1].destroyed and not named("TankHUD").Enabled and not named("BWEditor").Enabled,"leaving removes render models and hides every gameplay layer")
check(workspace.CurrentCamera.CameraType=="Custom" and workspace.CurrentCamera.CFrame==initial and workspace.CurrentCamera.FieldOfView==70 and workspace.CurrentCamera.FieldOfViewMode=="Diagonal","leaving restores camera state")
local total=#requests
for _=1,10 do frame(1/30) end
remotes.Snapshot.OnClientEvent:Fire({["101"]=state},{["101"]={selected="101"}})
remotes.Shot.OnClientEvent:Fire("101",Vector3.zero,Vector3.new(0,0,-1),"Boomer",0)
named("ResetBattle").Activated:Fire();named("Rattler").Activated:Fire()
check(#requests==total and #renderers==1 and effects==1,"late snapshots, effects and stale UI callbacks stay isolated after exit")
client:setActive(true);frame(1/30)
check(requests[#requests].name=="Input" and requests[#requests].args[1].throttle==0,"re-entry never inherits held movement keys")
UIS.PreferredInput=Enum.PreferredInput.Gamepad;UIS.preferredSignal:Fire()
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Gamepad1,KeyCode=Enum.KeyCode.Thumbstick1,Position=Vector3.new(0,1,0)})
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Gamepad1,KeyCode=Enum.KeyCode.Thumbstick2,Position=Vector3.new(.6,0,0)})
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.Gamepad1,KeyCode=Enum.KeyCode.ButtonR2,Position=Vector3.new(0,0,1)})
frame(1/30)
check(requests[#requests].args[1].throttle==1 and requests[#requests].args[1].fire and requests[#requests].args[1].turretX>0,"existing gamepad movement, turret and fire path survives integration")
client:setActive(false);client:setActive(true);remotes.Snapshot.OnClientEvent:Fire({["101"]=state},{["101"]={selected="101"}});frame(1/30)
check(requests[#requests].args[1].throttle==0 and not requests[#requests].args[1].fire,"leaving clears held gamepad sticks and trigger")
UIS.PreferredInput=Enum.PreferredInput.Touch;UIS.preferredSignal:Fire()
local drive=named("Drive");drive.AbsoluteSize=Vector2.new(160,160);drive.AbsolutePosition=Vector2.new(0,0)
local function finger(x,y) return {UserInputType=Enum.UserInputType.Touch,Position=Vector3.new(x,y,0),GetPropertyChangedSignal=function() return signal() end} end
drive.InputBegan:Fire(finger(80,8))
named("Fire").InputBegan:Fire(finger(200,100))
frame(1/30)
check(requests[#requests].args[1].throttle>.5 and requests[#requests].args[1].fire,"existing touch movement and fire path survives integration")
client:setActive(false);client:setActive(true);remotes.Snapshot.OnClientEvent:Fire({["101"]=state},{["101"]={selected="101"}});frame(1/30)
check(requests[#requests].args[1].throttle==0 and not requests[#requests].args[1].fire,"leaving clears captured touch gestures")
named("ReturnToMainMenu").Activated:Fire()
check(menus==1,"battle UI exposes return-to-menu path")
client:setActive(false)
Instance.new=savedNew; game.GetService=originalService
print(string.format("Shell production client isolation passed: %d assertions",count))

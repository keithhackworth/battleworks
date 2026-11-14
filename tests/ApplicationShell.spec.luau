local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local Session=require("GameplaySession")
local sent={}
local session=Session.new(function(action,id) table.insert(sent,{action,id}) end)
check(session.mode=="Menu" and not session:canControl() and #sent==0,"presence never requests battle admission")
local hostCalls={}
local host=require("BattleClientHost").new(function()
 table.insert(hostCalls,"create")
 return {setActive=function(_,active)table.insert(hostCalls,active)end}
end)
host:setActive(false)
check(#hostCalls==0,"menu startup does not construct battle UI, input or camera")
host:setActive(true);host:setActive(false);host:setActive(true)
check(#hostCalls==4 and hostCalls[1]=="create" and hostCalls[2]==true and hostCalls[3]==false and hostCalls[4]==true,"battle client initializes only once and preserves lifecycle on re-entry")
check(session:join() and session.mode=="Joining" and not session:canControl(),"join waits for server acknowledgment")
check(not session:join() and #sent==1,"duplicate join cannot issue extra requests")
session:leave()
check(not session:receive(1,true) and not session:canControl(),"late enter ack cannot reopen gameplay after cancellation")
check(session:receive(2,false),"leave ack accepted")
session:join(); session:receive(3,false,"Please wait")
check(session.mode=="Menu" and not session:canControl(),"rejected admission stays isolated")
session:join(); session:receive(4,true)
check(session:canControl(),"acknowledged admission allows battle")
session:leave()
check(not session:canControl() and sent[#sent][1]=="Leave","leave gates controls before server response")

local activated
local delayed=require("BattleClientHost").new(function()
 coroutine.yield()
 return {setActive=function(_,enabled)activated=enabled end}
end)
local loading=coroutine.create(function() delayed:setActive(true) end)
check(coroutine.resume(loading),"battle client may wait for a dependency")
delayed:setActive(false);coroutine.resume(loading)
check(activated==false,"canceled entry cannot reactivate a delayed battle client")

local originalService=game.GetService
local bindings={}
local actions={BindActionAtPriority=function(_,name,callback) bindings[name]=callback end,UnbindAction=function(_,name) bindings[name]=nil end}
game.GetService=function(self,name) if name=="ContextActionService" then return actions end; return originalService(self,name) end
local calls={}
local background={enter=function() table.insert(calls,"background-enter") end,exit=function() table.insert(calls,"background-exit") end,destroy=function() table.insert(calls,"background-destroy") end}
local gameplay={active=false,setActive=function(self,enabled) self.active=enabled;table.insert(calls,if enabled then "battle-enter" else "battle-exit") end}
local appSession=Session.new(function() end)
-- Turn the observed crashing engine property into a regression trap. Menus
-- must remain operable even when assigning native selection is forbidden.
local oldGuiMetatable=getmetatable(GuiService)
GuiService.SelectedObject=nil
setmetatable(GuiService,{__newindex=function(self,key,value)
 if key=="SelectedObject" and value~=nil then error("native menu selection must not be assigned") end
 rawset(self,key,value)
end})
local App=require("ApplicationShell")
local app=App.new(playerGui,workspace,appSession,gameplay,background)
local manager=app.manager
local main=manager:get("MainMenu")
check(manager.current=="MainMenu" and app.gui.Enabled and not gameplay.active,"application starts in main menu")
local expected={"Play BattleWorks","Garage","Store","World Editor","Preferences","Manuals"}
check(#main.buttons==6 and main.order==7,"main menu has exactly six actions and a separator")
for index,text in expected do check(main.buttons[index].Text==text,"main menu exact order: "..text) end
check(main.buttons[3].LayoutOrder==3 and main.buttons[4].LayoutOrder==5,"separator sits between Store and World Editor")
main.buttons[1].Activated:Fire()
check(manager.current=="Lobby" and not main.frame.Visible,"Play opens lobby without entering battle")
local lobby=manager:get("Lobby")
lobby.join.Activated:Fire()
check(appSession.mode=="Joining" and not gameplay.active and app.gui.Enabled,"lobby pending state remains outside gameplay")
app.home(); appSession:receive(1,true)
check(manager.current=="MainMenu" and not gameplay.active,"back cancels pending admission despite late acknowledgment")
main.buttons[1].Activated:Fire(); lobby.join.Activated:Fire(); appSession:receive(3,true)
check(manager.current=="Battle" and gameplay.active and not app.gui.Enabled,"admitted battle hides shell and starts existing client")
app.home()
check(manager.current=="MainMenu" and not gameplay.active and app.gui.Enabled,"return exits gameplay and restores main menu")
for _,name in {"Garage","Store","WorldEditor","Preferences","Manuals","BattleHistory"} do
 manager:show(name)
 local screen=manager:get(name)
 check(screen.frame.Visible and not main.frame.Visible,"independent screen enters: "..name)
 screen.buttons[#screen.buttons].Activated:Fire()
 check(manager.current=="MainMenu" and not screen.frame.Visible,"screen returns home: "..name)
end
local keyboard=bindings.BattleWorksShellNavigation
check(main.focusIndex==nil and GuiService.SelectedObject==nil,"startup never assigns native GUI selection")
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Down})
check(main.focusIndex==1,"first keyboard navigation focuses Play")
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Down})
check(main.focusIndex==2,"keyboard focus moves to Garage without engine selection")
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.Return})
check(manager.current=="Garage","keyboard activates focused route")
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.ButtonB})
check(manager.current=="MainMenu","Xbox B returns to main menu")
main:moveFocus(-1)
check(main.focusIndex==6,"local selection wraps backwards in menu order")
main:moveFocus(1)
check(main.focusIndex==1 and GuiService.SelectedObject==nil,"local selection wraps forwards without native focus")
for _,button in main.buttons do check(not button.Selectable and not button.NextSelectionDown,"menu buttons do not enter the native selection graph") end
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.DPadDown})
check(main.focusIndex==2,"Xbox D-pad moves local focus")
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.ButtonA})
check(manager.current=="Garage","Xbox A activates local focus")
keyboard(nil,Enum.UserInputState.Begin,{KeyCode=Enum.KeyCode.ButtonB})
main.content.AbsoluteSize=Vector2.new(400,100);main.content.AbsolutePosition=Vector2.zero
main.content.CanvasPosition=Vector2.zero
main.buttons[6].AbsolutePosition=Vector2.new(0,200);main.buttons[6].AbsoluteSize=Vector2.new(200,48)
main.focusIndex=5;main:moveFocus(1)
check(main.content.CanvasPosition.Y==148,"local focus scrolls the next button into a short viewport")
main.buttons[5].AbsolutePosition=Vector2.new(0,-40);main:moveFocus(-1)
check(main.content.CanvasPosition.Y==108,"local focus scrolls upward without engine auto-selection")
local cache=manager:get("Garage")
manager:show("Garage"); manager:show("MainMenu")
check(manager:get("Garage")==cache,"screens are reused rather than accumulating UI")
app:destroy()
check(not bindings.BattleWorksShellNavigation and not gameplay.active and app.gui.destroyed,"shell teardown releases input bindings and UI")
game.GetService=originalService
setmetatable(GuiService,oldGuiMetatable)

-- Capture only actual static arena parts, never gameplay objects or scripts.
local arena=Instance.new("Folder"); arena:SetAttribute("MapWidth",230); arena:SetAttribute("MapDepth",230)
local floor=Instance.new("Part"); floor.Name="Floor"; floor.Transparency=0
floor.IsA=function(_,class) return class=="Part" or class=="BasePart" end
local clones={}
floor.Clone=function()
 local copy=Instance.new("Part"); copy:SetAttribute("Gameplay","remove")
 local scriptNode=Instance.new("Script"); local mesh=Instance.new("SpecialMesh")
 copy.children={scriptNode,mesh}
 table.insert(clones,{part=copy,script=scriptNode,mesh=mesh})
 return copy
end
local tank=Instance.new("Part"); tank.Name="TankHitbox";tank.Transparency=0;tank.Clone=function() error("must not capture tanks") end
arena.children={floor,tank}
local camera=workspace.CurrentCamera
local Background=require("MenuBackground")
workspace:SetAttribute("BattleWorksMenu3D",true) -- explicitly exercise optional 3D capture
local presenter=Background.new(playerGui,arena)
presenter:enter()
check(#clones==1 and clones[1].script.destroyed and not clones[1].mesh.destroyed,"static capture strips executable descendants and retains appearance")
check(clones[1].part.Anchored and not clones[1].part.CanCollide and not clones[1].part.CanQuery and not clones[1].part:GetAttribute("Gameplay"),"snapshot cannot participate in battle")
check(workspace.CurrentCamera==camera and presenter.viewport.CurrentCamera==presenter.camera,"presentation uses a separate camera")
check(presenter.world:IsA("Folder"),"static menu scenery does not allocate a physics WorldModel")
presenter:exit(); presenter:enter()
check(#clones==1,"unchanged static background is cached across navigation")
presenter:destroy()
check(presenter.viewport.destroyed,"presentation teardown releases its viewport")
workspace:SetAttribute("BattleWorksMenu3D",false)
local fallback=Background.new(playerGui,arena);fallback:enter()
check(fallback.viewport:IsA("Frame") and not fallback.world and not fallback.camera,"diagnostic mode creates no viewport, native physics world or 3D camera")
fallback:exit();fallback:destroy()
check(fallback.viewport.destroyed,"diagnostic background retains normal lifecycle cleanup")
workspace:SetAttribute("BattleWorksMenu3D",nil)
local studioDefault=Background.new(playerGui,arena)
check(studioDefault.viewport:IsA("Frame") and not studioDefault.world,"Studio defaults to a plain menu background without native 3D allocations")
studioDefault:destroy()
print(string.format("Application shell/navigation/background suite passed: %d assertions",count))

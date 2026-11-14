local Manager=require(script.Parent.ScreenManager)
local Background=require(script.Parent.MenuBackground)
local GuiService=game:GetService("GuiService")
local Actions=game:GetService("ContextActionService")
local UIS=game:GetService("UserInputService")
local Shell={}; Shell.__index=Shell
local startupStages={}
local function startup(stage)
 if game:GetService("RunService"):IsStudio() and not startupStages[stage] then
  startupStages[stage]=true
  print("[BattleWorks startup/client] "..stage)
 end
end
local definitions={
 MainMenu=require(script.Parent.ShellMainMenu),Lobby=require(script.Parent.ShellLobby),
 Garage=require(script.Parent.ShellGarage),BattleHistory=require(script.Parent.ShellBattleHistory),
 Store=require(script.Parent.ShellStore),WorldEditor=require(script.Parent.ShellWorldEditor),
 Preferences=require(script.Parent.ShellPreferences),Manuals=require(script.Parent.ShellManuals),
 Battle=require(script.Parent.ShellBattle),
}
function Shell.new(playerGui,arena,session,gameplay,presenter,editorAssets,worldRequest)
 startup("creating shell GUI")
 local gui=Instance.new("ScreenGui"); gui.Name="BattleWorksShell"; gui.ResetOnSpawn=false
 gui.DisplayOrder=100; gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
 gui.Parent=playerGui
 startup("creating menu background")
 local background=presenter or Background.new(gui,arena)
 startup("menu background created")
 local content=Instance.new("Frame"); content.Name="Screens"; content.BackgroundTransparency=1
 content.Size=UDim2.fromScale(1,1); content.Parent=gui
 local self=setmetatable({gui=gui,background=background,session=session,gameplay=gameplay},Shell)
 local context={parent=content,session=session,gameplay=gameplay,trace=startup,worldRequest=worldRequest,
  editorAssets=if type(editorAssets)=="function" then nil else editorAssets,
  getEditorAssets=if type(editorAssets)=="function" then editorAssets else function() return editorAssets end}
 context.join=function() session:join() end
 context.home=function()
  if session.mode~="Menu" then session:leave() end
  self.manager:show("MainMenu")
 end
 self.home=context.home
 self.manager=Manager.new(context,definitions,function(name)
  gui.Enabled=name~="Battle"
  if name=="Battle" or name=="WorldEditor" then background:exit() else
   startup("showing menu background")
   background:enter()
   startup("menu background shown")
  end
 end)
 session.onState=function(mode,message)
  if mode=="Battle" then self.manager:show("Battle")
  elseif mode=="Joining" then self.manager:show("Lobby")
  elseif self.manager.current=="Battle" then self.manager:show("MainMenu") end
  self.manager:get("Lobby"):setStatus(mode=="Joining",message)
 end
 local function navigation(_,state,input)
  if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
  if self.manager.current=="WorldEditor" then
   if input.KeyCode==Enum.KeyCode.ButtonB and state==Enum.UserInputState.Begin then context.home();return Enum.ContextActionResult.Sink end
   return Enum.ContextActionResult.Pass
  end
  if self.manager.current=="Battle" then
   if input.KeyCode==Enum.KeyCode.ButtonB then
    if state==Enum.UserInputState.Begin then context.home() end
    return Enum.ContextActionResult.Sink
   end
   return Enum.ContextActionResult.Pass
  end
  if state~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
  if input.KeyCode==Enum.KeyCode.ButtonB or input.KeyCode==Enum.KeyCode.Backspace then context.home()
  else
   local screen=self.manager:get(self.manager.current)
   if input.KeyCode==Enum.KeyCode.Up or input.KeyCode==Enum.KeyCode.DPadUp then screen:moveFocus(-1)
   elseif input.KeyCode==Enum.KeyCode.Down or input.KeyCode==Enum.KeyCode.DPadDown then screen:moveFocus(1)
   elseif input.KeyCode==Enum.KeyCode.Return or input.KeyCode==Enum.KeyCode.ButtonA then screen:activateSelected() end
  end
  return Enum.ContextActionResult.Sink
 end
 -- Shell arrows/D-pad/A/Enter use local focus, bypassing native auto-selection.
 -- B returns home; Escape/CoreGui and gameplay input remain unchanged.
 Actions:BindActionAtPriority("BattleWorksShellNavigation",navigation,false,2000,
  Enum.KeyCode.Up,Enum.KeyCode.Down,Enum.KeyCode.DPadUp,Enum.KeyCode.DPadDown,Enum.KeyCode.Return,Enum.KeyCode.ButtonA,Enum.KeyCode.Backspace,Enum.KeyCode.ButtonB)
 startup("creating main menu widgets")
 self.manager:get("MainMenu")
 startup("main menu widgets created")
 self.manager:show("MainMenu")
 return self
end
function Shell:destroy()
 self.session:leave(); self.session.onState=function() end
 Actions:UnbindAction("BattleWorksShellNavigation"); GuiService.SelectedObject=nil
 self.manager:destroy(); self.background:destroy(); self.gui:Destroy()
end
return Shell

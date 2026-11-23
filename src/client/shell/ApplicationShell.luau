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
function Shell.new(playerGui,arena,session,gameplay,presenter,editorAssets,worldRequest,options)
 options=options or {}
 startup("creating shell GUI")
 local gui=Instance.new("ScreenGui"); gui.Name="BattleWorksShell"; gui.ResetOnSpawn=false
 gui.DisplayOrder=100; gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
 startup("creating menu background")
 local background=presenter or Background.new(gui,arena)
 startup("menu background created")
 local content=Instance.new("Frame"); content.Name="Screens"; content.BackgroundTransparency=1
 content.Size=UDim2.fromScale(1,1); content.Parent=gui
 local self=setmetatable({gui=gui,background=background,session=session,gameplay=gameplay},Shell)
 local context={royale=options.royale==true,parent=content,session=session,gameplay=gameplay,trace=startup,worldRequest=worldRequest,garageRequest=options.garageRequest,
  labTravel=options.labTravel,selectExperiment=options.selectExperiment,
  editorAssets=if type(editorAssets)=="function" then nil else editorAssets,
  getEditorAssets=if type(editorAssets)=="function" then editorAssets else function() return editorAssets end}
 local homeScreen=if options.selectExperiment then "InnovationLab" else "MainMenu"
 local screens=definitions
 if options.selectExperiment then
  screens=table.clone(definitions)
  screens.InnovationLab=require(script.Parent.ShellInnovationLab)
 end
 context.join=function() session:join() end
 function self.playWorld(document,revision)
  if session.mode~="Menu" then return false end
  self.playtest={document=document,revision=revision}
  return session:join()
 end
 context.playWorld=self.playWorld
 context.home=function()
  self.playtest=nil
  self.manager:show(homeScreen)
  if session.mode~="Menu" then session:leave() end
 end
 self.home=context.home
 function self.exitBattle()
  if not self.playtest then context.home();return end
  self.returningToEditor=self.playtest
  self.playtest=nil
  session:leave()
 end
 self.manager=Manager.new(context,screens,function(name)
  gui.Enabled=name~="Battle"
  if name=="Battle" or name=="WorldEditor" then background:exit() else
   startup("showing menu background")
   background:enter()
   startup("menu background shown")
  end
 end)
 startup("creating main menu widgets")
 self.manager:get(homeScreen)
 startup("main menu widgets created")
 self.manager:show(homeScreen)
 gui.Parent=playerGui
 session.onState=function(mode,message)
  if mode=="Menu" and self.returningToEditor then
   local draft=self.returningToEditor
   self.returningToEditor=nil
   self.manager:show("WorldEditor",draft)
   return
  end
  if options.selectExperiment then
   self.manager:show(if mode=="Battle" then "Battle" else homeScreen)
   if mode~="Battle" then self.manager:get(homeScreen):setStatus(if mode=="Joining" then "Starting experiment…" else message) end
   return
  end
  if mode=="Battle" then self.manager:show("Battle")
  elseif mode=="Joining" then self.manager:show("Lobby")
  elseif self.playtest then
   local draft=self.playtest;self.playtest=nil
   self.manager:show("WorldEditor",draft)
   if message then self.manager:get("WorldEditor").view:message(message) end
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
   if context.royale then return Enum.ContextActionResult.Pass end
   if input.KeyCode==Enum.KeyCode.ButtonB then
    if state==Enum.UserInputState.Begin then self.exitBattle() end
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
 return self
end
function Shell:destroy()
 self.session:leave(); self.session.onState=function() end
 Actions:UnbindAction("BattleWorksShellNavigation"); GuiService.SelectedObject=nil
 self.manager:destroy(); self.background:destroy(); self.gui:Destroy()
end
return Shell

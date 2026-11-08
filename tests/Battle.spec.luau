-- Pure local-pair ownership/lifecycle and per-tank editor state regressions.
local Battle=require("LocalBattle")
local BW=require("BWController")
local Sim=require("TankSimulation")
local Command=require("InputCommand")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local battle=Battle.new(7,1)
local function tank(kind)
 return {owner=7,kind=kind,state=Sim.new(Vector3.zero,kind),command=Command.neutral(),hitbox=Instance.new("Part"),lastInput=0}
end
local boomer,rattler=tank("Boomer"),tank("Rattler")
battle.tanks[Battle.id(7,"Boomer")]=boomer; battle.tanks[Battle.id(7,"Rattler")]=rattler
for _,size in {Vector2.new(25,25),Vector2.new(40,2000),Vector2.new(2000,40)} do
 local left,yaw=Battle.pose(size,1,"Boomer")
 local right,otherYaw=Battle.pose(size,1,"Rattler")
 check((right-left).Magnitude>=10,"both spawns remain separated on small maps")
 check(math.abs(left.X)<=size.X/2-5 and math.abs(right.Z)<=size.Y/2-5,"pair spawns inside resized arena")
 check(Sim.forward(yaw).X>0.99 and Sim.forward(otherYaw).X< -0.99,"both face toward opponent")
end
boomer.command.throttle=1; boomer.command.fire=true; boomer.pendingShot={age=0}
local oldState=boomer.state
check(Battle.select(battle,"Rattler"),"select persistent Rattler")
check(boomer.state==oldState and boomer.state.generation==0,"selection does not replace/reset state")
check(boomer.command.throttle==0 and not boomer.command.fire and boomer.pendingShot==nil,"selection clears departing manual input/preparation")
check(not Battle.select(battle,"Unknown") and not Battle.select(battle,{}),"invalid selection rejected")
BW.start(rattler,"forward(100)")
local runtime=rattler.bw
Battle.select(battle,"Boomer")
check(rattler.bw==runtime and BW.running(rattler),"unselected program preserves execution object")
check(not Battle.damage(battle,boomer,boomer,25) and boomer.state.health==100,"no self damage")
local outsider=tank("Rattler"); outsider.owner=8
check(not Battle.damage(battle,boomer,outsider,25),"other owner's local pair cannot damage this pair")
check(Battle.damage(battle,rattler,boomer,25) and rattler.state.health==75,"normal weapon damage retained")
Battle.damage(battle,rattler,boomer,200)
check(rattler.state.health==0 and battle.winner=="Boomer","HP clamps at zero and winner reported")
check(rattler.state.fatalWeapon=="Cannon" and rattler.state.damageByWeapon.Cannon==100,"battle records actual damage and fatal cannon attribution")
check(not BW.running(rattler) and rattler.command.throttle==0 and not rattler.command.fire and rattler.requireFireRelease,"death releases program and all input")
check(not Battle.damage(battle,rattler,boomer,25),"dead tank rejects further damage")
check(not BW.start(rattler,"fire()"),"dead tank cannot restart BW")
boomer.state.health=6
Battle.damage(battle,boomer,rattler,6)
check(battle.winner=="Draw" and boomer.state.health==0,"already-released shells can produce a double KO draw")
check(boomer.state.fatalWeapon=="Gatling","battle records fatal Gatling attribution independently of victim type")
local IDE=require("BWIDE")
local ui=IDE.new(Instance.new("PlayerGui"),function() return 1 end,function() return 2 end)
ui:bind("Boomer"); ui.editor.Text="forward(7)"; ui.pendingRequest=4
ui:bind("Rattler"); ui.editor.Text="fire(2)"; ui.pendingRequest=9
ui:bind("Boomer")
check(ui.editor.Text=="forward(7)" and ui.pendingRequest==4,"Boomer source/pending request restored independently")
ui:update({tankType="Boomer",bwRunning=true,bwRequestId=4,bwStatus="running",bwLine=1})
check(not ui.editor.TextEditable,"running selected tank cannot edit source")
ui:bind("Rattler"); ui:update({tankType="Rattler",bwRunning=false,bwRequestId=9,bwStatus="stopped"})
check(ui.editor.Text=="fire(2)" and ui.editor.TextEditable and not ui.pendingRequest,"Rattler source and stopped status remain independent")
ui:bind("Boomer")
check(ui.editor.Text=="forward(7)","other tank editing never overwrites first source")
ui:destroy()
-- Run -> close editor -> switch -> keyboard/mouse drive, with the other BW
-- runtime still alive. Exercise both tank directions and returning to BW control.
do
 local Controller=require("InputController")
 local Selector=require("TankSelector")
 local savedMouse=UIS.GetMouseLocation
 UIS.GetMouseLocation=function() return Vector2.new(100,100) end
 local camera={ScreenPointToRay=function() return {Origin=Vector3.new(0,20,0),Direction=Vector3.new(0,-1,0)} end}
 local controls=Controller.new(Instance.new("ScreenGui"),function() end)
 controls:setPreference("KeyboardMouse")
 for _,programKind in {"Boomer","Rattler"} do
  local manualKind=if programKind=="Boomer" then "Rattler" else "Boomer"
  local pair=Battle.new(7,1)
  pair.tanks[Battle.id(7,"Boomer")]=tank("Boomer")
  pair.tanks[Battle.id(7,"Rattler")]=tank("Rattler")
  pair.selected=Battle.id(7,programKind)
  local editor=IDE.new(Instance.new("PlayerGui"),function(source)
   BW.start(pair.tanks[pair.selected],source); return 1
  end,function() return 2 end)
  editor.editor.ReleaseFocus=function(self)
   if UIS.focusedTextBox==self then UIS.focusedTextBox=nil; UIS.TextBoxFocusReleased:Fire(self) end
  end
  local function snapshot()
   local selected=pair.tanks[pair.selected].state
   editor:bind(pair.selected); editor:update(selected)
   controls:setExternalControl(selected.bwRunning==true or selected.health<=0)
  end
  snapshot()
  editor.editor.Text="forward(100)"; editor.toggle.Activated:Fire()
  UIS.focusedTextBox=editor.editor; UIS.TextBoxFocused:Fire(editor.editor)
  editor.run.Activated:Fire(); snapshot()
  check(not editor.frame.Visible and UIS:GetFocusedTextBox()==nil,"Run hides IDE and clears native text focus")
  check(controls.suspended and not controls.providers.KeyboardMouse.active,"selected BW tank blocks manual input")
  local selector=Selector.new(Instance.new("ScreenGui"),function(kind)
   editor:close(); controls:release(); controls:setExternalControl(true)
   Battle.select(pair,kind); snapshot()
  end)
  selector:update(pair.tanks[pair.selected].state)
  selector.buttons[manualKind].Activated:Fire()
  check(not controls.suspended and controls.providers.KeyboardMouse.active,"switching to idle tank enables keyboard/mouse")
  UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.W,UserInputType=Enum.UserInputType.Keyboard},false)
  UIS.InputBegan:Fire({KeyCode=Enum.KeyCode.Unknown,UserInputType=Enum.UserInputType.MouseButton1},false)
  local manual=controls:sample(camera)
  check(manual.throttle==1 and manual.fire and manual.aimMode=="World" and manual.aim~=nil,"other tank accepts fresh keyboard movement, mouse aim and fire")
  local programmed=pair.tanks[Battle.id(7,programKind)]
  local runtime=programmed.bw
  local bwInput=BW.input(programmed,1/60)
  check(BW.running(programmed) and programmed.bw==runtime and bwInput.throttle>0,"other tank manual input leaves BW execution running")
  selector:update(pair.tanks[pair.selected].state)
  selector.buttons[programKind].Activated:Fire()
  check(controls.suspended and controls:sample(camera).throttle==0 and not controls:sample(camera).fire,"returning to programmed tank blocks manual controls again")
  BW.stop(programmed,"Test complete."); editor:destroy(); selector:destroy()
 end
 UIS.GetMouseLocation=savedMouse; UIS.focusedTextBox=nil
 controls:setExternalControl(false)
end
print(string.format("Local battle/IDE suite passed: %d assertions",count))

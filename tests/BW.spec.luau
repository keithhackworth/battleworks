local Parser=require("BWParser")
local Runtime=require("BWRuntime")
local Adapter=require("BWTankAdapter")
local Limits=require("BWConfig")
local Sim=require("TankSimulation")
local Command=require("InputCommand")
local Windup=require("WeaponWindup")
local Weapon=require("RattlerWeapon")
local Recoil=require("RattlerRecoil")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local function near(a,b,tolerance) return math.abs(a-b)<(tolerance or 1e-5) end
local program=assert(Parser.parse(Limits.LegacyDefaultSource))
check(#program==8 and program[1].line==3 and program[8].op=="fire","default program parses with original source lines")
local parsed=assert(Parser.parse("# hi\n\nforward(10) #inline\r\nturn_left(to=-90)\nturret_right(to=450)\nfire()\nfire(.5)"))
check(#parsed==5 and parsed[2].value==270 and parsed[3].value==90 and parsed[5].value==0.5,"blank lines, inline comments, CRLF and normalized headings")
for _,source in {"Forward(1)","forward()","forward(-1)","fire(to=90)","fire(11)","forward(1001)","turn_right(1441)","turn_left(to=36001)","forward(1); fire()","while true do","forward(1,2)","fire(unknown())"} do
 local result,err=Parser.parse("# line 1\n"..source)
 check(result==nil and err.line==2 and err.message:find("Line 2:",1,true)==1,"invalid syntax is rejected with its source line")
end
check(Parser.parse(string.rep("x",Limits.MaxSourceBytes+1))==nil,"source byte limit")
check(Parser.parse(string.rep("fire()\n",129))==nil,"instruction count limit")
check(Parser.parse(string.rep("\n",401))==nil,"source line limit")
check(Parser.parse({})==nil,"non-text source rejected")
check(near(Adapter.heading(0),0) and near(Adapter.heading(-math.pi/2),90) and near(Adapter.heading(math.pi/2),270),"compass is clockwise and camera-independent")
local function instruction(source) return assert(Parser.parse(source))[1] end
local sign,angle=Adapter.rotation(instruction("turn_right(to=90)"),0)
check(sign==-1 and near(math.deg(angle),90),"right absolute east turn")
sign,angle=Adapter.rotation(instruction("turn_left(to=90)"),0)
check(sign==1 and near(math.deg(angle),270),"left absolute east honors long route")
sign,angle=Adapter.rotation(instruction("turret_right(to=0)"),math.rad(-350))
check(sign==-1 and near(math.deg(angle),10),"absolute heading wraps across north")
-- Displacement projection counts recoil along the axis, but not wheel spin/side drift.
do
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new({instruction("forward(10)")},s)
 runtime:step(s,1/60)
 s.position=Vector3.new(20,8,0); s.speed=24
 runtime:step(s,1/60)
 check(runtime.current.progress==0 and runtime.status=="running","sideways/vertical drift and intended speed are not forward progress")
 s.position=Vector3.new(20,8,-9.95)
 local output=runtime:step(s,1/60)
 check(runtime.status=="completed" and output.throttle==0 and not output.fire,"actual displacement including recoil completes within tolerance")
end
-- Accumulated rotation survives multiple revolutions instead of shortest-path matching.
do
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new({instruction("turn_right(450)")},s)
 runtime:step(s,1/60)
 for _=1,450 do s.yaw-=math.rad(1); runtime:step(s,1/60) end
 check(runtime.status=="completed","450-degree relative turn tracks accumulated clockwise angle")
 local t=Sim.new(Vector3.zero); t.yaw=math.rad(350)
 runtime=Runtime.new({instruction("turn_left(20)")},t); runtime:step(t,1/60)
 t.yaw=math.rad(10); runtime:step(t,1/60)
 check(runtime.status=="completed","per-tick angular deltas handle wrapped source states")
end
-- Runtime never latches inputs after stop, timeout, destruction or replacement.
do
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new({instruction("forward(5, best_effort=false)")},s)
 for _=1,182 do runtime:step(s,1/60) end
 check(runtime.status=="error" and runtime.message:find("Line 1",1,true)~=nil,"blocked tank produces a line-numbered stuck error")
 local output=runtime:step(s,1/60)
 check(output.throttle==0 and output.steer==0 and not output.fire,"runtime error returns neutral input")
 runtime=Runtime.new({instruction("fire(2)")},s)
 check(runtime:step(s,1/60).fire,"timed fire starts held")
 runtime:stop("Stop pressed")
 check(not runtime:step(s,1/60).fire,"cancellation clears trigger")
 runtime=Runtime.new({instruction("forward(5)")},s); s.health=0
 check(runtime:step(s,1/60).throttle==0 and runtime.status=="stopped","destruction cancels execution")
 s.health=100; runtime=Runtime.new({instruction("forward(5)")},s); s.generation=1
 check(runtime:step(s,1/60).throttle==0 and runtime.status=="stopped","respawn or selection cancels execution")
 runtime=Runtime.new({instruction("forward(1000)")},s); runtime.elapsed=181
 check(runtime:step(s,1/60).throttle==0 and runtime.status=="error","program wall-clock bound is simulated and enforced")
end
-- Advance the unmodified movement/weapons exactly as the real fixed-step server does.
local function run(source,kind,environment,position)
 local instructions=assert(Parser.parse(source))
 local s=Sim.new(position or Vector3.zero,kind,101)
 local runtime=Runtime.new(instructions,s)
 local weapon=Weapon.new(); local pending
 local shots=0; local trace={}; local transitions={}
 local previousIndex=1
 for tick=1,10000 do
  local cmd=runtime:step(s,1/60)
  check(Command.validate(cmd)~=nil,"BW emits the established validated input contract")
  local rapid=Weapon.step(weapon,kind=="Rattler",cmd.fire,1/60)
  s.firing=kind=="Rattler" and weapon.firing; s.heat=weapon.heat
  Sim.step(s,cmd,1/60,nil,environment)
  if kind=="Rattler" then
   if rapid then
    shots+=1; s.weaponActivationSerial=(s.weaponActivationSerial or 0)+1
    s.weaponShotSerial=(s.weaponShotSerial or 0)+1
    local _,direction=Sim.shotPose(s); Recoil.kick(s,weapon.heat,direction)
   end
  else
   if pending then
    local done,origin=Windup.step(pending,s,1/60)
    if done then pending=nil; if origin then shots+=1; s.weaponShotSerial=(s.weaponShotSerial or 0)+1 end end
   end
   if not pending then
    pending=Windup.begin(s,cmd)
    if pending then s.weaponActivationSerial=(s.weaponActivationSerial or 0)+1 end
   end
  end
  if runtime.index~=previousIndex then
   table.insert(transitions,{index=previousIndex,position=s.position,yaw=s.yaw,turret=Adapter.heading(Adapter.angle(s,true))})
   previousIndex=runtime.index
  end
  if tick%60==0 then table.insert(trace,{s.position,runtime.message}) end
  if runtime.status~="running" then return runtime,s,shots,transitions,tick/60 end
 end
 error("BW test exceeded tick budget")
end
for _,kind in {"Boomer","Rattler"} do
 local runtime,s,shots,transitions,time=run(Limits.LegacyDefaultSource,kind)
 check(runtime.status=="completed" and (runtime.skipped or 0)==0,"default demonstration completes with "..kind..": "..runtime.message)
 check(#transitions==8,"all demonstration instructions run sequentially")
 check(near(-transitions[1].position.Z,20,0.2),"forward distance is accurate for "..kind)
 check(math.abs((Adapter.heading(transitions[2].yaw)-90+180)%360-180)<1.2,"clockwise chassis turn reaches east for "..kind)
 check(math.abs((transitions[4].turret+180)%360-180)<1.2,"absolute turret north remains world-relative for "..kind)
 check(shots>=2,"existing weapon fires single/timed activations for "..kind)
 if kind=="Boomer" then check(shots==5,"Boomer fire() plus fire(2) preserves normal cooldown/windup") end
 print(string.format("BW demo %s: %.2fs, %d actual shots",kind,time,shots))
 local one,_,singleShots=run("fire()\nfire()",kind)
 check(one.status=="completed" and singleShots==2,"consecutive single fire commands release and activate exactly once each for "..kind)
 local long,_,longShots=run("turn_left(450)\nturret_right(450)",kind)
 check(long.status=="completed","multi-revolution chassis/turret program completes for "..kind)
end
for _,kind in {"Boomer","Rattler"} do
 local environment=require("Environment").create(Vector2.new(230,230))
 local runtime,_,shots,_,time=run(Limits.LegacyDefaultSource,kind,environment,Vector3.new(-45.5,0,35))
 check(runtime.status=="completed" and (runtime.skipped or 0)==0,"default demo traverses existing terrain with "..kind..": "..runtime.message)
 print(string.format("BW terrain demo %s: %.2fs, %d shots",kind,time,shots))
end
-- IDE default source, server acknowledgments, line errors and cleanup.
do
 local IDE=require("BWIDE")
 local source,stopped,request
 request=0
 local ui=IDE.new(Instance.new("PlayerGui"),function(text) source=text; request+=1; return request end,function() stopped=true; request+=1; return request end)
 check(ui.editor.Text==Limits.DefaultSource and ui.editor.MultiLine and not ui.frame.Visible,"editor opens with the exact default demo")
 ui.toggle.Activated:Fire(); check(ui.frame.Visible,"BW editor toggle opens panel")
 ui.run.Activated:Fire()
 check(source==Limits.DefaultSource and ui.pendingRequest==1 and ui.editor.releasedFocus,"Run sends source text and releases text focus")
 check(not ui.frame.Visible,"Run closes the IDE so gameplay and tank selection are accessible")
 ui:update({bwRequestId=0,bwRunning=false})
 check(ui.pendingRequest==1 and ui.output.Text:find("Submitted",1,true)~=nil,"old snapshots cannot overwrite pending Run feedback")
 ui:update({bwRequestId=1,bwRunning=true,bwStatus="running",bwLine=4,bwIndex=2,bwCount=8,bwInstruction="turn_right(90)",bwMessage="Turning"})
 check(not ui.editor.TextEditable and ui.current.Text:find("Line 4",1,true)~=nil,"running IDE shows active source line and locks edits")
 ui.run.Activated:Fire(); check(request==1,"Run cannot accidentally restart a running program")
 ui.stop.Activated:Fire(); check(stopped and ui.pendingRequest==2,"Stop is available while running")
 ui:update({bwRequestId=2,bwRunning=false,bwStatus="stopped",bwMessage="Stopped by player."})
 check(ui.editor.TextEditable and ui.pendingRequest==nil,"server Stop confirmation restores editing")
 ui:update({bwRequestId=3,bwRunning=false,bwStatus="error",bwMessage="Line 2: Unknown command."})
 check(ui.output.Text:find("Line 2",1,true)~=nil,"line-numbered parser/runtime errors appear in output")
 ui.editor.Text="forward(1)\n\nfire()"; ui.editor:GetPropertyChangedSignal("Text"):Fire()
 check(ui.gutter.Text=="1\n2\n3","editor gutter numbers blank lines too")
 ui:destroy(); source=nil; ui.run.Activated:Fire()
 check(source==nil and ui.gui.destroyed,"IDE cleanup removes UI and event callbacks")
end
-- Manual providers are suspended, cleared and restored at BW ownership changes.
do
 local Controller=require("InputController")
 UIS.focusedTextBox=nil
 local controller=Controller.new(Instance.new("ScreenGui"),function() end)
 controller:setPreference("KeyboardMouse")
 local provider=controller.providers.KeyboardMouse
 provider.held[Enum.KeyCode.W]=true; provider.held[Enum.UserInputType.MouseButton1]=true
 controller:setExternalControl(true)
 local input=controller:sample({})
 check(controller.suspended and input.throttle==0 and not input.fire and not provider.active,"BW ownership suppresses held manual driving/fire")
 controller:setExternalControl(false)
 check(not controller.suspended and provider.active and next(provider.held)==nil,"returning manual control requires fresh presses")
end
-- Server lifecycle cleanup also handles invalid source, death and runtime errors.
do
 local Controller=require("BWController")
 local tank={state=Sim.new(Vector3.zero),rattler=Weapon.new(),command=Command.neutral(),lastInput=1}
 check(Controller.start(tank,"forward(5)"),"server validates and starts BW")
 tank.pendingShot={remaining=0.1}; tank.command.fire=true; tank.tickCommand={fire=true,throttle=1}
 Controller.stop(tank,"Stopped by player.")
 check(not tank.command.fire and tank.tickCommand.throttle==0 and not tank.pendingShot and not tank.state.bwRunning,"server cancellation clears command, trigger and prepared shell")
 check(not Controller.start(tank,"bad()") and tank.state.bwLine==1 and tank.state.bwStatus=="error","invalid source never starts execution")
 Controller.start(tank,"forward(5)"); tank.state.health=0
 local input=Controller.input(tank,1/60)
 check(not input.fire and input.throttle==0 and not tank.state.bwRunning,"destroyed tank stops and clears program inputs")
 tank.state.health=100; Controller.start(tank,"forward(5, best_effort=false)")
 for _=1,182 do Controller.input(tank,1/60) end
 check(tank.state.bwStatus=="completed" and tank.bw.devices.commands[1].state=="failed" and tank.requireFireRelease and not tank.command.fire,"device stuck failure is recorded and returns server ownership safely")
end
for _,kind in {"Boomer","Rattler"} do
 local left,leftState=run("turn_left(to=90)",kind)
 check(left.status=="completed" and leftState.yaw>math.rad(269),"absolute left turn takes the long route to east for "..kind)
 local right,rightState=run("turn_right(to=90)",kind)
 check(right.status=="completed" and rightState.yaw<math.rad(-89),"absolute right turn reaches east clockwise for "..kind)
 local turret,turretState=run("turn_right(90)\nturret_left(to=90)",kind)
 check(turret.status=="completed" and turretState.turretYaw>math.rad(269),"absolute turret heading stays world-relative after chassis turn for "..kind)
 local back,backState=run("forward(10)\nback(10)",kind)
 check(back.status=="completed" and math.abs(backState.position.Z)<0.3,"backward distance uses actual inverse movement for "..kind)
 local zero,_,zeroShots=run("fire(0)",kind)
 check(zero.status=="completed" and zeroShots==0,"zero duration fire produces no activation")
end
do
 local runtime,_,shots,_,time=run("fire(3)\nfire()","Rattler")
 check(runtime.status=="completed" and shots==31 and time>=5,"single-fire waits through existing Rattler overheat lockout without bypass")
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new({instruction("fire(best_effort=false)")},s)
 for _=1,901 do runtime:step(s,1/60) end
 check(runtime.status=="error" and runtime.message:find("timed out",1,true)~=nil,"weapon that never accepts activation fails within bounded time")
end
print(string.format("BW language/runtime suite passed: %d assertions",count))

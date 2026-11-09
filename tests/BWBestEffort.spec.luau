local Parser=require("BWParser")
local Runtime=require("BWRuntime")
local Sim=require("TankSimulation")
local Controller=require("BWController")
local Weapon=require("RattlerWeapon")
local Command=require("InputCommand")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local commands={"forward(10)","back(10)","turn_left(90)","turn_right(90)","turret_left(45)","turret_right(45)","turn_left(to=90)","turn_right(to=90)","turret_left(to=180)","turret_right(to=180)","fire()","fire(2)"}
for _,source in commands do
 local implicit=assert(Parser.parse(source))[1]
 check(implicit.bestEffort==true,"best effort defaults true for every command form")
 for _,flag in {"true","false"} do
  local withFlag=source:sub(1,-2)..(if source=="fire()" then "" else ", ").."best_effort="..flag..")"
  local parsed=assert(Parser.parse(withFlag))[1]
  check(parsed.bestEffort==(flag=="true") and parsed.value==implicit.value and parsed.absolute==implicit.absolute,"explicit option preserves existing argument meaning")
 end
end
local reordered=assert(Parser.parse("turret_left(best_effort=false, to=-90)"))[1]
check(reordered.absolute and reordered.value==270 and not reordered.bestEffort,"named options support either order")
for _,source in {"fire(best_effort=1)","fire(best_effort=true, best_effort=false)","forward(best_effort=false, 10)","turn_left(to=90, to=180)","turn_right(90, to=180)","fire(best_effort=true,)","forward(10,unknown=true)","fire(true)"} do
 local parsed,err=Parser.parse("# header\n"..source)
 check(not parsed and err.line==2,"malformed options remain line-numbered syntax errors")
end
-- Default stuck command skips with neutral output, then executes its successor.
do
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new(assert(Parser.parse("# header\nforward(10)\nfire(0)")),s)
 local neutral
 for _=1,182 do neutral=runtime:step(s,1/60); if runtime.index==2 then break end end
 check(runtime.status=="running" and runtime.index==2 and runtime.skipped==1,"default stuck failure advances rather than aborting")
 check(neutral.throttle==0 and neutral.steer==0 and not neutral.fire,"skip tick releases all intent")
 check(runtime.warning:find("Line 2 skipped",1,true)~=nil,"skipped line and reason persist as warning")
 runtime:step(s,1/60)
 check(runtime.status=="completed" and runtime.skipped==1,"program completes after a best-effort failure")
end
-- All forms, including single/timed fire, can skip an instruction timeout.
for _,source in commands do
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new(assert(Parser.parse(source.."\nforward(0)")),s)
 runtime:step(s,1/60)
 runtime.current.elapsed=runtime.current.timeout+1
 local neutral=runtime:step(s,1/60)
 check(runtime.index==2 and runtime.status=="running" and runtime.skipped==1,"timeout skips every command type")
 check(not neutral.fire and neutral.throttle==0 and neutral.turretX==0,"timed-out command cannot leak an active input")
 runtime:step(s,1/60)
 check(runtime.status=="completed","next command still runs after timeout")
 local strict=source:sub(1,-2)..(if source=="fire()" then "" else ", ").."best_effort=false)"
 runtime=Runtime.new(assert(Parser.parse(strict.."\nforward(0)")),s)
 runtime:step(s,1/60); runtime.current.elapsed=runtime.current.timeout+1
 runtime:step(s,1/60)
 check(runtime.status=="error" and runtime.index==1 and not runtime.skipped,"best_effort=false stops on timeout for every command form")
end
-- Physical failures are now nonfatal device lifecycle outcomes, even for legacy best_effort=false.
do
 local tank={state=Sim.new(Vector3.zero),rattler=Weapon.new(),command=Command.neutral(),bwServices={}}
 tank.bwServices.cancelWeapon=function() tank.pendingShot=nil end
 Controller.start(tank,"fire()\nfire()")
 Controller.input(tank,1/60)
 tank.pendingShot={remaining=0.1}; tank.state.weaponActivationSerial=1
 local device=tank.bw.devices.devices.weapon
 device.active.executor.current.elapsed=16
 local output=Controller.input(tank,1/60)
 check(not output.fire and not tank.pendingShot,"failed device operation cancels abandoned preparation")
 check(Controller.running(tank) and tank.bw.devices.commands[1].state=="failed","queued operation retains BW ownership after recoverable failure")
 check(Controller.input(tank,1/60).fire,"next queued fire starts on next tick")
end
-- Safety limits and explicit cancellation stay terminal regardless of the flag.
do
 local s=Sim.new(Vector3.zero)
 local runtime=Runtime.new(assert(Parser.parse("forward(10)\nfire()")),s)
 runtime.elapsed=181; local output=runtime:step(s,1/60)
 check(runtime.status=="error" and not runtime.skipped and output.throttle==0,"best effort never bypasses the global program limit")
 runtime=Runtime.new(assert(Parser.parse("fire()\nforward(10)")),s)
 runtime:stop("Stop pressed"); output=runtime:step(s,1/60)
 check(runtime.status=="stopped" and runtime.index==1 and not output.fire,"Stop cannot become a skippable failure")
 runtime=Runtime.new(assert(Parser.parse("forward(10)")),s); s.health=0
 runtime:step(s,1/60)
 check(runtime.status=="stopped" and not runtime.skipped,"destruction always stops the program")
end
local IDE=require("BWIDE")
local ui=IDE.new(Instance.new("PlayerGui"),function() return 1 end,function() return 2 end)
ui:update({bwStatus="completed",bwRunning=false,bwMessage="Program completed.",bwWarning="Line 2 skipped: blocked",bwSkipped=1})
check(ui.output.Text:find("Line 2 skipped",1,true)~=nil,"IDE retains skipped-command warning after completion")
ui:destroy()
print(string.format("BW best-effort suite passed: %d assertions",count))

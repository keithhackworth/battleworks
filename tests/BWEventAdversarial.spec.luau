local Parser=require("BWParser")
local Execution=require("BWExecution")
local Hardware=require("BWChassis")
local Simulation=require("TankSimulation")
local Controller=require("BWController")
local Limits=require("BWConfig")
local Value=require("BWValue")
local function make(source,tier,services,options)
 local code,err=Parser.parse(source)
 assert(code,err and err.message)
 local state=Simulation.new(Vector3.zero,"Boomer")
 return Execution.new(code,state,services,Hardware.default(tier),options),state
end

-- Two adjacent expensive handlers can reserve before a later slot ever sees
-- a fresh grant. The main slot still needs periodic service.
local contention,state=make([[function expensive(const event):
    while true:
        hardware = get_tank_state()
on_event("OnDamageTaken", expensive)
with thread(1):
    progress = 0
    while true:
        progress = progress + 1]],"Quad")
for _=1,2 do assert(contention:enqueueEvent("OnDamageTaken",{})) end
for cycle=1,96 do
 contention:step(state,.1)
 assert(contention.cyclesSpent<=cycle*Hardware.Tiers.Quad.ticks+1e-7,"shared credits must remain bounded")
end
assert(contention.variables.progress>25,"a pair of repeated reservations must leave the main program time")
assert(contention.threads[2].ticks>0 and contention.threads[3].ticks>0,"both expensive handlers progress")

local free,freeState=make("function flood(const event):\n"..string.rep("    print(1)\n",600)
 ..'on_event("OnDamageTaken", flood)',"Hexadeca",{outputEnabled=function()return false end})
for _=1,16 do assert(free:enqueueEvent("OnDamageTaken",{})) end
free:step(freeState,.1)
assert(free.outputCount<=Hardware.MaxOperationsPerCycle,"zero-tick instructions cannot multiply host work by slot count")
for _=1,40 do free:step(freeState,.1) end
assert(free.outputCount==16*600,"sliced zero-tick instructions still execute exactly once")

-- A host callback can enqueue, but cannot recursively advance the simulation.
local nested,nestedState
local callbackCount=0
nested,nestedState=make([[function report(const event):
    print(event.number)
on_event("OnDamageTaken", report)]],"Dual",{onPrint=function()
 callbackCount+=1
 if callbackCount==1 then
  assert(nested:enqueueEvent("OnDamageTaken",{number=2}))
  nested:step(nestedState,.1)
 end
end})
assert(nested:enqueueEvent("OnDamageTaken",{number=1}))
nested:step(nestedState,.1)
assert(callbackCount==1 and nested.elapsed==.1 and nested:diagnostics().events.pending==1,
 "callback must not recursively run a new CPU cycle")
nested:step(nestedState,.1)
assert(callbackCount==2 and nested.status=="running","follow-on event runs once on the next host step")

-- A lifecycle stop from a synchronous host callback clears the stack while
-- its coroutine is still unwinding.
local halted,haltedState
halted,haltedState=make([[function report(const event):
    print(1)
    forward()
on_event("OnDamageTaken", report)]],"Dual",{onPrint=function()
 halted:stop("Occupant disconnected.")
end})
assert(halted:enqueueEvent("OnDamageTaken",{}))
local command=halted:step(haltedState,.1)
assert(halted.status=="stopped" and halted.message=="Occupant disconnected." and halted.totalCallFrames==0
 and halted.devices.nextId==0 and command.throttle==0,"a synchronous stop retains its reason and suppresses later commands")

-- Explicit scanner abort races a queued acquisition. Both handlers get one
-- terminal result and forward execution never restarts the scanner call.
local results={}
local acquisitions=0
local service={scan=function(_,_,time)
 acquisitions+=1
 return {value=Value.result(nil,{count=0}),timestamp=time}
end,onPrint=function(value)table.insert(results,value)end}
local scan,scanState=make([[function sense(const event):
    observation = Scanner(0)
    print(observation.status)
function abort_scan(const event):
    abort_command("sensor0")
on_event("OnTankDetected", sense)
on_event("OnWallDetected", abort_scan)]],"Quad",service)
assert(scan:enqueueEvent("OnTankDetected",{}))
assert(scan:enqueueEvent("OnTankDetected",{}))
scan:step(scanState,.1)
assert(scan.devices.devices.sensor0.active and #scan.devices.devices.sensor0.queue==1)
assert(scan:enqueueEvent("OnWallDetected",{}))
for _=1,35 do scan:step(scanState,.1) end
assert(acquisitions==1 and #results==2 and table.find(results,"fail") and table.find(results,"success"),
 "aborted and queued acquisitions deliver one result apiece without a duplicate physical scan")
assert(scan.scanCount==2 and scan.devices.nextId==2 and not scan.devices:busy())
for _,entry in scan.devices.commands do assert(not entry.result and not entry.observation) end

local pausedScans=0
local paused,pausedState=make([[function sense(const event):
    observation = Scanner(0)
    forward()
on_event("OnTankDetected", sense)]],"Bunny",{scan=function(_,_,time)
 pausedScans+=1
 return {value=Value.result(nil,{count=0}),timestamp=time}
end})
local pausedTank={bw=paused,state=pausedState}
assert(paused:enqueueEvent("OnTankDetected",{}))
Controller.input(pausedTank,.1)
local awaiting=paused.threads[1].pending
local commandId=paused.devices.nextId
Controller.suspendInputs(pausedTank)
assert(paused.threads[1].pending==awaiting and pausedTank.tickCommand.throttle==0 and paused.devices.nextId==commandId,
 "parking vehicle inputs retains the owned scan and continuation")
for _=1,30 do Controller.input(pausedTank,.1) end
assert(pausedScans==1 and paused.devices.nextId==commandId+1
 and paused.devices.devices.drivetrain.active.continuous,"resume finishes the original scan and submits the next command once")

local destroyed,destroyedState
destroyed,destroyedState=make([[function sense(const event):
    observation = Scanner(0)
on_event("OnTankDetected", sense)]],"Dual",{scan=function(_,_,time)
 destroyed:stop("Tank destroyed in producer.")
 return {value=Value.result(nil,{count=0}),timestamp=time}
end})
assert(destroyed:enqueueEvent("OnTankDetected",{}))
for _=1,25 do destroyed:step(destroyedState,.1) end
local cancelledScan=destroyed.devices.commands[1]
assert(cancelledScan.state=="cancelled" and not cancelledScan.result and not cancelledScan.observation,
 "a late synchronous scan result cannot resurrect a cancelled request")

local armed,armedState
local weaponCancels=0
armed,armedState=make([[function arm(const event):
    fire()
    wait_for_clock(10)
on_event("OnDamageTaken", arm)]],"Dual",{cancelWeapon=function()
 weaponCancels+=1
 armed:stop("Nested cleanup.")
end})
assert(armed:enqueueEvent("OnDamageTaken",{}))
armed:step(armedState,.1)
armed:stop("Primary lifecycle stop.")
assert(weaponCancels==1 and armed.message=="Primary lifecycle stop." and not armed.devices:busy(),
 "recursive cleanup cannot repeat cancellation or overwrite the original lifecycle reason")

local blocked,blockedState=make([[function wait_forever(const event):
    wait_for(unset)
on_event("OnDamageTaken", wait_forever)]],"Dual")
for _=1,3 do assert(blocked:enqueueEvent("OnDamageTaken",{})) end
for _=1,3 do blocked:step(blockedState,.1) end
assert(blocked.threads[1].pending.kind=="variable" and blocked.threads[2].pending.kind=="variable"
 and #blocked.events.queue==1,"application-level waits can occupy all slots without blocking the host")
blocked.elapsed=Limits.MaxProgramSeconds
blocked:step(blockedState,.1)
assert(blocked.status=="error" and #blocked.events.queue==0,"the program watchdog still ends a wait cycle")

-- A reused logical slot must never cancel a still-active command from its
-- previous event invocation when a later handler faults.
local reuse,reuseState=make([[function drive(const event):
    forward()
function overflow(const event):
    recurse()
function recurse():
    recurse()
on_event("OnTankDetected", drive)
on_event("OnWallDetected", overflow)]],"Bunny",nil,{MaxCallDepthPerThread=4})
assert(reuse:enqueueEvent("OnTankDetected",{}))
for _=1,3 do reuse:step(reuseState,.1) end
assert(reuse.threads[1].state=="finished")
assert(reuse:enqueueEvent("OnWallDetected",{}))
for _=1,5 do reuse:step(reuseState,.1) end
assert(reuse.threads[1].state=="failed" and reuse.devices.devices.drivetrain.active.state=="running"
 and reuse.totalCallFrames==0,"slot reuse preserves old command ownership and unwinds failed frames")

-- Repeated turnover must stay within command-history, queue, thread and
-- payload bounds. The same registered program starts clean on a new generation.
local churn,churnState=make([[function move(const event):
    forward()
on_event("OnDamageTaken", move)]],"Hexadeca")
for tick=1,120 do
 for _=1,Limits.MaxQueuedEvents do churn:enqueueEvent("OnDamageTaken",{sample="churn"}) end
 churn:step(churnState,.1)
 assert(#churn.events.queue<=Limits.MaxQueuedEvents and churn.devices.retainedCount<=Limits.MaxCommandHistory+1)
end
assert(churn.devices.nextId>Limits.MaxCommandHistory and churn.events.dropped>0,"fixture actually exceeds archive and queue capacity")
local oldTank={bw=churn,state=churnState}
churnState.generation=(churnState.generation or 0)+1
assert(not Controller.emitEvent(oldTank,"OnDamageTaken",{}),"stale invocation cannot accept generation-crossing events")
churn:step(churnState,.1)
assert(churn.status=="stopped" and not churn.devices:busy() and #churn.events.queue==0)
local replacement=Execution.new(churn.instructions,churnState,nil,churn.config)
assert(replacement.events.sequence==0 and replacement.devices.nextId==0 and replacement.events.credit==0
 and next(replacement.threads)==nil,"respawning cannot inherit event or device work")
print("Adversarial BW event scheduler review passed")

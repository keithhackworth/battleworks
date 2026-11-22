local Parser=require("BWParser")
local Execution=require("BWExecution")
local Controller=require("BWController")
local Hardware=require("BWChassis")
local Simulation=require("TankSimulation")
local Limits=require("BWConfig")
local chassis=Hardware.default("Dual")
local function runtime(source,services,hardware)
 local instructions,err=Parser.parse(source)
 assert(instructions,err and err.message)
 local state=Simulation.new(Vector3.zero,"Boomer")
 return Execution.new(instructions,state,services,hardware or chassis),state
end

assert(not Parser.parse([[on_event("OnDamageTaken", absent)]]))
assert(not Parser.parse([[function handler(payload):
    print(payload)
on_event("OnDamageTaken", handler)]]))
assert(not Parser.parse([[function handler(const payload):
    alias = payload
    alias.amount = 20
on_event("OnDamageTaken", handler)]]))
assert(not Parser.parse([[function handler(const payload):
    print(payload)
on_event("OnDamageTaken", handler)
on_event("OnDamageTaken", handler)]]))

local printed={}
local vm,state=runtime([[on_event("OnDamageTaken", react)
function react(const observation):
    wait_for_clock(get_clock().time + 0.2)
    print(observation.amount)
with thread(1):
    wait_for_clock(get_clock().time + 5)]],{onPrint=function(value)table.insert(printed,value)end})
vm:step(state,.1)
assert(not vm:enqueueEvent("OnSoundDetected",{}),"unsubscribed event is ignored")
assert(not vm:enqueueEvent("OnDamageTaken",{amount=math.huge}),"non-finite payload is rejected")
local fields={amount=1}
assert(Controller.emitEvent({bw=vm,state=state},"OnDamageTaken",fields))
fields.amount=99
assert(vm:enqueueEvent("OnDamageTaken",{amount=2}))
vm:step(state,.1)
local reading=vm:diagnostics()
assert(reading.threads[1].waiting=="clock" and reading.threads[2].event=="OnDamageTaken"
 and reading.events.pending==1,"busy slots retain FIFO work")
for _=1,12 do vm:step(state,.1)end
assert(#printed==2 and printed[1]=="1" and printed[2]=="2","FIFO dispatch and immutable payload copy")
assert(vm.status=="running","event programs remain subscribed while idle")

local source=[[function react(const observation):
    turret_right(observation.amount)
on_event("OnDamageTaken", react)]]
local commands,commandState=runtime(source)
assert(commands:enqueueEvent("OnDamageTaken",{amount=20}))
assert(commands:enqueueEvent("OnDamageTaken",{amount=40}))
commands:step(commandState,.1)
local turret=commands.devices.devices.turret
assert(turret.active and turret.active.instruction.value==20 and turret.queue[1].instruction.value==40,
 "handlers assigned to two slots submit to the same device FIFO in scheduler order")
assert(commands.devices.nextId==2)

local bus,busState=runtime([[function react(const observation):
    hardware = get_tank_state()
    turret_right(15)
    print(observation.amount)
on_event("OnDamageTaken", react)
with thread(1):
    x = 0
    while true:
        x = x + 1]],{onPrint=function(value)table.insert(printed,value)end})
assert(bus:enqueueEvent("OnDamageTaken",{amount=3}))
for cycle=1,16 do
 bus:step(busState,.1)
 assert(bus.cyclesSpent<=cycle*Hardware.Tiers.Dual.ticks+1e-7,"threads must share exactly one CPU grant per cycle")
end
assert(printed[3]=="3" and bus.variables.x>1,"expensive instruction waits, then both workloads make progress")
assert(bus.devices.nextId==1,"a handler submits its command exactly once after CPU exhaustion")

local capped,capState=runtime(source,nil,Hardware.default("Bunny"))
for i=1,Limits.MaxQueuedEvents do assert(capped:enqueueEvent("OnDamageTaken",{amount=i})) end
local accepted,reason=capped:enqueueEvent("OnDamageTaken",{amount=100})
assert(not accepted and reason=="eventQueueFull" and capped:diagnostics().events.dropped==1,"FIFO overflow rejects newest event")
capped:step(capState,.1)
assert(capped:diagnostics().events.pending==Limits.MaxQueuedEvents-1,"Bunny dispatches one event at a time")
assert(capped.events.queue[1].payload.amount==2 and capped.events.queue[#capped.events.queue].payload.amount==Limits.MaxQueuedEvents,
 "overflow preserves the admitted FIFO and does not coalesce payloads")
capped:stop()
assert(capped:diagnostics().events.pending==0 and not capped:enqueueEvent("OnDamageTaken",{}),"stopping clears queued work")

local expanded,expandedState=runtime(source,nil,Hardware.default("Hexadeca"))
for i=1,17 do assert(expanded:enqueueEvent("OnDamageTaken",{amount=i})) end
expanded:step(expandedState,.1)
local expandedReading=expanded:diagnostics()
assert(expandedReading.events.dispatched==16 and expandedReading.events.pending==1 and expandedReading.threads[16].event=="OnDamageTaken",
 "the existing high-end computer supports 16 event slots")
assert(expanded.cyclesSpent<=Hardware.Tiers.Hexadeca.ticks+1e-7,"16 slots still share one CPU grant")

local legacy,legacyState=runtime([[with thread(1):
    fire()
with thread(2):
    turret_left(20)]])
legacy:step(legacyState,.1)
assert(legacy.events==nil and legacy.devices.nextId==2,"legacy programs retain existing dispatch")

local function movement(first,rotate)
 local controller,state=runtime([[function advance(const event):
    forward()
function reverse(const event):
    back()
on_event("OnTankDetected", advance)
on_event("OnWallDetected", reverse)]])
 if rotate then controller:step(state,.1) end
 assert(controller:enqueueEvent(first,{}))
 assert(controller:enqueueEvent(if first=="OnTankDetected" then "OnWallDetected" else "OnTankDetected",{}))
 local command=controller:step(state,.1)
 assert(controller.devices.commands[1].state=="cancelled" and controller.devices.commands[2].state=="running",
  "later continuous movement replaces the earlier command in scheduler order")
 return command.throttle
end
assert(movement("OnTankDetected")==-1 and movement("OnTankDetected")==-1 and movement("OnWallDetected")==1,
 "identical schedules choose the same movement and reversing submission changes the winner")
assert(movement("OnTankDetected",true)==1,"the rotated execution order, rather than FIFO admission, decides the last movement issuer")

local endless,endlessState=runtime([[function react(const event):
    while true:
        hardware = get_tank_state()
on_event("OnDamageTaken", react)
with thread(1):
    progress = 0
    while true:
        progress = progress + 1]])
assert(endless:enqueueEvent("OnDamageTaken",{}))
local previous=0
for cycle=1,48 do
 endless:step(endlessState,1/10)
 assert(endless.cyclesSpent<=cycle*Hardware.Tiers.Dual.ticks+1e-7,"an endless handler never exceeds the shared grant")
 if cycle%8==0 then
  assert(endless.variables.progress>previous,"main program continues making progress despite repeated expensive handler reservations")
  previous=endless.variables.progress
 end
end
assert(endless.threads[2].state~="finished" and endless.threads[2].ticks>0,"the never-ending handler occupies its slot and also gets CPU")

assert(not Parser.parse("emit_event()"),"BW source cannot publish an engine event")
local storm,stormState
local callbacks=0
storm,stormState=runtime([[function cascade(const event):
    print(event.amount)
on_event("OnDamageTaken", cascade)]],{onPrint=function()
 callbacks+=1
 for _=1,40 do storm:enqueueEvent("OnDamageTaken",{amount=1}) end
end})
assert(storm:enqueueEvent("OnDamageTaken",{amount=1}))
storm:step(stormState,.1)
assert(callbacks==1 and storm:diagnostics().events.pending==Limits.MaxQueuedEvents,"a producer invoked by a handler queues work without reentrant dispatch")
for _=1,10 do storm:step(stormState,.1) end
local stormEvents=storm:diagnostics().events
assert(stormEvents.dropped>0 and stormEvents.pending<=Limits.MaxQueuedEvents and callbacks<=21,
 "a feedback loop stays bounded by pending capacity and available slots per cycle")

local weaponCancels=0
local doomed,doomedState=runtime([[function moving(const event):
    forward()
    fire()
    wait_for_clock(get_clock().time + 30)
function scanning(const event):
    observation = Scanner(0)
on_event("OnTankDetected", moving)
on_event("OnWallDetected", scanning)]],{
 cancelWeapon=function()weaponCancels+=1 end,
 scan=function() error("destroyed tank must never finish the pending scan") end,
})
assert(doomed:enqueueEvent("OnTankDetected",{}))
assert(doomed:enqueueEvent("OnWallDetected",{}))
doomed:step(doomedState,.1)
assert(doomed.threads[1].pending.kind=="clock" and doomed.threads[2].pending.kind=="scan")
assert(doomed.devices.devices.weapon.active,"death fixture has a live weapon request")
assert(doomed.devices:busy() and doomed:enqueueEvent("OnTankDetected",{}))
doomedState.health=0
local stopped=doomed:step(doomedState,.1)
assert(doomed.status=="stopped" and doomed:diagnostics().events.pending==0 and doomed.totalCallFrames==0)
assert(not doomed.devices:busy() and stopped.throttle==0 and not stopped.fire,"death cancels active work and neutralizes input")
assert(weaponCancels==1,"death invokes the weapon cancellation hook")
for _,thread in doomed.threads do
 assert(thread.state=="finished" and not thread.coroutine and not thread.pending and #thread.frames==0 and not thread.instructions,
  "death releases handler payloads held by instruction streams")
end
for _,command in doomed.devices.commands do
 assert(command.state=="cancelled" and not command.result and not command.observation,"death releases command payloads")
end
assert(not Controller.emitEvent({bw=doomed,state=doomedState},"OnTankDetected",{}))
print("BW event scheduling, shared credit, device FIFO, and lifecycle passed")

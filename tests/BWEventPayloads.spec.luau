local Parser=require("BWParser")
local Execution=require("BWExecution")
local Controller=require("BWController")
local Hardware=require("BWChassis")
local Simulation=require("TankSimulation")
local Limits=require("BWConfig")
local Value=require("BWValue")
local source=[[function observe(const event):
    print(event.targets[0].point.x)
    print(event.targets[1])
    print(event.active)
    wait_for_clock(1)
on_event("OnTankDetected", observe)]]
local code,err=Parser.parse(source)
assert(code,err and err.message)
local function subscriber()
 local state=Simulation.new(Vector3.zero,"Boomer")
 local seen={}
 local vm=Execution.new(code,state,{onPrint=function(v)table.insert(seen,v)end},Hardware.default("Bunny"))
 return {bw=vm,state=state},seen
end
local first,firstSeen=subscriber()
local second,secondSeen=subscriber()
local point={x=42,y=7}
local original={targets={{point=point},Value.Null},active=false,emptyArray=Value.array({}),emptyMap={},sample=point}
assert(Controller.emitEvent(first,"OnTankDetected",original))
assert(Controller.emitEvent(second,"OnTankDetected",original))
local snapshot=first.bw.events.queue[1].payload
local other=second.bw.events.queue[1].payload
assert(Value.isDictionary(snapshot) and Value.isArray(snapshot.targets) and Value.isDictionary(snapshot.targets[1].point))
assert(Value.isArray(snapshot.emptyArray) and Value.isDictionary(snapshot.emptyMap),"empty container type is preserved when tagged")
assert(#snapshot.targets==2 and snapshot.targets[2]==Value.Null and snapshot.active==false,"null slots and false values survive copying")
assert(snapshot~=original and snapshot.targets[1].point~=point and other.targets[1].point~=snapshot.targets[1].point)
assert(not table.isfrozen(original) and not table.isfrozen(point),"the producer retains its own mutable tables")
for _,value in {snapshot,snapshot.targets,snapshot.targets[1],snapshot.targets[1].point,snapshot.emptyArray,snapshot.emptyMap,snapshot.sample} do
 assert(table.isfrozen(value),"every nested container is frozen")
end
assert(not pcall(function() snapshot.targets[1].point.x=100 end))
assert(not pcall(function() snapshot.targets[1]=Value.Null end))
point.x=99
original.targets[2]="modified"
original.active=true
for _,tank in {first,second} do
 tank.bw:step(tank.state,.1)
end
assert(first.bw.threads[1].frame.locals.event==snapshot and second.bw.threads[1].frame.locals.event==other,
 "dispatch reuses the validated snapshot without copying")
for _,seen in {firstSeen,secondSeen} do
 assert(table.concat(seen,",")=="42,null,false","both handlers see the original immutable data")
end
assert(Value.format(snapshot.targets)=='[{"point": {"x": 42, "y": 7}}, null]',"event values format like scanner values")

for _,body in {
 "    event.targets[0].point.x = 0",
 "    event.targets[0] = null",
 "    alias = identity(event.targets[0].point)\n    alias.x = 0",
} do
 local program=[[function identity(const item):
    return item
function mutate(const event):
]]..body..'\non_event("OnTankDetected", mutate)'
 local compiled=Parser.parse(program)
 if compiled then
  local state=Simulation.new(Vector3.zero,"Boomer")
  local runtime=Execution.new(compiled,state,nil,Hardware.default("Bunny"))
  assert(runtime:enqueueEvent("OnTankDetected",original))
  local protected=runtime.events.queue[1].payload
  for _=1,4 do runtime:step(state,.1) end
  assert(runtime.status=="error" and runtime.message:find("immutable value",1,true),
   "runtime rejects writes through aliases whose type was not known to the compiler")
  assert(protected.targets[1].point.x==99 and point.x==99,"a rejected write leaves the snapshot and source unchanged")
 end
end
local legacy=assert(Parser.parse([[function echo(amount):
    print(amount)
function react(const event):
    echo(event.amount)
on_event("OnTankDetected", react)]]))
local legacyState=Simulation.new(Vector3.zero,"Boomer")
local flatReading
local flat=Execution.new(legacy,legacyState,{onPrint=function(value)flatReading=value end},Hardware.default("Bunny"))
assert(flat:enqueueEvent("OnTankDetected",{amount=12}))
for _=1,3 do flat:step(legacyState,.1) end
assert(flatReading=="12","existing flat fields still pass through scalar helpers")

local target=subscriber()
local vm=target.bw
local function reject(fields)
 local ok,reason=vm:enqueueEvent("OnTankDetected",fields)
 assert(not ok and reason=="invalidEventPayload" and #vm.events.queue==0,"invalid payload cannot take a queue slot")
end
local cycle={}
cycle.back=cycle
reject(cycle)
local indirect={}
indirect.child={parent=indirect}
reject(indirect)
reject({nested={callback=function()end}})
reject({nested={value=math.huge}})
reject({nested={value=0/0}})
reject({nested={[2]=true}})
reject({nested={[1]=true,label=true}})
reject({nested={[{}]=true}})
reject(Value.array({1,2}))
reject({nested=setmetatable({},{__iter=function()error("must not use producer iteration")end})})
local deep={}
local cursor=deep
for _=1,Limits.MaxEventPayloadDepth do cursor.child={};cursor=cursor.child end
reject(deep)
local repeated={}
for i=1,Limits.MaxArrayItems do repeated[i]="" end
local wide={}
for _=1,math.floor(Limits.MaxEventPayloadElements/Limits.MaxArrayItems)+1 do table.insert(wide,repeated) end
reject({wide=wide})
reject({nested={text=string.rep("a",Limits.MaxStringBytes),more="b"}})

for i=1,Limits.MaxQueuedEvents do assert(vm:enqueueEvent("OnTankDetected",{nested={i}})) end
local ok,reason=vm:enqueueEvent("OnTankDetected",{nested={999}})
assert(not ok and reason=="eventQueueFull" and vm.events.dropped==1)
assert(vm.events.queue[1].payload.nested[1]==1 and vm.events.queue[#vm.events.queue].payload.nested[1]==Limits.MaxQueuedEvents,
 "overflow leaves admitted nested snapshots unchanged and ordered")
vm:stop()
assert(#vm.events.queue==0,"stop releases queued nested snapshots")
print("BW nested event payload validation, isolation, and queue tests passed")

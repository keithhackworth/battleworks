local Parser=require("BWParser")
local Execution=require("BWExecution")
local Hardware=require("BWChassis")
local Simulation=require("TankSimulation")
local hardware=Hardware.default("Hexadeca")
local spec=Hardware.Tiers.Hexadeca
local count=30
local warmup,frames=60,240
local step=1/60
local eventSource=[[function spin(const event):
    pulses = 0
    while true:
        pulses = pulses + 1
on_event("OnDamageTaken", spin)]]
local function run(label,source,events)
 local instructions,err=Parser.parse(source)
 assert(instructions,err and err.message)
 local fleet={}
 for i=1,count do
  local state=Simulation.new(Vector3.new(i*20,0,0),"Boomer")
  local runtime=Execution.new(instructions,state,{outputEnabled=function()return false end},hardware)
  for _=1,events do assert(runtime:enqueueEvent("OnDamageTaken",{}))end
  fleet[i]={state=state,runtime=runtime}
 end
 local samples,total={},0
 for tick=1,warmup+frames do
  local started=os.clock()
  for _,tank in fleet do tank.runtime:step(tank.state,step) end
  if tick>warmup then
   local ms=(os.clock()-started)*1000
   table.insert(samples,ms);total+=ms
  end
 end
 for _,tank in fleet do
  local vm=tank.runtime
  assert(vm.status=="running","every VM survives the workload")
  if events>0 then
   assert(vm.events.sequence==spec.threads and #vm.events.queue==0,"all sixteen slots are occupied")
   assert(vm.cyclesSpent<=(vm.cycle+1)*spec.ticks+1e-7,"a tank never spends more than its single grant per cycle")
   for id=1,spec.threads do
    local thread=vm.threads[id]
    assert(thread and thread.event and thread.ticks>0 and thread.state~="finished","every busy slot makes progress")
   end
  end
  vm:stop()
 end
 table.sort(samples)
 print(string.format("BW fleet %-13s %2d tanks | ms/fixed step avg %.3f p95 %.3f max %.3f",
  label,count,total/frames,samples[math.ceil(frames*.95)],samples[frames]))
end
run("legacy idle","wait_for_clock(179)",0)
run("event idle",eventSource,0)
run("16 busy slots",eventSource,spec.threads)
print("BW 30-tank scheduling workload passed")

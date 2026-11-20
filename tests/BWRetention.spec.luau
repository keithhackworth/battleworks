local Parser=require("BWParser")
local VM=require("BWExecution")
local Sim=require("TankSimulation")
local H=require("BWChassis")
local V=require("BWValue")
local Limits=require("BWConfig")
local count=0
local function check(ok,message)count+=1;assert(ok,message)end
local function run(enabled)
 local source="index = 0\nwhile index < 220:\n    hit = Scanner(0)\n    index = index + 1\nwait_for_clock(get_clock().time + 1)"
 local p,e=Parser.parse(source);assert(p,e and e.message)
 local state=Sim.new(Vector3.zero,"Boomer");local output,scans=0,0
 local services={outputEnabled=function()return enabled end,onEvent=function()output+=1 end,
 scan=function(angle,performance,time)
  scans+=1;local samples={}
  for i=1,24 do table.insert(samples,V.dictionary({elevation=i,slope_angle=0,elevation_rate=0,wetness=0,ground_detected=true},true))end
  return V.observation(V.result(nil,{sensor=angle,timestamp=time,count=0,terrain=V.dictionary({samples=V.array(samples)},true)}),time,state.position,state.yaw)
 end}
 local vm=VM.new(p,state,services,H.default("Hexadeca"))
 for _=1,10000 do vm:step(state,1/60);if vm.status~="running"then break end end
 check(vm.status=="completed"and scans==220,"long scan workload completes through actual BW queues")
 check(#vm.results==Limits.MaxScannerHistory,"intended scanner history remains intact and bounded")
 local archived=0
 for _,command in vm.devices.commands do
  archived+=1
  check(command.result==nil and command.observation==nil and command.executor==nil,"consumed command history retains metadata, not redundant full payloads/executors")
  check(vm.devices:status(command.id).state==command.state,"command_status remains available after payload release")
 end
 check(archived==220 and vm.variables.hit.terrain.samples[24].elevation==24,"program variables retain complete legal scan values")
 vm:stop("test stop")
 check(#vm.results==0 and vm.lastObservation==nil and vm.lastValue==nil,"Stop releases held scan history")
 return vm.cyclesSpent,vm.outputCount,output
end
local a,ac,ao=run(true);local b,bc,bo=run(false)
check(a==b and ac==bc and ao>0 and bo==0,"unoccupied output suppression does not alter CPU fees or program/log attempt semantics")
print("BW long-run payload retention passed: "..count.." assertions")

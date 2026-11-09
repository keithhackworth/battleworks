-- The user's eight independent scan/print loops, running on Rattler's Octa.
local Parser=require(Shared.BWParser)
local Runtime=require(Shared.BWExecution)
local Hardware=require(Shared.BWChassis)
local Value=require(Shared.BWValue)
local Sim=require(Shared.TankSimulation)
local blocks={}
for index=0,7 do
 table.insert(blocks,string.format([[with thread(%d):
    while true:
        scan%d = Scanner(position=%d)
        if scan%d.status == "success" and scan%d.count > 0:
            print(scan%d.detections[0])]],index+1,index,index,index,index,index))
end
local source=table.concat(blocks,"\n\n")
local instructions,err=Parser.parse(source); assert(instructions,err and err.message)
local state=Sim.new(Vector3.zero,"Rattler")
local runtime=Runtime.new(instructions,state,{scan=function(angle,performance,time)
 local hit=Value.dictionary({type="tank",distance=30,relative_direction=angle,world_direction=angle,player="test.enemy#1",relation="enemy",point=Value.dictionary({x=0,y=2.5,z=-30},true)},true)
 return Value.observation(Value.result(nil,{sensor=angle,timestamp=time,count=1,detections=Value.array({hit})}),time,state.position,state.yaw)
end},Hardware.forTank("Rattler"))
for _=1,1800 do
 local input=runtime:step(state,1/60); Sim.step(state,input,1/60)
 if runtime.status~="running" then break end
end
print("Eight-sensor reproduction:",runtime.status,runtime.message,"scans",runtime.scanCount,"outputs",runtime.outputCount)
assert(runtime.status=="running",runtime.message)
assert(runtime.scanCount>512 and runtime.outputCount>1024,"must run past every former lifetime cap")
assert(#runtime.results<=128 and #runtime.devices.completed<=512,"server histories stay bounded")
assert(runtime.devices.retainedCount<=512+8,"retain recent terminal records plus active scans")
for id=1,8 do assert(runtime.threads[id].state~="failed" and runtime.variables["scan"..tostring(id-1)] and runtime.variables["scan"..tostring(id-1)].sensor==(id-1)*45,"each sensor thread keeps producing its own observations") end
runtime:stop("Test Stop")
assert(not runtime.devices:busy() and next(runtime.variables)==nil,"Stop still cancels all eight streams")
print("Eight-sensor continuous-loop regression passed")
-- Excess debugging is rate-limited with an explicit diagnostic, never fatal.
do
 local sections={}; for i=1,8 do table.insert(sections,string.format('with thread(%d):\n    while true:\n        print("debug")',i)) end
 local events,notices=0,0
 local s=Sim.new(Vector3.zero,"Rattler")
 local r=Runtime.new(assert(Parser.parse(table.concat(sections,"\n"))),s,{onEvent=function(event) events+=1; if event.kind=="diagnostic" then notices+=1 end end},Hardware.forTank("Rattler"))
 r:step(s,1/60)
 assert(r.status=="running" and r.suppressedLogs>0 and events<=64 and notices==1,"bounded logging emits an omission notice without stopping")
 local firstCycleEvents=events
 for _=1,6 do r:step(s,1/60) end
 assert(events>firstCycleEvents and events<=128,"logging allowance recovers next CPU cycle")
 assert(r.cyclesSpent>0,"while tests still pay normal CPU ticks")
end
-- Terminal history eviction never evicts active work or changes accepted IDs.
do
 local Devices=require(Shared.BWDevices)
 local s=Sim.new(Vector3.zero,"Rattler")
 local d=Devices.new(Hardware.forTank("Rattler"),s,{})
 local active=d:submit("drivetrain",{op="forward",value=1000,line=1},0,1)
 local ids={}
 for i=1,600 do
  local accepted=d:submit("weapon",{op="fire",value=0,line=1},i,1)
  assert(accepted.status=="success","no lifetime submission ceiling")
  table.insert(ids,accepted.commandId); local input=d:step(s,1/60,i/60); Sim.step(s,input,1/60,Vector2.new(4000,4000))
 end
 assert(d.commands[active.commandId] and d.devices.drivetrain.active,"long-running active command retained")
 assert(d:status(ids[1]).reason=="invalidArgument" and d:status(ids[#ids]).state=="completed","old terminal history expires; recent status remains queryable")
 assert(d.retainedCount<=513 and #d.completed<=512,"command records bounded while IDs increase")
 d:stop(601); assert(not d:busy(),"all work still cancellable after history rollover")
end
-- Chassis validation still rejects this eight-thread program on single-core Boomer.
do
 local Controller=require(Client.BWController)
 local tank={state=Sim.new(Vector3.zero,"Boomer"),command=require(Shared.InputCommand).neutral()}
 assert(not Controller.start(tank,source) and tank.state.bwMessage:find("Bunny",1,true),"select Rattler for eight threads")
end
print("Rolling scanner/log/command history safety passed")
-- Temporary scanner workload failures remain ordinary values in the user's guard.
do
 local s=Sim.new(Vector3.zero,"Rattler"); local calls=0
 local r=Runtime.new(instructions,s,{scan=function(angle,performance,time)
  calls+=1
  if calls%3==0 then return nil,"scannerBusy" end
  local hit=Value.dictionary({type="wall",distance=20,relative_direction=angle,world_direction=angle,player=Value.Null,relation=Value.Null,point=Value.Null},true)
  return Value.observation(Value.result(nil,{sensor=angle,timestamp=time,count=1,detections=Value.array({hit})}),time,s.position,s.yaw)
 end},Hardware.forTank("Rattler"))
 for _=1,600 do r:step(s,1/60); if r.status~="running" then break end end
 assert(r.status=="running" and calls>512,"transient scannerBusy results do not stop/restrict continuous loops")
 r.elapsed=181; r:step(s,1/60)
 assert(r.status=="error" and r.message:find("180",1,true) and not r.devices:busy(),"global runtime timeout still safely stops continuous scanner program")
end
print("Continuous scanner workload recovery and timeout passed")
-- Audit real scanner cooldown/work-budget behavior with all eight physical devices.
do
 local Scanner=require(Client.DirectionalScanner)
 local s=Sim.new(Vector3.zero,"Rattler"); local record={state=s}
 local scanner=Scanner.new({GetPartBoundsInRadius=function() return {} end},function() return {},{} end)
 local successes,failures={},{}
 local r=Runtime.new(instructions,s,{scan=function(angle,performance,time,hardware)
  local observation,reason=scanner:execute(record,angle,time,hardware)
  local counts=if observation then successes else failures
  counts[angle]=(counts[angle] or 0)+1
  return observation,reason
 end},Hardware.forTank("Rattler"))
 for _=1,600 do r:step(s,1/60) end
 local report={}; for position=0,7 do local angle=position*45; table.insert(report,string.format("%d: %d successes / %d failures",position,successes[angle] or 0,failures[angle] or 0)) end
 print("Real scanner per-sensor audit:",table.concat(report,"; "))
 assert(r.status=="running",r.message)
 for position=0,7 do
  local angle=position*45
  assert((successes[angle] or 0)>=50,"query-priority rotation prevents starvation of sensor "..position)
  local status=r:diagnostics().devices["sensor"..angle]
  assert(status.scanAttempts>=99 and status.scanSuccesses==successes[angle] and status.lastScan,"per-sensor scan activity exposed in private diagnostics")
 end
end

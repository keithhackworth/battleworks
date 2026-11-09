local H=require(Shared.BWChassis)
local Parser=require(Shared.BWParser)
local R=require(Shared.BWExecution)
local V=require(Shared.BWValue)
local Sim=require(Shared.TankSimulation)
local checks=0
local function check(v,m) checks+=1; assert(v,m) end
local function runtime(source,tier,services)
 local p,e=Parser.parse(source); assert(p,e and e.message)
 local state=Sim.new(Vector3.zero,"Boomer"); state.tankType="Boomer"
 return R.new(p,state,services,H.default(tier or "Dual")),state
end
local function run(r,s,seconds)
 for _=1,math.floor(seconds*60) do local input=r:step(s,1/60); Sim.step(s,input,1/60) end
end
check(H.performance(50)==0.75,"nonlinear curve")
for name,spec in H.Tiers do check(H.validate(H.default(name)),name.." valid default") end
local bad=H.default("Bunny"); bad.devices.drivetrain.allocation=101; check(not H.validate(bad),"allocation rejected")
local r,s=runtime('with thread(1):\n    ready = false\n    wait_for_clock(0.3)\n    ready = true\nwith thread(2):\n    wait_for(ready)\n    seen = ready')
run(r,s,1); check(r.status=="completed",r.message); check(r.variables.seen==true,"shared wait")
local bunny,bs=runtime('with thread(2):\n    x = 1',"Bunny"); check(bunny.status=="error","capacity enforced")
local quad,qs=runtime('with thread(4):\n    x = 4',"Quad"); run(quad,qs,.2); check(quad.variables.x==4,"quad fourth stream")
local conflict,cs=runtime('with thread(1):\n    x = 1\nwith thread(2):\n    x = 2'); run(conflict,cs,.2); check(conflict.variables.x==2,"ascending last writer")
local sync,ss=runtime('x = false\na = variable_has_changed(x)\nb = variable_has_changed(x)\nx = false\nc = variable_has_changed(x)\nt = get_clock()'); run(sync,ss,.5)
check(sync.variables.a.changed and not sync.variables.b.changed and sync.variables.c.changed,"assignment versions")
check(sync.variables.t.status=="success" and sync.variables.t.time>0,"clock result")
local dict,ds=runtime('d = {"x": 2}\nd.x = 3\ny = d["x"]'); run(dict,ds,.3); check(dict.variables.y==3,dict.message)
local budgetSource={}; for i=1,100 do table.insert(budgetSource,'clock = get_clock()') end
local budget,bgs=runtime(table.concat(budgetSource,"\n"),"Bunny")
budget:step(bgs,1/60); check(budget.cyclesSpent<=10 and budget.threads[1].index<=51,"CPU throttled"); run(budget,bgs,2); check(budget.status=="completed",budget.message)
local queue,ps=runtime('a = forward(100)\nb = back(10)\nc = forward(10)\ncontinued = true',"Bunny")
queue:step(ps,1/60); check(queue.variables.a.status=="success" and queue.variables.b.status=="success","accepted queued")
check(queue.variables.c.reason=="deviceQueueFull" and queue.variables.continued,"nonfatal queue full")
check(#queue.devices.devices.drivetrain.queue==1,"queue invariant")
local active=queue.devices.devices.drivetrain.active.id
queue.devices:manage("drivetrain",false,queue.time); check(queue.devices.devices.drivetrain.active.id==active,"clear preserves active")
queue.devices:manage("drivetrain",true,queue.time); check(queue.devices.commands[active].state=="cancelled","abort lifecycle")
queue:stop(); check(not queue.devices:busy() and next(queue.variables)==nil,"stop cleanup")
print("BW execution suite passed: "..checks.." assertions")
-- Concurrent physical pipelines, FIFO, cross-thread submission and exact acceptance semantics.
do
 local r,s=runtime('with thread(1):\n    a = forward(4)\n    b = back(2)\nwith thread(2):\n    t = turret_right(45)\n    f = fire(0)',"Dual")
 local states={}; local last
 for _=1,180 do
  local input=r:step(s,1/60)
  local c=r.devices.devices.drivetrain.active
  if c and c.id~=last then table.insert(states,c.instruction.op); last=c.id end
  Sim.step(s,input,1/60)
 end
 check(states[1]=="forward" and states[2]=="back","FIFO physical order")
 check(r.variables.t.status=="success" and r.variables.f.status=="success","cross-thread independent devices")
 check(r.devices.commands[r.variables.a.commandId].state=="completed","accepted movement completes")
 check(r.devices.commands[r.variables.t.commandId].started<r.devices.commands[r.variables.a.commandId].completed,"turret operates concurrently")
 check(r.status=="completed",r.message)
end
-- CPU stops charging after submission while drive continues; wait does not steal another thread's credit.
do
 local r,s=runtime('with thread(1):\n    forward(100)\nwith thread(2):\n    wait_for_clock(1)\n    done = true',"Dual")
 r:step(s,1/60); local spent=r.cyclesSpent
 run(r,s,.5); check(r.cyclesSpent==spent,"operating device consumes no CPU ticks")
 check(s.position.Magnitude>0 and r.threads[1].state=="finished" and r.threads[2].state=="waiting","finished stream leaves waiting stream and drive alive")
 run(r,s,.6); check(r.variables.done==true,"clock wait resumed")
end
-- Scanner acquisitions are deferred, independently owned and timestamped at service execution.
do
 local acquisitions={}
 local function scan(angle,performance,time)
  table.insert(acquisitions,{angle=angle,time=time,performance=performance})
  return V.observation(V.result(nil,{type=V.Null,distance=V.Null,relative_direction=V.Null,world_direction=V.Null,player=V.Null,relation=V.Null,sensor=angle,timestamp=time,point=V.Null}),time,s and s.position or Vector3.zero,0)
 end
 local r,s=runtime('with thread(1):\n    a = Scanner(0)\nwith thread(2):\n    b = Scanner(90)',"Hexadeca",{scan=scan})
 r:step(s,1/60); check(#acquisitions==0,"no premature acquisition")
 run(r,s,.3)
 check(#acquisitions==2 and r.variables.a.sensor==0 and r.variables.b.sensor==90,"independent scanner ownership")
 check(r.variables.a.timestamp==acquisitions[1].time and r.variables.a.timestamp>1/60,"actual acquisition time")
 check(r.variables.a.status=="success" and r.variables.a.type==V.Null,"successful empty snapshot")
 check(not pcall(function() r.variables.a.distance=3 end),"immutable scan snapshot")
 check(not Parser.parse('Scanner(100)'),"literal invalid physical sensor")
 local missing,ms=runtime('a = Scanner(45)\ncontinued = true',"Bunny")
 missing.config.devices.sensor45=nil; missing.devices.devices.sensor45=nil
 run(missing,ms,.3); check(missing.variables.a.reason=="deviceUnavailable" and missing.variables.continued,"uninstalled scanner nonfatal")
 local computed,cs=runtime('angle = 100\na = Scanner(angle)\ncontinued = true')
 run(computed,cs,.3); check(computed.variables.a.reason=="invalidSensor" and computed.variables.continued,"computed invalid angle nonfatal")
 local disabled,ds=runtime('a = Scanner(0)\ncontinued = true')
 disabled.devices.devices.sensor0.performance=0; run(disabled,ds,.3)
 check(disabled.variables.a.reason=="deviceDisabled" and disabled.variables.continued,"disabled hardware result")
end
-- Clearing/aborting observations wakes their correct waiting threads; no lost cancellation.
do
 local services={scan=function() error("cancelled scans must not acquire") end}
 local r,s=runtime('with thread(1):\n    result = Scanner(0)\nwith thread(2):\n    abort_command("sensor0")',"Dual",services)
 run(r,s,.4); check(r.status=="completed" and r.variables.result.reason=="commandCancelled","abort wakes scan waiter")
 local device=r.devices.devices.sensor0
 local a=r.devices:submit("sensor0",{op="Scanner",value=0,line=1},1,1)
 local b=r.devices:submit("sensor0",{op="Scanner",value=0,line=1},1,2)
 r.devices:manage("sensor0",false,1)
 check(r.devices.commands[b.commandId].result.reason=="commandCancelled" and device.active.id==a.commandId,"queue clear wakes pending observation without abort")
end
-- Dictionary snapshots and root-reference versioning; invalid runtime values stay safe.
do
 local r,s=runtime('d = {"value": false}\na = variable_has_changed(d)\nd.value = true\nb = variable_has_changed(d)\nx = d.value')
 run(r,s,.3); check(r.variables.a.changed and r.variables.b.changed and r.variables.x,"property mutation increments root version")
 local undef,us=runtime('a = forward(missing)'); run(undef,us,.1)
 check(undef.status=="error" and undef.message:find("Undefined variable",1,true),"undefined argument is a real runtime error")
 local invalid,is=runtime('a = -2\nr = forward(a)\ncontinued = true'); run(invalid,is,.2)
 check(invalid.variables.r.reason=="invalidArgument" and invalid.variables.continued,"invalid operational argument result")
 check(not Parser.parse('wait_for(true)') and not Parser.parse('variable_has_changed(1)'),"variable references statically preserved")
 local errorRuntime,es=runtime('a = Scanner(0)',"Hexadeca",{scan=function() error("fixture engine failure") end})
 run(errorRuntime,es,.2); check(errorRuntime.status=="error" and errorRuntime.message:find("fixture engine failure",1,true),"engine faults surfaced and stopped")
end
-- Full-speed physics is unchanged; allocation affects caps, not acceleration or projectile velocity.
do
 local s=Sim.new(Vector3.zero,"Boomer"); s.drivePerformance=H.performance(50)
 local input=require(Shared.InputCommand).neutral(); input.throttle=1; Sim.step(s,input,1/60)
 check(math.abs(s.speed-24*.75)<1e-8,"drivetrain cap 75 percent")
 check(10*H.performance(50)==7.5,"rated ten gives seven point five")
 local drive=require(Shared.RattlerDrive); local low=Sim.new(Vector3.zero,"Rattler"); low.drivePerformance=.75
 local high=Sim.new(Vector3.zero,"Rattler"); drive.step(low,input,1/60,1); drive.step(high,input,1/60,1)
 check(low.speed==high.speed,"same low-speed acceleration")
 for _=1,180 do drive.step(low,input,1/60,1); drive.step(high,input,1/60,1) end
 check(math.abs(low.speed-22.5)<1e-6 and high.speed==30,"Rattler target cap scaling")
 local lowTurret=Sim.new(Vector3.zero); lowTurret.turretPerformance=.75; input.throttle=0; input.turretX=1
 Sim.step(lowTurret,input,1/60); check(math.abs(lowTurret.turretYaw+3.5*.75/60)<1e-7,"turret allocation rate")
 local Windup=require(Shared.WeaponWindup); local w=Sim.new(Vector3.zero); w.weaponPerformance=.75; input.fire=true
 local pending=Windup.begin(w,input); check(pending and math.abs(pending.remaining-.2/.75)<1e-7,"weapon preparation scaling")
 w.weaponPerformance=0; w.cooldown=0; check(not Windup.begin(w,input),"zero weapon cannot operate")
end
-- Identical fixed simulation steps reached from varying host-frame partitions give identical order.
do
 local function replay(frameSteps)
  local logs={}; local clock=0; local accumulator=0
  local r,s=runtime('with thread(1):\n    wait_for_clock(0.2)\n    x = 1\n    print(x)\nwith thread(2):\n    x = 2\n    print(x)',"Dual",{onPrint=function(text,line,thread) table.insert(logs,thread..":"..text) end,getClock=function() return clock end})
  for _,frame in frameSteps do
   accumulator+=frame
   while accumulator>=1/60-1e-10 do r:step(s,1/60); clock+=1/60; accumulator-=1/60 end
  end
  return table.concat(logs,"|"),r.cyclesSpent,r.variables.x
 end
 local sixty={}; for _=1,60 do table.insert(sixty,1/60) end
 local irregular={}; for _=1,10 do table.insert(irregular,.03); table.insert(irregular,.07) end
 local a,b,c=replay(sixty); local x,y,z=replay(irregular)
 check(a==x and b==y and c==z,"frame partitions deterministic")
end
-- Destruction and generation changes terminate both queues and waiters.
for _,mode in {"health","generation"} do
 local r,s=runtime('with thread(1):\n    forward(100)\n    back(100)\nwith thread(2):\n    wait_for(ready)')
 r:step(s,1/60); if mode=="health" then s.health=0 else s.generation=99 end
 local input=r:step(s,1/60)
 check(r.status=="stopped" and not r.devices:busy() and input.throttle==0 and not input.fire and next(r.variables)==nil,"lifecycle cleanup "..mode)
end
print("BW expanded execution coverage passed: "..checks.." assertions")
-- Fractional expression costs, bounded carryover and zero-cost safety.
do
 local original=H.Costs.print; H.Costs.print=15
 local r,s=runtime('print("once")',"Bunny")
 r:step(s,1/60); check(r.outputCount==0,"insufficient complete operation budget defers side effect")
 run(r,s,.2); check(r.outputCount==1 and r.status=="completed","carryover executes exactly once")
 H.Costs.print=original
 local source={}; for _=1,128 do table.insert(source,'get_clock()') end
 local zero,zs=runtime(table.concat(source,"\n"),"Bunny")
 local oldSafety=H.MaxOperationsPerCycle; H.MaxOperationsPerCycle=16
 zero:step(zs,1/60); check(zero.status=="running" and zero.threads[1].index<128,"zero-cost safety bounded per cycle")
 run(zero,zs,4); check(zero.status=="completed" and zero.cyclesSpent==0,"zero-cost program eventually finishes without charged ticks")
 H.MaxOperationsPerCycle=oldSafety
 local waiting,ws=runtime('wait_for(never)',"Bunny"); run(waiting,ws,3)
 check(waiting.threads[1].credit<=20,"unused credit bounded")
 waiting.elapsed=181; waiting:step(ws,1/60); check(waiting.status=="error" and not waiting.devices:busy(),"global bound cancels indefinite wait")
end
-- Queue race after abort preserves already accepted FIFO work.
do
 local r,s=runtime('a = forward(10)\nb = back(10)',"Dual"); r:step(s,1/60)
 local d=r.devices.devices.drivetrain; local pending=d.queue[1]
 r.devices:manage("drivetrain",true,r.time)
 local third=r.devices:submit("drivetrain",{op="forward",value=1,line=1},r.time,2)
 check(third.status=="success" and d.queue[1]==pending and not d.active,"new submission cannot jump old queue after abort")
 r.devices:step(s,1/60,r.time+1/60); check(d.active==pending,"oldest queued starts next tick")
end
-- Multiple requests to one sensor are serialized and ownership never crosses threads.
do
 local calls=0
 local r,s=runtime('with thread(1):\n    a = Scanner(0)\nwith thread(2):\n    b = Scanner(0)',"Hexadeca",{scan=function(angle,performance,time)
  calls+=1; return V.observation(V.result(nil,{sensor=angle,timestamp=time,sequence=calls}),time,Vector3.zero,0)
 end})
 run(r,s,.5); check(calls==2 and r.variables.a.sequence==1 and r.variables.b.sequence==2,"same-sensor FIFO acquisition ownership")
 check(r.variables.b.timestamp-r.variables.a.timestamp>=.1-1e-8,"same device observations honor sensor cooldown without global gating")
end
-- Server hardware validation and private IDE instrumentation are exercised without Studio layout assumptions.
do
 local Controller=require("BWController")
 local tank={state=Sim.new(Vector3.zero),command=require(Shared.InputCommand).neutral()}
 local valid,reason=Controller.configure(tank,H.default("Bunny")); check(valid and tank.state.drivePerformance==H.performance(40),"server applies validated hardware")
 local invalid=H.default("Bunny"); invalid.devices.turret.bus=2
 check(not Controller.configure(tank,invalid) and tank.hardware.tier=="Bunny","invalid config rejected unchanged")
 Controller.start(tank,'wait_for(ready)'); check(not Controller.configure(tank,H.default("Dual")),"no live hardware mutation")
 Controller.stop(tank)
 local IDE=require("BWIDE"); local configured
 local ui=IDE.new(Instance.new("PlayerGui"),function() return 1 end,function() return 2 end,function(config) configured=config end)
 ui:bind("test"); ui:receiveRuntime("test",{configuration=H.default("Dual"),runtime=R.new(assert(Parser.parse('with thread(2):\n    wait_for(done)')),Sim.new(Vector3.zero),{},H.default("Dual")):diagnostics()})
 ui:update({bwStatus="idle"})
 check(ui.configEditor.Text:find("Dual",1,true)==1 and ui.diagnostics.Text:find("2 threads",1,true),"hardware inspected in IDE")
 ui.applyHardware.Activated:Fire(); check(configured and configured.tier=="Dual","valid config submitted")
 ui.configEditor.Text='Bunny\ndrivetrain 1 100\nturret 1 100'; configured=nil; ui.applyHardware.Activated:Fire()
 check(not configured and ui.diagnostics.Text:find("busOverallocated",1,true),"client feedback validates bus sums")
 ui:receiveOutput("test",0,1,{thread=2,kind="result",line=1,timestamp=.3,text='deviceQueueFull'})
 check(ui.scanOutputs.test.text:find("T2",1,true) and ui.scanOutputs.test.text:find("deviceQueueFull",1,true),"thread timestamp log retained")
 ui:destroy()
end
print("BW final execution coverage passed: "..checks.." assertions")
-- Budget reservation makes ordinary read/modify/write assignments atomic across threads.
do
 local sum={}; for _=1,60 do table.insert(sum,'x') end
 local function balanced(count) if count==1 then return 'x' end; local left=math.floor(count/2); return '('..balanced(left)..' + '..balanced(count-left)..')' end
 local expression=balanced(60)
 local source='x = 1\nwith thread(1):\n    x = '..expression..'\nwith thread(2):\n    x = 2'
 local r,s=runtime(source,"Bunny") -- capacity check separately; use Dual to execute both
 r,s=runtime(source,"Dual")
 r:step(s,1/60); check(r.variables.x==2 and r.threads[1].state=="waiting","expensive assignment has no partial writes or cached reads")
 run(r,s,.3); check(r.variables.x==120,"atomic assignment reads current value when budget available")
end
print("BW atomic reservation coverage passed: "..checks.." assertions")
do
 local one,os=runtime('x = 0\nif x == 1:\n    y = 1')
 local three,ts=runtime('x = 0\nif x == 1:\n    y = 1\nelif x == 2:\n    y = 2\nelif x == 3:\n    y = 3')
 local switch,ss=runtime('x = 0\nswitch x:\n    case 1:\n        y = 1\n    case 2:\n        y = 2\n    case 3:\n        y = 3')
 run(one,os,.3); run(three,ts,.3); run(switch,ss,.3)
 check(one.cyclesSpent<switch.cyclesSpent and switch.cyclesSpent<three.cyclesSpent,"if/switch intended tradeoff has no per-case costs")
 check(math.abs(switch.cyclesSpent-2.3)<1e-8,"switch charged once regardless of number of cases")
 local isolated,is=runtime('print(x)'); run(isolated,is,.2)
 check(isolated.status=="error","new scheduler environments isolated")
 local mixed,ms=runtime('x = false and Scanner(0).type == "tank"\ny = true or Scanner(90).type == "tank"',"Hexadeca",{scan=function() error("short-circuited physical scan") end})
 run(mixed,ms,.2); check(mixed.status=="completed" and mixed.scanCount==0 and mixed.devices.nextId==0,"short circuit has no physical submissions")
end
print("BW acceptance coverage passed: "..checks.." assertions")
do
 local r,s=runtime('forward(100)\nobservation = Scanner(0)\nobservation.type = "wall"',"Hexadeca",{scan=function(angle,performance,time)
  return V.observation(V.result(nil,{sensor=angle,type="tank",timestamp=time}),time,Vector3.zero,0)
 end})
 run(r,s,.3)
 check(r.status=="error" and r.message:find("line 3",1,true) and r.message:find("Cannot mutate",1,true),"BW mutation of scanner snapshot has source diagnostic")
 check(not r.devices:busy() and r:step(s,1/60).throttle==0,"immutable-value runtime error cancels concurrent movement")
end
print("BW final snapshot safety coverage passed: "..checks.." assertions")

do
 local seen
 local r,s=runtime('result = Scanner(0)',"Bunny",{scan=function(angle,performance,time,hardware)
  seen=hardware; return V.observation(V.result(nil,{count=0,detections=V.array({}),range=hardware.range,timestamp=time}),time,Vector3.zero,0)
 end})
 run(r,s,2)
 check(seen and seen.range==150 and seen.distancePercent==100,"low bus allocation still requests full 150-stud effective distance")
 local config=H.default("Bunny"); config.devices.sensor0.range=250; config.devices.sensor0.distancePercent=80
 local copy=H.copy(config)
 check(H.validate(copy) and copy.devices.sensor0.range==250 and copy.devices.sensor0.distancePercent==80,"future scanner range hardware survives validated copying")
end
print("BW scanner range integration passed: "..checks.." assertions")
-- Debugging output is free, including pure reads/formatting expressions. Real
-- device/synchronization/query calls nested inside print keep their normal cost.
do
 local lines={}; for _=1,100 do table.insert(lines,'print("debug")') end
 local free,fs=runtime(table.concat(lines,"\n"),"Bunny")
 free:step(fs,1/60)
 check(free.status=="completed" and free.cyclesSpent==0 and free.outputCount==100,"debug output does not throttle program throughput")
 local pure,ps=runtime('data = {"value": 5}\nprint((data.value + 2) * 3 == 21 and not false)\nprint([data.value, data.value / 2])')
 run(pure,ps,.2)
 check(pure.status=="completed" and math.abs(pure.cyclesSpent-H.Costs.write)<1e-8,"debug-only reads/index/arithmetic/logical operations free")
 local assigned,as=runtime('result = print(123)'); run(assigned,as,.2)
 check(assigned.variables.result.status=="success" and assigned.cyclesSpent==H.Costs.write,"assigning a print result still has ordinary write cost")
 local function scan(angle,performance,time) return V.observation(V.result(nil,{sensor=angle,timestamp=time}),time,Vector3.zero,0) end
 local printed,ss=runtime('angle = 0\nprint(Scanner(angle).timestamp)',"Hexadeca",{scan=scan})
 local ordinary,os=runtime('angle = 0\nScanner(angle)',"Hexadeca",{scan=scan})
 run(printed,ss,.3); run(ordinary,os,.3)
 check(printed.status=="completed" and printed.scanCount==1 and math.abs(printed.cyclesSpent-ordinary.cyclesSpent-H.Costs.access)<1e-8,"printing a scan cannot bypass scan, argument or result access costs")
 local queried,qs=runtime('print(command_status(forward(10).commandId))')
 queried:step(qs,1/60)
 check(math.abs(queried.cyclesSpent-(H.Costs.forward+H.Costs.queue+H.Costs.access))<1e-8,"nested gameplay operations inside print still charged")
 local spent=queried.cyclesSpent
 queried:log(queried.threads[1],"diagnostic",1)
 check(queried.cyclesSpent==spent,"automatic diagnostic logging has no tick charge")
end
print("BW free debug output coverage passed: "..checks.." assertions")

do
 local printed,ps=runtime('print(1 < 2 and forward(0).status == "success")')
 local ordinary,os=runtime('result = 1 < 2 and forward(0).status == "success"')
 run(printed,ps,.2); run(ordinary,os,.2)
 check(printed.status=="completed" and math.abs(printed.cyclesSpent-ordinary.cyclesSpent+H.Costs.write)<1e-8,"debug output cannot waive logic controlling a real operation")
end
print("BW debug gameplay isolation passed: "..checks.." assertions")
-- Actual tank defaults: Boomer has one bus/core; Rattler has eight.
do
 local Controller=require("BWController")
 for _,case in {{"Boomer","Bunny",1,10,1},{"Rattler","Octa",8,30,8}} do
  local config=H.forTank(case[1]); local spec=H.Tiers[config.tier]
  check(config.tier==case[2] and spec.threads==case[3] and spec.ticks==case[4] and spec.queue==case[5],"tank-specific CPU/chassis defaults "..case[1])
  check(H.validate(config),"tank default bus sums valid "..case[1])
  local buses={}; for _,device in config.devices do buses[device.bus]=true end
  local used=0; for _ in buses do used+=1 end
  check(used==case[3],"all assigned chassis buses used "..case[1])
  local tank={state=Sim.new(Vector3.zero,case[1]),command=require(Shared.InputCommand).neutral()}
  local source='with thread('..tostring(case[3])..'):\n    ready = true'
  check(Controller.start(tank,source),"last installed CPU core can run "..case[1])
  Controller.input(tank,1/60)
  check(tank.bw.variables.ready==true and tank.hardware.tier==case[2],"server controller uses tank profile "..case[1])
  Controller.stop(tank)
  check(not Controller.start(tank,'with thread('..tostring(case[3]+1)..'):\n    ready = true'),"server rejects thread beyond tank default capacity "..case[1])
 end
end
print("BW tank chassis coverage passed: "..checks.." assertions")

-- Own facing is an explicit server-state query, with the same compass as to=.
do
 for _,heading in {0,90,180,270,359.9,360,720,-90} do
  local r,s=runtime('facing = get_facing_direction()')
  s.yaw=-math.rad(heading); s.turretYaw=math.rad(57)
  run(r,s,.2)
  local value=r.variables.facing
  check(r.status=="completed" and value.status=="success" and value.reason==V.Null,"facing query standardized result")
  check(math.abs((value.world_direction-heading%360+180)%360-180)<1e-7,"facing follows actual chassis compass heading")
  check(value.world_direction>=0 and value.world_direction<360 and not pcall(function() value.world_direction=0 end),"normalized immutable facing result")
  check(math.abs(r.cyclesSpent-H.Costs.get_facing_direction-H.Costs.write)<1e-8,"facing query cost charged once plus assignment")
 end
 local r,s=runtime('before = get_facing_direction()\nturn_right(90)\nqueued = get_facing_direction()\nclock = get_clock()\nwait_for_clock(clock.time + 0.2)\nafter = get_facing_direction()')
 r:step(s,1/60)
 check(r.variables.before.world_direction==r.variables.queued.world_direction,"queued turn does not fabricate an immediate facing")
 run(r,s,.4)
 check(r.variables.after.world_direction>r.variables.before.world_direction,"later query follows resolved simulation rotation")
 local facing,fs=runtime('goal = get_facing_direction()\nturn_right(to=goal.world_direction)')
 fs.yaw=-math.rad(123)
 run(facing,fs,.3)
 check(facing.status=="completed" and math.abs(fs.yaw+math.rad(123))<1e-8,"facing result directly usable in absolute turn")
 local printed,ps=runtime('print(get_facing_direction())')
 run(printed,ps,.2)
 check(printed.cyclesSpent==H.Costs.get_facing_direction,"printing facing retains explicit gameplay query cost")
 check(not Parser.parse('get_facing_direction(1)') and not Parser.parse('get_facing_direction(to=90)'),"facing query takes no arguments")
end
print("BW facing direction coverage passed: "..checks.." assertions")

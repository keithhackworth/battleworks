local Parser=require(Shared.BWParser)
local Runtime=require(Shared.BWExecution)
local Hardware=require(Shared.BWChassis)
local Value=require(Shared.BWValue)
local Sim=require(Shared.TankSimulation)
local Controller=require(Client.BWController)
local Legacy=require(Shared.BWRuntime)
local count=0
local function check(ok,message) count+=1; assert(ok,message) end
local function new(source,tier,services)
 local instructions,err=Parser.parse(source); assert(instructions,err and err.message)
 local state=Sim.new(Vector3.zero,"Boomer")
 return Runtime.new(instructions,state,services,Hardware.default(tier or "Dual")),state
end
local function run(runtime,state,seconds)
 for _=1,math.ceil(seconds*60) do local input=runtime:step(state,1/60); Sim.step(state,input,1/60); if runtime.status~="running" then break end end
end
for position=0,7 do
 local instruction=assert(Parser.parse("Scanner(position="..position..")"))[1]
 local angle=assert(Parser.parse("Scanner("..(position*45)..")"))[1]
 check(instruction.op=="Scanner" and instruction.value==angle.value and instruction.bestEffort==angle.bestEffort,"position maps to identical physical angle")
end
for _,source in {'Scanner(position=-1)','Scanner(position=8)','Scanner(position=1.5)','Scanner(position=true)','Scanner(position="4")',
 'Scanner(180, position=4)','Scanner(position=4, position=4)','Scanner(position=4, 180)','forward(position=4)'} do
 local p,e=Parser.parse("# first\n"..source)
 check(not p and e.line==2,"invalid positions/signatures rejected before execution: "..source)
end
local requests={}
local services={scan=function(angle,performance,time)
 table.insert(requests,angle)
 return Value.observation(Value.result(nil,{sensor=angle,timestamp=time,count=0,detections=Value.array({})}),time,Vector3.zero,0)
end}
local runtime,state=new('index = 4\na = Scanner(position=index)\nb = Scanner(180)',"Hexadeca",services)
run(runtime,state,1)
check(runtime.status=="completed" and requests[1]==180 and requests[2]==180,"computed position and angle share acquisition path")
check(runtime.variables.a.sensor==180 and runtime.variables.b.sensor==180,"returned sensor retains degrees")
check(math.abs(runtime.cyclesSpent-(Hardware.Costs.write*3+Hardware.Costs.Scanner*2+Hardware.Costs.read))<1e-8,"position has same scanner submission cost")
local bad,bs=new('index = 8\nresult = Scanner(position=index)\ncontinued = true')
run(bad,bs,.4); check(bad.variables.result.reason=="invalidSensor" and bad.variables.continued,"computed invalid position returns nonfatal failure")
local unavailable,us=new('result = Scanner(position=4)')
unavailable.devices.devices.sensor180=nil
run(unavailable,us,.3); check(unavailable.variables.result.reason=="deviceUnavailable","position still requires installed hardware")
-- Every requested falsey value skips the body; empty dictionaries are also empty.
for _,condition in {'0','""','null','false','[]','{}'} do
 local r,s=new('ran = false\nwhile '..condition..':\n    ran = true\n    Scanner(position=0)\ndone = true',"Dual",{scan=function() error("false loop scanned") end})
 run(r,s,.3)
 check(r.status=="completed" and r.variables.ran==false and r.variables.done and r.devices.nextId==0,"falsey loop skips work: "..condition)
end
for _,condition in {'true','1','-1','"hello"','" "','[0]','{"x": false}'} do
 local r,s=new('condition = '..condition..'\ncount = 0\nwhile condition:\n    count = count + 1\n    condition = 0')
 run(r,s,.4); check(r.status=="completed" and r.variables.count==1,"truthy loop executes then reevaluates: "..condition)
end
local loop,ls=new('n = 3\nwhile n:\n    n = n - 1')
run(loop,ls,.4)
check(loop.variables.n==0 and loop.status=="completed","numeric condition reevaluated to zero")
check(math.abs(loop.cyclesSpent-6.1)<1e-8,"loop pays test every iteration including final false, plus normal expressions")
local nested,ns=new('outer = 2\ncount = 0\nwhile outer:\n    inner = 3\n    while inner:\n        count = count + 1\n        inner = inner - 1\n    outer = outer - 1')
run(nested,ns,1); check(nested.variables.count==6 and nested.variables.outer==0 and nested.variables.inner==0,"nested loop backward jumps are local")
local branches,brs=new('n = 3\ncount = 0\nwhile n:\n    switch n:\n        case 2:\n            count = count + 10\n        default:\n            if n == 3:\n                count = count + 1\n            else:\n                count = count + 100\n    n = n - 1')
run(branches,brs,1); check(branches.variables.count==111,"loops compose with switch and if without fallthrough")
local mixed,ms=new('keep = true\nwhile keep:\n    if true:\n        keep = false\nelse_value = 7')
run(mixed,ms,.4); check(mixed.variables.else_value==7,"dedentation after nested body resumes following statement")
local shared,ss=new('with thread(1):\n    keep = true\n    while keep:\n        get_clock()\n    exited = true\nwith thread(2):\n    clock = get_clock()\n    wait_for_clock(clock.time + 0.2)\n    keep = false',"Dual")
run(shared,ss,1); check(shared.status=="completed" and shared.variables.exited,"loop cannot starve another thread setting its shared condition")
local busy,bys=new('while true:\n    get_clock()',"Bunny")
busy:step(bys,1/60)
check(busy.status=="running" and busy.cyclesSpent<=10 and busy.threads[1].state=="waiting","endless loop bounded by CPU budget")
local spent=busy.cyclesSpent; busy:stop("Stop pressed"); busy:step(bys,1/60)
check(busy.status=="stopped" and busy.cyclesSpent==spent and next(busy.variables)==nil,"Stop cancels active loop and clears environment")
local zero,zs=new('while true:\n    get_clock()',"Bunny")
local original=Hardware.Costs.loop; Hardware.Costs.loop=0
zero:step(zs,1/60); Hardware.Costs.loop=original
check(zero.status=="running" and zero.cyclesSpent==0,"zero-cost loop still bounded by hard operation cap")
zero.elapsed=181; zero:step(zs,1/60)
check(zero.status=="error" and zero.message:find("180",1,true),"global timeout terminates runaway loop")
-- Scan conditions run only when reached and wait without repeating acquisition.
local scans=0
local scanning,scs=new('count = 0\nwhile Scanner(position=0).count:\n    count = count + 1',"Hexadeca",{scan=function(angle,performance,time)
 scans+=1
 return Value.observation(Value.result(nil,{sensor=angle,count=if scans<=2 then 1 else 0,timestamp=time}),time,Vector3.zero,0)
end})
run(scanning,scs,1)
check(scanning.status=="completed" and scans==3 and scanning.variables.count==2,"asynchronous loop condition scans once per test")
local drive,ds=new('command = forward(2)\nstatus = command_status(command.commandId)\nwhile status.state == "accepted" or status.state == "running":\n    clock = get_clock()\n    wait_for_clock(clock.time + 0.1)\n    status = command_status(command.commandId)\ndone = true')
run(drive,ds,2)
check(drive.status=="completed" and drive.variables.done and drive.variables.status.state=="completed","loop can poll device completion while physical drive continues")
for _,source in {'while:\n    print(1)','while true\n    print(1)','while true:\nprint(1)','while true:\n  print(1)',
 'while false:\n    unknown_function()','while true:\n    break','while true:\n    continue','while true:\n    with thread(2):\n        print(1)'} do
 check(not Parser.parse(source),"malformed/unsupported loop syntax rejected: "..source)
end
local undefined,uds=new('while missing:\n    print(1)')
run(undefined,uds,.2); check(undefined.status=="error" and undefined.message:find("line 1",1,true) and undefined.message:find("Undefined variable",1,true),"undefined loop condition reports original source line")
local invalid,ivs=new('n = 1\nwhile n:\n    n = n / 0')
-- The division uses a variable, so the error belongs to runtime line 3.
run(invalid,ivs,.2); check(invalid.status=="error" and invalid.message:find("line 3",1,true),"loop body errors retain source line")
local tank={state=Sim.new(Vector3.zero),command=require(Shared.InputCommand).neutral()}
check(Controller.start(tank,'forward(100)\nwhile true:\n    get_clock()'),"controller starts device plus loop")
Controller.input(tank,1/60); Controller.stop(tank,"Stopped")
check(not tank.state.bwRunning and not tank.bw.devices:busy() and tank.command.throttle==0,"controller Stop clears loop and physical command")
local legacyState=Sim.new(Vector3.zero)
local legacy=Legacy.new(assert(Parser.parse('n = 2\nwhile n:\n    n = n - 1')),legacyState)
for _=1,30 do legacy:step(legacyState,1/60) end
check(legacy.status=="completed" and legacy.variables.n==0,"retained interpreter understands new loop control flow")
print("BW loops/positions suite passed: "..count.." assertions")
for _,change in {"health","generation"} do
 local r,s=new('forward(100)\nwhile true:\n    get_clock()')
 r:step(s,1/60)
 if change=="health" then s.health=0 else s.generation=1 end
 local input=r:step(s,1/60)
 check(r.status=="stopped" and not r.devices:busy() and input.throttle==0 and not input.fire,"active loop and drive stop on "..change)
end
local badLimit,badState=new('while true:\n    get_clock()')
badLimit.elapsed=181; badLimit:step(badState,1/60)
check(badLimit.status=="error" and badLimit.message:find("180",1,true),"positive-cost loops retain global duration bound")
check(not Parser.parse('Scanner(position=4, to=180)'),"scanner angle/index alias cannot be mixed with to keyword")
local reordered=assert(Parser.parse('Scanner(best_effort=false, position=4)'))[1]
check(reordered.value==180 and reordered.bestEffort==false,"position and best_effort keyword order supported")
print("BW loops/positions lifecycle passed: "..count.." assertions")

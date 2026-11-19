local Parser=require("BWParser")
local VM=require("BWExecution")
local Sim=require("TankSimulation")
local Hardware=require("BWChassis")
local Limits=require("BWConfig")
local count=0
local function check(ok,m)count+=1;assert(ok,m)end
for _,n in {129,257,1001}do
 local lines={'function identity(const n):','    return n','function nested_call(const n):','    return identity(n)','function recurse(const n):','    if n <= 0:','        return nested_call(n)','    return recurse(n - 1)','x = 0'}
 for _=1,n do table.insert(lines,'x = x + 1')end
 table.insert(lines,'answer = recurse(8)')
 local source=table.concat(lines,'\n');local compiled,err=Parser.parse(source)
 check(compiled~=nil,"large source compiles with ordinary functions: "..n.." "..tostring(err and err.message))
 local s=Sim.new(Vector3.zero);local vm=VM.new(compiled,s,nil,Hardware.default("Octa"))
 for _=1,600 do vm:step(s,1/60);if vm.status~="running"then break end end
 check(vm.status=="completed"and vm.variables.x==n and vm.variables.answer==0,"large source executes normally under unchanged CPU grants")
 check(vm.cyclesSpent>=n*.5,"ordinary read/write/arithmetic accounting preserved")
end
local over=assert(Parser.parse('function recurse(const n):\n    return recurse(n + 1)\nx = recurse(0)'))
local s=Sim.new(Vector3.zero);local vm=VM.new(over,s,nil,Hardware.default("Octa"))
for _=1,1200 do vm:step(s,1/60);if vm.status~="running"then break end end
check(Limits.MaxCallDepthPerThread==50 and vm.status=="error"and vm.message:find("Call stack overflow",1,true),"existing fifty-frame recursive overflow fails safely: "..vm.message)
check(not vm.devices:busy()and vm.totalCallFrames==0,"overflow releases commands and stack resources")
local source='x = 0'..string.rep('\nx = x + 1',1100)
check(Parser.parse(source)~=nil,"no hidden editor-style400-line ceiling")
check(Parser.parse(string.rep('#',Limits.MaxSourceBytes+1))==nil,"technical upload memory bound retained")
local nested='while true:\n';for i=1,14 do nested=nested..string.rep(' ',i*4)..'while true:\n'end
nested=nested..string.rep(' ',60)..'stop()'
check(Parser.parse(nested)==nil,"parser nesting protection remains")
local zero=VM.new(assert(Parser.parse(string.rep("get_clock()\n",1001))),s,nil,Hardware.default("Octa"))
zero:step(s,1/60)
check(zero.status=="running"and zero.threads[1].index<=Hardware.MaxOperationsPerCycle+1,"large zero-cost program still yields at existing per-cycle runaway guard")
check(zero.cyclesSpent==0,"source length does not add a gameplay fee")
local editor=require("BWEditorText").history(source)
editor:record(source.."\nstop()",1,1,"large-edit")
editor:undo()
check(editor.current.text==source,"editor history retains large source verbatim without old line/statement truncation")
local realClock=os.clock
local elapsed=0
os.clock=function()elapsed+=2;return elapsed end
local timed,timeout=Parser.parse(string.rep("stop()\n",200))
os.clock=realClock
check(timed==nil and timeout.message:find("technical time budget",1,true),"technical compilation deadline fails safely without changing gameplay CPU costs")
print("BW large-program safety passed: "..count.." assertions")

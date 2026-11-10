local P=require(Shared.BWParser)
local R=require(Shared.BWExecution)
local H=require(Shared.BWChassis)
local S=require(Shared.TankSimulation)
local V=require(Shared.BWValue)
local checks,cases=0,0
local function check(v,m) checks+=1; assert(v,m) end
local function near(a,b) return math.abs(a-b)<1e-7 end
local function compile(source)
 cases+=1
 local p,e=P.parse(source); check(p~=nil,e and e.message or "compile"); return p
end
local function execute(source,options)
 options=options or {}
 local p=compile(source); local state=S.new(Vector3.zero,"Rattler")
 local logs={}; local services={onPrint=function(text,line,thread) table.insert(logs,{text=text,line=line,thread=thread}) end}
 if options.scan then services.scan=options.scan end
 local r=R.new(p,state,services,H.default(options.tier or "Dual"),options.limits)
 for _=1,options.steps or 600 do
  local input=r:step(state,1/60); S.step(state,input,1/60,Vector2.new(2000,2000))
  if r.status~="running" then break end
 end
 return r,logs,state
end
local function succeeds(source,options)
 local r,logs,state=execute(source,options); check(r.status=="completed",r.message); check(r.totalCallFrames==0,"normal frame cleanup"); return r,logs,state
end
local function invalid(source,part)
 cases+=1; local p,e=P.parse(source); check(p==nil,"must reject: "..source)
 check(e and e.line>=1 and string.find(e.message,part or "Line",1,true)~=nil,e and e.message or "diagnostic")
end
local r=succeeds([[function zero():
    return 7
x = zero()]])
check(r.variables.x==7,"zero argument return")
r=succeeds([[x = later(2, 3)
function later(a, b):
    return a + b]])
check(r.variables.x==5,"forward reference, multiple arguments")
r=succeeds([[function double(const x):
    return x * 2
function add(a, b):
    return a + b
answer = add(double(3), double(double(2)))
if double(2) == 4:
    passed = true]])
check(r.variables.answer==14 and r.variables.passed,"nested expression and conditional calls")
r=succeeds([[function factorial(const n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)
result = factorial(6)]])
check(r.variables.result==720 and r.peakCallFrames==6,"recursive return and independent bindings")
r=succeeds([[function even(const n):
    if n == 0:
        return true
    return odd(n - 1)
function odd(const n):
    if n == 0:
        return false
    return even(n - 1)
a = even(8)
b = odd(7)]])
check(r.variables.a and r.variables.b,"mutual recursion")
r=succeeds([[function empty():
    local_value = 2
function early():
    return
    fire()
x = empty()
y = early()]])
check(r.variables.x==V.Null and r.variables.y==V.Null and r.variables.local_value==nil and r.devices.nextId==0,"implicit/bare return and unexecuted code")
r=succeeds([[value = 99
function change(value):
    value = value + 10
    temp = value
    return temp
CONST original = 5
result = change(original)
again = change(5)]])
check(r.variables.result==15 and r.variables.again==15 and r.variables.value==99 and r.variables.temp==nil,"scalars copied, local scope and shadowing")
r=succeeds([[function update(location):
    location.x = 100
function replace(location):
    location = {x: 0}
position = {x: 3, y: 12}
update(position)
replace(position)
update({x: 1})]])
check(r.variables.position.x==100,"mutable reference changes persist; rebinding stays local")
r=succeeds([[function update(items):
    items[0] = 9
function replace(items):
    items = [100]
a = [1, 2]
update(a)
replace(a)
update([0])]])
check(V.get(r.variables.a,0)==9 and V.get(r.variables.a,1)==2,"array identity and literal reference arguments")
r=succeeds([[function inspect(const target):
    return target.position.x
obj = {position: {x: 3}}
x = inspect(obj)
obj.position.x = 10]])
check(r.variables.x==3 and r.variables.obj.position.x==10,"deep const view does not freeze caller object")
r=succeeds([[function scalar(x):
    x = x + 1
    return x
function inspect(const x):
    return scalar(x)
value = inspect(2)]])
check(r.variables.value==3,"const scalar can pass to mutable scalar")
r=succeeds([[function inner(const obj):
    return obj.x
function outer(const obj):
    return inner(obj)
x = outer({x: 2})]])
check(r.variables.x==2,"const reference forwarding")
r=succeeds([[function change(const protected, mutable):
    mutable.x = 10
left = {x: 1}
right = {x: 2}
change(left, right)]])
check(r.variables.right.x==10 and r.variables.left.x==1,"independently allocated objects accepted")
local failures={
 {'return 2',"return"},
 {'function f():\n    return\nfunction f():\n    return',"Duplicate"},
 {'function f(a, a):\n    return',"duplicate"},
 {'function f():\n    return\nf(1)',"expects"},
 {'function f(a):\n    return\nf()',"expects"},
 {'unknown()',"Unknown"},
 {'function print():\n    return',"Expected"},
 {'function f():\n    return\nf = 3',"function"},
 {'function f(const target):\n    target = 2',"const parameter"},
 {'function f(const target):\n    target.x = 10',"const"},
 {'function f(const target):\n    target.position.x = 10',"const"},
 {'function f(const target):\n    target.history[0].position.x = 10',"const"},
 {'function f(const target):\n    target.history.append(10)',"Expected"},
 {'function f(const target):\n    position = target.location\n    position.x = 10',"const"},
 {'function modify(location):\n    location.x = 10\nfunction inspect(const target):\n    modify(target.position)',"const"},
 {'function modify(location):\n    location.x = 10\nfunction inspect(const target):\n    modify(target)\ninspect({x: 1})',"const"},
 {'function change(const protected, mutable):\n    mutable.x = 10\nobj = {x: 1}\nchange(obj, obj)',"alias"},
 {'function change(const a, b):\n    b.x = 2\nobj = {x: 1}\nalias = obj\nchange(obj, alias)',"alias"},
 {'function change(const a, b):\n    b.x = 2\nobj = {position: {x: 1}}\nchange(obj, obj.position)',"alias"},
 {'function f(const a):\n    alias = a\n    alias[0] = 2\nf([1])',"const"},
 {'function f(const a):\n    alias = {x: a}\n    alias.x[0] = 2\nf([1])',"const"},
}
for _,case in failures do invalid(case[1],case[2]) end
-- Costs use actual production rates; calls, returns and const access are free.
local c=H.Costs
r=succeeds([[function go(distance):
    distance = distance + 10
    forward(distance)
CONST distance = 5
go(distance)]])
check(near(r.cyclesSpent,2*c.write+2*c.read+c.arithmetic+c.forward),"exact mutable binding/read/write ticks")
local free=succeeds([[function go(const distance):
    forward(distance + 10)
go(5)]])
check(near(free.cyclesSpent,c.arithmetic+c.forward),"const binding/read and call/return free")
local literal=succeeds('forward(5 + 10)')
check(near(free.cyclesSpent,literal.cyclesSpent),"const function same cost as inline body")
r=succeeds([[function f(const n):
    if n == 0:
        return 0
    return f(n - 1)
x = f(4)]])
check(near(r.cyclesSpent,5*(c.branch+c.comparison)+4*c.arithmetic+c.write),"exact recursive executed costs")
r=succeeds([[function unused(a):
    a = a + 1
    fire()
x = 1]])
check(near(r.cyclesSpent,c.write),"uncalled function costs nothing")
r=succeeds([[function f(a):
    if a > 0:
        return a
    a = a + 1
x = f(2)]])
check(near(r.cyclesSpent,2*c.read+2*c.write+c.comparison+c.branch),"early return only executes selected branch")
-- Independent call stacks/locals and waits on real virtual threads.
r=succeeds([[function pause(const n):
    local = n
    clock = get_clock()
    wait_for_clock(clock.time + 0.3)
    return local
with thread(1):
    a = pause(10)
with thread(2):
    b = pause(20)]])
check(r.variables.a==10 and r.variables.b==20 and r.peakCallFrames==2,"concurrent stacks survive waits without local leakage")
local depthSource=[[function recurse(const n):
    if n == 0:
        return 1
    return recurse(n - 1)
x = recurse(3)]]
r=succeeds(depthSource,{limits={MaxCallDepthPerThread=4}})
check(r.peakCallFrames==4,"exact configured depth; top level excluded")
local overflow=execute(depthSource,{limits={MaxCallDepthPerThread=3}})
check(overflow.status=="error" and string.find(overflow.message,"recurse",1,true) and string.find(overflow.message,"Thread 1",1,true),"one beyond depth reports function and thread")
check(overflow.totalCallFrames==0 and #overflow.threads[1].frames==0,"overflow cleanup has no leaked frames")
r=succeeds([[function f():
    return 1
x = 0
while x < 100:
    f()
    x = x + 1]])
check(r.peakCallFrames==1,"repeated calls do not leak frames")
local failed=execute([[function bad():
    return 1 / zero
zero = 0
x = bad()]])
check(failed.status=="error" and failed.totalCallFrames==0,"runtime error clears frames")
invalid([[function inspect(const x):
    return x.value
shared = {value: 1}
with thread(1):
    a = inspect(shared)
with thread(2):
    shared.value = 2]],"shared")
-- Read/write/access accounting, live object identity and selected branches.
r=succeeds([[function rotate(const target):
    turn_left(target)
function move(location):
    rotate(location.x)
    location.done = true
move({x: 3, y: 12})]])
check(near(r.cyclesSpent,2*c.write+2*c.read+c.access+c.turn_left),"property traversal and mutation charged exactly once")
check(near(r.threads[1].costs.read,2*c.read) and near(r.threads[1].costs.write,2*c.write),"category-level actual accounting")
r=succeeds([[function f(const a, const b):
    return a + b
x = f(2, 3)
y = f(4, 5)]])
check(near(r.cyclesSpent,2*c.arithmetic+2*c.write),"repeated const calls only arithmetic and destinations")
r=succeeds([[function scalar(x):
    return x
function data():
    return [2, 3]
x = scalar(5)
a = data()
b = a
a[0] = 8]])
check(r.variables.a==r.variables.b and V.get(r.variables.b,0)==8,"returned arrays preserve reference identity")
r=succeeds([[function f(n):
    n = n + 1
    return n
function g(const n):
    return f(n)
x = g(1)
y = f(2)]])
check(r.variables.x==2 and r.variables.y==3,"scalar parameter qualifiers do not change caller values")
r=succeeds([[CONST amount = 8
function f(amount):
    amount = amount + 1
    return amount
x = f(2)
y = amount]])
check(r.variables.x==3 and r.variables.y==8,"parameter shadows compile-time global constant")
r=succeeds([[function fn():
    return 3
function other(fn):
    fn = fn + 1
    return fn
x = other(2)
y = fn()]])
check(r.variables.x==3 and r.variables.y==3,"local value may shadow static function name; call namespace remains static")
r=succeeds([[function worker(const n):
    local = n
    clock = get_clock()
    wait_for_clock(clock.time + 0.2)
    return local
with thread(1):
    a = worker(1)
with thread(2):
    b = worker(2)
with thread(3):
    c = worker(3)
with thread(4):
    d = worker(4)]],{tier="Quad"})
check(r.variables.a==1 and r.variables.b==2 and r.variables.c==3 and r.variables.d==4 and r.peakCallFrames==4,"four independent frames/local environments")
-- Shared global values can still synchronize independent function invocations.
r=succeeds([[ready = false
function wait_ready():
    wait_for(ready)
    return ready
function publish():
    clock = get_clock()
    wait_for_clock(clock.time + 0.3)
    return true
with thread(1):
    seen = wait_ready()
with thread(2):
    ready = publish()]])
check(r.variables.seen==true,"function global reads and wait_for shared identity")
r=succeeds([[function local_ready(n):
    wait_for(n)
    result = variable_has_changed(n)
    return result.changed
x = local_ready(1)]])
check(r.variables.x==false,"local synchronization version observation is frame scoped")
-- Scanner waits resume the exact invocation, with no speculative/duplicate scans.
local acquisitions={}
local function scan(angle,performance,time)
 table.insert(acquisitions,{sensor=angle,time=time})
 return V.observation(V.result(nil,{count=0,detections=V.array({}),sensor=angle,timestamp=time}),time,Vector3.zero,0)
end
r=succeeds([[function observe(const position):
    snapshot = Scanner(position=position)
    return snapshot
with thread(1):
    a = observe(0)
with thread(2):
    b = observe(2)]],{tier="Octa",scan=scan})
check(#acquisitions==2 and r.variables.a.sensor==0 and r.variables.b.sensor==90,"concurrent returned scans preserve ownership")
check(r.variables.a.timestamp>0 and r.variables.b.timestamp>0 and table.isfrozen(r.variables.a),"acquisition timestamps and immutable result preserved")
invalid([[function bad(const target):
    target.x = 10
bad(2)]],"const")
invalid([[function mutate(x):
    x.x = 2
function intermediate(x):
    mutate(x)
function protect(const x):
    intermediate(x)
protect({x: 1})]],"const")
invalid([[function get(const x):
    return x
function protect(const x):
    alias = get(x)
    alias.x = 9
protect({x: 1})]],"const")
invalid([[function protect(const x):
    box = {}
    key = "alias"
    box[key] = x
    alias = box[key]
    alias.x = 9
protect({x: 1})]],"const")
invalid([[function change(const protected, mutable):
    mutable.x = 10
obj = {x: 1}
if true:
    alias = obj
else:
    alias = {x: 2}
change(obj, alias)]],"alias")
invalid([[global = {x: 1}
function mutate_global():
    global.x = 10
function protect(const target):
    mutate_global()
protect(global)]],"const")
invalid([[function f(const x):
    a = clone(x)
f({x: 1})]],"Unknown") -- no pre-existing public clone API to extend
r=succeeds([[function copy_fields(const source):
    local_copy = {x: source.x}
    local_copy.x = 10
    return local_copy.x
x = copy_fields({x: 1})]])
check(r.variables.x==10,"independent storage assembled from scalar fields remains mutable")
-- Stack capacities come from server settings and installed computer thread capacity.
for _,tier in {"Bunny","Dual","Quad","Octa","Hexadeca"} do
 local rt=execute('function f():\n    return 1\nx = f()', {tier=tier})
 check(rt.maxCallDepth==50 and rt.maxTotalCallFrames==50*H.Tiers[tier].threads,"derived total capacity for "..tier)
end
r=succeeds([[function f(const n):
    if n == 0:
        return 0
    return f(n - 1)
x = f(49)]],{tier="Bunny",steps=1200})
check(r.peakCallFrames==50,"default exactly 50 frames")
local over=execute([[function f(const n):
    if n == 0:
        return 0
    return f(n - 1)
x = f(50)]],{tier="Bunny",steps=1200})
check(over.status=="error" and over.totalCallFrames==0 and over.peakCallFrames==50,"default overflow does not push 51st frame")
local independent=execute([[function fail():
    return fail()
function okay():
    clock = get_clock()
    wait_for_clock(clock.time + 0.4)
    return 42
with thread(1):
    fail()
with thread(2):
    success = okay()]],{limits={MaxCallDepthPerThread=4}})
check(independent.status=="error" and independent.variables.success==42 and independent.threads[2].state=="finished","overflow in one thread leaves unrelated thread operational")
check(independent.totalCallFrames==0 and #independent.threads[1].frames==0,"isolated overflow total counter cleanup")
local both=succeeds([[function f(const n):
    if n == 0:
        clock = get_clock()
        wait_for_clock(clock.time + 0.2)
        return 1
    return f(n - 1)
with thread(1):
    a = f(3)
with thread(2):
    b = f(3)]],{limits={MaxCallDepthPerThread=4}})
check(both.peakCallFrames==8 and both.maxTotalCallFrames==8,"threads concurrently reach derived total frame capacity")
-- Lower the server aggregate guard independently to exercise failed push atomicity.
do
 local state=S.new(Vector3.zero,"Rattler")
 local rt=R.new(compile([[function f():
    clock = get_clock()
    wait_for_clock(clock.time + 0.2)
    return 1
with thread(1):
    a = f()
with thread(2):
    b = f()]]),state,nil,H.default("Dual"),{MaxCallDepthPerThread=3})
 rt.maxTotalCallFrames=1
 for _=1,120 do rt:step(state,1/60) end
 check(rt.status=="error" and rt.variables.a==1 and rt.variables.b==nil,"aggregate guard independent of per-thread depth")
 check(rt.totalCallFrames==0 and rt.peakCallFrames==1,"failed aggregate push leaves counts unchanged")
end
-- CPU starvation resumes exactly once; free operations still have a dispatch cap.
do
 local state=S.new(Vector3.zero,"Rattler")
 local source=[[function free():
    get_clock()
while true:
    free()]]
 local rt=R.new(compile(source),state,nil,H.default("Bunny"))
 rt:step(state,1/60)
 check(rt.status=="running" and rt.threads[1].ticks<=H.Tiers.Bunny.ticks+1e-8,"bounded scheduler handles repeated free functions")
 rt:stop("cancelled")
 check(rt.totalCallFrames==0 and rt.threads[1].coroutine==nil and not rt.devices:busy(),"cancel clears coroutine/frame/device state")
end
-- Destruction, generation change and Stop while suspended inside a function.
for _,reason in {"stop","destroy","reset"} do
 local state=S.new(Vector3.zero,"Rattler")
 local rt=R.new(compile([[function wait():
    forward()
    clock = get_clock()
    wait_for_clock(clock.time + 100)
wait()]]),state,nil,H.default("Bunny"))
 rt:step(state,1/60)
 check(rt.totalCallFrames==1 and rt.devices:busy(),"function is suspended with active drivetrain")
 if reason=="stop" then rt:stop("stop")
 elseif reason=="destroy" then state.health=0; rt:step(state,1/60)
 else state.generation=(state.generation or 0)+1; rt:step(state,1/60) end
 check(rt.totalCallFrames==0 and not rt.devices:busy() and rt.threads[1].coroutine==nil,"lifecycle cleanup: "..reason)
end
-- Static errors retain source locations even in uncalled function bodies.
do
 cases+=1
 local _,err=P.parse('function okay():\n    return 1\nfunction wrong(const target):\n    target.x = 2')
 check(err and err.line==4,"deep const diagnostic identifies source line")
end

r=succeeds([[function copy(x):
    return x
result = copy(get_clock().time)]])
check(type(r.variables.result)=="number","known scalar metadata from built-ins can pass by value")
r=succeeds([[function truth(const v):
    return v
a = truth(false)
b = truth(0)
c = truth("")
d = truth(null)]])
check(r.variables.a==false and r.variables.b==0 and r.variables.c=="" and r.variables.d==V.Null,"falsy returns preserved without conversion")
r=succeeds([[function add(x):
    return x + 1
const start = 2
x = add(start)]])
check(r.variables.x==3,"lowercase compile-time const spelling")
invalid('function f():\n    return 1 / 0',"Division")
invalid('function outer():\n    function inner():\n        return',"top level")
invalid('function f():\n    return\nf(x=1)',"expects")
invalid('function f(const x):\n    return x\nf(x=1)',"positional")
invalid('function f(a):\n    return a\nCONST f = 2',"conflicts")
-- Low CPU throughput cannot duplicate nested side effects while resuming.
do
 local reads,writes,arithmetic=H.Costs.read,H.Costs.write,H.Costs.arithmetic
 H.Costs.read=6; H.Costs.write=7; H.Costs.arithmetic=6
 local a=succeeds([[function emit(a):
    print("once")
    return a + 1
x = emit(2) + emit(3)]],{tier="Bunny",steps=1200})
 check(a.printCount==2 and a.variables.x==7 and a.threads[1].credit>=-1e-8,"nested calls resume without duplicate prints or negative budget")
 H.Costs.read=reads; H.Costs.write=writes; H.Costs.arithmetic=arithmetic
end
-- Every scheduler run follows the same call ordering and charged budget trace.
do
 local source=[[function f(const n):
    if n == 0:
        return 1
    return f(n - 1) + 1
with thread(1):
    a = f(4)
with thread(2):
    b = f(3)]]
 local function trace(dt)
  local state=S.new(Vector3.zero,"Rattler")
  local rt=R.new(compile(source),state,nil,H.default("Dual")); local totals={}
  for _=1,60 do rt:step(state,dt); table.insert(totals,rt.cyclesSpent) end
  return rt,totals
 end
 local a,at=trace(1/60); local b,bt=trace(1/60)
 for i=1,#at do check(at[i]==bt[i],"deterministic per-tick recursive budget trace") end
 check(a.variables.a==b.variables.a and a.variables.b==b.variables.b,"deterministic concurrent results")
 local slow=trace(1/30)
 check(a.cyclesSpent==slow.cyclesSpent,"render/frame variation preserves final executed costs")
end
-- Compiler suggestions are optional metadata, never automatic source edits.
do
 local p=compile('function read(distance):\n    return distance\nx = read(2)')
 check(#p.tips==1 and p.tips[1].line==1 and p.tips[1].message:find("const",1,true),"unmodified scalar parameter tip")
 local p2=compile('function change(distance):\n    distance = 2\n    return distance\nx = change(1)')
 check(#p2.tips==0,"modified parameter gets no const suggestion")
end

do
 local source=[[function f(const n):
    if n == 0:
        clock = get_clock()
        wait_for_clock(clock.time + 0.5)
        return 1
    return f(n - 1)
]]
 for id=1,16 do source..=string.format("with thread(%d):\n    result%d = f(49)\n",id,id) end
 local rt=succeeds(source,{tier="Hexadeca",steps=1200})
 check(rt.peakCallFrames==800 and rt.maxTotalCallFrames==800,"all sixteen threads can reach their own 50-frame limit concurrently")
 for id=1,16 do check(rt.variables["result"..id]==1 and rt.threads[id].peakCallDepth==50,"independent full-depth stack on thread "..id) end
end
do
 local rt,state
 state=S.new(Vector3.zero,"Rattler")
 rt=R.new(compile([[function overflow():
    return overflow()
function drive_and_fail():
    steer_right(20)
    forward()
    overflow()
with thread(1):
    drive_and_fail()
with thread(2):
    steer_left(10)
    forward()]]),state,nil,H.default("Dual"),{MaxCallDepthPerThread=3})
 rt:step(state,1/60)
 check(rt.threads[1].state=="failed" and rt.devices.devices.drivetrain.active.thread==2,"failed thread cannot cancel another thread's drivetrain work")
 check(rt.devices.steering>0 and rt.totalCallFrames==0,"other thread retains its steering after isolated overflow")
 rt:stop("done")
end
r=succeeds([[function f(const n):
    return n
with thread(1):
    shared = f(1)
with thread(2):
    shared = f(2)]])
check(r.variables.shared==2,"simultaneous function results use documented ascending thread order")
r=succeeds([[function f(const n):
    return n + 1
print(f(2))]])
check(near(r.cyclesSpent,c.arithmetic),"print cannot waive user function body gameplay work")
-- Per-frame errors do not leak private names into shared global state.
local scoped=execute([[function f():
    if false:
        value = 3
    return value
value = 99
x = f()]])
check(scoped.status=="error" and scoped.message:find("Undefined variable",1,true),"lexical local reads before binding do not fall back to shared globals")

for _,literal in {"3",'"text"',"null","false"} do
 local rt=execute("function mutate(value):\n    value.x = 1\nmutate("..literal..")")
 check(rt.status=="error" and rt.message:find("Cannot mutate",1,true) and not rt.message:find("Internal",1,true),"invalid scalar mutation is a BW diagnostic")
end

-- Even a server-tuned zero-cost loop cannot monopolize a simulation step.
do
 local savedLoop=H.Costs.loop; H.Costs.loop=0
 local state=S.new(Vector3.zero,"Rattler")
 local rt=R.new(compile('function free():\n    get_clock()\nwhile true:\n    free()'),state,nil,H.default("Bunny"))
 rt:step(state,1/60)
 check(rt.status=="running" and rt.cyclesSpent==0 and (rt.threads[1].loopTests or 0)>0,"hard dispatch cap applies when every executed operation costs zero")
 rt:stop("stop"); H.Costs.loop=savedLoop
 check(rt.totalCallFrames==0,"zero-cost suspension cleanup")
end
r=succeeds('function lower():\n    return 1\nfunction Lower():\n    return 2\nx = lower() + Lower()')
check(r.variables.x==3,"function names retain case sensitivity")
invalid('function lower():\n    return 1\nLOWER()',"Unknown")

print(string.format("BW functions suite passed: %d assertions across %d program checks",checks,cases))

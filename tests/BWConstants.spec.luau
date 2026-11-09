local P=require(Shared.BWParser)
local R=require(Shared.BWExecution)
local H=require(Shared.BWChassis)
local S=require(Shared.TankSimulation)
local V=require(Shared.BWValue)
local E=require(Shared.BWExpression)
local checks=0
local function check(v,m) checks+=1; assert(v,m) end
local function parse(source) local p,e,ast=P.parse(source); assert(p,e and e.message); return p,ast end
local function execute(source)
 local p=parse(source); local state=S.new(Vector3.zero,"Boomer")
 local r=R.new(p,state,nil,H.default("Dual")); local trace={}
 for i=1,180 do local input=r:step(state,1/60); S.step(state,input,1/60); trace[i]={ticks=r.cyclesSpent,position=state.position,yaw=state.yaw} end
 return r,trace
end
local p,ast=parse('CONST distance = 10\nCONST double = distance * 2\nforward(double)')
check(#p==1 and p[1].value==20 and p[1].call==nil,"constant command compiles to literal instruction")
check(ast[1].kind=="const" and ast[2].value==20,"source AST retains evaluated declarations")
local only=execute('CONST n = null\nCONST b = false\nCONST s = "hello"\nCONST x = -2 + 4 * (8 / 2)\nCONST test = x == 14 and not b')
check(only.cyclesSpent==0 and next(only.variables)==nil,"declarations emit no runtime storage or costs")
local r=execute('CONST n = null\nCONST b = false\nCONST s = "hello"\nCONST x = -2 + 4 * (8 / 2)\nCONST test = x == 14 and not b\na = n\nboolean_value = b\nc = s\nd = x\nif test:\n    passed = true')
check(r.variables.a==V.Null and r.variables.boolean_value==false and r.variables.c=="hello" and r.variables.d==14 and r.variables.passed,"all scalar types and conditions")
local literal='forward(10)\nback(10)\nturn_left(90)\nforward(10)'
local named='CONST move = 5 * 2\nCONST turn = 180 / 2\nforward(move)\nback(move)\nturn_left(turn)\nforward(move)'
local a,at=execute(literal); local b,bt=execute(named)
check(a.cyclesSpent==4 and b.cyclesSpent==a.cyclesSpent,"command ticks identical")
for i=1,#at do check(at[i].ticks==bt[i].ticks and (at[i].position-bt[i].position).Magnitude<1e-8 and at[i].yaw==bt[i].yaw,"per-frame reservation/scheduling/physical equivalence") end
local variable=execute('move = 10\nforward(move)')
local constant=execute('CONST move = 10\nforward(move)')
check(math.abs(variable.cyclesSpent-constant.cyclesSpent-H.Costs.write-H.Costs.read)<1e-8,"ordinary writes and reads still charged")
local concurrent=execute('CONST shared = 10\nwith thread(1):\n    x = shared\nwith thread(2):\n    y = shared')
check(concurrent.variables.x==10 and concurrent.variables.y==10 and concurrent.variables.shared==nil,"cross-thread substitution without shared-state storage")
local inside=execute('with thread(1):\n    CONST amount = 2\n    x = amount\nwith thread(2):\n    y = amount')
check(inside.variables.y==2,"program-wide textual scope matches BW shared namespace")
local invalid={
 'CONST x = 1\nx = 2', 'CONST x = null\nx = 2', 'CONST x = false\nCONST x = 2',
 'CONST x = 1\nx.field = 2','CONST x = 1\nx[0] = 2',
 'CONST x = unknown', 'CONST x = x', 'CONST x = y\nCONST y = x',
 'v = 1\nCONST x = v', 'CONST x = get_clock()', 'CONST x = Scanner(0)',
 'CONST x = false and fire()', 'CONST x = true or missing',
 'CONST x = [1]', 'CONST x = {"a": 1}', 'CONST x = [1][0]',
 'CONST x = 1\nCONST x = 1', 'x = 1\nCONST x = 2',
 'CONST x = 1\nwith thread(2):\n    x = 2',
 'CONST forward = 1', 'CONST true = 1', 'CONST x', 'CONST 2 = 1',
 'CONST x = 1 / 0', 'CONST x = "a" + 1', 'CONST x = 1e308 * 10',
 'CONST angle = 100\nScanner(angle)', 'CONST x = 1\nwait_for(x)',
 'CONST x = 1\nvariable_has_changed(x)', 'CONST x = 1\nCONST y = X',
}
for _,source in invalid do local bad,err=P.parse(source); check(not bad and err.line>=1 and err.message:find('Line '),"invalid constant: "..source) end
local _,err=P.parse('CONST x = 1\n\nx = 2'); check(err.line==3,"diagnostic points at mutation")
local case=execute('CONST x = 1\nCONST X = 2\na = x\nb = X'); check(case.variables.a==1 and case.variables.b==2,"case-sensitive names")
-- Real evaluator sees literal nodes, so it cannot charge a read or expression operation.
local cp=parse('CONST value = (10 + 5) / 3\na = value')
local charged=0; check(E.evaluate(cp[1].expression,{variables={},charge=function() charged+=1 end})==5 and charged==0,"literal substitution zero evaluated costs")
local folded=execute('CONST enabled = 1 < 2 and not false\nif enabled:\n    forward(1)')
local plain=execute('if true:\n    forward(1)')
check(folded.cyclesSpent==plain.cyclesSpent,"compile-time comparison/logical work free")
local namedMany={'CONST item = 3 * 7'}; local literalMany={}
for i=1,70 do table.insert(namedMany,'v'..i..' = item'); table.insert(literalMany,'v'..i..' = 21') end
local throttledNamed,nt=execute(table.concat(namedMany,"\n")); local throttledLiteral,lt=execute(table.concat(literalMany,"\n"))
for i=1,#nt do check(nt[i].ticks==lt[i].ticks,"reservation equality across exhausted CPU cycles") end
check(throttledNamed.variables.v70==21 and throttledNamed.cyclesSpent==throttledLiteral.cyclesSpent,"budget deferral preserves results")
local operators=execute('CONST a = +8 - 2\nCONST b = a >= 6 and a <= 6\nCONST c = a != 5 or false\nCONST d = "a" < "b"\nCONST e = null == null\nCONST f = a > 0\nif b and c and d and e and f:\n    ok = true\nswitch a:\n    case 6:\n        matched = true')
check(operators.variables.ok and operators.variables.matched,"constant comparisons, unary plus, switch labels")
check(not P.parse('CONST value = 1\nif false:\n    value = 2'),"unreachable mutation is rejected statically")
print('BW CONST suite passed: '..checks..' assertions')

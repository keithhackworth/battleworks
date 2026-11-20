local Parser=require("BWParser")
local VM=require("BWExecution")
local Sim=require("TankSimulation")
local H=require("BWChassis")
local C=require("VehicleComponents")
local Controller=require("BWController")
local count=0
local function check(ok,message)count+=1;assert(ok,message)end
local function run(source)
 local p,e=Parser.parse(source);check(p~=nil,e and e.message or "parse")
 local state=Sim.new(Vector3.zero,"Boomer")
 local hardware=H.default("Bunny",C.get(state));local tank={state=state,hardware=hardware}
 Controller.applyHardware(tank)
 local vm=VM.new(p,state,{},hardware)
 for _=1,1200 do local command=vm:step(state,1/60);Sim.step(state,command,1/60);if vm.status~="running"then break end end
 return vm,state,p
end
local direct,ds=run("turn_left(20)")
local alias,as,code=run("CONST turn_command_left = turn_left\nturn_command_left(20)")
check(alias.status=="completed"and math.abs(as.yaw-ds.yaw)<1e-8,"command alias executes exact original mechanics")
check(alias.cyclesSpent==direct.cyclesSpent and #code==1 and code[1].line==2,"alias adds no runtime CPU fee and preserves invocation source line")
local named=run("const right = turn_right\nright(to=20)")
check(named.status=="completed","named arguments retain canonical signature")
local chain=run("CONST a = get_tank_direction\nCONST b = a\nheading = b()")
check(chain.status=="completed"and chain.variables.heading.world_direction==0,"read-command aliases and alias chains use ordinary BW values/costs")
for _,source in {
 "CONST a=turn_left\na=20",
 "CONST a=turn_left\nCONST a=steer_left",
 "CONST a=turn_left\na(999999)",
 "CONST a=turn_left\na(20,to=30)",
 "a(20)\nCONST a=turn_left",
 "CONST a=turn_left\nx=a",
 "CONST a=turn_left\nfunction f(a):\n    return a\nf(1)",
 "if true:\n    CONST a=turn_left\na(20)",
 "CONST a=not_a_command\na(20)",
}do check(not Parser.parse(source),"invalid alias declaration/call retains compiler protections")end
print("BW immutable command aliases passed: "..count.." assertions")

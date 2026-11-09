local Parser=require("BWParser")
local Runtime=require("BWRuntime")
local Sim=require("TankSimulation")
local Value=require("BWValue")
local Config=require("BWConfig")
local ScannerConfig=require("ScannerConfig")
local G=require("ScannerGeometry")
local Windup=require("WeaponWindup")
local Weapon=require("RattlerWeapon")
local Recoil=require("RattlerRecoil")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local function near(a,b) return math.abs(a-b)<1e-5 end
local function run(source,kind,reading,options)
 options=options or {}
 local instructions,err,ast=Parser.parse(source)
 assert(instructions,if err then err.message else "parse failed")
 local state=Sim.new(Vector3.zero,kind or "Boomer")
 local prints,scans,events,inputs={},{},{},{}
 local clock=0; local channels={}
 local runtime=Runtime.new(instructions,state,{
  scan=function(angle)
   local index=G.sensorIndex(angle)
   if options.cooldowns and clock-(channels[index] or -100)<ScannerConfig.SensorCooldown-1e-8 then return nil,"Sensor cooldown" end
   channels[index]=clock; table.insert(scans,angle)
   return Value.observation(reading or Value.scan(),clock,state.position,state.yaw)
  end,
  onValue=function(observation,line) table.insert(events,{kind="scan",observation=observation,line=line}) end,
  onPrint=function(text,line) table.insert(prints,text); table.insert(events,{kind="print",text=text,line=line}) end,
 })
 local weapon=Weapon.new(); local pending
 for tick=1,(options.ticks or 12000) do
  local input=runtime:step(state,1/60); table.insert(inputs,input)
  local previous=state.position
  Sim.step(state,input,1/60)
  if options.blocked then state.position=previous; state.speed=0 end
  if state.tankType=="Rattler" then
   local fire=Weapon.step(weapon,true,input.fire,1/60); state.firing=weapon.firing
   if fire then state.weaponActivationSerial=(state.weaponActivationSerial or 0)+1; state.weaponShotSerial=(state.weaponShotSerial or 0)+1; local _,dir=Sim.shotPose(state); Recoil.kick(state,weapon.heat,dir) end
  else
   if pending then local done,origin=Windup.step(pending,state,1/60); if done then pending=nil; if origin then state.weaponShotSerial=(state.weaponShotSerial or 0)+1 end end end
   if not pending then pending=Windup.begin(state,input); if pending then state.weaponActivationSerial=(state.weaponActivationSerial or 0)+1 end end
  end
  clock+=1/60
  if runtime.status~="running" then break end
 end
 return runtime,state,prints,scans,events,inputs,ast
end
local source=[=[shots = 0
shots = shots + 1
number = (10 + 5 * 2 - -4) / 2
text = "hello # still a string"
flag = not 1 + 2 * 3 == 8 and true or false
nothing = null
array = [number, text, flag, nothing]
print(shots)
print(number)
print(array)
]=]
local runtime,state,prints,scans,events,inputs,ast=run(source)
check(runtime.status=="completed" and #ast==10,"block AST compiles assignments and print statements")
check(runtime.variables.shots==1 and runtime.variables.number==12,"assignment, reassignment, arithmetic and unary precedence")
check(runtime.variables.flag==true and runtime.variables.nothing==Value.Null,"not/and/or precedence and boolean/null values")
check(prints[1]=="1" and prints[2]=="12" and prints[3]=='[12, "hello # still a string", true, null]',"readable scalar/array printing with quote-aware comments")
check(runtime.cycleCounts.read>0 and runtime.cycleCounts.write==7 and runtime.cycleCounts.arithmetic>0 and runtime.cycleCounts.comparison>0 and runtime.cycleCounts.logical>0,"informational CPU hooks count expression operations")
for _,sample in {
 {'1 + 2 * 3', '7'}, {'(1 + 2) * 3','9'}, {'10 - 3 - 2','5'}, {'20 / 2 / 2','5'},
 {'-2 * -3','6'}, {'+2','2'}, {'1 != 2','true'}, {'2 <= 2','true'}, {'3 >= 2','true'},
 {'3 > 2','true'}, {'1 < 2','true'}, {'true and false','false'}, {'false or true','true'},
 {'not false','true'}, {'not 2 < 1','true'}, {'null == null','true'}, {'null != false','true'},
 {'1 == "1"','false'}, {'[1, null] == [1, null]','true'}, {'[1] != [2]','true'},
 {'"b" > "a"','true'}, {'[true, false, null][1]','false'},
} do
 local r,_,out=run('print('..sample[1]..')')
 check(r.status=="completed" and out[1]==sample[2],"typed operator/index semantics: "..sample[1])
end
local arithmetic=run('forward(1 + 1)')
check(arithmetic.status=="completed" and arithmetic.cycleCounts.arithmetic==1,"constant expression action arguments retain runtime accounting")
local scanned=Value.scan("tank",58,39.6,"pilot.Rattler#17","enemy")
runtime,state,prints,scans,events=run([=[direction = 45
result = Scanner(direction)
distance = result[1]
bearing = result[2]
identity = result[3]
if result[0] == "tank" and result[4] == "enemy":
    print(identity)
    if distance < 30:
        fire(2)
    elif distance < 75:
        print(bearing)
        fire(1)
    else:
        forward(10)
else:
    print("wrong")
]=],"Boomer",scanned)
check(runtime.status=="completed" and #scans==1 and scans[1]==45 and runtime.variables.result==scanned,"scanner result assignment keeps structured snapshot and expression angle")
check(runtime.variables.distance==58 and runtime.variables.bearing==39.6 and prints[1]=="pilot.Rattler#17" and prints[2]=="39.600000000000001","zero-based scanner access and only selected nested branch")
check((state.weaponShotSerial or 0)>=1 and state.position.Magnitude==0,"selected conditional weapon command executes original asynchronous weapon")
check(events[1].kind=="scan" and events[1].line==2 and events[2].kind=="print" and runtime.cycleCounts.branch>=2,"scanner diagnostics and print records remain ordered with source lines")
check(runtime.results[1].timestamp==1/60 and runtime.lastValue==scanned,"scanner timestamp is measurement tick rather than later print time")
for _,sample in {{"tank","enemy","Enemy detected"},{"tank","teammate","Friendly tank"},{"wall",Value.Null,"Obstacle detected"},{Value.Null,Value.Null,"Nothing"}} do
 local result=if sample[1]==Value.Null then Value.scan() else Value.scan(sample[1],20,45,"id",if sample[2]==Value.Null then nil else sample[2])
 runtime,state,prints,scans=run([=[result = Scanner(45)
if result[0] == "tank":
    if result[4] == "enemy":
        print("Enemy detected")
        fire(0)
    else:
        print("Friendly tank")
elif result[0] == "wall":
    print("Obstacle detected")
    turn_right(0)
else:
    print("Nothing")
    forward(0)
]=],"Boomer",result)
 check(runtime.status=="completed" and #prints==1 and prints[1]==sample[3] and #scans==1,"acceptance A branching for each observation/affiliation")
end
runtime,state,prints,scans=run([=[if false:
    result = Scanner(45)
a = false and Scanner(90)[0] == "tank"
b = true or undefined_variable > 0
if true or Scanner(180)[0] == "wall":
    print("safe")
]=])
check(runtime.status=="completed" and #scans==0 and prints[1]=="safe","unreachable bodies and short-circuited operands never scan or read undefined variables")
runtime,state,prints,scans=run([=[switch Scanner(90)[0]:
    case "tank":
        print("tank")
    case "wall":
        print("wall")
    case null:
        print("none")
    default:
        print("other")
print("done")
]=],"Boomer",Value.scan("wall",22,90))
check(runtime.status=="completed" and #scans==1 and #prints==2 and prints[1]=="wall" and prints[2]=="done","switch expression evaluated once, first case only, no fallthrough")
for _,label in {'"tank"','2','true','false','null'} do
 runtime,state,prints=run('value = '..label..'\nswitch value:\n    default:\n        print("wrong")\n    case '..label..':\n        switch 2:\n            case 1 + 1:\n                print("nested")\n            default:\n                print("wrong")')
 check(runtime.status=="completed" and #prints==1 and prints[1]=="nested","switch scalar equality, default fallback and nested constant-expression case")
end
for _,kind in {"Boomer","Rattler"} do
 runtime,state,prints=run([=[distance = 4
angle = 20
forward(distance)
turn_right(angle)
turret_left(to=180 - angle)
if true:
    back(distance / 2)
    duration = .15
    fire(duration)
print("finished")
]=],kind)
 check(runtime.status=="completed" and prints[1]=="finished" and (state.weaponShotSerial or 0)>0,"expressions and conditional asynchronous actions preserve "..kind.." behavior")
end
runtime,state,prints,scans=run('angle = 0\na = Scanner(angle)\nb = Scanner(90)\nprint(a[0])',"Boomer",Value.scan(),{cooldowns=true})
check(runtime.status=="completed" and #scans==2,"different physical scanner channels remain independent inside expressions")
runtime,state,prints,scans=run('a = Scanner(0)\nb = Scanner(0)',"Boomer",Value.scan(),{cooldowns=true})
check(runtime.status=="error" and runtime.message:find("Line 2",1,true) and #scans==1,"same-sensor cooldown failure is not turned into a fake expression value")
-- Best effort still applies inside branches without discarding program values.
runtime,state,prints=run('x = 7\nif true:\n    forward(100)\n    print(x)',"Boomer",nil,{blocked=true})
check(runtime.status=="completed" and runtime.skipped==1 and prints[1]=="7","best-effort obstruction skips one action and retains enclosing branch variables")
local accepted={
[=[result = Scanner(45)
if result[0] == "tank":
    if result[4] == "enemy":
        print("Enemy detected")
        fire(2)
    else:
        print("Friendly tank")
elif result[0] == "wall":
    print("Obstacle detected")
    turn_right(90)
else:
    forward(20)]=],
[=[result = Scanner(90)
switch result[0]:
    case "tank":
        print("Tank detected")
    case "wall":
        print("Wall detected")
    case null:
        print("Nothing detected")
    default:
        print("Unknown object")]=],
[=[result = Scanner(45)
if result[0] == "tank" and result[4] == "enemy":
    bearing = result[2]
    distance = result[1]
    print(bearing)
    print(distance)
    if distance < 30:
        fire(2)
    elif distance < 75:
        fire(1)
    else:
        forward(10)]=],
}
for index,source in accepted do for _,kind in {"Boomer","Rattler"} do
 runtime,state,prints,scans=run(source,kind,scanned)
 check(runtime.status=="completed" and #scans==1 and not runtime.skipped,"exact acceptance program "..index.." executes on "..kind)
end end
for _,sample in {
 {'print(missing)',1,"Undefined variable"},
 {'x = 2\nprint(x[0])',2,"Cannot index"},
 {'result = Scanner(0)\nprint(result[-1])',2,"Array index"},
 {'result = Scanner(0)\nprint(result[5])',2,"Array index"},
 {'result = Scanner(0)\nprint(result[1.5])',2,"Array index"},
 {'result = Scanner(0)\nprint(result["1"])',2,"Array index"},
 {'a = 0\nb = 5 / a',2,"Division by zero"},
 {'a = "x"\nb = a + 1',2,"Arithmetic requires"},
 {'a = true\nif a < 1:\n    fire()',2,"Ordering requires"},
 {'a = 2\nif a:\n    fire()',2,"Expected a boolean"},
 {'d = 1001\nforward(d)',2,"Argument must"},
 {'a = 1e300\nb = a * a',2,"non-finite"},
 {'flag = 1\nfire(best_effort=flag)',2,"best_effort"},
} do
 runtime,state,prints,scans,events,inputs=run(sample[1])
 check(runtime.status=="error" and runtime.message:find("Line "..sample[2]..":",1,true) and runtime.message:find(sample[3],1,true),"runtime error has meaningful source line: "..sample[3])
 local final=inputs[#inputs]
 check(not final.fire and final.throttle==0 and final.steer==0 and next(runtime.variables)==nil,"runtime failure returns neutral inputs and discards variable environment")
end
for _,source in {
 'forward(1)\nif :\n    fire()',
 'if true\n    fire()',
 'if true:\n  fire()',
 'if true:\n\tfire()',
 'if true:\nfire()',
 '    fire()',
 'elif true:\n    fire()',
 'else:\n    fire()',
 'if true:\n    print("ok")\nelse x:\n    fire()',
 'switch 1:\n    fire()',
 'switch 1:\n    case 1 + 1:\n        fire()\n    case 2:\n        fire()',
 'switch "x":\n    default:\n        fire()\n    default:\n        back(1)',
 'x = 1\nswitch x:\n    case x:\n        fire()',
 'switch 1:\n    case Scanner(0):\n        fire()',
 'switch 1:\n    case [1]:\n        fire()',
 'a = missing_function(1)',
 'print(1,2)',
 'print()',
 'a = Scanner("x")',
 'a = 1 / 0',
 'a = [1,2][4]',
 'a = "x" + 1',
 'Scanner = 1',
 'for x in [1]:\n    fire()',
 'def f():\n    fire()',
 'a = 1 < 2 < 3',
} do
 local result,err=Parser.parse(source)
 check(not result and err.line>=1 and err.message:find("Line ",1,true)==1,"malformed program statically rejected before any action: "..source)
end
local deep='print('..string.rep('(',Config.MaxExpressionDepth+1)..'1'..string.rep(')',Config.MaxExpressionDepth+1)..')'
check(not Parser.parse(deep),"excessive expression nesting bounded")
local nested={}; for i=0,Config.MaxBlockDepth+1 do table.insert(nested,string.rep(' ',i*4)..'if true:') end; table.insert(nested,string.rep(' ',(Config.MaxBlockDepth+2)*4)..'fire()')
check(not Parser.parse(table.concat(nested,'\n')),"excessive block nesting bounded")
-- Stop and reset cannot retain another program's variables or latent actions.
local Controller=require("BWController")
local tank={state=Sim.new(Vector3.zero),command=require("InputCommand").neutral(),lastInput=0,rattler=Weapon.new()}
check(Controller.start(tank,'secret = 42\nif true:\n    forward(100)\n    fire()'),"conditional program starts through authoritative controller")
for _=1,3 do local input=Controller.input(tank,1/60); Sim.step(tank.state,input,1/60) end
check(tank.bw.variables.secret==42 and tank.bw.devices.devices.drivetrain.active.executor.current.kind=="move","branch retains asynchronous movement state")
Controller.stop(tank,"Stopped by player.")
check(next(tank.bw.variables)==nil and tank.command.throttle==0 and not tank.command.fire,"Stop inside conditional discards variables and releases owned input")
Controller.start(tank,'print(secret)'); Controller.input(tank,1/60)
check(tank.state.bwStatus=="error" and tank.state.bwMessage:find("Undefined variable",1,true),"replaced program cannot read previous variables")
local first=Runtime.new(assert(Parser.parse('x = 1')),Sim.new(Vector3.zero)); first:step(Sim.new(Vector3.zero),1/60)
local second=Runtime.new(assert(Parser.parse('print(x)')),Sim.new(Vector3.zero)); second:step(Sim.new(Vector3.zero),1/60)
check(second.status=="error" and first.variables.x==1,"simultaneous tanks/programs have separate variable environments")
Controller.start(tank,'x = 1'); Controller.input(tank,1/60); Controller.stop(tank,"Battle reset.")
check(next(tank.bw.variables)==nil,"reset also clears completed program's variables")
local Text=require("BWEditorText")
local text,cursor=Text.edit('if true:','if true:\n',10,'enter')
check(text=='if true:\n    ' and cursor==14,"Enter after block header inserts four-space indent")
text=Text.edit('    print(1)','    print(1)\n',14,'enter')
check(text=='    print(1)\n    ',"Enter retains current indentation")
text=Text.edit('', '\tif true:\n\t\tprint("\\t")',-1)
check(text=='\tif true:\n\t\tprint("\\t")',"editor preserves pasted whitespace without normalization")
local large=Value.array({1}); for _=1,12 do large=Value.array({large,large,large,large}) end
check(#Value.format(large)<=Config.MaxOutputBytes+24,"printing shared nested arrays has a bounded formatting budget")
-- Printed values share the private, chronological IDE history with observations.
local IDE=require("BWIDE")
local ui=IDE.new(Instance.new("PlayerGui"),function() return 1 end,function() return 2 end)
ui:bind("tank")
ui:receiveOutput("tank",0,1,{kind="scan",angle=45,text=Value.format(scanned),timestamp=1,line=1})
ui:receiveOutput("tank",0,1,{kind="print",text="Enemy detected",timestamp=1.1,line=3})
ui:update({generation=0,bwRequestId=1,bwRunRequestId=1,bwStatus="completed",bwMessage="Program completed.",tankType="Boomer"})
check(ui.output.Text:find("Scanner(45)",1,true) and ui.output.Text:find("Enemy detected",1,true)<ui.output.Text:find("Program completed.",1,true),"diagnostic, print and completion remain visible in chronological output")
for i=3,Config.MaxOutputEvents do ui:receiveOutput("tank",0,1,{kind="print",text=tostring(i),timestamp=i,line=3}) end
check(#ui.scanOutputs.tank.readings==Config.MaxOutputEvents,"IDE preserves bounded mixed print/scan history rather than replacing it")
ui.editorController:bind("indent-test","if true:")
ui.editor.CursorPosition=9; ui.editorController:key("enter",Enum.KeyCode.Return)
ui.editor.Text="if true:\n"; ui.editor.CursorPosition=10; ui.editor:GetPropertyChangedSignal("Text"):Fire()
check(ui.editor.Text=="if true:\n    " and ui.editor.CursorPosition==14,"live editor change hook applies indentation without recursive editing")
ui:destroy()
print(string.format("BW v0.2 expressions/blocks/runtime suite passed: %d assertions",count))

local IDE=require("BWIDE")
local Parser=require("BWParser")
local count=0
local function check(ok,message)count+=1;assert(ok,message)end
local request=0
local ui=IDE.new(Instance.new("PlayerGui"),function()request+=1;return request end,function()request+=1;return request end)
ui:bind("a")
local lines={};for i=1,10 do table.insert(lines,"print("..i..")")end
local source=table.concat(lines,"\n")
local function replace(text,cursor)
 ui.editorController.smartPaste=false
 ui.editor.Text=text
 ui.editor:GetPropertyChangedSignal("Text"):Fire()
 ui.editor.CursorPosition=cursor or 1
 ui.editor:GetPropertyChangedSignal("CursorPosition"):Fire()
end
replace(source)
ui:update({bwRunning=true,bwStatus="running",bwLine=140,bwIndex=93,bwCount=145})
check(ui.current.Text=="Line 1/10 • instruction 1/10","unrelated autonomous VM cannot overwrite visible source counters")
local fifth=1;for i=1,4 do fifth+=#lines[i]+1 end
ui.editor.CursorPosition=fifth;ui.editor:GetPropertyChangedSignal("CursorPosition"):Fire()
check(ui.current.Text=="Line 5/10 • instruction 5/10","cursor moves both counters using current compiled buffer")
ui:update({bwRunning=false,bwStatus="stopped",bwLine=140,bwIndex=93,bwCount=145})
replace("print(1)\nprint(2)",#"print(1)\n"+1)
check(ui.current.Text=="Line 2/2 • instruction 2/2","replacement invalidates previous instruction total")
ui:bind("b")
replace("print(3)")
check(ui.current.Text=="Line 1/1 • instruction 1/1"and ui.lastObservedState==nil,"tank switch clears runtime source association and status")
ui:bind("a");ui.editor.CursorPosition=1;ui.editor:GetPropertyChangedSignal("CursorPosition"):Fire()
check(ui.current.Text=="Line 1/2 • instruction 1/2","returning to tank restores its own source map")
replace("# comment\nprint(4)\n",1)
check(ui.current.Text=="Line 1/3 • instruction 0/1","blank/comment lines are not executable instructions")
replace("not_valid(")
check(ui.current.Text:find("syntax error",1,true)and not ui.current.Text:find("/145",1,true),"invalid edit cannot retain previous instruction count")
ui:receiveRuntime("a",{generation=2,requestId=4})
ui:receiveRuntime("a",{generation=1,requestId=9})
ui:receiveRuntime("a",{generation=2,requestId=3})
check(ui.runtimeReadings.a.generation==2 and ui.runtimeReadings.a.requestId==4,"late diagnostics cannot restore an older generation or program run")
-- Cursor and executing instruction are separate positions for the same source.
replace(source,1)
ui:update({generation=3,controlEpoch=12,bwRunning=false,bwStatus="stopped"})
ui.run.Activated:Fire()
ui:update({generation=3,controlEpoch=12,bwRunRequestId=request,bwRequestId=request,bwRunning=true,bwLine=2,bwIndex=2,bwCount=10})
check(ui.current.Text=="Line 1/10 • instruction 1/10"and ui.execution.Text=="Running line 2 • instruction 2/10","matching execution advances independently of parked cursor")
ui:update({generation=3,controlEpoch=12,bwRunRequestId=request,bwRequestId=request,bwRunning=true,bwLine=7,bwIndex=7,bwCount=10})
check(ui.execution.Text=="Running line 7 • instruction 7/10","next authoritative VM state advances execution line")
check(ui.executionHighlight.Visible and ui.executionHighlight.Position.Y.Offset>0,"matching running source highlights its actual executing row")
ui:update({generation=4,controlEpoch=14,bwRunRequestId=0,bwRequestId=0,bwRunning=true,bwLine=140,bwIndex=93,bwCount=145})
check(ui.execution.Text=="Execution: different program running in tank","respawn or another occupant's program cannot reuse matching source status")
check(not ui.executionHighlight.Visible,"different or replaced program never highlights the draft")
ui:bind("b")
check(ui.execution.Text=="Execution: stopped","switch clears stale execution line immediately")
ui:bind("a")
local function log(serial,message)
 ui:receiveOutput("a",4,1,{programSerial=serial,programKind="Player",programName="Editor program",kind="command",line=3,timestamp=2,thread=1,text=message})
end
log(10,"forward -> success");log(11,"fire -> success")
check(#ui.scanOutputs.a.readings==1 and ui.scanOutputs.a.text:find("fire",1,true)and not ui.scanOutputs.a.text:find("forward",1,true),"new actual invocation clears previous run logs even when request ID is reused")
log(10,"turn_right -> stale")
check(not ui.scanOutputs.a.text:find("turn_right",1,true),"late prior-program event cannot contaminate current invocation")
ui.pendingRequest=nil
ui:update({generation=4,controlEpoch=14,bwRunRequestId=0,bwRequestId=0,bwRunning=true,bwProgramKind="Personality",bwLine=140,bwIndex=93,bwCount=145})
local beforeRequest=request
check(ui.editor.TextEditable and ui.run.AutoButtonColor,"local draft stays editable while a different built-in personality runs")
ui.run.Activated:Fire()
check(request==beforeRequest+1 and ui.submittedPrograms.a.source==ui.editor.Text,"Run actually submits visible source to replace built-in Auto instead of silently ignoring click")
ui.minimumScanRequests.a=99;ui:setControlEpoch(22)
ui:receiveOutput("a",4,0,{programSerial=20,programName="Marauder",line=3,timestamp=1,text="new Auto run"})
check(ui.scanOutputs.a.requestId==0 and ui.scanOutputs.a.text:find("new Auto",1,true),"new occupancy/control lease clears old request fence so fresh Auto logs remain available")
ui:bind("b");ui.minimumScanRequests.b=88;ui:setControlEpoch(22)
check(ui.minimumScanRequests.b==0,"equal epoch numbers on different tanks still establish separate output leases")
ui:bind("a");ui:setControlEpoch(22)
ui.frame.Visible=true;ui.gui.AbsoluteSize=Vector2.new(1000,700);ui.frame.AbsoluteSize=Vector2.new(600,500);ui.frame.AbsolutePosition=Vector2.new(100,100)
local start=ui.frame.Position
local UIS=game:GetService("UserInputService")
ui.titleBar.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector3.new(120,110,0)})
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Position=Vector3.new(170,150,0)})
check(ui.frame.Position.X.Offset==start.X.Offset+50 and ui.frame.Position.Y.Offset==start.Y.Offset+40,"title bar dragging moves code window without altering source")
UIS.InputEnded:Fire({UserInputType=Enum.UserInputType.MouseButton1})
local stopped=ui.frame.Position
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Position=Vector3.new(200,200,0)})
check(ui.frame.Position==stopped,"releasing mouse ends window drag")
local touch={UserInputType=Enum.UserInputType.Touch,Position=Vector3.new(120,110,0)}
ui.titleBar.InputBegan:Fire(touch);touch.Position=Vector3.new(-5000,-5000,0);UIS.InputChanged:Fire(touch)
check(ui.frame.Position.Y.Offset==stopped.Y.Offset-100,"touch drag keeps title bar inside viewport")
ui.closeButton.Activated:Fire()
check(not ui.frame.Visible,"close button hides window without issuing a program Stop")
-- Delayed compile A must not overwrite replacement B or a destroyed editor.
local delay=task.delay;local pending={}
task.delay=function(_,callback)table.insert(pending,callback)end
ui.editor.Text=source;ui:sourceStatusChanged()
ui.editor.Text="print(9)";ui.editor.CursorPosition=1;ui:sourceStatusChanged()
for i=#pending,1,-1 do pending[i]()end
check(ui.current.Text=="Line 1/1 • instruction 1/1","out-of-order debounce callbacks retain only latest source mapping")
ui.editor.Text="print(8)";ui:sourceStatusChanged();ui:destroy();for _,callback in pending do callback()end
task.delay=delay
print("BW editor source/caret status passed: "..count.." assertions")

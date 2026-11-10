local T=require(Shared.BWEditorText)
local Editor=require(Client.BWEditorController)
local IDE=require(Client.BWIDE)
local count=0
local function check(v,m) count+=1; assert(v,m) end
local function equal(actual,expected,m) check(actual==expected,m..' ['..tostring(actual)..']') end
for _,case in {
 {'    forward(10)','    forward(10)\n    '},
 {'if true:','if true:\n    '},
 {'    while true:','    while true:\n        '},
 {'\tif true:','\tif true:\n\t    '},
 {'if true: # inline comment','if true: # inline comment\n    '},
 {'    # comment:','    # comment:\n    '},
 {'print("colon:")','print("colon:")\n'},
 {'    print("💥")','    print("💥")\n    '},
} do local s,c,a=T.enter(case[1],#case[1]+1,-1); equal(s,case[2],'Enter preserves indentation/block semantics'); check(c==#s+1 and a==-1,'caret follows Enter') end
local s,c=T.enter('first\r\n    next',#'first\r\n    next'+1,-1)
equal(s,'first\r\n    next\r\n    ','Enter follows CRLF document style')
s,c=T.enter('    abcDEF',8,-1); equal(s,'    abc\n    DEF','split line at caret'); check(c==13,'split caret before suffix')
s,c=T.enter('if true:DELETE',15,9); equal(s,'if true:\n    ','Enter replaces selection')
equal(T.finishEnter('    abcXYZ','    abc\n',11,8),'    abc\n    ','native Enter replaces forward selection')
equal(T.finishEnter('    abcXYZ','    abc\n',8,11),'    abc\n    ','native Enter replaces reverse selection')
for _,case in {{'        x',9,'    x',5},{'      x',7,'    x',5},{'  x',3,'x',1},{'\t\tx',3,'\tx',2},{'\t  x',4,'\tx',2},{'    ',5,'',1}} do
 s,c=T.backspace(case[1],case[2],-1); equal(s,case[3],'Backspace previous indentation stop'); check(c==case[4],'Backspace caret')
end
check(T.backspace('    x',6,-1)==nil and T.backspace('    x',5,1)==nil,'code/selection deletion left native')
s,c=T.indent('  forward(1)',8,-1,false); equal(s,'      forward(1)','Tab indents whole current line'); check(c==12,'Tab preserves content-relative caret')
s,c=T.indent(s,c,-1,true); equal(s,'  forward(1)','ShiftTab reverses indent')
local sample='one\n    two\nthree'
local a
s,c,a=T.indent(sample,13,1,false); equal(s,'    one\n        two\nthree','selection ending at next column one excludes next line'); check(c==21 and a==5,'forward selection offsets')
local reversed,rc,ra=T.indent(sample,1,13,false); equal(reversed,s,'reverse selection same lines'); check(rc==5 and ra==21,'reverse selection orientation')
s,c,a=T.indent(s,c,a,true); equal(s,sample,'multi-line outdent roundtrip')
s=T.indent('\tprint("💥")\r\n  back(2)',1,#'\tprint("💥")\r\n  back(2)'+1,false)
equal(s,'    \tprint("💥")\r\n      back(2)','explicit indent preserves tabs/CRLF/Unicode outside requested edit')
-- Native Backspace can remove an entire multi-codepoint grapheme.
check(T.nativeEcho('    é',#'    é'+1,-1,'backspace','    '),'native grapheme deletion is not mistaken for extra indent deletion')
for _,case in {
 {'one\ntwo\nthree',2,'two\nthree'},
 {'one\ntwo\nthree',6,'one\nthree'},
 {'one\ntwo',6,'one'},
 {'one\n',5,'one'},
 {'one',2,''}, {'',1,''},
 {'one\r\ntwo\r\nthree',7,'one\r\nthree'},
 {'one\r\ntwo',7,'one'},
 {'one\n\nthree',5,'one\nthree'},
 {'one\n💥💥',2,'💥💥'},
} do
 local deleted,position,mark=T.deleteLine(case[1],case[2])
 equal(deleted,case[3],'ShiftDelete complete line including newline')
 check(position>=1 and position<=#deleted+1 and mark==-1,'line-delete caret valid')
 local byte=deleted:byte(position); check(not byte or byte<128 or byte>=192,'line-delete caret is a UTF8 boundary')
end
local pasted='\tif true:\r\n  \tprint("💥")  \r\n\r\n    back(2)\n'
local untouched=T.edit('',pasted,#pasted+1); equal(untouched,pasted,'multiline paste exactly preserved')
equal(T.edit('', '\n',2),'\n','pasted single newline is not Enter')
-- Decorating native input cannot change its newline count, including CRLF,
-- an existing following newline, auto-indented input and key-repeat payloads.
for _,payload in {'\n','\r\n','\n    ','\n\n','\r\n\r\n'} do
 local old='    if true:\n    old()'
 local at=#'    if true:'+1
 local raw=old:sub(1,at-1)..payload..old:sub(at)
 local first,last=T.nativeEnterSelection(old,raw,at+#payload,at+1,-1)
 local formatted=T.finishEnter(old,raw,first,last)
 local _,nativeLines=raw:gsub('\n','')
 local _,formattedLines=formatted:gsub('\n','')
 check(nativeLines==formattedLines,'Enter formatter only inserts whitespace, never another line')
end
local before='    old()'
local rebased=T.paste(before,'    if true:\n        forward(1)\nold()',5,-1,true)
equal(rebased,'    if true:\n            forward(1)\n    old()','relative indentation is retained even if it is unusual')
rebased=T.paste(before,'    if true:\n    forward(1)old()',5,-1,true)
equal(rebased,'    if true:\n        forward(1)\n    old()','AI snippet without final newline does not merge obsolete code')
local ai='        if true:\n            forward(1)\n'
rebased=T.paste(before,'    '..ai..'old()',5,-1,true)
equal(rebased,'    if true:\n        forward(1)\n    old()','common AI indentation removed before alignment')
rebased=T.paste(before,'    if true:\r\n\tforward(1)\r\nold()',5,-1,true)
equal(rebased,'    if true:\r\n        forward(1)\r\n    old()','smart paste preserves CRLF and converts leading tab columns only')
local inline='print("")'
equal(T.paste(inline,'print("a\n  b")',8,-1,true),'print("a\n  b")','inline string paste remains literal')
equal(T.paste(before,'    \n\nold()',5,-1,true),'    \n\nold()','blank-only clipboard remains literal')
local h=T.history('original'); h:select(5,2); h:record(pasted,#pasted+1,-1)
equal(h:undo().text,'original','multiline paste one undo operation'); check(h.current.cursor==5 and h.current.anchor==2,'undo selection restored')
equal(h:redo().text,pasted,'redo restores exact paste')
h:undo(); h:record('replacement',12,-1); check(#h.redoStack==0,'new edit drops redo branch')
local grouped=T.history('a'); grouped:record('b',2,-1,1); grouped:record('c\n\td',5,-1,1); equal(grouped:undo().text,'a','one paste gesture can emit multiple native text changes')
local bounded=T.history(''); for i=1,150 do bounded:record(tostring(i),1,-1) end; check(#bounded.undoStack==96,'history bounded by entry count')
local bytes=T.history(''); for i=1,8 do bytes:record(string.rep('x',100000)..i,1,-1) end; check(bytes.bytes<=524288,'history bounded by byte retention')
-- Real controller with deferred events, native echoes, focused routing and caret changes.
local UIS=game:GetService('UserInputService')
local savedDefer=task.defer; local savedDelay=task.delay; local savedDown=UIS.IsKeyDown
local queue={}; task.defer=function(fn) table.insert(queue,fn) end
local frames={}; task.delay=function(_,fn) table.insert(frames,fn) end
local function flushDeferred() local steps=0; while #queue>0 do steps+=1; assert(steps<100,'recursive editor event loop'); table.remove(queue,1)() end end
local function frame()
 local pending=frames; frames={}
 for _,fn in pending do fn() end
 flushDeferred()
end
local function flush()
 flushDeferred()
 local steps=0; while #frames>0 do steps+=1; assert(steps<12,'unsettled editor frames'); frame() end
end
local down={}; UIS.IsKeyDown=function(_,key) return down[key]==true end
local box=Instance.new('TextBox'); box.Text='if true:'; box.CursorPosition=9; box.SelectionStart=-1
box.ReturnPressedFromOnScreenKeyboard=signal()
box.CaptureFocus=function() UIS.focusedTextBox=box end
UIS.focusedTextBox=box
local updates=0; local ed=Editor.new(box,function() updates+=1 end); ed:bind('a','if true:')
box.CursorPosition=9; box:GetPropertyChangedSignal('CursorPosition'):Fire()
local function press(key) UIS.InputBegan:Fire({KeyCode=Enum.KeyCode[key]},true) end
local function release(key) UIS.InputEnded:Fire({KeyCode=Enum.KeyCode[key]}) end
local function native(source,cursor,anchor)
 box.Text=source; box:GetPropertyChangedSignal('Text'):Fire()
 box.CursorPosition=cursor; box.SelectionStart=anchor or -1
 box:GetPropertyChangedSignal('CursorPosition'):Fire(); box:GetPropertyChangedSignal('SelectionStart'):Fire()
end
press('Return'); equal(box.Text,'if true:','Enter notification does not synthesize a newline')
native('if true:\n',10); flush(); release('Return')
equal(box.Text,'if true:\n    ','native Enter echo removed'); check(box.CursorPosition==14,'late native caret restored')
press('Backspace'); native('if true:\n',10); flush(); release('Backspace')
equal(box.Text,'if true:\n','Backspace removes level, not line break')
press('Tab'); native('if true:\n    \t',15); flush(); release('Tab')
equal(box.Text,'if true:\n    ','Tab native echo not duplicated')
down[Enum.KeyCode.LeftShift]=true; press('Tab'); flush(); release('Tab'); down[Enum.KeyCode.LeftShift]=false
equal(box.Text,'if true:\n','ShiftTab native shortcut outdents')
-- A payload received before the keyboard event must still use the prior caret.
native('if true:\n\n',11); press('Return'); flush(); release('Return')
equal(box.Text,'if true:\n\n','native-first Enter is applied exactly once')
-- Deferred Lua callbacks are still in the native input resumption. Formatting
-- must wait until actual later Heartbeats and a stable native caret.
ed:bind('resumption-test','    forward(10)'); box.CursorPosition=#box.Text+1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
press('Return'); native('    forward(10)\n',17)
flushDeferred()
equal(box.Text,'    forward(10)\n','same-frame defers cannot rewrite native Enter')
frame(); equal(box.Text,'    forward(10)\n','first heartbeat only observes input')
box.CursorPosition=16; box:GetPropertyChangedSignal('CursorPosition'):Fire()
frame(); equal(box.Text,'    forward(10)\n','moving native caret postpones formatting')
flush(); release('Return')
equal(box.Text,'    forward(10)\n    ','settled Enter adds spaces only after stable frames')
-- Deferred signals from our own writes must not become a second native edit.
local settled=box.Text
box:GetPropertyChangedSignal('Text'):Fire(); flush()
equal(box.Text,settled,'deferred own Text event is ignored by text identity')
ed:bind('a','ignored')
-- Actual reported shape: Enter in a multi-line document immediately before
-- an existing newline, with the native caret observed against the old Text.
for index,line in {'    forward(10)','    if true:'} do
 local old=line..'\n    back(2)'
 ed:bind('existing-newline-'..index,old)
 box.CursorPosition=#line+2; box.SelectionStart=-1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
 press('Return'); release('Return')
 native(line..'\n\n    back(2)',#line+2); flush()
 local indent=string.rep(' ',if index==1 then 4 else 8)
 equal(box.Text,line..'\n'..indent..'\n    back(2)','existing newline is not mistaken for newly inserted line')
 check(box.CursorPosition==#line+#indent+2,'caret is on the new indented line, not below it')
 ed:key('undo'); equal(box.Text,old,'undo restores middle-of-document Enter'); check(box.CursorPosition==#line+1,'undo restores actual pre-Enter caret')
end
ed:bind('a','ignored')
-- Key release before native insertion must not abandon indentation.
for index,line in {'    forward(10)','    if true:'} do
 ed:bind('late-enter-'..index,line)
 box.CursorPosition=#line+1; box.SelectionStart=-1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
 press('Return'); flush(); release('Return')
 equal(box.Text,line,'no synthesized newline while native insertion is pending')
 native(line..'\n',#line+2); flush()
 local spaces=if index==1 then 4 else 8
 equal(box.Text,line..'\n'..string.rep(' ',spaces),'delayed native Enter produces one indented line')
 local expectedCursor=#box.Text+1
 box.CursorPosition=#line+2; box:GetPropertyChangedSignal('CursorPosition'):Fire(); flush()
 check(box.CursorPosition==expectedCursor,'late native column-zero caret corrected after key release')
 down[Enum.KeyCode.LeftControl]=true
 native(line..'\n',#line+2); press('Z'); flush(); release('Z')
 equal(box.Text,line,'Enter indentation/newline undo atomically despite native-first raw echo')
 native(line..'\n',#line+2); press('Y'); flush(); release('Y')
 equal(box.Text,line..'\n'..string.rep(' ',spaces),'Enter redo restores indentation')
 down[Enum.KeyCode.LeftControl]=false
 ed:key('undo')
end
-- Also cover native insertion fully committed before keyboard notification.
local nativeFirst='        back(5)'
ed:bind('fully-native-first',nativeFirst); box.CursorPosition=#nativeFirst+1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
native(nativeFirst..'\n',#nativeFirst+2); flush(); press('Return'); flush(); release('Return')
equal(box.Text,nativeFirst..'\n        ','fully committed native-first Enter is not duplicated')
ed:key('undo'); equal(box.Text,nativeFirst,'native-first correction remains one undo')
ed:bind('a','ignored')
-- Two inputs can arrive before deferred native commit: no typed text is lost.
native(box.Text..'x',#box.Text+2); press('Tab'); flush(); release('Tab')
check(box.Text:sub(-1)=='x' and box.Text:find('    x',1,true),'queued ordinary typing survives a following indentation key')
-- Software-keyboard Enter is supported, without double-handling a physical Enter.
local onscreenBefore=box.Text
box.ReturnPressedFromOnScreenKeyboard:Fire(); native(onscreenBefore..'\n',#onscreenBefore+2); flush()
check(#box.Text>#onscreenBefore and box.Text:find(onscreenBefore,1,true)==1,'on-screen keyboard Enter')
local expected=T.enter(box.Text,box.CursorPosition,box.SelectionStart)
local physicalBefore=box.Text
press('Return'); box.ReturnPressedFromOnScreenKeyboard:Fire(); native(physicalBefore..'\n',#physicalBefore+2); flush(); release('Return')
equal(box.Text,expected,'physical/virtual return events do not double-indent')
-- Exact paste mode retains the earlier literal-whitespace workflow.
ed.smartPaste=false
-- ShiftDelete is line deletion, not native cut-selection/delete-next-char.
local lines='    first()\n    old()\n    last()'
ed:bind('delete-shortcuts',lines)
box.CursorPosition=#'    first()\n    ol'+1; box.SelectionStart=-1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
down[Enum.KeyCode.LeftShift]=true; press('Delete')
native('    first()\n    lastX()',20); flush(); release('Delete'); down[Enum.KeyCode.LeftShift]=false
equal(box.Text,'    first()\n    last()','ShiftDelete removes entire caret line and discards native echo')
down[Enum.KeyCode.LeftControl]=true; press('Z'); flush(); release('Z'); equal(box.Text,lines,'CtrlZ restores deleted line in one step')
press('Y'); flush(); release('Y'); equal(box.Text,'    first()\n    last()','CtrlY reapplies line deletion')
down[Enum.KeyCode.LeftControl]=false
ed:bind('native-first-delete',lines)
box.CursorPosition=#'    first()\n    ol'+1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
down[Enum.KeyCode.LeftShift]=true
native('    first()\n    last()',18); press('Delete'); flush(); release('Delete'); down[Enum.KeyCode.LeftShift]=false
equal(box.Text,'    first()\n    last()','native-first full-line deletion is not applied twice')
ed:key('undo'); equal(box.Text,lines,'native-first line deletion remains one undo step')
ed:bind('a','ignored')
-- User reproduction: native undo/redo results arrive AFTER shortcut key-up.
ed:bind('typing-history','base')
native('base typed',11); flush()
down[Enum.KeyCode.LeftControl]=true
press('Z'); release('Z'); flushDeferred()
equal(box.Text,'base typed','keyboard undo does not rewrite during native input processing')
native('base typed',11); flush() -- native undo of an eager programmatic write
 equal(box.Text,'base','late native callback cannot cancel application undo')
check(#ed.history.redoStack==1,'undo retains redo despite late native callback')
-- Echoes can arrive long after key release and the initial settling frames.
native('base typed',11); flush()
equal(box.Text,'base','native redo after completed settling cannot overwrite undo')
check(#ed.history.redoStack==1,'late native redo never becomes a new typing transaction')

press('Y'); release('Y'); native('base',5); flush()
equal(box.Text,'base typed','CtrlY reapplies typing instead of undoing it')
press('Y'); release('Y'); native('base',5); flush()
equal(box.Text,'base typed','empty redo does not consume a native undo result')
press('Z'); release('Z'); press('Y'); release('Y'); native('base',5); flush()
equal(box.Text,'base typed','rapid CtrlZ then CtrlY uses one deterministic history')
press('Z'); release('Z'); native('base',5); flush()
equal(box.Text,'base','repeated undo remains predictable')
-- Native history callbacks before InputBegan must not be committed as typing.
native('base typed',11); flushDeferred(); press('Y'); release('Y'); flush()
equal(box.Text,'base typed','native-first redo remains an application redo')
check(#ed.history.redoStack==0,'redo stack consumed exactly once')
-- A genuine editing key relinquishes the latch and starts a fresh edit.
down[Enum.KeyCode.LeftControl]=false
press('X'); native('base typedX',12); flush(); release('X')
equal(box.Text,'base typedX','typing after history latch remains editable')
down[Enum.KeyCode.LeftControl]=true; press('Z'); release('Z'); flush()
equal(box.Text,'base typed','new typing after latch is undoable')
-- Undo before a typed change has reached its native-commit heartbeat.
down[Enum.KeyCode.LeftControl]=false
ed:bind('uncommitted-typing','start'); native('startX',7)
down[Enum.KeyCode.LeftControl]=true; press('Z'); release('Z'); flush()
equal(box.Text,'start','uncommitted typing is recorded before undo')
press('Y'); release('Y'); flush(); equal(box.Text,'startX','uncommitted typing still supports redo')
down[Enum.KeyCode.LeftControl]=false
-- Real chord ordering: Control flushes pending typing before native Z runs.
ed:bind('modifier-flush','prefix'); down[Enum.KeyCode.LeftControl]=false
native('prefix typed',13) -- no heartbeat/history commit yet
down[Enum.KeyCode.LeftControl]=true; press('LeftControl')
native('prefix',7); flushDeferred(); press('Z'); release('Z'); flush()
equal(box.Text,'prefix','native-first undo of pending typing uses the correct base')
press('Y'); release('Y'); flush(); equal(box.Text,'prefix typed','modifier flush retains pending typing for redo')
down[Enum.KeyCode.LeftControl]=false
ed:bind('a','ignored')
-- Clipboard edits are ordinary native payloads; no source-wide processing.
local beforePaste=box.Text; local beforeCount=#ed.history.undoStack
down[Enum.KeyCode.LeftControl]=true; press('V')
native(pasted,#pasted+1); flush(); release('V')
equal(box.Text,pasted,'CtrlV preserves exact whitespace'); check(#ed.history.undoStack==beforeCount+1,'CtrlV records exactly one transaction')
press('Z'); native('',1); flush(); release('Z')
equal(box.Text,beforePaste,'CtrlZ restores entire pre-paste buffer despite native undo echo')
press('Y'); flush(); release('Y'); equal(box.Text,pasted,'CtrlY restores paste')
press('Z'); flush(); release('Z'); down[Enum.KeyCode.LeftShift]=true; press('Z'); flush(); release('Z'); down[Enum.KeyCode.LeftShift]=false
equal(box.Text,pasted,'CtrlShiftZ redo')
down[Enum.KeyCode.LeftControl]=false
-- Smart paste aligns unindented AI replacements while leaving old code present.
ed.smartPaste=true
local originalSmart='with thread(1):\n    old()'
ed:bind('smart',originalSmart)
box.CursorPosition=#'with thread(1):\n    '+1; box:GetPropertyChangedSignal('CursorPosition'):Fire()
down[Enum.KeyCode.LeftControl]=true; press('V')
local payload='if true:\n    forward(10)\n'
local prefix='with thread(1):\n    '
native(prefix..payload..'old()',#prefix+#payload+1); flush(); release('V')
local expectedSmart='with thread(1):\n    if true:\n        forward(10)\n    old()'
equal(box.Text,expectedSmart,'CtrlV rebases snippet to prepared indentation and preserves obsolete suffix')
native(prefix..payload..'old()',#prefix+#payload+1); press('Z'); flush(); release('Z'); equal(box.Text,originalSmart,'aligned paste is one undo, including native-first unformatted echo')
native(prefix..payload..'old()',#prefix+#payload+1); press('Y'); flush(); release('Y'); equal(box.Text,expectedSmart,'redo restores aligned paste, including native-first echo')
-- A new exact paste matching an old unformatted echo must remain a new transaction.
ed.smartPaste=false
box.SelectionStart=1; box.CursorPosition=#box.Text+1; box:GetPropertyChangedSignal('SelectionStart'):Fire()
press('V'); native(prefix..payload..'old()',#prefix+#payload+6)
press('Z'); flush(); release('Z'); release('V')
equal(box.Text,expectedSmart,'fresh exact paste is distinct from native format undo echo')
press('Y'); flush(); release('Y'); equal(box.Text,prefix..payload..'old()','exact paste redo stays exact')
down[Enum.KeyCode.LeftControl]=false
ed:bind('a','ignored'); ed.smartPaste=false
-- Context-menu / mobile paste has no keyboard token and is still one native edit.
local nativeBefore=box.Text; native('  x\n\t y\n',10); flush(); ed:key('undo'); equal(box.Text,nativeBefore,'context-menu multiline paste atomic undo')
-- Undo immediately after paste, before deferred commit, still retains redo.
down[Enum.KeyCode.LeftControl]=true
native('immediate\n\tpaste',17); press('Z'); flush(); release('Z')
equal(box.Text,nativeBefore,'immediate paste undo before deferred commit')
ed:key('redo'); equal(box.Text,'immediate\n\tpaste','immediate paste redo retained')
ed:key('undo'); down[Enum.KeyCode.LeftControl]=false
-- Source-only routing: output/hardware keyboard shortcuts are untouched.
UIS.focusedTextBox=Instance.new('TextBox'); local unchanged=box.Text; press('Tab'); flush(); equal(box.Text,unchanged,'only source focus handles editing keys')
UIS.focusedTextBox=box
ed:bind('b','second'); native('second edited',14); flush(); ed:bind('a','ignored'); equal(box.Text,nativeBefore,'per-tank source and history retained')
ed:bind('b','ignored'); ed:key('undo'); equal(box.Text,'second','per-tank undo isolated')
native('late edit',10); local beforeDestroy=updates; ed:destroy(); flush(); check(updates==beforeDestroy,'destroy cancels deferred writes')
-- IDE Run submits bytes verbatim; undo buttons use the same atomic history.
local sent
local ui=IDE.new(Instance.new('PlayerGui'),function(source) sent=source; return 1 end,function() return 2 end)
ui:bind('test')
ui.editor.CursorPosition=5; ui.editor:GetPropertyChangedSignal('CursorPosition'):Fire()
ui.editor.CaptureFocus=function() UIS.focusedTextBox=ui.editor; ui.editor.CursorPosition=#ui.editor.Text+1; ui.editor:GetPropertyChangedSignal('CursorPosition'):Fire() end
check(ui.editorController.smartPaste and ui.pasteMode.Text=='Paste: align','alignment is default mode')
ui.pasteMode.Activated:Fire(); check(not ui.editorController.smartPaste and ui.pasteMode.Text=='Paste: exact','exact paste mode available')
check(ui.editor.CursorPosition==5,'paste mode button preserves prepared caret through native focus reset')
ui.editor.Text=pasted; ui.editor.CursorPosition=#pasted+1; ui.editor:GetPropertyChangedSignal('Text'):Fire(); flush()
local original=ui.editorController.history.undoStack[#ui.editorController.history.undoStack].text
ui.undo.Activated:Fire(); equal(ui.editor.Text,original,'IDE undo button')
ui.redo.Activated:Fire(); equal(ui.editor.Text,pasted,'IDE redo button')
ui.run.Activated:Fire(); equal(sent,pasted,'Run does not normalize pasted whitespace')
ui:destroy(); flush()
task.defer=savedDefer; task.delay=savedDelay; UIS.IsKeyDown=savedDown; UIS.focusedTextBox=nil
print('BW editor indentation/paste/history suite passed: '..count..' assertions')

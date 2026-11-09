-- Native TextBox retains clipboard/IME input. Explicit editing keys own bounded
-- undo transactions; a short key guard discards native echoes of handled keys.
local Text=require(game.ReplicatedStorage.Shared.BWEditorText)
local UIS=game:GetService('UserInputService')
local Editor={}; Editor.__index=Editor
function Editor.new(box,changed)
 local self=setmetatable({box=box,changed=changed,sessions={},connections={},serial=0,smartPaste=true},Editor)
 self.history=Text.history(box.Text)
 local function connect(event,callback) table.insert(self.connections,event:Connect(callback)) end
 connect(box:GetPropertyChangedSignal('Text'),function() self:nativeChanged() end)
 for _,property in {'CursorPosition','SelectionStart'} do
  connect(box:GetPropertyChangedSignal(property),function()
   if self.writing then return end
   local caret=self.enterCaret
   if caret and caret.history==self.history and self.history.current==caret.state and box.Text==caret.state.text and box.CursorPosition==caret.nativeCursor then
    self:queueEnterCaret(); return
   end
   if not self.guard and box.Text==self.history.current.text then self.history:select(box.CursorPosition,box.SelectionStart) end
  end)
 end
 connect(UIS.InputBegan,function(input)
  self.guard=nil; self.enterCaret=nil
  if UIS:GetFocusedTextBox()~=box then return end
  local function down(name) return UIS.IsKeyDown and UIS:IsKeyDown(Enum.KeyCode[name]) end
  local control=down('LeftControl') or down('RightControl') or down('LeftMeta') or down('RightMeta')
  local shift=down('LeftShift') or down('RightShift')
  if down('LeftAlt') or down('RightAlt') then return end -- preserve OS/AltGr input
  local key=input.KeyCode
  if self.enterIntent and key~=Enum.KeyCode.Return and key~=Enum.KeyCode.KeypadEnter and box.Text==self.enterIntent.base.text then self.enterIntent=nil end
  if control and key==Enum.KeyCode.V then
   self.serial+=1; self.pasteGesture=self.serial
   if box.Text==self.history.current.text then self.history:select(box.CursorPosition,box.SelectionStart) end
   local old=self.history.current
   self.pasteBase={text=old.text,cursor=old.cursor,anchor=old.anchor}
   self.pasteVerbatim=shift or not self.smartPaste
   return
  end
  if control and key==Enum.KeyCode.Z then self:key(if shift then 'redo' else 'undo',key)
  elseif control and key==Enum.KeyCode.Y then self:key('redo',key)
  elseif not control and (key==Enum.KeyCode.Return or key==Enum.KeyCode.KeypadEnter) then self.enterHeld=true; if not self.enterIntent then self:key('enter',key) end
  elseif not control and key==Enum.KeyCode.Tab then self:key(if shift then 'outdent' else 'indent',key)
  elseif not control and key==Enum.KeyCode.Backspace then self:key('backspace',key) end
  self.pasteGesture=nil; self.pasteBase=nil; self.pasteVerbatim=nil
 end)
 connect(UIS.InputEnded,function(input)
  if input.KeyCode==Enum.KeyCode.Return or input.KeyCode==Enum.KeyCode.KeypadEnter then self.enterHeld=false end
  if self.guard and self.guard.key==input.KeyCode then self.guard=nil end
  if input.KeyCode==Enum.KeyCode.V and self.pasteGesture then self:commitNative(); self.pasteGesture=nil; self.pasteBase=nil; self.pasteVerbatim=nil end
 end)
 if box.ReturnPressedFromOnScreenKeyboard then connect(box.ReturnPressedFromOnScreenKeyboard,function()
  if self.enterIntent or (self.enterHeld and self.enterCaret) then return end
  self:key('enter',Enum.KeyCode.Return)
 end) end
 self:write(self.history.current)
 return self
end
function Editor:write(state)
 self.writing=true
 self.box.Text=state.text
 self.box.SelectionStart=state.anchor
 self.box.CursorPosition=state.cursor
 self.writing=false
 self.changed(state.text)
end
function Editor:commitNative()
 if self.destroyed or self.writing or self.guard then return end
 local box=self.box
 local source,cursor,anchor=box.Text,box.CursorPosition,box.SelectionStart
 local old=self.history.current
 local before={text=old.text,cursor=old.cursor,anchor=old.anchor}
 local fromPaste=self.pasteBase~=nil or self.pasteGesture~=nil
 if source~=self.history.current.text and self.smartPaste and not self.pasteVerbatim then
  local base=self.pasteBase or self.history.current
  local aligned,position,selection=Text.paste(base.text,source,base.cursor,base.anchor,self.pasteBase~=nil)
  if aligned~=source then source=aligned; cursor=position; anchor=selection end
 end
 self.pasteBase=nil
 self.serial+=1
 local gesture=self.pasteGesture or self.serial
 local state=self.history:record(source,cursor,anchor,gesture)
 if source~=before.text then self.recentNative={history=self.history,before=before,after=source,gesture=gesture,fromPaste=fromPaste,at=os.clock()} end
 if source~=box.Text then
  self.lastNativeFormat={history=self.history,raw=box.Text,formatted=source}
  self:write(state)
 else self.changed(source) end
end
function Editor:nativeChanged()
 if self.destroyed or self.writing then return end
 -- Deferred engine signals from our own Text assignment arrive after the
 -- writing flag clears. Equality, not that flag alone, identifies the echo.
 if self.box.Text==self.history.current.text then return end
 if not self.enterIntent and self.enterHeld and Text.nativeEcho(self.history.current.text,self.history.current.cursor,self.history.current.anchor,'enter',self.box.Text) then
  self:requestEnter(); return
 end
 if self.enterIntent then
  self:queueEnter(); return
 end
 local guard=self.guard
 if guard then
  self:write(guard.state)
  -- Native caret changes can follow Text. Restore after that event completes.
  task.defer(function() if not self.destroyed and self.guard==guard then self:write(guard.state) end end)
  return
 end
 if self.pending then return end
 local history=self.history
 self.pending=true
 task.defer(function()
  self.pending=false
  if not self.destroyed and self.history==history then self:commitNative() end
 end)
end
function Editor:queueEnter()
 local intent=self.enterIntent
 if not intent or intent.scheduled then return end
 intent.scheduled=true
 task.delay(0,function()
  if self.destroyed or self.enterIntent~=intent then return end
  local source,cursor=self.box.Text,self.box.CursorPosition
  task.delay(0,function()
   if self.destroyed or self.enterIntent~=intent then return end
   intent.scheduled=false
   if source==self.box.Text and cursor==self.box.CursorPosition then self:finishEnter()
   else self:queueEnter() end
  end)
 end)
end
function Editor:queueEnterCaret()
 local caret=self.enterCaret
 if not caret or caret.scheduled then return end
 caret.scheduled=true
 task.delay(0,function()
  caret.scheduled=false
  if not self.destroyed and self.enterCaret==caret then self:restoreEnterCaret() end
 end)
end
function Editor:restoreEnterCaret()
 local caret=self.enterCaret
 if not caret or caret.history~=self.history or self.history.current~=caret.state or self.box.Text~=caret.state.text then return end
 self.writing=true; self.box.SelectionStart=caret.state.anchor; self.box.CursorPosition=caret.state.cursor; self.writing=false
end
function Editor:requestEnter()
 if self.enterIntent then return end
 local old=self.history.current
 if self.box.Text==old.text then self.history:select(self.box.CursorPosition,self.box.SelectionStart) end
 local base={text=old.text,cursor=old.cursor,anchor=old.anchor}
 local recent=self.recentNative
 local gesture
 -- Native Text/caret signals may finish before InputBegan is delivered. Fold
 -- that recently committed native newline into the same undo transaction.
 if recent and recent.history==self.history and not recent.fromPaste and recent.after==self.box.Text and os.clock()-recent.at<0.1 and Text.nativeEcho(recent.before.text,recent.before.cursor,recent.before.anchor,'enter',self.box.Text) then
  base=recent.before; gesture=recent.gesture
 elseif self.box.Text~=old.text and not Text.nativeEcho(base.text,base.cursor,base.anchor,'enter',self.box.Text) then
  self:commitNative(); old=self.history.current
  base={text=old.text,cursor=old.cursor,anchor=old.anchor}
 end
 self.serial+=1
 local intent={history=self.history,base=base,gesture=gesture or self.serial}
 self.enterIntent=intent
 -- task.defer is within the same frame and is too early for native editing.
 self:queueEnter()
end
function Editor:finishEnter()
 local intent=self.enterIntent
 if not intent or intent.history~=self.history then return end
 local base=intent.base
 local first,last=Text.nativeEnterSelection(base.text,self.box.Text,self.box.CursorPosition,base.cursor,base.anchor)
 local source,cursor,anchor,nativeCursor=Text.finishEnter(base.text,self.box.Text,first,last)
 if not source then
  if self.box.Text~=base.text then self.enterIntent=nil; self:commitNative() end
  return
 end
 self.enterIntent=nil; self.recentNative=nil
 local before=if self.history.current.text==base.text then self.history.current else self.history.undoStack[#self.history.undoStack]
 if before and before.text==base.text then
  before.cursor=if base.anchor and base.anchor>0 and base.cursor>base.anchor then last else first
  before.anchor=if base.anchor and base.anchor>0 and base.anchor~=base.cursor then (if base.cursor>base.anchor then first else last) else -1
 end
 local state=self.history:record(source,cursor,anchor,intent.gesture)
 self.enterCaret={history=self.history,state=state,nativeCursor=nativeCursor}
 if source~=self.box.Text then self.lastNativeFormat={history=self.history,raw=self.box.Text,formatted=source} end
 self:write(state)
 self:queueEnterCaret()
end
function Editor:key(action,key)
 if self.destroyed then return end
 if action=='enter' then self:requestEnter(); return end
 if self.enterIntent then self:finishEnter(); self.enterIntent=nil end
 local history=self.history; local old=history.current
 if self.box.Text~=old.text then
  local stack=if action=='undo' then history.undoStack elseif action=='redo' then history.redoStack else nil
  local target=stack and stack[#stack]
  local format=self.lastNativeFormat
  local formatEcho=stack and format and format.history==history and self.box.Text==format.raw and (old.text==format.formatted or (target and target.text==format.formatted))
  local echo=not self.pasteBase and (Text.nativeEcho(old.text,old.cursor,old.anchor,action,self.box.Text) or (target and target.text==self.box.Text) or formatEcho)
  if not echo then self:commitNative(); old=history.current end
 end
 if self.box.Text==old.text then history:select(self.box.CursorPosition,self.box.SelectionStart) end
 local source,cursor,anchor
 if action=='undo' or action=='redo' then
  old=history[action](history)
 else
  if action=='backspace' then source,cursor,anchor=Text.backspace(old.text,old.cursor,old.anchor)
  else source,cursor,anchor=Text.indent(old.text,old.cursor,old.anchor,action=='outdent') end
  if not source then return end -- ordinary Backspace is left to the native editor
  old=history:record(source,cursor,anchor)
 end
 local guard=if key then {state=old,key=key} else nil; self.guard=guard
 self:write(old)
 if not guard then return end
 task.defer(function()
  if self.destroyed or self.guard~=guard then return end
  if UIS:GetFocusedTextBox()~=self.box and self.box.CaptureFocus then self.box:CaptureFocus() end
  self:write(old)
 end)
end
function Editor:focus()
 local current=self.history.current
 local saved={text=current.text,cursor=current.cursor,anchor=current.anchor}
 if self.box.CaptureFocus then self.box:CaptureFocus() end
 self.history:select(saved.cursor,saved.anchor); self:write(saved)
end
function Editor:release()
 self.guard=nil; self:finishEnter(); self.enterIntent=nil; self.enterCaret=nil; self.enterHeld=false; self:commitNative(); self.pasteGesture=nil; self.pasteBase=nil; self.pasteVerbatim=nil
end
function Editor:bind(id,source)
 self:release()
 self.serial+=1; self.pending=false
 if self.id then self.sessions[self.id]=self.history end
 self.id=id; self.history=self.sessions[id] or Text.history(source)
 self:write(self.history.current)
end
function Editor:destroy()
 self.destroyed=true; self.guard=nil; self.enterIntent=nil; self.enterCaret=nil
 for _,connection in self.connections do connection:Disconnect() end
 self.connections={}; self.sessions={}; self.lastNativeFormat=nil
end
return Editor

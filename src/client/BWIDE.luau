-- Compact in-game editor. Only source text/Stop intent go to the server.
local Config=require(game.ReplicatedStorage.Shared.BWConfig)
local EditorController=require(script.Parent.BWEditorController)
local Parser=require(game.ReplicatedStorage.Shared.BWParser)
local Hardware=require(game.ReplicatedStorage.Shared.BWChassis)
local HandbookView=require(script.Parent.BWHandbookView)
local IDE={}
IDE.__index=IDE
local statusKeys={"generation","controlEpoch","bwProgramSerial","bwRunRequestId","bwRequestId","bwRunning","bwProgramKind","tankType","bwStatus","bwLine","bwIndex","bwCount","bwInstruction","bwMessage","bwWarning","bwSkipped"}
local function text(parent,class,name)
	local item=Instance.new(class); item.Name=name; item.Font=Enum.Font.Code; item.TextSize=14
	item.TextColor3=Color3.fromRGB(238,239,220); item.BackgroundColor3=Color3.fromRGB(31,39,45)
	item.BorderSizePixel=0; item.Parent=parent
	return item
end
-- Keep each native TextBox page small, even while retained scan dictionaries
-- contain hundreds of thousands of characters. History remains available.
function IDE.pages(message)
 local units={}
 for line in (message.."\n"):gmatch("([^\n]*)\n") do
  while #line>Config.MaxOutputPageBytes do
   local cut=Config.MaxOutputPageBytes
   while cut>0 do local nextByte=line:byte(cut+1); if not nextByte or nextByte<128 or nextByte>=192 then break end; cut-=1 end
   table.insert(units,line:sub(1,cut)); line=line:sub(cut+1)
  end
  table.insert(units,line)
 end
 -- Pack from newest to oldest: the latest page must contain recent prints,
 -- never just a dangling "Running" footer after a full earlier page.
 local reversed,lines,bytes={}, {},0
 local function flush()
  local ordered={}; for i=#lines,1,-1 do table.insert(ordered,lines[i]) end
  table.insert(reversed,table.concat(ordered,"\n")); lines={}; bytes=0
 end
 for index=#units,1,-1 do
  local line=units[index]; local needed=#line+(if #lines>0 then 1 else 0)
  if #lines>0 and (bytes+needed>Config.MaxOutputPageBytes or #lines>=Config.MaxOutputPageLines) then flush(); needed=#line end
  table.insert(lines,line); bytes+=needed
 end
 if #lines>0 or #reversed==0 then flush() end
 local pages={}; for i=#reversed,1,-1 do table.insert(pages,reversed[i]) end
 return pages
end
function IDE.new(playerGui,onRun,onStop,onConfigure,onSource)
	local self=setmetatable({onSource=onSource,connections={},running=false,sources={},requests={},scanOutputs={},minimumScanRequests={},submittedPrograms={},serverSources={},sourceBaselines={},dirtyDrafts={},editedDrafts={}},IDE)
	local gui=Instance.new("ScreenGui"); gui.Name="BWEditor"; gui.ResetOnSpawn=false
	gui:SetAttribute("EditorVersion","E3.3-live")
	gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets; gui.DisplayOrder=30; gui.Parent=playerGui; self.gui=gui
	local toggle=text(gui,"TextButton","ToggleBW")
	toggle.AnchorPoint=Vector2.new(1,1); toggle.Position=UDim2.new(1,-12,1,-12); toggle.Size=UDim2.new(.27,0,0,26)
	toggle.TextScaled=true
	local toggleBounds=Instance.new("UISizeConstraint");toggleBounds.MaxSize=Vector2.new(194,26);toggleBounds.Parent=toggle
	local toggleText=Instance.new("UITextSizeConstraint");toggleText.MaxTextSize=14;toggleText.Parent=toggle
	toggle.Text="BW Editor • E3.3"; toggle.Selectable=true; self.toggle=toggle
	local frame=Instance.new("Frame"); frame.Name="EditorPanel"; frame.AnchorPoint=Vector2.new(0.5,0.5)
	frame.Position=UDim2.fromScale(0.5,0.5); frame.Size=UDim2.fromScale(0.94,0.88)
	frame.BackgroundColor3=Color3.fromRGB(21,28,33); frame.Active=true; frame.Visible=false; frame.Parent=gui; self.frame=frame
	local size=Instance.new("UISizeConstraint"); size.MaxSize=Vector2.new(780,620); size.MinSize=Vector2.new(240,260); size.Parent=frame
	local current=text(frame,"TextLabel","CurrentInstruction")
	current.Position=UDim2.fromOffset(12,32); current.Size=UDim2.new(1,-206,0,14)
	current.BackgroundTransparency=1; current.TextXAlignment=Enum.TextXAlignment.Left; current.TextSize=12; current.TextWrapped=true
	current.Text="BW v0.2 • Ready"; self.current=current
 local execution=text(frame,"TextLabel","ExecutionPosition")
 execution.Position=UDim2.fromOffset(12,47);execution.Size=UDim2.new(1,-206,0,13)
 execution.BackgroundTransparency=1;execution.TextXAlignment=Enum.TextXAlignment.Left;execution.TextSize=11
 execution.Text="Execution: stopped";self.execution=execution
	local run=text(frame,"TextButton","Run"); run.Position=UDim2.new(1,-184,0,32); run.Size=UDim2.fromOffset(78,28)
	run.Text="Run"; run.BackgroundColor3=Color3.fromRGB(43,120,64); run.Selectable=true; self.run=run
	local stop=text(frame,"TextButton","Stop"); stop.Position=UDim2.new(1,-96,0,32); stop.Size=UDim2.fromOffset(84,28)
	stop.Text="Stop"; stop.BackgroundColor3=Color3.fromRGB(153,62,39); stop.Selectable=true; self.stop=stop
	local scroll=Instance.new("ScrollingFrame"); scroll.Name="SourceScroll"
	scroll.Position=UDim2.fromOffset(12,44); scroll.Size=UDim2.new(1,-24,0.75,-64)
	scroll.ScrollBarThickness=6; scroll.BackgroundColor3=Color3.fromRGB(31,39,45); scroll.BorderSizePixel=0
	scroll.ClipsDescendants=true; scroll.Parent=frame; self.scroll=scroll
	local gutter=text(scroll,"TextLabel","LineNumbers"); gutter.Size=UDim2.fromOffset(34,200)
	gutter.TextXAlignment=Enum.TextXAlignment.Right; gutter.TextYAlignment=Enum.TextYAlignment.Top; gutter.BackgroundTransparency=1
	gutter.TextColor3=Color3.fromRGB(132,150,157); self.gutter=gutter
	local highlight=Instance.new("Frame");highlight.Name="ExecutionLineHighlight";highlight.BackgroundColor3=Color3.fromRGB(83,146,86);highlight.BackgroundTransparency=.7;highlight.BorderSizePixel=0;highlight.Active=false;highlight.Visible=false;highlight.Parent=scroll;self.executionHighlight=highlight
 local editor=text(scroll,"TextBox","Source"); editor.Position=UDim2.fromOffset(42,0)
	editor.MultiLine=true; editor.ClearTextOnFocus=false; editor.TextWrapped=false
	editor.TextXAlignment=Enum.TextXAlignment.Left; editor.TextYAlignment=Enum.TextYAlignment.Top
	editor.BackgroundTransparency=1;editor.ZIndex=2;gutter.ZIndex=2
	editor.Text=Config.DefaultSource; self.editor=editor
 local tools=Instance.new("Frame"); tools.Name="SourceTools"; tools.BackgroundTransparency=1
 tools.Position=UDim2.fromOffset(12,90); tools.Size=UDim2.new(1,-24,0,24); tools.Parent=frame; self.sourceTools=tools
 local undo=text(tools,"TextButton","Undo"); undo.Size=UDim2.fromOffset(54,22); undo.Text="Undo"; undo.TextSize=11; self.undo=undo
 local redo=text(tools,"TextButton","Redo"); redo.Position=UDim2.fromOffset(60,0); redo.Size=UDim2.fromOffset(54,22); redo.Text="Redo"; redo.TextSize=11; self.redo=redo
 local pasteMode=text(tools,"TextButton","PasteMode"); pasteMode.Position=UDim2.fromOffset(124,0); pasteMode.Size=UDim2.new(1,-124,0,22)
 pasteMode.TextSize=11; pasteMode.Text="Paste: align"; self.pasteMode=pasteMode
	local outputScroll=Instance.new("ScrollingFrame"); outputScroll.Name="OutputScroll"
	outputScroll.Position=UDim2.new(0,12,0.75,-12); outputScroll.Size=UDim2.new(1,-24,0.25,0)
	outputScroll.ScrollBarThickness=6; outputScroll.BorderSizePixel=0
	outputScroll.Active=true; outputScroll.ScrollingDirection=Enum.ScrollingDirection.XY
	outputScroll.BackgroundColor3=Color3.fromRGB(31,39,45); outputScroll.ClipsDescendants=true
	outputScroll.CanvasPosition=Vector2.zero; outputScroll.Parent=frame; self.outputScroll=outputScroll
	local output=text(outputScroll,"TextBox","Output"); output.Position=UDim2.fromOffset(4,4)
	output.TextXAlignment=Enum.TextXAlignment.Left; output.TextYAlignment=Enum.TextYAlignment.Top
	output.TextWrapped=false; output.TextSize=12; output.Text="Write BW commands, then Run. Scanner(45) prints one observation. Stop releases program control."
	output.MultiLine=true; output.ClearTextOnFocus=false; output.TextEditable=false; output.Selectable=true
	self.output=output
    local older=text(frame,"TextButton","OlderLogs"); older.Position=UDim2.new(0,12,.75,-46); older.Size=UDim2.fromOffset(54,28)
    older.Text="Older"; older.TextSize=11; older.Selectable=true; self.olderLogs=older
    local newer=text(frame,"TextButton","NewerLogs"); newer.Position=UDim2.new(0,72,.75,-46); newer.Size=UDim2.fromOffset(54,28)
    newer.Text="Latest"; newer.TextSize=11; newer.Selectable=true; self.newerLogs=newer
    local logStatus=text(frame,"TextLabel","LogStatus"); logStatus.Position=UDim2.new(0,134,.75,-46); logStatus.Size=UDim2.new(1,-146,0,28)
    logStatus.TextSize=11; logStatus.TextWrapped=true; logStatus.TextXAlignment=Enum.TextXAlignment.Left; logStatus.BackgroundTransparency=1; self.logStatus=logStatus
	local hardware=text(frame,"TextButton","Hardware")
    hardware.Position=UDim2.new(.5,6,0,63); hardware.Size=UDim2.new(.5,-18,0,22); hardware.Text="Hardware / threads"; self.hardwareButton=hardware
    scroll.Position=UDim2.fromOffset(12,118); scroll.Size=UDim2.new(1,-24,0.75,-172)
    local panel=Instance.new("Frame"); panel.Name="HardwarePanel"; panel.Position=UDim2.fromOffset(12,90); panel.Size=UDim2.new(1,-24,0.75,-144)
    panel.BackgroundColor3=Color3.fromRGB(21,28,33); panel.Visible=false; panel.Parent=frame; self.hardwarePanel=panel
    local configEditor=text(panel,"TextBox","HardwareConfiguration"); configEditor.Position=UDim2.fromOffset(0,0); configEditor.Size=UDim2.new(.5,-4,1,-32)
    configEditor.MultiLine=true; configEditor.ClearTextOnFocus=false; configEditor.TextXAlignment=Enum.TextXAlignment.Left; configEditor.TextYAlignment=Enum.TextYAlignment.Top; configEditor.TextSize=12; self.configEditor=configEditor
    local diagnosticScroll=Instance.new("ScrollingFrame"); diagnosticScroll.Name="RuntimeScroll"; diagnosticScroll.Position=UDim2.new(.5,4,0,0); diagnosticScroll.Size=UDim2.new(.5,-4,1,0); diagnosticScroll.ScrollBarThickness=5; diagnosticScroll.Parent=panel; self.diagnosticScroll=diagnosticScroll
    local diagnostics=text(diagnosticScroll,"TextLabel","RuntimeDiagnostics"); diagnostics.Position=UDim2.fromOffset(0,0); diagnostics.Size=UDim2.new(1,-8,1,0)
    diagnostics.TextXAlignment=Enum.TextXAlignment.Left; diagnostics.TextYAlignment=Enum.TextYAlignment.Top; diagnostics.TextSize=11; diagnostics.TextWrapped=true; self.diagnostics=diagnostics
    local apply=text(panel,"TextButton","ApplyHardware"); apply.Position=UDim2.new(0,0,1,-28); apply.Size=UDim2.new(.5,-4,0,28); apply.Text="Apply (program stopped)"; self.applyHardware=apply
    self.runtimeReadings={}
    local handbook=text(frame,"TextButton","OpenHandbook")
    handbook.Position=UDim2.fromOffset(12,63); handbook.Size=UDim2.new(.5,-18,0,22)
    handbook.Text="BW Handbook"; handbook.TextSize=12; handbook.Selectable=true; self.handbookButton=handbook
    self.handbook=HandbookView.new(frame)
    local function connect(event,callback) table.insert(self.connections,event:Connect(callback)) end
 local title=text(frame,"TextLabel","EditorTitleBar");title.Position=UDim2.fromOffset(0,0);title.Size=UDim2.new(1,-148,0,24);title.Text="BW Editor • drag to move";title.Active=true;self.titleBar=title
 local close=text(frame,"TextButton","CloseEditor");close.Position=UDim2.new(1,-32,0,0);close.Size=UDim2.fromOffset(32,24);close.Text="×";self.closeButton=close
 connect(close.Activated,function()self:close()end)
 local tankCode=text(frame,"TextButton","LoadTankCode");tankCode.Position=UDim2.new(1,-148,0,0);tankCode.Size=UDim2.fromOffset(116,24);tankCode.Text="Tank code";tankCode.Visible=false;self.tankCode=tankCode
 connect(tankCode.Activated,function()local reading=self.serverSources[self.tankId];if reading then self:loadTankSource(reading)end end)
 self.window=require(script.Parent.BWEditorWindow).attach(gui,frame,title,connect)
	connect(older.Activated,function()
        self.output:ReleaseFocus(); self.output.SelectionStart=-1
        self.logPageIndex=math.max(1,(self.currentLogPage or #(self.outputPages or {}))-1)
        self:setOutput(self.fullOutputMessage or self.output.Text,true); self:renderLogStatus()
    end)
    connect(newer.Activated,function()
        self.output:ReleaseFocus(); self.output.SelectionStart=-1
        self.logPageIndex=nil; self:setOutput(self.fullOutputMessage or self.output.Text,true); self:renderLogStatus()
    end)
    connect(handbook.Activated,function()
        editor:ReleaseFocus(); output:ReleaseFocus(); configEditor:ReleaseFocus()
        self.handbook:open()
    end)
    connect(hardware.Activated,function() panel.Visible=not panel.Visible; scroll.Visible=not panel.Visible; tools.Visible=not panel.Visible end)
    connect(apply.Activated,function()
        local configuration,reason=self:parseHardware(configEditor.Text)
        if not configuration then diagnostics.Text="Configuration: "..reason; return end
        if onConfigure then onConfigure(configuration) end
    end)
    connect(toggle.Activated,function()
		frame.Visible=not frame.Visible
  if frame.Visible and self.onSource then self.onSource()end
		if not frame.Visible then self:close() end
	end)
	connect(run.Activated,function()
		if (self.running and not self.personalityRunning)or self.pendingRequest then return end
		self.editorController:release();self.handbook:close();editor:ReleaseFocus();self.output:ReleaseFocus()
		local source=editor.Text
		self.logPageIndex=nil; self.fullOutputMessage=nil
		self.pendingRequest=onRun(source)
		if self.tankId then
			self.scanOutputs[self.tankId]=nil
			self.minimumScanRequests[self.tankId]=self.pendingRequest
   local own=self.lastObservedState
   self.submittedPrograms[self.tankId]={source=source,requestId=self.pendingRequest,generation=own and own.generation or 0,epoch=own and own.controlEpoch}
		end
		self:setOutput("Submitted for server validation…")
	end)
	connect(stop.Activated,function()
		editor:ReleaseFocus()
		self.pendingRequest=onStop()
		self:setOutput("Stop requested…"..(if self.scanOutputs[self.tankId] then self.scanOutputs[self.tankId].text else ""))
	end)
 self.lastEditorText=editor.Text
 self.editorController=EditorController.new(editor,function(source)
  self.lastEditorText=source
  if self.tankId and not self.loadingTankSource then
   self.dirtyDrafts[self.tankId]=source~=((self.serverSources[self.tankId]and self.serverSources[self.tankId].text)or self.sourceBaselines[self.tankId]or Config.DefaultSource)
   if self.dirtyDrafts[self.tankId]then self.editedDrafts[self.tankId]=true end
  end
  self:layoutSource();self:sourceStatusChanged();self:refreshSourceTitle()
 end)
 connect(editor:GetPropertyChangedSignal("CursorPosition"),function()self:renderEditorStatus()end)
 connect(pasteMode.Activated,function()
  self.editorController:release(); self.editorController.smartPaste=not self.editorController.smartPaste
  pasteMode.Text=if self.editorController.smartPaste then "Paste: align" else "Paste: exact"
  self.editorController:focus()
 end)
 connect(undo.Activated,function() self.editorController:release(); self.editorController:focus(); self.editorController:key("undo") end)
 connect(redo.Activated,function() self.editorController:release(); self.editorController:focus(); self.editorController:key("redo") end)
	connect(scroll:GetPropertyChangedSignal("AbsoluteSize"),function() self:layoutSource() end)
	connect(outputScroll:GetPropertyChangedSignal("AbsoluteSize"),function() self:layoutOutput(false) end)
	self:layoutSource(); self:layoutOutput(false);self:sourceStatusChanged()
	return self
end
function IDE:fitAboveTouchDrive(touchRoot,driveStick)
 local function position()
  local bottom=if touchRoot.Visible then driveStick.Size.Y.Offset+44 else 12
  self.toggle.Position=UDim2.new(1,-12,1,-bottom)
 end
 table.insert(self.connections,touchRoot:GetPropertyChangedSignal("Visible"):Connect(position))
 table.insert(self.connections,driveStick:GetPropertyChangedSignal("Size"):Connect(position))
 position()
end
function IDE:close()
 if self.window then self.window.stop()end
 self.editorController:release()
	self.handbook:close()
	self.output:ReleaseFocus()
	self.editor:ReleaseFocus()
	self.frame.Visible=false
end
-- Editing and pending acknowledgments belong to the selected persistent tank.
function IDE:bind(id)
	if self.tankId==id then return end
 self.editorController:release()
	self.handbook:close()
	if self.tankId then
		self.sources[self.tankId]=self.editor.Text
		self.requests[self.tankId]=self.pendingRequest
	end
	self.editor:ReleaseFocus()
	self.output:ReleaseFocus()
	self.logPageIndex=nil; self.fullOutputMessage=nil; self.outputPages=nil; self.currentLogPage=nil
	self.tankId=id;self.loadingTankSource=true
 self.editorController:bind(id,self.sources[id] or Config.DefaultSource)
 self.loadingTankSource=false
	self.statusMemoTank=nil;self.renderedDiagnosticTank=nil
	self.pendingRequest=self.requests[id]; self.running=false;self.personalityRunning=false;self.lastObservedState=nil
	self:layoutSource();self:sourceStatusChanged();self:refreshSourceTitle()
end
-- A public tank may have many control leases with reset client request IDs.
-- Keep drafts, but never carry a previous lease's output/request fences across.
function IDE:setControlEpoch(epoch)
 if self.controlEpoch==epoch and self.controlTankId==self.tankId then return end
 self.statusMemoTank=nil;self.renderedDiagnosticTank=nil
 self.controlTankId=self.tankId;self.controlEpoch=epoch;self.pendingRequest=nil;self.lastObservedState=nil
 if self.tankId then
  self.scanOutputs[self.tankId]=nil;self.minimumScanRequests[self.tankId]=0
  self.runtimeReadings[self.tankId]=nil;self.requests[self.tankId]=nil;self.serverSources[self.tankId]=nil
 end
 self:renderEditorStatus();self:refreshSourceTitle()
 if self.tankId and self.onSource then self.onSource()end
end
-- Exact observations arrive privately, separate from public tank snapshots.
function IDE:receiveOutput(id,generation,requestId,reading)
	if requestId<(self.minimumScanRequests[id] or 0) then return end
	local output=self.scanOutputs[id]
 local serial=reading.programSerial or 0
 if output and generation==output.generation and requestId==output.requestId and serial<(output.programSerial or 0)then return end
 if output and (generation<output.generation or (generation==output.generation and requestId<output.requestId)) then return end
	if not output or output.generation~=generation or output.requestId~=requestId or output.programSerial~=serial then
		output={generation=generation,requestId=requestId,programSerial=serial,programKind=reading.programKind,programName=reading.programName,readings={},text=""}; self.scanOutputs[id]=output
	end
	output.receivedCount=(output.receivedCount or 0)+1
 if reading.kind=="print" then output.receivedPrints=(output.receivedPrints or 0)+1 end
	table.insert(output.readings,reading)
	-- Bound mixed scanner diagnostics and explicit prints for one program.
	if #output.readings>Config.MaxOutputEvents then table.remove(output.readings,1) end
	local lines={}
	for _,entry in output.readings do
		local label=if entry.kind=="diagnostic" then "Log" elseif entry.kind=="print" then "print" elseif entry.angle~=nil then string.format("Scanner(%.6g) ->",entry.angle) elseif entry.kind=="scan" then "Scanner" else "Command"
		table.insert(lines,string.format("%s • L%d • t=%.3f • %s",label,entry.line,entry.timestamp,"T"..tostring(entry.thread or 1).." • "..entry.text))
	end
	output.text="\n"..table.concat(lines,"\n")
end
IDE.receiveScan=IDE.receiveOutput -- preserve existing callers while output now includes print
function IDE:layoutOutput(follow)
	local lines,longest=0,0
	for line in (self.output.Text.."\n"):gmatch("([^\n]*)\n") do lines+=1; longest=math.max(longest,#line) end
	local viewport=self.outputScroll.AbsoluteSize
	local width=math.max(1,viewport.X-12,longest*7.5+12)
	local height=math.max(1,lines*16+12)
	self.output.Size=UDim2.fromOffset(width,height)
	self.outputScroll.CanvasSize=UDim2.fromOffset(width+8,height+8)
	if follow then self.outputScroll.CanvasPosition=Vector2.new(self.outputScroll.CanvasPosition.X,math.max(0,height+8-viewport.Y)) end
end
function IDE:setOutput(message,force)
	-- Keep live log updates from clearing a selection while the player copies.
	if game:GetService("UserInputService"):GetFocusedTextBox()==self.output then
        local first,last=self.output.SelectionStart or -1,self.output.CursorPosition or -1
        if first>0 and last>0 and first~=last then self.outputNeedsRefresh=true;return end
    end
	self.outputNeedsRefresh=false
 local pages=self.outputPages
    if force or self.fullOutputMessage~=message or not pages then
        self.fullOutputMessage=message; pages=IDE.pages(message); self.outputPages=pages
    end
    local page=math.clamp(self.logPageIndex or #pages,1,#pages)
    self.currentLogPage=page
    local visible=pages[page]
    if not force and self.output.Text==visible then return end
	local scroll=self.outputScroll
	local canvas=scroll.CanvasSize
	local atBottom=not canvas or scroll.CanvasPosition.Y>=canvas.Y.Offset-scroll.AbsoluteSize.Y-8
	self.output.Text=visible; self:layoutOutput(self.logPageIndex==nil and atBottom)
end
function IDE:renderLogStatus()
 local reading=self.runtimeReadings and self.runtimeReadings[self.tankId]
 local runtime=reading and reading.runtime
 local own=self.lastObservedState
 if own and reading and ((reading.generation~=nil and reading.generation~=(own.generation or 0)) or (reading.requestId~=nil and reading.requestId~=(own.bwRunRequestId or own.bwRequestId or 0))) then runtime=nil end
 local history=self.scanOutputs[self.tankId]
 local received=if history then history.receivedPrints or 0 else 0
 local prints=if runtime and runtime.printCount~=nil then tostring(runtime.printCount) else "?"
 local pages=self.outputPages or {}
 local suffix=if runtime and (runtime.suppressedLogs or 0)>0 then " • rate-limited: "..tostring(runtime.suppressedLogs) else ""
 local first,last=self.output.SelectionStart or -1,self.output.CursorPosition or -1
 if game:GetService("UserInputService"):GetFocusedTextBox()==self.output and first>0 and last>0 and first~=last then suffix..=" • selection paused" end
 self.logStatus.Text=string.format("Prints run: %s • received: %d • page %d/%d",prints,received,self.currentLogPage or 1,math.max(1,#pages))..suffix
end
function IDE:layoutSource()
	local lines,longest,numbers=0,0,{}
	for line in (self.editor.Text.."\n"):gmatch("([^\n]*)\n") do
		lines+=1; if lines>1000 then break end
		longest=math.max(longest,#line)
		table.insert(numbers,tostring(lines))
	end
	local height=math.max(36,math.min(lines,1000)*18+16)
	local width=math.max(220,self.scroll.AbsoluteSize.X-48,math.min(longest,2000)*8.5+16)
	self.editor.Size=UDim2.fromOffset(width,height); self.gutter.Size=UDim2.fromOffset(34,height)
	self.gutter.Text=table.concat(numbers,"\n"); self.scroll.CanvasSize=UDim2.fromOffset(width+48,height)
end
-- The header describes the visible source/caret, never the tank VM's unrelated
-- program (for example an expanded autonomous personality with library lines).
function IDE:renderEditorStatus()
 local source=self.editor.Text
 local cursor=self.editor.CursorPosition
 if not cursor or cursor<1 then cursor=self.editorController and self.editorController.history.current.cursor or 1 end
 cursor=math.clamp(cursor,1,#source+1)
 local _,lineBreaks=source:sub(1,cursor-1):gsub("\n","")
 local _,allBreaks=source:gsub("\n","")
 local suffix="instruction …"
 if self.statusSource==source then
  if self.statusError then suffix="instruction — (syntax error)"
  else
   local index=0
   for _,entry in self.statusInstructions do if entry.line<=lineBreaks+1 then index=entry.index end end
   suffix=string.format("instruction %d/%d",index,#self.statusInstructions)
  end
 end
 self.current.Text=string.format("Line %d/%d • %s",lineBreaks+1,allBreaks+1,suffix)
 self.executionHighlight.Visible=false
 local own=self.lastObservedState;local submitted=self.submittedPrograms[self.tankId]
 if own and own.bwRunning then
  local authoritative=self.serverSources[self.tankId]
  local matching=(submitted and submitted.source==source and submitted.generation==(own.generation or 0)and submitted.requestId==(own.bwRunRequestId or own.bwRequestId or 0)and submitted.epoch==own.controlEpoch)or(authoritative and authoritative.text==source and authoritative.generation==(own.generation or 0)and authoritative.epoch==own.controlEpoch and authoritative.programSerial==own.bwProgramSerial)
  if matching then
   self.execution.Text=string.format("Running line %d • instruction %d/%d",own.bwLine or 0,own.bwIndex or 0,own.bwCount or 0)
   local line=own.bwLine or 0
   if line>=1 and line<=allBreaks+1 then
    local bounds=self.editor.TextBounds
    local row=if bounds and bounds.Y>0 then bounds.Y/(allBreaks+1)else 18
    self.executionHighlight.Position=UDim2.fromOffset(42,(line-1)*row)
    self.executionHighlight.Size=UDim2.new(0,self.editor.Size.X.Offset,0,row)
    self.executionHighlight.Visible=true
   end
  else self.execution.Text="Execution: different program running in tank"end
 elseif self.pendingRequest then self.execution.Text="Execution: awaiting server"
 else self.execution.Text="Execution: "..(own and own.bwStatus or "stopped")end
end
function IDE:sourceStatusChanged()
 self.statusRevision=(self.statusRevision or 0)+1
 local revision=self.statusRevision;local source=self.editor.Text
 self:renderEditorStatus()
 -- Do not compile the buffer on every render/cursor movement. Debounce typing;
 -- an old callback cannot overwrite a replacement/switch/undo's source mapping.
 task.delay(.2,function()
  if self.destroyed or self.statusRevision~=revision or self.editor.Text~=source then return end
  local parsed,err=Parser.parse(source);local entries={}
  if parsed then
   local ids={};for id in parsed.streams do table.insert(ids,id)end;table.sort(ids)
   for _,id in ids do for _,instruction in ipairs(parsed.streams[id])do
    table.insert(entries,{line=instruction.line,index=#entries+1})
   end end
  end
  self.statusSource=source;self.statusError=err;self.statusInstructions=entries
  self:renderEditorStatus()
 end)
end
function IDE:parseHardware(source)
 local lines={}; for line in (source.."\n"):gmatch("([^\n]*)\n") do if line:match("%S") then table.insert(lines,line) end end
 local config={tier=lines[1],devices={}}
 for i=2,#lines do
  local name,bus,allocation=lines[i]:match("^(%w+)%s+(%d+)%s+([%d.]+)%s*$")
  if not name or config.devices[name] then return nil,"Use: device bus allocation (one per line)." end
  config.devices[name]={bus=tonumber(bus),allocation=tonumber(allocation)}
 end
 local ok,reason=Hardware.validate(config); if not ok then return nil,reason end
 return config
end
function IDE:refreshSourceTitle()
 local source=self.serverSources[self.tankId]
 self.tankCode.Visible=source~=nil
 self.titleBar.Text=if source then source.name..(if self.dirtyDrafts[self.tankId]then " • local draft"else " • drag to move")else "BW Editor • drag to move"
end
function IDE:loadTankSource(source)
 self.loadingTankSource=true
 self.editorController:loadSource(source.text)
 self.loadingTankSource=false
 self.sourceBaselines[self.tankId]=source.text;self.dirtyDrafts[self.tankId]=false;self.editedDrafts[self.tankId]=false
 self.sources[self.tankId]=source.text;self:refreshSourceTitle();self:renderEditorStatus()
end
function IDE:receiveTankSource(id,reading)
 local source=reading.source
 if type(source)~="table"or type(source.text)~="string"then return end
 source=table.clone(source);source.name=if type(source.name)=="string"then source.name else "Tank program";source.generation=reading.generation;source.requestId=reading.requestId;source.epoch=reading.controlEpoch
 self.serverSources[id]=source
 if id~=self.tankId then return end
 if self.editor.Text==source.text then
  self.sourceBaselines[id]=source.text;self.dirtyDrafts[id]=false
 elseif not self.dirtyDrafts[id]and not self.editedDrafts[id]then self:loadTankSource(source)else self.dirtyDrafts[id]=true end
 self:refreshSourceTitle();self:renderEditorStatus()
end
function IDE:receiveRuntime(id,reading)
 local old=self.runtimeReadings[id]
 if old and reading.generation~=nil and old.generation~=nil then
  if reading.generation<old.generation or (reading.generation==old.generation and reading.requestId~=nil and old.requestId~=nil and reading.requestId<old.requestId)then return end
 end
 if not reading.configurationResult and old then reading.configurationResult=old.configurationResult end
 self.runtimeReadings[id]=reading
 self:receiveTankSource(id,reading)
end
function IDE:renderRuntime()
 local reading=self.runtimeReadings[self.tankId]; if not reading then return end
 local own=self.lastObservedState
 local clock=reading.runtime and reading.runtime.clock
 if self.renderedDiagnostic==reading and self.renderedDiagnosticTank==self.tankId and self.renderedDiagnosticGeneration==(own and own.generation)and self.renderedDiagnosticRun==(own and own.bwRunRequestId)and self.renderedDiagnosticSerial==(own and own.bwProgramSerial)and self.renderedDiagnosticClock==clock then return end
 self.renderedDiagnostic=reading;self.renderedDiagnosticTank=self.tankId;self.renderedDiagnosticGeneration=own and own.generation;self.renderedDiagnosticRun=own and own.bwRunRequestId;self.renderedDiagnosticSerial=own and own.bwProgramSerial;self.renderedDiagnosticClock=clock
 local config=reading.configuration
 if config then
  self.configEditor.TextEditable=config.allocations==nil
  self.applyHardware.Visible=config.allocations==nil
  if config.allocations then
   local lines={config.tier,"Garage bus configuration"}
   for _,name in Hardware.Categories do table.insert(lines,string.format("%s %.1f%%",name,config.allocations[name])) end
   self.configEditor.Text=table.concat(lines,"\n")
  elseif self.lastHardwareTank~=self.tankId or reading.configurationResult then
   local lines={config.tier}; local names={}; for name in config.devices do table.insert(names,name) end; table.sort(names)
   for _,name in names do local d=config.devices[name]; table.insert(lines,string.format("%s %d %g",name,d.bus,d.allocation)) end
   self.configEditor.Text=table.concat(lines,"\n")
  end
  self.lastHardwareTank=self.tankId
 end
 local spec=Hardware.Tiers[config and config.tier or "Hexadeca"]
 local lines={string.format("%d threads, %d ticks, queue %d",spec.threads,spec.ticks,spec.queue),if reading.configurationResult then "Config: "..reading.configurationResult else "Device bus allocation%"}
 local r=reading.runtime
 local own=self.lastObservedState
 if own and ((reading.generation~=nil and reading.generation~=(own.generation or 0))or(reading.requestId~=nil and reading.requestId~=(own.bwRunRequestId or own.bwRequestId or 0)))then r=nil end
 if r then
  table.insert(lines,string.format("%s • %.3fs • %d ticks/cycle",r.tier,r.clock,r.ticksPerCycle))
  table.insert(lines,string.format("Scans: %d • log attempts: %d • omitted: %d",r.scanCount or 0,r.outputCount or 0,r.suppressedLogs or 0))
  local ids={}; for id in r.threads do table.insert(ids,id) end; table.sort(ids)
  for _,id in ids do local t=r.threads[id]; table.insert(lines,string.format("T%d L%d %s %s ticks=%.1f",id,t.line,t.state,t.waiting,t.ticks)..string.format(" loops=%d prints=%d",t.loopTests or 0,t.prints or 0)..string.format(" depth=%d %s",t.callDepth or 0,t.functionName or "")); if t.error and t.error~="" then table.insert(lines,"  "..t.error) end end
  local names={}; for name in r.devices do table.insert(names,name) end; table.sort(names)
  for _,name in names do local d=r.devices[name]; local idsInQueue={}; for _,c in d.queue do table.insert(idsInQueue,tostring(c.id)..":"..c.op) end
   table.insert(lines,string.format("%s B%d %g%% active=%s Q[%s]",name,d.bus,d.allocation,if d.active then tostring(d.active.id)..":"..d.active.op else "idle",table.concat(idsInQueue,",")))
   if d.steeringDegrees~=nil then table.insert(lines,string.format("  wheel target %.1f degrees (+left / -right)",d.steeringDegrees)) end
   if d.acquisitionSeconds then
    table.insert(lines,string.format("  %.1f° / %.1f studs • %.2fs acquisition",d.coneWidth,d.range,d.acquisitionSeconds))
   end
   if d.lastScan then
    local reading=d.lastScan
    local result=if reading.status=="success" then tostring(reading.count).." objects" else reading.reason or "failed"
    table.insert(lines,string.format("  scans %d ok / %d failed • %s @ %.3fs",d.scanSuccesses or 0,d.scanFailures or 0,result,reading.timestamp))
   end
  end
 end
 if r then for _,c in r.recent or {} do if c.state=="failed" or c.state=="cancelled" then table.insert(lines,string.format("#%d T%d %s %s",c.id,c.thread,c.state,c.reason or "")) end end end
 self.diagnostics.Text=table.concat(lines,"\n")
 local height=math.max(120,#lines*30); self.diagnostics.Size=UDim2.new(1,-8,0,height); self.diagnosticScroll.CanvasSize=UDim2.fromOffset(0,height)
end
function IDE:update(state)
 self.lastObservedState=state
 self:renderRuntime()
	if not state then self.running=false;self.personalityRunning=false; self:renderEditorStatus(); return end
	self.running=state.bwRunning==true
 self.personalityRunning=self.running and state.bwProgramKind=="Personality"
	self.toggle.Text=(state.tankType or "Tank")..(if self.running then " • BW running" else " • BW Editor")
	self.editor.TextEditable=not self.running or self.personalityRunning
	self.run.AutoButtonColor=(not self.running or self.personalityRunning)and not self.pendingRequest
	if self.pendingRequest and (state.bwRequestId or 0)<self.pendingRequest then return end
	self.pendingRequest=nil
 local history=self.scanOutputs[self.tankId];local logText=history and history.text
 local memo=self.statusMemo or{};self.statusMemo=memo
 local same=self.statusMemoTank==self.tankId and self.statusMemoLog==logText and self.statusMemoVisible==self.frame.Visible
 for _,key in statusKeys do if memo[key]~=state[key]then same=false;break end end
 if same and self.outputNeedsRefresh then
  local first,last=self.output.SelectionStart or -1,self.output.CursorPosition or -1
  if game:GetService("UserInputService"):GetFocusedTextBox()~=self.output or first<1 or last<1 or first==last then same=false end
 end
 if same then
  if self.renderedLogReading~=self.runtimeReadings[self.tankId]then self.renderedLogReading=self.runtimeReadings[self.tankId];self:renderLogStatus()end
  return
 end
 for _,key in statusKeys do memo[key]=state[key]end
 self.statusMemoTank=self.tankId;self.statusMemoLog=logText;self.statusMemoVisible=self.frame.Visible
	local status=state.bwStatus or "idle"
	self:renderEditorStatus()
	local message=(if self.running then (state.bwInstruction or "").."\n" else "")..(state.bwMessage or "Ready. BW controls the selected tank while running.")
	local output=self.scanOutputs[self.tankId]
	if output and output.generation==(state.generation or 0) and output.requestId==(state.bwRunRequestId or state.bwRequestId or 0) then
		local provenance=if output.programName then string.format("%s • %s • run %d\n",tostring(self.tankId),output.programName,output.programSerial)else ""
  if state.bwProgramSerial==nil or output.programSerial==state.bwProgramSerial then message=provenance..output.text:sub(2).."\n"..message end
	elseif output and (output.generation<(state.generation or 0) or output.requestId<(state.bwRunRequestId or state.bwRequestId or 0)) then self.scanOutputs[self.tankId]=nil end
	if state.bwWarning and state.bwWarning~="" then message..="\n"..state.bwWarning end
	self:setOutput(message)
 self:renderLogStatus()
	self.output.TextColor3=if status=="error" then Color3.fromRGB(255,157,125) else Color3.fromRGB(238,239,220)
end
function IDE:destroy()
 if self.window then self.window.stop()end
 self.editorController:destroy()
	self.destroyed=true
	self.handbook:destroy()
	for _,connection in self.connections do connection:Disconnect() end
	self.gui:Destroy()
end
return IDE

-- Compact in-game editor. Only source text/Stop intent go to the server.
local Config=require(game.ReplicatedStorage.Shared.BWConfig)
local EditorText=require(game.ReplicatedStorage.Shared.BWEditorText)
local IDE={}
IDE.__index=IDE
local function text(parent,class,name)
	local item=Instance.new(class); item.Name=name; item.Font=Enum.Font.Code; item.TextSize=14
	item.TextColor3=Color3.fromRGB(238,239,220); item.BackgroundColor3=Color3.fromRGB(31,39,45)
	item.BorderSizePixel=0; item.Parent=parent
	return item
end
function IDE.new(playerGui,onRun,onStop)
	local self=setmetatable({connections={},running=false,sources={},requests={},scanOutputs={},minimumScanRequests={}},IDE)
	local gui=Instance.new("ScreenGui"); gui.Name="BWEditor"; gui.ResetOnSpawn=false
	gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets; gui.DisplayOrder=30; gui.Parent=playerGui; self.gui=gui
	local toggle=text(gui,"TextButton","ToggleBW")
	toggle.AnchorPoint=Vector2.new(1,0); toggle.Position=UDim2.new(1,-8,0,172); toggle.Size=UDim2.fromOffset(194,26)
	toggle.Text="BW Editor"; toggle.Selectable=true; self.toggle=toggle
	local frame=Instance.new("Frame"); frame.Name="EditorPanel"; frame.AnchorPoint=Vector2.new(0.5,0.5)
	frame.Position=UDim2.fromScale(0.5,0.5); frame.Size=UDim2.fromScale(0.94,0.88)
	frame.BackgroundColor3=Color3.fromRGB(21,28,33); frame.Active=true; frame.Visible=false; frame.Parent=gui; self.frame=frame
	local size=Instance.new("UISizeConstraint"); size.MaxSize=Vector2.new(780,620); size.MinSize=Vector2.new(240,170); size.Parent=frame
	local current=text(frame,"TextLabel","CurrentInstruction")
	current.Position=UDim2.fromOffset(12,8); current.Size=UDim2.new(1,-206,0,28)
	current.BackgroundTransparency=1; current.TextXAlignment=Enum.TextXAlignment.Left; current.TextSize=12; current.TextWrapped=true
	current.Text="BW v0.2 • Ready"; self.current=current
	local run=text(frame,"TextButton","Run"); run.Position=UDim2.new(1,-184,0,8); run.Size=UDim2.fromOffset(78,28)
	run.Text="Run"; run.BackgroundColor3=Color3.fromRGB(43,120,64); run.Selectable=true; self.run=run
	local stop=text(frame,"TextButton","Stop"); stop.Position=UDim2.new(1,-96,0,8); stop.Size=UDim2.fromOffset(84,28)
	stop.Text="Stop"; stop.BackgroundColor3=Color3.fromRGB(153,62,39); stop.Selectable=true; self.stop=stop
	local scroll=Instance.new("ScrollingFrame"); scroll.Name="SourceScroll"
	scroll.Position=UDim2.fromOffset(12,44); scroll.Size=UDim2.new(1,-24,0.75,-64)
	scroll.ScrollBarThickness=6; scroll.BackgroundColor3=Color3.fromRGB(31,39,45); scroll.BorderSizePixel=0
	scroll.ClipsDescendants=true; scroll.Parent=frame; self.scroll=scroll
	local gutter=text(scroll,"TextLabel","LineNumbers"); gutter.Size=UDim2.fromOffset(34,200)
	gutter.TextXAlignment=Enum.TextXAlignment.Right; gutter.TextYAlignment=Enum.TextYAlignment.Top; gutter.BackgroundTransparency=1
	gutter.TextColor3=Color3.fromRGB(132,150,157); self.gutter=gutter
	local editor=text(scroll,"TextBox","Source"); editor.Position=UDim2.fromOffset(42,0)
	editor.MultiLine=true; editor.ClearTextOnFocus=false; editor.TextWrapped=false
	editor.TextXAlignment=Enum.TextXAlignment.Left; editor.TextYAlignment=Enum.TextYAlignment.Top
	editor.Text=Config.DefaultSource; self.editor=editor
	local outputScroll=Instance.new("ScrollingFrame"); outputScroll.Name="OutputScroll"
	outputScroll.Position=UDim2.new(0,12,0.75,-12); outputScroll.Size=UDim2.new(1,-24,0.25,0)
	outputScroll.ScrollBarThickness=6; outputScroll.BorderSizePixel=0
	outputScroll.Active=true; outputScroll.ScrollingDirection=Enum.ScrollingDirection.XY
	outputScroll.BackgroundColor3=Color3.fromRGB(31,39,45); outputScroll.ClipsDescendants=true
	outputScroll.CanvasPosition=Vector2.zero; outputScroll.Parent=frame; self.outputScroll=outputScroll
	local output=text(outputScroll,"TextLabel","Output"); output.Position=UDim2.fromOffset(4,4)
	output.TextXAlignment=Enum.TextXAlignment.Left; output.TextYAlignment=Enum.TextYAlignment.Top
	output.TextWrapped=false; output.TextSize=12; output.Text="Write BW commands, then Run. Scanner(45) prints one observation. Stop releases program control."
	self.output=output
	local function connect(event,callback) table.insert(self.connections,event:Connect(callback)) end
	connect(toggle.Activated,function()
		frame.Visible=not frame.Visible
		if not frame.Visible then self:close() end
	end)
	connect(run.Activated,function()
		if self.running or self.pendingRequest then return end
		self:close()
		local source=EditorText.edit(self.lastEditorText,editor.Text,-1)
		if source~=editor.Text then editor.Text=source end
		self.pendingRequest=onRun(source)
		if self.tankId then
			self.scanOutputs[self.tankId]=nil
			self.minimumScanRequests[self.tankId]=self.pendingRequest
		end
		self:setOutput("Submitted for server validation…")
	end)
	connect(stop.Activated,function()
		editor:ReleaseFocus()
		self.pendingRequest=onStop()
		self:setOutput("Stop requested…"..(if self.scanOutputs[self.tankId] then self.scanOutputs[self.tankId].text else ""))
	end)
	self.lastEditorText=editor.Text
	connect(editor:GetPropertyChangedSignal("Text"),function()
		if self.adjustingText then return end
		-- Native TextBox caret updates may follow Text; read the settled position.
		task.defer(function()
			if self.destroyed then return end
			local source,cursor=EditorText.edit(self.lastEditorText,editor.Text,editor.CursorPosition or -1)
			self.lastEditorText=source
			if source~=editor.Text then
				self.adjustingText=true; editor.Text=source
				if cursor>0 then editor.CursorPosition=cursor end
				self.adjustingText=false
			end
			self:layoutSource()
		end)
	end)
	connect(scroll:GetPropertyChangedSignal("AbsoluteSize"),function() self:layoutSource() end)
	connect(outputScroll:GetPropertyChangedSignal("AbsoluteSize"),function() self:layoutOutput(false) end)
	self:layoutSource(); self:layoutOutput(false)
	return self
end
function IDE:close()
	self.editor:ReleaseFocus()
	self.frame.Visible=false
end
-- Editing and pending acknowledgments belong to the selected persistent tank.
function IDE:bind(id)
	if self.tankId==id then return end
	if self.tankId then
		self.sources[self.tankId]=self.editor.Text
		self.requests[self.tankId]=self.pendingRequest
	end
	self.editor:ReleaseFocus()
	self.tankId=id; self.editor.Text=self.sources[id] or Config.DefaultSource
	self.pendingRequest=self.requests[id]; self.running=false
	self:layoutSource()
end
-- Exact observations arrive privately, separate from public tank snapshots.
function IDE:receiveOutput(id,generation,requestId,reading)
	if requestId<(self.minimumScanRequests[id] or 0) then return end
	local output=self.scanOutputs[id]
	if output and (generation<output.generation or (generation==output.generation and requestId<output.requestId)) then return end
	if not output or output.generation~=generation or output.requestId~=requestId then
		output={generation=generation,requestId=requestId,readings={},text=""}; self.scanOutputs[id]=output
	end
	table.insert(output.readings,reading)
	-- Bound mixed scanner diagnostics and explicit prints for one program.
	if #output.readings>Config.MaxOutputEvents then table.remove(output.readings,1) end
	local lines={}
	for _,entry in output.readings do
		local label=if entry.kind=="print" then "print" elseif entry.angle~=nil then string.format("Scanner(%.6g) ->",entry.angle) else "Scanner"
		table.insert(lines,string.format("%s • L%d • t=%.3f • %s",label,entry.line,entry.timestamp,entry.text))
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
function IDE:setOutput(message)
	if self.output.Text==message then return end
	local scroll=self.outputScroll
	local canvas=scroll.CanvasSize
	local atBottom=not canvas or scroll.CanvasPosition.Y>=canvas.Y.Offset-scroll.AbsoluteSize.Y-8
	self.output.Text=message; self:layoutOutput(atBottom)
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
function IDE:update(state)
	if not state then self.running=false; self.current.Text="BW v0.2 • Waiting for tank"; return end
	self.running=state.bwRunning==true
	self.toggle.Text=(state.tankType or "Tank")..(if self.running then " • BW running" else " • BW Editor")
	self.editor.TextEditable=not self.running
	self.run.AutoButtonColor=not self.running and not self.pendingRequest
	if self.pendingRequest and (state.bwRequestId or 0)<self.pendingRequest then return end
	self.pendingRequest=nil
	local status=state.bwStatus or "idle"
	self.current.Text=if self.running then string.format("Line %d • instruction %d/%d",state.bwLine or 0,state.bwIndex or 0,state.bwCount or 0)
		else "BW v0.2 • "..status
	local message=(if self.running then (state.bwInstruction or "").."\n" else "")..(state.bwMessage or "Ready. BW controls the selected tank while running.")
	local output=self.scanOutputs[self.tankId]
	if output and output.generation==(state.generation or 0) and output.requestId==(state.bwRunRequestId or state.bwRequestId or 0) then
		message=output.text:sub(2).."\n"..message
	elseif output and (output.generation<(state.generation or 0) or output.requestId<(state.bwRunRequestId or state.bwRequestId or 0)) then self.scanOutputs[self.tankId]=nil end
	if state.bwWarning and state.bwWarning~="" then message..="\n"..state.bwWarning end
	self:setOutput(message)
	self.output.TextColor3=if status=="error" then Color3.fromRGB(255,157,125) else Color3.fromRGB(238,239,220)
end
function IDE:destroy()
	self.destroyed=true
	for _,connection in self.connections do connection:Disconnect() end
	self.gui:Destroy()
end
return IDE

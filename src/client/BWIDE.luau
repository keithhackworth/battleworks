-- Compact in-game editor. Only source text/Stop intent go to the server.
local Config=require(game.ReplicatedStorage.Shared.BWConfig)
local IDE={}
IDE.__index=IDE
local function text(parent,class,name)
	local item=Instance.new(class); item.Name=name; item.Font=Enum.Font.Code; item.TextSize=14
	item.TextColor3=Color3.fromRGB(238,239,220); item.BackgroundColor3=Color3.fromRGB(31,39,45)
	item.BorderSizePixel=0; item.Parent=parent
	return item
end
function IDE.new(playerGui,onRun,onStop)
	local self=setmetatable({connections={},running=false},IDE)
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
	current.Text="BW v0.1 • Ready"; self.current=current
	local run=text(frame,"TextButton","Run"); run.Position=UDim2.new(1,-184,0,8); run.Size=UDim2.fromOffset(78,28)
	run.Text="Run"; run.BackgroundColor3=Color3.fromRGB(43,120,64); run.Selectable=true; self.run=run
	local stop=text(frame,"TextButton","Stop"); stop.Position=UDim2.new(1,-96,0,8); stop.Size=UDim2.fromOffset(84,28)
	stop.Text="Stop"; stop.BackgroundColor3=Color3.fromRGB(153,62,39); stop.Selectable=true; self.stop=stop
	local scroll=Instance.new("ScrollingFrame"); scroll.Name="SourceScroll"
	scroll.Position=UDim2.fromOffset(12,44); scroll.Size=UDim2.new(1,-24,1,-140)
	scroll.ScrollBarThickness=6; scroll.BackgroundColor3=Color3.fromRGB(31,39,45); scroll.BorderSizePixel=0
	scroll.ClipsDescendants=true; scroll.Parent=frame; self.scroll=scroll
	local gutter=text(scroll,"TextLabel","LineNumbers"); gutter.Size=UDim2.fromOffset(34,200)
	gutter.TextXAlignment=Enum.TextXAlignment.Right; gutter.TextYAlignment=Enum.TextYAlignment.Top; gutter.BackgroundTransparency=1
	gutter.TextColor3=Color3.fromRGB(132,150,157); self.gutter=gutter
	local editor=text(scroll,"TextBox","Source"); editor.Position=UDim2.fromOffset(42,0)
	editor.MultiLine=true; editor.ClearTextOnFocus=false; editor.TextWrapped=false
	editor.TextXAlignment=Enum.TextXAlignment.Left; editor.TextYAlignment=Enum.TextYAlignment.Top
	editor.Text=Config.DefaultSource; self.editor=editor
	local output=text(frame,"TextLabel","Output"); output.Position=UDim2.new(0,12,1,-88); output.Size=UDim2.new(1,-24,0,76)
	output.TextXAlignment=Enum.TextXAlignment.Left; output.TextYAlignment=Enum.TextYAlignment.Top
	output.TextWrapped=true; output.TextSize=12; output.Text="Write BW commands, then Run. Stop releases program control."
	self.output=output
	local function connect(event,callback) table.insert(self.connections,event:Connect(callback)) end
	connect(toggle.Activated,function()
		frame.Visible=not frame.Visible
		if not frame.Visible then editor:ReleaseFocus() end
	end)
	connect(run.Activated,function()
		if self.running or self.pendingRequest then return end
		editor:ReleaseFocus()
		self.pendingRequest=onRun(editor.Text)
		output.Text="Submitted for server validation…"
	end)
	connect(stop.Activated,function()
		editor:ReleaseFocus()
		self.pendingRequest=onStop()
		output.Text="Stop requested…"
	end)
	connect(editor:GetPropertyChangedSignal("Text"),function() self:layoutSource() end)
	connect(scroll:GetPropertyChangedSignal("AbsoluteSize"),function() self:layoutSource() end)
	self:layoutSource()
	return self
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
	if not state then self.running=false; self.current.Text="BW v0.1 • Waiting for tank"; return end
	self.running=state.bwRunning==true
	self.toggle.Text=if self.running then "BW: running • Open" else "BW Editor"
	self.editor.TextEditable=not self.running
	self.run.AutoButtonColor=not self.running and not self.pendingRequest
	if self.pendingRequest and (state.bwRequestId or 0)<self.pendingRequest then return end
	self.pendingRequest=nil
	local status=state.bwStatus or "idle"
	self.current.Text=if self.running then string.format("Line %d • instruction %d/%d",state.bwLine or 0,state.bwIndex or 0,state.bwCount or 0)
		else "BW v0.1 • "..status
	self.output.Text=(if self.running then (state.bwInstruction or "").."\n" else "")..(state.bwMessage or "Ready. BW controls the selected tank while running.")
	self.output.TextColor3=if status=="error" then Color3.fromRGB(255,157,125) else Color3.fromRGB(238,239,220)
end
function IDE:destroy()
	for _,connection in self.connections do connection:Disconnect() end
	self.gui:Destroy()
end
return IDE

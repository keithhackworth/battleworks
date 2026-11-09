-- Local, read-only popup; opening it never changes BW execution or tank controls.
local TextService=game:GetService("TextService")
local Content=require(game.ReplicatedStorage.Shared.BWHandbook)
local View={}; View.__index=View
local function text(parent,class,name)
 local item=Instance.new(class); item.Name=name; item.Font=Enum.Font.Code; item.TextSize=14
 item.TextColor3=Color3.fromRGB(238,239,220); item.BackgroundColor3=Color3.fromRGB(31,39,45)
 item.BorderSizePixel=0; item.ZIndex=22; item.Parent=parent
 return item
end
function View.new(parent)
 local self=setmetatable({connections={},sections=Content.sections(),tabs={}},View)
 local frame=Instance.new("Frame"); frame.Name="BWHandbookPopup"; frame.Size=UDim2.fromScale(1,1)
 frame.Position=UDim2.fromScale(0,0); frame.BackgroundColor3=Color3.fromRGB(21,28,33)
 frame.BorderSizePixel=0; frame.Active=true; frame.ZIndex=20; frame.Visible=false; frame.Parent=parent; self.frame=frame
 local title=text(frame,"TextLabel","HandbookTitle"); title.Position=UDim2.fromOffset(12,6)
 title.Size=UDim2.new(1,-110,0,34); title.TextXAlignment=Enum.TextXAlignment.Left; title.TextWrapped=true; title.TextSize=14; title.BackgroundTransparency=1; self.title=title
 local close=text(frame,"TextButton","CloseHandbook"); close.Position=UDim2.new(1,-90,0,10)
 close.Size=UDim2.fromOffset(78,28); close.Text="Close"; close.Selectable=true; self.closeButton=close
 local hint=text(frame,"TextLabel","HandbookHint"); hint.Position=UDim2.fromOffset(12,42)
 hint.Size=UDim2.new(1,-24,0,28); hint.TextSize=11; hint.TextWrapped=true; hint.TextXAlignment=Enum.TextXAlignment.Left; hint.BackgroundTransparency=1
 hint.Text="Commands are indexed at the top of each topic. Use the right scrollbar for details; scroll tabs sideways for more topics."
 local navigation=Instance.new("ScrollingFrame"); navigation.Name="HandbookTopics"
 navigation.Position=UDim2.fromOffset(12,74); navigation.Size=UDim2.new(1,-24,0,38)
 navigation.BackgroundTransparency=1; navigation.BorderSizePixel=0; navigation.ScrollBarThickness=8; navigation.ScrollBarImageTransparency=0; navigation.ScrollBarImageColor3=Color3.fromRGB(210,220,225)
 navigation.ScrollingDirection=Enum.ScrollingDirection.X; navigation.CanvasSize=UDim2.fromOffset(#self.sections*132,34)
 navigation.Active=true; navigation.ClipsDescendants=true; navigation.ZIndex=21; navigation.Parent=frame; self.navigation=navigation
 local scroll=Instance.new("ScrollingFrame"); scroll.Name="HandbookScroll"
 scroll.Position=UDim2.fromOffset(12,120); scroll.Size=UDim2.new(1,-24,1,-132)
 scroll.BackgroundColor3=Color3.fromRGB(31,39,45); scroll.BorderSizePixel=0; scroll.ScrollBarThickness=10; scroll.ScrollBarImageTransparency=0; scroll.ScrollBarImageColor3=Color3.fromRGB(210,220,225); scroll.ScrollingEnabled=true
 scroll.ScrollingDirection=Enum.ScrollingDirection.Y; scroll.AutomaticCanvasSize=Enum.AutomaticSize.None
 scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.CanvasPosition=Vector2.zero
 scroll.Active=true; scroll.ClipsDescendants=true; scroll.ZIndex=21; scroll.Parent=frame; self.scroll=scroll
 local body=text(scroll,"TextBox","HandbookText"); body.Position=UDim2.fromOffset(8,6)
 body.Size=UDim2.new(1,-26,0,0); body.AutomaticSize=Enum.AutomaticSize.None
 body.TextXAlignment=Enum.TextXAlignment.Left; body.TextYAlignment=Enum.TextYAlignment.Top
 body.TextWrapped=true; body.MultiLine=true; body.ClearTextOnFocus=false; body.TextEditable=false; body.Selectable=true; self.body=body
 table.insert(self.connections,scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:layout() end))
 table.insert(self.connections,close.Activated:Connect(function() self:close() end))
 for index,section in self.sections do
  local tab=text(navigation,"TextButton","HandbookTab_"..section.id)
  tab.Position=UDim2.fromOffset((index-1)*132,0); tab.Size=UDim2.fromOffset(126,30)
  tab.Text=section.label; tab.TextSize=12; tab.Selectable=true; self.tabs[index]=tab
  table.insert(self.connections,tab.Activated:Connect(function() self:showSection(index) end))
 end
 self:showSection(1)
 return self
end
function View:layout()
 -- A measured explicit canvas avoids TextBox/AutomaticCanvasSize feedback:
 -- long sections must be scrollable even when their text exceeds the viewport.
 local width=math.max(1,self.scroll.AbsoluteSize.X-40)
 local bounds=TextService:GetTextSize(self.body.Text,self.body.TextSize,self.body.Font,Vector2.new(width,1000000))
 local height=math.ceil(bounds.Y)+24
 self.body.Size=UDim2.fromOffset(width,height)
 self.scroll.CanvasSize=UDim2.fromOffset(0,height+12)
end
function View:showSection(index)
 local section=self.sections[index]; if not section then return end
 self.body:ReleaseFocus(); self.selected=index
 self.title.Text="BW Handbook • "..section.title; self.body.Text=section.body
 self:layout()
 self.scroll.CanvasPosition=Vector2.zero
 for i,tab in self.tabs do tab.BackgroundColor3=if i==index then Color3.fromRGB(43,100,120) else Color3.fromRGB(31,39,45) end
end
function View:open() self.frame.Visible=true; self:layout() end
function View:close() self.body:ReleaseFocus(); self.frame.Visible=false end
function View:destroy()
 for _,connection in self.connections do connection:Disconnect() end
 self.frame:Destroy()
end
return View

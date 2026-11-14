-- Shared responsive card, typography, buttons and focus lifecycle.
local View={}; View.__index=View
local ink=Color3.fromRGB(237,239,224)
local muted=Color3.fromRGB(160,176,179)
local orange=Color3.fromRGB(240,158,69)
local function label(parent,name,text,size,color)
 local item=Instance.new("TextLabel"); item.Name=name; item.Text=text; item.Font=Enum.Font.GothamMedium
 item.TextSize=size; item.TextColor3=color or ink; item.TextXAlignment=Enum.TextXAlignment.Left
 item.BackgroundTransparency=1; item.TextWrapped=true; item.Parent=parent
 return item
end
function View.new(context,title,subtitle)
 local self=setmetatable({context=context,buttons={},actions={},outlines={},connections={},order=0},View)
 local frame=Instance.new("Frame"); frame.Name=title; frame.AnchorPoint=Vector2.new(0,.5)
 frame.Position=UDim2.fromScale(.045,.5); frame.Size=UDim2.fromScale(.91,.9)
 frame.BackgroundColor3=Color3.fromRGB(15,25,29); frame.BackgroundTransparency=.08; frame.BorderSizePixel=0
 frame.Visible=false; frame.Parent=context.parent; self.frame=frame
 local limit=Instance.new("UISizeConstraint"); limit.MaxSize=Vector2.new(490,780); limit.Parent=frame
 local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,14); corner.Parent=frame
 local stroke=Instance.new("UIStroke"); stroke.Color=Color3.fromRGB(71,91,94); stroke.Transparency=.3; stroke.Parent=frame
 local accent=Instance.new("Frame"); accent.Name="Accent"; accent.BackgroundColor3=orange; accent.BorderSizePixel=0
 accent.Position=UDim2.fromOffset(24,22); accent.Size=UDim2.fromOffset(34,3); accent.Parent=frame
 local eyebrow=label(frame,"Eyebrow","BATTLEWORKS  /  COMMAND CENTER",10,muted)
 eyebrow.Position=UDim2.fromOffset(24,34); eyebrow.Size=UDim2.new(1,-48,0,22)
 local heading=label(frame,"Title",title,30); heading.Font=Enum.Font.GothamBold
 heading.Position=UDim2.fromOffset(24,62); heading.Size=UDim2.new(1,-48,0,44)
 local hint=label(frame,"Subtitle",subtitle,13,muted); hint.Position=UDim2.fromOffset(24,108); hint.Size=UDim2.new(1,-48,0,42)
 local scroll=Instance.new("ScrollingFrame"); scroll.Name="Content"; scroll.Position=UDim2.fromOffset(24,164)
 scroll.Size=UDim2.new(1,-48,1,-208); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
 scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
 scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=orange; scroll.Parent=frame; self.content=scroll
 local layout=Instance.new("UIListLayout"); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Padding=UDim.new(0,9); layout.Parent=scroll
 local footer=label(frame,"Footer","YOUR TANKS. YOUR CODE. YOUR BATTLEFIELD.",10,muted)
 footer.Position=UDim2.new(0,24,1,-32); footer.Size=UDim2.new(1,-48,0,20)
 return self
end
function View:button(name,text,action,primary)
 self.order+=1
 local button=Instance.new("TextButton"); button.Name=name; button.Text=text; button.LayoutOrder=self.order
 button.Size=UDim2.new(1,-4,0,48); button.Font=Enum.Font.GothamMedium; button.TextSize=16
 button.TextXAlignment=Enum.TextXAlignment.Left; button.BorderSizePixel=0; button.AutoButtonColor=false
 button.TextColor3=if primary then Color3.fromRGB(28,34,31) else ink
 button.BackgroundColor3=if primary then orange else Color3.fromRGB(32,47,52)
 button.Selectable=false; button.Parent=self.content
 local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,16); pad.Parent=button
 local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,7); corner.Parent=button
 local stroke=Instance.new("UIStroke"); stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke.Color=orange; stroke.Transparency=1; stroke.Parent=button
 self.outlines[button]=stroke
 table.insert(self.connections,button.MouseEnter:Connect(function() self.hovered=button;self:paintFocus() end))
 table.insert(self.connections,button.MouseLeave:Connect(function() if self.hovered==button then self.hovered=nil end;self:paintFocus() end))
 table.insert(self.connections,button.Activated:Connect(function() if self.frame.Visible then action() end end))
 table.insert(self.buttons,button); self.actions[button]=action
 return button
end
function View:separator()
 self.order+=1
 local holder=Instance.new("Frame"); holder.Name="Separator"; holder.LayoutOrder=self.order
 holder.Size=UDim2.new(1,-4,0,16); holder.BackgroundTransparency=1; holder.Parent=self.content
 local line=Instance.new("Frame"); line.BorderSizePixel=0; line.BackgroundColor3=Color3.fromRGB(74,91,94)
 line.Size=UDim2.new(1,0,0,1); line.Position=UDim2.fromScale(0,.5); line.Parent=holder
end
function View:paragraph(name,text)
 self.order+=1
 local item=label(self.content,name,text,15,muted); item.LayoutOrder=self.order
 item.Size=UDim2.new(1,-8,0,0); item.AutomaticSize=Enum.AutomaticSize.Y
 return item
end
function View:back() return self:button("MainMenu","Back to Main Menu",self.context.home) end
-- Do not write GuiService.SelectedObject or construct native NextSelection
-- cycles. The Windows Studio trace stops inside that engine selection path.
-- Menu navigation owns its index, outline and scroll position instead.
function View:paintFocus()
 local focused=self.focusIndex and self.buttons[self.focusIndex]
 for button,outline in self.outlines do
  outline.Transparency=if button==focused or button==self.hovered then 0 else 1
 end
end
function View:enter()
 self.frame.Visible=true;self.content.CanvasPosition=Vector2.zero
 self.focusIndex=nil;self.hovered=nil;self:paintFocus()
 if self.context.trace then self.context.trace("custom menu navigation ready; native auto-focus disabled") end
end
function View:exit()
 self.frame.Visible=false;self.focusIndex=nil;self.hovered=nil;self:paintFocus()
end
function View:moveFocus(delta)
 if #self.buttons==0 then return end
 if not self.focusIndex then self.focusIndex=if delta<0 then #self.buttons else 1
 else self.focusIndex=(self.focusIndex-1+delta)%#self.buttons+1 end
 self:paintFocus()
 local button=self.buttons[self.focusIndex]
 local top=button.AbsolutePosition.Y-self.content.AbsolutePosition.Y
 local bottom=top+button.AbsoluteSize.Y
 local viewport=self.content.AbsoluteSize.Y
 local position=self.content.CanvasPosition
 if viewport>0 then
  if top<0 then self.content.CanvasPosition=Vector2.new(position.X,math.max(0,position.Y+top))
  elseif bottom>viewport then self.content.CanvasPosition=Vector2.new(position.X,position.Y+bottom-viewport) end
 end
end
function View:activateSelected()
 local button=self.buttons[self.focusIndex or 1]
 local action=button and self.actions[button]
 if action then action() end
end
function View:destroy()
 for _,connection in self.connections do connection:Disconnect() end
 self.frame:Destroy()
end
return View

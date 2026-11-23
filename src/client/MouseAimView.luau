local Mouse=require(script.Parent.MouseAim)
local View={Shortcut="C"};View.__index=View
local function button(parent,name,text,position,size)
 local b=Instance.new("TextButton");b.Name=name;b.Text=text;b.Position=position;b.Size=size;b.BackgroundColor3=Color3.fromRGB(36,51,57);b.TextColor3=Color3.fromRGB(237,239,224);b.TextSize=14;b.Font=Enum.Font.GothamMedium;b.Parent=parent;return b
end
function View.new(gui,onMode,onModal)
 local self=setmetatable({selected="Mouse Points",onModal=onModal},View)
 local icon=button(gui,"MouseAimSelector","",UDim2.new(1,-250,0,4),UDim2.fromOffset(40,40));self.icon=icon
 -- Asset-free controller silhouette, readable without an uploaded image.
 local pad=Instance.new("Frame");pad.Position=UDim2.fromOffset(4,4);pad.Size=UDim2.fromOffset(32,19);pad.BackgroundColor3=Color3.fromRGB(188,208,205);pad.Parent=icon
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,7);corner.Parent=pad
 for i,text in {"+","••"}do local l=Instance.new("TextLabel");l.BackgroundTransparency=1;l.Size=UDim2.fromOffset(16,19);l.Position=UDim2.fromOffset((i-1)*16,0);l.Text=text;l.TextSize=16;l.TextColor3=Color3.fromRGB(30,44,48);l.Parent=pad end
 local shortcut=Instance.new("TextLabel");shortcut.Name="MouseAimShortcut";shortcut.BackgroundTransparency=1;shortcut.Position=UDim2.fromOffset(0,24);shortcut.Size=UDim2.fromOffset(40,14);shortcut.Text=View.Shortcut;shortcut.TextSize=12;shortcut.Font=Enum.Font.GothamMedium;shortcut.TextColor3=icon.TextColor3;shortcut.Parent=icon
 local hint=Instance.new("TextLabel");hint.Name="MouseAimHint";hint.BackgroundTransparency=1;hint.Position=UDim2.new(1,-275,0,46);hint.Size=UDim2.fromOffset(90,20);hint.TextSize=11;hint.TextColor3=Color3.fromRGB(210,225,220);hint.Parent=gui;self.hint=hint
 local panel=Instance.new("Frame");panel.Name="MouseAimOptions";panel.AnchorPoint=Vector2.new(1,0);panel.Position=UDim2.new(1,-8,0,90);panel.Size=UDim2.fromOffset(230,168);panel.BackgroundColor3=Color3.fromRGB(24,34,39);panel.Visible=false;panel.ZIndex=15;panel.Parent=gui;self.panel=panel
 self.buttons={}
 for i,mode in Mouse.Modes do
  local b=button(panel,mode,mode,UDim2.fromOffset(6,6+(i-1)*40),UDim2.new(1,-12,0,36));b.ZIndex=16;self.buttons[mode]=b
  b.Activated:Connect(function()onMode(mode);self:open(false)end)
 end
 local help=Instance.new("TextLabel");help.BackgroundTransparency=1;help.Size=UDim2.new(1,-12,0,36);help.Position=UDim2.fromOffset(6,128);help.Text="Right-drag to orbit or tilt\nAlt: use UI  •  Shift+C: recenter joystick";help.TextWrapped=true;help.TextSize=12;help.TextColor3=Color3.fromRGB(188,208,205);help.ZIndex=16;help.Parent=panel
 icon.Activated:Connect(function()self:open(not panel.Visible)end)
 local ring=Instance.new("Frame");ring.Name="MouseJoystickDeadZone";ring.AnchorPoint=Vector2.new(.5,.5);ring.Size=UDim2.fromOffset(Mouse.DeadZone*2,Mouse.DeadZone*2);ring.BackgroundColor3=Color3.fromRGB(180,215,218);ring.BackgroundTransparency=.93;ring.Visible=false;ring.Parent=gui;self.ring=ring
 local round=Instance.new("UICorner");round.CornerRadius=UDim.new(.5,0);round.Parent=ring
 local stroke=Instance.new("UIStroke");stroke.Color=Color3.fromRGB(180,215,218);stroke.Transparency=.55;stroke.Thickness=1;stroke.Parent=ring
 local dot=Instance.new("Frame");dot.Name="MouseJoystickPosition";dot.AnchorPoint=Vector2.new(.5,.5);dot.Size=UDim2.fromOffset(7,7);dot.BackgroundColor3=Color3.fromRGB(220,234,224);dot.Visible=false;dot.Parent=gui;self.dot=dot
 local dotRound=Instance.new("UICorner");dotRound.CornerRadius=UDim.new(.5,0);dotRound.Parent=dot
 self:select(self.selected)
 return self
end
function View:open(open)self.panel.Visible=open;self.onModal(open)end
function View:select(mode)
 self.selected=mode;self.hint.Text=if mode=="Mouse Direct"then "Esc: free cursor"elseif mode=="Mouse Joystick"then "Shift+C: center"else "RMB: orbit";self.icon:SetAttribute("MouseAimMode",mode)
 for name,b in self.buttons do b.Text=(if name==mode then "● "else "○ ")..name end
end
function View:setVisible(visible)
 self.icon.Visible=visible;self.hint.Visible=visible
 if not visible then self:open(false);self.ring.Visible=false;self.dot.Visible=false end
end
function View:update(provider,enabled)
 local visible=enabled and provider.mouseMode=="Mouse Joystick"and provider.center~=nil and not provider.uiBlocked and not provider.freeCursor and not provider.orbiting
 self.ring.Visible=visible;self.dot.Visible=visible
 if visible then
  self.ring.Position=UDim2.fromOffset(provider.center.X,provider.center.Y)
  local delta=(provider.pointer or provider.center)-provider.center
  local point=provider.center+(if delta.Magnitude>Mouse.Radius then delta.Unit*Mouse.Radius else delta)
  self.dot.Position=UDim2.fromOffset(point.X,point.Y)
 end
end
return View

-- Native TextChannelWindow + native-managed input. Never reads player text,
-- calls SendAsync, creates chat remotes, or grants channel membership.
local Chat={};Chat.__index=Chat
local State=require(script.Parent.PlaygroundChatState)
local function label(parent,name,text,size)
 local p=Instance.new("TextLabel");p.Name=name;p.Text=text;p.Size=size;p.BackgroundTransparency=1;p.TextColor3=Color3.fromRGB(225,235,227);p.TextSize=14;p.TextWrapped=true;p.Font=Enum.Font.GothamMedium;p.Parent=parent;return p
end
function Chat.new(playerGui,input,mode)
 if mode~="BattleRoyale"then return nil end
 local self=setmetatable({input=input,connections={},saved={},active=false,destroyed=false,allowed=false},Chat)
 local players=game:GetService("Players");self.player=players.LocalPlayer
 local service=game:GetService("TextChatService");self.service=service
 self.state=State.new(self.player.UserId)
 local gui=Instance.new("ScreenGui");gui.Name="PlaygroundChat";gui.ResetOnSpawn=false;gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.DisplayOrder=5;gui.Enabled=false;gui.Parent=playerGui;self.gui=gui
 local root=Instance.new("Frame");root.Name="ChatDock";root.AnchorPoint=Vector2.new(0,1);root.BackgroundTransparency=1;root.Parent=gui;self.root=root
 local toggle=Instance.new("TextButton");toggle.Name="ChatToggle";toggle.Text="Chat  •  Enter";toggle.Size=UDim2.new(1,0,0,44);toggle.BackgroundColor3=Color3.fromRGB(32,47,52);toggle.TextColor3=Color3.fromRGB(237,239,224);toggle.Font=Enum.Font.GothamMedium;toggle.TextSize=14;toggle.Parent=root;self.toggle=toggle
 local panel=Instance.new("Frame");panel.Name="ChatPanel";panel.Position=UDim2.fromOffset(0,46);panel.Size=UDim2.new(1,0,1,-46);panel.BackgroundColor3=Color3.fromRGB(24,34,39);panel.BackgroundTransparency=.12;panel.Visible=false;panel.ClipsDescendants=true;panel.Parent=root;self.panel=panel
 local ok,window=pcall(Instance.new,"TextChannelWindow")
 if ok then
  window.Name="NativeChatHistory";window.Size=UDim2.new(1,-12,1,-76);window.Position=UDim2.fromOffset(6,2);window.BackgroundTransparency=1;window.Parent=panel;self.window=window
 end
 local box=Instance.new("TextBox");box.Name="ChatInput";box.Text="";box.PlaceholderText="Connecting to Roblox chat…";box.ClearTextOnFocus=false;box.MultiLine=false;box.TextEditable=false;box.TextSize=16;box.Font=Enum.Font.Gotham;box.TextColor3=Color3.fromRGB(237,239,224);box.BackgroundColor3=Color3.fromRGB(40,55,61);box.Size=UDim2.new(1,-12,0,44);box.Position=UDim2.new(0,6,1,-70);box.Parent=panel;self.box=box
 local status=label(panel,"ChatStatus","Connecting to Roblox chat…",UDim2.new(1,-12,0,24));status.Position=UDim2.new(0,6,1,-24);status.TextSize=12;self.status=status
 self:connect(toggle.Activated,function()self:setExpanded(not self.state.expanded)end)
 self:connect(box.Focused,function()
  if not self.active or not self.state.expanded then return end
  self.fieldFocused=true;self:focusChanged()
 end)
 self:connect(box.FocusLost,function()self.fieldFocused=false;self:focusChanged()end)
 self:connect(gui:GetPropertyChangedSignal("AbsoluteSize"),function()self:layout();self:focusChanged()end)
 self:connect(input.button.Activated,function()self:layout();self:focusChanged()end)
 self:connect(game:GetService("UserInputService"):GetPropertyChangedSignal("PreferredInput"),function()self:layout();self:focusChanged()end)
 self:layout()
 -- No keyboard listener here: native input receives Return/Escape. The shared
 -- input abstraction opens/closes our wrapper before Roblox handles those keys.
 self.unbind=input:bindTextEntry("PlaygroundChat",{
  enabled=function()return self.active and self.ready and self.allowed end,
  focused=function()return self.fieldFocused or (self.bar and self.bar.IsFocused)end,
  open=function()self:setExpanded(true)end,
  cancel=function()self:setExpanded(false)end,
 })
 self:connect(players.PlayerRemoving,function(player)if player==self.player then self:destroy()end end)
 if service then
  self:connect(service.ChildAdded,function()self:discover()end)
  self:connect(service.MessageReceived,function(message)
   if self.destroyed or not self.channel then return end
   if self.state:receive(message,self.channel)then self:refresh()end
   if message.TextChannel==self.channel and message.TextSource and message.TextSource.UserId==self.player.UserId then
    if message.Status==Enum.TextChatMessageStatus.Success then self.status.Text="Roblox chat • filtered and moderated"
    elseif message.Status~=Enum.TextChatMessageStatus.Sending then self.status.Text="Roblox could not deliver this message. Check chat permissions or try later."end
   end
  end)
  self:discover()
 else self.reason="Roblox chat service is unavailable.";self:refresh()end
 return self
end
function Chat:connect(signal,callback)
 if signal then table.insert(self.connections,signal:Connect(callback))end
end
function Chat:layout()
 local size=self.gui.AbsoluteSize
 local touch=self.input.mode=="Touch"or game:GetService("UserInputService").PreferredInput==Enum.PreferredInput.Touch
 -- Same dimensions as the existing touch layout, without changing its controls.
 local stick=if touch then math.min(170,size.X*.23,size.Y*.42)else 0
 self.compact=touch and size.Y<480
 local modal=self.compact and self.state.expanded
 local bottom=if touch and not modal then stick+28 else 12
 local width=math.max(120,math.min(310,size.X*.42))
 local height=if modal then math.max(80,math.min(260,size.Y-122))else math.max(130,math.min(260,size.Y-bottom-105))
 local tiny=modal and height<150
 self.panel.Position=UDim2.fromOffset(0,if tiny then 36 else 46)
 self.panel.Size=UDim2.new(1,0,1,if tiny then -36 else -46)
 self.toggle.Size=UDim2.new(1,0,0,if tiny then 34 else 44)
 self.box.Position=if tiny then UDim2.fromOffset(6,0)else UDim2.new(0,6,1,-70)
 self.status.Visible=not tiny
 self.root.Position=UDim2.new(0,12,1,-bottom)
 self.root.Size=UDim2.fromOffset(width,if self.state.expanded then height else 44)
 if self.window then self.window.Visible=height>=160 end
end
function Chat:remember(object,key,value)
 self.saved[object]=self.saved[object]or {}
 if self.saved[object][key]==nil then self.saved[object][key]={object[key]}end
 object[key]=value
end
function Chat:discover()
 if self.destroyed or not self.service then return end
 local service=self.service
 if service.ChatVersion~=Enum.ChatVersion.TextChatService then self.reason="This place requires Roblox TextChatService chat.";self:refresh();return end
 local bar=service:FindFirstChildOfClass("ChatInputBarConfiguration")
 local history=service:FindFirstChildOfClass("ChatWindowConfiguration")
 local channels=service:FindFirstChild("TextChannels")
 if channels and self.channels~=channels then self.channels=channels;self:connect(channels.ChildAdded,function()self:discover()end)end
 local channel=channels and channels:FindFirstChild("RBXGeneral")
 if not bar or not history or not channel then return end
 if not self.window then
  self.reason="Update Roblox to use Playground chat. Native chat remains available.";self:refresh();return
 end
 if not self.ready then
  self.bar=bar;self.history=history;self.channel=channel;self.window.Target=channel
  self:remember(history,"Enabled",false)
  self:remember(bar,"Enabled",false)
  self:remember(bar,"TargetTextChannel",channel)
  self:remember(bar,"KeyboardKeyCode",Enum.KeyCode.Return)
  self:remember(bar,"TextBox",self.box)
  self.ready=true
  self:connect(bar:GetPropertyChangedSignal("IsFocused"),function()self:focusChanged()end)
  self:connect(channel.ChildAdded,function()self:checkPermission()end)
  self:connect(channel.ChildRemoved,function()self:checkPermission()end)
 end
 self:checkPermission()
end
function Chat:checkPermission()
 self.permissionRevision=(self.permissionRevision or 0)+1;local revision=self.permissionRevision
 if not self.ready then return end
 -- Native TextSource is Roblox's live channel eligibility, not a game flag.
 local source
 for _,child in self.channel:GetChildren()do if child:IsA("TextSource")and child.UserId==self.player.UserId then source=child;break end end
 if self.source~=source then
  if self.sourceConnection then self.sourceConnection:Disconnect();self.sourceConnection=nil end
  self.source=source
  if source then self.sourceConnection=source:GetPropertyChangedSignal("CanSend"):Connect(function()self:checkPermission()end)end
 end
 self.allowed=false;self:refresh()
 task.spawn(function()
  local ok,allowed=pcall(self.service.CanUserChatAsync,self.service,self.player.UserId)
  if self.destroyed or revision~=self.permissionRevision then return end
  self.allowed=ok and allowed==true and source~=nil and source.CanSend==true
  self.reason=if not ok then "Roblox chat permissions could not be checked. Reopen chat to retry."elseif not allowed then "Chat is unavailable for this Roblox account."elseif not source or not source.CanSend then "Global chat is not available yet."else nil
  self:refresh()
 end)
end
function Chat:focusChanged()
 if self.destroyed then return end
 local focused=self.active and self.state.expanded and (self.fieldFocused or (self.bar and self.bar.IsFocused==true)or self.compact)
 self.input:setTextEntryFocus("PlaygroundChat",focused)
end
function Chat:refresh()
 if self.destroyed then return end
 self.gui.Enabled=self.active
 self.panel.Visible=self.state.expanded
 self.toggle.Text=(if self.state.expanded then "Chat  ▾"else "Chat  ▸")..(if self.state.unread>0 then "  ("..self.state.unread..")"else "  •  Enter")
 self.box.TextEditable=self.active and self.state.expanded and self.ready==true and self.allowed
 if self.bar then self.bar.Enabled=self.active and self.state.expanded and self.allowed end
 self.box.PlaceholderText=if self.allowed then "Enter a message…"else (self.reason or "Connecting to Roblox chat…")
 self.status.Text=self.reason or (if self.allowed then "Roblox chat • filtered and moderated"else "Connecting to Roblox chat…")
 self:layout();self:focusChanged()
end
function Chat:setExpanded(expanded)
 if expanded and self.ready and not self.allowed then self:checkPermission()end
 self.state:setExpanded(expanded)
 -- Roblox owns focus for the registered TextBox. Refresh hides and disables the input bar.
 if not self.state.expanded then self.fieldFocused=false end
 self:refresh()
end
function Chat:setActive(active)
 self.active=active==true;self.state:setActive(self.active)
 if not self.active then self:setExpanded(false)else self:refresh()end
end
function Chat:destroy()
 if self.destroyed then return end
 self.active=false;self.input:setTextEntryFocus("PlaygroundChat",false)
 self.destroyed=true
 if self.unbind then self.unbind()end
 for _,connection in self.connections do connection:Disconnect()end
 if self.sourceConnection then self.sourceConnection:Disconnect()end
 for object,properties in self.saved do for key,value in properties do object[key]=value[1]end end
 self.gui:Destroy()
end
return Chat

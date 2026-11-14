-- Private saved-world UI. All network waits are cancellable from this screen.
local Library={};Library.__index=Library
local function make(class,parent,props)
 local node=Instance.new(class);for k,v in props do node[k]=v end;node.Parent=parent;return node
end
local function button(parent,text,x,y,width)
 return make("TextButton",parent,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,32),BackgroundColor3=Color3.fromRGB(43,61,66),TextColor3=Color3.fromRGB(235,241,230),TextSize=14,Font=Enum.Font.GothamMedium,Selectable=false,BorderSizePixel=0})
end
function Library.new(parent,request,onLoad,onPlay)
 local self=setmetatable({request=request,onLoad=onLoad,onPlay=onPlay,revisions={},epoch=0},Library)
 self.frame=make("Frame",parent,{Name="MyWorlds",Position=UDim2.fromScale(.1,.12),Size=UDim2.fromScale(.8,.76),BackgroundColor3=Color3.fromRGB(17,28,33),Visible=false,Active=true,ZIndex=20})
 local title=make("TextLabel",self.frame,{Text="MY WORLDS  /  private saves",Position=UDim2.fromOffset(20,12),Size=UDim2.new(1,-40,0,32),BackgroundTransparency=1,TextColor3=Color3.fromRGB(244,178,78),TextSize=20,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})
 local function field(name,y)
  return make("TextBox",self.frame,{Name=name,PlaceholderText=name,Text="",ClearTextOnFocus=false,Position=UDim2.fromOffset(20,y),Size=UDim2.new(1,-40,0,32),TextColor3=Color3.fromRGB(235,241,230),BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Gotham,TextSize=14})
 end
 self.name=field("World name",56);self.id=field("World ID (change for a new save)",96)
 self.save=button(self.frame,"Save",20,140,90)
 self.play=button(self.frame,"Save & Play",120,140,150);self.play.BackgroundColor3=Color3.fromRGB(121,89,37)
 self.refresh=button(self.frame,"Refresh saves",280,140,140)
 self.status=make("TextLabel",self.frame,{Text="",Position=UDim2.fromOffset(20,180),Size=UDim2.new(1,-40,0,60),BackgroundTransparency=1,TextColor3=Color3.fromRGB(235,241,230),TextSize=14,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham})
 self.list=make("ScrollingFrame",self.frame,{Position=UDim2.fromOffset(20,248),Size=UDim2.new(1,-40,1,-300),BackgroundTransparency=1,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=5,BorderSizePixel=0})
 make("UIListLayout",self.list,{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder})
 self.close=button(self.frame,"Back to editing",20,0,160);self.close.Position=UDim2.new(0,20,1,-42)
 self.close.Activated:Connect(function() self:hide() end)
 self.save.Activated:Connect(function() self:saveWorld(false) end)
 self.play.Activated:Connect(function() self:saveWorld(true) end)
 self.refresh.Activated:Connect(function() self:run(function(epoch) self:fetch(epoch) end) end)
 return self
end
function Library:current(epoch) return self.frame.Visible and self.epoch==epoch end
function Library:call(action,payload)
 assert(self.request,"Saved worlds are unavailable in this build")
 local response=self.request(action,payload)
 assert(type(response)=="table" and response.ok,response and response.message or "World service did not reply")
 return response
end
function Library:run(fn)
 if self.busy or not self.frame.Visible then return end
 self.busy=true;local epoch=self.epoch
 self.status.Text="Working…"
 task.spawn(function()
  local ok,err=pcall(fn,epoch)
  if not self:current(epoch) then return end
  self.busy=false
  if not ok then self.status.Text=tostring(err):gsub("^.-:%d+:%s*","") end
 end)
end
function Library:fetch(epoch)
 local result=self:call("List")
 if not self:current(epoch) then return end
 for _,node in self.list:GetChildren() do if node:IsA("GuiObject") then node:Destroy() end end
 for index,world in result.worlds do
  local row=button(self.list,"Open  •  "..world.name.."  ["..world.id.."]",0,0,200)
  row.Size=UDim2.new(1,-8,0,36);row.LayoutOrder=index
  row.Activated:Connect(function()
   self:run(function(token)
    local saved=self:call("Load",world.id)
    if not self:current(token) then return end
    self.revisions[world.id]=saved.revision
    self.document=self.onLoad(saved.document)
    self.name.Text=saved.document.name;self.id.Text=saved.document.id
    self.status.Text="Opened revision "..saved.revision..". Return to editing, or Save & Play."
   end)
  end)
 end
 self.status.Text=(if result.temporary then "STUDIO: saves last only until you stop Play. " else "Saved privately to your Roblox account. ").."Open a save before updating it. Opening replaces your draft. Change World ID for a separate save."
end
function Library:open(document)
 self.epoch+=1;self.busy=false;self.document=document
 self.name.Text=document.name;self.id.Text=document.id;self.frame.Visible=true
 self:run(function(epoch) self:fetch(epoch) end)
end
function Library:saveWorld(play)
 self:run(function(epoch)
  -- Serialize a copy before yielding; edits made later cannot alter this save.
  local copy=require(game.ReplicatedStorage.Shared.WorldEditorState).copy(self.document)
  copy.id=self.id.Text;copy.name=self.name.Text
  local saved=self:call("Save",{document=copy,revision=self.revisions[copy.id] or 0})
  if not self:current(epoch) then return end
  self.revisions[copy.id]=saved.revision
  self.document.id=copy.id;self.document.name=copy.name
  self.status.Text=(if saved.temporary then "STUDIO SESSION ONLY • " else "Saved to your account • ").."revision "..saved.revision
  if play then
   self.status.Text..=" • launching your world…"
   local result=self:call("Play",{id=copy.id,revision=saved.revision})
   if not self:current(epoch) then return end
   if result.launch then self:hide();self.onPlay()
   elseif result.teleporting then self.status.Text="Saved. Traveling to your private battlefield… If travel fails, your draft and save remain available here." end
  end
 end)
end
function Library:hide() self.frame.Visible=false;self.epoch+=1;self.busy=false end
function Library:destroy() self:hide();self.frame:Destroy() end
return Library

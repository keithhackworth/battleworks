-- Editor UI only. Picking, transactions and world geometry live elsewhere.
local Placement=require(game.ReplicatedStorage.Shared.ModelPlacement)
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local View={};View.__index=View
local ink=Color3.fromRGB(235,241,230)
local accent=Color3.fromRGB(244,178,78)
local function make(class,parent,props)
 local p=Instance.new(class);for key,value in props do p[key]=value end;p.Parent=parent;return p
end
local function text(parent,name,value,height)
 return make("TextLabel",parent,{Name=name,Text=value,Size=UDim2.new(1,-8,0,height or 24),BackgroundTransparency=1,TextColor3=ink,TextSize=13,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})
end
local function button(parent,name,value,size,position)
 return make("TextButton",parent,{Name=name,Text=value,Size=size or UDim2.new(1,0,0,32),Position=position or UDim2.fromOffset(0,0),TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),TextSize=13,Font=Enum.Font.GothamMedium,Selectable=true,BorderSizePixel=0,AutoButtonColor=true})
end
local function scrolling(parent,name,size,position)
 local p=make("ScrollingFrame",parent,{Name=name,Size=size,Position=position,BackgroundColor3=Color3.fromRGB(23,35,39),BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=5,ScrollBarImageColor3=accent,Active=true})
 return p
end
local function rectContains(p,point)
 local at,size=p.AbsolutePosition,p.AbsoluteSize
 return point.X>=at.X and point.X<=at.X+size.X and point.Y>=at.Y and point.Y<=at.Y+size.Y
end
function View.new(context)
 local self=setmetatable({connections={},paletteConnections={},thumbnails={},fields={},callbacks={},buttons={}},View)
 local frame=make("Frame",context.parent,{Name="World Editor",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(17,28,33),BorderSizePixel=0,Visible=false});self.frame=frame
 local viewport=make("ViewportFrame",frame,{Name="EditorViewport",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(37,58,66),BorderSizePixel=0,Ambient=Color3.fromRGB(170,180,190),LightColor=Color3.fromRGB(255,239,210),LightDirection=Vector3.new(-1,-1,-1),Active=false});self.viewport=viewport
 local toolbar=make("Frame",frame,{Name="Toolbar",Size=UDim2.new(1,0,0,54),BackgroundColor3=Color3.fromRGB(19,30,35),BorderSizePixel=0,Active=true});self.toolbar=toolbar
 self.back=button(toolbar,"MainMenu","← Main Menu",UDim2.fromOffset(120,38),UDim2.fromOffset(8,8));self.buttons={self.back}
 self.back.Activated:Connect(context.home)
 local title=text(toolbar,"EditorTitle","WORLD BUILDER",32);title.Position=UDim2.fromOffset(144,12);title.Size=UDim2.fromOffset(180,32);title.TextColor3=accent
 self.tools={}
 for index,name in {"Move","Rotate","Scale"} do
  self.tools[name]=button(toolbar,name,name,UDim2.fromOffset(68,32),UDim2.fromOffset(328+(index-1)*72,12))
 end
 self.undo=button(toolbar,"Undo","Undo",UDim2.fromOffset(60,32),UDim2.fromOffset(624,12))
 self.redo=button(toolbar,"Redo","Redo",UDim2.fromOffset(60,32),UDim2.fromOffset(688,12))
 self.export=button(toolbar,"Export","Export JSON",UDim2.fromOffset(114,32),UDim2.new(1,-126,0,12));self.export.BackgroundColor3=Color3.fromRGB(121,89,37)
 local pane=make("Frame",frame,{Name="AssetPalette",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,66),Size=UDim2.new(0,310,.48,-32),BackgroundColor3=Color3.fromRGB(23,35,39),BorderSizePixel=0,Active=true});self.palette=pane
 local label=text(pane,"PaletteTitle","ASSET LIBRARY  •  drag into the world",28);label.Position=UDim2.fromOffset(12,6)
 self.up=button(pane,"ParentDirectory","↑",UDim2.fromOffset(32,28),UDim2.fromOffset(10,38))
 self.breadcrumb=text(pane,"AssetDirectory","Assets /",28);self.breadcrumb.Position=UDim2.fromOffset(50,38);self.breadcrumb.Size=UDim2.new(1,-60,0,28)
 self.search=make("TextBox",pane,{Name="SearchAssets",Position=UDim2.fromOffset(10,72),Size=UDim2.new(1,-20,0,30),Text="",PlaceholderText="Search asset names or full paths…",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Gotham,TextSize=13})
 self.assetScroll=scrolling(pane,"AssetTiles",UDim2.new(1,-20,1,-142),UDim2.fromOffset(10,108))
 local grid=make("UIGridLayout",self.assetScroll,{CellSize=UDim2.new(.5,-5,0,116),CellPadding=UDim2.fromOffset(6,6),SortOrder=Enum.SortOrder.LayoutOrder})
 self.page=text(pane,"Page","",24);self.page.Position=UDim2.new(0,10,1,-28);self.page.Size=UDim2.new(1,-90,0,24)
 self.nextPage=button(pane,"NextAssets","Next →",UDim2.fromOffset(72,24),UDim2.new(1,-82,1,-28))
 self.properties=scrolling(frame,"ObjectProperties",UDim2.new(0,310,.52,-106),UDim2.new(1,-322,.48,44))
 make("UIPadding",self.properties,{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12),PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,10)})
 make("UIListLayout",self.properties,{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
 local order=0
 local function row(p) order+=1;p.LayoutOrder=order;return p end
 row(text(self.properties,"PropertiesTitle","BATTLEWORKS PROPERTIES",24))
 self.selected=row(text(self.properties,"SelectedObject","Select a placed object to inspect it.",46));self.selected.Size=UDim2.new(1,-8,0,0);self.selected.AutomaticSize=Enum.AutomaticSize.Y
 for _,spec in {{"x","Position X"},{"y","Height Y (lowest point)"},{"z","Position Z"},{"pitch","Tilt X / pitch (degrees)"},{"yaw","Yaw Y (degrees)"},{"roll","Tilt Z / roll (degrees)"},{"scale","Uniform scale"},{"hp","Durability / HP"}} do
  row(text(self.properties,spec[1].."Label",spec[2],20))
  self.fields[spec[1]]=row(make("TextBox",self.properties,{Name=spec[1],Size=UDim2.new(1,-8,0,28),Text="",PlaceholderText="—",ClearTextOnFocus=false,TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),TextSize=14,Font=Enum.Font.Code}))
 end
 self.solid=row(button(self.properties,"Collision","Collision: —"));self.destructible=row(button(self.properties,"Destructible","Destructible: —"))
 self.influences=row(text(self.properties,"Influences","Fixed objects • height / tilt • uniform scale",100))
 self.duplicate=row(button(self.properties,"Duplicate","Duplicate  •  Ctrl+D"));self.delete=row(button(self.properties,"Delete","Delete  •  Delete"))
 local controls=make("Frame",frame,{Name="EditorOptions",Position=UDim2.fromOffset(12,66),Size=UDim2.fromOffset(208,76),BackgroundColor3=Color3.fromRGB(23,35,39),Active=true,BorderSizePixel=0});self.options=controls
 self.snap=button(controls,"GridSnap","Grid snap: OFF",UDim2.fromOffset(132,28),UDim2.fromOffset(8,8))
 self.grid=make("TextBox",controls,{Name="GridSize",Text="1",ClearTextOnFocus=false,Size=UDim2.fromOffset(48,28),Position=UDim2.fromOffset(150,8),BackgroundColor3=Color3.fromRGB(43,61,66),TextColor3=ink,TextSize=14,Font=Enum.Font.Code})
 self.frameWorld=button(controls,"FrameWorld","Frame world  •  F",UDim2.fromOffset(190,26),UDim2.fromOffset(8,42))
 self.worlds=button(frame,"SavedWorlds","My Worlds / Save & Play",UDim2.fromOffset(208,36),UDim2.fromOffset(12,150));self.worlds.BackgroundColor3=Color3.fromRGB(121,89,37)
 self.rotationAxes={}
 local rotations=make("Frame",frame,{Name="RotationAxes",Position=UDim2.fromOffset(12,194),Size=UDim2.fromOffset(208,64),BackgroundColor3=Color3.fromRGB(23,35,39),BorderSizePixel=0,Active=true});self.rotationPanel=rotations
 local axisTitle=text(rotations,"AxisTitle","ROTATION AXIS",24);axisTitle.Position=UDim2.fromOffset(8,2)
 for index,axis in {"Pitch","Yaw","Roll"} do
  self.rotationAxes[axis]=button(rotations,axis,({Pitch="Tilt X",Yaw="Yaw Y",Roll="Tilt Z"})[axis],UDim2.fromOffset(60,28),UDim2.fromOffset(8+(index-1)*65,28))
 end
 self.status=text(frame,"EditorStatus","Loading native asset library…",30);self.status.Position=UDim2.new(0,12,1,-72);self.status.Size=UDim2.new(1,-344,0,30);self.status.BackgroundTransparency=.1;self.status.BackgroundColor3=Color3.fromRGB(19,30,35)
 self.hint=text(frame,"EditorHints","Click / drag to place • Esc cancels • Right drag orbits • WASD pans • Wheel zooms",30);self.hint.Position=UDim2.new(0,12,1,-36);self.hint.Size=UDim2.new(1,-344,0,30)
 local overlay=make("Frame",frame,{Name="ExportOverlay",Position=UDim2.fromScale(.08,.12),Size=UDim2.fromScale(.84,.76),BackgroundColor3=Color3.fromRGB(17,28,33),Visible=false,Active=true,ZIndex=10});self.overlay=overlay
 local exportTitle=text(overlay,"ExportTitle","EXPORT WORLD  /  authoring schema v2",32);exportTitle.Position=UDim2.fromOffset(16,8);exportTitle.ZIndex=11
 self.name=make("TextBox",overlay,{Name="WorldName",Text="My BattleWorks World",PlaceholderText="World name",ClearTextOnFocus=false,Position=UDim2.fromOffset(16,48),Size=UDim2.new(.5,-24,0,30),TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Gotham,TextSize=14,ZIndex=11})
 self.worldId=make("TextBox",overlay,{Name="WorldId",Text="ingame_world",PlaceholderText="World ID",ClearTextOnFocus=false,Position=UDim2.new(.5,8,0,48),Size=UDim2.new(.5,-24,0,30),TextColor3=ink,BackgroundColor3=Color3.fromRGB(43,61,66),Font=Enum.Font.Code,TextSize=14,ZIndex=11})
 self.json=make("TextBox",overlay,{Name="ExportJSON",Position=UDim2.fromOffset(16,124),Size=UDim2.new(1,-32,1,-172),Text="",ClearTextOnFocus=false,MultiLine=true,TextEditable=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextColor3=ink,BackgroundColor3=Color3.fromRGB(27,40,46),Font=Enum.Font.Code,TextSize=12,ZIndex=11})
 self.generate=button(overlay,"GenerateJSON","Generate / Select JSON",UDim2.fromOffset(208,30),UDim2.fromOffset(16,86));self.generate.ZIndex=11
 self.closeExport=button(overlay,"CloseExport","Close",UDim2.fromOffset(72,30),UDim2.new(1,-88,1,-38));self.closeExport.ZIndex=11
 self.closeExport.Activated:Connect(function() overlay.Visible=false end)
 return self
end
function View:on(event,callback) table.insert(self.connections,event:Connect(callback)) end
function View:message(message) self.status.Text=tostring(message):gsub("^.-:%d+:%s*","") end
function View:isModal() return self.overlay.Visible or (self.library and self.library.frame.Visible) end
function View:isScene(point)
 return self.frame.Visible and not self:isModal() and not rectContains(self.worlds,point) and not rectContains(self.rotationPanel,point) and rectContains(self.viewport,point) and not rectContains(self.toolbar,point) and not rectContains(self.palette,point) and not rectContains(self.properties,point) and not rectContains(self.options,point) and not rectContains(self.status,point) and not rectContains(self.hint,point)
end
function View:thumbnail(parent,item,assets)
 local templates=assets and assets:FindFirstChild("Templates")
 if not templates or not item.available then return end
 local viewport=make("ViewportFrame",parent,{Name="AssetPreview",Position=UDim2.fromOffset(4,4),Size=UDim2.new(1,-8,0,78),BackgroundColor3=Color3.fromRGB(50,68,72),BorderSizePixel=0,Ambient=Color3.fromRGB(190,190,190),LightColor=Color3.fromRGB(255,235,210),Active=false})
 local world=Instance.new("Folder");world.Parent=viewport
 local model=Placement.place(templates,{id="thumbnail",template=item.model,position=Vector3.zero,rotation=Vector3.zero,scale=1},nil,world)
 if model then
  local box,size=model:GetBoundingBox();local radius=math.max(size.X,size.Y,size.Z,1)
  local camera=Instance.new("Camera");camera.FieldOfView=38;camera.CFrame=CFrame.lookAt(box.Position+Vector3.new(radius*.9,radius*.55,radius),box.Position);camera.Parent=viewport;viewport.CurrentCamera=camera
 end
 table.insert(self.thumbnails,viewport)
end
function View:paletteEntries(directories,items,prefix,page,assets,onFolder,onAsset)
 for _,connection in self.paletteConnections do connection:Disconnect() end;self.paletteConnections={}
 for _,child in self.assetScroll:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
 self.thumbnails={};self.breadcrumb.Text="Assets / "..prefix
 local entries={};for _,folder in directories do table.insert(entries,{folder=folder}) end;for _,item in items do table.insert(entries,{item=item}) end
 local pages=math.max(1,math.ceil(#entries/24));page=math.clamp(page,1,pages)
 for index=(page-1)*24+1,math.min(#entries,page*24) do
  local entry=entries[index];local tile=button(self.assetScroll,entry.folder or entry.item.model,"");tile.LayoutOrder=index
  if entry.folder then
   local label=text(tile,"Folder","▸  "..entry.folder.." /",90);label.TextSize=17;label.TextColor3=accent
   table.insert(self.paletteConnections,tile.Activated:Connect(function() onFolder(entry.folder) end))
  else
   local item=entry.item;self:thumbnail(tile,item,assets)
   local name=text(tile,"AssetName",(if item.available then item.name.."\n"..item.model else "[Missing] "..item.model),30);name.Position=UDim2.fromOffset(5,83);name.Size=UDim2.new(1,-10,0,30);name.TextSize=11
   if not item.available then tile.BackgroundColor3=Color3.fromRGB(64,45,43) end
   if tile.MouseButton1Down then
    table.insert(self.paletteConnections,tile.MouseButton1Down:Connect(function() onAsset(item) end))
   else
    table.insert(self.paletteConnections,tile.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then onAsset(item) end end))
   end
  end
 end
 self.page.Text=string.format("%d assets / folders • %d/%d",#entries,page,pages)
 return page,pages
end
function View:selection(entry,item)
 self.selected.Text=if entry then entry.id.."\n"..entry.asset else "Select a placed object to inspect it."
 local values=if entry then {x=entry.position[1],y=entry.position[2],z=entry.position[3],pitch=entry.rotation[1],yaw=entry.rotation[2],roll=entry.rotation[3],scale=entry.scale,hp=entry.hp} else {}
 for key,field in self.fields do field.Text=if values[key] then string.format("%.5g",values[key]) else "" end
 self.solid.Text="Collision: "..(if entry then (if entry.solid then "SOLID" else "NONE") else "—")
 self.destructible.Text="Destructible: "..(if entry then (if entry.destructible then "YES" else "NO") else "—")
 self.influences.Text=if entry then "physical.movable = false\n"..(if item.zone then item.zone.." zone: "..(if item.zone=="Water" then "90%" else "75%").." speed\n" else "")..(if item.collider then string.format("Collider W %.3g / D %.3g / H %.3g",item.collider.widthFraction,item.collider.depthFraction,item.collider.heightFraction) else "No registered collider; visual only") else "Fixed objects • height / tilt • uniform scale"
end
function View:destroy()
 for _,connection in self.connections do connection:Disconnect() end
 for _,connection in self.paletteConnections do connection:Disconnect() end
 self.frame:Destroy()
end
return View

-- Local Studio plugin. Not included in the BattleWorks runtime place.
if not plugin then return end
local Http=game:GetService("HttpService")
local Run=game:GetService("RunService")
local Selection=game:GetService("Selection")
local UIS=game:GetService("UserInputService")
local Storage=game:GetService("ServerStorage")
local Studio=game:GetService("StudioService")
local CoreGui=game:GetService("CoreGui")
-- Local plugins load in every open place, including blank/edit DataModels.
-- Check all game dependencies before requiring modules that access Shared.
local shared=game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local server=game:GetService("ServerScriptService"):FindFirstChild("Server")
if not shared or not shared:FindFirstChild("AssetPaths") or not shared:FindFirstChild("WorldEditorState") or not shared:FindFirstChild("ModelPlacement") or not server or not server:FindFirstChild("StudioAssetPlacement") then
 warn("BattleWorks legacy World Builder: open a synced BattleWorks place, then reload this plugin. The in-game World Editor does not require the plugin.")
 return
end
local State=require(script.EditorState)
local Preview=require(script.Preview)
local preview=Preview.new(require(server.StudioAssetPlacement),Storage)
local toolbar=plugin:CreateToolbar("BattleWorks")
local toggle=toolbar:CreateButton("WorldBuilder","Create and edit BattleWorks worlds","","World Builder")
local info=DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left,false,false,430,850,350,450)
local widget=plugin:CreateDockWidgetPluginGuiAsync("BattleWorksWorldBuilder_v1",info); widget.Title="BattleWorks World Builder"
local mouse=plugin:GetMouse()
local session,items,byType,editor,placing,gesture
local busy=false; local mode="Move"; local suppressSelection=false; local viewportDrag=false
local redraw,refreshSelection,refreshWorlds,saveWorld
local connections={}
local colors={bg=Color3.fromRGB(35,40,47),field=Color3.fromRGB(53,60,70),text=Color3.fromRGB(235,239,243)}
local function make(class,parent,props)
 local o=Instance.new(class);for k,v in props do o[k]=v end;o.Parent=parent;return o
end
local panel=make("ScrollingFrame",widget,{Size=UDim2.fromScale(1,1),BackgroundColor3=colors.bg,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ScrollBarThickness=8})
make("UIPadding",panel,{PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,12),PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,20)})
make("UIListLayout",panel,{Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
local order=0
local function label(parent,text,height)
 order+=1;return make("TextLabel",parent,{LayoutOrder=order,Size=UDim2.new(1,0,0,height or 24),BackgroundTransparency=1,Text=text,TextColor3=colors.text,Font=Enum.Font.SourceSans,TextSize=15,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})
end
local function section(text) return label(panel,text,28) end
local status=label(panel,"Start node tools/world-builder.js, then Connect.",60)
local function message(text) status.Text=text end
local function guard(fn)
 if busy then return end
 if not Run:IsEdit() then message("Stop Play before editing worlds.");return end
 busy=true
 task.spawn(function()local ok,err=pcall(fn);busy=false;if not ok then message(tostring(err)) end end)
end
local function button(parent,text,fn)
 order+=1;local b=make("TextButton",parent,{LayoutOrder=order,Size=UDim2.new(1,0,0,27),BackgroundColor3=colors.field,TextColor3=colors.text,Text=text,Font=Enum.Font.SourceSans,TextSize=15,AutoButtonColor=true})
 b.Activated:Connect(function()guard(fn)end);return b
end
local function field(parent,title,value)
 label(parent,title,20)
 order+=1;return make("TextBox",parent,{LayoutOrder=order,Size=UDim2.new(1,0,0,27),BackgroundColor3=colors.field,TextColor3=colors.text,Text=tostring(value),ClearTextOnFocus=false,Font=Enum.Font.Code,TextSize=14})
end
local function api(method,route,body,anonymous)
 local url=plugin:GetSetting("BWBuilderURL") or "http://127.0.0.1:34873"
 assert(url:match("^http://127%.0%.0%.1:%d+$"),"Bridge URL must be http://127.0.0.1:PORT")
 local request={Url=url..route,Method=method,Headers={}}
 if not anonymous then assert(session,"Connect to the local bridge first");request.Headers["X-BW-Token"]=session end
 if body then request.Headers["Content-Type"]="application/json";request.Body=Http:JSONEncode(body) end
 local response=Http:RequestAsync(request)
 local data=Http:JSONDecode(response.Body)
 assert(response.Success,data.error or response.StatusMessage)
 return data
end
local function remember()
 if editor then plugin:SetSetting("BWBuilderDraft",Http:JSONEncode(editor.document)) end
end
local function active() assert(editor,"Create or open a world first");return editor end
local function number(box,name,min,max)
 local n=tonumber(box.Text);assert(n and n==n and math.abs(n)<math.huge and n>=(min or -2000) and n<=(max or 2000),"Invalid "..name);return n
end
local worldName=field(panel,"World name","New World")
local worldId=field(panel,"World ID (used when creating or duplicating)","new_world")
local function dirtyLabel()
 if editor then widget.Title="BW World Builder • "..editor.document.name..(editor:dirty() and " *" or "") end
end
local function setDocument(document,needsCreate)
 for _,o in document.objects do
  if o.asset then for _,item in items or {} do if item.model==o.asset then o.type=item.id;break end end end
 end
 editor=State.new(document);editor.needsCreate=needsCreate or false;placing=nil;plugin:SetSetting("BWBuilderLastWorld",document.id)
 worldName.Text=document.name;worldId.Text=document.id
 redraw();remember()
end
local url=field(panel,"Local bridge",plugin:GetSetting("BWBuilderURL") or "http://127.0.0.1:34873")
button(panel,"Connect / refresh catalog",function()
 plugin:SetSetting("BWBuilderURL",url.Text);session=api("GET","/session",nil,true).token
 local discovered={}
 local function walk(folder,prefix)
  for _,child in folder:GetChildren() do
   local full=prefix..child.Name
   if child:IsA("Model") then local _,size=child:GetBoundingBox();table.insert(discovered,{path=full,size={size.X,size.Y,size.Z}})
   elseif child:IsA("Folder") then walk(child,full.."/") end
  end
 end
 local assets=Storage:FindFirstChild("BattleWorksAssets");if assets then walk(assets,"") end
 api("POST","/discover",{assets=discovered})
 local data=api("GET","/catalog");items=data.items;byType={};for _,item in items do byType[item.id]=item end
 refreshWorlds(); redraw();message("Connected. Built-ins are ready; imported models need their one-time native import/export.")
end)
button(panel,"New world",function()
 assert(not editor or not editor:dirty(),"Save changes before creating another world")
 local document=api("POST","/new",{id=worldId.Text,name=worldName.Text})
 setDocument(document,true)
end)
button(panel,"Restore last unsaved draft",function()
 assert(not editor or not editor:dirty(),"Save current changes first")
 local draft=plugin:GetSetting("BWBuilderDraft");assert(draft,"No draft saved")
 setDocument(Http:JSONDecode(draft));message("Draft restored. Save to register it for gameplay.")
end)
local worldsFrame=make("Frame",panel,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,LayoutOrder=order+1});order+=1
make("UIListLayout",worldsFrame,{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder})
refreshWorlds=function()
 for _,c in worldsFrame:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
 label(worldsFrame,"Saved worlds / legacy editable copies",24)
 for _,entry in api("GET","/worlds").worlds do
  button(worldsFrame,(if entry.editable then "Open: " else "Import copy: ")..entry.name,function()
   assert(not editor or not editor:dirty(),"Save current changes before opening another world")
   local document=api("GET","/world?id="..Http:UrlEncode(entry.id));setDocument(document,not entry.editable)
   message(if entry.editable then "Opened "..document.name else "Legacy world flattened into an editable copy. Original is preserved.")
  end)
 end
end
local function installCatalog(catalog)
 -- Apply the bridge-generated data immediately, so Test does not race Rojo's
 -- filesystem watcher. This is the same catalog format, not another loader.
 local config=Storage:FindFirstChild("BattleWorksStudio");assert(config,"Sync BattleWorks before editing")
 local function build(node)
  local o=Instance.new(node.ClassName);o.Name=node.Name or "WorldCatalog"
  for k,v in node.Properties or {} do
   if node.ClassName=="Vector3Value" and k=="Value" then o.Value=Vector3.new(table.unpack(v)) else o[k]=v end
  end
  for _,c in node.Children or {} do build(c).Parent=o end
  return o
 end
 local folder=build(catalog);folder.Name="WorldCatalog"
 local old=config:FindFirstChild("WorldCatalog");if old then old:Destroy() end;folder.Parent=config
 local selected=config:FindFirstChild("SelectedWorld");assert(selected,"Missing SelectedWorld");selected.Value=editor.document.id
end
saveWorld=function(select)
 local state=active();state.document.name=worldName.Text
 -- Measure native dimensions from actual templates before validation/saving.
 for _,o in state.document.objects do o.bounds=preview:bounds(assert(byType[o.type],"Unknown catalog type")) end
 local result=api("POST","/save",{document=state.document,select=select,createOnly=state.needsCreate})
 state:markSaved(result.document);state.needsCreate=false;if select then installCatalog(result.catalog) end
 remember();dirtyLabel();refreshWorlds();message("Saved "..state.document.name..(if select then " and selected for gameplay." else "."))
end
button(panel,"Save + register",function()saveWorld(false)end)
button(panel,"Select this world",function()saveWorld(true)end)
button(panel,"Test World (save → select → Play)",function()
 saveWorld(true);preview:clear();Selection:Set({});placing=nil
 task.spawn(function()
  local ok,err=pcall(function() game:GetService("StudioTestService"):ExecutePlayModeAsync({battleworksWorld=editor.document.id}) end)
  if not ok then message("World saved and selected. Use Studio Play (F5): "..tostring(err)) end
  if Run:IsEdit() and widget.Enabled then redraw() end
 end)
end)
button(panel,"Publish world for repository builds",function()
 saveWorld(false);api("POST","/publish",{id=editor.document.id})
 local config=Storage:FindFirstChild("BattleWorksStudio");config.PublishedWorld.Value=editor.document.id
 message("Published for repository builds. Roblox cloud publishing is separate.")
end)
button(panel,"Select Default Test Arena",function()
 api("POST","/default",{});Storage.BattleWorksStudio.SelectedWorld.Value=""
 message("Default Test Arena selected for next Play.")
end)
button(panel,"Duplicate world using World ID above",function()
 local copy=State.copy(active().document);copy.id=worldId.Text;copy.name=worldName.Text
 assert(copy.id~=editor.document.id,"Enter a new unique World ID above")
 api("POST","/save",{document=copy,createOnly=true});setDocument(copy);refreshWorlds();message("Created independent world copy.")
end)
local confirm=field(panel,"Delete confirmation: type current world ID","")
button(panel,"Delete saved world",function()
 local id=active().document.id;api("POST","/delete",{id=id,confirmation=confirm.Text})
 local config=Storage:FindFirstChild("BattleWorksStudio")
 if config then
  for _,key in {"SelectedWorld","PublishedWorld"}do local value=config:FindFirstChild(key);if value and value.Value==id then value.Value=""end end
  local catalog=config:FindFirstChild("WorldCatalog")
  if catalog then for _,entry in catalog:GetChildren()do local key=entry:FindFirstChild("WorldId");if key and key.Value==id then entry:Destroy()end end end
 end
 editor=nil;preview:clear();Selection:Set({});confirm.Text="";plugin:SetSetting("BWBuilderDraft",nil);refreshWorlds();message("Deleted "..id..". Default arena restored if it was selected.")
end)
button(panel,"Import world JSON file",function()
 assert(not editor or not editor:dirty(),"Save current changes first")
 local file=Studio:PromptImportFileAsync({"json"});if not file then return end
 local text=file:GetBinaryContents();assert(#text<=2*1024*1024,"World import exceeds 2MB")
 local document=Http:JSONDecode(text);assert(document.schemaVersion==2,"Use the legacy world list to migrate v1 definitions")
 local result=api("POST","/import",{document=document});setDocument(result.document);refreshWorlds();message("Imported and registered world.")
end)
button(panel,"Export portable JSON file",function()
 saveWorld(false)
 local result=api("POST","/export-file",{id=editor.document.id});message("Exported: "..result.path)
end)
section("Palette — click then place, or drag into viewport")
local search=field(panel,"Filter catalog","")
local palette=make("Frame",panel,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,LayoutOrder=order+1});order+=1
make("UIListLayout",palette,{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder})
local paletteItems={}
local function fillPalette()
 for _,c in palette:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
 local sorted=State.copy(items or {});
 for _,kind in {"Boomer","Rattler"} do table.insert(sorted,{name=kind.." spawn",category="Tank spawn locations",spawnKind=kind})end
 table.sort(sorted,function(a,b)return a.category..a.name<b.category..b.name end)
 local previous
 for _,item in sorted do
  if not (item.category.." "..item.name):lower():find(search.Text:lower(),1,true) then continue end
  if previous~=item.category then label(palette,item.category,23);previous=item.category end
  local available=item.spawnKind~=nil or preview:template(item)~=nil
  local b=button(palette,(item.model or item.name)..(if item.spawnKind then "" elseif not available then " [model missing]" elseif not item.packaged then " [export once]" else ""),function()
   active();assert(available,"Missing Studio Model "..item.model);placing=item;plugin:Activate(true);message("Place "..item.name.." in the viewport. Escape cancels.")
  end)
  b.MouseButton1Down:Connect(function()
   if not busy and editor and available and Run:IsEdit() then placing=item;viewportDrag=false;plugin:Activate(true) end
  end)
  -- Model preview uses actual template proportions, with a bounded number of
  -- live thumbnail clones; large catalogs keep text entries for responsiveness.
  if available and not item.spawnKind and #paletteItems<24 then
   local viewport=make("ViewportFrame",b,{Size=UDim2.fromOffset(40,25),Position=UDim2.new(1,-42,0,1),BackgroundTransparency=1})
   local clone=preview:template(item):Clone()
   for _,d in clone:GetDescendants() do if d:IsA("LuaSourceContainer") then d:Destroy() end end
   clone.Parent=viewport;local cf,size=clone:GetBoundingBox();local camera=Instance.new("Camera");camera.CFrame=CFrame.lookAt(cf.Position+Vector3.new(1,.7,1).Unit*size.Magnitude*1.3,cf.Position);camera.Parent=viewport;viewport.CurrentCamera=camera
   table.insert(paletteItems,viewport)
  end
 end
end
search:GetPropertyChangedSignal("Text"):Connect(function()table.clear(paletteItems);fillPalette()end)
section("Editing tools")
local grid=field(panel,"Grid snap (studs)",1)
grid.FocusLost:Connect(function()if editor then local ok,err=pcall(function()editor.grid=number(grid,"grid",.1,100)end);if not ok then message(err)end end end)
button(panel,"Toggle grid snapping",function()local s=active();s.grid=number(grid,"grid",.1,100);s.snap=not s.snap;message("Grid snapping "..(if s.snap then "on" else "off"))end)
for _,tool in {"Move","Rotate","Scale"} do button(panel,tool.." handles",function()mode=tool;placing=nil;plugin:Activate(true);refreshSelection()end) end
button(panel,"Duplicate selected",function()active():duplicate();redraw();remember()end)
button(panel,"Delete selected",function()active():delete();redraw();remember()end)
button(panel,"Undo",function()if active():undo()then redraw();remember()end end)
button(panel,"Redo",function()if active():redo()then redraw();remember()end end)
button(panel,"Frame world / overhead camera",function()
 local d=active().document;local c=workspace.CurrentCamera;c.CFrame=CFrame.lookAt(Vector3.new(0,math.max(d.settings.width,d.settings.depth)*.8,math.max(d.settings.width,d.settings.depth)*.25),Vector3.zero);c.Focus=CFrame.new()
end)
section("Selected object(s)")
local selectedLabel=label(panel,"Nothing selected",25)
local assetLabel=label(panel,"Asset path: —",40)
local px=field(panel,"X",0);local pz=field(panel,"Z",0);local yaw=field(panel,"Yaw / spawn heading (degrees)",0);local scale=field(panel,"Uniform asset scale",1)
local solid=field(panel,"Collision: true / false","true");local destructible=field(panel,"Destructible: true / false","false");local hp=field(panel,"Health",100)
local function boolean(box)assert(box.Text=="true" or box.Text=="false","Enter true or false");return box.Text=="true"end
button(panel,"Apply properties to selection",function()
 local s=active();assert(next(s.selection),"Select an object")
 s:change(function()for id in s.selection do local o,spawn=s:find(id);o.position={number(px,"X"),if spawn then 0 else o.position[2],number(pz,"Z")};if spawn then o.heading=number(yaw,"heading",-360000,360000) else o.rotation={o.rotation[1],number(yaw,"yaw",-360000,360000),o.rotation[3]};o.scale=number(scale,"scale",.001,1000);o.solid=boolean(solid);o.destructible=boolean(destructible);o.hp=number(hp,"health",1,100000)end end end)
 redraw();remember()
end)
section("World settings — flat ground")
local description=field(panel,"Description","")
local width=field(panel,"Width (studs)",230);local depth=field(panel,"Depth (studs)",230)
local material=field(panel,"Ground material", "Grass");local color=field(panel,"Ground RGB, comma separated","100,112,86")
button(panel,"Apply world settings",function()
 local rgb={};for n in color.Text:gmatch("[^,]+")do table.insert(rgb,tonumber(n))end;assert(#rgb==3,"Ground color needs R,G,B")
 for _,n in rgb do assert(n and n>=0 and n<=255,"RGB values must be 0–255")end
 local s=active();s:change(function()s.document.name=worldName.Text;s.document.description=description.Text;s.document.settings.width=number(width,"width",25,2000);s.document.settings.depth=number(depth,"depth",25,2000);assert(Enum.Material[material.Text],"Unknown material");s.document.settings.ground={material=material.Text,color=rgb}end)
 redraw();remember()
end)
label(panel,"Shift-click for multiple selection. Drag objects on ground; use handles for move/yaw/uniform scale. Ctrl+D duplicates, Delete removes, Ctrl+Z/Y undo/redo. Escape cancels placement. Use Studio camera controls to pan/orbit/zoom. No drivable elevation in this version.",95)
local handles=Instance.new("Handles");handles.Name="BWMoveScale";handles.Style=Enum.HandlesStyle.Movement;handles.Faces=Faces.new(Enum.NormalId.Left,Enum.NormalId.Right,Enum.NormalId.Front,Enum.NormalId.Back);handles.Color3=Color3.fromRGB(255,200,65);handles.Parent=CoreGui
local arcs=Instance.new("ArcHandles");arcs.Name="BWRotate";arcs.Axes=Axes.new(Enum.Axis.Y);arcs.Color3=Color3.fromRGB(95,210,130);arcs.Parent=CoreGui
local gizmo=Instance.new("Part");gizmo.Name="BWEditorGizmo";gizmo.Anchored=true;gizmo.Transparency=1;gizmo.CanCollide=false;gizmo.CanTouch=false;gizmo.CanQuery=false;gizmo.Archivable=false
preview.beforeClear=function()handles.Adornee=nil;arcs.Adornee=nil;gizmo.Parent=nil end
refreshSelection=function()
 if not editor then handles.Adornee=nil;arcs.Adornee=nil;return end
 local selected={};local names={}
 for id in editor.selection do
  if preview.models[id] then table.insert(selected,preview.models[id]);table.insert(names,id) end
 end
 table.sort(names);selectedLabel.Text=if #names>0 then table.concat(names,", ") else "Nothing selected"
 suppressSelection=true;Selection:Set(selected);suppressSelection=false
 handles.Adornee=nil;arcs.Adornee=nil
 if #names==0 then return end
 local first,spawn=editor:find(names[1]);assetLabel.Text="Asset path: "..tostring(first.asset or (if spawn then "Tank spawn" else "legacy catalog reference"));px.Text=tostring(first.position[1]);pz.Text=tostring(first.position[3]);yaw.Text=tostring(if spawn then first.heading else first.rotation[2])
 scale.Text=tostring(first.scale or 1);solid.Text=tostring(first.solid or false);destructible.Text=tostring(first.destructible or false);hp.Text=tostring(first.hp or 100)
 local model=preview.models[names[1]];local cf,size=model:GetBoundingBox();gizmo.Size=Vector3.new(math.max(1,size.X),math.max(1,size.Y),math.max(1,size.Z));gizmo.CFrame=CFrame.new(cf.Position);gizmo.Parent=preview:folder()
 if mode=="Rotate" then arcs.Adornee=gizmo else handles.Style=if mode=="Scale" then Enum.HandlesStyle.Resize else Enum.HandlesStyle.Movement;handles.Adornee=gizmo end
 dirtyLabel()
end
redraw=function()
 if not editor or not widget.Enabled or not Run:IsEdit() then return end
 local errors=preview:rebuild(editor.document,byType or {});refreshSelection()
 description.Text=editor.document.description;width.Text=tostring(editor.document.settings.width);depth.Text=tostring(editor.document.settings.depth)
 material.Text=editor.document.settings.ground.material;color.Text=table.concat(editor.document.settings.ground.color,",")
 table.clear(paletteItems);fillPalette();dirtyLabel()
 if #errors>0 then message(table.concat(errors,"\n")) end
end
local function point()
 local ray=mouse.UnitRay;if math.abs(ray.Direction.Y)<1e-5 then return end
 local t=-ray.Origin.Y/ray.Direction.Y;if t<0 then return end
 local p=ray.Origin+ray.Direction*t;return {p.X,0,p.Z}
end
local function place()
 if not placing or not editor then return end
 local p=point();if not p then return end
 editor.grid=number(grid,"grid",.1,100)
 local item=placing
 if item.spawnKind then
  editor:change(function()for _,spawn in editor.document.spawns do if spawn.tank==item.spawnKind then spawn.position={editor:snapValue(p[1]),0,editor:snapValue(p[3])};editor.selection={[spawn.id]=true};break end end end)
 else local bounds=preview:bounds(item);editor:add(item,p,bounds)end
 placing=nil;viewportDrag=false;redraw();remember()
end
local function finishGesture()
 if gesture and editor then editor:record(gesture.before);gesture=nil;refreshSelection();remember();dirtyLabel() end
end
local function beginGesture(kind)
 active();placing=nil;gesture={kind=kind,before=editor:snapshot()}
end
handles.MouseButton1Down:Connect(function()if editor and Run:IsEdit()then beginGesture(mode)end end)
handles.MouseDrag:Connect(function(face,distance)
 if not editor or not gesture or not Run:IsEdit()then return end
 local before=gesture.before;editor:restore(before)
 local axis=if face==Enum.NormalId.Left then {-1,0} elseif face==Enum.NormalId.Right then {1,0} elseif face==Enum.NormalId.Front then {0,-1} else {0,1}
 for id in editor.selection do
  local o,spawn=editor:find(id)
  if gesture.kind=="Scale" and not spawn then o.scale=math.clamp(o.scale*(1+distance/math.max(gizmo.Size.X,gizmo.Size.Z)),.001,1000)
  elseif gesture.kind=="Move" then o.position[1]=editor:snapValue(o.position[1]+distance*axis[1]);o.position[3]=editor:snapValue(o.position[3]+distance*axis[2])end
  preview:pose(id,o)
 end
end)
handles.MouseButton1Up:Connect(finishGesture)
arcs.MouseButton1Down:Connect(function()if editor and Run:IsEdit()then beginGesture("Rotate")end end)
arcs.MouseDrag:Connect(function(_,angle)
 if not gesture or not editor or not Run:IsEdit()then return end
 editor:restore(gesture.before);local degrees=math.deg(angle);if editor.snap then degrees=math.round(degrees/5)*5 end
 for id in editor.selection do local o,spawn=editor:find(id);if spawn then o.heading=(o.heading+degrees)%360 else o.rotation[2]=(o.rotation[2]+degrees)%360 end;preview:pose(id,o)end
end)
arcs.MouseButton1Up:Connect(finishGesture)
local function editorId(target)
 while target and target~=preview.root do local id=target:GetAttribute("BWEditorId");if id then return id end;target=target.Parent end
end
mouse.Button1Down:Connect(function()
 if not editor or not widget.Enabled or busy or not Run:IsEdit()then return end
 if placing then guard(place);return end
 if gesture and gesture.kind~="Ground" then return end
 local id=editorId(mouse.Target);local extend=UIS:IsKeyDown(Enum.KeyCode.LeftShift)or UIS:IsKeyDown(Enum.KeyCode.RightShift)
 editor:select(id,extend);refreshSelection()
 if id and mode=="Move" then beginGesture("Ground");gesture.start=point()end
end)
mouse.Move:Connect(function()
 if not editor or not widget.Enabled or not Run:IsEdit()then return end
 if placing then viewportDrag=true end
 if gesture and gesture.kind=="Ground" and gesture.start then
  local p=point();if not p then return end
  editor:restore(gesture.before)
  local dx,dz=p[1]-gesture.start[1],p[3]-gesture.start[3]
  for id in editor.selection do local o=editor:find(id);o.position[1]=editor:snapValue(o.position[1]+dx);o.position[3]=editor:snapValue(o.position[3]+dz);preview:pose(id,o)end
 end
end)
mouse.Button1Up:Connect(finishGesture)
connections[#connections+1]=UIS.InputEnded:Connect(function(input)
 if not widget.Enabled or not Run:IsEdit()then return end
 if input.UserInputType==Enum.UserInputType.MouseButton1 then
  if placing and viewportDrag then guard(place)end
  finishGesture()
 end
end)
connections[#connections+1]=Selection.SelectionChanged:Connect(function()
 if suppressSelection or not editor or not widget.Enabled or not Run:IsEdit()then return end
 local selection={}
 for _,instance in Selection:Get()do local id=editorId(instance);if id then selection[id]=true end end
 editor.selection=selection;refreshSelection()
end)
connections[#connections+1]=UIS.InputBegan:Connect(function(input,processed)
 if processed or not editor or not widget.Enabled or UIS:GetFocusedTextBox()or not Run:IsEdit()then return end
 local ctrl=UIS:IsKeyDown(Enum.KeyCode.LeftControl)or UIS:IsKeyDown(Enum.KeyCode.RightControl)or UIS:IsKeyDown(Enum.KeyCode.LeftMeta)or UIS:IsKeyDown(Enum.KeyCode.RightMeta)
 if input.KeyCode==Enum.KeyCode.Escape then placing=nil;if gesture then editor:restore(gesture.before);gesture=nil;redraw();remember() end;plugin:Deactivate();return end
 guard(function()
  if ctrl and input.KeyCode==Enum.KeyCode.Z then editor:undo();redraw()
  elseif ctrl and input.KeyCode==Enum.KeyCode.Y then editor:redo();redraw()
  elseif ctrl and input.KeyCode==Enum.KeyCode.D then editor:duplicate();redraw()
  elseif input.KeyCode==Enum.KeyCode.Delete then editor:delete();redraw()end
  remember()
 end)
end)
connections[#connections+1]=Run:GetPropertyChangedSignal("RunState"):Connect(function()
 if not Run:IsEdit()then finishGesture();placing=nil;handles.Adornee=nil;arcs.Adornee=nil;preview:clear()
 elseif widget.Enabled and editor then task.defer(redraw)end
end)
toggle.Click:Connect(function()widget.Enabled=not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
 if widget.Enabled then plugin:Activate(true);if editor then redraw()end
 else finishGesture();placing=nil;preview:clear();handles.Adornee=nil;arcs.Adornee=nil;plugin:Deactivate();remember()end
end)
plugin.Unloading:Connect(function()
 remember();preview:clear();handles:Destroy();arcs:Destroy();gizmo:Destroy()
 for _,connection in connections do connection:Disconnect()end
end)

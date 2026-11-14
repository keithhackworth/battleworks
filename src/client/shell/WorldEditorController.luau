local Shared=game.ReplicatedStorage.Shared
local State=require(Shared.WorldEditorState)
local Document=require(Shared.WorldEditorDocument)
local Math=require(Shared.WorldEditorMath)
local View=require(script.Parent.WorldEditorView)
local Scene=require(script.Parent.WorldEditorScene)
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Controller={};Controller.__index=Controller
function Controller.new(context)
 if not context.editorAssets and context.getEditorAssets then context.editorAssets=context.getEditorAssets() end
 local view=View.new(context)
 local self=setmetatable({context=context,view=view,frame=view.frame,buttons=view.buttons,state=State.new(Document.fresh()),catalog=Document.catalog({}),prefix="",page=1,mode="Move",runtime={},keys={},yaw=.55,pitch=1,distance=210,focus=Vector3.zero},Controller)
 self.state.snap=false
 self.library=require(script.Parent.WorldLibrary).new(view.frame,context.worldRequest,function(document)
  self:cancel();self.state=State.new(document);self.state.snap=false
  view.name.Text=document.name;view.worldId.Text=document.id
  self:frameWorld();self:refresh();self:updateGrid()
  return self.state.document
 end,function() if self.active then context.join() end end)
 view.library=self.library
 self:loadCatalog()
 local function action(event,fn) view:on(event,function(...) if self.active then fn(...) end end) end
 for mode,button in view.tools do action(button.Activated,function() self:setMode(mode) end) end
 for axis,button in view.rotationAxes do action(button.Activated,function() self.rotationAxis=axis;self:setMode("Rotate") end) end
 action(view.undo.Activated,function() self:history(false) end);action(view.redo.Activated,function() self:history(true) end)
 action(view.duplicate.Activated,function() self:perform(function() self.state:duplicate() end,"Duplicated selection. Drag the new object to move it.") end)
 action(view.delete.Activated,function() self:perform(function() self.state:delete() end,"Deleted selection.") end)
 action(view.up.Activated,function() self.prefix=self.prefix:gsub("[^/]+/$","");self.page=1;self:browse() end)
 action(view.nextPage.Activated,function() self.page=self.page%self.pages+1;self:browse() end)
 view:on(view.search:GetPropertyChangedSignal("Text"),function() if self.active then self.page=1;self:browse() end end)
 action(view.snap.Activated,function() self.state.snap=not self.state.snap;self:updateGrid() end)
 action(view.grid.FocusLost,function()
  local value=tonumber(view.grid.Text)
  if not value or value~=value or value<.1 or value>50 then view.grid.Text=tostring(self.state.grid);view:message("Grid size must be between 0.1 and 50 studs.");return end
  self.state.grid=value;self:updateGrid()
 end)
 action(view.frameWorld.Activated,function() self:frameWorld() end)
 for key,field in view.fields do action(field.FocusLost,function()
  local entry=self:selected();if not entry then return end
  local n=tonumber(field.Text)
  self:perform(function()
   assert(n and n==n and math.abs(n)<math.huge,"Enter a finite number")
   if key=="x" then entry.position[1]=n elseif key=="y" then entry.position[2]=n elseif key=="z" then entry.position[3]=n elseif key=="pitch" then entry.rotation[1]=n elseif key=="yaw" then entry.rotation[2]=n elseif key=="roll" then entry.rotation[3]=n elseif key=="scale" then entry.scale=n else entry.hp=n end
  end,"Updated "..key)
 end) end
 action(view.solid.Activated,function() local o=self:selected();if o then self:perform(function() o.solid=not o.solid end,"Collision updated.") end end)
 action(view.destructible.Activated,function() local o=self:selected();if o then self:perform(function() o.destructible=not o.destructible end,"Destructibility updated.") end end)
 action(view.export.Activated,function()
  self:cancel();view.name.Text=self.state.document.name;view.worldId.Text=self.state.document.id
  view.overlay.Visible=true;self:export()
 end)
 action(view.generate.Activated,function() self:export() end)
 action(view.worlds.Activated,function() self:cancel();self.library:open(self.state.document) end)
 return self
end
function Controller:loadCatalog()
 local context=self.context
 if not context.editorAssets and context.getEditorAssets then context.editorAssets=context.getEditorAssets() end
 if not context.editorAssets then return false end
 local data=context.editorAssets:FindFirstChild("Catalog")
 if not data then return false end
 local ok,items=pcall(function() return Http:JSONDecode(data.Value) end)
 if ok then self.catalog=Document.catalog(items) else self.view:message("Catalog could not be read: "..tostring(items)) end
 return ok
end
function Controller:selected()
 for id in self.state.selection do return self.state:find(id) end
end
function Controller:refresh()
 if self.scene then self.scene:sync(self.state.document,self.catalog) end
 local selected=self:selected();self.view:selection(selected,selected and self.catalog.byPath[selected.asset])
 if self.scene then self.scene:selection(selected and selected.id,self.distance) end
 self.view.undo.Text="Undo ("..#self.state.past..")";self.view.redo.Text="Redo ("..#self.state.future..")"
end
function Controller:perform(fn,message)
 self:cancel()
 local before=self.state:snapshot();local past,future=table.clone(self.state.past),table.clone(self.state.future)
 local ok,err=pcall(function() fn();Document.export(self.state.document,self.catalog) end)
 if not ok then self.state:restore(before);self.state.past=past;self.state.future=future
 elseif self.state.past[#self.state.past]==past[#past] then self.state:record(before) end
 self:refresh();self.view:message(if ok then message else tostring(err))
 return ok
end
function Controller:history(redo)
 self:cancel()
 local changed=if redo then self.state:redo() else self.state:undo()
 self:refresh();self.view:message(if changed then (if redo then "Redone." else "Undone.") else "No more history.")
end
function Controller:browse()
 local dirs,items=Document.tree(self.catalog,self.prefix,self.view.search.Text)
 self.page,self.pages=self.view:paletteEntries(dirs,items,self.prefix,self.page,self.context.editorAssets,function(folder)
  self.prefix..=folder.."/";self.page=1;self:browse()
 end,function(item) self:choose(item) end)
end
function Controller:choose(item)
 if not item.available then self.view:message("Native model is not packaged: "..item.model);return end
 self:cancel();self.placing=item;self.paletteDrag=self:mousePosition()
 self.state.selection={};self:refresh();self.view:message(item.model.." • drag onto ground, or click ground to place. Esc cancels.")
end
function Controller:updateGrid()
 self.view.snap.Text="Grid snap: "..(if self.state.snap then "ON" else "OFF")
 if self.scene then self.scene:grid(self.state.snap,self.state.grid) end
end
function Controller:setMode(mode)
 self:cancel();self.mode=mode
 if self.scene then self.scene:setMode(mode,self.rotationAxis or "Yaw") end
 for axis,button in self.view.rotationAxes do button.BackgroundColor3=if axis==(self.rotationAxis or "Yaw") then Color3.fromRGB(133,94,38) else Color3.fromRGB(43,61,66) end
 for name,button in self.view.tools do button.BackgroundColor3=if name==mode then Color3.fromRGB(133,94,38) else Color3.fromRGB(43,61,66) end
 self.view:message(if mode=="Move" then "Move • red X / blue Z slides; green Y raises or lowers. Height Y also accepts an exact value." elseif mode=="Rotate" then "Rotate • choose Tilt X, Yaw Y or Tilt Z on the left, then drag the ring. Grid snaps angles to 15°." else "Scale • drag the green anchor to resize uniformly.")
end
function Controller:frameWorld() self.focus=Vector3.zero;self.distance=math.max(self.state.document.settings.width,self.state.document.settings.depth)*.95;self.pitch=1;self.yaw=.55 end
function Controller:mousePosition()
 local origin=game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.None).Min
 return Math.guiPoint(UIS:GetMouseLocation(),origin)
end
function Controller:pointer()
 local mouse=self:mousePosition()
 if not self.scene then return nil,nil,nil,mouse end
 local origin,direction=Math.ray(self.scene.camera.CFrame,self.view.viewport.AbsoluteSize,mouse-self.view.viewport.AbsolutePosition,self.scene.camera.FieldOfView)
 return Math.ground(origin,direction),origin,direction,mouse
end
function Controller:candidate(point)
 local item=self.placing
 return {id="placement_preview",type=item.id,asset=item.model,position={self.state:snapValue(point.X),0,self.state:snapValue(point.Z)},rotation={0,0,0},scale=item.defaultScale or 1,solid=item.solid or false,destructible=item.destructible or false,hp=item.hp or 100,bounds=State.copy(item.size)}
end
function Controller:place(point)
 if not self.placing or not point then return end
 local item=self.placing
 local valid,reason=pcall(Document.checkEntry,self.state.document,self.catalog,self:candidate(point))
 if not valid then self.view:message(reason);return end
 self:perform(function() self.state:add(item,{point.X,0,point.Z},item.size) end,"Placed "..item.model..". Drag the object to move it.")
end
function Controller:cancel()
 if self.gesture then self.state:restore(self.gesture.before);self.gesture=nil;if self.scene then self.scene:sync(self.state.document,self.catalog) end end
 self.placing=nil;self.paletteDrag=nil;self.orbit=nil;self.pan=nil
 if self.scene then self.scene:clearGhost() end
end
function Controller:finishGesture(cancel)
 local g=self.gesture;if not g then return end
 self.gesture=nil
 local ok,err=pcall(function() Document.export(self.state.document,self.catalog) end)
 if cancel or not ok then self.state:restore(g.before) else self.state:record(g.before) end
 self:refresh();self.view:message(if cancel then "Transform canceled." elseif ok then "Transform applied." else tostring(err))
end
function Controller:begin(input,processed)
 if self.paused or UIS:GetFocusedTextBox() or self.view:isModal() then return end
 local point,origin,direction,mouse=self:pointer()
 if not point or not self.view:isScene(mouse) then return end
 if processed then return end
 if input.UserInputType==Enum.UserInputType.MouseButton2 then self.orbit={last=mouse};return end
 if input.UserInputType==Enum.UserInputType.MouseButton3 then self.pan={point=point,focus=self.focus};return end
 if processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
 if self.placing then self:place(point);return end
 local id,handle=self.scene:pick(origin,direction,mouse-self.view.viewport.AbsolutePosition,self.view.viewport.AbsoluteSize)
 if id then self.state:select(id);self:refresh() end
 local entry=self:selected()
 if entry and (handle or (id and self.mode=="Move")) then
  local kind=handle or "Move"
  local pivot=if kind:sub(1,6)=="Rotate" then self.scene.models[entry.id].model:GetBoundingBox().Position else nil
  local start=Math.dragPoint(kind,entry,origin,direction,self.scene.camera.CFrame,pivot)
  if not start then self.view:message("Orbit the camera slightly to face this rotation ring, then drag again.");return end
  self.gesture={before=self.state:snapshot(),base=State.copy(entry),id=entry.id,start=start,kind=kind,pivot=pivot}
 elseif not id and not handle then self.state.selection={};self:refresh() end
end
function Controller:key(input,processed)
 if processed or UIS:GetFocusedTextBox() or self.view:isModal() then return end
 self.keys[input.KeyCode]=true
 local control=UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) or UIS:IsKeyDown(Enum.KeyCode.LeftMeta) or UIS:IsKeyDown(Enum.KeyCode.RightMeta)
 local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
 if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.Q then self:cancel();self:refresh()
 elseif control and input.KeyCode==Enum.KeyCode.Z then self:history(shift)
 elseif control and input.KeyCode==Enum.KeyCode.Y then self:history(true)
 elseif control and input.KeyCode==Enum.KeyCode.D then self:perform(function() self.state:duplicate() end,"Duplicated selection.")
 elseif input.KeyCode==Enum.KeyCode.Delete or input.KeyCode==Enum.KeyCode.Backspace then self:perform(function() self.state:delete() end,"Deleted selection.")
 elseif input.KeyCode==Enum.KeyCode.One then self:setMode("Move") elseif input.KeyCode==Enum.KeyCode.Two then self:setMode("Rotate")
 elseif input.KeyCode==Enum.KeyCode.Three then self:setMode("Scale")
 elseif input.KeyCode==Enum.KeyCode.G then self.state.snap=not self.state.snap;self:updateGrid()
 elseif input.KeyCode==Enum.KeyCode.F then self:frameWorld() end
end
function Controller:step(dt)
 local scene=self.scene;if not scene then return end
 local mouse=self:mousePosition()
 if self.orbit then local delta=mouse-self.orbit.last;self.yaw-=delta.X*.006;self.pitch=math.clamp(self.pitch+delta.Y*.004,.35,1.45);self.orbit.last=mouse end
 if not UIS:GetFocusedTextBox() and not self.gesture and not self.placing and not self.view:isModal() then
  local forward=(if self.keys[Enum.KeyCode.W] then 1 else 0)-(if self.keys[Enum.KeyCode.S] then 1 else 0)
  local right=(if self.keys[Enum.KeyCode.D] then 1 else 0)-(if self.keys[Enum.KeyCode.A] then 1 else 0)
  if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then forward=0;right=0 end
  self.focus+=(Vector3.new(-math.sin(self.yaw),0,-math.cos(self.yaw))*forward+Vector3.new(math.cos(self.yaw),0,-math.sin(self.yaw))*right)*self.distance*math.min(dt,.1)*.6
 end
 scene.camera.CFrame=CFrame.lookAt(self.focus+Vector3.new(math.sin(self.yaw)*math.cos(self.pitch),math.sin(self.pitch),math.cos(self.yaw)*math.cos(self.pitch))*self.distance,self.focus)
 local point,origin,direction=self:pointer()
 if self.pan and point then self.focus+=self.pan.point-point end
 if self.gesture then
  local g=self.gesture;local entry=self.state:find(g.id)
  local drag=Math.dragPoint(g.kind,g.base,origin,direction,scene.camera.CFrame,g.pivot)
  if drag then
   local transform=Math.transform(g.base,g.kind,g.start,drag,self.state.snap,self.state.grid,g.pivot)
   entry.position=transform.position;entry.rotation=transform.rotation;entry.scale=transform.scale
   scene:sync(self.state.document,self.catalog)
  end
 end
 if self.placing and point and self.view:isScene(mouse) then
  local candidate=self:candidate(point)
  local ok,err=pcall(Document.checkEntry,self.state.document,self.catalog,candidate)
  scene:ghost(candidate,self.placing,ok)
  self.view:message(if ok then self.placing.model.." • release / click to place" else tostring(err))
 else scene:clearGhost() end
 local selected=self:selected();scene:selection(selected and selected.id,self.distance)
 if self.gesture and selected then
  local valid=pcall(Document.checkEntry,self.state.document,self.catalog,selected)
  for _,p in scene.wire do p.Color=if valid then Color3.fromRGB(255,209,91) else Color3.fromRGB(245,90,75) end
 end
end
function Controller:export()
 local document=State.copy(self.state.document)
 document.id=self.view.worldId.Text;document.name=self.view.name.Text
 local ok,result=pcall(function() return Http:JSONEncode(Document.export(document,self.catalog)) end)
 if not ok then self.view.json.Text="Export blocked: "..tostring(result);return end
 self.state.document.id=document.id;self.state.document.name=document.name
 self.view.json.Text=result;self.view.json:CaptureFocus();self.view.json.SelectionStart=1;self.view.json.CursorPosition=(utf8.len(result) or #result)+1
 self.view:message("JSON export is optional. Use My Worlds / Save & Play to save and launch directly in the game.")
end
function Controller:enter()
 assert(self.context.session.mode=="Menu","Leave battle before editing")
 self.active=true;self.paused=false;self.frame.Visible=true;self.view.overlay.Visible=false
 game:GetService("GuiService").SelectedObject=nil
 if self:loadCatalog() then
  self.scene=Scene.new(self.view.viewport,self.context.editorAssets,self.state.document)
  self:frameWorld();self:refresh();self:updateGrid();self:setMode(self.mode)
 else self.view:message("Asset library unavailable. Rebuild/sync the place with its editor catalog; no live battle objects will be edited.") end
 self:browse()
 local function connect(event,fn) table.insert(self.runtime,event:Connect(fn)) end
 connect(UIS.InputBegan,function(input,processed)
  if input.UserInputType==Enum.UserInputType.Keyboard then self:key(input,processed) elseif self.scene then self:begin(input,processed) end
 end)
 connect(UIS.InputEnded,function(input)
  self.keys[input.KeyCode]=nil
  if input.UserInputType==Enum.UserInputType.MouseButton2 then self.orbit=nil end
  if input.UserInputType==Enum.UserInputType.MouseButton3 then self.pan=nil end
  if input.UserInputType==Enum.UserInputType.MouseButton1 then
   local point,_,_,mouse=self:pointer()
   if self.paused then self:cancel();return end
   if self.paletteDrag then
    local start=self.paletteDrag;self.paletteDrag=nil
    if point and (mouse-start).Magnitude>6 and self.view:isScene(mouse) then self:place(point) end
   elseif self.gesture then self:finishGesture(false) end
  end
 end)
 connect(UIS.InputChanged,function(input)
  if input.UserInputType==Enum.UserInputType.MouseWheel and not self.view:isModal() and self.view:isScene(self:mousePosition()) then self.distance=math.clamp(self.distance*math.exp(-input.Position.Z*.12),20,1600) end
 end)
 connect(UIS.WindowFocusReleased,function() self:cancel();self.keys={};self:refresh() end)
 local gui=game:GetService("GuiService")
 connect(gui.MenuOpened,function() self.paused=true;self:cancel();self.keys={} end)
 connect(gui.MenuClosed,function() self.paused=false end)
 if self.scene then connect(Run.RenderStepped,function(dt) self:step(dt) end) end
end
function Controller:exit()
 self.library:hide()
 self:cancel();self.active=false;self.frame.Visible=false;self.keys={}
 for _,connection in self.runtime do connection:Disconnect() end;self.runtime={}
 local focused=UIS:GetFocusedTextBox();if focused then focused:ReleaseFocus() end
 if self.scene then self.scene:destroy();self.scene=nil end
end
function Controller:moveFocus() game:GetService("GuiService").SelectedObject=self.view.back end
function Controller:activateSelected() self.context.home() end
function Controller:destroy() self:exit();self.view:destroy() end
return Controller

local Shared=game.ReplicatedStorage.Shared
local State=require(Shared.WorldEditorState)
local Document=require(Shared.WorldEditorDocument)
local Math=require(Shared.WorldEditorMath)
local Snap=require(Shared.WorldEditorSnap)
local Visual=require(Shared.AssetGeometry)
local View=require(script.Parent.WorldEditorView)
local Scene=require(script.Parent.WorldEditorScene)
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Actions=game:GetService("ContextActionService")
local Controller={};Controller.__index=Controller
function Controller.new(context)
 if not context.editorAssets and context.getEditorAssets then context.editorAssets=context.getEditorAssets() end
 local view=View.new(context)
 local self=setmetatable({context=context,view=view,frame=view.frame,buttons=view.buttons,state=State.new(Document.editorFresh()),catalog=Document.catalog({}),prefix="",page=1,mode="Move",runtime={},keys={},yaw=.55,pitch=1,distance=210,focus=Vector3.zero},Controller)
 self.state.snap=false
 self.library=require(script.Parent.WorldLibrary).new(view.frame,context.worldRequest,function(document)
  self:replaceDocument(document)
  return self.state.document
 end,function() if self.active then context.join() end end)
 view.library=self.library
 self:loadCatalog()
 local function action(event,fn) view:on(event,function(...) if self.active then fn(...) end end) end
 for mode,button in view.tools do action(button.Activated,function() self:setMode(mode) end) end
 for axis,button in view.rotationAxes do action(button.Activated,function() self.rotationAxis=axis;self:setMode("Rotate") end) end
 action(view.undo.Activated,function() self:history(false) end);action(view.redo.Activated,function() self:history(true) end)
 action(view.duplicate.Activated,function() self:perform(function() self.state:duplicate() end,"Duplicated selection. Drag the new object to move it.") end)
 action(view.delete.Activated,function()
  if not self:selected() then view:message("Select an object or starting zone, then click Delete.");return end
  self:perform(function() self.state:delete() end,"Deleted selection. Undo restores it.")
 end)
 action(view.placeStart.Activated,function()
  if #self.state.document.spawns>=5 then view:message("All five starts are placed. Select a marked area to move or delete it.");return end
  self:cancel();self.placingStart=true;view:message("Click clear ground to place the next numbered starting area. Each area holds three tanks; keep centers 40 studs apart. Esc cancels.")
 end)
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
 action(view.edgeSnap.Activated,function()self:setMode("Snap")end)
 action(view.snapContact.Activated,function()
  self:cancel();self.fitMode=if self.fitMode=="Stretch" then "Scale" else "Stretch";self:refresh()
 end)
 action(view.pinA.Activated,function()self:pinHere("A")end)
 action(view.pinB.Activated,function()self:pinHere("B")end)
 action(view.releasePin.Activated,function()
  local entry=self:selected();if not entry then return end
  self:perform(function()self.state.pins[entry.id]=nil end,"Released endpoint pins.")
 end)
 for key,field in view.fields do action(field.FocusLost,function()
  local entry=self:selected();if not entry then return end
  local n=tonumber(field.Text)
  self:perform(function()
   assert(n and n==n and math.abs(n)<math.huge,"Enter a finite number")
   if entry.slot then
    assert(key=="x" or key=="z" or key=="yaw","Starting areas stay on the ground; edit X, Z or yaw")
    if key=="yaw" then entry.heading=n else entry.position[if key=="x" then 1 else 3]=n end
    return
   end
   if key=="x" or key=="y" or key=="z" then self.state.pins[entry.id]=nil
   elseif self.state.pins[entry.id] and key~="hp" then self.state.pins[entry.id].second=nil end
   if key=="x" then entry.position[1]=n elseif key=="y" then entry.position[2]=n elseif key=="z" then entry.position[3]=n elseif key=="pitch" then entry.rotation[1]=n elseif key=="yaw" then entry.rotation[2]=n elseif key=="roll" then entry.rotation[3]=n elseif key=="scale" then entry.scale=n else entry.hp=n end
  end,"Updated "..key)
 end) end
 action(view.solid.Activated,function() local o=self:selected();if o and not o.slot then self:perform(function() o.solid=not o.solid end,"Collision updated.") end end)
 action(view.destructible.Activated,function() local o=self:selected();if o and not o.slot then self:perform(function() o.destructible=not o.destructible end,"Destructibility updated.") end end)
 action(view.export.Activated,function()
  self:cancel();view.name.Text=self.state.document.name;view.worldId.Text=self.state.document.id
  view.overlay.Visible=true;self:export()
 end)
 action(view.generate.Activated,function() self:export() end)
 action(view.import.Activated,function() self:import() end)
 action(view.worlds.Activated,function() self:cancel();self.library:open(self.state.document) end)
 return self
end
function Controller:replaceDocument(document)
 self:cancel()
 document=Document.numberStarts(State.copy(document))
 local candidate
 local ok,reason=pcall(function()
  candidate=Scene.new(self.view.viewport,self.context.editorAssets,document)
  candidate:sync(document,self.catalog)
 end)
 if not ok then
  if candidate then candidate:destroy() end
  if self.scene then self.view.viewport.CurrentCamera=self.scene.camera end
  error(reason,0)
 end
 if self.scene then self.scene:destroy() end
 self.scene=candidate;self.state=State.new(document);self.state.snap=false
 self.view.name.Text=document.name;self.view.worldId.Text=document.id
 self:frameWorld();self:refresh();self:updateGrid();self:setMode(self.mode)
end
function Controller:import()
 local ok,reason=pcall(function()
  assert(#self.view.json.Text<=260000,"Import exceeds 260 KB")
  local document=Http:JSONDecode(self.view.json.Text)
  require(Shared.WorldSettings).validate({width=document.settings.width,depth=document.settings.depth,ground=document.settings.ground,boundary=document.settings.boundary,spawns=document.spawns,zones={}},true)
  document=Document.export(document,self.catalog)
  for _,entry in document.objects do assert(self.catalog.byPath[entry.asset].available,"An imported asset is unavailable in this game") end
  self:replaceDocument(document)
  self.library.revisions[document.id]=nil
  self.view.overlay.Visible=false
 end)
 local message=tostring(reason):gsub("^.-:%d+:%s*","")
 self.view:message(if ok then "Imported backup. Use My Worlds / Save to make it durable; change World ID for a separate copy." else "Import blocked: "..message)
end
function Controller:loadCatalog()
 local context=self.context
 if not context.editorAssets and context.getEditorAssets then context.editorAssets=context.getEditorAssets() end
 if not context.editorAssets then return false end
 local data=context.editorAssets:FindFirstChild("Catalog")
 if not data then return false end
 local ok,items=pcall(function() return require(Shared.CatalogData).decode(data,Http,true) end)
 if ok then self.catalog=Document.catalog(items) else self.view:message("Catalog could not be read: "..tostring(items)) end
 return ok
end
function Controller:selected()
 for id in self.state.selection do return self.state:find(id) end
end
function Controller:refresh()
 self.view.placeStart.Text="Place start zone  •  "..#self.state.document.spawns.."/5"
 if self.scene then self.scene:sync(self.state.document,self.catalog) end
 local selected=self:selected();self.view:selection(selected,selected and self.catalog.byPath[selected.asset])
 if self.scene then self.scene:selection(selected and selected.id,self.distance) end
 self:updateSnap()
 self.view.undo.Text="Undo ("..#self.state.past..")";self.view.redo.Text="Redo ("..#self.state.future..")"
end
local function copyPose(entry,pose)
 entry.position=State.copy(pose.position);entry.rotation=State.copy(pose.rotation);entry.scale=pose.scale
 entry.stretch=State.copy(pose.stretch)
end
function Controller:updateSnap()
 local entry=self:selected();local pin=entry and self.state.pins[entry.id]
 local side=if pin then pin.side else (self.snapPreview and self.snapPreview.side) or self.snapSide or 0
 self.view.edgeSnap.Text="Snap tool  •  4"
 self.view.snapContact.Text=if self.fitMode=="Stretch" then "Scale / [Stretch]" else "[Scale] / Stretch"
 self.view.pinStatus.Text=if self.fitMode=="Stretch" then "Drag one of four side handles. Opposite side stays fixed. Stretch preserves thickness and the other dimension. Native blocks only." else "Drag one of four side handles onto an edge. Opposite side stays fixed. Scale resizes all dimensions. Move moves the whole piece."
 if self.scene then self.scene:setSnap(self.edgeSnap,self.state.pins,side);self.scene:selection(entry and entry.id,self.distance) end
end
function Controller:pinHere(endpoint)
 local entry=self:selected();if not entry then self.view:message("Select an object first.");return end
 if self.state.pins[entry.id] then self.view:message("Release the existing pin before choosing a different fixed end.");return end
 local item=self.catalog.byPath[entry.asset]
 if item.zone then self.view:message("Water/mud regions stay on the ground and cannot be pinned.");return end
 local ends,box=Snap.ends(entry,self.snapSide);self.edgeSnap=true
 self:perform(function()
  self.state.pins[entry.id]=Snap.pin(endpoint,{point={ends[endpoint].X,ends[endpoint].Y,ends[endpoint].Z},normal={box.up.X,box.up.Y,box.up.Z},kind="position"},self.snapSide)
 end,"Pinned end "..endpoint.." at its current position. Drag the other end onto a platform or ground.")
end
function Controller:reconcilePins(before)
 local previous={};for _,entry in before.objects do previous[entry.id]=entry end
 for id,pin in self.state.pins do
  local entry=self.state:find(id)
  if not entry then self.state.pins[id]=nil
  elseif pin.second then
   local old=previous[id]
   if old then
    assert(entry.scale==old.scale,"Both endpoints are fitted. Release pins before resizing")
    for i=1,3 do assert(entry.position[i]==old.position[i] and entry.rotation[i]==old.rotation[i],"Both endpoints are fitted. Release pins before transforming") end
   end
  else Snap.anchor(entry,pin) end
 end
end
function Controller:perform(fn,message)
 self:cancel()
 local before=self.state:snapshot();local past,future=table.clone(self.state.past),table.clone(self.state.future)
 local ok,err=pcall(function() fn();self:reconcilePins(before.document);Document.export(self.state.document,self.catalog) end)
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
 self.edgeSnap=mode=="Snap"
 if self.scene then
  self.scene:setMode(mode,self.rotationAxis or "Yaw")
  local selected=self:selected();self.scene:selection(selected and selected.id,self.distance)
 end
 for axis,button in self.view.rotationAxes do button.BackgroundColor3=if axis==(self.rotationAxis or "Yaw") then Color3.fromRGB(133,94,38) else Color3.fromRGB(43,61,66) end
 for name,button in self.view.tools do button.BackgroundColor3=if name==mode then Color3.fromRGB(133,94,38) else Color3.fromRGB(43,61,66) end
 self:updateSnap()
 self.view:message(if mode=="Move" then "Move • red X / blue Z slides; green Y raises or lowers. Height Y also accepts an exact value." elseif mode=="Rotate" then "Rotate • choose local X, Y or Z on the left, then drag the ring. Axes follow the object; grid snaps the turn to 15°." elseif mode=="Snap" then "Snap • drag any of the four side handles onto a surface edge. Choose Scale or Stretch on the left." else "Scale • drag the green anchor to resize uniformly.")
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
 if self.placingStart and point then
  self:perform(function()self.state:addStart(point)end,"Starting area placed. Drag it to move; set yaw to change facing.")
  return
 end
 if not self.placing or not point then return end
 local item=self.placing
 local valid,reason=pcall(Document.checkEntry,self.state.document,self.catalog,self:candidate(point))
 if not valid then self.view:message(reason);return end
 self:perform(function() self.state:add(item,{point.X,0,point.Z},item.size) end,"Placed "..item.model..". Drag the object to move it.")
end
function Controller:cancel()
 if self.gesture then self.state:restore(self.gesture.before);self.gesture=nil;if self.scene then self.scene:sync(self.state.document,self.catalog) end end
 self.placing=nil;self.placingStart=nil;self.paletteDrag=nil;self:stopCamera()
 self.snapPreview=nil
 if self.scene then self.scene:snapFeedback(nil);self.scene:setSnap(self.edgeSnap,self.state.pins,self.snapSide) end
 if self.scene then self.scene:clearGhost();self.scene:startPreview(nil) end
end
function Controller:finishGesture(cancel)
 local g=self.gesture;if not g then return end
 self.gesture=nil
 local ok,err=pcall(function()
  local preview=self.snapPreview
  if g.kind=="Snap" then assert(preview and preview.valid,"No valid snap target; previous pose restored") end
  if preview and preview.valid then
   local pin=if g.kind=="Snap" then State.copy(g.pin) else self.state.pins[g.id]
   if g.kind=="Snap" then self.state.pins[g.id]=pin end
   if pin then pin.second=Snap.pin(preview.endpoint,preview.target,pin.side)
   else self.state.pins[g.id]=Snap.pin(preview.endpoint,preview.target,preview.side) end
  end
  Document.export(self.state.document,self.catalog)
 end)
 if cancel or not ok then self.state:restore(g.before) else self.state:record(g.before) end
 self.snapPreview=nil;if self.scene then self.scene:snapFeedback(nil) end
 self:refresh();self.view:message(if cancel then "Transform canceled." elseif ok then "Transform applied." else tostring(err))
end
function Controller:beginSnap(endpoint,entry)
 local pin=self.state.pins[entry.id]
 if self.catalog.byPath[entry.asset].zone then self.view:message("Ground regions cannot be fitted.");return end
 local side=0
 local opposite=Snap.opposite(endpoint)
 if self.fitMode=="Stretch" and not self.catalog.byPath[entry.asset].stretchable then self.fitMode="Scale" end
 local ends,box=Snap.ends(entry,side)
 local fixed=if pin and pin.endpoint==opposite then State.copy(pin) elseif pin and pin.second and pin.second.endpoint==opposite then State.copy(pin.second) else Snap.pin(opposite,{point={ends[opposite].X,ends[opposite].Y,ends[opposite].Z},normal={box.up.X,box.up.Y,box.up.Z},kind="position"},side)
 fixed.second=nil
 self.edgeSnap=true
 self.gesture={kind="Snap",endpoint=endpoint,id=entry.id,before=self.state:snapshot(),base=State.copy(entry),pin=fixed,side=side,startPoint=ends[endpoint]}
 self.state.pins[entry.id]=State.copy(fixed)
 self.snapPreview=nil;self:updateSnap()
 self.view:message("Drag this end; the opposite end stays fixed. Release to hold the fit. Esc cancels.")
end
function Controller:stopCamera()
 local drag=self.cameraDrag
 if drag then UIS.MouseBehavior=drag.behavior;UIS.MouseIconEnabled=drag.icon end
 self.cameraDrag=nil;self.cameraDelta=Vector2.zero
end
function Controller:beginCamera(input)
 if self.cameraDrag then return self.cameraDrag.button==input.UserInputType end
 if not self.active or not self.scene or self.paused or UIS:GetFocusedTextBox() or self.view:isModal() or not self.view:isScene(self:mousePosition()) then return false end
 local button=input.UserInputType
 if button~=Enum.UserInputType.MouseButton2 and button~=Enum.UserInputType.MouseButton3 then return false end
 if self.gesture then self:finishGesture(true) end
 self.cameraDrag={button=button,behavior=UIS.MouseBehavior,icon=UIS.MouseIconEnabled}
 self.cameraDelta=Vector2.zero
 UIS.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition;UIS.MouseIconEnabled=false
 return true
end
function Controller:cameraAction(_,state,input)
 if state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then
  if self.cameraDrag and self.cameraDrag.button==input.UserInputType then self:stopCamera();return Enum.ContextActionResult.Sink end
 elseif state==Enum.UserInputState.Begin then
  if self:beginCamera(input) then return Enum.ContextActionResult.Sink end
 elseif self.cameraDrag and self.cameraDrag.button==input.UserInputType then return Enum.ContextActionResult.Sink end
 return Enum.ContextActionResult.Pass
end
function Controller:begin(input,processed)
 if self.paused or UIS:GetFocusedTextBox() or self.view:isModal() then return end
 if self.cameraDrag then return end
 if input.UserInputType==Enum.UserInputType.MouseButton2 or input.UserInputType==Enum.UserInputType.MouseButton3 then
  if not processed then self:beginCamera(input) end
  return
 end
 local point,origin,direction,mouse=self:pointer()
 if not origin or not direction or not self.view:isScene(mouse) then return end
 if processed then return end
 if processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
 if self.placing or self.placingStart then self:place(point);return end
 local id,handle=self.scene:pick(origin,direction,mouse-self.view.viewport.AbsolutePosition,self.view.viewport.AbsoluteSize)
 if id then self.state:select(id);self:refresh() end
 local entry=self:selected()
 if entry and entry.slot then
  local start=Math.ground(origin,direction)
  if (id or handle) and start then self:setMode("Move");self.gesture={kind="StartMove",id=entry.id,before=self.state:snapshot(),base=State.copy(entry),start=start,axis=handle} end
  return
 end
 if entry and handle and handle:match("^Snap[ABCD]$") then self:beginSnap(handle:sub(-1),entry);return end
 if entry and (handle or (id and self.mode=="Move")) then
  local kind=handle or "Move"
  local pin=self.state.pins[entry.id]
  local before=self.state:snapshot()
  if kind:sub(1,4)=="Move" then pin=nil end
  if pin then pin=State.copy(pin);pin.second=nil end
  local pivot=if pin then Vector3.new(table.unpack(pin.point)) elseif kind:sub(1,6)=="Rotate" then Visual.measure(self.scene.models[entry.id].model).Position else nil
  local start=Math.dragPoint(kind,entry,origin,direction,self.scene.camera.CFrame,pivot)
  if not start then self.view:message("Orbit the camera slightly to face this rotation ring, then drag again.");return end
  self.state.pins[entry.id]=State.copy(pin)
  self.gesture={before=before,base=State.copy(entry),id=entry.id,start=start,kind=kind,pivot=pivot,pin=State.copy(pin)}
 elseif not id and not handle then self.state.selection={};self:refresh() end
end
function Controller:key(input,processed)
 if self.paused or processed or UIS:GetFocusedTextBox() or self.view:isModal() then return end
 self.keys[input.KeyCode]=true
 local control=UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) or UIS:IsKeyDown(Enum.KeyCode.LeftMeta) or UIS:IsKeyDown(Enum.KeyCode.RightMeta)
 local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
 if input.KeyCode==Enum.KeyCode.Q and self.cameraDrag then return end
 if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.Q then self:cancel();self:refresh()
 elseif control and input.KeyCode==Enum.KeyCode.Z then self:history(shift)
 elseif control and input.KeyCode==Enum.KeyCode.Y then self:history(true)
 elseif control and input.KeyCode==Enum.KeyCode.D then self:perform(function() self.state:duplicate() end,"Duplicated selection.")
 elseif input.KeyCode==Enum.KeyCode.Delete or input.KeyCode==Enum.KeyCode.Backspace then self:perform(function() self.state:delete() end,"Deleted selection.")
 elseif input.KeyCode==Enum.KeyCode.One then self:setMode("Move") elseif input.KeyCode==Enum.KeyCode.Two then self:setMode("Rotate")
 elseif input.KeyCode==Enum.KeyCode.Three then self:setMode("Scale")
 elseif input.KeyCode==Enum.KeyCode.Four then self:setMode("Snap")
 elseif input.KeyCode==Enum.KeyCode.G then self.state.snap=not self.state.snap;self:updateGrid()
 elseif input.KeyCode==Enum.KeyCode.F then self:frameWorld() end
end
function Controller:step(dt)
 local scene=self.scene;if not scene then return end
 local mouse=self:mousePosition()
 if self.cameraDrag then
  UIS.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
  local delta=self.cameraDelta;self.cameraDelta=Vector2.zero
  local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
  if self.cameraDrag.button==Enum.UserInputType.MouseButton3 or shift then
   self.focus+=Math.cameraPan(scene.camera.CFrame,self.view.viewport.AbsoluteSize,delta,self.distance,scene.camera.FieldOfView)
   self.focus=Vector3.new(self.focus.X,math.max(0,self.focus.Y),self.focus.Z)
  else self.yaw-=delta.X*.006;self.pitch+=delta.Y*.004 end
 end
 if not self.paused and not UIS:GetFocusedTextBox() and not self.gesture and (not self.placing or self.cameraDrag) and not self.view:isModal() then
  local forward=(if self.keys[Enum.KeyCode.W] then 1 else 0)-(if self.keys[Enum.KeyCode.S] then 1 else 0)
  local right=(if self.keys[Enum.KeyCode.D] then 1 else 0)-(if self.keys[Enum.KeyCode.A] then 1 else 0)
  if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then forward=0;right=0 end
  self.focus+=(Vector3.new(-math.sin(self.yaw),0,-math.cos(self.yaw))*forward+Vector3.new(math.cos(self.yaw),0,-math.sin(self.yaw))*right)*self.distance*math.min(dt,.1)*.6
  if self.cameraDrag then
   local vertical=(if self.keys[Enum.KeyCode.E] then 1 else 0)-(if self.keys[Enum.KeyCode.Q] then 1 else 0)
   self.focus=Vector3.new(self.focus.X,math.max(0,self.focus.Y+vertical*self.distance*math.min(dt,.1)*.6),self.focus.Z)
  end
 end
 self.pitch=Math.cameraPitch(self.pitch,self.focus.Y,self.distance)
 scene.camera.CFrame=CFrame.lookAt(self.focus+Vector3.new(math.sin(self.yaw)*math.cos(self.pitch),math.sin(self.pitch),math.cos(self.yaw)*math.cos(self.pitch))*self.distance,self.focus)
 local point,origin,direction=self:pointer()
 if self.placingStart and point and self.view:isScene(mouse) then
  local used={};for _,p in self.state.document.spawns do used[p.slot]=true end
  local slot=1;while used[slot] do slot+=1 end
  local spawn={id="start_"..slot,slot=slot,position={self.state:snapValue(point.X),0,self.state:snapValue(point.Z)},heading=0}
  local draft=State.copy(self.state.document);table.insert(draft.spawns,spawn)
  local valid,reason=pcall(Document.export,draft,self.catalog)
  scene:startPreview(spawn,valid);self.view:message(if valid then "Click to place player "..slot.." starting area • three tanks" else tostring(reason))
 else scene:startPreview(nil) end
 if self.gesture then
  local g=self.gesture;local entry=self.state:find(g.id)
  self.snapPreview=nil
  if g.kind=="StartMove" then
   if point then entry.position={if g.axis=="MoveZ" then g.base.position[1] else self.state:snapValue(g.base.position[1]+point.X-g.start.X),0,if g.axis=="MoveX" then g.base.position[3] else self.state:snapValue(g.base.position[3]+point.Z-g.start.Z)} end
  elseif g.kind=="Snap" then
   copyPose(entry,g.base)
   local target=if origin and direction and self.view:isScene(mouse) then scene:snapTarget(origin,direction,g.id,g.target) else nil
   if not target and origin and direction and self.view:isScene(mouse) then
    -- Away from surfaces, drag in a screen-facing plane through the grabbed end.
    local n=scene.camera.CFrame.LookVector
    local d=direction.X*n.X+direction.Y*n.Y+direction.Z*n.Z
    local offset=g.startPoint-origin
    local t=if math.abs(d)>.00001 then (offset.X*n.X+offset.Y*n.Y+offset.Z*n.Z)/d else -1
    if t>0 then
     local p=origin+direction*t
     target={point={p.X,p.Y,p.Z},normal={0,1,0},kind="position"}
    end
   end
   g.target=target
   if target then
    local ok,pose=pcall(function()
     if g.pin then return Snap.fit(g.base,g.endpoint,target,g.pin,self.fitMode) end
     return Snap.anchor(State.copy(g.base),Snap.pin(g.endpoint,target,g.side))
    end)
    if ok then copyPose(entry,pose) end
    local valid,reason=pcall(Document.checkEntry,self.state.document,self.catalog,entry)
    self.snapPreview={endpoint=g.endpoint,target=target,valid=ok and valid,side=g.side}
    self.view:message(if not ok then tostring(pose) elseif not valid then tostring(reason) else "Release to hold this side • "..target.kind.." • "..(self.fitMode or "Scale"))
   end
  else
   local drag=Math.dragPoint(g.kind,g.base,origin,direction,scene.camera.CFrame,g.pivot)
   if drag then
    local transform=Math.transform(g.base,g.kind,g.start,drag,self.state.snap,self.state.grid,g.pivot)
    copyPose(entry,transform)
    if g.pin then Snap.anchor(entry,g.pin) end
    if self.edgeSnap and self.view:isScene(mouse) then
     local free=if g.pin then Snap.opposite(g.pin.endpoint) else nil
     local near=Snap.nearby(self.state.document,entry,free,g.pin and g.pin.side)
     if near then
      local ok,pose=pcall(function()
       if g.pin then return Snap.fit(entry,near.endpoint,near.target,g.pin) end
       return Snap.anchor(State.copy(entry),Snap.pin(near.endpoint,near.target,near.side))
      end)
      if ok then copyPose(entry,pose) end
      local valid=pcall(Document.checkEntry,self.state.document,self.catalog,entry)
      self.snapPreview={endpoint=near.endpoint,target=near.target,valid=ok and valid,side=near.side}
     end
    end
   end
  end
  scene:sync(self.state.document,self.catalog)
  scene:snapFeedback(self.snapPreview and self.snapPreview.target,not self.snapPreview or self.snapPreview.valid)
 end
 if self.placing and point and self.view:isScene(mouse) then
  local candidate=self:candidate(point)
  local ok,err=pcall(Document.checkEntry,self.state.document,self.catalog,candidate)
  scene:ghost(candidate,self.placing,ok)
  self.view:message(if ok then self.placing.model.." • release / click to place" else tostring(err))
 else scene:clearGhost() end
 local selected=self:selected();self:updateSnap()
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
 Actions:BindActionAtPriority("BattleWorksEditorCamera",function(...)return self:cameraAction(...)end,false,3000,Enum.UserInputType.MouseButton2,Enum.UserInputType.MouseButton3)
 -- Viewport-local delivery also works when UI marks the global event processed.
 connect(self.view.viewport.InputBegan,function(input) self:beginCamera(input) end)
 connect(UIS.InputBegan,function(input,processed)
  if input.UserInputType==Enum.UserInputType.Keyboard then self:key(input,processed) elseif self.scene then self:begin(input,processed) end
 end)
 connect(UIS.InputEnded,function(input)
  self.keys[input.KeyCode]=nil
  if self.cameraDrag and self.cameraDrag.button==input.UserInputType then self:stopCamera() end
  if input.UserInputType==Enum.UserInputType.MouseButton1 then
   local point,_,_,mouse=self:pointer()
   if self.cameraDrag then self.paletteDrag=nil;return end
   if self.paused then self:cancel();return end
   if self.paletteDrag then
    local start=self.paletteDrag;self.paletteDrag=nil
    if point and (mouse-start).Magnitude>6 and self.view:isScene(mouse) then self:place(point) end
   elseif self.gesture then self:finishGesture(false) end
  end
 end)
 connect(UIS.InputChanged,function(input)
  if self.cameraDrag and input.UserInputType==Enum.UserInputType.MouseMovement then
   self.cameraDelta+=Vector2.new(input.Delta.X,input.Delta.Y)
  end
  if input.UserInputType==Enum.UserInputType.MouseWheel and not self.paused and not UIS:GetFocusedTextBox() and not self.view:isModal() and self.view:isScene(self:mousePosition()) then self.distance=math.clamp(self.distance*math.exp(-input.Position.Z*.12),20,1600) end
 end)
 connect(UIS.WindowFocusReleased,function() self:cancel();self.keys={};self:refresh() end)
 connect(UIS.TextBoxFocused,function() self:stopCamera();self.keys={} end)
 local gui=game:GetService("GuiService")
 connect(gui.MenuOpened,function() self.paused=true;self:cancel();self.keys={} end)
 connect(gui.MenuClosed,function() self.paused=false end)
 if self.scene then connect(Run.RenderStepped,function(dt) self:step(dt) end) end
end
function Controller:exit()
 self.library:hide()
 self:cancel();self.active=false;self.frame.Visible=false;self.keys={}
 Actions:UnbindAction("BattleWorksEditorCamera")
 for _,connection in self.runtime do connection:Disconnect() end;self.runtime={}
 local focused=UIS:GetFocusedTextBox();if focused then focused:ReleaseFocus() end
 if self.scene then self.scene:destroy();self.scene=nil end
end
function Controller:moveFocus() game:GetService("GuiService").SelectedObject=self.view.back end
function Controller:activateSelected() self.context.home() end
function Controller:destroy() self:exit();self.view:destroy() end
return Controller

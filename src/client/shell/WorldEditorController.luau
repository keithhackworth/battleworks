local Shared=game.ReplicatedStorage.Shared
local State=require(Shared.WorldEditorState)
local Document=require(Shared.WorldEditorDocument)
local Math=require(Shared.WorldEditorMath)
local Snap=require(Shared.WorldEditorSnap)
local Visual=require(Shared.AssetGeometry)
local Placement=require(Shared.ModelPlacement)
local Motion=require(Shared.WorldMotion)
local Audio=require(Shared.WorldSound)
local Catalog=require(Shared.CatalogData)
local Attachment=require(Shared.AssetAttachment)
local Tunnel=require(Shared.WorldTunnel)
local Heightfield=require(Shared.WorldHeightfield)
local Materials=require(Shared.TerrainMaterials)
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
 self.state.snap=false;self.assetScales={};self.cameraSensitivity=1;self.recentAssets={}
 self.brush={operation="Raise",radius=26,strength=24,falloff=.65,elevation=0,depth=4}
 self.library=require(script.Parent.WorldLibrary).new(view.frame,context.worldRequest,function(document)
  self:replaceDocument(document)
  return self.state.document
 end,function() if self.active then (context.playWorld or context.join)() end end)
 view.library=self.library
 self:loadCatalog()
 local function action(event,fn) view:on(event,function(...) if self.active then fn(...) end end) end
 for mode,button in view.tools do action(button.Activated,function() self:setMode(mode) end) end
 action(view.terrain.Activated,function() self:setMode(if self.mode=="Terrain" then "Move" else "Terrain") end)
 local tankWidth,tankLength=Scene.buildTankScale(view.tankScaleViewport)
 view.tankScaleSize.Text=string.format("%g × %g studs",tankWidth,tankLength)
 self.traversability=true
 view.traversability.BackgroundColor3=View.activeColor
 view.traversalLegend.Visible=true
 action(view.traversability.Activated,function()
  self.traversability=not self.traversability
  view.traversability.BackgroundColor3=if self.traversability then View.activeColor else View.buttonColor
  view.traversalLegend.Visible=self.traversability
  self:refresh()
 end)
 for operation,control in view.terrainTools do
  action(control.Activated,function()
   self:finishTerrain(false);self.brush.operation=operation;self:setMode("Terrain")
  end)
 end
 for operation,control in view.surfaceTools do
  action(control.Activated,function()
   self:finishTerrain(false);self.brush.operation=operation;self:setMode("Terrain")
   if operation=="Tunnel" then self:refreshTunnel();view:message("Click or tap two portals to build a straight tunnel.")
   elseif operation=="Water" then view:message("Click a channel or basin to route water downhill. Set fill depth in the inspector.")
   elseif operation=="Carve Ravine" then view:message("Drag to cut a channel. Radius sets width and depth sets the bed below your stroke's start.")
   else view:message("Drag to paint "..operation..". Radius sets the width.") end
  end)
 end
 action(view.tunnelNew.Activated,function()
  self.tunnelIndex=nil;self.tunnelStart=nil;self:refreshTunnel()
  view:message("Click or tap two portal positions.")
 end)
 action(view.tunnelNext.Activated,function()
  local list=self.state.document.settings.tunnels
  if list and #list>0 then
   self.tunnelStart=nil;self.tunnelIndex=(self.tunnelIndex or 0)%#list+1;self:refreshTunnel()
   view:message("Selected tunnel "..self.tunnelIndex.." of "..#list..".")
  end
 end)
 action(view.tunnelDelete.Activated,function()
  local index=self.tunnelIndex
  if not index then return end
  self.tunnelIndex=nil
  self:perform(function()
   local settings=self.state.document.settings
   local list=State.copy(settings.tunnels);table.remove(list,index)
   settings.tunnels=if #list>0 then list else nil
  end,"Tunnel removed.")
 end)
 for key,field in view.tunnelFields do action(field.FocusLost,function()
  local settings=self.state.document.settings
  local index=self.tunnelIndex
  local value=tonumber(field.Text)
  if not value then self:refreshTunnel();return end
  if index and settings.tunnels and settings.tunnels[index] then
   self:perform(function()
    local list=State.copy(settings.tunnels)
    local tunnel=list[index]
    if key=="start" then tunnel.a[2]=value elseif key=="finish" then tunnel.b[2]=value else tunnel[key]=value end
    settings.tunnels=list
   end,"Tunnel updated.")
  elseif key=="diameter" and value>=12 and value<=48 then self.tunnelDiameter=value
  elseif key=="traction" and value>=0 and value<=100 then self.tunnelTraction=value end
  self:refreshTunnel()
 end) end
 action(view.traction.FocusLost,function()
  local kind=self.brush.operation
  if not Materials.TunableTraction[kind] then return end
  local raw=view.traction.Text
  local default=Materials.defaultTraction(kind)
  local percent=if raw:match("^%s*$") then default else tonumber(raw)
  if not percent or percent~=percent or percent<0 or percent>100 then
   self:refreshTraction();view:message("Enter traction from 0 to 100% of pavement, or clear it to restore the default.");return
  end
  self:perform(function()
   local settings=self.state.document.settings
   if not settings.terrain and percent==default then return end
   local field=if settings.terrain then table.clone(settings.terrain) else Heightfield.new(settings.width,settings.depth)
   local values=table.clone(field.traction or {})
   values[kind]=if percent==default then nil else percent
   field.traction=if next(values) then values else nil
   settings.terrain=field
  end,string.format("%s traction set to %.4g%% of pavement.",kind,percent))
 end)
 local bounds={radius={2,160},strength={.5,96},falloff={0,1},elevation={Heightfield.MinHeight,Heightfield.MaxHeight},depth={.25,32}}
 for key,field in view.brushFields do
  action(field.FocusLost,function()
   local value=tonumber(field.Text);local range=bounds[key]
   if value and value>=range[1] and value<=range[2] then self.brush[key]=value
   else view:message(string.format("Enter a value from %g to %g.",range[1],range[2])) end
   field.Text=tostring(self.brush[key])
  end)
 end
 for axis,button in view.rotationAxes do action(button.Activated,function() self.rotationAxis=axis;self:setMode("Rotate") end) end
 action(view.undo.Activated,function() self:history(false) end);action(view.redo.Activated,function() self:history(true) end)
 action(view.newWorld.Activated,function()
  if self:perform(function()
   self.state.document=Document.editorFresh()
   self.state.document.id="world_"..Http:GenerateGUID(false):gsub("-","")
   self.state.selection={};self.state.pins={}
  end,"New world. Undo restores the previous draft.") then self:frameWorld() end
 end)
 action(view.openWorld.Activated,function() self:cancel();self.library:open(self.state.document) end)
 action(view.openPlayground.Activated,function()
  self:cancel()
  self.library:open(self.state.document,"playground")
 end)
 action(view.saveWorld.Activated,function() self:cancel();self.library:open(self.state.document,"save") end)
 action(view.saveAs.Activated,function() self:cancel();self.library:open(self.state.document,"copy") end)
 for axis,field in view.dimensions do action(field.FocusLost,function()
  local value=tonumber(field.Text)
  if value~=self.state.document.settings[axis] then
   if self:perform(function()
    assert(value and value%1==0 and value>=25 and value<=2000,"Use a whole number from 25 to 2000 studs.")
    local settings=self.state.document.settings
    local width,depth=settings.width,settings.depth
    settings[axis]=value
    if settings.terrain then
     settings.terrain=Heightfield.resize(settings.terrain,width,depth,settings.width,settings.depth)
    end
   end,"World resized. Undo restores the previous size and terrain.") then self:frameWorld() end
  end
 end) end
 action(view.cameraSensitivity.FocusLost,function()
  local value=tonumber(view.cameraSensitivity.Text)
  if value and value>=.2 and value<=3 then self.cameraSensitivity=value
  else view:message("Camera sensitivity must be between 0.2 and 3.") end
  view.cameraSensitivity.Text=tostring(self.cameraSensitivity)
 end)
 action(view.duplicate.Activated,function() self:perform(function() self.state:duplicate() end,"Duplicated selection. Drag the new object to move it.") end)
 action(view.repeatPlacement.Activated,function()
  self.repeatPlacement=not self.repeatPlacement
  view.repeatPlacement.Text=if self.repeatPlacement then "Repeat: On" else "Repeat: Off"
 end)
 action(view.recentAssets.Activated,function()
  self.showRecent=not self.showRecent;self.page=1;self:browse()
 end)
 action(view.copyScale.Activated,function()
  local entry=self:selected();if not entry or entry.slot then return end
  self.copiedScale=entry.scale;view:message("Copied uniform scale. Select another object to apply it.")
 end)
 action(view.pasteScale.Activated,function()
  local entry=self:selected();if not entry or entry.slot or not self.copiedScale then return end
  if self:perform(function() entry.scale=self.copiedScale end,"Applied copied scale.") then self.assetScales[entry.asset]=entry.scale end
 end)
 action(view.delete.Activated,function()
  if not self:selected() then view:message("Select an object or starting zone, then click Delete.");return end
  self:perform(function() self.state:delete() end,"Deleted selection. Undo restores it.")
 end)
 action(view.placeStart.Activated,function()
  if #self.state.document.spawns>=5 then view:message("All five starts are placed. Select a marked area to move or delete it.");return end
  self:cancel();self.placingStart=true;view:message("Click clear ground to place the next numbered starting area. Each area holds three tanks; keep centers 40 studs apart. Esc cancels.")
 end)
 action(view.up.Activated,function()
  if self.showRecent then self.showRecent=false else self.prefix=self.prefix:gsub("[^/]+/$","") end
  self.page=1;self:browse()
 end)
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
  self:perform(function()self:clearContacts(entry.id) end,"Released endpoint pins.")
 end)
 for key,field in view.fields do action(field.FocusLost,function()
  local entry=self:selected();if not entry then return end
  local n=tonumber(field.Text)
  local changed=self:perform(function()
   assert(n and n==n and math.abs(n)<math.huge,"Enter a finite number")
   if entry.slot then
    assert(key=="x" or key=="z" or key=="yaw","Starting areas stay on the ground; edit X, Z or yaw")
    if key=="yaw" then entry.heading=n else entry.position[if key=="x" then 1 else 3]=n end
    return
   end
   if key~="hp" then self:clearContacts(entry.id) end
   local axis=({sizeX=1,sizeY=2,sizeZ=3})[key]
   if axis then
    entry.stretch=entry.stretch or {1,1,1}
    entry.stretch[axis]=n/(entry.bounds[axis]*entry.scale)
   elseif key=="x" then entry.position[1]=n elseif key=="y" then entry.position[2]=n elseif key=="z" then entry.position[3]=n elseif key=="pitch" then entry.rotation[1]=n elseif key=="yaw" then entry.rotation[2]=n elseif key=="roll" then entry.rotation[3]=n elseif key=="scale" then entry.scale=n else entry.hp=n end
   if axis or key=="scale" then self:checkResizeSize(entry) end
  end,"Updated "..key)
  if changed and key=="scale" then self.assetScales[entry.asset]=entry.scale end
 end) end
 action(view.motionDraw.Activated,function() self:toggleMotionDraw() end)
 local modes={activation=Audio.Modes,playback=Audio.Playback,rollOff=Audio.RollOff,filter=Audio.Filters,origin=Audio.Origins}
 for key,values in modes do action(view.soundButtons[key].Activated,function()
  local entry=self:selected()
  if not entry or not entry.sound then return end
  self:perform(function()
   local index=table.find(values,entry.sound[key] or Audio.Default[key]) or 1
   entry.sound[key]=values[index%#values+1]
  end,"Sound Block updated.")
 end) end
 for key,row in view.soundFields do action(row.field.FocusLost,function()
  local entry=self:selected();local value=tonumber(row.field.Text)
  if not entry or not entry.sound then return end
  if not value then self:refresh();return end
  self:perform(function() entry.sound[key]=value end,"Sound Block updated.")
 end) end
 action(view.soundButtons.effect.Activated,function() self:openSoundPicker("effect") end)
 action(view.soundButtons.targets.Activated,function() self:openSoundPicker("targets") end)
 action(view.sfxClose.Activated,function() self:closeSoundPicker() end)
 action(view.sfxSearch:GetPropertyChangedSignal("Text"),function() if self.soundPicker then self:showSoundPicker() end end)
 action(view.soundButtons.preview.Activated,function()
  local entry=self:selected()
  if self.soundPreview then self:stopSoundPreview()
  elseif entry and entry.sound then self:playSoundPreview(self.sfxByKey[entry.sound.effect],entry.sound) end
 end)
 action(view.soundButtons.attach.Activated,function() self:toggleAttachment() end)
 action(view.spinToggle.Activated,function()
  local entry=self:motionEntry()
  if entry then self:perform(function()
   if entry.spin then entry.spin=nil else entry.spin={axis={0,1,0},speed=30,pause=0,space="local"} end
  end,"Rotation updated.") end
 end)
 action(view.spinSpace.Activated,function()
  local entry=self:motionEntry()
  if entry and entry.spin then self:perform(function()
   entry.spin.space=if entry.spin.space=="local" then "world" else "local"
  end,"Rotation axis space updated.") end
 end)
 action(view.spinMode.Activated,function()
  local entry=self:motionEntry()
  if entry and entry.spin then self:perform(function()
   entry.spin.swing=if entry.spin.swing then nil else 90
  end,"Rotation mode updated.") end
 end)
 for key,row in view.spinFields do action(row.field.FocusLost,function()
  local entry=self:motionEntry()
  local value=tonumber(row.field.Text)
  if not entry or not entry.spin or not value then self:refresh();return end
  self:perform(function()
   local axis=({x=1,y=2,z=3})[key]
   if axis then entry.spin.axis[axis]=value else entry.spin[key]=value end
  end,"Rotation updated.")
 end) end
 action(view.motionPreview.Activated,function() self:toggleMotionPreview() end)
 action(view.motionRemove.Activated,function()
  local entry=self:selected()
  if entry and entry.motion then
   self:cancel()
   self:perform(function() entry.motion=nil end,"Removed motion path.")
  end
 end)
 action(view.motionPoint.Activated,function()
  if not self.motionDraft or not self.motionPoint then return end
  table.remove(self.motionDraft.points,self.motionPoint);self.motionPoint=nil
  self:drawMotion()
 end)
 for axis,row in view.waypointFields do
  action(row.field.FocusLost,function()
   local entry=self:motionEntry()
   local motion,index=self.motionDraft,self.motionPoint
   local coordinate=tonumber(row.field.Text)
   if entry and motion and index and coordinate and coordinate>=-2000 and coordinate<=2000 then
    local points=motion.points
    local closed=Motion.closed(points)
    local offset=coordinate-entry.position[axis]
    points[index][axis]=offset
    if closed and (index==1 or index==#points) then points[1][axis]=offset;points[#points][axis]=offset end
   end
   self:drawMotion()
  end)
 end
 for _,key in {"face","enabled"} do
  local button=if key=="face" then view.motionFace else view.motionEnable
  action(button.Activated,function() self:updateMotionProperty(key) end)
 end
 for key,row in view.motionFields do
  action(row.field.FocusLost,function() self:updateMotionProperty(key,tonumber(row.field.Text)) end)
 end
 action(view.solid.Activated,function() local o=self:selected();if o and not o.slot and not o.sound then self:perform(function() o.solid=not o.solid end,"Collision updated.") end end)
 action(view.regenerates.Activated,function()
  local entry=self:selected()
  if entry and entry.destructible then
   self:perform(function() entry.regenerates=entry.regenerates==false end,"Regeneration updated.")
  end
 end)
 action(view.assetTraction.FocusLost,function()
  local entry=self:selected()
  if not entry or not Document.canSetAssetTraction(self.catalog.byPath[entry.asset]) then return end
  local raw=view.assetTraction.Text
  local value=tonumber(raw)
  if not raw:match("^%s*$") and not (value and value>=0 and value<=100) then
   self:refresh();self.view:message("Enter asset traction from 0 to 100%, or clear it to use the material default.");return
  end
  self:perform(function() entry.traction=value end,"Asset traction updated. It applies when the asset is solid.")
 end)
 action(view.regenerationDelay.FocusLost,function()
  local entry=self:selected()
  if not entry or not entry.destructible or entry.regenerates==false then return end
  local delay=tonumber(view.regenerationDelay.Text)
  if not delay or not (delay>=0 and delay<=Document.MaxRegenerationDelay) then
   self:refresh();self.view:message("Enter a regeneration delay from 0 to 3600 seconds.");return
  end
  self:perform(function() entry.regenerationDelay=delay end,"Regeneration delay updated.")
 end)
 action(view.destructible.Activated,function() local o=self:selected();if o and not o.slot and not o.sound then self:perform(function() o.destructible=not o.destructible end,"Destructibility updated.") end end)
 action(view.export.Activated,function()
  self:cancel();view.name.Text=self.state.document.name;view.worldId.Text=self.state.document.id
  view.overlay.Visible=true;self:export()
 end)
 action(view.generate.Activated,function() self:export() end)
 action(view.import.Activated,function() self:import() end)
 action(view.worlds.Activated,function() self:cancel();self.library:open(self.state.document) end)
 return self
end
function Controller:checkResizeSize(entry)
 local item=self.catalog.byPath[entry.asset]
 if entry.stretch and item.resizeAxes and self.scene then
  Placement.checkResizeSize(self.scene:template(item),entry.scale,entry.stretch)
 end
end
function Controller:loadSounds()
 self.sfx={};self.sfxByKey={}
 local value=Shared.Parent and Shared.Parent:FindFirstChild("BattleWorksSfxCatalog")
 if not value then return end
 local ok,items=pcall(Catalog.decode,value,Http)
 if not ok or type(items)~="table" then return end
 for _,item in items do
  if type(item)=="table" and type(item.name)=="string" and type(item.category)=="string" and type(item.key)=="string" and type(item.assetId)=="string" and item.assetId:match("^[1-9]%d*$") then
   table.insert(self.sfx,item);self.sfxByKey[item.key]=item
  end
 end
 table.sort(self.sfx,function(a,b)
  if a.category==b.category then return a.name<b.name end
  return a.category<b.category
 end)
end
function Controller:stopSoundPreview()
 if self.soundPreview then self.soundPreview:Destroy();self.soundPreview=nil end
 self.soundPreviewId=nil
 self.view.soundButtons.preview.Text="Preview Sound"
end
function Controller:playSoundPreview(item,settings)
 self:stopSoundPreview()
 if not item then self.view:message("Choose an available sound first.");return end
 if string.find(string.lower(item.moderation or ""),"reject",1,true) then self.view:message("Roblox has rejected this sound.");return end
 local preview=Instance.new("Sound")
 preview.SoundId="rbxassetid://"..item.assetId
 preview.Volume=settings.volume;preview.PlaybackSpeed=settings.speed
 preview.Parent=game:GetService("SoundService")
 self.soundPreview=preview;self.view.soundButtons.preview.Text="Stop Preview"
 local entry=self:selected();self.soundPreviewId=entry and entry.id
 preview.Ended:Connect(function() if self.soundPreview==preview then self:stopSoundPreview() end end)
 preview:Play()
 task.delay(8,function()
  if self.soundPreview==preview and not preview.IsLoaded then
   self:stopSoundPreview();self.view:message("Sound unavailable. Check Roblox moderation and experience audio permissions.")
  end
 end)
end
function Controller:openSoundPicker(mode)
 local entry=self:selected()
 if not entry or not entry.sound then return end
 self:stopCamera()
 self.soundPicker={mode=mode,id=entry.id}
 self.view.sfxPicker.Visible=true
 self.view.sfxSearch.Text=""
 self:showSoundPicker()
end
function Controller:closeSoundPicker()
 self.soundPicker=nil;self.view.sfxPicker.Visible=false
 self.view:soundChoices({},function()end)
 self:stopSoundPreview()
end
function Controller:showSoundPicker()
 local picker=self.soundPicker
 local entry=picker and self.state:find(picker.id)
 if not entry then return end
 local search=self.view.sfxSearch.Text:lower()
 local rows={}
 local function matches(text) return text:lower():find(search,1,true)~=nil end
 if picker.mode=="effect" then
  self.view.sfxTitle.Text=if #self.sfx==0 then "No sounds imported yet" else "Sound Effects"
  if matches("None") then table.insert(rows,{key="",name="None"}) end
  for _,item in self.sfx do
   local name=item.category.."  /  "..item.name
   if matches(name) then table.insert(rows,{key=item.key,name=name,assetId=item.assetId,moderation=item.moderation}) end
  end
  self.view:soundChoices(rows,function(item)
   self:closeSoundPicker()
   self:perform(function() entry.sound.effect=item.key end,"Sound effect selected.")
  end,function(item)
   if self.soundPreview and self.soundPreview.SoundId=="rbxassetid://"..item.assetId then self:stopSoundPreview()
   else self:playSoundPreview(item,entry.sound) end
  end)
 else
  self.view.sfxTitle.Text="Trigger Assets"
  for _,asset in self.state.document.objects do
   if asset~=entry and (not entry.attachment or entry.attachment.parent~=asset.id) then
    local name=asset.id.."  /  "..asset.asset
    if matches(name) then
     local checked=table.find(entry.sound.targets or {},asset.id)
     table.insert(rows,{id=asset.id,name=(if checked then "☑  " else "☐  ")..name})
    end
   end
  end
  self.view:soundChoices(rows,function(item)
   self:perform(function()
    local targets=entry.sound.targets or {};entry.sound.targets=targets
    local i=table.find(targets,item.id)
    if i then table.remove(targets,i)
    else assert(#targets<32,"Select up to 32 trigger assets");table.insert(targets,item.id) end
   end,"Trigger assets updated.")
   self:showSoundPicker()
  end)
 end
end
function Controller:refreshSound(entry)
 if self.soundPreview and (not entry or entry.id~=self.soundPreviewId) then self:stopSoundPreview() end
 local sound=entry and entry.sound
 local buttons=self.view.soundButtons
 for _,button in buttons do button.Visible=sound~=nil end
 for key,row in self.view.soundFields do
  local visible=sound~=nil and (key~="interval" or sound.playback=="Repeat")
  row.label.Visible=visible;row.field.Visible=visible
  if visible and UIS:GetFocusedTextBox()~=row.field then row.field.Text=tostring(sound[key]) end
 end
 if not sound then return end
 local item=self.sfxByKey and self.sfxByKey[sound.effect]
 buttons.effect.Text=if item then item.category.." / "..item.name elseif sound.effect~="" then "Unavailable sound • Choose Effect" else "Choose Sound Effect"
 buttons.activation.Text="Activation: "..({Always="Always Active",Entry="On Entry",Exit="On Exit",Occupied="While Occupied"})[sound.activation]
 buttons.playback.Text="Playback: "..({Once="Once per activation",Loop="Loop while active",Repeat="Repeat while active"})[sound.playback]
 buttons.rollOff.Text="RollOff: "..sound.rollOff
 buttons.filter.Text="Trigger: "..({Tanks="Tanks only",Moving="Moving assets only",Both="Tanks and moving assets",Specific="Specific placed assets",Terrain="Terrain contact"})[sound.filter or "Tanks"]
 buttons.origin.Text=if sound.origin=="Trigger" then "Sound origin: Triggering object" else "Sound origin: Sound Block"
 buttons.targets.Visible=sound.filter=="Specific"
 buttons.targets.Text="Select Trigger Assets ("..#(sound.targets or {})..")"
 buttons.attach.Text=if entry.attachment then "Detach from "..entry.attachment.parent else "Snap & Lock to Asset"
end
function Controller:reconcileAttachments(before)
 local prior={}
 for _,entry in before.objects do prior[entry.id]=entry end
 for _,entry in self.state.document.objects do
  if entry.attachment then
   local old=prior[entry.id]
   local parent=self.state:find(entry.attachment.parent)
   if not parent then entry.attachment=nil
   elseif (old and State.equal(old.attachment,entry.attachment) and
    (not State.equal(old.position,entry.position) or not State.equal(old.rotation,entry.rotation))) or
    (not old and prior[parent.id]) then
    entry.attachment=Attachment.relative(parent,entry)
   end
  end
 end
 Document.resolveAttachments(self.state.document)
end
function Controller:lockAttachment(entry,parent)
 if not parent or parent.slot or parent.sound or parent==entry then self.view:message("Select a placed asset to attach to.");return end
 self:perform(function() entry.attachment=Attachment.relative(parent,entry) end,"Sound Block attached to "..parent.id..".")
end
function Controller:toggleAttachment()
 local entry=self:selected()
 if not entry or not entry.sound then return end
 if entry.attachment then
  local pose
  local preview=self.motionPreview
  local record=self.scene and self.scene.models[entry.id]
  if preview and record and preview.children[entry.id] then
   local rest=preview.children[entry.id].pivot
   pose=record.model:GetPivot()*rest:ToObjectSpace(Attachment.frame(entry.position,entry.rotation))
  end
  self:perform(function()
   if pose then Attachment.setPose(entry,pose) end
   entry.attachment=nil
  end,"Sound Block detached.")
  return
 end
 local pin=self.state.pins[entry.id]
 local target=pin and ((pin.second and pin.second.targetId) or pin.targetId)
 if target and self.state:find(target) then self:lockAttachment(entry,self.state:find(target));return end
 self:cancel();self.attaching=entry.id
 self.view:message("Click or tap the parent asset. The Sound Block keeps its current offset.")
end
function Controller:replaceDocument(document)
 self:cancel()
 local previous=self.state:snapshot()
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
 self.state:record(previous)
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
function Controller:refreshTraction()
 local kind=self.brush.operation
 local visible=self.mode=="Terrain" and Materials.TunableTraction[kind]==true
 self.view.traction.Visible=visible;self.view.tractionLabel.Visible=visible
 if visible then
  local default=Materials.defaultTraction(kind)
  local field=self.state.document.settings.terrain
  local percent=field and field.traction and field.traction[kind] or default
  self.view.tractionLabel.Text=string.format("Traction (%% of pavement) · default %.4g%%",default)
  if UIS:GetFocusedTextBox()~=self.view.traction then self.view.traction.Text=tostring(percent) end
 end
end
function Controller:motionEntry()
 local entry=self:selected()
 local item=entry and self.catalog.byPath[entry.asset]
 return if item and not item.zone then entry else nil
end
function Controller:drawMotion()
 local entry=self:motionEntry()
 local m=self.motionDraft or (entry and entry.motion)
 local view=self.view
 view.motionDraw.Visible=entry~=nil
 view.motionDraw.Text=if self.motionDraft then "Finish Motion Path" elseif m then "Edit Motion Path" else "Draw Motion Path"
 local spin=entry and entry.spin
 view.spinToggle.Visible=entry~=nil and not self.motionDraft
 view.spinToggle.Text=if spin then "Remove rotation" else "Add automatic rotation"
 view.spinSpace.Visible=spin~=nil and not self.motionDraft
 view.spinSpace.Text=if spin and spin.space=="local" then "Axis space: Local" else "Axis space: World"
 view.spinMode.Visible=view.spinSpace.Visible
 view.spinMode.Text=if spin and spin.swing then "Rotation mode: Swing" else "Rotation mode: Continuous"
 view.spinFields.pause.label.Text=if spin and spin.swing then "Pause at each end (seconds)" else "Pause after each turn (seconds)"
 for key,row in view.spinFields do
  row.label.Visible=spin~=nil and not self.motionDraft and (key~="swing" or spin.swing~=nil);row.field.Visible=row.label.Visible
  local axis=({x=1,y=2,z=3})[key]
  if row.field.Visible and UIS:GetFocusedTextBox()~=row.field then row.field.Text=tostring(if axis then spin.axis[axis] else spin[key]) end
 end
 local parent=entry and entry.attachment and self.state:find(entry.attachment.parent)
 view.motionPreview.Visible=(m~=nil or spin~=nil or (parent and (parent.motion or parent.spin)~=nil)) and not self.motionDraft
 view.motionPreview.Text=if self.motionPreview then "Stop Preview" else "Preview Motion"
 view.motionRemove.Visible=entry~=nil and entry.motion~=nil and not self.motionDraft
 local point=self.motionDraft and self.motionPoint and self.motionDraft.points[self.motionPoint]
 view.motionPoint.Visible=point~=nil
 for axis,row in view.waypointFields do
  row.field.Visible=point~=nil;row.label.Visible=point~=nil
  if point and UIS:GetFocusedTextBox()~=row.field then row.field.Text=tostring(entry.position[axis]+point[axis]) end
 end
 view.motionFace.Visible=m~=nil;view.motionEnable.Visible=m~=nil
 if m then
  view.motionFace.Text=if m.face then "Face direction of travel" else "Maintain orientation"
  view.motionEnable.Text=if m.enabled then "Motion enabled" else "Motion disabled"
 end
 for key,row in view.motionFields do
  row.label.Visible=m~=nil;row.field.Visible=m~=nil
  if m and UIS:GetFocusedTextBox()~=row.field then row.field.Text=tostring(m[key]) end
 end
 if not self.scene then return end
 local points={}
 local closed=m and Motion.closed(m.points)
 if entry and m then
  local origin=Vector3.new(table.unpack(entry.position))+Vector3.new(0,.75,0)
  for i,p in m.points do points[i]=origin+Vector3.new(table.unpack(p)) end
  if closed then points[#points]=points[1] end
 end
 self.scene:drawMotion(points,closed,self.motionPoint)
end
function Controller:toggleMotionDraw()
 local entry=self:motionEntry()
 if not entry then return end
 if self.motionDraft then
  local motion=self.motionDraft
  if Motion.closed(motion.points) then motion.points[#motion.points]=State.copy(motion.points[1]) end
  local settings=self.state.document.settings
  local ok,reason=pcall(Motion.validate,motion,entry.position,settings.width,settings.depth)
  if not ok then self.view:message(tostring(reason));return end
  self.motionDraft=nil;self.motionPoint=nil
  self:perform(function() entry.motion=motion end,"Motion path saved to the draft.")
  return
 end
 self:cancel()
 self.motionDraft=if entry.motion then State.copy(entry.motion) else {points={},speed=12,pause=0,face=false,enabled=true}
 self:drawMotion()
 self.view:message("Click or tap to add waypoints. Drag a marker to move it. Close a loop within 5 studs of the first point. Escape cancels.")
end
function Controller:updateMotionProperty(key,value)
 local entry=self:motionEntry()
 local m=self.motionDraft or (entry and entry.motion)
 if not m then return end
 if key=="face" or key=="enabled" then value=not m[key]
 elseif not value or value~=value or value<(if key=="speed" then 1 else 0) or value>(if key=="speed" then 60 else 10) then self:drawMotion();return end
 if self.motionDraft then m[key]=value;self:drawMotion()
 else self:stopMotionPreview();self:perform(function() m[key]=value end,"Motion settings updated.") end
end
function Controller:motionOffset(entry,point)
 local x,z=self.state:snapValue(point.X),self.state:snapValue(point.Z)
 local settings=self.state.document.settings
 local y=if settings.terrain then Heightfield.sample(settings.terrain,settings.width,settings.depth,x,z) else point.Y
 return {x-entry.position[1],y-entry.position[2],z-entry.position[3]}
end
function Controller:motionInput(input,point,mouse)
 local m=self.motionDraft
 local entry=self:motionEntry()
 if not m or not entry then return end
 local origin=Vector3.new(table.unpack(entry.position))
 local scene=self.scene
 local pixel=mouse-self.view.viewport.AbsolutePosition
 local closest,distance=nil,13
 for i,p in m.points do
  local projected=Math.project(scene.camera.CFrame,self.view.viewport.AbsoluteSize,origin+Vector3.new(table.unpack(p))+Vector3.new(0,.75,0),scene.camera.FieldOfView)
  if projected and (projected-pixel).Magnitude<distance then closest=i;distance=(projected-pixel).Magnitude end
 end
 if closest then
  self.motionPoint=closest
  local closed=Motion.closed(m.points)
  self.motionDrag={input=input,index=closest,pixel=mouse,closed=closed,canClose=closest==1 and #m.points>=3 and #m.points<Motion.MaxPoints and not closed}
 elseif point and #m.points<Motion.MaxPoints then
  local i=#m.points+1
  m.points[i]=self:motionOffset(entry,point)
  self.motionPoint=i
 end
 self:drawMotion()
end
function Controller:moveMotionPoint(mouse)
 local drag,m,entry=self.motionDrag,self.motionDraft,self:motionEntry()
 if not drag or not m or not entry or (mouse-drag.pixel).Magnitude<3 then return end
 drag.moved=true
 local point=self:pointer(mouse,true)
 if not point then return end
 local values=self:motionOffset(entry,point)
 m.points[drag.index]=values
 if drag.closed and (drag.index==1 or drag.index==#m.points) then
  m.points[1]=State.copy(values);m.points[#m.points]=State.copy(values)
 end
 self:drawMotion()
end
local function motionPreview(entry,model)
 local r=entry.rotation
 local orientation=CFrame.Angles(math.rad(r[1]),math.rad(r[2]),math.rad(r[3]))
 return {entry=entry,model=model,pivot=model:GetPivot(),
  path=entry.motion and entry.motion.enabled and Motion.compile(entry.motion),
  spin=entry.spin and Motion.compileSpin(entry.spin,orientation),center=Visual.measure(model).Position}
end
local function previewPose(preview,time)
 if not preview.path and not preview.spin then return preview.pivot end
 local offset,yaw=Vector3.zero,nil
 if preview.path then offset,yaw=Motion.sample(preview.path,time) end
 local origin=Vector3.new(table.unpack(preview.entry.position))
 local angle=if yaw then yaw-math.rad(preview.entry.rotation[2]) else 0
 local spinAngle=if preview.spin then Motion.spinAngle(preview.spin,time) else 0
 return Motion.frame(origin,offset,angle,preview.spin,spinAngle,preview.center)*preview.pivot
end
function Controller:toggleMotionPreview()
 if self.motionPreview then self:stopMotionPreview();self:drawMotion();return end
 local entry=self:motionEntry()
 if entry and entry.attachment then
  local parent=self.state:find(entry.attachment.parent)
  if parent and (parent.motion or parent.spin) then entry=parent end
 end
 local record=entry and (entry.motion or entry.spin) and self.scene.models[entry.id]
 if not record then return end
 self.motionPreview=motionPreview(entry,record.model)
 self.motionPreview.time=0;self.motionPreview.children={}
 for _,child in self.state.document.objects do
  if child.attachment and child.attachment.parent==entry.id then
   local model=self.scene.models[child.id].model
   self.motionPreview.children[child.id]=motionPreview(child,model)
  end
 end
 self:drawMotion()
end
function Controller:stopMotionPreview()
 local preview=self.motionPreview
 if not preview then return end
 self.motionPreview=nil
 if preview.model.Parent then preview.model:PivotTo(preview.pivot) end
 for _,child in preview.children do if child.model.Parent then child.model:PivotTo(child.pivot) end end
end
function Controller:refreshTunnel()
 local enabled=self.mode=="Terrain" and self.brush.operation=="Tunnel"
 local list=self.state.document.settings.tunnels
 local tunnel=list and self.tunnelIndex and list[self.tunnelIndex]
 if not tunnel then self.tunnelIndex=nil end
 local view=self.view
 view.tunnelNew.Visible=enabled;view.tunnelNext.Visible=enabled and list~=nil;view.tunnelDelete.Visible=enabled and tunnel~=nil
 for key,field in view.tunnelFields do
  local visible=enabled and (tunnel~=nil or key=="diameter" or key=="traction")
  field.Visible=visible;view.tunnelLabels[key].Visible=visible
  if visible and UIS:GetFocusedTextBox()~=field then
   field.Text=tostring(if tunnel then (if key=="start" then tunnel.a[2] elseif key=="finish" then tunnel.b[2] else tunnel[key])
    elseif key=="diameter" then self.tunnelDiameter or 18 else self.tunnelTraction or 100)
  end
 end
 if enabled and self.scene then
  local points={}
  if tunnel then points={Vector3.new(table.unpack(tunnel.a)),Vector3.new(table.unpack(tunnel.b))}
  elseif self.tunnelStart then points={self.tunnelStart} end
  self.scene:drawMotion(points,false,nil)
 end
end
function Controller:tunnelClick(point)
 if not point then return end
 if not self.tunnelStart then
  self.tunnelIndex=nil;self.tunnelStart=point;self:refreshTunnel()
  self.view:message("Choose the second portal. You can adjust both elevations after placement.")
  return
 end
 local start=self.tunnelStart
 local function portal(p) return {p.X,p.Y,p.Z} end
 local tunnel={a=portal(start),b=portal(point),diameter=self.tunnelDiameter or 18,traction=self.tunnelTraction or 100}
 local ok=self:perform(function()
  local settings=self.state.document.settings
  settings.terrain=settings.terrain or Heightfield.new(settings.width,settings.depth)
  local list=State.copy(settings.tunnels or {})
  table.insert(list,tunnel);settings.tunnels=list
 end,"Tunnel created.")
 if ok then
  local settings=self.state.document.settings
  self.tunnelIndex=#settings.tunnels
  if Tunnel.cover(settings,tunnel)<0 then
   self.view:message("Tunnel created. The lining is exposed at the midpoint. Raise the hill or lower both portals for more cover.")
  end
 else
  self.tunnelStart=start
 end
 self:refreshTunnel()
end
function Controller:refresh()
 self:refreshTraction()
 for axis,field in self.view.dimensions do
  if UIS:GetFocusedTextBox()~=field then field.Text=tostring(self.state.document.settings[axis]) end
 end
 self.view.placeStart.Text="Place start zone  •  "..#self.state.document.spawns.."/5"
 if self.scene then
  self.scene.traversability=self.traversability
  self.scene:sync(self.state.document,self.catalog)
 end
 local selected=self:selected();self.view:selection(selected,selected and self.catalog.byPath[selected.asset]);self:refreshSound(selected)
 if self.scene then self.scene:selection(selected and selected.id,self.distance) end
 self:updateSnap()
 self:drawMotion()
 self:refreshTunnel()
 self.view.undo.Text="Undo ("..#self.state.past..")";self.view.redo.Text="Redo ("..#self.state.future..")"
end
local function copyPose(entry,pose)
 entry.position=State.copy(pose.position);entry.rotation=State.copy(pose.rotation);entry.scale=pose.scale
 entry.stretch=State.copy(pose.stretch)
end
function Controller:updateSnap()
 local entry=self:selected();local pin=entry and self.state.pins[entry.id]
 local side=if pin then pin.side else (self.snapPreview and self.snapPreview.side) or self.snapSide or 0
 self.view.edgeSnap.Text="Snap tool"
 self.view.snapContact.Text=if self.fitMode=="Stretch" then "Scale / [Stretch]" else "[Scale] / Stretch"
 self.view.pinStatus.Text=if self.fitMode=="Stretch" then "Drag a handle on an enabled resize axis. The opposite side stays fixed." else "Drag A–D or an edge dot onto a target dot or line. Click a source dot to pin that edge."
 if self.scene then self.scene:setSnap(self.edgeSnap,self.state.pins,side);self.scene:selection(entry and entry.id,self.distance) end
end
function Controller:pinHere(endpoint)
 local entry=self:selected();if not entry then self.view:message("Select an object first.");return end
 if self.state.pins[entry.id] then self.view:message("Release the existing pin before choosing a different fixed end.");return end
 local item=self.catalog.byPath[entry.asset]
 if item.zone then self.view:message("Water/mud regions stay on the ground and cannot be pinned.");return end
 local ends,box=Snap.ends(entry,self.snapSide,item.collider);self.edgeSnap=true
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
    for i=1,3 do assert((entry.stretch and entry.stretch[i] or 1)==(old.stretch and old.stretch[i] or 1),"Both endpoints are fitted. Release pins before resizing") end
    for i=1,3 do assert(entry.position[i]==old.position[i] and entry.rotation[i]==old.rotation[i],"Both endpoints are fitted. Release pins before transforming") end
   end
  else Snap.anchor(entry,pin,self:snapProfile(entry)) end
 end
end
function Controller:clearContacts(id)
 self.state.pins[id]=nil
 for other,pin in self.state.pins do
  if pin.targetId==id then
   self.state.pins[other]=if pin.second and pin.second.targetId~=id then pin.second else nil
  elseif pin.second and pin.second.targetId==id then
   pin.second=nil
  end
 end
end
function Controller:snapProfile(entry)
 local item=self.catalog.byPath[entry.asset]
 return item and item.collider
end
function Controller:perform(fn,message)
 self:cancel()
 local before=self.state:snapshot();local past,future=table.clone(self.state.past),table.clone(self.state.future)
 local ok,err=pcall(function() fn();self:reconcilePins(before.document);self:reconcileAttachments(before.document);Document.export(self.state.document,self.catalog) end)
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
 local query=self.view.search.Text
 local dirs,items,prefix
 if self.showRecent and query=="" then
  dirs,items,prefix={},{},"Recent"
  for _,path in self.recentAssets do
   local item=self.catalog.byPath[path]
   if Document.isPlaceable(item) then table.insert(items,item) end
  end
 else
  dirs,items=Document.tree(self.catalog,self.prefix,query);prefix=self.prefix
 end
 self.view.recentAssets.BackgroundColor3=if self.showRecent then View.activeColor else View.buttonColor
 self.page,self.pages=self.view:paletteEntries(dirs,items,prefix,self.page,self.context.editorAssets,function(folder)
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
 self.view:terrainMode(mode=="Terrain",self.brush.operation)
 self:refreshTraction()
 self:refreshTunnel()
 if self.scene then
  self.scene:setMode(mode,self.rotationAxis or "Yaw")
  local selected=self:selected();self.scene:selection(selected and selected.id,self.distance)
 end
 for axis,button in self.view.rotationAxes do button.BackgroundColor3=if axis==(self.rotationAxis or "Yaw") then View.activeColor else View.buttonColor end
 for name,button in self.view.tools do button.BackgroundColor3=if name==mode then View.activeColor else View.buttonColor end
 self:updateSnap()
 self.view:message(if mode=="Terrain" then self.brush.operation.." Terrain · hold and drag on the ground. Escape cancels the stroke." elseif mode=="Move" then "Move • red X / blue Z slides; green Y raises or lowers." elseif mode=="Rotate" then "Rotate • choose a local axis, then drag the ring." elseif mode=="Snap" then "Snap • drag a side handle onto a surface edge." elseif mode=="Select" then "Select an object or navigate the scene." elseif mode=="Resize" then "Resize • drag an enabled local axis. Red is width, green is height, and blue is length." else "Scale • drag the green anchor to resize uniformly.")
end
function Controller:frameWorld() self.focus=Vector3.zero;self.distance=math.max(self.state.document.settings.width,self.state.document.settings.depth)*.95;self.pitch=1;self.yaw=.55 end
function Controller:focusSelected()
 local selected=self:selected()
 if not selected then self:frameWorld();return end
 self.focus=Vector3.new(table.unpack(selected.position))
 local record=self.scene and self.scene.models[selected.id]
 local size
 if record then local _,bounds=record.model:GetBoundingBox();size=bounds end
 self.distance=if size then math.clamp(size.Magnitude*1.8,20,1600) else 48
end
function Controller:zoom(delta)
 if self.gesture or self.terrainStroke or self.paused or self.windowUnfocused then return end
 local point=self:pointer()
 local nextDistance=math.clamp(self.distance*math.exp(-delta*.12*self.cameraSensitivity),20,2200)
 if point then self.focus+=(point-self.focus)*(1-nextDistance/self.distance) end
 self.distance=nextDistance
end
function Controller:mousePosition()
 local origin=game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.None).Min
 return Math.guiPoint(UIS:GetMouseLocation(),origin)
end
function Controller:pointer(mouse,motion)
 mouse=mouse or self:mousePosition()
 if not self.scene then return nil,nil,nil,mouse end
 local origin,direction=Math.ray(self.scene.camera.CFrame,self.view.viewport.AbsoluteSize,mouse-self.view.viewport.AbsolutePosition,self.scene.camera.FieldOfView)
 local settings=self.state.document.settings
 local point=if (self.mode=="Terrain" or motion) and settings.terrain then Heightfield.pick(settings.terrain,settings.width,settings.depth,origin,direction) else Math.ground(origin,direction)
 if (self.mode=="Terrain" or motion) and point and (math.abs(point.X)>settings.width/2 or math.abs(point.Z)>settings.depth/2) then point=nil end
 return point,origin,direction,mouse
end
function Controller:paintTerrain(point,dt)
 local stroke=self.terrainStroke
 local settings=self.state.document.settings
 local field=settings.terrain or stroke.field
 local brush=self.brush
 local previous=stroke.previous or point
 local spacing=math.max(2,brush.radius*.4)
 local stamps=math.clamp(math.ceil((point-previous).Magnitude/spacing),1,24)
 local dirty={}
 for i=1,stamps do
  local center=previous+(point-previous)*(i/stamps)
  local code=table.find(Heightfield.Paint,brush.operation)
  local updates
  if code then updates=Heightfield.paint(field,settings.width,settings.depth,center,brush.radius,code)
  else
   local carve=brush.operation=="Carve Ravine"
   updates=Heightfield.brush(field,settings.width,settings.depth,center,if carve then "Carve" else brush.operation,
    brush.radius,brush.strength,brush.falloff,if carve then stroke.elevation else brush.elevation,dt/stamps,stroke.remainder)
  end
  for id,chunk in updates do
   dirty[id]=chunk
  end
 end
 if next(dirty) then
  settings.terrain=field
  self.scene:syncTerrain(settings,dirty)
 end
 stroke.previous=point
end
function Controller:finishTerrain(cancel)
 local stroke=self.terrainStroke
 if not stroke then return end
 self.terrainStroke=nil
 if cancel then self.state:restore(stroke.before)
 else self.state:record(stroke.before) end
 self:refresh()
end
function Controller:candidate(point)
 local item=self.placing
 return {id="placement_preview",type=item.id,asset=item.model,position={self.state:snapValue(point.X),0,self.state:snapValue(point.Z)},rotation={0,0,0},scale=self.assetScales[item.model] or item.defaultScale or 1,solid=State.defaultSolid(item),destructible=item.destructible or false,hp=item.hp or 100,bounds=State.copy(item.size),sound=if item.model==Audio.Asset then State.copy(Audio.Default) else nil}
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
 if self:perform(function() self.state:add(item,{point.X,0,point.Z},item.size,self.assetScales[item.model]) end,"Placed "..item.model) then
  local previous=table.find(self.recentAssets,item.model)
  if previous then table.remove(self.recentAssets,previous) end
  table.insert(self.recentAssets,1,item.model)
  if #self.recentAssets>12 then table.remove(self.recentAssets) end
  if self.repeatPlacement then self.placing=item end
 end
end
function Controller:cancel()
 self.tunnelStart=nil
 self.attaching=nil
 self.motionDraft=nil;self.motionPoint=nil;self.motionDrag=nil;self:stopMotionPreview()
 if self.scene then self:drawMotion() end
 self:finishTerrain(true)
 if self.gesture then self.state:restore(self.gesture.before);self.gesture=nil;if self.scene then self.scene:sync(self.state.document,self.catalog) end end
 self.placing=nil;self.placingStart=nil;self.paletteDrag=nil;self:stopCamera()
 self.snapPreview=nil
 if self.scene then self.scene:snapFeedback(nil);self.scene:clearEdgeTargets();self.scene:setSnap(self.edgeSnap,self.state.pins,self.snapSide) end
 if self.scene then self.scene:clearGhost();self.scene:startPreview(nil) end
 if self.scene then self.scene:brushFootprint(nil) end
end
function Controller:finishGesture(cancel)
 local g=self.gesture;if not g then return end
 self.gesture=nil
 if self.scene then self.scene.draggingSnap=false;self.scene:clearEdgeTargets() end
 local ok,err=pcall(function()
  local preview=self.snapPreview
  if not cancel and g.clickPin and not g.moved then
   self.state:restore(g.before)
   self.state.pins[g.id]=g.clickPin
   return
  end
  if g.kind=="Snap" then assert(preview and preview.valid,"No valid snap target; previous pose restored") end
  if preview and preview.valid then
   local pin=if g.kind=="Snap" then State.copy(g.pin) else self.state.pins[g.id]
   if g.kind=="Snap" then self.state.pins[g.id]=pin end
   if pin then pin.second=Snap.pin(preview.endpoint,preview.target,pin.side,g.edgeIndex,g.edgeFraction)
   else self.state.pins[g.id]=Snap.pin(preview.endpoint,preview.target,preview.side) end
  end
  self:reconcileAttachments(g.before.document)
  Document.export(self.state.document,self.catalog)
 end)
 if cancel or not ok then self.state:restore(g.before) else
  self.state:record(g.before)
  local entry=self.state:find(g.id)
  if entry and entry.asset and entry.scale~=g.base.scale then self.assetScales[entry.asset]=entry.scale end
 end
 self.snapPreview=nil;if self.scene then self.scene:snapFeedback(nil) end
 self:refresh();self.view:message(if cancel then "Transform canceled." elseif ok then "Transform applied." else tostring(err))
end
function Controller:beginSnap(endpoint,entry,choice,pixel)
 local pin=self.state.pins[entry.id]
 if self.catalog.byPath[entry.asset].zone then self.view:message("Ground regions cannot be fitted.");return end
 local side=if pin then pin.side or 0 else self.snapSide or 0
 local opposite=Snap.opposite(endpoint)
 local item=self.catalog.byPath[entry.asset]
 if self.fitMode=="Stretch" and not Document.canResize(item,Snap.axis(entry,endpoint)) then
  if item.resizeAxes or (item.collider and item.collider.explicitCollision) then
   self.view:message("This local axis cannot be stretched. Select Scale to fit uniformly.");return
  end
  self.fitMode="Scale"
 end
 local ends,box=Snap.ends(entry,side,item.collider)
 local fixed=if pin and pin.endpoint==opposite then State.copy(pin) elseif pin and pin.second and pin.second.endpoint==opposite then State.copy(pin.second) else Snap.pin(opposite,{point={ends[opposite].X,ends[opposite].Y,ends[opposite].Z},normal={box.up.X,box.up.Y,box.up.Z},kind="position"},side)
 fixed.second=nil
 self.edgeSnap=true
 local picked=if choice then choice.point else ends[endpoint]
 local edgeIndex=choice and choice.edge.index
 local fraction=choice and choice.fraction
 local clickPin=if edgeIndex then Snap.pin(endpoint,{point={picked.X,picked.Y,picked.Z},normal={box.up.X,box.up.Y,box.up.Z},kind="position"},side,edgeIndex,fraction) else nil
 self.gesture={kind="Snap",endpoint=endpoint,id=entry.id,before=self.state:snapshot(),base=State.copy(entry),pin=fixed,side=side,startPoint=picked,
  edgeIndex=edgeIndex,edgeFraction=fraction,clickPin=clickPin,startPixel=pixel}
 self.scene.draggingSnap=true
 self.state.pins[entry.id]=State.copy(fixed)
 self.snapPreview=nil;self:updateSnap()
 self.view:message("Drag this end; the opposite end stays fixed. Release to hold the fit. Esc cancels.")
end
local function releaseEditorCursor()
 if UIS.MouseBehavior~=Enum.MouseBehavior.Default then UIS.MouseBehavior=Enum.MouseBehavior.Default end
 if not UIS.MouseIconEnabled then UIS.MouseIconEnabled=true end
end
function Controller:stopCamera()
 if self.cameraDrag then releaseEditorCursor() end
 self.cameraDrag=nil;self.cameraDelta=Vector2.zero
end
function Controller:beginCamera(input)
 if self.cameraDrag and self.cameraDrag.button==input.UserInputType then return true end
 if not self.active or not self.scene or self.terrainStroke or self.paused or UIS:GetFocusedTextBox() or self.view:isModal() or not self.view:isScene(self:mousePosition()) then return false end
 local button=input.UserInputType
 if button~=Enum.UserInputType.MouseButton2 and button~=Enum.UserInputType.MouseButton3 then return false end
 if self.gesture then return false end
 self:stopCamera()
 self.cameraDrag={button=button}
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
 if input.UserInputType==Enum.UserInputType.MouseButton2 or input.UserInputType==Enum.UserInputType.MouseButton3 then
  if not processed then self:beginCamera(input) end
  return
 end
 if self.cameraDrag then return end
 local touch=input.UserInputType==Enum.UserInputType.Touch
 local mousePoint=if touch then Math.guiPoint(Vector2.new(input.Position.X,input.Position.Y),game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.None).Min) else nil
 local point,origin,direction,mouse=self:pointer(mousePoint,self.motionDraft~=nil)
 if not origin or not direction or not self.view:isScene(mouse) then return end
 if processed and not touch then return end
 if input.UserInputType~=Enum.UserInputType.MouseButton1 and not touch then return end
 if self.attaching then
  local id=self.scene:pick(origin,direction,mouse-self.view.viewport.AbsolutePosition,self.view.viewport.AbsoluteSize)
  local child=self.state:find(self.attaching)
  if child and id then self:lockAttachment(child,self.state:find(id)) end
  return
 end
 if self.motionDraft then if not self.motionDrag then self:motionInput(input,point,mouse) end;return end
 self:stopMotionPreview()
 if self.mode=="Terrain" and self.brush.operation=="Tunnel" then self:tunnelClick(point);return end
 if touch then
  if self.placing or self.placingStart then self:place(point)
  elseif self.mode~="Terrain" then
   local pixel=mouse-self.view.viewport.AbsolutePosition
   local id=self.scene:pick(origin,direction,pixel,self.view.viewport.AbsoluteSize)
   if id then self.state:select(id);self:refresh() end
  end
  return
 end
 if self.mode=="Terrain" then
  if point and not self.terrainStroke then
   local settings=self.state.document.settings
   if self.brush.operation=="Water" then
    self:perform(function()
     settings.terrain=settings.terrain or Heightfield.new(settings.width,settings.depth)
     local dirty=Heightfield.fillWater(settings.terrain,settings.width,settings.depth,point,self.brush.depth)
     self.scene:syncTerrain(settings,dirty)
    end,"Water routed downhill and into connected low ground.")
    return
   end
   self.terrainStroke={before=self.state:snapshot(),field=settings.terrain or Heightfield.new(settings.width,settings.depth),remainder={},elapsed=0,elevation=point.Y-self.brush.depth}
   self:paintTerrain(point,.05)
  end
  return
 end
 if self.placing or self.placingStart then self:place(point);return end
 local pixel=mouse-self.view.viewport.AbsolutePosition
 local id,handle,choice=self.scene:pick(origin,direction,pixel,self.view.viewport.AbsoluteSize)
 if id then self.state:select(id);self:refresh() end
 if self.mode=="Select" then
  if not id then self.state.selection={};self:refresh() end
  return
 end
 local entry=self:selected()
 if entry and entry.slot then
  local start=Math.ground(origin,direction)
  if (id or handle) and start then self:setMode("Move");self.gesture={kind="StartMove",id=entry.id,before=self.state:snapshot(),base=State.copy(entry),start=start,axis=handle} end
  return
 end
 if entry and handle and handle:match("^Snap[ABCD]$") then self:beginSnap(handle:sub(-1),entry,choice,pixel);return end
 if entry and (handle or (id and self.mode=="Move")) then
  local kind=handle or "Move"
  local before=self.state:snapshot()
  local pivot=if Math.resizeAxis(kind) then self.scene.anchors[kind].CFrame.Position elseif kind:sub(1,6)=="Rotate" then Visual.measure(self.scene.models[entry.id].model).Position else nil
  local start=Math.dragPoint(kind,entry,origin,direction,self.scene.camera.CFrame,pivot)
  if not start then self.view:message("Orbit the camera slightly to face this rotation ring, then drag again.");return end
  self:clearContacts(entry.id)
  self.gesture={before=before,base=State.copy(entry),id=entry.id,start=start,kind=kind,pivot=pivot}
  if Math.resizeAxis(kind) then
   self.gesture.viewportSize=self.view.viewport.AbsoluteSize
   self.gesture.viewportPosition=self.view.viewport.AbsolutePosition
  end
 elseif not id and not handle then self.state.selection={};self:refresh() end
end
function Controller:key(input,processed)
 if input.KeyCode==Enum.KeyCode.Escape and self.soundPicker then self:stopCamera();releaseEditorCursor();self:closeSoundPicker();return end
 if input.KeyCode==Enum.KeyCode.Escape then self:stopCamera();releaseEditorCursor() end
 if self.paused or processed or UIS:GetFocusedTextBox() or self.view:isModal() then return end
 if self.gesture and input.KeyCode~=Enum.KeyCode.Escape then return end
 self.keys[input.KeyCode]=true
 local control=UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) or UIS:IsKeyDown(Enum.KeyCode.LeftMeta) or UIS:IsKeyDown(Enum.KeyCode.RightMeta)
 local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
 if input.KeyCode==Enum.KeyCode.Escape then self:cancel();self:refresh()
 elseif control and input.KeyCode==Enum.KeyCode.Z then self:history(shift)
 elseif control and input.KeyCode==Enum.KeyCode.Y then self:history(true)
 elseif control and input.KeyCode==Enum.KeyCode.D then self:perform(function() self.state:duplicate() end,"Duplicated selection.")
 elseif input.KeyCode==Enum.KeyCode.Delete or input.KeyCode==Enum.KeyCode.Backspace then self:perform(function() self.state:delete() end,"Deleted selection.")
 elseif input.KeyCode==Enum.KeyCode.One then self:setMode("Move") elseif input.KeyCode==Enum.KeyCode.Two then self:setMode("Rotate")
 elseif input.KeyCode==Enum.KeyCode.Three then self:setMode("Scale")
 elseif input.KeyCode==Enum.KeyCode.Four then self:setMode("Snap")
 elseif input.KeyCode==Enum.KeyCode.G then self.state.snap=not self.state.snap;self:updateGrid()
 elseif input.KeyCode==Enum.KeyCode.F then self:focusSelected()
 elseif input.KeyCode==Enum.KeyCode.Home then self:frameWorld() end
end
function Controller:step(dt)
 if self.cameraDrag and not UIS:IsMouseButtonPressed(self.cameraDrag.button) then self:stopCamera() end
 if not self.cameraDrag then releaseEditorCursor() end
 local scene=self.scene;if not scene then return end
 local preview=self.motionPreview
 if preview then
  preview.time+=dt
  local pose=previewPose(preview,preview.time)
  preview.model:PivotTo(pose)
  for _,child in preview.children do
   child.model:PivotTo(Attachment.follow(pose,preview.pivot,previewPose(child,preview.time)))
  end
 end
 local mouse=self:mousePosition()
 local pixel=mouse-self.view.viewport.AbsolutePosition
 local overScene=self.view:isScene(mouse)
 scene.sourcePixel=if overScene then pixel else nil
 local gesture=self.gesture
 if gesture and Math.resizeAxis(gesture.kind) then
  if gesture.viewportSize~=self.view.viewport.AbsoluteSize or gesture.viewportPosition~=self.view.viewport.AbsolutePosition then
   self:finishGesture(true)
   return
  end
  if not overScene then gesture.leftViewport=true end
  if gesture.leftViewport and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
   -- Studio can swallow the mouse-up when the cursor leaves its window.
   self:finishGesture(false)
   return
  end
  if not overScene then return end
 end
 if self.cameraDrag then
  UIS.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
  local delta=self.cameraDelta*self.cameraSensitivity;self.cameraDelta=Vector2.zero
  if self.cameraDrag.button==Enum.UserInputType.MouseButton3 then
   self.focus+=Math.cameraPan(scene.camera.CFrame,self.view.viewport.AbsoluteSize,delta,self.distance,scene.camera.FieldOfView)
   self.focus=Vector3.new(self.focus.X,math.max(0,self.focus.Y),self.focus.Z)
  else self.yaw-=delta.X*.006;self.pitch+=delta.Y*.004 end
 end
 if not self.paused and not UIS:GetFocusedTextBox() and not self.gesture and not self.terrainStroke and (not self.placing or self.cameraDrag) and not self.view:isModal() then
  local forward=(if self.keys[Enum.KeyCode.W] then 1 else 0)-(if self.keys[Enum.KeyCode.S] then 1 else 0)
  local right=(if self.keys[Enum.KeyCode.D] then 1 else 0)-(if self.keys[Enum.KeyCode.A] then 1 else 0)
  if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then forward=0;right=0 end
  local vertical=(if self.keys[Enum.KeyCode.E] then 1 else 0)-(if self.keys[Enum.KeyCode.Q] then 1 else 0)
  local boost=if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then 2.5 else 1
  local travel=self.distance*math.min(dt,.1)*.6*boost
  self.focus+=(Vector3.new(-math.sin(self.yaw),0,-math.cos(self.yaw))*forward+Vector3.new(math.cos(self.yaw),0,-math.sin(self.yaw))*right+Vector3.new(0,vertical,0))*travel
  self.focus=Vector3.new(self.focus.X,math.max(0,self.focus.Y),self.focus.Z)
 end
 self.pitch=Math.cameraPitch(self.pitch,self.focus.Y,self.distance)
 local cameraOffset=Vector3.new(math.sin(self.yaw)*math.cos(self.pitch),math.sin(self.pitch),math.cos(self.yaw)*math.cos(self.pitch))*self.distance
 scene.camera.CFrame=CFrame.lookAt(self.focus+cameraOffset,self.focus)
 scene:updateTankScale(self.view,cameraOffset,self.distance)
 if next(scene.soundMarkers) then scene:updateSoundMarkers() end
 local point,origin,direction=self:pointer()
 if self.mode=="Terrain" then
  local brushPoint=if not self.cameraDrag and not self.paused and self.view:isScene(mouse) then point else nil
  if self.brush.operation=="Tunnel" then
   scene:brushFootprint(nil)
   if self.tunnelStart then scene:drawMotion(if brushPoint then {self.tunnelStart,brushPoint} else {self.tunnelStart},false,nil) end
   return
  end
  scene:brushFootprint(brushPoint,self.brush.radius)
  local stroke=self.terrainStroke
  if stroke and brushPoint then
   stroke.elapsed+=math.min(dt,.1)
   if stroke.elapsed>=.05 then self:paintTerrain(brushPoint,stroke.elapsed);stroke.elapsed=0 end
  elseif stroke then stroke.previous=nil;stroke.elapsed=0 end
  return
 end
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
   if not g.startPixel or (pixel-g.startPixel).Magnitude>4 then g.moved=true end
   local aiming=(not g.clickPin or g.moved) and origin and direction and self.view:isScene(mouse)
   if not aiming then scene:clearEdgeTargets() end
   local target=if aiming then scene:snapTarget(origin,direction,g.id,g.target,pixel) else nil
   if not target and aiming then
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
     if g.pin then
      local fitted=Snap.fit(g.base,g.endpoint,target,g.pin,self.fitMode,self:snapProfile(entry),g.edgeIndex,g.edgeFraction)
      fitted.asset=entry.asset
      self:checkResizeSize(fitted)
      return fitted
     end
     return Snap.anchor(State.copy(g.base),Snap.pin(g.endpoint,target,g.side),self:snapProfile(entry))
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
    if Math.resizeAxis(g.kind) or (g.kind=="Scale" and transform.stretch) then
     local candidate=table.clone(entry)
     copyPose(candidate,transform)
     local valid,err=pcall(function()
      self:checkResizeSize(candidate)
      Document.checkEntry(self.state.document,self.catalog,candidate)
     end)
     if not valid then self.view:message(tostring(err));return end
    end
    copyPose(entry,transform)
   end
  end
  scene:sync(self.state.document,self.catalog,g)
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
function Controller:enter(playtest)
 assert(self.context.session.mode=="Menu","Leave battle before editing")
 self.context.gameplay:setActive(false)
 self:loadSounds()
 releaseEditorCursor()
 if playtest and playtest.document then
  local draft=Document.numberStarts(State.copy(playtest.document))
  self.state=State.new(draft);self.state.snap=false
  self.library.revisions[draft.id]=playtest.revision
  self.library.saved[draft.id]=State.copy(playtest.document)
 end
 self.active=true;self.paused=false;self.windowUnfocused=false;self.frame.Visible=true;self.view.overlay.Visible=false
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
  if self.motionDrag and (self.motionDrag.input==input or input.UserInputType==Enum.UserInputType.MouseButton1) then
   local drag=self.motionDrag;self.motionDrag=nil
   if drag.canClose and not drag.moved and self.motionDraft then
    local points=self.motionDraft.points
    table.insert(points,State.copy(points[1]));self.motionPoint=#points
    self:drawMotion()
   end
   return
  end
  self.keys[input.KeyCode]=nil
  if self.cameraDrag and self.cameraDrag.button==input.UserInputType then self:stopCamera() end
  if input.UserInputType==Enum.UserInputType.MouseButton1 then
   if self.cameraDrag then self.paletteDrag=nil;return end
   if self.paused then self:cancel();return end
   if self.paletteDrag then
    local point,_,_,mouse=self:pointer()
    local start=self.paletteDrag;self.paletteDrag=nil
    if point and (mouse-start).Magnitude>6 and self.view:isScene(mouse) then self:place(point) end
   elseif self.terrainStroke then self:finishTerrain(false)
   elseif self.gesture then self:finishGesture(false) end
  end
 end)
 connect(UIS.InputChanged,function(input)
  if self.motionDrag and (input==self.motionDrag.input or input.UserInputType==Enum.UserInputType.MouseMovement) then
   local pointer=if input.UserInputType==Enum.UserInputType.Touch then Math.guiPoint(Vector2.new(input.Position.X,input.Position.Y),game:GetService("GuiService"):GetInsetArea(Enum.ScreenInsets.None).Min) else self:mousePosition()
   self:moveMotionPoint(pointer)
  end
  if self.cameraDrag and input.UserInputType==Enum.UserInputType.MouseMovement then
   self.cameraDelta+=Vector2.new(input.Delta.X,input.Delta.Y)
  end
  if input.UserInputType==Enum.UserInputType.MouseWheel and not UIS:GetFocusedTextBox() and not self.view:isModal() and self.view:isScene(self:mousePosition()) then self:zoom(input.Position.Z) end
 end)
 connect(UIS.WindowFocusReleased,function() self.windowUnfocused=true;self:cancel();self.keys={};self:refresh() end)
 connect(UIS.WindowFocused,function() self.windowUnfocused=false end)
 connect(UIS.TextBoxFocused,function() self:stopCamera();self.keys={} end)
 local gui=game:GetService("GuiService")
 connect(gui.MenuOpened,function() self.paused=true;self:cancel();self.keys={} end)
 connect(gui.MenuClosed,function() self.paused=false end)
 if self.scene then
  connect(Run.RenderStepped,function(dt) self:step(dt) end)
  if playtest and playtest.openPlayground and self.state.document.id~="playground" then
   self.library:open(self.state.document,"playground")
  end
 end
end
function Controller:exit()
 self:closeSoundPicker()
 self.library:hide()
 self:cancel();self.active=false;self.frame.Visible=false;self.keys={}
 Actions:UnbindAction("BattleWorksEditorCamera")
 for _,connection in self.runtime do connection:Disconnect() end;self.runtime={}
 local focused=UIS:GetFocusedTextBox()
 if focused and focused:IsDescendantOf(self.frame) then focused:ReleaseFocus() end
 if self.scene then self.scene:destroy();self.scene=nil end
end
function Controller:moveFocus() game:GetService("GuiService").SelectedObject=self.view.back end
function Controller:activateSelected() self.context.home() end
function Controller:destroy() self:exit();self.view:destroy() end
return Controller

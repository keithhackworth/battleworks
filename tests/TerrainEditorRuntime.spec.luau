do
 local H=require("WorldHeightfield")
 local view=controller.view
 local scale=view.tankScaleViewport
 local footprint=scale:FindFirstChild("Footprint")
 check(footprint.Size.X==10 and footprint.Size.Z==10,"corner tank model matches the vehicle solver footprint")
 check(scale.CurrentCamera and scale.Parent:FindFirstChild("Label").Text=="Tank Scale","corner tank has its own camera and label")
 local function tankPixelsPerStud(distance)
  controller.distance=distance
  controller:step(0)
  local camera=scale.CurrentCamera
  local previewHeight=view.tankScaleCard.Size.Y.Offset-40
  return previewHeight/(2*math.tan(math.rad(camera.FieldOfView)/2)*camera.CFrame.Position.Magnitude)
 end
 local near,far=tankPixelsPerStud(80),tankPixelsPerStud(800)
 local expected=view.viewport.AbsoluteSize.Y/(2*math.tan(math.rad(controller.scene.camera.FieldOfView)/2)*800)
 check(math.abs(far-expected)<1e-6 and math.abs(near/far-10)<1e-6,"corner tank matches the editor projection and shrinks tenfold at ten times the distance")
 check(controller.traversability and view.traversalLegend.Visible and controller.scene.terrainOverlay,"the editor enables traversability by default")
 view.traversability.Activated:Fire()
 view.newWorld.Activated:Fire()
 view.dimensions.width.Text="96";view.dimensions.width.FocusLost:Fire()
 view.dimensions.depth.Text="96";view.dimensions.depth.FocusLost:Fire()
 view.terrain.Activated:Fire()
 local oldSize=view.frame.AbsoluteSize
 view.frame.AbsoluteSize=Vector2.new(1440,820)
 view:layout()
 local materialSection=view.surfaceTools.Grass.Parent
 local operationSection=view.terrainTools.Raise.Parent
 local atlas=require("UIAssets").get("editor/terrain-materials.png")
 for _, name in {"Grass","Mud","Ice","Snow","Pavement","Water"} do
  local control=view.surfaceTools[name]
  check(control.Parent==materialSection and control:FindFirstChild("MaterialSwatch"):FindFirstChild("TerrainTexture").Image==atlas.image,
   name.." has a distinct material atlas region")
 end
 for _,spec in {{"Raise","raise"},{"Lower","lower"},{"Smooth","smooth"},{"Flatten","flatten"},{"Carve Ravine","ravine"},{"Tunnel","tunnel"}} do
  local control=view.terrainTools[spec[1]] or view.surfaceTools[spec[1]]
  check(control.Parent==operationSection and control:FindFirstChild("Icon_"..spec[2])~=nil,spec[1].." has an operation graphic")
 end
 check(materialSection.Visible and materialSection.Size.X.Offset==1440
  and view.surfaceTools.None.Position.X.Offset<view.surfaceTools.Clear.Position.X.Offset
  and view.surfaceTools.Clear.Position.X.Offset<view.surfaceTools.Grass.Position.X.Offset,
  "full-width terrain strip starts with None and Clear")
 for _,section in {operationSection} do
  local layout
  for _, child in section:GetChildren() do if child:IsA("UIGridLayout") then layout=child;break end end
  check(section.Visible and layout.CellSize.X.Offset*3+layout.CellPadding.X.Offset*2<=section.Size.X.Offset-15
   and layout.CellSize.Y.Offset*2+layout.CellPadding.Y.Offset+4<=section.Size.Y.Offset,
   "desktop terrain has room for two full rows and three columns")
 end
 local brushFields=view.brushFields
 local brushScroll=brushFields.radius.Parent.Parent
 check(brushFields.strength.Parent.Parent==brushScroll and brushFields.falloff.Parent.Parent==brushScroll
  and brushScroll.Size.Y.Offset>=105,"desktop Tool Settings shows all three brush properties together")
 check(view.brushLabels.radius.Text=="Brush Size (studs)" and view.brushLabels.strength.Text=="Heaviness"
  and view.brushLabels.falloff.Text=="Steepness (0–1)","terrain brush labels follow the specification")
 check(view.inspector:FindFirstChild("ToolSettingsRecess").Visible and view.inspector:FindFirstChild("SelectionPropertiesRecess").Visible,
  "Tool Settings and Selection Properties have separate recessed surfaces")
 view.frame.AbsoluteSize=oldSize
 view:layout()
 local defaults={Grass=75,Mud=20,Snow=31.25,Ice=.25}
 for kind,percent in defaults do
  view.surfaceTools[kind].Activated:Fire()
  check(view.tractionLabel.Visible and math.abs(tonumber(view.worldTraction[kind].Text)-percent)<1e-8,"paint brush shows the default traction for "..kind)
 end
 view.surfaceTools.Ice.Activated:Fire()
 view.worldTraction.Ice.Text="15";view.worldTraction.Ice.FocusLost:Fire()
 check(controller.state.document.settings.terrain.traction.Ice==15,"editing traction updates the world document")
 local tractionSave=require("WorldEditorDocument").export(controller.state.document,controller.catalog)
 controller:history(false)
 check(tonumber(view.worldTraction.Ice.Text)==.25,"undo restores the default in the inspector")
 controller:history(true)
 check(tonumber(view.worldTraction.Ice.Text)==15,"redo restores the override in the inspector")
 controller:replaceDocument(tractionSave)
 check(tonumber(view.worldTraction.Ice.Text)==15,"opening the saved terrain restores traction settings")
 view.worldTraction.Ice.Text="";view.worldTraction.Ice.FocusLost:Fire()
 check(not controller.state.document.settings.terrain.traction,"clearing the last override restores material defaults")
 view.brushFields.radius.Text="16";view.brushFields.radius.FocusLost:Fire()
 check(view.terrainTools.Raise.Parent.Visible and view.brushPanel.Visible and view.tools.Move.Visible~=false,"Terrain provides contextual brush controls and keeps the primary tools available")
 local savedPointer=controller.pointer
 local point=Vector3.zero
 controller.pointer=function()return point,Vector3.new(0,100,0),Vector3.new(0,-1,0),Vector2.zero end
 local mouse1={UserInputType=Enum.UserInputType.MouseButton1,KeyCode=Enum.KeyCode.Unknown}
 local function paintIce(x, percent)
  view.surfaceTools.Ice.Activated:Fire()
  view.brushTraction.Text=percent
  view.brushTraction.FocusLost:Fire()
  point=Vector3.new(x,0,0)
  controller:begin(mouse1,false)
  UIS.InputEnded:Fire(mouse1)
 end
 view.worldTraction.Ice.Text="15";view.worldTraction.Ice.FocusLost:Fire()
 paintIce(-25,"0")
 paintIce(25,"75")
 local function grip(x)
  local settings=controller.state.document.settings
  local env={terrainSettings=settings,zones={},rocks={},logs={},trees={}}
  local _,kind,_,_,profile=require("Environment").sample(env,x,0)
  check(kind=="Ice","traction test samples painted ice")
  return profile.authoredTraction
 end
 check(grip(-25)==0 and grip(25)==.75,"two ice strokes in one world have distinct simulated traction")
 controller:history(false)
 check(select(3,H.surface(controller.state.document.settings.terrain,96,96,25,0))==nil,"undo removes the second traction stroke")
 controller:history(true)
 check(grip(25)==.75,"redo restores the painted override")
 paintIce(25,"")
 check(grip(25)==.15 and grip(-25)==0,"repainting with a blank brush clears only the touched overrides")
 view.worldTraction.Ice.Text="30";view.worldTraction.Ice.FocusLost:Fire()
 check(grip(25)==.3 and grip(-25)==0,"changing world fallback preserves painted overrides, including zero")
 local original=controller.state.document.settings.terrain
 local resized=H.resize(original,96,96,192,96)
 H.validate(resized,192,96)
 local state=require("WorldEditorState")
 local before=state.copy(controller.state.document)
 local history=#controller.state.past
 point=Vector3.new(-25,0,0)
 view.surfaceTools.None.Activated:Fire()
 controller:begin(mouse1,false);UIS.InputEnded:Fire(mouse1)
 check(state.equal(before,controller.state.document) and #controller.state.past==history,"None leaves the terrain and history untouched")
 view.surfaceTools.Clear.Activated:Fire()
 check(state.equal(before,controller.state.document),"selecting Clear does not edit until the brush is used")
 controller:begin(mouse1,false);UIS.InputEnded:Fire(mouse1)
 local cleared=controller.state.document.settings.terrain
 local paint,water,traction=H.surface(cleared,96,96,-25,0)
 check(paint==nil and water==nil and traction==nil and grip(25)==.3
  and state.equal(cleared.heights,original.heights) and #controller.state.past==history+1,
  "Clear restores the default surface under the brush without changing the heights or neighboring paint")
 controller:history(false)
 check(grip(-25)==0,"Undo restores the material and its local traction")
 view.surfaceTools.Water.Activated:Fire()
 check(not view.paintEntireWorld.Visible,"Water keeps its routing tool")
 view.surfaceTools.Ice.Activated:Fire()
 view.brushTraction.Text="44";view.brushTraction.FocusLost:Fire()
 local beforeFill=state.copy(controller.state.document)
 local historyBeforeFill=#controller.state.past
 view.paintEntireWorld.Activated:Fire()
 check(state.equal(beforeFill,controller.state.document),"arming the fill does not edit the world")
 controller:begin(mouse1,false);UIS.InputEnded:Fire(mouse1)
 local filled=controller.state.document.settings.terrain
 for _,corner in {{-47,-47},{-47,47},{47,-47},{47,47}} do
  local kind,_,traction=H.surface(filled,96,96,corner[1],corner[2])
  check(kind=="Ice" and traction==44,"paint entire world reaches every corner with the brush traction")
 end
 check(not controller.brush.paintEntireWorld and #controller.state.past==historyBeforeFill+1
  and state.equal(filled.heights,beforeFill.settings.terrain.heights),"world fill is one edit and preserves elevations")
 controller:history(false)
 check(state.equal(beforeFill,controller.state.document),"Undo restores the entire previous surface")
 check(select(3,H.surface(resized,192,96,-50,0))==0,"resizing carries the traction with its material cells")
 local function stroke(operation,x,z,travel)
  view.terrainTools[operation].Activated:Fire()
  point=Vector3.new(x,0,z)
  local before=#controller.state.past
  controller:begin(mouse1,false)
  for i=1,12 do point=Vector3.new(x+travel*i/12,0,z);controller:step(.05) end
  UIS.InputEnded:Fire(mouse1)
  check(#controller.state.past==before+1,"continuous "..operation.." drag records one undo entry")
 end
 local settings=controller.state.document.settings
 local function height(x,z) return H.sample(controller.state.document.settings.terrain,96,96,x,z) end
 stroke("Raise",-6,0,6)
 check(height(0,0)>5 and height(-45,-45)==0,"Raise creates a localized hill")
 check(controller.scene.terrain and controller.scene.floor.Transparency==1 and controller.scene.brushRing,"terrain replaces the editor floor and displays a footprint")
 local untouched=controller.scene.terrain.chunks[0][1]
 stroke("Lower",30,0,0)
 check(height(30,0)<-7 and controller.scene.terrain.chunks[0][1]==untouched,"Lower creates a pit without replacing an unaffected chunk")
 local preSmooth=table.concat(settings.terrain.heights,",")
 stroke("Smooth",0,0,0)
 local postSmooth=table.concat(settings.terrain.heights,",")
 check(preSmooth~=postSmooth,"Smooth edits the hill transition")
 controller:history(false)
 check(table.concat(controller.state.document.settings.terrain.heights,",")==preSmooth,"Undo restores the exact terrain")
 controller:history(true)
 check(table.concat(controller.state.document.settings.terrain.heights,",")==postSmooth,"Redo restores the exact smoothed terrain")
 view.brushFields.elevation.Text="4";view.brushFields.elevation.FocusLost:Fire()
 stroke("Flatten",0,0,0)
 check(math.abs(height(0,0)-4)<.6,"Flatten approaches the selected elevation")
 local saved=require("WorldEditorDocument").export(controller.state.document,controller.catalog)
 controller:replaceDocument(saved)
 check(table.concat(controller.state.document.settings.terrain.heights,",")==table.concat(saved.settings.terrain.heights,","),"reopening the terrain draft reproduces all samples")
 local pick=H.pick(saved.settings.terrain,96,96,Vector3.new(30,30,0),Vector3.new(0,-1,0))
 check(pick and pick.Y<0,"surface picker reaches below the original ground plane")
 view.traversability.Activated:Fire()
 check(view.traversalLegend.Visible and controller.scene.terrainOverlay,"traversability toggle paints the saved terrain")
 for _,marker in controller.scene.terrainOverlay.folder:GetChildren() do
  check(not marker.CanQuery and not marker.CanCollide,"overlay markers cannot intercept brush picks or movement")
 end
 view.traversability.Activated:Fire()
 check(not controller.scene.terrainOverlay and not view.traversalLegend.Visible,"disabling traversability releases its overlay geometry")
 controller.pointer=savedPointer
end
controller:destroy()
check(cameraBindings.BattleWorksEditorCamera==nil,"terrain editor cleans up input bindings")
print("Terrain editor sculpting and history passed")

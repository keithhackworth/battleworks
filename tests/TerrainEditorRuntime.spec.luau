do
 local H=require("WorldHeightfield")
 local view=controller.view
 view.newWorld.Activated:Fire()
 view.dimensions.width.Text="96";view.dimensions.width.FocusLost:Fire()
 view.dimensions.depth.Text="96";view.dimensions.depth.FocusLost:Fire()
 view.terrain.Activated:Fire()
 view.brushFields.radius.Text="16";view.brushFields.radius.FocusLost:Fire()
 check(view.terrainTools.Raise.Visible and view.brushPanel.Visible and not view.tools.Move.Visible,"Terrain mode replaces object tools with the brush controls")
 local savedPointer=controller.pointer
 local point=Vector3.zero
 controller.pointer=function()return point,Vector3.new(0,100,0),Vector3.new(0,-1,0),Vector2.zero end
 local mouse1={UserInputType=Enum.UserInputType.MouseButton1,KeyCode=Enum.KeyCode.Unknown}
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

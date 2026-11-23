do
 local H=require("WorldHeightfield")
 local view=controller.view
 view.newWorld.Activated:Fire()
 view.dimensions.width.Text="48";view.dimensions.width.FocusLost:Fire()
 view.dimensions.depth.Text="48";view.dimensions.depth.FocusLost:Fire()
 view.terrain.Activated:Fire()
 local settings=controller.state.document.settings
 settings.terrain=H.new(48,48)
 check(view.dimensions.width.Parent==view.brushPanel,"world size controls are available while sculpting")
 local oldTerrain=controller.state.document.settings.terrain
 oldTerrain.heights[H.index(oldTerrain,4,4)]=32
 oldTerrain.paint=table.create(64,0);oldTerrain.paint[37]=2
 oldTerrain.water=table.create(64,0);oldTerrain.water[37]=H.WaterOffset+40
 view.dimensions.width.Text="72";view.dimensions.width.FocusLost:Fire()
 local resized=controller.state.document.settings
 check(resized.width==72 and resized.depth==48 and resized.terrain.columns==12,"resize regenerates the terrain grid for the new width")
 check(controller.scene.terrainData==resized.terrain and controller.scene.floor.Size.X==72,"resize rebuilds the visible terrain at the new size")
 check(H.sample(resized.terrain,72,48,0,0)==H.sample(oldTerrain,48,48,0,0),"resize keeps the central elevation")
 local material,water=H.surface(resized.terrain,72,48,0,0)
 check(material=="Mud" and water==5,"resize carries paint and water to the new grid")
 controller:history(false)
 check(controller.state.document.settings.width==48 and table.concat(controller.state.document.settings.terrain.heights,",")==table.concat(oldTerrain.heights,","),"undo restores the original dimensions and exact samples")
 controller:history(true)
 local exported=require("WorldEditorDocument").export(controller.state.document,controller.catalog)
 controller:replaceDocument(exported)
 check(controller.state.document.settings.width==72 and controller.state.document.settings.terrain.columns==12,"resized terrain survives export and reopen")
end
do
 local Surface=require("WorldTerrainSurface")
 local H=require("WorldHeightfield")
 local terrain=H.new(25,25)
 terrain.heights[H.index(terrain,2,4)]=40*H.Unit
 terrain.water=table.create(terrain.columns*terrain.rows,0)
 terrain.water[1]=H.WaterOffset+8
 terrain.water[2]=H.WaterOffset+20
 terrain.water[3]=H.WaterOffset+32
 local settings={width=25,depth=25,terrain=terrain,ground={material="Grass",color={100,112,86}}}
 local world=Instance.new("Folder")
 local gameplay=Surface.new(world,settings,true)
 local overlay=Surface.new(world,settings,false,true)
 gameplay:all();overlay:all()
 local water={}
 for _,part in gameplay.folder:GetChildren() do
  if part.Name=="WaterSurface" then
   water[math.round(part.CFrame.Position.X*10)]=part
   check(not part.CanCollide and not part.CanQuery,"water appearance does not add collision or scanner geometry")
  else check(part.Material~=Enum.Material.Neon,"gameplay terrain has no editor slope tint") end
 end
 local keys={};for key in water do table.insert(keys,key) end;table.sort(keys)
 check(#keys==3 and water[keys[1]].Transparency>water[keys[2]].Transparency and water[keys[2]].Transparency>water[keys[3]].Transparency,"water renders intermediate appearance near the depth limit")
 local steep=false
 for _,part in overlay.folder:GetChildren() do
  if part.Shape==Enum.PartType.Wedge and part.CFrame.Position.Z>0 then steep=true end
 end
 check(steep,"editor overlay tints a dry steep slope")
 world:Destroy()
end
controller:destroy()
print("Terrain resize integration passed")

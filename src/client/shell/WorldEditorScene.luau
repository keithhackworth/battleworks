local Shared=game.ReplicatedStorage.Shared
local Placement=require(Shared.ModelPlacement)
local Paths=require(Shared.AssetPaths)
local Math=require(Shared.WorldEditorMath)
local Snap=require(Shared.WorldEditorSnap)
local Visual=require(Shared.AssetGeometry)
local StartingAreas=require(Shared.StartingAreas)
local Heightfield=require(Shared.WorldHeightfield)
local TerrainSurface=require(Shared.WorldTerrainSurface)
local Traversal=require(Shared.TerrainTraversal)
local Materials=require(Shared.TerrainMaterials)
local Components=require(Shared.VehicleComponents)
local Document=require(Shared.WorldEditorDocument)
local Scene={};Scene.__index=Scene
local snapLabelSize=24
local snapLabelOffset=Vector2.new(-12,-26)
local edgeLimit=32
local function part(parent,name,size,frame,color,transparency)
 local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
 p.Size=size;p.CFrame=frame;p.Color=color;p.Transparency=transparency or 0;p.Parent=parent;return p
end
function Scene:edgeMarkers(kind,candidates,chosen,pin)
 self.edgeLabels=self.edgeLabels or {}
 local labels=self.edgeLabels[kind] or {}
 self.edgeLabels[kind]=labels
 for i,candidate in candidates or {} do
  local label=labels[i]
  if not label then
   label=Instance.new("TextLabel");label.Name=kind.."CollisionEdge";label.Text="●"
   label.AnchorPoint=Vector2.new(.5,.5);label.Size=UDim2.fromOffset(18,18)
   label.BackgroundTransparency=1;label.TextStrokeTransparency=.1;label.ZIndex=5
   label.Parent=self.viewport;labels[i]=label
  end
  label.Position=UDim2.fromOffset(candidate.pixel.X,candidate.pixel.Y)
  local active=(chosen and chosen.edge==candidate.edge) or (pin and pin.edgeIndex==candidate.edge.index)
  label.TextColor3=if active then Color3.fromRGB(100,245,145) else Color3.fromRGB(90,210,255)
  label.TextSize=if active then 17 else 12
  label.Visible=true
 end
 for i=(candidates and #candidates or 0)+1,#labels do labels[i].Visible=false end
 self.edgeLines=self.edgeLines or {}
 local line=self.edgeLines[kind]
 if chosen then
  local camera=self.camera.CFrame
  local a=Math.project(camera,self.viewport.AbsoluteSize,chosen.edge.a,self.camera.FieldOfView)
  local b=Math.project(camera,self.viewport.AbsoluteSize,chosen.edge.b,self.camera.FieldOfView)
  if a and b then
   if not line then
    line=Instance.new("Frame");line.Name=kind.."CollisionLine";line.AnchorPoint=Vector2.new(.5,.5)
    line.BackgroundColor3=Color3.fromRGB(100,245,145);line.BorderSizePixel=0;line.ZIndex=4
    line.Parent=self.viewport;self.edgeLines[kind]=line
   end
   local delta=b-a
   line.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2)
   line.Size=UDim2.fromOffset(delta.Magnitude,2)
   line.Rotation=math.deg(math.atan2(delta.Y,delta.X))
   line.Visible=true
   return
  end
 end
 if line then line.Visible=false end
end
function Scene:projectEdges(edges,pixel)
 return Snap.screenEdges(edges,function(point)
  return Math.project(self.camera.CFrame,self.viewport.AbsoluteSize,point,self.camera.FieldOfView)
 end,pixel,edgeLimit)
end
function Scene:clearEdgeTargets()
 self.edgeTargetId=nil;self:edgeMarkers("Target")
end
function Scene.new(viewport,assets,document)
 local world=Instance.new("WorldModel");world.Name="PrivateEditorWorld";world.Parent=viewport
 local camera=Instance.new("Camera");camera.FieldOfView=48;camera.FieldOfViewMode=Enum.FieldOfViewMode.Vertical;camera.Parent=viewport;viewport.CurrentCamera=camera
 local root=Instance.new("Folder");root.Name="Objects";root.Parent=world
 local gizmos=Instance.new("Folder");gizmos.Name="Anchors";gizmos.Parent=world
 local snapGizmos=Instance.new("Folder");snapGizmos.Name="SnapHandles";snapGizmos.Parent=world
 local self=setmetatable({world=world,camera=camera,root=root,gizmos=gizmos,snapGizmos=snapGizmos,models={},assets=assets,document=document,mode="Move",wire={},snapEnds={},snapLabels={},viewport=viewport},Scene)
 for _,endpoint in {"A","B","C","D"} do
  local p=part(snapGizmos,"Snap"..endpoint,Vector3.new(2,2,2),CFrame.new(),if endpoint=="A" then Color3.fromRGB(80,215,255) else Color3.fromRGB(255,183,92),1)
  p.Shape=Enum.PartType.Ball;p.Material=Enum.Material.Neon;p:SetAttribute("EditorHandle","Snap"..endpoint);self.snapEnds[endpoint]=p
  local label=Instance.new("TextLabel");label.Name="SnapLabel"..endpoint;label.Text="↔";label.Size=UDim2.fromOffset(snapLabelSize,snapLabelSize);label.BackgroundTransparency=1;label.TextColor3=p.Color;label.TextSize=18;label.Font=Enum.Font.GothamBold;label.TextStrokeTransparency=.2;label.Visible=false;label.ZIndex=4;label.Parent=viewport;self.snapLabels[endpoint]=label
 end
 local s=document.settings
 self.floor=part(world,"EditorGround",Vector3.new(s.width,1,s.depth),CFrame.new(0,-.5,0),Color3.fromRGB(table.unpack(s.ground.color)));self.floor.Material=Enum.Material[s.ground.material];self.floor.CanQuery=true
 self.spawnModels={}
 self:setMode("Move")
 return self
end
function Scene:template(item) return self.assets and Paths.resolve(self.assets:FindFirstChild("Templates"),item.model) end
function Scene:make(entry,item,parent)
 local template=self:template(item);if not template then return nil,"Native template unavailable: "..item.model end
 local model,reason=Placement.place(self.assets:FindFirstChild("Templates"),{id=entry.id,template=item.model,position=Vector3.new(table.unpack(entry.position)),rotation=Vector3.new(table.unpack(entry.rotation)),scale=entry.scale,stretch=entry.stretch,resizeAxes=item.resizeAxes},nil,parent or self.root)
 if model then
  model:SetAttribute("EditorObjectId",entry.id)
  for _,p in model:GetDescendants() do if p:IsA("BasePart") then p.CanQuery=Visual.visible(p) end end
 end
 return model,reason
end
function Scene:sync(document,catalog,preview)
 self.document=document
 local settings=document.settings
 if self.traversability and not preview then
  local zones,keys={},{settings.ground.material}
  for _,entry in document.objects do
   local item=catalog.byPath[entry.asset]
   if item.zone then
    local zone={x=entry.position[1],z=entry.position[3],rx=entry.bounds[1]*entry.scale/2,rz=entry.bounds[3]*entry.scale/2,
     profile=Materials.forGround(settings.ground.material,item.zone)}
    table.insert(zones,zone);table.insert(keys,table.concat({item.zone,zone.x,zone.z,zone.rx,zone.rz},":"))
   end
  end
  local key=table.concat(keys,";")
  if self.overlayZoneKey~=key then
   self.overlayZoneKey=key;self.overlayZones=zones
   if self.terrainOverlay then self.terrainOverlay:destroy();self.terrainOverlay=nil end
  end
 end
 self:syncTerrain(settings)
 local size=Vector3.new(settings.width,1,settings.depth)
 if self.floor.Size~=size then
  self.floor.Size=size
  if self.gridStep then self:grid(true,self.gridStep) end
 end
 local material=Enum.Material[settings.ground.material]
 if self.floor.Material~=material then self.floor.Material=material end
 local color=Color3.fromRGB(table.unpack(settings.ground.color))
 if self.floor.Color~=color then self.floor.Color=color end
 local retained={}
 for _,entry in document.objects do
  retained[entry.id]=true
  local record=self.models[entry.id]
  if record and record.entry.asset~=entry.asset then
   if record.traversalMarker then record.traversalMarker:Destroy() end
   record.model:Destroy()
   record=nil
  end
  if not record then
   local item=catalog.byPath[entry.asset];local model,err=self:make(entry,item)
   assert(model,err);record={model=model,scale=self:template(item):GetScale()};self.models[entry.id]=record
  end
  record.entry=entry;record.item=catalog.byPath[entry.asset]
  local stretchKey=if entry.stretch then table.concat(entry.stretch,",") else ""
  if record.stretchKey~=stretchKey or record.x~=entry.position[1] or record.y~=entry.position[2] or record.z~=entry.position[3] or record.pitch~=entry.rotation[1] or record.yaw~=entry.rotation[2] or record.roll~=entry.rotation[3] or record.objectScale~=entry.scale then
   Placement.pose(record.model,record.scale,{position=Vector3.new(table.unpack(entry.position)),rotation=Vector3.new(table.unpack(entry.rotation)),scale=entry.scale,stretch=entry.stretch,resizeAxes=record.item.resizeAxes})
   record.stretchKey=stretchKey
   record.snapGeometry=nil
   record.snapSource=nil
   record.x=entry.position[1];record.y=entry.position[2];record.z=entry.position[3];record.pitch=entry.rotation[1];record.yaw=entry.rotation[2];record.roll=entry.rotation[3];record.objectScale=entry.scale
   record.traversalDirty=true
  end
  local traction=settings.terrain and settings.terrain.traction
  if self.traversability and entry.solid and (record.traversalDirty or not record.traversalChecked or record.traversalTraction~=traction) then
   self:markStructure(record,traction)
  elseif (not self.traversability or not entry.solid) and record.traversalChecked then
   if record.traversalMarker then record.traversalMarker:Destroy();record.traversalMarker=nil end
   record.traversalChecked=false
  end
 end
 for id,record in self.models do if not retained[id] then
  if record.traversalMarker then record.traversalMarker:Destroy() end
  record.model:Destroy();self.models[id]=nil
 end end
 local starts={}
 for _,spawn in document.spawns do if spawn.slot then
  starts[spawn.id]=true
  local height=Heightfield.sample(settings.terrain,settings.width,settings.depth,spawn.position[1],spawn.position[3])
  local key=table.concat(spawn.position,",")..":"..spawn.heading..":"..spawn.slot..":"..height
  local old=self.spawnModels[spawn.id]
  if not old or old.key~=key then
   local model
   if old and old.heading==spawn.heading and old.slot==spawn.slot then
    model=old.model;model:PivotTo(CFrame.new(spawn.position[1]-old.x,height-old.height,spawn.position[3]-old.z)*model:GetPivot())
   else if old then old.model:Destroy() end;model=StartingAreas.make(self.root,spawn,true,height) end
   self.spawnModels[spawn.id]={key=key,spawn=true,model=model,entry=spawn,x=spawn.position[1],z=spawn.position[3],height=height,heading=spawn.heading,slot=spawn.slot}
  end
 end end
 for id,record in self.spawnModels do if not starts[id] then record.model:Destroy();self.spawnModels[id]=nil end end
end
function Scene:markStructure(record,traction)
 record.traversalDirty=false;record.traversalChecked=true
 record.traversalTraction=traction
 local native=Placement.stretchPart(record.model)
 if not native then return end
 local slope=math.acos(math.clamp(native.CFrame.UpVector.Y,0,1))
 local profile=Materials.withTraction(Materials.fromMaterial(native.Material),traction)
 local color=TerrainSurface.TraversalColors[Traversal.classify(slope,0,profile)]
 if not color then
  if record.traversalMarker then record.traversalMarker:Destroy();record.traversalMarker=nil end
  return
 end
 local marker=record.traversalMarker or part(self.world,"PlacedTraversability",Vector3.one,CFrame.new(),color,.38)
 marker.Color=color;marker.Material=Enum.Material.Neon
 marker.Size=Vector3.new(native.Size.X,.05,native.Size.Z)
 marker.CFrame=native.CFrame*CFrame.new(0,native.Size.Y/2+.06,0)
 record.traversalMarker=marker
end
function Scene:syncTerrain(settings,dirty)
 if self.terrainData~=settings.terrain or (settings.terrain and self.terrain.settings~=settings) then
  if self.terrain then self.terrain:destroy();self.terrain=nil end
  self.terrainData=settings.terrain
  if settings.terrain then self.terrain=TerrainSurface.new(self.world,settings,false);self.terrain:all() end
 elseif dirty and self.terrain then
  for _,chunk in dirty do self.terrain:chunk(chunk[1],chunk[2]) end
 end
 self.floor.Transparency=if self.terrain then 1 else 0
 self.floor.CanQuery=self.terrain==nil
 if self.traversability then
  if not self.terrainOverlay or self.overlaySource~=settings.terrain or self.overlayWidth~=settings.width or self.overlayDepth~=settings.depth
   or self.overlayMaterial~=settings.ground.material then
   if self.terrainOverlay then self.terrainOverlay:destroy() end
   local config=table.clone(settings)
   config.traversalZones=self.overlayZones
   config.terrain=settings.terrain or Heightfield.new(settings.width,settings.depth)
   self.terrainOverlay=TerrainSurface.new(self.world,config,false,true);self.terrainOverlay:all()
   self.overlaySource=settings.terrain;self.overlayWidth=settings.width;self.overlayDepth=settings.depth;self.overlayMaterial=settings.ground.material
  elseif dirty then
   for _,chunk in dirty do self.terrainOverlay:chunk(chunk[1],chunk[2]) end
  end
 elseif self.terrainOverlay then self.terrainOverlay:destroy();self.terrainOverlay=nil end
end
function Scene.buildTankScale(viewport)
 local chassis=Components.get("Boomer").Chassis
 local size=chassis.Hitbox
 local camera=Instance.new("Camera")
 camera.FieldOfView=36
 camera.FieldOfViewMode=Enum.FieldOfViewMode.Vertical
 camera.CFrame=CFrame.lookAt(Vector3.new(18,14,-19),Vector3.new(0,size.Y*.45,-1))
 camera.Parent=viewport;viewport.CurrentCamera=camera
 local function piece(name,dimensions,x,y,z,color)
  part(viewport,name,dimensions,CFrame.new(x,y,z),color)
 end
 local hull=Color3.fromRGB(112,184,197)
 local tracks=Color3.fromRGB(56,86,101)
 piece("Footprint",Vector3.new(chassis.CollisionWidth,.04,chassis.CollisionLength),0,-.04,0,tracks)
 for _,side in {-1,1} do
  piece("Track",Vector3.new(size.X*.18,size.Y*.42,size.Z),side*size.X*.41,size.Y*.21,0,tracks)
 end
 piece("Hull",Vector3.new(size.X*.65,size.Y*.42,size.Z*.78),0,size.Y*.43,0,hull)
 piece("Turret",Vector3.new(size.X*.45,size.Y*.36,size.Z*.39),0,size.Y*.82,0,hull)
 piece("Barrel",Vector3.new(.65,.65,size.Z*.48),0,size.Y*.82,-size.Z*.40,hull)
 return chassis.CollisionWidth,chassis.CollisionLength
end
function Scene:updateTankScale(view,offset,distance)
 local size=self.viewport.AbsoluteSize
 if size.X<=0 or size.Y<=0 then return end
 local camera=view.tankScaleViewport.CurrentCamera
 if self.scaleCameraOffset~=offset then
  self.scaleCameraOffset=offset
  camera.CFrame=CFrame.lookAt(offset,Vector3.zero)
 end
 local editorFov=self.camera.FieldOfView
 if self.scaleViewportSize==size and self.scaleDistance==distance and self.scaleEditorFov==editorFov then return end
 self.scaleViewportSize=size;self.scaleDistance=distance;self.scaleEditorFov=editorFov
 local halfTangent=math.tan(math.rad(editorFov)/2)
 -- Keep the same pixel focal length as the main viewport. The card can
 -- grow to fit close-ups without making the tank itself larger or smaller.
 local radius=10
 local projected=math.ceil(size.Y*radius/(math.max(1,distance-radius)*halfTangent))
 local minHeight=math.max(32,math.ceil(size.Y/45))
 local height=math.clamp(projected,minHeight,math.max(minHeight,math.floor(size.Y*.35)-40))
 local availableWidth=math.max(1,size.X-20)
 local minWidth=math.min(112,availableWidth)
 local maxWidth=math.min(availableWidth,math.max(minWidth,math.floor(size.X*.3)))
 local width=math.clamp(projected,minWidth,maxWidth)
 local cardSize=UDim2.fromOffset(width,height+40)
 if view.tankScaleCard.Size~=cardSize then view.tankScaleCard.Size=cardSize end
 local fieldOfView=math.deg(2*math.atan(halfTangent*height/size.Y))
 if camera.FieldOfView~=fieldOfView then camera.FieldOfView=fieldOfView end
end
function Scene:brushFootprint(point,radius)
 if not point then
  if self.brushRing then self.brushRing.Parent=nil end
  return
 end
 if not self.brushRing then
  self.brushRing=Instance.new("Folder");self.brushRing.Name="TerrainBrushFootprint";self.brushLines={}
  for i=1,28 do
   local line=part(self.brushRing,"BrushEdge",Vector3.one,CFrame.new(),Color3.fromRGB(255,163,49))
   line.Material=Enum.Material.Neon;self.brushLines[i]=line
  end
 end
 if self.brushRing.Parent~=self.world then self.brushRing.Parent=self.world end
 local settings=self.document.settings
 local previous
 for i=0,28 do
  local angle=i*2*math.pi/28
  local x,z=point.X+math.cos(angle)*radius,point.Z+math.sin(angle)*radius
  local p=Vector3.new(x,.18+Heightfield.sample(settings.terrain,settings.width,settings.depth,x,z),z)
  if previous then
   local line=self.brushLines[i]
   line.Size=Vector3.new(.18,.13,(p-previous).Magnitude)
   line.CFrame=CFrame.lookAt((p+previous)*.5,p)
   line.Transparency=if math.abs(x)>settings.width/2 or math.abs(z)>settings.depth/2 then 1 else 0
  end
  previous=p
 end
end
function Scene:startPreview(spawn,valid)
 if not spawn then if self.startGhost then self.startGhost:Destroy();self.startGhost=nil end;return end
 if self.startGhost and self.startGhostSlot==spawn.slot and self.startGhostValid==valid then
  self.startGhost:PivotTo(CFrame.new(spawn.position[1]-self.startGhostX,0,spawn.position[3]-self.startGhostZ)*self.startGhost:GetPivot())
  self.startGhostX=spawn.position[1];self.startGhostZ=spawn.position[3];return
 end
 if self.startGhost then self.startGhost:Destroy() end
 self.startGhost=StartingAreas.make(self.world,spawn,false)
 self.startGhostSlot=spawn.slot;self.startGhostValid=valid;self.startGhostX=spawn.position[1];self.startGhostZ=spawn.position[3]
 for _,p in self.startGhost:GetDescendants() do if p:IsA("BasePart") then p.Transparency=.4;if not valid then p.Color=Color3.fromRGB(245,90,75) end end end
end
function Scene:ghost(entry,item,valid)
 if self.ghostPath~=item.model then
  self:clearGhost();local model=self:make(entry,item,self.world);if not model then return end
  self.ghostModel=model;self.ghostPath=item.model
 end
 if not self.ghostModel then return end
 Placement.pose(self.ghostModel,self:template(item):GetScale(),{position=Vector3.new(table.unpack(entry.position)),rotation=Vector3.new(table.unpack(entry.rotation)),scale=entry.scale})
 for _,p in self.ghostModel:GetDescendants() do if p:IsA("BasePart") then p.CanQuery=false;p.Transparency=.6;p.Color=if valid then Color3.fromRGB(94,224,171) else Color3.fromRGB(244,95,78) end end
end
function Scene:clearGhost()
 if self.ghostModel then self.ghostModel:Destroy() end
 self.ghostModel=nil;self.ghostPath=nil
end
function Scene:setMode(mode,rotationAxis)
 self.mode=mode
 self.rotationAxis=rotationAxis or "Yaw"
 for _,p in self.gizmos:GetChildren() do p:Destroy() end
 self.anchors={}
 local function anchor(code,color)
  local p=part(self.gizmos,code,Vector3.new(1.8,1.8,1.8),CFrame.new(),color);p.Material=Enum.Material.Neon;p.Shape=Enum.PartType.Ball;p.CanQuery=true;p:SetAttribute("EditorHandle",code)
  self.anchors[code]=p
 end
 if mode=="Move" then anchor("MoveX",Color3.fromRGB(248,105,90));anchor("MoveY",Color3.fromRGB(120,232,174));anchor("MoveZ",Color3.fromRGB(85,170,255))
 elseif mode=="Rotate" then
  local prefix=if self.rotationAxis=="Pitch" then "RotatePitch" elseif self.rotationAxis=="Roll" then "RotateRoll" else "Rotate"
  local color=if self.rotationAxis=="Pitch" then Color3.fromRGB(248,105,90) elseif self.rotationAxis=="Roll" then Color3.fromRGB(85,170,255) else Color3.fromRGB(245,194,75)
  for i=1,16 do anchor(prefix..i,color) end
 elseif mode=="Scale" then anchor("Scale",Color3.fromRGB(120,232,174))
 elseif mode=="Resize" then
  anchor("ResizeX",Color3.fromRGB(248,105,90));anchor("ResizeY",Color3.fromRGB(120,232,174));anchor("ResizeZ",Color3.fromRGB(85,170,255))
 end
end
function Scene:selection(id,distance)
 local record=id and (self.models[id] or self.spawnModels[id])
 local size=math.clamp(distance*.012,1,3)
 for _,p in self.gizmos:GetChildren() do
  local enabled=record~=nil and (not record.spawn or (self.mode=="Move" and p.Name~="MoveY"))
  local axis=Math.resizeAxis(p.Name)
  if axis then enabled=enabled and Document.canResize(record.item,axis) end
  p.Transparency=if enabled then 0 else 1;p.CanQuery=enabled
 end
 for endpoint,p in self.snapEnds do p.Transparency=1;p.CanQuery=false;self.snapLabels[endpoint].Visible=false end
 local pin=self.snapPins and self.snapPins[id]
 self.sourceChoices=nil
 if self.mode=="Snap" and record and not record.spawn and record.item and self.sourcePixel and not self.draggingSnap then
  if not record.snapSource then record.snapSource=Snap.sourceOptions(record.entry,record.item.collider) end
  self.sourceChoices=record.snapSource
  if self.sourceChoices then
   local choice,candidates=self:projectEdges(self.sourceChoices,self.sourcePixel)
   self:edgeMarkers("Source",candidates,choice,pin)
  else self:edgeMarkers("Source") end
 else self:edgeMarkers("Source") end
 if not record then for _,p in self.wire do p.Transparency=1 end;return end
 if self.mode=="Snap" and not record.spawn then
  local ends=Snap.ends(record.entry,if pin then pin.side else self.snapSide,record.item and record.item.collider)
  for endpoint,p in self.snapEnds do
   local pinned=pin and ((not pin.edgeIndex and pin.endpoint==endpoint) or (pin.second and not pin.second.edgeIndex and pin.second.endpoint==endpoint))
   p.Color=if pinned then Color3.fromRGB(100,245,145) elseif endpoint=="A" then Color3.fromRGB(80,215,255) else Color3.fromRGB(255,183,92)
   p.Transparency=0;p.CanQuery=true;p.Size=Vector3.new(size*1.3,size*1.3,size*1.3);p.CFrame=CFrame.new(ends[endpoint])
   local pixel=Math.project(self.camera.CFrame,self.viewport.AbsoluteSize,ends[endpoint],self.camera.FieldOfView)
   local label=self.snapLabels[endpoint];label.Visible=pixel~=nil
   if pixel then label.Position=UDim2.fromOffset(pixel.X+snapLabelOffset.X,pixel.Y+snapLabelOffset.Y);label.TextColor3=p.Color end
  end
 end
 local box,bounds=Visual.measure(record.model)
 local center=box.Position
 local reach=math.max(bounds.X,bounds.Y,bounds.Z)/2+size*2
 for code,p in self.anchors do
  p.Size=Vector3.new(size,size,size)
  local offset
  local axis=Math.resizeAxis(code)
  if axis then
   local axes={box.RightVector,box.UpVector,box.LookVector*-1}
   local extents={bounds.X,bounds.Y,bounds.Z}
   offset=axes[axis]*(extents[axis]/2+size*2)
  elseif code=="MoveY" then offset=Vector3.new(0,reach,0)
  elseif code:find("X",1,true) then offset=Vector3.new(reach,0,0)
  elseif code:find("Z",1,true) then offset=Vector3.new(0,0,reach)
  elseif code=="Scale" then offset=Vector3.new(reach,0,reach)
  else
   local i=tonumber(code:match("%d+"));local a=i*math.pi/8
   local kind=if self.rotationAxis=="Pitch" then "RotatePitch" elseif self.rotationAxis=="Roll" then "RotateRoll" else "Rotate"
   local u,v=Math.rotationBasis({rotation={record.pitch or 0,record.yaw or 0,record.roll or 0}},kind)
   offset=(u*math.cos(a)+v*math.sin(a))*reach
  end
  p.CFrame=CFrame.new(center+offset)
 end
 local index=0
 -- Actual wire geometry renders in ViewportFrames, unlike Studio Handles.
 for axis=1,3 do
  local other={};for a=1,3 do if a~=axis then table.insert(other,a) end end
  for _,u in {-1,1} do for _,v in {-1,1} do
   index+=1
   if not self.wire[index] then self.wire[index]=part(self.world,"SelectionOutline",Vector3.new(1,1,1),CFrame.new(),Color3.fromRGB(255,209,91));self.wire[index].Material=Enum.Material.Neon end
   local dimensions={.12,.12,.12};dimensions[axis]=({bounds.X,bounds.Y,bounds.Z})[axis]+.18
   local at={0,0,0};local extents={bounds.X,bounds.Y,bounds.Z};at[other[1]]=u*extents[other[1]]/2;at[other[2]]=v*extents[other[2]]/2
   local p=self.wire[index];p.Transparency=0;p.Size=Vector3.new(table.unpack(dimensions));p.CFrame=box*CFrame.new(table.unpack(at))
  end end
 end
end
function Scene:setSnap(enabled,pins,side)self.snapEnabled=enabled;self.snapPins=pins;self.snapSide=side or 0 end
function Scene:collisionSnap(record)
 local profile=record.item and record.item.collider
 if not profile or profile.fit~="faces" then return nil end
 if not record.snapGeometry or record.snapProfile~=profile then
  record.snapGeometry=Snap.collisionGeometry(record.entry,profile);record.snapProfile=profile
 end
 return record.snapGeometry
end
function Scene:nearbySnap(entry,point)
 local record=self.models[entry.id]
 local geometry=record and self:collisionSnap(record)
 if geometry then return Snap.collisionTarget(entry,geometry,point,Snap.Radius) end
 return Snap.target(entry,point,Snap.Radius)
end
function Scene:snapTarget(origin,direction,ignore,previous,pixel)
 local include={self.floor}
 local selected,selectedGeometry,contact,limit
 limit=5000
 for id,record in self.models do
  if id~=ignore then
   local geometry=self:collisionSnap(record)
   if geometry then
    local hit,distance=Snap.collisionHit(geometry,origin,direction,limit)
    if hit then selected=record;selectedGeometry=geometry;contact=hit;limit=distance end
   else table.insert(include,record.model) end
  end
 end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=include;params.RespectCanCollide=false
 local hit=self.world:Raycast(origin,direction*5000,params)
 local onCollision=contact and (not hit or limit<=(hit.Position-origin).Magnitude)
 if pixel then
  local hovered=if onCollision then selected else self.edgeTargetId and self.models[self.edgeTargetId]
  local geometry=hovered and hovered.entry.id~=ignore and self:collisionSnap(hovered)
  if geometry then
   local choice,candidates=self:projectEdges(geometry.edges,pixel)
   if #candidates>0 then
    self.edgeTargetId=hovered.entry.id;self:edgeMarkers("Target",candidates,choice)
    if choice then return Snap.edgeTarget(hovered.entry,choice) end
   else self:clearEdgeTargets() end
  else self:clearEdgeTargets() end
 end
 if onCollision then
  return Snap.collisionTarget(selected.entry,selectedGeometry,contact.point,Snap.Radius,contact.normal)
 end
 if not hit then return nil end
 if hit.Instance==self.floor then return {point={hit.Position.X,0,hit.Position.Z},normal={0,1,0},targetId="ground",kind="ground"} end
 local p=hit.Instance
 while p and p~=self.world do
  local id=p:GetAttribute("EditorObjectId")
  if id then
   local record=self.models[id];if not record then return nil end
   local target=Snap.target(record.entry,hit.Position,Snap.Radius,previous)
   if record.entry.asset:sub(1,8)=="Builtin/" then return target end
   -- Imported geometry need not reach the upper face of its rectangular bounds
   -- (rocks, roofs, arches). A native visible surface hit remains a valid target.
   if target and target.kind~="face" and hit.Normal then
    local point=Vector3.new(table.unpack(target.point));local normal=Vector3.new(table.unpack(target.normal))
    local surfaceParams=RaycastParams.new();surfaceParams.FilterType=Enum.RaycastFilterType.Include;surfaceParams.FilterDescendantsInstances={record.model};surfaceParams.RespectCanCollide=false
    local probe=self.world:Raycast(point+normal*.2,normal*-.4,surfaceParams)
    if probe and (probe.Position-point).Magnitude<.08 then return target end
   end
   return {point={hit.Position.X,hit.Position.Y,hit.Position.Z},normal=if hit.Normal then {hit.Normal.X,hit.Normal.Y,hit.Normal.Z} else {0,1,0},targetId=id,kind="surface"}
  end
  p=p.Parent
 end
end
function Scene:snapFeedback(target,valid)
 if not target then
  if self.snapContact then self.snapContact.Transparency=1;self.snapEdge.Transparency=1 end
  return
 end
 if not self.snapFeedbackFolder then
  local folder=Instance.new("Folder");folder.Name="SnapPreview";folder.Parent=self.world;self.snapFeedbackFolder=folder
  self.snapContact=part(folder,"SnapContact",Vector3.new(.6,.6,.6),CFrame.new(),Color3.fromRGB(100,245,145))
  self.snapContact.Shape=Enum.PartType.Ball;self.snapContact.Material=Enum.Material.Neon
  self.snapEdge=part(folder,"SnapEdge",Vector3.new(.14,.14,1),CFrame.new(),self.snapContact.Color,1);self.snapEdge.Material=Enum.Material.Neon
 end
 local color=if valid then Color3.fromRGB(100,245,145) else Color3.fromRGB(245,90,75)
 local point=Vector3.new(table.unpack(target.point))
 self.snapContact.CFrame=CFrame.new(point);self.snapContact.Color=color;self.snapContact.Transparency=0
 self.snapEdge.Transparency=1
 if target.edge then
  local a,b=Vector3.new(table.unpack(target.edge[1])),Vector3.new(table.unpack(target.edge[2]))
  if (b-a).Magnitude>.001 then self.snapEdge.Size=Vector3.new(.14,.14,(b-a).Magnitude);self.snapEdge.CFrame=CFrame.lookAt((a+b)/2,b);self.snapEdge.Color=color;self.snapEdge.Transparency=0 end
 end
end
function Scene:grid(enabled,step)
 self.gridStep=if enabled then step else nil
 if self.gridFolder then self.gridFolder:Destroy();self.gridFolder=nil end
 if not enabled then return end
 local folder=Instance.new("Folder");folder.Name="Grid";folder.Parent=self.world;self.gridFolder=folder
 local w,d=self.document.settings.width,self.document.settings.depth
 step*=math.max(1,math.ceil(math.max(w,d)/(step*40)))
 for x=-math.floor(w/2/step)*step,w/2,step do part(folder,"GridLine",Vector3.new(.035,.02,d),CFrame.new(x,.02,0),Color3.fromRGB(190,215,195),.65) end
 for z=-math.floor(d/2/step)*step,d/2,step do part(folder,"GridLine",Vector3.new(w,.02,.035),CFrame.new(0,.02,z),Color3.fromRGB(190,215,195),.65) end
end
function Scene:pick(origin,direction,pixel,viewportSize)
 local function kind(code)
  if code:sub(1,11)=="RotatePitch" then return "RotatePitch" end
  if code:sub(1,10)=="RotateRoll" then return "RotateRoll" end
  return if code:sub(1,6)=="Rotate" then "Rotate" else code
 end
 -- Use a small pixel hit area for visible anchors. A thin ring/axis handle
 -- should not lose to the object's mesh or require a pixel-perfect click.
 if pixel and viewportSize then
  local chosen,best,bestDepth,bestPriority=nil,math.huge,math.huge,-1
  local pickable=table.clone(self.anchors)
  for endpoint,p in self.snapEnds do pickable["Snap"..endpoint]=p end
  for code,p in pickable do
   if p.CanQuery and p.Transparency<1 then
    local at,depth=Math.project(self.camera.CFrame,viewportSize,p.CFrame.Position,self.camera.FieldOfView)
    if at and at.X>=0 and at.Y>=0 and at.X<=viewportSize.X and at.Y<=viewportSize.Y then
     local distance=(at-pixel).Magnitude
     local radius=math.max(10,p.Size.X*viewportSize.Y/(4*depth*math.tan(math.rad(self.camera.FieldOfView)/2))+3)
     -- A buried sphere may only be visible through its overlay arrow. Include
     -- that rendered label before querying bodies, so it cannot select the
     -- overlapping object instead of dragging this selected object's handle.
     local label=self.snapLabels[code:match("^Snap([ABCD])$")]
     local relative=pixel-at-snapLabelOffset
     local onLabel=label and label.Visible and relative.X>=0 and relative.Y>=0 and relative.X<=snapLabelSize and relative.Y<=snapLabelSize
     local priority=if distance<=6 then 2 elseif onLabel then 1 else 0
     if onLabel then distance=math.min(distance,(relative-Vector2.new(snapLabelSize/2,snapLabelSize/2)).Magnitude) end
     if (distance<=radius or onLabel) and (priority>bestPriority or (priority==bestPriority and (distance<best or (distance==best and depth<bestDepth)))) then chosen=code;best=distance;bestDepth=depth;bestPriority=priority end
    end
   end
  end
  if self.sourceChoices then
   local choice=self:projectEdges(self.sourceChoices,pixel)
   if choice and (not chosen or choice.priority>bestPriority or (choice.priority==bestPriority and choice.distance<best)) then
    return nil,"Snap"..choice.edge.side,choice
   end
  end
  if chosen then return nil,kind(chosen) end
 end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.RespectCanCollide=false
 -- Test gizmos separately so the model body cannot steal an anchor click.
 params.FilterDescendantsInstances={self.gizmos,self.snapGizmos}
 local hit=self.world:Raycast(origin,direction*5000,params)
 if hit then
  local handle=hit.Instance:GetAttribute("EditorHandle")
  if handle then return nil,kind(handle) end
 end
 params.FilterDescendantsInstances={self.root}
 hit=self.world:Raycast(origin,direction*5000,params)
 if not hit then return nil end
 local p=hit.Instance
 while p and p~=self.world do local id=p:GetAttribute("EditorObjectId");if id then return id end;p=p.Parent end
end
function Scene:destroy()
 if self.tankScale then self.tankScale:Destroy() end
 if self.terrain then self.terrain:destroy() end
 if self.terrainOverlay then self.terrainOverlay:destroy() end
 if self.brushRing then self.brushRing:Destroy() end
 self.world:Destroy();self.camera:Destroy();for _,label in self.snapLabels do label:Destroy() end
 for _,labels in self.edgeLabels or {} do for _,label in labels do label:Destroy() end end
 for _,line in self.edgeLines or {} do line:Destroy() end
end
return Scene

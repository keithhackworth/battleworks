local Shared=game.ReplicatedStorage.Shared
local Placement=require(Shared.ModelPlacement)
local Paths=require(Shared.AssetPaths)
local Math=require(Shared.WorldEditorMath)
local Scene={};Scene.__index=Scene
local function part(parent,name,size,frame,color,transparency)
 local p=Instance.new("Part");p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
 p.Size=size;p.CFrame=frame;p.Color=color;p.Transparency=transparency or 0;p.Parent=parent;return p
end
function Scene.new(viewport,assets,document)
 local world=Instance.new("WorldModel");world.Name="PrivateEditorWorld";world.Parent=viewport
 local camera=Instance.new("Camera");camera.FieldOfView=48;camera.FieldOfViewMode=Enum.FieldOfViewMode.Vertical;camera.Parent=viewport;viewport.CurrentCamera=camera
 local root=Instance.new("Folder");root.Name="Objects";root.Parent=world
 local gizmos=Instance.new("Folder");gizmos.Name="Anchors";gizmos.Parent=world
 local self=setmetatable({world=world,camera=camera,root=root,gizmos=gizmos,models={},assets=assets,document=document,mode="Move",wire={}},Scene)
 local s=document.settings
 self.floor=part(world,"EditorGround",Vector3.new(s.width,1,s.depth),CFrame.new(0,-.5,0),Color3.fromRGB(table.unpack(s.ground.color)));self.floor.Material=Enum.Material[s.ground.material];self.floor.CanQuery=true
 for _,spawn in document.spawns do
  local marker=part(world,spawn.tank.."Spawn",Vector3.new(10,.12,12),CFrame.new(spawn.position[1],.08,spawn.position[3])*CFrame.Angles(0,-math.rad(spawn.heading),0),if spawn.tank=="Boomer" then Color3.fromRGB(244,172,75) else Color3.fromRGB(80,215,128),.35)
  marker.CanQuery=false
 end
 self:setMode("Move")
 return self
end
function Scene:template(item) return self.assets and Paths.resolve(self.assets:FindFirstChild("Templates"),item.model) end
function Scene:make(entry,item,parent)
 local template=self:template(item);if not template then return nil,"Native template unavailable: "..item.model end
 local model,reason=Placement.place(self.assets:FindFirstChild("Templates"),{id=entry.id,template=item.model,position=Vector3.new(table.unpack(entry.position)),rotation=Vector3.new(table.unpack(entry.rotation)),scale=entry.scale},nil,parent or self.root)
 if model then
  model:SetAttribute("EditorObjectId",entry.id)
  for _,p in model:GetDescendants() do if p:IsA("BasePart") then p.CanQuery=true end end
 end
 return model,reason
end
function Scene:sync(document,catalog)
 self.document=document
 local retained={}
 for _,entry in document.objects do
  retained[entry.id]=true
  local record=self.models[entry.id]
  if not record then
   local item=catalog.byPath[entry.asset];local model,err=self:make(entry,item)
   assert(model,err);record={model=model,scale=self:template(item):GetScale()};self.models[entry.id]=record
  end
  if record.x~=entry.position[1] or record.y~=entry.position[2] or record.z~=entry.position[3] or record.pitch~=entry.rotation[1] or record.yaw~=entry.rotation[2] or record.roll~=entry.rotation[3] or record.objectScale~=entry.scale then
   Placement.pose(record.model,record.scale,{position=Vector3.new(table.unpack(entry.position)),rotation=Vector3.new(table.unpack(entry.rotation)),scale=entry.scale})
   record.x=entry.position[1];record.y=entry.position[2];record.z=entry.position[3];record.pitch=entry.rotation[1];record.yaw=entry.rotation[2];record.roll=entry.rotation[3];record.objectScale=entry.scale
  end
 end
 for id,record in self.models do if not retained[id] then record.model:Destroy();self.models[id]=nil end end
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
 end
end
function Scene:selection(id,distance)
 local record=id and self.models[id]
 local size=math.clamp(distance*.012,1,3)
 for _,p in self.gizmos:GetChildren() do p.Transparency=if record then 0 else 1;p.CanQuery=record~=nil end
 if not record then for _,p in self.wire do p.Transparency=1 end;return end
 local box,bounds=record.model:GetBoundingBox();local center=box.Position
 local reach=math.max(bounds.X,bounds.Y,bounds.Z)/2+size*2
 for code,p in self.anchors do
  p.Size=Vector3.new(size,size,size)
  local offset
  if code=="MoveY" then offset=Vector3.new(0,reach,0)
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
function Scene:grid(enabled,step)
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
  local chosen,best,bestDepth=nil,math.huge,math.huge
  for code,p in self.anchors do
   if p.CanQuery and p.Transparency<1 then
    local at,depth=Math.project(self.camera.CFrame,viewportSize,p.CFrame.Position,self.camera.FieldOfView)
    if at and at.X>=0 and at.Y>=0 and at.X<=viewportSize.X and at.Y<=viewportSize.Y then
     local distance=(at-pixel).Magnitude
     local radius=math.max(10,p.Size.X*viewportSize.Y/(4*depth*math.tan(math.rad(self.camera.FieldOfView)/2))+3)
     if distance<=radius and (distance<best or (distance==best and depth<bestDepth)) then chosen=code;best=distance;bestDepth=depth end
    end
   end
  end
  if chosen then return nil,kind(chosen) end
 end
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.RespectCanCollide=false
 -- Test gizmos separately so the model body cannot steal an anchor click.
 params.FilterDescendantsInstances={self.gizmos}
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
function Scene:destroy() self.world:Destroy();self.camera:Destroy() end
return Scene

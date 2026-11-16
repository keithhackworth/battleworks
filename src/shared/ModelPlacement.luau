-- Native Studio-imported Model cloning only. No GLB parsing or asset downloads.
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local Placement={}
local nativeSizes=setmetatable({},{__mode="k"})
function Placement.stretchPart(model)
 local selected
 for _,p in model:GetDescendants() do
  if p:IsA("BasePart") then
   if selected or not p:IsA("Part") or p.Shape~=Enum.PartType.Block then return nil end
   for _,child in p:GetChildren() do if child:IsA("DataModelMesh") then return nil end end
   selected=p
  end
 end
 if not selected then return nil end
 -- An angled child would require shear, which a native Part cannot represent.
 local pivot=model:GetPivot()
 for _,axis in {"RightVector","UpVector","LookVector"} do
  local a,b=pivot[axis],selected.CFrame[axis]
  if math.abs(a.X*b.X+a.Y*b.Y+a.Z*b.Z)<.99999 then return nil end
 end
 return selected
end
function Placement.pose(model,templateScale,spec)
 local p=if spec.stretch or nativeSizes[model] then Placement.stretchPart(model) else nil
 if spec.stretch then assert(p,"Stretch requires a single aligned native block asset") end
 if p and not nativeSizes[model] then nativeSizes[model]=p.Size/model:GetScale()*templateScale end
 model:ScaleTo(templateScale*spec.scale)
 if p then
  local s=spec.stretch or {1,1,1};local size=nativeSizes[model]*spec.scale
  p.Size=Vector3.new(size.X*s[1],size.Y*s[2],size.Z*s[3])
 end
 local r=spec.rotation
 model:PivotTo(CFrame.Angles(math.rad(r.X),math.rad(r.Y),math.rad(r.Z)))
 local bounds,size=model:GetBoundingBox()
 local halfHeight=(math.abs(bounds.RightVector.Y)*size.X+math.abs(bounds.UpVector.Y)*size.Y+math.abs(bounds.LookVector.Y)*size.Z)/2
 local offset=Vector3.new(spec.position.X-bounds.Position.X,spec.position.Y-(bounds.Position.Y-halfHeight),spec.position.Z-bounds.Position.Z)
 model:PivotTo(CFrame.new(offset)*model:GetPivot())
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Placement.place(assets,spec,arena,destination,builtins)
 if not spec or type(spec.id)~="string" or spec.id=="" or type(spec.template)~="string" or typeof(spec.position)~="Vector3" or typeof(spec.rotation)~="Vector3" or not finite(spec.scale) or spec.scale<=0 then
  return nil,"Invalid imported-model placement configuration."
 end
 for _,v in {spec.position,spec.rotation} do if not finite(v.X) or not finite(v.Y) or not finite(v.Z) then return nil,"Invalid placement coordinates." end end
 if spec.stretch then
  if type(spec.stretch)~="table" or #spec.stretch~=3 then return nil,"Invalid stretch factors" end
  for _,n in spec.stretch do if not finite(n) or n<.001 or n>1000 then return nil,"Invalid stretch factors" end end
 end
 local template,pathError=Paths.resolve(assets,spec.template)
 if not template and builtins then template,pathError=Paths.resolve(builtins,spec.template) end
 if not template or not template:IsA("Model") then
  return nil,"Import "..(spec.source or spec.asset or spec.template).." as Model ServerStorage/BattleWorksAssets/"..spec.template.." in Edit mode. "..tostring(pathError or "")
 end
 local hasParts=false
 for _,part in template:GetDescendants() do if part:IsA("BasePart") then hasParts=true; break end end
 if not hasParts then return nil,"Imported Model '"..spec.template.."' has no mesh/part geometry." end
 local clone
 local ok,reason=pcall(function()
  clone=template:Clone(); assert(clone,"Imported Model is not Archivable.")
  clone.Name=spec.id
  for _,part in clone:GetDescendants() do
   if part:IsA("LuaSourceContainer") then part:Destroy()
   elseif part:IsA("BasePart") then part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false end
  end
  Placement.pose(clone,template:GetScale(),spec)
  local folder=destination
  if not folder then
   local old=arena:FindFirstChild("WorldScenery"); if old then old:Destroy() end
   folder=Instance.new("Folder"); folder.Name="WorldScenery"; folder.Parent=arena
  end
  clone.Parent=folder
 end)
 if not ok then if clone then clone:Destroy() end; return nil,"Cannot place imported Model '"..spec.template.."': "..tostring(reason) end
 return clone
end
-- Build off-tree first: missing panels must not leave a partial selected world.
function Placement.placeMany(assets,specs,arena,configure,builtins)
 if type(specs)~="table" or #specs>512 then return nil,"Imported worlds require 0–512 placements." end
 local folder=Instance.new("Folder"); folder.Name="WorldScenery"
 local models={}; local ids={}
 for _,spec in specs do
  if type(spec)~="table" or type(spec.id)~="string" or ids[spec.id] then folder:Destroy(); return nil,"Invalid/duplicate imported placement ID." end
  ids[spec.id]=true
  local model,reason=Placement.place(assets,spec,arena,folder,builtins)
  if not model then folder:Destroy(); return nil,reason end
  table.insert(models,model)
  if configure then
   local ok,err=pcall(configure,model,spec)
   if not ok then folder:Destroy(); return nil,"Invalid world interaction: "..tostring(err) end
  end
 end
 local old=arena:FindFirstChild("WorldScenery"); if old then old:Destroy() end
 folder.Parent=arena
 return models
end
return Placement

-- Native Studio-imported Model cloning only. No GLB parsing or asset downloads.
local Placement={}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Placement.place(assets,spec,arena,destination)
 if not spec or type(spec.id)~="string" or spec.id=="" or type(spec.template)~="string" or typeof(spec.position)~="Vector3" or typeof(spec.rotation)~="Vector3" or not finite(spec.scale) or spec.scale<=0 then
  return nil,"Invalid imported-model placement configuration."
 end
 for _,v in {spec.position,spec.rotation} do if not finite(v.X) or not finite(v.Y) or not finite(v.Z) then return nil,"Invalid placement coordinates." end end
 local template=if assets then assets:FindFirstChild(spec.template) else nil
 if not template or not template:IsA("Model") then
  return nil,"Import "..(spec.source or spec.asset or spec.template).." as Model ServerStorage/BattleWorksAssets/"..spec.template.." in Edit mode."
 end
 local hasParts=false
 for _,part in template:GetDescendants() do if part:IsA("BasePart") then hasParts=true; break end end
 if not hasParts then return nil,"Imported Model '"..spec.template.."' has no mesh/part geometry." end
 local clone
 local ok,reason=pcall(function()
  clone=template:Clone(); assert(clone,"Imported Model is not Archivable.")
  clone.Name=spec.id
  for _,part in clone:GetDescendants() do
   if part:IsA("BasePart") then part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false end
  end
  clone:ScaleTo(template:GetScale()*spec.scale)
  local r=spec.rotation
  clone:PivotTo(CFrame.Angles(math.rad(r.X),math.rad(r.Y),math.rad(r.Z)))
  local bounds,size=clone:GetBoundingBox()
  local halfHeight=(math.abs(bounds.RightVector.Y)*size.X+math.abs(bounds.UpVector.Y)*size.Y+math.abs(bounds.LookVector.Y)*size.Z)/2
  local offset=Vector3.new(spec.position.X-bounds.Position.X,spec.position.Y-(bounds.Position.Y-halfHeight),spec.position.Z-bounds.Position.Z)
  clone:PivotTo(CFrame.new(offset)*clone:GetPivot())
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
function Placement.placeMany(assets,specs,arena,configure)
 if type(specs)~="table" or #specs<1 or #specs>512 then return nil,"Imported worlds require 1–512 placements." end
 local folder=Instance.new("Folder"); folder.Name="WorldScenery"
 local models={}; local ids={}
 for _,spec in specs do
  if type(spec)~="table" or type(spec.id)~="string" or ids[spec.id] then folder:Destroy(); return nil,"Invalid/duplicate imported placement ID." end
  ids[spec.id]=true
  local model,reason=Placement.place(assets,spec,arena,folder)
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

-- Edit-mode clones only. Uses the game's native placement helper for identical
-- grounding/scaling; no competing gameplay loader or simulated physics.
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local Preview={}; Preview.__index=Preview
function Preview.new(placement,storage)
 return setmetatable({placement=placement,storage=storage,models={},templates={}},Preview)
end
function Preview:folder()
 if not self.root or not self.root.Parent then
  self.root=Instance.new("Folder"); self.root.Name="BattleWorksEditorPreview"; self.root.Parent=workspace
  self.root.Archivable=false
 end
 return self.root
end
function Preview:template(item)
 return Paths.resolve(self.storage:FindFirstChild("BattleWorksAssets"),item.model)
end
function Preview:bounds(item)
 local template=self:template(item)
 assert(template and template:IsA("Model"),"Missing model "..item.model..". Import/export it once, or choose a built-in object.")
 local _,size=template:GetBoundingBox(); return {size.X,size.Y,size.Z}
end
function Preview:pose(id,entry)
 local model=self.models[id]; if not model then return end
 if entry.tank then model:PivotTo(CFrame.new(entry.position[1],.12,entry.position[3])*CFrame.Angles(0,math.rad(-entry.heading),0)); return end
 model:ScaleTo(self.templates[id]*entry.scale)
 model:PivotTo(CFrame.Angles(0,math.rad(entry.rotation[2]),0))
 local bounds,size=model:GetBoundingBox()
 local half=(math.abs(bounds.RightVector.Y)*size.X+math.abs(bounds.UpVector.Y)*size.Y+math.abs(bounds.LookVector.Y)*size.Z)/2
 model:PivotTo(CFrame.new(entry.position[1]-bounds.Position.X,-(bounds.Position.Y-half),entry.position[3]-bounds.Position.Z)*model:GetPivot())
end
function Preview:object(entry,item)
 local template=self:template(item); if not template then return nil,"Missing imported model: "..item.model end
 local model,reason=self.placement.place(self.storage:FindFirstChild("BattleWorksAssets"),{id=entry.id,template=item.model,source=item.source,position=Vector3.new(table.unpack(entry.position)),rotation=Vector3.new(table.unpack(entry.rotation)),scale=entry.scale},self:folder(),self:folder(),self.storage:FindFirstChild("BattleWorksBuiltinAssets"))
 if not model then return nil,reason end
 model:SetAttribute("BWEditorId",entry.id)
 for _,p in model:GetDescendants() do
  if p:IsA("LuaSourceContainer") then p:Destroy()
  elseif p:IsA("BasePart") then p.Locked=false; p.CanQuery=true; p.CanCollide=false end
 end
 self.models[entry.id]=model; self.templates[entry.id]=template:GetScale()
 return model
end
function Preview:spawn(entry)
 local model=Instance.new("Model"); model.Name=entry.id; model:SetAttribute("BWEditorId",entry.id)
 local part=Instance.new("Part"); part.Name="Spawn"; part.Size=Vector3.new(9,.2,11); part.Anchored=true; part.CanCollide=false; part.Transparency=.35
 part.Color=if entry.tank=="Boomer" then Color3.fromRGB(255,165,50) else Color3.fromRGB(70,215,105); part.Parent=model
 model.PrimaryPart=part
 local nose=Instance.new("Part");nose.Name="ForwardMarker";nose.Size=Vector3.new(3,.2,2);nose.CFrame=CFrame.new(0,0,-6);nose.Color=Color3.new(1,1,1);nose.Anchored=true;nose.CanCollide=false;nose.Parent=model
 local label=Instance.new("BillboardGui"); label.Size=UDim2.fromOffset(160,30); label.StudsOffset=Vector3.new(0,3,0); label.AlwaysOnTop=true; label.Parent=part
 local text=Instance.new("TextLabel"); text.Size=UDim2.fromScale(1,1); text.BackgroundTransparency=1; text.Text=entry.tank.." spawn ↑"; text.TextColor3=Color3.new(1,1,1); text.TextSize=16; text.Parent=label
 model.Parent=self:folder(); self.models[entry.id]=model; self:pose(entry.id,entry)
end
function Preview:rebuild(document,byType)
 self:clear(); local root=self:folder(); local errors={}
 local floor=Instance.new("Part"); floor.Name="EditorGround"; floor.Anchored=true; floor.Size=Vector3.new(document.settings.width,1,document.settings.depth); floor.Position=Vector3.new(0,-.5,0); floor.CanCollide=false; floor.Material=Enum.Material[document.settings.ground.material]; floor.Color=Color3.fromRGB(table.unpack(document.settings.ground.color)); floor.Locked=true; floor.Parent=root
 -- Thin boundary outlines; no per-frame grid geometry or instance polling.
 for _,v in {{0,-document.settings.depth/2,document.settings.width,.15},{0,document.settings.depth/2,document.settings.width,.15},{-document.settings.width/2,0,.15,document.settings.depth},{document.settings.width/2,0,.15,document.settings.depth}} do
  local line=Instance.new("Part"); line.Name="BoundaryOutline"; line.Size=Vector3.new(v[3],.2,v[4]); line.Position=Vector3.new(v[1],.1,v[2]); line.Anchored=true; line.CanCollide=false; line.CanQuery=false; line.Color=Color3.fromRGB(255,205,65); line.Parent=root
 end
 for _,o in document.objects do
  local item=byType[o.type]
  if item then
   local model,err=self:object(o,item)
   if model then o.bounds=self:bounds(item) else table.insert(errors,o.id..": "..err) end
  else table.insert(errors,o.id..": unknown catalog type "..tostring(o.type)) end
 end
 for _,p in document.spawns do self:spawn(p) end
 return errors
end
function Preview:clear()
 if self.beforeClear then self.beforeClear() end
 if self.root then self.root:Destroy(); self.root=nil end
 table.clear(self.models); table.clear(self.templates)
end
return Preview

-- One sanitized template library for local editors. No editor mutations/remotes
-- are accepted by the battle server, and ServerStorage originals remain intact.
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local Catalog={}
local Placement=require(game.ReplicatedStorage.Shared.ModelPlacement)
local Visual=require(game.ReplicatedStorage.Shared.AssetGeometry)
local Fit=require(script.Parent.MeshCollisionFit)
local cloudClasses={
 Model=true,Folder=true,MeshPart=true,Part=true,WedgePart=true,CornerWedgePart=true,
 SurfaceAppearance=true,Decal=true,Texture=true,SpecialMesh=true,
}
local function sanitizeCloud(container)
 for _,child in container:GetChildren() do
  if not cloudClasses[child.ClassName] then child:Destroy()
  else
   assert(not Visual.isCollisionNode(child.Name),"Cloud model contains collision-only render geometry")
   if child:IsA("BasePart") then child.Anchored=true;child.CanCollide=false;child.CanTouch=false;child.CanQuery=false end
   sanitizeCloud(child)
  end
 end
end
local function subfolder(root,segments)
 local folder=root
 for i=1,#segments-1 do
  local nextFolder=folder:FindFirstChild(segments[i])
  if not nextFolder then
   nextFolder=Instance.new("Folder");nextFolder.Name=segments[i];nextFolder.Parent=folder
  end
  assert(nextFolder:IsA("Folder"),"Asset path conflicts with a model")
  folder=nextFolder
 end
 return folder
end
function Catalog.loadCloudModel(source,item)
 local ref=item.cloudModel
 assert(source and Paths.valid(item.model) and item.model:sub(1,8)~="Builtin/","Invalid cloud asset path")
 local assetId,creatorId=tonumber(ref.assetId),tonumber(ref.creatorId)
 assert(assetId and assetId%1==0 and assetId>0 and assetId<=9007199254740991 and
  creatorId and creatorId%1==0 and creatorId>0 and (ref.creatorType=="User" or ref.creatorType=="Group"),"Invalid cloud model identity")
 if game.CreatorId and game.CreatorId~=0 then
  assert(game.CreatorId==creatorId and game.CreatorType.Name==ref.creatorType,"Roblox model owner differs from the experience creator")
 end
 -- InsertService applies Roblox's owned/shared model permissions. Only trusted
 -- server catalog entries reach this path. Keep the fetched tree off-world.
 local model=game:GetService("InsertService"):LoadAsset(assetId)
 assert(model,"Roblox returned no model")
 local ok,result=pcall(function()
  assert(model:IsA("Model"),"Roblox asset must be a Model")
  sanitizeCloud(model)
  local _,size=Visual.measure(model)
  if item.collider then Visual.checkFaceProfile(size,item.collider) end
  local segments=string.split(item.model,"/")
  local folder=subfolder(source,segments)
  assert(not folder:FindFirstChild(segments[#segments]),"Cloud model path already exists")
  model.Name=segments[#segments];model.Parent=folder
  return model
 end)
 if not ok then model:Destroy();error(result,0) end
 return result
end
function Catalog.publish(storage,replicated,metadata,http)
 local entries=require(game.ReplicatedStorage.Shared.CatalogData).decode(metadata,http)
 local hidden={}
 local visibility=metadata.Parent and metadata.Parent:FindFirstChild("HiddenEditorAssets")
 if visibility and visibility:IsA("StringValue") then
  for _,assetPath in http:JSONDecode(visibility.Value) do hidden[assetPath]=true end
 end
 local root=Instance.new("Folder"); root.Name="BattleWorksEditorAssets"
 local templates=Instance.new("Folder"); templates.Name="Templates"; templates.Parent=root
 local source=storage:FindFirstChild("BattleWorksAssets")
 for _,item in entries do
  local model=Paths.resolve(source,item.model)
  item.available=false
  if hidden[item.model] then item.hidden=true end
  if not model and item.cloudModel then
   local ok,result=pcall(Catalog.loadCloudModel,source,item)
   if ok then model=result else
    item.loadError=tostring(result)
    warn("BattleWorks could not load Roblox model "..item.model..": "..item.loadError)
   end
  end
  if model then
   local copy
   local ok=pcall(function()
    copy=model:Clone(); assert(copy,"Unclonable asset")
    for _,node in copy:GetDescendants() do
     assert(not Visual.isCollisionNode(node.Name),"Import the visual-only GLB")
     if node:IsA("LuaSourceContainer") or node:IsA("Sound") or node:IsA("ParticleEmitter") or node:IsA("Trail") or node:IsA("Beam") then node:Destroy()
     elseif node:IsA("BasePart") then node.Anchored=true;node.CanCollide=false;node.CanTouch=false;node.CanQuery=false end
    end
    local _,size=Visual.measure(model);assert(size.X>0 and size.Y>0 and size.Z>0,"Empty native bounds");item.size={size.X,size.Y,size.Z}
    if item.collider and item.collider.fit=="mesh" then item.collider.boxes=Fit.profile(model) end
    if item.collider then
     local aligned,reason=pcall(Visual.checkFaceProfile,size,item.collider)
     if not aligned then
      if item.collider.explicitCollision then
       warn("BattleWorks explicit collision profile rejected for "..item.model..": "..tostring(reason))
       error(reason,0)
      end
      warn("BattleWorks collision profile for "..item.model.." uses native sampling: "..tostring(reason))
      item.collisionWarning=tostring(reason)
      item.collider={widthFraction=1,heightFraction=1,depthFraction=1,fit="mesh",boxes=Fit.profile(model)}
     end
    end
    local segments=string.split(item.model,"/")
    local folder=subfolder(templates,segments)
    copy.Name=segments[#segments];copy.Parent=folder;item.available=true;item.stretchable=Placement.stretchPart(model)~=nil and not item.zone
    item.resizeAxes=Placement.resizeAxes(model,item.resizeAxes)
   end)
   if not ok then if copy then copy:Destroy() end;item.available=false end
  end
 end
 local data=Instance.new("StringValue");data.Name="Catalog";require(game.ReplicatedStorage.Shared.CatalogData).write(data,entries,http);data.Parent=root
 root:SetAttribute("Ready",true);root.Parent=replicated
 return root
end
return Catalog

-- One sanitized template library for local editors. No editor mutations/remotes
-- are accepted by the battle server, and ServerStorage originals remain intact.
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local Catalog={}
local Placement=require(game.ReplicatedStorage.Shared.ModelPlacement)
local Visual=require(game.ReplicatedStorage.Shared.AssetGeometry)
local Fit=require(script.Parent.MeshCollisionFit)
function Catalog.publish(storage,replicated,metadata,http)
 local entries=require(game.ReplicatedStorage.Shared.CatalogData).decode(metadata,http)
 local root=Instance.new("Folder"); root.Name="BattleWorksEditorAssets"
 local templates=Instance.new("Folder"); templates.Name="Templates"; templates.Parent=root
 local source=storage:FindFirstChild("BattleWorksAssets")
 for _,item in entries do
  local model=Paths.resolve(source,item.model)
  item.available=false
  if model then
   local copy
   local ok=pcall(function()
    copy=model:Clone(); assert(copy,"Unclonable asset")
    for _,node in copy:GetDescendants() do
     if node:IsA("LuaSourceContainer") or node:IsA("Sound") or node:IsA("ParticleEmitter") or node:IsA("Trail") or node:IsA("Beam") then node:Destroy()
     elseif node:IsA("BasePart") then node.Anchored=true;node.CanCollide=false;node.CanTouch=false;node.CanQuery=false end
    end
    local _,size=Visual.measure(model);assert(size.X>0 and size.Y>0 and size.Z>0,"Empty native bounds");item.size={size.X,size.Y,size.Z}
    if item.collider and item.collider.fit=="mesh" then item.collider.boxes=Fit.profile(model) end
    if item.collider then
     local aligned,reason=pcall(Visual.checkFaceProfile,size,item.collider)
     if not aligned then
      warn("BattleWorks collision profile for "..item.model.." uses native sampling: "..tostring(reason))
      item.collisionWarning=tostring(reason)
      item.collider={widthFraction=1,heightFraction=1,depthFraction=1,fit="mesh",boxes=Fit.profile(model)}
     end
    end
    local folder=templates;local segments=string.split(item.model,"/")
    for i=1,#segments-1 do
     local nextFolder=folder:FindFirstChild(segments[i])
     if not nextFolder then nextFolder=Instance.new("Folder");nextFolder.Name=segments[i];nextFolder.Parent=folder end
     folder=nextFolder
    end
    copy.Name=segments[#segments];copy.Parent=folder;item.available=true;item.stretchable=Placement.stretchPart(model)~=nil and not item.zone
   end)
   if not ok then if copy then copy:Destroy() end;item.available=false end
  end
 end
 local data=Instance.new("StringValue");data.Name="Catalog";require(game.ReplicatedStorage.Shared.CatalogData).write(data,entries,http);data.Parent=root
 root:SetAttribute("Ready",true);root.Parent=replicated
 return root
end
return Catalog

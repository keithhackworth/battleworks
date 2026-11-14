-- One sanitized template library for local editors. No editor mutations/remotes
-- are accepted by the battle server, and ServerStorage originals remain intact.
local Paths=require(game.ReplicatedStorage.Shared.AssetPaths)
local Catalog={}
function Catalog.publish(storage,replicated,metadata,http)
 local entries=http:JSONDecode(metadata.Value)
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
    local _,size=model:GetBoundingBox();assert(size.X>0 and size.Y>0 and size.Z>0,"Empty native bounds");item.size={size.X,size.Y,size.Z}
    local folder=templates;local segments=string.split(item.model,"/")
    for i=1,#segments-1 do
     local nextFolder=folder:FindFirstChild(segments[i])
     if not nextFolder then nextFolder=Instance.new("Folder");nextFolder.Name=segments[i];nextFolder.Parent=folder end
     folder=nextFolder
    end
    copy.Name=segments[#segments];copy.Parent=folder;item.available=true
   end)
   if not ok then if copy then copy:Destroy() end;item.available=false end
  end
 end
 local data=Instance.new("StringValue");data.Name="Catalog";data.Value=http:JSONEncode(entries);data.Parent=root
 root:SetAttribute("Ready",true);root.Parent=replicated
 return root
end
return Catalog

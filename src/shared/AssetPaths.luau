-- Case-sensitive logical asset paths. The native index bridges bundle mounts
-- under ServerStorage/BattleWorksAssets without moving or copying geometry.
-- Never search by basename unless a legacy bare name resolves uniquely.
local Paths={}
local indexes=setmetatable({},{__mode="k"})
function Paths.valid(value)
 if type(value)~="string" or value=="" or #value>512 or value:match("^%s") or value:match("%s$") or value:find("[\\%c:]") or value:sub(1,1)=="/" or value:sub(-1)=="/" or value:find("//",1,true) then return false end
 for segment in value:gmatch("[^/]+") do if segment=="." or segment==".." or segment:match("^%s") or segment:match("%s$") then return false end end
 return true
end
local function exact(root,value)
  local current=root
  for segment in value:gmatch("[^/]+") do
   local nextNode
   for _,node in current:GetChildren() do if node.Name==segment then if nextNode then return nil,"Ambiguous asset path segment '"..segment.."' in "..value end;nextNode=node end end
   if not nextNode then return nil,"Missing asset path '"..value.."' (segment '"..segment.."')" end
   current=nextNode
  end
  if not current:IsA("Model") then return nil,"Asset path '"..value.."' must identify a Model" end
  return current
end
local function indexFor(root)
 local source
 for _,node in root:GetChildren() do if node.Name=="__BattleWorksAssetIndex" then
  if source then return nil,"Duplicate native asset index" end;source=node
 end end
 if not source then return {} end
 if not source:IsA("StringValue") then return nil,"Native asset index must be a StringValue" end
 local cached=indexes[root];if cached and cached.value==source.Value then return cached.paths end
 local ok,index=pcall(function()return game:GetService("HttpService"):JSONDecode(source.Value)end)
 if not ok or type(index)~="table" or index.version~=1 or type(index.paths)~="table" then return nil,"Invalid native asset index; run node tools/build-editor-catalog.js" end
 for logical,native in index.paths do if not Paths.valid(logical) or not Paths.valid(native) then return nil,"Invalid native asset index path; rebuild the editor catalog" end end
 indexes[root]={value=source.Value,paths=index.paths};return index.paths
end
function Paths.resolve(root,value)
 if not Paths.valid(value) then return nil,"Invalid asset path '"..tostring(value).."'; use a relative forward-slash path inside BattleWorksAssets." end
 if not root then return nil,"Missing ServerStorage/BattleWorksAssets" end
 -- Built-ins retain their explicit mount and never resolve to bundled copies.
 if value:sub(1,8)=="Builtin/" then return exact(root,value) end
 local index,reason=indexFor(root);if not index then return nil,reason end
 if index[value] then return exact(root,index[value]) end
 if value:find("/",1,true) then return exact(root,value) end
 -- A root-level Model name is also an exact canonical path. Adding a bundle
 -- with another basename must not break an existing standalone saved reference.
 local direct
 for _,node in root:GetChildren() do if node.Name==value and node:IsA("Model") then
  if direct then return nil,"Ambiguous asset path '"..value.."'" end;direct=node
 end end
 if direct then return direct end
 local matches={};local names={}
 local function walk(folder,prefix)
  for _,node in folder:GetChildren() do
   local full=prefix..node.Name
   if node:IsA("Model") then if node.Name==value then table.insert(matches,node);table.insert(names,full) end
   elseif node:IsA("Folder") then walk(node,full.."/") end
  end
 end
 walk(root,"")
 if #matches>1 then table.sort(names);return nil,"Ambiguous asset '"..value.."'; use full path: "..table.concat(names,", ") end
 if #matches==0 then return nil,"Missing asset path '"..value.."'" end
 return matches[1]
end
return Paths

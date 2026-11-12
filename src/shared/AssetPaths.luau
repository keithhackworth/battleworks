-- Paths are case-sensitive and relative to ServerStorage/BattleWorksAssets.
-- Never search by basename unless a legacy bare name resolves uniquely.
local Paths={}
function Paths.valid(value)
 if type(value)~="string" or value=="" or #value>512 or value:match("^%s") or value:match("%s$") or value:find("[\\%c:]") or value:sub(1,1)=="/" or value:sub(-1)=="/" or value:find("//",1,true) then return false end
 for segment in value:gmatch("[^/]+") do if segment=="." or segment==".." or segment:match("^%s") or segment:match("%s$") then return false end end
 return true
end
function Paths.resolve(root,value)
 if not Paths.valid(value) then return nil,"Invalid asset path '"..tostring(value).."'; use a relative forward-slash path inside BattleWorksAssets." end
 if not root then return nil,"Missing ServerStorage/BattleWorksAssets" end
 if value:find("/",1,true) then
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

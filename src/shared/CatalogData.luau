-- Catalog geometry can exceed Roblox's per-StringValue limit. Existing small
-- catalogs stay a single JSON string; large ones use bounded child chunks.
local C={Limit=170000,Prefix="BattleWorksChunks:v1:"}
function C.decode(node,http,waitForChunks)
 local raw=node.Value
 if raw:sub(1,#C.Prefix)==C.Prefix then
  local count=tonumber(raw:sub(#C.Prefix+1));assert(count and count%1==0 and count>0 and count<=1024,"Invalid catalog chunk count")
  local chunks={}
  for i=1,count do
   local name=string.format("Chunk%04d",i)
   local child=node:FindFirstChild(name) or (waitForChunks==true and node:WaitForChild(name,5))
   if waitForChunks=="pending" and (not child or child.Value=="") then return nil end
   assert(child and child:IsA("StringValue"),"Catalog chunk not available yet");chunks[i]=child.Value
  end
  raw=table.concat(chunks)
 end
 return http:JSONDecode(raw)
end
function C.write(node,value,http)
 local raw=http:JSONEncode(value)
 if #raw<=C.Limit then node.Value=raw;return end
 local count,start=0,1
 while start<=#raw do
  local finish=math.min(start+C.Limit-1,#raw)
  while finish<#raw and raw:byte(finish+1)>=128 and raw:byte(finish+1)<192 do finish-=1 end
  count+=1
  local child=Instance.new("StringValue");child.Name=string.format("Chunk%04d",count);child.Value=raw:sub(start,finish);child.Parent=node
  start=finish+1
 end
 node.Value=C.Prefix..count
end
return C

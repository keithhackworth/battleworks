local editor=Instance.new("StringValue");editor.Name="EditorAssetCatalog";editor.Value="editor_metadata";editor.Parent=config
local factory=Instance.new
Instance.new=function(class)
 local node=factory(class)
 local original=getmetatable(node)
 setmetatable(node,{__index=function(self,key)
  if key=="Parent" then return rawget(self,"_parent") end
  return original.__index(self,key)
 end,__newindex=function(self,key,value)
  if key=="Parent" then rawset(self,"_parent",value);if value and value.children then table.insert(value.children,self) end
  else original.__newindex(self,key,value) end
 end})
 function node:Destroy()
  for _,child in self.children do if child.Parent==self then child:Destroy() end end
  self.destroyed=true;self.Parent=nil
 end
 return node
end
game.ReplicatedStorage.FindFirstChild=function(self,name)
 for _,node in created do if node.Name==name and node.Parent==self and not node.destroyed then return node end end
end
for _,item in builderItems do
 local template=builtin:FindFirstChild(item.model:match("[^/]+$"))
 function template:GetBoundingBox()return CFrame.new(),Vector3.new(table.unpack(item.size))end
end
local encoded={};local serial=0
local http={JSONDecode=function(_,raw)
 if raw=="editor_metadata" then return require("WorldEditorState").copy(builderItems) end
 if encoded[raw] then return require("WorldEditorState").copy(encoded[raw]) end
 return builderSettings
end,JSONEncode=function(_,value)
 serial+=1;local token="json_"..serial;encoded[token]=require("WorldEditorState").copy(value);return token
end}
local playerWorldService=game.GetService
game.GetService=function(self,name)
 if name=="HttpService" then return http end
 return playerWorldService(self,name)
end
local cloudProfile={};local teleportCalls={};local teleportFailed=signal()
local ds={GetAsync=function(_,key)return require("WorldEditorState").copy(cloudProfile[key])end,UpdateAsync=function(_,key,fn)cloudProfile[key]=fn(cloudProfile[key])end}
local cloudService=game.GetService
http.GenerateGUID=function()return "server-generated-reservation"end
game.PlaceId=55;game.PrivateServerId="";game.PrivateServerOwnerId=0
game.GetService=function(self,name)
 if name=="DataStoreService" then return {GetDataStore=function(_,name)check(name=="BattleWorksPlayerWorlds_v1","private datastore namespace");return ds end} end
 if name=="TeleportService" then return {TeleportInitFailed=teleportFailed,TeleportAsync=function(_,place,players,options)table.insert(teleportCalls,{place=place,players=players,options=options})end} end
 return cloudService(self,name)
end
local teleportFactory=Instance.new
Instance.new=function(class)
 local p=teleportFactory(class)
 if class=="TeleportOptions" then p.SetTeleportData=function(self,data)self.data=data end end
 return p
end

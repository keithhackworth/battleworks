-- Actual compiler-generated catalog/settings are injected by scripts/check.mjs.
local storage=Instance.new("Folder"); storage.Name="ServerStorage"
local function makeNode(data)
 local node=Instance.new(data.ClassName);node.Name=data.Name or "WorldCatalog"
 for k,v in data.Properties or {} do node[k]=if data.ClassName=="Vector3Value" and k=="Value" then Vector3.new(table.unpack(v)) else v end
 for _,child in data.Children or {} do makeNode(child).Parent=node end
 return node
end
local config=Instance.new("Configuration");config.Name="BattleWorksStudio";config.Parent=storage
local selected=Instance.new("StringValue");selected.Name="SelectedWorld";selected.Value="builder_demo";selected.Parent=config
local published=Instance.new("StringValue");published.Name="PublishedWorld";published.Value="builder_demo";published.Parent=config
local catalog=makeNode(builderCatalog);catalog.Name="WorldCatalog";catalog.Parent=config
local assets=Instance.new("Folder");assets.Name="BattleWorksAssets";assets.Parent=storage
local builtin=Instance.new("Folder");builtin.Name="Builtin";builtin.Parent=assets
for _,item in builderItems do
 local template=Instance.new("Model");template.Name=item.model:match("[^/]+$");template.Parent=builtin
 function template:Clone()
  local model=Instance.new("Model");model.scale=1;model.pivot=CFrame.new()
  local mesh=Instance.new("Part");mesh.Name="Geometry";mesh.Transparency=0;mesh.Parent=model
  function mesh:IsA(class)return class=="Part" or class=="BasePart"end
  function model:GetScale()return self.scale end
  function model:ScaleTo(scale)self.scale=scale end
  function model:GetPivot()return self.pivot end
  function model:PivotTo(cf)self.pivot=cf;mesh.CFrame=cf*CFrame.new(0,item.size[2]*self.scale/2,0);mesh.Size=Vector3.new(table.unpack(item.size))*self.scale end
  function model:GetBoundingBox()return self.pivot*CFrame.new(0,item.size[2]*self.scale/2,0),Vector3.new(table.unpack(item.size))*self.scale end
  return model
 end
 function template:GetScale()return 1 end
 function template:GetDescendants()return {{IsA=function(_,class)return class=="BasePart"end}}end
end
local previousService=game.GetService
game.GetService=function(self,name)
 if name=="ServerStorage"then return storage end
 if name=="HttpService"then return {JSONDecode=function(_,raw)check(type(raw)=="string"and raw:find("spawns",1,true),"real generated settings JSON passed to decoder");return builderSettings end}end
 return previousService(self,name)
end

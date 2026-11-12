local Selector=require("StudioWorldSelector")
local checks=0
local function check(ok,message) checks+=1; assert(ok,message) end
local function instance(class,name,value,children)
 local v={ClassName=class,Name=name,Value=value,children=children or {},attributes={}}
 function v:IsA(kind) return self.ClassName==kind end
 function v:FindFirstChild(key) for _,c in self.children do if c.Name==key then return c end end end
 function v:GetChildren() return self.children end
 function v:SetAttribute(key,n) self.attributes[key]=n end
 return v
end
local function record(id,name,status)
 return instance("Configuration",id,nil,{
  instance("StringValue","WorldId",id),instance("StringValue","DisplayName",name),instance("StringValue","Status",status or "preview-only"),
  instance("StringValue","Reason","Unresolved GLB mappings; manifest loader is not implemented."),instance("StringValue","ManifestPath","build/worlds/"..id..".json"),
 })
end
local selected=instance("StringValue","SelectedWorld","")
local config=instance("Configuration","BattleWorksStudio",nil,{selected,instance("Folder","WorldCatalog",nil,{record("village_battle","Village Battle"),record("forest","Forest Arena")})})
local storage=instance("Folder","ServerStorage",nil,{config})
local arena=instance("Folder","Arena")
local studio={IsStudio=function() return true end}
local messages={}; local function log(message) table.insert(messages,message) end
local available=Selector.catalog(config)
check(#available==3 and available[1].id=="default" and available[2].id=="forest","default and discovered worlds sorted deterministically")
local result=Selector.start(studio,storage,arena,log)
check(result.active.id=="default" and result.status=="ready","empty selection uses test arena")
check(arena.attributes.WorldId=="default" and arena.attributes.WorldName=="Default Test Arena","server publishes active world ID/name")
check(#messages>=4,"availability and active selection are logged")
selected.Value="village_battle"
result=Selector.start(studio,storage,arena,log)
check(result.status=="fallback" and result.requested=="village_battle" and result.active.id=="default","unresolved world explicitly falls back")
check(result.reason:find("Unresolved GLB",1,true) and result.reason:find("Village Battle",1,true),"fallback explains assets and requested world")
check(arena.attributes.WorldSelectionStatus=="fallback" and arena.attributes.RequestedWorldId=="village_battle","all clients observe same server-selected fallback")
Selector.start(studio,storage,instance("Folder","NextSessionArena"),log)
check(selected.Value=="village_battle","startup never overwrites persisted Edit-mode selection")
selected.Value="missing_world"; result=Selector.start(studio,storage,arena,log)
check(result.active.id=="default" and result.reason:find("Unknown world ID",1,true),"unknown world is diagnostic fallback")
selected.Value=" default "; result=Selector.start(studio,storage,arena,log)
check(result.status=="ready" and result.active.id=="default","test arena can be explicitly selected on next startup")
local fakeReady=Selector.resolve("village_battle",{ {id="village_battle",name="Village",status="ready"} },true)
check(fakeReady.active.id=="default" and fakeReady.status=="fallback","catalog label cannot bypass absent runtime loader")
local noConfig=Selector.start(studio,nil,instance("Folder","Arena"),log)
check(noConfig.active.id=="default","missing configuration preserves current test arena")
local productionArena=instance("Folder","Arena")
local oldCount=#messages
local forbidden={FindFirstChild=function() error("production must not inspect Studio configuration") end}
result=Selector.start({IsStudio=function() return false end},forbidden,productionArena,log)
check(result.active.id=="default" and next(productionArena.attributes)==nil and #messages==oldCount,"production ignores selection, attributes and logging")
local malformed=instance("Configuration","BattleWorksStudio",nil,{instance("Folder","SelectedWorld")})
result=Selector.start(studio,instance("Folder","ServerStorage",nil,{malformed}),arena,log)
check(result.status=="fallback" and result.reason:find("StringValue",1,true),"malformed configuration is a safe diagnostic fallback")
print(string.format("Studio world selector suite passed: %d assertions",checks))
-- A registered placement becomes active only after the native clone succeeds.
local spec={id="tree-large",template="tree-large",source="GLBs/suburban/tree-large.glb",position=Vector3.zero,rotation=Vector3.zero,scale=4}
local trees={{id="tree_test",name="Tree Test",status="asset-dependent",placement=spec}}
local loaded=0
local ready=Selector.resolve("tree_test",trees,true,function(p) loaded+=1; check(p==spec,"selected placement identity"); return {} end)
check(loaded==1 and ready.active.id=="tree_test" and ready.active.profile=="single-model","successful single-model selection uses minimal environment")
local missing=Selector.resolve("tree_test",trees,true,function() return nil,"Missing imported tree-large model" end)
check(missing.active.id=="default" and missing.reason:find("Missing imported",1,true),"missing model preserves complete default arena")
check(Selector.resolve("tree_test",trees,false,function() error("production cannot load Studio assets") end).active.id=="default","production never runs imported-asset placement")
print(string.format("Studio imported-model selection coverage passed: %d assertions",checks))

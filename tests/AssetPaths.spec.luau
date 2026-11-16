local Paths=require("AssetPaths")
local count=0
local function check(v,m)count+=1;assert(v,m)end
local function node(name,class,children)
 local n={Name=name,children=children or {}}
 function n:IsA(c)return class==c end
 function n:GetChildren()return self.children end
 return n
end
local a=node("Fence","Model");local b=node("Fence","Model")
local root=node("BattleWorksAssets","Folder",{node("Buildings","Folder",{node("Houses","Folder",{a})}),node("Structures","Folder",{node("Fences","Folder",{b})})})
check(Paths.resolve(root,"Buildings/Houses/Fence")==a,"exact first hierarchy")
check(Paths.resolve(root,"Structures/Fences/Fence")==b,"same basename exact second hierarchy")
local model,err=Paths.resolve(root,"Fence");check(not model and err:find("Ambiguous",1,true),"ambiguous legacy name rejected")
model,err=Paths.resolve(root,"Structures/Houses/Fence");check(not model and err:find("segment",1,true),"missing segment identified without basename fallback")
root.children[2]=nil;check(Paths.resolve(root,"Fence")==a,"unambiguous legacy basename preserved")
local direct=node("Fence","Model");table.insert(root.children,direct)
check(Paths.resolve(root,"Fence")==direct,"exact standalone root path remains stable when nested bundle models share its basename")
for _,path in {"../Fence","/Fence","Buildings//Fence","Buildings\\Fence","Buildings/./Fence","Fence/"}do check(not Paths.valid(path),"invalid canonical path rejected")end
check(not Paths.resolve(root,"Buildings/Houses"),"folders cannot masquerade as model assets")
local oak=node("Oak","Model",{node("Primitive","Model")})
local other=node("Oak","Model")
local bundle=node("assets","Folder",{node("Trees","Folder",{oak}),node("Decorations","Folder",{other})})
local nativeIndex=node("__BattleWorksAssetIndex","StringValue");nativeIndex.Value="bundle-index"
local builtin=node("BW_block","Model")
local bundled=node("BattleWorksAssets","Folder",{bundle,nativeIndex,node("Builtin","Folder",{builtin})})
local oldService=game.GetService;local decodes=0
game.GetService=function(self,name)
 if name=="HttpService" then return {JSONDecode=function(_,value)
  decodes+=1;assert(value=="bundle-index")
  return {version=1,paths={["Trees/Oak"]="assets/Trees/Oak",["Decorations/Oak"]="assets/Decorations/Oak",legacy_oak="assets/Trees/Oak"}}
 end}end
 return oldService(self,name)
end
check(Paths.resolve(bundled,"Trees/Oak")==oak,"indexed logical path finds Model inside binary bundle mount")
check(Paths.resolve(bundled,"Decorations/Oak")==other,"duplicate basenames retain distinct bundle identities")
check(Paths.resolve(bundled,"legacy_oak")==oak,"registered legacy reference resolves through index without geometry copies")
check(decodes==1,"runtime caches decoded index per asset library")
check(Paths.resolve(bundled,"Builtin/BW_block")==builtin,"bundles do not replace explicit built-in mount")
check(not Paths.resolve(bundled,"assets"),"bundle folder cannot be placed as a Model")
model,err=Paths.resolve(bundled,"Oak");check(not model and err:find("Ambiguous",1,true),"unknown bare bundle names remain ambiguity checked")
nativeIndex.Value="corrupt"
check(not Paths.resolve(bundled,"Trees/Oak"),"changed invalid index fails clearly without guessing another asset")
game.GetService=oldService
print(string.format("Hierarchical asset paths suite passed: %d assertions",count))

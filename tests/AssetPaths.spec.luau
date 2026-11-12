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
for _,path in {"../Fence","/Fence","Buildings//Fence","Buildings\\Fence","Buildings/./Fence","Fence/"}do check(not Paths.valid(path),"invalid canonical path rejected")end
check(not Paths.resolve(root,"Buildings/Houses"),"folders cannot masquerade as model assets")
print(string.format("Hierarchical asset paths suite passed: %d assertions",count))

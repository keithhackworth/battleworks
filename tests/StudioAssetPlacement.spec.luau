-- Numeric Model doubles exercise the real placement code. Native import, mesh
-- bounds/materials and Studio save/Play behavior still require a manual test.
local Placement=require("StudioAssetPlacement")
local function container(name)
 local v={Name=name,children={}}
 function v:FindFirstChild(key) for _,c in self.children do if c.Name==key and not c.destroyed then return c end end end
 function v:Destroy() self.destroyed=true end
 function v:GetChildren() return self.children end
 function v:SetAttribute(k,n) self[k]=n end
 return v
end
local arena=container("Arena"); local assets=container("Assets"); local clones={}
local originalFactory=Instance.new
Instance.new=function(class)
 if class~="Folder" then return originalFactory(class) end
 local v=container("")
 return setmetatable(v,{__newindex=function(self,k,n) rawset(self,k,n); if k=="Parent" and n then table.insert(n.children,self) end end})
end
local template={Name="tree-large",scale=2,pivot=CFrame.new(100,50,100)}
function template:IsA(class) return class=="Model" end
local sourcePart={Anchored=false}; function sourcePart:IsA(class) return class=="BasePart" end
function template:GetDescendants() return {sourcePart} end
function template:GetScale() return self.scale end
function template:Clone()
 local v={Name=self.Name,scale=self.scale,pivot=self.pivot,part={Anchored=false}}
 function v.part:IsA(class) return class=="BasePart" end
 function v:GetDescendants() return {self.part} end
 function v:ScaleTo(s) self.scale=s end
 function v:PivotTo(cf) self.pivot=cf end
 function v:GetPivot() return self.pivot end
 function v:GetBoundingBox() return self.pivot*CFrame.new(3*self.scale,5*self.scale,-2*self.scale),Vector3.new(2,10,2)*self.scale end
 function v:Destroy() self.destroyed=true end
 function v:GetChildren() return self.children end
 function v:SetAttribute(k,n) self[k]=n end
 table.insert(clones,v); return v
end
table.insert(assets.children,template)
local spec={id="tree-large",template="tree-large",source="GLBs/suburban/tree-large.glb",position=Vector3.zero,rotation=Vector3.new(0,35,0),scale=4}
local clone,reason=Placement.place(assets,spec,arena)
check(clone~=nil,reason)
check(#clones==1 and clone.Name=="tree-large" and clone.Parent.Parent==arena,"one imported tree clone, not an asset substitute")
check(clone.scale==8 and template.scale==2 and sourcePart.Anchored==false,"uniform relative scale; source template never changed")
local box,size=clone:GetBoundingBox()
check(math.abs(box.Position.X)<1e-6 and math.abs(box.Position.Z)<1e-6,"bounds centered at world XZ origin regardless of template pivot")
check(math.abs(box.Position.Y-size.Y/2)<1e-6,"tree base rests on ground rather than geometric center")
check(clone.part.Anchored and not clone.part.CanCollide and not clone.part.CanTouch and not clone.part.CanQuery,"decorative clone cannot alter tank/projectile physics")
local oldFolder=clone.Parent
spec.position=Vector3.new(12,3,-8); spec.rotation=Vector3.new(10,50,20); spec.scale=.5
clone,reason=Placement.place(assets,spec,arena); check(clone~=nil,reason)
box,size=clone:GetBoundingBox()
local half=(math.abs(box.RightVector.Y)*size.X+math.abs(box.UpVector.Y)*size.Y+math.abs(box.LookVector.Y)*size.Z)/2
check(math.abs(box.Position.X-12)<1e-6 and math.abs(box.Position.Z+8)<1e-6 and math.abs(box.Position.Y-half-3)<1e-6,"rotation/scale overrides use rotated bounds and requested base height")
check(oldFolder.destroyed,"reinitialization replaces scenery rather than duplicating it")
local absent,errorMessage=Placement.place(nil,spec,arena)
check(not absent and errorMessage:find("GLBs/suburban/tree-large.glb",1,true),"missing template gives exact import source; no random substitute")
spec.scale=0; check(Placement.place(assets,spec,arena)==nil,"invalid scale fails safely")
spec.scale=1; local empty=container("Assets"); table.insert(empty.children,{Name="tree-large",IsA=function() return true end,GetDescendants=function() return {} end})
check(Placement.place(empty,spec,arena)==nil,"empty imported model cannot activate world")
local savedClone=template.Clone; template.Clone=function() error("unavailable mesh clone") end
check(Placement.place(assets,spec,arena)==nil,"native placement failures return diagnostic for default-arena fallback")
template.Clone=savedClone
-- Exercise catalog decoding -> selector -> actual placement helper together.
local function node(class,name,value,children)
 local n=container(name); n.ClassName=class; n.Value=value; n.children=children or {}
 function n:IsA(kind) return self.ClassName==kind end
 return n
end
assets.Name="BattleWorksAssets"
local values={node("StringValue","InstanceId","tree-large"),node("StringValue","AssetId","tree_large"),node("StringValue","Source",spec.source),node("StringValue","Template","tree-large"),node("Vector3Value","Position",Vector3.zero),node("Vector3Value","Rotation",Vector3.zero),node("NumberValue","Scale",4)}
local record=node("Configuration","tree_test",nil,{node("StringValue","WorldId","tree_test"),node("StringValue","DisplayName","Tree Test"),node("StringValue","Status","asset-dependent"),node("Configuration","Placement",nil,values)})
local config=node("Configuration","BattleWorksStudio",nil,{node("StringValue","SelectedWorld","tree_test"),node("Folder","WorldCatalog",nil,{record})})
local storage=node("Folder","ServerStorage",nil,{config,assets})
local selected=require("StudioWorldSelector").start({IsStudio=function() return true end},storage,arena,function() end)
check(selected.active.id=="tree_test" and selected.active.profile=="single-model" and arena.WorldId=="tree_test","registered placement activates through existing server selector")
local active=0; for _,m in clones do if not m.destroyed and m.Parent and not m.Parent.destroyed then active+=1 end end
check(active==1,"exactly one active imported clone after initialization")
local missingStorage=node("Folder","ServerStorage",nil,{config})
local fallbackArena=container("Arena")
selected=require("StudioWorldSelector").start({IsStudio=function() return true end},missingStorage,fallbackArena,function() end)
check(selected.active.id=="default" and not fallbackArena:FindFirstChild("WorldScenery"),"missing import does not activate an empty test world")
Instance.new=originalFactory; CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Studio native-model placement suite passed: %d assertions",count))

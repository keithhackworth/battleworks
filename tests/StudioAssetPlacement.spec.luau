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
-- Decode the generated interaction values through the actual startup path.
for _,v in {node("BoolValue","Solid",true),node("BoolValue","Destructible",true),node("NumberValue","Health",150),node("Vector3Value","ColliderFractions",Vector3.new(.18,.45,.18))} do table.insert(values,v) end
selected=require("StudioWorldSelector").start({IsStudio=function() return true end},storage,arena,function() end)
local object=selected.objects.records["tree-large"]
check(selected.active.id=="tree_test" and object and object.health==150 and object.solid,"catalog interaction values create authoritative object on startup")
check(#selected.objects:obstacles()==1 and object.proxy.CanQuery,"startup wires blocking and projectile queries")
selected.objects:impact({Instance=object.proxy},150,{})
check(object.destroyed and #selected.objects:obstacles()==0,"selected imported model accepts fatal damage")
selected.objects:reset()
check(object.health==150 and object.proxy.CanQuery,"selected imported model resets without reimport")
-- Multiple native placements share one scenery folder; a missing later asset
-- leaves the previous scene intact instead of silently dropping the tree.
local fence=table.clone(template); fence.Name="fence"; table.insert(assets.children,fence)
local treeSpec={id="tree-large",template="tree-large",source=spec.source,position=Vector3.zero,rotation=Vector3.zero,scale=4}
local fenceSpec={id="curvy-fence/segment_000",template="fence",source="fence.glb",position=Vector3.new(50,0,0),rotation=Vector3.new(0,70,0),scale=8}
local models,err=Placement.placeMany(assets,{treeSpec,fenceSpec},arena)
check(models and #models==2,err or "multi-model placement succeeds")
check(models[1].Parent==models[2].Parent and models[1].Parent.Parent==arena,"tree and fence coexist under one scene")
local box,size=models[2]:GetBoundingBox()
check(math.abs(box.Position.X-50)<1e-6 and math.abs(box.Position.Y-size.Y/2)<1e-6,"fence panel grounds independently at its path location")
local preserved=models[1].Parent
local missingSpec=table.clone(fenceSpec); missingSpec.template="absent"
local rejected,message=Placement.placeMany(assets,{treeSpec,missingSpec},arena)
check(not rejected and message:find("fence.glb",1,true) and not preserved.destroyed,"missing panel fails atomically and diagnoses its asset")
local duplicate=Placement.placeMany(assets,{treeSpec,treeSpec},arena)
check(not duplicate and not preserved.destroyed,"duplicate IDs cannot replace live world")
-- Generated Placements folder is decoded by the existing selector.
local function fields(p)
 return {node("StringValue","InstanceId",p.id),node("StringValue","Source",p.source),node("StringValue","Template",p.template),node("Vector3Value","Position",p.position),node("Vector3Value","Rotation",p.rotation),node("NumberValue","Scale",p.scale)}
end
record.children={node("StringValue","WorldId","tree_test"),node("StringValue","Status","asset-dependent"),node("Folder","Placements",nil,{node("Configuration","item_0",nil,values),node("Configuration","item_1",nil,fields(fenceSpec))})}
selected=require("StudioWorldSelector").start({IsStudio=function() return true end},storage,arena,function() end)
check(selected.active.id=="tree_test" and selected.objects.records["tree-large"].solid,"selector activates multi-placement world retaining tree interactions")
local latest=clones[#clones]; local prior=clones[#clones-1]
check(latest.Parent==prior.Parent and not latest.Parent.destroyed,"selector retains all generated clones")
record.children[3].children[2].children[3].Value="absent"
local fallback=require("StudioWorldSelector").start({IsStudio=function() return true end},storage,container("NewArena"),function() end)
check(fallback.active.id=="default" and next(fallback.objects.records)==nil,"missing panel gives default arena with no partial interactive records")
Instance.new=originalFactory
-- A single native block exercises anisotropic placement and repeated pose reset.
local block={Size=Vector3.new(8,1,20),CFrame=CFrame.new(),Shape=Enum.PartType.Block}
function block:IsA(kind)return kind=="Part" or kind=="BasePart"end
function block:GetChildren()return {}end
local deck={scale=1,frame=CFrame.new()}
function deck:GetDescendants()return {block}end
function deck:GetScale()return self.scale end
function deck:GetPivot()return self.frame end
function deck:ScaleTo(n)block.Size=block.Size*(n/self.scale);self.scale=n end
function deck:PivotTo(frame)self.frame=frame;block.CFrame=frame end
function deck:GetBoundingBox()return block.CFrame,block.Size end
check(Placement.stretchPart(deck)==block,"native block is stretchable")
local pose={scale=1,stretch={1,1,2},position=Vector3.new(4,8,-12),rotation=Vector3.new(20,90,15)}
for i=1,10 do Placement.pose(deck,1,pose)end
check(math.abs(block.Size.Z-40)<1e-6 and block.Size.X==8 and block.Size.Y==1,"repeated native poses stretch one axis without cumulative deformation")
local Geometry=require("WorldObjectGeometry")
local expected=Geometry.from({4,8,-12},{20,90,15},{8,1,40},1)
check((deck.frame.Position-expected.position).Magnitude<1e-5,"stretched visual bounds match server geometry and lowest-point placement")
pose.stretch=nil;Placement.pose(deck,1,pose)
check(block.Size.Z==20,"undo/reset removes stretch from native geometry")
pose.scale=2;pose.stretch={3,1,1};Placement.pose(deck,1,pose)
check(block.Size.X==48 and block.Size.Y==2 and block.Size.Z==40,"uniform scale composes with per-axis stretching")
block.Shape=Enum.PartType.Ball
check(Placement.stretchPart(deck)==nil,"unsupported shapes cannot be stretched")
check(not pcall(Placement.pose,deck,1,pose),"placement rejects stretch on unsupported native shapes")
do
 local model={Name="Rope bridge",frame=CFrame.new(),parts={}}
 function model:IsA(kind)return kind=="Model"end
 local function mesh(name,position,size,rotation)
  local p={Name=name,CFrame=CFrame.new(position)*(rotation or CFrame.new()),Size=size,Parent=model,Transparency=0}
  function p:IsA(kind)return kind=="BasePart" or kind=="MeshPart" end
  function p:SetAttribute()end
  table.insert(model.parts,p);return p
 end
 function model:GetDescendants()return self.parts end
 function model:GetPivot()return self.frame end
 function model:GetBoundingBox()return self.frame,Vector3.new(20,4,40) end
 function model:ScaleTo(scale)assert(scale==1)end
 function model:PivotTo(frame)
  local old=self.frame
  local function at(v)
   local r,u,b=old.RightVector,old.UpVector,old.LookVector
   return Vector3.new(v:Dot(r),v:Dot(u),-v:Dot(b))
  end
  for _,p in self.parts do
   local cf=p.CFrame
   p.CFrame=frame*CFrame.fromMatrix(at(cf.Position-old.Position),at(cf.RightVector),at(cf.UpVector),at(cf.LookVector*-1))
  end
  self.frame=frame
 end
 function model:SetAttribute()end
 local boards=mesh("Boards",Vector3.new(0,-1,0),Vector3.new(16,2,40))
 local rope=mesh("Ropes",Vector3.new(0,1,0),Vector3.new(20,2,40),CFrame.Angles(0,math.pi,0))
 local axes=Placement.resizeAxes(model,{true,true,true})
 check(axes[1] and axes[2] and axes[3],"a multipart bridge supports all aligned resize axes")
 rope.CFrame=CFrame.new(0,1,0)*CFrame.Angles(0,math.pi/4,0)
 axes=Placement.resizeAxes(model,{true,true,true})
 check(not axes[1] and axes[2] and not axes[3],"angled children disable the axes that would introduce shear")
 rope.CFrame=CFrame.new(0,1,0)*CFrame.Angles(0,math.pi,0)
 local resize={id="bridge",scale=1,resizeAxes={true,true,true},stretch={1.5,2,2},position=Vector3.new(6,3,12),rotation=Vector3.new(0,90,0)}
 for i=1,4 do Placement.pose(model,1,resize)end
 local bounds,size=require("AssetGeometry").measure(model)
 check((size-Vector3.new(30,8,80)).Magnitude<1e-5 and (boards.Size-Vector3.new(24,4,80)).Magnitude<1e-5,"multipart mesh sizes and bounds resize without drift")
 check(math.abs(rope.CFrame.Position.Y-boards.CFrame.Position.Y-4)<1e-5 and math.abs(bounds.Position.Y-7)<1e-5,"child origins stretch along with meshes and preserve grounding")
 local faces,bases={},{}
 for _,range in {{-.5,-.25},{-.25,0},{.05,.25},{.25,.5}} do
  local a,b=range[1],range[2]
  table.insert(faces,{{-.4,0,a},{-.4,0,b},{.4,0,a}})
  table.insert(faces,{{.4,0,a},{-.4,0,b},{.4,0,b}})
  table.insert(bases,-.2);table.insert(bases,-.2)
 end
 resize.interaction={fit="faces",faces=faces,bases=bases,sourceSize={20,4,40},fractions=Vector3.new(1,1,1),solid=true,destructible=false,hp=100}
 local objects=require("WorldObjects").new()
 local bridge=objects:add(model,resize)
 check(#bridge.bodies==8 and math.abs(objects:support(-20,12,20)-7)<1e-5,"four resized collision slabs supply support after the world rotation")
 check(objects:support(8,12,20)==nil and objects:support(-20,26,20)==nil,"the resized deck gap and rope border stay clear")
 resize.stretch=nil;Placement.pose(model,1,resize)
 check((boards.Size-Vector3.new(16,2,40)).Magnitude<1e-5,"reset restores original multipart geometry")
 local item={id="asset.bridge",model="Forest/Rope bridge",available=true,resizeAxes={true,true,true},
  collider={fit="faces",faces=faces,bases=bases,sourceSize={20,4,40},widthFraction=1,heightFraction=1,depthFraction=1}}
 local folder={Name="Forest",GetChildren=function()return {model}end}
 local assets={GetChildren=function()return {folder}end}
 local doc=require("WorldEditorDocument").editorFresh()
 doc.objects={{id="bridge",type=item.id,asset=item.model,bounds={1,1,1},position={6,3,12},rotation={0,90,0},scale=1,stretch={1.5,2,2},solid=true,destructible=false,hp=100}}
 local validate=require("PlayerWorldDocument").validate
 local saved,specs=validate(doc,{item},assets)
 check(math.abs(saved.objects[1].bounds[3]-40)<1e-5 and specs[1].stretch[3]==2 and specs[1].interaction.faces==faces,"server rederives native bounds and carries resized collision from its own catalog")
 item.resizeAxes={true,false,true}
 check(not pcall(validate,saved,{item},assets),"server rejects a saved or client-supplied stretch on a disabled axis")
end
CFrame.new=saveNew; CFrame.Angles=saveAngles; CFrame.lookAt=saveLookAt
print(string.format("Studio native-model placement suite passed: %d assertions",count))

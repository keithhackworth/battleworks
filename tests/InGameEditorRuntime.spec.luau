-- Reuse numeric CFrame fixtures. No native viewport pixels/input dispatch claims.
local oldIndex=mt.__index
mt.__index=function(f,key)
 if key=="VectorToWorldSpace" then return function(self,v)return rotate(self.m,v)end end
 if key=="ToObjectSpace" then return function(self,other)
  return CFrame.fromMatrix(self:PointToObjectSpace(other.Position),self:VectorToObjectSpace(other.RightVector),
   self:VectorToObjectSpace(other.UpVector),self:VectorToObjectSpace(other.LookVector)*-1)
 end end
 if key=="VectorToObjectSpace" or key=="PointToObjectSpace" then return function(self,v)
  if key=="PointToObjectSpace" then v=v-self.p end
  local m=self.m
  return Vector3.new(m[1]*v.X+m[4]*v.Y+m[7]*v.Z,m[2]*v.X+m[5]*v.Y+m[8]*v.Z,m[3]*v.X+m[6]*v.Y+m[9]*v.Z)
 end end
 return oldIndex(f,key)
end
local State=require("WorldEditorState")
local Document=require("WorldEditorDocument")
local baseFactory=Instance.new
local runtimeInstances={}
local function isGui(class) return class=="Frame" or class=="TextButton" or class=="TextLabel" or class=="TextBox" or class=="ScrollingFrame" or class=="ViewportFrame" end
Instance.new=function(class)
 local p=baseFactory(class);p.children={};p.scale=1;p.pivot=CFrame.new();p.baseSize=Vector3.new(4,12,4)
 function p:IsA(kind) return kind==class or (kind=="BasePart" and class=="Part") or (kind=="GuiObject" and isGui(class)) or (kind=="LuaSourceContainer" and class=="Script") end
 function p:GetChildren() local out={};for _,child in self.children do if not child.destroyed and child.Parent==self then table.insert(out,child)end end;return out end
 function p:FindFirstChild(name)for _,child in self:GetChildren()do if child.Name==name then return child end end end
 function p:GetDescendants()local out={};local function visit(parent)for _,child in parent:GetChildren()do table.insert(out,child);visit(child)end end;visit(self);return out end
 function p:Destroy()for _,child in self:GetChildren()do child:Destroy()end;self.destroyed=true;self.Parent=nil end
 function p:GetScale()return self.scale end
 function p:ScaleTo(n)self.scale=n end
 function p:GetPivot()return self.pivot end
 function p:PivotTo(cf)self.pivot=cf end
 function p:GetBoundingBox()return self.pivot*CFrame.new(3*self.scale,6*self.scale,-2*self.scale),self.baseSize*self.scale end
 function p:Clone()
  local copy=Instance.new(class);copy.Name=self.Name;copy.scale=self.scale;copy.baseSize=self.baseSize
  for _,child in self:GetChildren()do local cloned=child:Clone();cloned.Parent=copy end
  return copy
 end
 function p:CaptureFocus()UIS.focusedTextBox=self end
 function p:ReleaseFocus()if UIS.focusedTextBox==self then UIS.focusedTextBox=nil end end
 function p:IsDescendantOf(ancestor)
  local parent=self.Parent
  while parent do
   if parent==ancestor then return true end
   parent=parent.Parent
  end
  return false
 end
 setmetatable(p,{__newindex=function(self,key,value)rawset(self,key,value);if key=="Parent" and value then table.insert(value.children,self)end end})
 table.insert(runtimeInstances,p);return p
end
local function node(class,name,parent)local p=Instance.new(class);p.Name=name;p.Parent=parent;return p end
local source=Instance.new("Folder");source.Name="BattleWorksAssets"
-- Match Rojo's Folder-bundle mount: logical Trees/Oak is physically below assets/.
local bundle=node("Folder","assets",source)
local trees=node("Folder","Trees",bundle)
local bundleIndex=node("StringValue","__BattleWorksAssetIndex",source);bundleIndex.Value="source-index"
local oak=node("Model","Oak",trees);local sourcePart=node("Part","Trunk",oak);sourcePart.Anchored=false
local sourceScript=node("Script","MustNotExecute",oak)
local storage=Instance.new("Folder");source.Parent=storage
local a={id="asset.oak",name="Oak",model="Trees/Oak",defaultScale=1,solid=true,destructible=true,hp=150,collider={widthFraction=.3,depthFraction=.3,heightFraction=.5}}
local missing=State.copy(a);missing.id="asset.absent";missing.model="Trees/Missing"
local published,lastExport,importedDocument
local http={JSONDecode=function(_,raw)
 if raw=="source-index" then return {version=1,paths={["Trees/Oak"]="assets/Trees/Oak"}} end
 if raw=="hidden_assets" then return {"Trees/Missing"} end
 if raw=="backup_json" then return State.copy(importedDocument) end
 if raw=="malformed_json" then error("Invalid JSON") end
 return State.copy(if raw=="catalog" then published else {a,missing})
end,JSONEncode=function(_,value)
 if value.schemaVersion then lastExport=State.copy(value);return "{\"schemaVersion\":2}" end
 published=State.copy(value);return "catalog"
end,GenerateGUID=function()return "11111111-1111-1111-1111-111111111111" end}
local replicated=Instance.new("Folder")
local indexService=game.GetService
game.GetService=function(self,name)if name=="HttpService" then return http end;return indexService(self,name)end
local config=node("Folder","BattleWorksStudio",storage)
local metadata=node("StringValue","EditorAssetCatalog",config);metadata.Value="source"
local hidden=node("StringValue","HiddenEditorAssets",config);hidden.Value="hidden_assets"
local library=require("EditorAssetCatalog").publish(storage,replicated,metadata,http)
game.GetService=indexService
check(library.Parent==replicated and library:GetAttribute("Ready"),"catalog published once as a replicated library")
check(published[1].available and not published[2].available and published[1].size[2]==12,"only actual native templates are available; dimensions measured from source")
check(published[2].hidden and not published[1].hidden,"server publishes configured visibility alongside existing catalog entries")
check(oak.Parent==trees and trees.Parent==bundle,"bundle geometry stays in its original source hierarchy while templates are published")
local template=library:FindFirstChild("Templates"):FindFirstChild("Trees"):FindFirstChild("Oak")
check(template and not template:FindFirstChild("MustNotExecute") and not template:FindFirstChild("Trunk").CanCollide and not template:FindFirstChild("Trunk").CanQuery,"published templates strip executable content and all physical participation")
check(not sourcePart.Anchored and not sourceScript.destroyed,"source gameplay templates are unchanged")
do
 local catalog=require("EditorAssetCatalog")
 local service=game.GetService
 local oldCreator,oldType=game.CreatorId,game.CreatorType
 game.CreatorId=42;game.CreatorType={Name="User"}
 local remote=node("Model","Cloud bridge")
 local visual=node("Part","Deck",remote);visual.ClassName="Part";visual.Anchored=false
 local scriptChild=node("Script","Removed",remote);scriptChild.ClassName="Script"
 local calls=0
 game.GetService=function(self,name)
  if name=="InsertService" then return {LoadAsset=function(_,id)check(id==12345,"load uses the trusted catalog ID");calls+=1;return remote end} end
  return service(self,name)
 end
 local cloudItem={model="Forest/CloudBridge",cloudModel={assetId="12345",creatorId="99",creatorType="User"}}
 check(not pcall(catalog.loadCloudModel,source,cloudItem) and calls==0,"cloud asset checks owner before loading")
 cloudItem.cloudModel.creatorId="42"
 local loaded=catalog.loadCloudModel(source,cloudItem)
 check(loaded.Name=="CloudBridge" and loaded.Parent.Name=="Forest" and loaded.Parent.Parent==source,"cloud model mounts at the same canonical path as native models")
 check(visual.Anchored and not visual.CanCollide and not visual.CanQuery and scriptChild.destroyed,"cloud geometry is inert and scripts are stripped before mounting")
 game.GetService=service;game.CreatorId=oldCreator;game.CreatorType=oldType
end
local oldService=game.GetService
local stepping=signal()
local cameraBindings={}
local actions={BindActionAtPriority=function(_,name,callback,_,priority,...)cameraBindings[name]={callback=callback,priority=priority,inputs={...}}end,UnbindAction=function(_,name)cameraBindings[name]=nil end}
UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true
local run={RenderStepped=stepping,IsStudio=function()return true end}
game.GetService=function(self,name)if name=="HttpService"then return http elseif name=="RunService"then return run elseif name=="ContextActionService"then return actions end;return oldService(self,name)end
local mouse=Vector2.new(400,200)
UIS.GetMouseLocation=function()return mouse end;UIS.IsKeyDown=function()return false end
UIS.IsMouseButtonPressed=function()return true end
local worldBefore=#workspace:GetChildren();local cameraBefore=workspace.CurrentCamera
local menu=0
local gameplayActive=true
local controller=require("WorldEditorController").new({parent=Instance.new("Frame"),editorAssets=library,session={mode="Menu"},
 gameplay={setActive=function(_,enabled)gameplayActive=enabled end},home=function()menu+=1 end})
controller:enter();controller.view.isScene=function()return true end
check(controller.scene.world.Parent==controller.view.viewport and workspace.CurrentCamera==cameraBefore,"editor uses an isolated WorldModel and camera")
check(not controller.state.snap,"grid is optional and off by default")
local item=controller.catalog.byPath["Trees/Oak"]
do
 local explicit=table.clone(item)
 explicit.solid=false
 explicit.collider=table.clone(item.collider)
 explicit.collider.explicitCollision=true
 check(Document.canSetAssetTraction(explicit) and not Document.canSetAssetTraction({id="builtin.decoration",collider={}}),"explicit collision assets qualify for traction and the decorative sphere is excluded")
 local point=Vector3.new(10.25,0,-30.75)
 controller:choose(explicit)
 check(controller:candidate(point).solid,"explicit collision overrides a stale non-solid catalog default in the preview")
 local draft=State.new(State.copy(controller.state.document))
 local id=draft:add(explicit,{point.X,0,point.Z})
 check(draft:find(id).solid,"placing an explicit collision asset makes it solid")
 explicit.collider.explicitCollision=nil
 check(not controller:candidate(point).solid,"ordinary non-solid assets keep their configured default")
end
controller:choose(item);controller:place(Vector3.new(10.25,0,-30.75))
controller:choose(item);controller:place(Vector3.new(25.5,0,-30.25))
local first,second=controller.state.document.objects[1],controller.state.document.objects[2]
do
 local original=item.collider.explicitCollision
 item.collider.explicitCollision=true
 controller:refresh()
 check(controller.view.assetTraction.Visible,"selected collision asset exposes the traction field")
 controller.view.assetTraction.Text="0";controller.view.assetTraction.FocusLost:Fire()
 check(second.traction==0,"traction field accepts zero")
 controller.view.assetTraction.Text="";controller.view.assetTraction.FocusLost:Fire()
 check(second.traction==nil,"clearing traction restores the material default")
 item.collider.explicitCollision=original
 controller:refresh()
end
check(first.id~=second.id and first.asset=="Trees/Oak" and first.position[1]==10.25,"palette placement creates independent unique instances with free coordinates")
check(controller.scene.models[first.id].model~=controller.scene.models[second.id].model,"repeated asset placement clones independent native models")
local body=controller.scene.models[first.id].model:FindFirstChild("Trunk")
check(not body.CanCollide and body.CanQuery and body.Parent.Parent==controller.scene.root,"selectable editor geometry never enters Workspace collision")
local box,size=controller.scene.models[first.id].model:GetBoundingBox()
check(math.abs(box.Position.X-first.position[1])<1e-6 and math.abs(box.Position.Y-size.Y/2)<1e-6,"editor uses the production placement helper's exact grounding")
-- Imported rock/building surfaces below the outer top face are valid snap
-- targets. Builtin ramps/platforms continue to use their established face math.
do
 local scene=controller.scene;local savedRaycast=scene.world.Raycast
 local hitPoint=Vector3.new(first.position[1],1,first.position[3])
 for _,normal in {Vector3.new(0,1,0),Vector3.new(0,0,1)}do
  scene.world.Raycast=function()return {Instance=body,Position=hitPoint,Normal=normal}end
  local target=scene:snapTarget(Vector3.new(0,60,0),Vector3.new(0,-1,0),second.id)
  check(target and target.kind=="surface" and target.point[2]==1 and target.normal[3]==normal.Z,"imported irregular rock and building sides snap at the actual native query surface")
 end
 local record=scene.models[first.id];local originalAsset=record.entry.asset
 record.entry.asset="Builtin/BW_block"
 local target=scene:snapTarget(Vector3.new(0,60,0),Vector3.new(0,-1,0),second.id)
 check(not target,"builtin snapping does not change to side-surface behavior")
 record.entry.asset=originalAsset;scene.world.Raycast=savedRaycast
end
do
 local scene=controller.scene
 local record=scene.models[first.id]
 local previousItem,previousRaycast=record.item,scene.world.Raycast
 record.item={collider={fit="faces",faces={
  {{-.5,-.25,-.5},{-.5,-.25,.5},{.5,-.25,-.5}},
  {{.5,-.25,-.5},{-.5,-.25,.5},{.5,-.25,.5}},
 }}}
 scene.world.Raycast=function()return nil end
 local x,z=first.position[1],first.position[3]
 local target=scene:snapTarget(Vector3.new(x+1.9,40,z),Vector3.new(0,-1,0),second.id)
 check(target and target.targetId==first.id and target.kind=="edge" and math.abs(target.point[2]-3)<1e-5,"private viewport snaps to collision deck without a visible-mesh ray hit")
 local nearby=scene:nearbySnap(first,Vector3.new(x+1.9,3,z))
 check(nearby and nearby.kind=="edge","body magnets use the same imported collision edges")
 record.item=previousItem;scene.world.Raycast=previousRaycast
end
-- A geometry-based query double: unlike an unconditional mocked hit, a wrong
-- camera ray really misses. Use a nonzero Roblox top-bar inset and viewport offset.
local Math=require("WorldEditorMath")
local oldFullRect=GuiService.fullRect
GuiService.fullRect={Min=Vector2.new(0,-58),Max=Vector2.new(1280,662)}
controller.view.viewport.AbsolutePosition=Vector2.new(80,40)
controller.view.viewport.AbsoluteSize=Vector2.new(900,500)
controller.scene.camera.CFrame=CFrame.lookAt(box.Position+Vector3.new(0,60,100),box.Position)
local function intersect(frame,bounds,origin,direction)
 local o=frame:PointToObjectSpace(origin);local d=frame:VectorToObjectSpace(direction)
 local near,far=0,5000
 for _,axis in {"X","Y","Z"} do
  local half=bounds[axis]/2
  if math.abs(d[axis])<1e-8 then if math.abs(o[axis])>half then return nil end
  else
   local a,b=(-half-o[axis])/d[axis],(half-o[axis])/d[axis]
   near=math.max(near,math.min(a,b));far=math.min(far,math.max(a,b))
   if near>far then return nil end
  end
 end
 return near
end
controller.scene.world.Raycast=function(_,origin,delta,params)
 if params.FilterDescendantsInstances[1]~=controller.scene.root then return nil end
 local closest,best=nil,math.huge
 for _,record in controller.scene.models do
  local frame,bounds=record.model:GetBoundingBox()
  local distance=intersect(frame,bounds,origin,delta.Unit)
  if distance and distance<best then best=distance;closest=record.model:FindFirstChild("Trunk") end
 end
 if closest then return {Instance=closest,Distance=best,Position=origin+delta.Unit*best} end
end
local pixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,box.Position,controller.scene.camera.FieldOfView)
mouse=controller.view.viewport.AbsolutePosition+pixel-GuiService.fullRect.Min
controller.state.selection={};controller:refresh();controller.scene:selection(nil,controller.distance)
local rawOrigin,rawDirection=Math.ray(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,mouse-controller.view.viewport.AbsolutePosition,controller.scene.camera.FieldOfView)
check(controller.scene:pick(rawOrigin,rawDirection)==nil,"regression fixture reproduces the uncorrected top-bar-offset miss")
local _,pickOrigin,pickDirection,guiMouse=controller:pointer()
check(guiMouse.Y==mouse.Y-58 and controller.scene:pick(pickOrigin,pickDirection)==first.id,"real pointer conversion selects the rendered object with a nonzero GUI inset")
local nativeClick={UserInputType=Enum.UserInputType.MouseButton1,KeyCode=Enum.KeyCode.Unknown}
controller:begin(nativeClick,false)
check(controller:selected().id==first.id and controller.gesture.kind=="Move","clicking a placed object's rendered position reselects it and starts movement")
controller:finishGesture(true)
controller.scene:selection(first.id,controller.distance)
local anchor=controller.scene.anchors.MoveX
local anchorPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,anchor.CFrame.Position,controller.scene.camera.FieldOfView)
mouse=controller.view.viewport.AbsolutePosition+anchorPixel+Vector2.new(5,0)-GuiService.fullRect.Min
controller:begin(nativeClick,false)
check(controller:selected().id==first.id and controller.gesture and controller.gesture.kind=="MoveX","click near a visible axis anchor retains selection and starts handle drag")
controller:finishGesture(true)
for _,mode in {"Rotate","Scale"} do
 controller:setMode(mode);controller.scene:selection(first.id,controller.distance)
 local p=if mode=="Scale" then controller.scene.anchors.Scale else controller.scene.anchors.Rotate1
 local at=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,p.CFrame.Position,controller.scene.camera.FieldOfView)
 mouse=controller.view.viewport.AbsolutePosition+at-GuiService.fullRect.Min
 controller:begin(nativeClick,false)
 check(controller.gesture and controller.gesture.kind==mode and controller:selected().id==first.id,"rendered "..mode.." anchor remains attached to selection")
 controller:finishGesture(true)
end
controller:setMode("Move")
controller.state.selection={};controller.scene:selection(nil,controller.distance)
mouse=controller.view.viewport.AbsolutePosition+pixel-GuiService.fullRect.Min
controller:begin(nativeClick,false)
check(controller:selected().id==first.id,"object remains reselectable after canceling multiple handle gestures")
controller:finishGesture(true)
GuiService.fullRect=oldFullRect
local point=Vector3.new(10.25,0,-30.75)
controller.pointer=function()return point,point+Vector3.new(0,40,0),Vector3.new(0,-1,0),mouse end
controller.scene.world.Raycast=function()return {Instance=body}end
check(controller.scene:pick(Vector3.new(0,40,0),Vector3.new(0,-1,0))==first.id,"private world ray picking resolves the placed object's unique identity")
local picked=first.id
controller.scene.pick=function()return picked end
local click={UserInputType=Enum.UserInputType.MouseButton1,KeyCode=Enum.KeyCode.Unknown}
controller:choose(item);mouse=Vector2.new(470,240);point=Vector3.new(40,0,-40);controller:step(1/60)
local ghost=controller.scene.ghostModel
check(ghost and ghost:FindFirstChild("Trunk").Transparency==.6 and not ghost:FindFirstChild("Trunk").CanQuery,"palette drag shows a translucent non-selectable native placement preview")
UIS.InputEnded:Fire(click)
check(#controller.state.document.objects==3 and not controller.placing and not controller.scene.ghostModel,"releasing a palette drag places one unique object and clears its preview")
point=Vector3.new(10.25,0,-30.75)
controller:begin(click,true)
check(controller.gesture==nil,"processed CoreGui input never starts an editor transform")
controller:begin(click,false)
local history=#controller.state.past
for i=1,10 do point=Vector3.new(10.25+i*.2,0,-30.75);controller:step(1/60)end
check(#controller.state.past==history,"continuous object dragging creates no per-frame undo entries")
controller:finishGesture(false)
check(#controller.state.past==history+1 and math.abs(controller.state:find(first.id).position[1]-12.25)<1e-6,"one drag commits one reversible transaction")
controller:history(false);check(controller.state:find(first.id).position[1]==10.25,"undo drag")
controller:history(true);check(controller.state:find(first.id).position[1]==12.25,"redo drag")
point=Vector3.new(12.25,0,-30.75);controller:begin(click,false);point=Vector3.new(999,0,999);controller:step(1/60);controller:finishGesture(false)
check(controller.state:find(first.id).position[1]==12.25,"out-of-bounds transformation is rejected atomically")
controller.state:select(first.id);controller:refresh()
local hp=controller.view.fields.hp;hp.Text="225";hp.FocusLost:Fire()
check(controller.state:find(first.id).hp==225,"property inspector edits actual BattleWorks durability")
hp.Text="-1";hp.FocusLost:Fire()
check(controller.state:find(first.id).hp==225,"invalid property edit rolls back without corrupting state")
controller.view.duplicate.Activated:Fire();check(#controller.state.document.objects==4,"duplicate UI action")
controller.view.delete.Activated:Fire();check(#controller.state.document.objects==3,"delete UI action")
controller:history(false);check(#controller.state.document.objects==4,"delete undo")
controller:setMode("Rotate");check(controller.scene.anchors.Rotate1 and controller.scene.anchors.Rotate16,"rotation ring has visible 3D anchors")
controller:setMode("Scale");check(controller.scene.anchors.Scale~=nil,"uniform scale has a 3D anchor")
check(controller.view.tools.Stretch==nil,"toolbar exposes only supported transform tools")
do
 local policy=controller.catalog.byPath[first.asset]
 local old=policy.resizeAxes
 policy.resizeAxes={true,false,true}
 controller.state:select(first.id);controller.view.tools.Resize.Activated:Fire();controller:refresh()
 local handles=controller.scene.anchors
 check(handles.ResizeX.CanQuery and not handles.ResizeY.CanQuery and handles.ResizeZ.CanQuery,"resize tool only exposes enabled handles")
 check(controller.view.fields.sizeX.TextEditable and not controller.view.fields.sizeY.TextEditable and controller.view.fields.sizeZ.TextEditable,"dimension inspector follows the same axis policy")
 policy.resizeAxes=old
 controller:setMode("Scale")
end
-- Height-only and tilt-only edits must invalidate the actual scene pose cache.
controller.state:select(first.id);controller:refresh()
controller.view.fields.y.Text="6";controller.view.fields.y.FocusLost:Fire()
check(controller.state:find(first.id).position[2]==6 and controller.scene.models[first.id].y==6,"height inspector updates authoritative document and scene even without horizontal changes")
controller.pointer=getmetatable(controller).pointer
controller.scene.pick=getmetatable(controller.scene).pick
controller:setMode("Move");controller:step(1/60)
local yAnchor=controller.scene.anchors.MoveY
local yPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,yAnchor.CFrame.Position,controller.scene.camera.FieldOfView)
mouse=controller.view.viewport.AbsolutePosition+yPixel-GuiService.fullRect.Min
controller:begin(click,false)
check(controller.gesture and controller.gesture.kind=="MoveY","green vertical anchor can be selected on an elevated object")
mouse-=Vector2.new(0,40);controller:step(1/60);controller:finishGesture(false)
local raised=controller.state:find(first.id).position[2]
check(raised>6 and controller.state:find(first.id).position[1]==12.25,"vertical drag raises selection without changing its X/Z position")
controller.view.rotationAxes.Pitch.Activated:Fire();controller:step(1/60)
local ring=controller.scene.anchors.RotatePitch1
local ringPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,ring.CFrame.Position,controller.scene.camera.FieldOfView)
local targetPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,controller.scene.anchors.RotatePitch3.CFrame.Position,controller.scene.camera.FieldOfView)
mouse=controller.view.viewport.AbsolutePosition+ringPixel-GuiService.fullRect.Min
controller:begin(click,false)
check(controller.gesture and controller.gesture.kind=="RotatePitch","Tilt X button presents a separately pickable pitch ring")
mouse=controller.view.viewport.AbsolutePosition+targetPixel-GuiService.fullRect.Min
controller:step(1/60);controller:finishGesture(false)
local tilted=controller.state:find(first.id).rotation[1]
check(tilted>1 and controller.scene.models[first.id].pitch==tilted,"pitch ring applies a 3D tilt and refreshes native placement")
controller:history(false);check(controller.state:find(first.id).rotation[1]==0 and controller.state:find(first.id).position[2]==raised,"undo tilt preserves raised height")
controller:history(true);check(controller.state:find(first.id).rotation[1]==tilted,"redo restores tilted transform")
-- Exercise actual buttons, ring geometry, projection, picking and drags at
-- exactly 90deg yaw; previously local X/Z rings collapsed onto the same axis.
local Geometry=require("WorldObjectGeometry")
local savedRotation=State.copy(controller.state:find(first.id).rotation)
for _,axis in {"Pitch","Roll","Yaw"} do
 controller:perform(function()controller.state:find(first.id).rotation={0,90,0}end,"Yaw regression setup")
 controller.view.rotationAxes[axis].Activated:Fire()
 local base={rotation={0,90,0}}
 local expectedRight,expectedUp,expectedBack=Geometry.axes(base.rotation)
 local normal=if axis=="Pitch" then expectedRight elseif axis=="Roll" then expectedBack else expectedUp
 local record=controller.scene.models[first.id];local center=record.model:GetBoundingBox().Position
 -- Switching axes updates visible anchor positions immediately, before a tick.
 local prefix=if axis=="Pitch" then "RotatePitch" elseif axis=="Roll" then "RotateRoll" else "Rotate"
 local a=controller.scene.anchors[prefix.."1"].CFrame.Position
 local b=controller.scene.anchors[prefix.."3"].CFrame.Position
 local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
 check(math.abs(dot(a-center,normal))<1e-5 and (a-center).Magnitude>1,"axis button immediately places its ring in rotated local plane")
 local initialPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,a,controller.scene.camera.FieldOfView)
 local finalPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,b,controller.scene.camera.FieldOfView)
 mouse=controller.view.viewport.AbsolutePosition+initialPixel-GuiService.fullRect.Min
 controller:begin(click,false)
 check(controller.gesture and controller.gesture.kind==prefix,"yaw=90 ring picks correct local axis from its rendered position")
 mouse=controller.view.viewport.AbsolutePosition+finalPixel-GuiService.fullRect.Min
 controller:step(1/60);controller:finishGesture(false)
 local rotation=State.copy(controller.state:find(first.id).rotation)
 local r,u,bk=Geometry.axes(rotation)
 local invariant=if axis=="Pitch" then r elseif axis=="Roll" then bk else u
 check((invariant-normal).Magnitude<1e-5 and (r-expectedRight).Magnitude+(u-expectedUp).Magnitude+(bk-expectedBack).Magnitude>.1,"ring turns about selected local axis instead of yaw or another component")
 controller:history(false)
 check(controller.state:find(first.id).rotation[2]==90,"undo restores original yaw=90 orientation")
 controller:history(true)
 local restoredRight,restoredUp,restoredBack=Geometry.axes(controller.state:find(first.id).rotation)
 check((restoredRight-r).Magnitude+(restoredUp-u).Magnitude+(restoredBack-bk).Magnitude<1e-5,"redo restores composed local-axis orientation")
end
controller:perform(function()controller.state:find(first.id).rotation=savedRotation end,"Restore test pose")
controller.view.fields.roll.Text="-10";controller.view.fields.roll.FocusLost:Fire()
check(controller.state:find(first.id).rotation[3]==-10 and controller.scene.models[first.id].roll==-10,"roll inspector updates third rotation axis")
controller.view.rotationAxes.Roll.Activated:Fire()
check(controller.scene.anchors.RotateRoll1~=nil and controller.view.tools.Stretch==nil,"Tilt Z has its own ring while removed stretch tool remains absent")
controller.view.worldId.Text="bad id";controller:export()
check(controller.state.document.id=="ingame_world" and controller.view.json.Text:find("blocked",1,true),"invalid export metadata cannot poison future editing")
controller.view.worldId.Text="oak_test";controller:export()
check(lastExport.schemaVersion==2 and lastExport.objects[1].asset=="Trees/Oak" and lastExport.objects[1].hp==225,"export UI emits existing authoring schema and original hierarchical asset/influences")
importedDocument=State.copy(controller.state.document);importedDocument.id="backup_world";importedDocument.name="Backup world";importedDocument.settings.width=260;importedDocument.objects[1].position[2]=12
local previousScene=controller.scene
controller.view.json.Text="backup_json";controller.view.import.Activated:Fire()
check(controller.state.document.id=="backup_world" and controller.state.document.objects[1].position[2]==12,"JSON backup restores current draft and raised transforms")
check(previousScene.world.destroyed and controller.scene.floor.Size.X==260 and controller.view.viewport.CurrentCamera==controller.scene.camera,"import rebuilds private scene and dimensions without leaking prior scene")
check(controller.state.document.objects[1].asset=="Trees/Oak" and controller.state.document.objects[1].rotation[3]==-10,"import preserves hierarchical identity and tilt")
local currentState=controller.state
controller.view.json.Text="malformed_json";controller.view.import.Activated:Fire()
check(controller.state==currentState and controller.view.status.Text:find("Import blocked",1,true),"malformed backup leaves current world intact")
controller.view.back.Activated:Fire();check(menu==1,"editor exposes explicit main-menu return")
local countBefore=#controller.state.document.objects;local private=controller.scene.world
controller:exit();UIS.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.Delete},false);stepping:Fire(1/60)
check(private.destroyed and controller.scene==nil and #controller.runtime==0 and #controller.state.document.objects==countBefore,"exit removes geometry, disconnects all runtime input and preserves the local draft")
check(#workspace:GetChildren()==worldBefore and workspace.CurrentCamera==cameraBefore,"editing never changes the active battle or workspace camera")
controller:enter();check(#controller.state.document.objects==countBefore,"returning to editor restores session draft")
-- Exercise actual save/open UI and cancellation with controllable task scheduling.
local savedSpawn=task.spawn;local tasks={};local calls={};local savedEntry
local joinCount=0;controller.context.join=function()joinCount+=1 end
controller.library.request=function(action,payload)
 table.insert(calls,{action=action,payload=State.copy(payload)})
 if action=="List" then return {ok=true,temporary=true,worlds=if savedEntry then {{id=savedEntry.document.id,name=savedEntry.document.name,revision=savedEntry.revision}} else {}} end
 if action=="Save" then
  savedEntry={document=State.copy(payload.document),revision=payload.revision+1}
  return {ok=true,temporary=true,document=State.copy(savedEntry.document),revision=savedEntry.revision}
 end
 if action=="Load" then return {ok=true,document=State.copy(savedEntry.document),revision=savedEntry.revision} end
 if action=="Delete" then assert(payload.revision==savedEntry.revision);savedEntry=nil;return {ok=true,deleted=true} end
 if action=="Play" then return {ok=true,launch=true} end
 error("Unexpected world action")
end
controller.view.worlds.Activated:Fire()
check(controller.library.frame.Visible and controller.library.status.Text:find("STUDIO",1,true),"world library opens with explicit temporary-save labeling")
controller.library.id.Text="my_oaks";controller.library.name.Text="My oaks"
controller.library.save.Activated:Fire()
check(savedEntry and savedEntry.document.objects[1].asset=="Trees/Oak" and controller.state.document.id=="my_oaks","save UI sends actual document with hierarchical paths and updates metadata only after success")
controller.library.refresh.Activated:Fire()
local row
for _,node in controller.library.list:GetChildren()do if node:IsA("Frame")then row=node:GetChildren()[1] end end
controller.state.document.objects={};row.Activated:Fire()
check(#controller.state.document.objects==countBefore and controller.library.document==controller.state.document,"open UI restores a saved world and replaces its history/state")
local beforeBlocked=#calls
controller.library.play.Activated:Fire()
check(joinCount==0 and #calls==beforeBlocked and controller.library.frame.Visible,"incomplete world is blocked before saving or requesting Play")
check(controller.library.status.Text:find("not playable",1,true) and controller.library.status.Text:find("0/5",1,true) and controller.library.status.Text:find("top toolbar",1,true),"Play explains the five-zone requirement, current count and tool location")
controller.state.document.spawns={}
for i,p in {{-60,0,-60},{0,0,-60},{60,0,-60},{-60,0,60},{60,0,60}} do table.insert(controller.state.document.spawns,{id="start_"..i,slot=i,position=p,heading=0})end
controller.library.play.Activated:Fire()
check(joinCount==1 and not controller.library.frame.Visible and calls[#calls].action=="Play","Save & Play requests admission only after server launch acknowledgment")
controller.library:open(controller.state.document)
local playCalls=#calls
controller.library.play.Activated:Fire()
check(joinCount==2 and #calls==playCalls+1 and calls[#calls].action=="Play" and calls[#calls].payload.revision==savedEntry.revision,"unchanged Save & Play launches the existing revision without saving")
controller.library:open(controller.state.document)
local deleteButton
for _,node in controller.library.list:GetChildren() do
 if node:IsA("Frame") then for _,button in node:GetChildren() do if button.Text=="Delete" then deleteButton=button end end end
end
local deleteCalls=#calls
deleteButton.Activated:Fire()
check(#calls==deleteCalls and deleteButton.Text=="Confirm Delete","delete requires explicit confirmation")
deleteButton.Activated:Fire()
check(calls[#calls].action=="Delete" and not savedEntry and #controller.state.document.objects==countBefore,"delete removes the saved entry and preserves the editor draft")
-- A late save acknowledgment after leaving cannot trigger Play or overwrite metadata.
task.spawn=function(fn)table.insert(tasks,fn)end
controller.library:open(controller.state.document);table.remove(tasks,1)()
controller.library.id.Text="cancelled_world"
controller.library.play.Activated:Fire();controller:exit();local beforeCalls=#calls
table.remove(tasks,1)()
check(joinCount==2 and #calls==beforeCalls+1 and calls[#calls].action=="Save" and controller.state.document.id=="my_oaks","leaving while a save waits never launches a battle or applies a stale UI result")
task.spawn=savedSpawn;controller:enter()
controller.library.request=function()return {ok=false,message="Storage unavailable"}end
controller.library:open(controller.state.document)
check(controller.library.status.Text:find("Storage unavailable",1,true) and not controller.library.busy,"service errors leave library usable with clear feedback")
-- Camera capture uses movement deltas, including a locked cursor and a
-- viewport-owned event whose global counterpart was marked processed.
controller.library:hide();controller.view.overlay.Visible=false
controller:frameWorld();controller:step(1/60)
local cameraAction=cameraBindings.BattleWorksEditorCamera
check(cameraAction and cameraAction.priority==3000,"editor installs a scoped camera action above default camera priority")
local savedPointer=controller.pointer
controller.pointer=function()return nil,Vector3.new(0,2,0),Vector3.new(0,.1,-1).Unit,mouse end
local rightClick={UserInputType=Enum.UserInputType.MouseButton2,KeyCode=Enum.KeyCode.Unknown}
check(not gameplayActive,"entering the editor explicitly suspends gameplay")
UIS.MouseBehavior=Enum.MouseBehavior.LockCenter;UIS.MouseIconEnabled=false
controller:step(0)
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and UIS.MouseIconEnabled,"an idle editor clears stale turret capture")
controller:begin(rightClick,true)
check(not controller.cameraDrag,"processed global right click alone cannot claim unrelated UI input")
controller.view.viewport.InputBegan:Fire(rightClick)
check(controller.cameraDrag and UIS.MouseBehavior==Enum.MouseBehavior.LockCurrentPosition and not UIS.MouseIconEnabled,"viewport-owned right click captures camera without requiring terrain ray hit")
UIS.InputBegan:Fire({UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.Escape},true)
check(not controller.cameraDrag and UIS.MouseBehavior==Enum.MouseBehavior.Default and UIS.MouseIconEnabled,"processed Escape still releases capture")
controller.view.viewport.InputBegan:Fire(rightClick)
local yawBefore=controller.yaw;local absoluteMouse=mouse
local historyBefore=#controller.state.past;local objectsBefore=#controller.state.document.objects
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Delta=Vector3.new(80,-600,0)})
controller:step(1/60)
check(mouse==absoluteMouse and controller.yaw~=yawBefore,"locked cursor still orbits using raw relative movement")
check(controller.scene.camera.CFrame.Position.Y>=1.49 and controller.scene.camera.CFrame.Position.Y<1.51 and controller.pitch<.02,"right drag reaches eye level without moving below floor")
check(workspace.CurrentCamera==cameraBefore and #controller.state.past==historyBefore and #controller.state.document.objects==objectsBefore,"camera changes neither gameplay camera nor world document/history")
local beforeYaw=controller.yaw
controller:step(1/60);check(controller.yaw==beforeYaw,"one movement delta is consumed once rather than repeated every frame")
UIS.IsKeyDown=function(_,key)return key==Enum.KeyCode.LeftShift end
local beforeFocus=controller.focus
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Delta=Vector3.new(40,20,0)})
controller:step(1/60)
check((controller.focus-beforeFocus).Magnitude<1e-6 and controller.yaw~=beforeYaw,"right drag still orbits at eye level while Shift is held")
UIS.IsKeyDown=function()return false end
local beforeHeight=controller.focus.Y
controller.placing=controller.catalog.byPath["Trees/Oak"]
local armedItem=controller.placing
controller:key({KeyCode=Enum.KeyCode.E},false);controller:step(1/60);controller.keys[Enum.KeyCode.E]=nil
check(controller.focus.Y>beforeHeight,"E raises viewpoint while camera is captured")
controller:key({KeyCode=Enum.KeyCode.Q},false);controller:step(1/60);controller.keys[Enum.KeyCode.Q]=nil
check(controller.cameraDrag~=nil and controller.focus.Y<=beforeHeight+.01,"Q lowers viewpoint while dragging instead of canceling camera")
check(controller.placing==armedItem,"camera navigation preserves an armed asset without placing it")
controller.placing=nil
check(cameraAction.callback("BattleWorksEditorCamera",Enum.UserInputState.End,rightClick)==Enum.ContextActionResult.Sink and not controller.cameraDrag,"camera action owns release and clears capture")
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and UIS.MouseIconEnabled,"right-button release restores cursor and mouse behavior")
local middle={UserInputType=Enum.UserInputType.MouseButton3,KeyCode=Enum.KeyCode.Unknown}
check(cameraAction.callback("BattleWorksEditorCamera",Enum.UserInputState.Begin,middle)==Enum.ContextActionResult.Sink,"middle-button pan captured by editor action")
beforeFocus=controller.focus
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Delta=Vector3.new(30,0,0)})
controller:step(1/60)
check((controller.focus-beforeFocus).Magnitude>1,"middle drag pans without relying on a ground-plane intersection")
UIS.InputEnded:Fire(middle)
check(not controller.cameraDrag and UIS.MouseBehavior==Enum.MouseBehavior.Default,"global mouse release also safely unlocks camera")
controller:beginCamera(middle)
controller:beginCamera(rightClick)
check(controller.cameraDrag.button==Enum.UserInputType.MouseButton2,"right drag replaces middle capture even if its release was missed")
UIS.IsMouseButtonPressed=function()return false end
controller:step(1/60)
check(not controller.cameraDrag and UIS.MouseBehavior==Enum.MouseBehavior.Default,"button polling recovers from a missed release")
UIS.IsMouseButtonPressed=function()return true end
controller.view.isScene=function()return false end
check(cameraAction.callback("BattleWorksEditorCamera",Enum.UserInputState.Begin,rightClick)==Enum.ContextActionResult.Pass and not controller.cameraDrag,"palette/panel clicks are not captured by camera action")
controller.view.isScene=function()return true end
controller.view.overlay.Visible=true
check(not controller:beginCamera(rightClick),"JSON modal blocks camera capture")
controller.view.overlay.Visible=false
UIS.focusedTextBox=controller.view.name
check(not controller:beginCamera(rightClick),"text entry blocks camera capture")
UIS.focusedTextBox=nil
controller:beginCamera(rightClick);GuiService.MenuOpened:Fire()
check(not controller.cameraDrag and controller.paused and UIS.MouseIconEnabled,"Roblox menu releases cursor capture")
local distanceBefore=controller.distance
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseWheel,Position=Vector3.new(0,0,1)})
check(controller.distance==distanceBefore,"wheel does not zoom behind Roblox menu")
GuiService.MenuClosed:Fire();controller:beginCamera(rightClick);UIS.WindowFocusReleased:Fire()
check(not controller.cameraDrag and UIS.MouseBehavior==Enum.MouseBehavior.Default,"focus loss cancels camera capture")
controller:beginCamera(rightClick);UIS.TextBoxFocused:Fire()
check(not controller.cameraDrag,"focusing text input releases camera capture")
controller:beginCamera(rightClick);cameraAction.callback("BattleWorksEditorCamera",Enum.UserInputState.Cancel,rightClick)
check(not controller.cameraDrag,"cancelled input restores camera state")
local originalPick=controller.scene.pick
controller.scene.pick=function()return first.id end
controller.state.selection={}
controller:begin({UserInputType=Enum.UserInputType.MouseButton1,KeyCode=Enum.KeyCode.Unknown},false)
check(controller:selected() and controller:selected().id==first.id,"eye-level object selection works even when ray has no floor intersection")
controller.scene.pick=originalPick
UIS.MouseBehavior=Enum.MouseBehavior.LockCenter;UIS.MouseIconEnabled=false
controller:beginCamera(rightClick);controller:stopCamera()
check(UIS.MouseBehavior==Enum.MouseBehavior.Default and UIS.MouseIconEnabled,"editor camera release never restores a stale gameplay mouse lock")
UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true
controller.pointer=savedPointer;controller:beginCamera(rightClick);controller:exit()
check(not cameraBindings.BattleWorksEditorCamera and not controller.cameraDrag and UIS.MouseBehavior==Enum.MouseBehavior.Default,"editor exit unbinds camera action and restores mouse state")
local exitedYaw=controller.yaw
UIS.InputChanged:Fire({UserInputType=Enum.UserInputType.MouseMovement,Delta=Vector3.new(100,100,0)})
check(controller.yaw==exitedYaw,"late mouse events cannot move an exited editor")
controller:enter();check(cameraBindings.BattleWorksEditorCamera~=nil,"re-entry creates one fresh camera binding")
-- Exercise production snapping transactions, including cancel and refit.
local Snap=require("WorldEditorSnap")
controller.state.document.spawns={} -- Snap scenarios use their own unobstructed draft.
controller.scene.camera.CFrame=CFrame.lookAt(Vector3.new(0,60,100),Vector3.zero)
controller.state:select(first.id);controller.snapSide=0;controller:setMode("Snap");controller:refresh()
local selected=controller:selected()
check(controller.scene.snapEnds.A.CanQuery and controller.scene.snapEnds.B.CanQuery,"snap endpoints are pickable only in private editor scene")
check(controller.view.tools.Snap~=nil and controller.scene.snapEnds.C.CanQuery and controller.scene.snapEnds.D.CanQuery,"Snap tool exposes four side handles")
controller:setMode("Move")
check(not controller.scene.snapEnds.A.CanQuery and not controller.scene.snapEnds.C.CanQuery,"side handles cannot steal Move drags")
controller:setMode("Snap")
controller.view.snapContact.Activated:Fire()
check(controller.fitMode=="Stretch" and controller.view.snapContact.Text=="Scale / [Stretch] / Move","Snap mode cycles from Scale to Stretch")
controller:beginSnap("C",selected)
check(controller.gesture and controller.fitMode=="Scale","imported meshes can snap by falling back from unsupported stretch to proportional scale")
controller:finishGesture(true);selected=controller:selected()
check(controller.fitMode=="Scale","mesh snap fallback keeps Scale selected")
do
 local policy=controller.catalog.byPath[selected.asset]
 local oldCollider,oldAxes=policy.collider,policy.resizeAxes
 policy.collider=table.clone(oldCollider);policy.collider.explicitCollision=true
 policy.resizeAxes={true,true,true}
 controller.fitMode="Stretch";controller:beginSnap("C",selected)
 check(controller.gesture and controller.fitMode=="Stretch","an imported collision asset keeps the requested stretch mode")
 controller:finishGesture(true);selected=controller:selected()
 policy.resizeAxes=nil
 controller:beginSnap("C",selected)
 check(not controller.gesture and controller.fitMode=="Stretch","an incompatible collision asset does not silently switch to uniform scaling")
 policy.collider=oldCollider;policy.resizeAxes=oldAxes;controller.fitMode="Scale"
end
local endpointPixel=Math.project(controller.scene.camera.CFrame,controller.view.viewport.AbsoluteSize,controller.scene.snapEnds.A.CFrame.Position,controller.scene.camera.FieldOfView)
local _,snapHandle=controller.scene:pick(Vector3.new(0,60,100),Vector3.new(0,-1,0),endpointPixel,controller.view.viewport.AbsoluteSize)
check(snapHandle=="SnapA","endpoint pixel picking takes priority over model body")
do
 local scene=controller.scene;local savedRaycast=scene.world.Raycast;local savedPointer=controller.pointer
 local savedCamera=scene.camera.CFrame
 local center=scene.models[first.id].model:GetBoundingBox().Position
 scene.camera.CFrame=CFrame.lookAt(center+Vector3.new(0,12,18),center)
 local occluder=scene.models[second.id].model:FindFirstChild("Trunk")
 local bodyQueries=0
 scene.world.Raycast=function(_,_,_,params)
  if params.FilterDescendantsInstances[1]==scene.root then bodyQueries+=1;return {Instance=occluder}end
 end
 for _,endpoint in {"A","B","C","D"}do
  for _,offset in {Vector2.zero,Vector2.new(0,-23)}do
   controller.state:select(first.id);controller:refresh()
   local pixel=Math.project(scene.camera.CFrame,controller.view.viewport.AbsoluteSize,scene.snapEnds[endpoint].CFrame.Position,scene.camera.FieldOfView)+offset
   controller.pointer=function()return Vector3.zero,Vector3.new(0,60,100),Vector3.new(0,-1,0),controller.view.viewport.AbsolutePosition+pixel end
   controller:begin(nativeClick,false)
   check(controller:selected().id==first.id and controller.gesture and controller.gesture.id==first.id and controller.gesture.endpoint==endpoint,"buried snap sphere and its offset label start the selected object's correct endpoint drag: "..endpoint.." "..offset.Y.." got "..tostring(controller.gesture and controller.gesture.endpoint))
   controller:finishGesture(true)
  end
 end
 check(bodyQueries==0,"selected snap handle and label clicks never fall through to overlapping object selection")
 local id=scene:pick(Vector3.new(0,60,100),Vector3.new(0,-1,0),Vector2.new(2,2),controller.view.viewport.AbsoluteSize)
 check(id==second.id,"clicking away from handles still selects another overlapping object normally")
 controller:setMode("Move")
 local pixel=Math.project(scene.camera.CFrame,controller.view.viewport.AbsoluteSize,scene.snapEnds.A.CFrame.Position,scene.camera.FieldOfView)+Vector2.new(0,-23)
 id=scene:pick(Vector3.new(0,60,100),Vector3.new(0,-1,0),pixel,controller.view.viewport.AbsoluteSize)
 check(id==second.id,"hidden snap labels cannot steal clicks outside Snap mode")
 scene.camera.CFrame=savedCamera;scene.world.Raycast=savedRaycast;controller.pointer=savedPointer;controller:setMode("Snap");selected=controller:selected()
end
controller:pinHere("A")
local pinned=State.copy(controller.state.pins[first.id])
check(pinned and pinned.side==0,"pin action records selected corner contact")
controller:pinHere("B")
check(controller.state.pins[first.id].endpoint=="A","choosing another fixed end cannot silently break existing pin")
local previousPose=State.copy(selected)
controller:beginSnap("B",selected)
local target={point={35,10,-25},normal={0,1,0},kind="edge",targetId=second.id}
local fitted=Snap.fit(selected,"B",target,pinned)
selected.position=fitted.position;selected.rotation=fitted.rotation;selected.scale=fitted.scale
controller.snapPreview={endpoint="B",target=target,valid=true,side=0}
controller:finishGesture(false)
check(controller.state.pins[first.id].second~=nil,"fitting commits both endpoint contacts")
local ends=Snap.ends(controller:selected(),0)
check((ends.A-Vector3.new(table.unpack(pinned.point))).Magnitude<1e-5 and (ends.B-Vector3.new(table.unpack(target.point))).Magnitude<1e-5,"controller fit preserves fixed contact and reaches target")
controller:history(false)
check(not controller.state.pins[first.id].second and controller:selected().scale==previousPose.scale,"undo restores pose and single pin together")
controller:history(true)
check(controller.state.pins[first.id].second~=nil,"redo restores fitted endpoints")
controller:beginSnap("B",controller:selected());controller:finishGesture(true)
check(controller.state.pins[first.id].second~=nil,"cancel refit restores previous second contact")
controller:beginSnap("B",controller:selected());controller:finishGesture(false)
check(controller.state.pins[first.id].second~=nil,"missing snap target rolls back refit")
local contactsBeforeRelease=State.copy(controller.state.pins[first.id]);local pastBeforeRelease=#controller.state.past
controller:perform(function()controller.state.pins[first.id]=nil end,"Released")
check(controller.state.pins[first.id]==nil,"release unlocks transforms")
check(#controller.state.past==pastBeforeRelease,"releasing contacts does not consume an undo step")
controller.state.pins[first.id]=contactsBeforeRelease
local oldPointer=controller.pointer;local oldTarget=controller.scene.snapTarget
controller.pointer=function()return Vector3.zero,Vector3.new(0,60,0),Vector3.new(0,-1,0),Vector2.zero end
controller.view.isScene=function()return true end
controller.scene.snapTarget=function()return target end
controller:beginSnap("B",controller:selected());controller:step(.016)
check(controller.snapPreview and controller.snapPreview.valid,"production drag step computes a valid fit preview")
controller:finishGesture(false)
check(controller.state.pins[first.id].second~=nil,"production drag preview commits")
controller:beginSnap("B",controller:selected())
controller.scene.snapTarget=function()return {point={10000,0,0},kind="ground"} end
controller:step(.016)
check(controller.snapPreview and not controller.snapPreview.valid,"invalid world-boundary fit displays rejection")
controller:finishGesture(false)
check(controller.state.pins[first.id].second~=nil,"invalid fit leaves previous contacts intact")
do
 local before=State.copy(controller:selected())
 local contacts=State.copy(controller.state.pins[first.id])
 local profile=controller:snapProfile(before)
 controller.view.snapContact.Activated:Fire()
 controller.view.snapContact.Activated:Fire()
 check(controller.fitMode=="Move" and controller.view.snapContact.Text=="Scale / Stretch / [Move]","Snap mode cycles from Stretch to Move")
 local start=Snap.contact(before,"B",contacts.side,profile)
 local destination=start+Vector3.new(1,0,0)
 controller.scene.snapTarget=function()return {point={destination.X,destination.Y,destination.Z},kind="edge"} end
 controller:beginSnap("B",controller:selected());controller:step(.016)
 check(controller.snapPreview and controller.snapPreview.valid and not controller.gesture.pin,"Move previews a translation without an opposite anchor")
 controller:finishGesture(true)
 check(State.equal(controller:selected(),before) and State.equal(controller.state.pins[first.id],contacts),"canceling a snap move restores the pose and both pins")
 controller:beginSnap("B",controller:selected());controller:step(.016);controller:finishGesture(false)
 local moved=controller:selected()
 local pin=controller.state.pins[first.id]
 check(pin and not pin.second and (Snap.contact(moved,"B",pin.side,profile)-destination).Magnitude<1e-5,"Move lands the grabbed contact exactly on the target and pins it")
 check(moved.scale==before.scale and State.equal(moved.stretch,before.stretch) and State.equal(moved.rotation,before.rotation),"snap movement preserves scale, stretch and rotation")
 controller:history(false)
 check(State.equal(controller:selected(),before) and State.equal(controller.state.pins[first.id],contacts),"undo restores the pose and previous pins")
 controller.view.snapContact.Activated:Fire()
 check(controller.fitMode=="Scale","Snap mode cycles from Move back to Scale")
end
controller.pointer=oldPointer;controller.scene.snapTarget=oldTarget
local fixedBefore=State.copy(controller.state.pins[first.id])
controller:beginSnap(fixedBefore.endpoint,controller:selected())
check(controller.gesture and controller.gesture.pin.endpoint~=fixedBefore.endpoint,"previously fixed end can be grabbed; opposite end becomes pivot")
controller:finishGesture(true)
check(controller.state.pins[first.id].endpoint==fixedBefore.endpoint,"cancel endpoint swap restores previous contacts")
local savedPick=controller.scene.pick
controller.scene.pick=function()return nil,"MoveX" end
controller.pointer=function()return Vector3.zero,Vector3.new(0,60,0),Vector3.new(0,-1,0),Vector2.zero end
controller:begin({UserInputType=Enum.UserInputType.MouseButton1},false)
check(controller.gesture and controller.gesture.kind=="MoveX" and not controller.gesture.pin and not controller.state.pins[first.id],"Move mode releases contacts instead of blocking movement")
controller:finishGesture(true)
check(controller.state.pins[first.id].second~=nil,"cancel whole-piece movement restores both contacts")
controller:begin({UserInputType=Enum.UserInputType.MouseButton1},false)
local moveX=controller:selected().position[1]
controller.edgeSnap=false
controller.pointer=function()return Vector3.new(3,0,0),Vector3.new(3,60,0),Vector3.new(0,-1,0),Vector2.zero end
controller:step(.016);controller:finishGesture(false)
check(math.abs(controller:selected().position[1]-moveX-3)<1e-5 and not controller.state.pins[first.id],"whole-piece move commits normally after fitting")
controller:history(false)
check(controller.state.pins[first.id].second~=nil,"undo movement restores fitted pose and contacts")
do
 local button={UserInputType=Enum.UserInputType.MouseButton1}
 for _,handle in {"Rotate1","Scale","ResizeZ"} do
  local mode=if handle=="Rotate1" then "Rotate" elseif handle=="Scale" then "Scale" else "Resize"
  controller:setMode(mode)
  controller.scene.pick=function()return nil,handle end
  controller.pointer=function()return Vector3.zero,Vector3.new(3,60,0),Vector3.new(0,-1,-.1).Unit,Vector2.zero end
  controller:begin(button,false)
  check(controller.gesture and not controller.state.pins[first.id],"starting "..mode.." releases both contacts")
  controller:finishGesture(true)
  check(controller.state.pins[first.id].second~=nil,"cancel restores contacts after "..mode)
 end
 local oldYaw=controller:selected().rotation[2]
 controller.view.fields.yaw.Text=tostring(oldYaw+10)
 controller.view.fields.yaw.FocusLost:Fire()
 check(not controller.state.pins[first.id] and controller:selected().rotation[2]==oldYaw+10,"inspector rotation detaches the piece")
 controller:history(false)
 controller.state.pins[second.id]={endpoint="A",point={0,0,0},targetId=first.id}
 controller.view.releasePin.Activated:Fire()
 check(not controller.state.pins[first.id] and not controller.state.pins[second.id],"clearing contacts also removes a neighboring piece's reference to the selected object")
 controller:history(false)
 controller.state.pins[second.id]=nil
end
do
 controller:setMode("Resize")
 controller.scene.pick=function()return nil,"ResizeZ" end
 controller.pointer=function()return Vector3.zero,Vector3.new(3,60,0),Vector3.new(0,-1,-.1).Unit,Vector2.zero end
 controller:begin({UserInputType=Enum.UserInputType.MouseButton1},false)
 check(controller.gesture and controller.gesture.kind=="ResizeZ","resize starts before the pointer leaves")
 local oldScene,oldButton=controller.view.isScene,UIS.IsMouseButtonPressed
 controller.view.isScene=function()return false end
 UIS.IsMouseButtonPressed=function()return true end
 controller.pointer=function()error("outside pointer should not be projected into the world")end
 local distance,focus=controller.distance,controller.focus
 controller:step(1/60)
 controller:zoom(100)
 controller:key({KeyCode=Enum.KeyCode.F},false)
 check(controller.gesture and controller.distance==distance and controller.focus==focus,"outside resize holds the last preview and blocks camera zoom and focus")
 UIS.IsMouseButtonPressed=function()return false end
 controller:step(1/60)
 check(not controller.gesture and controller.distance==distance,"mouse release outside ends the resize without moving the camera")
 controller.view.isScene=oldScene;UIS.IsMouseButtonPressed=oldButton
 controller.pointer=oldPointer
end
controller:setMode("Snap");controller:beginSnap("C",controller:selected())
check(controller.gesture.pin.endpoint=="D","side handle chooses its own opposite side as pivot")
controller:finishGesture(true)
controller.scene.pick=savedPick;controller.pointer=oldPointer
-- Ground-only, numbered areas use the actual editor placement and history path.
controller.state=State.new(require("WorldEditorDocument").editorFresh());controller:refresh()
check(#controller.state.document.spawns==0,"new editor draft requires designer-placed starting areas")
check(controller.view.placeStart.Parent.Parent==controller.view.toolbar,"starting-zone placement is discoverable in the top toolbar")
for i,p in {Vector3.new(-60,0,-60),Vector3.new(0,0,-60),Vector3.new(60,0,-60),Vector3.new(-60,0,60),Vector3.new(60,0,60)} do
 controller.view.placeStart.Activated:Fire();controller:place(p)
 local spawn=controller.state.document.spawns[i]
 check(spawn and spawn.slot==i and controller.scene.spawnModels[spawn.id]~=nil,"placing starting areas creates numbered, selectable caution markings")
end
controller.view.placeStart.Activated:Fire();check(not controller.placingStart,"sixth starting area cannot be armed")
local spawn=controller.state.document.spawns[3];controller.state:select(spawn.id);controller:refresh()
check(controller.view.selected.Text:find("PLAYER 3",1,true)~=nil,"selection identifies exact player starting slot")
controller.view.fields.x.Text="65";controller.view.fields.x.FocusLost:Fire()
check(controller.state:find(spawn.id).position[1]==65,"starting area supports ground position editing")
controller.view.delete.Activated:Fire();check(#controller.state.document.spawns==4,"starting areas can be deleted")
controller:history(false);check(#controller.state.document.spawns==5,"undo restores numbered starting area")
do
 local view=controller.view
 view.dimensions.width.Text="300";view.dimensions.width.FocusLost:Fire()
 check(controller.state.document.settings.width==300 and controller.scene.floor.Size.X==300,"width updates both the draft and viewport")
 view.dimensions.width.Text="25";view.dimensions.width.FocusLost:Fire()
 check(controller.state.document.settings.width==300 and #controller.state.document.spawns==5,"shrinking across starts is rejected without losing data")
 controller:history(false)
 check(controller.scene.floor.Size.X==230,"undo restores the floor dimensions")
 view.newWorld.Activated:Fire()
 check(#controller.state.document.spawns==0 and controller.state.document.id:find("^world_"),"New World clears the draft with a unique save ID")
 controller:history(false)
 check(#controller.state.document.spawns==5,"New World is undoable")
 view.saveAs.Activated:Fire()
 check(controller.library.frame.Visible and controller.library.copyMode and controller.library.id.Text=="","Save As opens the existing library in copy mode")
 controller.library:hide()
 view.assets.Activated:Fire()
 check(not view.palette.Visible,"the toolbar collapses the asset dock")
 view.assets.Activated:Fire()
 controller:choose(controller.catalog.byPath["Trees/Oak"]);controller:place(Vector3.new(0,0,70))
 view.fields.scale.Text="1.5";view.fields.scale.FocusLost:Fire()
 view.repeatPlacement.Activated:Fire()
 controller:choose(controller.catalog.byPath["Trees/Oak"])
 check(controller:candidate(Vector3.new(68,0,0)).scale==1.5,"new placement inherits the last edited scale of the asset")
 controller:place(Vector3.new(68,0,0))
 check(controller.placing~=nil and controller:selected().scale==1.5,"repeat placement remains armed and uses the preview scale")
 controller:cancel()
 controller:focusSelected()
 check(controller.focus.X==68,"F focus targets the selected asset")
 controller:frameWorld()
 check(controller.focus==Vector3.zero,"frame world restores the scene-centered camera")
end
do
 local view=controller.view
 local selected=controller:selected()
 check(view.regenerates.Visible and view.regenerationDelay.Text=="5" and view.regenerationDelay.TextEditable,"destructible assets show regeneration enabled with a five-second default")
 view.regenerationDelay.Text="12.5";view.regenerationDelay.FocusLost:Fire()
 view.regenerates.Activated:Fire()
 check(selected.regenerates==false and selected.regenerationDelay==12.5 and not view.regenerationDelay.TextEditable,"checkbox preserves a custom delay when disabled")
 view.regenerates.Activated:Fire()
 check(selected.regenerates and view.regenerationDelay.Text=="12.5","re-enabling restores the custom delay")
 view.spinToggle.Activated:Fire()
 check(selected.spin and selected.spin.space=="local" and view.spinFields.pause.field.Visible,"the asset inspector exposes rotation without a path")
 view.spinFields.x.field.Text="1";view.spinFields.x.field.FocusLost:Fire()
 view.spinFields.pause.field.Text="3";view.spinFields.pause.field.FocusLost:Fire()
 check(selected.spin.axis[1]==1 and selected.spin.axis[2]==1 and selected.spin.pause==3,"rotation settings combine axes and set a per-turn pause")
 view.spinSpace.Activated:Fire()
 check(selected.spin.space=="world","axis selector can restore world-space spin")
 view.spinSpace.Activated:Fire()
 view.spinMode.Activated:Fire()
 check(selected.spin.swing==90 and view.spinFields.swing.field.Visible,"selecting Swing opens the angle field with a ninety-degree default")
 view.spinFields.swing.field.Text="55";view.spinFields.swing.field.FocusLost:Fire()
 check(selected.spin.swing==55,"swing angle is saved on the placement")
 view.motionPreview.Activated:Fire();check(controller.motionPreview and controller.motionPreview.spin,"rotation-only assets can be previewed")
 view.motionPreview.Activated:Fire()
 view.motionDraw.Activated:Fire()
 check(controller.motionDraft~=nil,"motion action opens an editable path draft")
 local pointer=Vector2.new(-1000,-1000)
 for _,point in {Vector3.new(62,0,0),Vector3.new(82,0,0),Vector3.new(82,0,20),Vector3.new(63,0,0)} do
  controller:motionInput({},point,pointer)
 end
 check(#controller.scene.motionMarkers==4 and #controller.scene.motionLines==3,"waypoints and connected path render in the scene")
 controller.motionPoint=2;controller:drawMotion()
 view.waypointFields[2].field.Text="12";view.waypointFields[2].field.FocusLost:Fire()
 check(controller.motionDraft.points[2][2]==12-selected.position[2],"the waypoint inspector supports vertical motion without moving the other points")
 view.waypointFields[2].field.Text="0";view.waypointFields[2].field.FocusLost:Fire()
 view.motionDraw.Activated:Fire()
 check(selected.motion and State.equal(selected.motion.points[1],selected.motion.points[4]),"finishing a closed path snaps its endpoint to the start")
 view.motionPreview.Activated:Fire()
 check(controller.motionPreview~=nil,"preview animates the selected native model")
 view.motionPreview.Activated:Fire()
 check(controller.motionPreview==nil and selected.motion.enabled,"stopping preview leaves authored motion enabled")
 view.motionRemove.Activated:Fire()
 check(selected.motion==nil,"removing a path clears the saved placement configuration")
 controller:history(false)
 check(controller:selected().motion~=nil,"removing a path is undoable")
end
do
 local loads=0
 local playground=State.copy(controller.state.document)
 controller.state.selection={}
 playground.id="playground";playground.name="Saved Playground"
 controller.library.request=function(action)
  check(action=="Playground","direct Playground editing uses the existing world loader")
  loads+=1;return {ok=true,document=State.copy(playground),revision=7}
 end
 controller:exit()
 controller:enter({openPlayground=true})
 check(loads==1 and controller.state.document.id=="playground" and not controller.library.frame.Visible,
  "Edit Playground loads the saved world into the viewport")
 controller.state.document.name="Unsaved Playground edit"
 controller:exit()
 controller:enter({openPlayground=true})
 check(loads==1 and controller.state.document.name=="Unsaved Playground edit","reopening Edit Playground keeps the in-session draft")
end
do
 local audio=require("WorldSound")
 local builtin=node("Folder","Builtin",library:FindFirstChild("Templates"))
 local template=node("Model","BW_sound_block",builtin)
 local part=node("Part","Geometry",template)
 part.Shape=Enum.PartType.Block;part.Transparency=.6;part.Size=Vector3.new(8,4,8);part.CFrame=CFrame.new()
 local meta={id="builtin.sound_block",name="Sound Block",model=audio.Asset,size={8,4,8},solid=false,stretchable=true,available=true}
 table.insert(controller.catalog.items,meta)
 controller.catalog.byType[meta.id]=meta;controller.catalog.byPath[meta.model]=meta
 controller:setMode("Move")
 local parent=controller.state.document.objects[1]
 controller:choose(meta);controller:place(Vector3.new(10,0,32))
 local block=controller:selected()
 local view=controller.view
 check(block and block.sound and not block.solid and controller.scene.models[block.id].badge,"sound placement defaults to an editor-only marked volume")
 local volume=controller.scene.models[block.id].model:FindFirstChild("Geometry")
 check(volume.Transparency==.5 and volume.CanQuery,"Sound Blocks render and can be selected as translucent volumes")
 view.soundVisibility.Activated:Fire()
 check(volume.LocalTransparencyModifier==1 and not volume.CanQuery and not controller:selected(),"hiding Sound Blocks also disables picking")
 view.soundVisibility.Activated:Fire()
 check(volume.LocalTransparencyModifier==0 and volume.CanQuery,"showing Sound Blocks restores picking")
 controller.state:select(block.id);controller:refresh()
 view.soundButtons.follow.Activated:Fire()
 view.duplicate.Activated:Fire()
 local duplicate=controller:selected()
 check(duplicate.id~=block.id and State.equal(duplicate.position,block.position) and State.equal(duplicate.sound,block.sound),
  "duplicating with collision following on preserves the starting contact and sound settings")
 controller:history(false);controller.state:select(block.id);controller:refresh()
 block=controller:selected()
 view.solid.Activated:Fire()
 check(not block.solid,"the Sound Block inspector never enables physical collision")
 check(Document.canResize(meta,1) and Document.canResize(meta,2) and Document.canResize(meta,3),"sound triggers expose all three native resize dimensions")
 view.soundButtons.activation.Activated:Fire()
 for _=1,3 do view.soundButtons.filter.Activated:Fire() end
 view.soundButtons.origin.Activated:Fire()
 check(block.sound.activation=="Entry" and block.sound.filter=="Specific" and block.sound.origin=="Trigger","the inspector stores trigger activation, filters and source")
 view.soundButtons.targets.Activated:Fire()
 check(view.sfxPicker.Visible and view.sfxTitle.Text=="Trigger Assets","specific filters open a placed-ID picker")
 view.sfxClose.Activated:Fire()
 controller:lockAttachment(block,parent)
 check(block.attachment and block.attachment.parent==parent.id and view.soundButtons.attach.Text:find(parent.id,1,true),"locking stores the parent ID and displays it in the inspector")
 local pose=State.copy(block.position)
 view.soundButtons.attach.Activated:Fire()
 check(not block.attachment and State.equal(block.position,pose),"detach preserves the world pose")
end
do
 local before=controller.state:snapshot()
 local painting={kind="PaintSoundTrail",before=before,penDown=true,lastStamp=Vector3.zero,previousPixel=Vector2.zero,previousHit=Vector3.zero}
 controller.gesture=painting
 check(controller:gestureBlocksCamera(),"the pointer controls the brush while pressed")
 check(controller:liftPaintPointer() and controller.gesture==painting and painting.lastStamp==Vector3.zero,
  "lifting retains the same audio trigger and its existing stamps")
 check(not controller:gestureBlocksCamera() and painting.previousPixel==nil and painting.previousHit==nil and controller.view.finishPaint.Visible,
  "between strokes the camera is movable, the next stroke starts disconnected, and Finish Painting is visible")
 controller:cancel();controller:refresh()
 check(not controller.view.finishPaint.Visible,"cancel closes the entire pending paint session")
end
controller:destroy()
check(cameraBindings.BattleWorksEditorCamera==nil,"destroy removes camera binding")
do
 local replicatedLibrary
 local delayed=require("WorldEditorController").new({parent=Instance.new("Frame"),
  getEditorAssets=function()return replicatedLibrary end,session={mode="Menu"},
  gameplay={setActive=function()end},home=function()end})
 delayed:enter()
 check(not delayed.scene and delayed.view.status.Text:find("Loading",1,true),"early entry shows the loading state")
 replicatedLibrary=library
 local data=library:FindFirstChild("Catalog")
 local raw=data.Value
 data.Value=require("CatalogData").Prefix.."1"
 stepping:Fire(.25)
 check(not delayed.scene,"the editor waits for the complete replicated catalog")
 local chunk=node("StringValue","Chunk0001",data);chunk.Value=raw
 stepping:Fire(.25)
 check(delayed.scene and delayed.catalog.byPath["Trees/Oak"].available,"the open editor builds its scene and palette when the catalog arrives")
 delayed:destroy()
 chunk:Destroy();data.Value=raw
end
Instance.new=baseFactory;game.GetService=oldService
print(string.format("In-game editor production catalog/scene/controller passed: %d assertions",count))

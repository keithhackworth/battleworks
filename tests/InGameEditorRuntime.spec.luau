-- Reuse numeric CFrame fixtures. No native viewport pixels/input dispatch claims.
local oldIndex=mt.__index
mt.__index=function(f,key)
 if key=="VectorToWorldSpace" then return function(self,v)return rotate(self.m,v)end end
 if key=="VectorToObjectSpace" or key=="PointToObjectSpace" then return function(self,v)
  if key=="PointToObjectSpace" then v=v-self.p end
  local m=self.m
  return Vector3.new(m[1]*v.X+m[4]*v.Y+m[7]*v.Z,m[2]*v.X+m[5]*v.Y+m[8]*v.Z,m[3]*v.X+m[6]*v.Y+m[9]*v.Z)
 end end
 return oldIndex(f,key)
end
local State=require("WorldEditorState")
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
 setmetatable(p,{__newindex=function(self,key,value)rawset(self,key,value);if key=="Parent" and value then table.insert(value.children,self)end end})
 table.insert(runtimeInstances,p);return p
end
local function node(class,name,parent)local p=Instance.new(class);p.Name=name;p.Parent=parent;return p end
local source=Instance.new("Folder");source.Name="BattleWorksAssets"
local trees=node("Folder","Trees",source)
local oak=node("Model","Oak",trees);local sourcePart=node("Part","Trunk",oak);sourcePart.Anchored=false
local sourceScript=node("Script","MustNotExecute",oak)
local storage=Instance.new("Folder");source.Parent=storage
local a={id="asset.oak",name="Oak",model="Trees/Oak",defaultScale=1,solid=true,destructible=true,hp=150,collider={widthFraction=.3,depthFraction=.3,heightFraction=.5}}
local missing=State.copy(a);missing.id="asset.absent";missing.model="Trees/Missing"
local published,lastExport
local http={JSONDecode=function(_,raw)return State.copy(if raw=="catalog" then published else {a,missing})end,JSONEncode=function(_,value)
 if value.schemaVersion then lastExport=State.copy(value);return "{\"schemaVersion\":2}" end
 published=State.copy(value);return "catalog"
end}
local replicated=Instance.new("Folder")
local library=require("EditorAssetCatalog").publish(storage,replicated,{Value="source"},http)
check(library.Parent==replicated and library:GetAttribute("Ready"),"catalog published once as a replicated library")
check(published[1].available and not published[2].available and published[1].size[2]==12,"only actual native templates are available; dimensions measured from source")
local template=library:FindFirstChild("Templates"):FindFirstChild("Trees"):FindFirstChild("Oak")
check(template and not template:FindFirstChild("MustNotExecute") and not template:FindFirstChild("Trunk").CanCollide and not template:FindFirstChild("Trunk").CanQuery,"published templates strip executable content and all physical participation")
check(not sourcePart.Anchored and not sourceScript.destroyed,"source gameplay templates are unchanged")
local oldService=game.GetService
local stepping=signal()
local run={RenderStepped=stepping,IsStudio=function()return true end}
game.GetService=function(self,name)if name=="HttpService"then return http elseif name=="RunService"then return run end;return oldService(self,name)end
local mouse=Vector2.new(400,200)
UIS.GetMouseLocation=function()return mouse end;UIS.IsKeyDown=function()return false end
local worldBefore=#workspace:GetChildren();local cameraBefore=workspace.CurrentCamera
local menu=0
local controller=require("WorldEditorController").new({parent=Instance.new("Frame"),editorAssets=library,session={mode="Menu"},home=function()menu+=1 end})
controller:enter();controller.view.isScene=function()return true end
check(controller.scene.world.Parent==controller.view.viewport and workspace.CurrentCamera==cameraBefore,"editor uses an isolated WorldModel and camera")
check(not controller.state.snap,"grid is optional and off by default")
local item=controller.catalog.byPath["Trees/Oak"]
controller:choose(item);controller:place(Vector3.new(10.25,0,-30.75))
controller:choose(item);controller:place(Vector3.new(25.5,0,-30.25))
local first,second=controller.state.document.objects[1],controller.state.document.objects[2]
check(first.id~=second.id and first.asset=="Trees/Oak" and first.position[1]==10.25,"palette placement creates independent unique instances with free coordinates")
check(controller.scene.models[first.id].model~=controller.scene.models[second.id].model,"repeated asset placement clones independent native models")
local body=controller.scene.models[first.id].model:FindFirstChild("Trunk")
check(not body.CanCollide and body.CanQuery and body.Parent.Parent==controller.scene.root,"selectable editor geometry never enters Workspace collision")
local box,size=controller.scene.models[first.id].model:GetBoundingBox()
check(math.abs(box.Position.X-first.position[1])<1e-6 and math.abs(box.Position.Y-size.Y/2)<1e-6,"editor uses the production placement helper's exact grounding")
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
controller.view.fields.roll.Text="-10";controller.view.fields.roll.FocusLost:Fire()
check(controller.state:find(first.id).rotation[3]==-10 and controller.scene.models[first.id].roll==-10,"roll inspector updates third rotation axis")
controller.view.rotationAxes.Roll.Activated:Fire()
check(controller.scene.anchors.RotateRoll1~=nil and controller.view.tools.Stretch==nil,"Tilt Z has its own ring while removed stretch tool remains absent")
controller.view.worldId.Text="bad id";controller:export()
check(controller.state.document.id=="ingame_world" and controller.view.json.Text:find("blocked",1,true),"invalid export metadata cannot poison future editing")
controller.view.worldId.Text="oak_test";controller:export()
check(lastExport.schemaVersion==2 and lastExport.objects[1].asset=="Trees/Oak" and lastExport.objects[1].hp==225,"export UI emits existing authoring schema and original hierarchical asset/influences")
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
for _,node in controller.library.list:GetChildren()do if node:IsA("TextButton")then row=node end end
controller.state.document.objects={};row.Activated:Fire()
check(#controller.state.document.objects==countBefore and controller.library.document==controller.state.document,"open UI restores a saved world and replaces its history/state")
controller.library.play.Activated:Fire()
check(joinCount==1 and not controller.library.frame.Visible and calls[#calls].action=="Play","Save & Play requests admission only after server launch acknowledgment")
-- A late save acknowledgment after leaving cannot trigger Play or overwrite metadata.
task.spawn=function(fn)table.insert(tasks,fn)end
controller.library:open(controller.state.document);table.remove(tasks,1)()
controller.library.id.Text="cancelled_world"
controller.library.play.Activated:Fire();controller:exit();local beforeCalls=#calls
table.remove(tasks,1)()
check(joinCount==1 and #calls==beforeCalls+1 and calls[#calls].action=="Save" and controller.state.document.id=="my_oaks","leaving while a save waits never launches a battle or applies a stale UI result")
task.spawn=savedSpawn;controller:enter()
controller.library.request=function()return {ok=false,message="Storage unavailable"}end
controller.library:open(controller.state.document)
check(controller.library.status.Text:find("Storage unavailable",1,true) and not controller.library.busy,"service errors leave library usable with clear feedback")
controller:destroy()
Instance.new=baseFactory;game.GetService=oldService
print(string.format("In-game editor production catalog/scene/controller passed: %d assertions",count))

local count=0
local function check(ok,message) assert(ok,message);count+=1 end
local State=require("WorldEditorState")
local Document=require("WorldEditorDocument")
local Math=require("WorldEditorMath")
local a={id="asset.oak",name="Oak",model="Trees/Oak",defaultScale=1,size={4,12,4},solid=true,destructible=true,hp=150,collider={widthFraction=.3,depthFraction=.3,heightFraction=.5},available=true}
local b=State.copy(a);b.id="asset.other_oak";b.model="Decorations/Oak";b.solid=false;b.destructible=false
local catalog=Document.catalog({a,b})
local dirs,items=Document.tree(catalog,"")
check(#dirs==2 and dirs[1]=="Decorations" and dirs[2]=="Trees" and #items==0,"palette drills through canonical directories")
dirs,items=Document.tree(catalog,"Trees/")
check(#dirs==0 and #items==1 and items[1].model=="Trees/Oak","leaf asset identity remains fully qualified")
_,items=Document.tree(catalog,"","oak")
check(#items==2 and items[1].id~=items[2].id,"search keeps duplicate basenames independently discoverable")
local s=State.new(Document.fresh());s.snap=false
local one=s:add(a,{10.25,0,-30.75});local two=s:add(b,{-30.1,0,-15.6})
check(one~=two and s:find(one).asset=="Trees/Oak" and s:find(two).asset=="Decorations/Oak","each placement creates an independent instance with full asset identity")
check(s:find(one).position[1]==10.25,"free placement has no forced snapping")
s:select(one);s:duplicate();local three=s:nextId()
check(#s.document.objects==3 and s.document.objects[3].id~=one,"duplicate is a distinct object")
s:undo();check(#s.document.objects==2,"placement duplication undo")
s:redo();check(#s.document.objects==3,"placement duplication redo")
s:select(one)
local before=s:snapshot();local history=#s.past
local base=State.copy(s:find(one))
for step=1,15 do
 local result=Math.transform(base,"MoveX",Vector3.zero,Vector3.new(step*.1,0,200),false,1)
 s:find(one).position=result.position
end
check(#s.past==history and s:find(one).position[3]==base.position[3],"continuous axis drag changes only chosen axis and creates no per-frame history")
s:record(before);check(#s.past==history+1,"gesture commits one history transaction")
s:undo();check(s:find(one).position[1]==base.position[1],"undo restores exact free coordinates")
s:redo();check(math.abs(s:find(one).position[1]-base.position[1]-1.5)<1e-6,"redo restores committed drag")
local snapped=Math.transform(base,"Move",Vector3.zero,Vector3.new(.8,0,.8),true,2)
check(snapped.position[1]%2==0 and snapped.position[3]%2==0,"optional grid snapping uses configured grid")
local x,z=base.position[1],base.position[3]
local rotated=Math.transform(base,"Rotate",Vector3.new(x+10,0,z),Vector3.new(x,0,z+10),false,1)
check(rotated.rotation[2]==270,"rotation follows Roblox yaw orientation")
local scaled=Math.transform(base,"Scale",Vector3.new(x+10,0,z),Vector3.new(x+15,0,z),false,1)
check(scaled.scale==1.5 and scaled.position[1]==x and scaled.position[3]==z,"scale anchor preserves object position and uniform proportions")
-- At Euler yaw=90 the previous component-edit rings collapsed onto X.
local Geometry=require("WorldObjectGeometry")
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
for _,rotation in {{0,90,0},{0,270,0},{20,90,15},{-25,89.999,30}} do
 local object={position={3,8,-7},rotation=rotation,scale=1}
 local right,up,back=Geometry.axes(rotation)
 local axes={{"RotatePitch",right},{"Rotate",up},{"RotateRoll",back}}
 local normals={}
 for _,spec in axes do
  local u,v,n=Math.rotationBasis(object,spec[1]);table.insert(normals,n)
  check((n-spec[2]).Magnitude<1e-6,"rotation handle follows selected object's local axis after yaw")
  local pivot=Vector3.new(3,8,-7)
  local angle=math.rad(30)
  local transformed=Math.transform(object,spec[1],pivot+u*10,pivot+(u*math.cos(angle)+v*math.sin(angle))*10,false,1,pivot)
  local actual={Geometry.axes(transformed.rotation)}
  local sign=if spec[1]=="Rotate" then -1 else 1
  local c,sine=math.cos(angle),math.sin(angle)*sign
  local function expected(q)
   local cross=Vector3.new(n.Y*q.Z-n.Z*q.Y,n.Z*q.X-n.X*q.Z,n.X*q.Y-n.Y*q.X)
   return q*c+cross*sine+n*(dot(n,q)*(1-c))
  end
  for axis,q in {right,up,back} do check((actual[axis]-expected(q)).Magnitude<1e-5,"local-axis drag composes orientation correctly through Euler singularities") end
  check(transformed.position[2]==8 and transformed.scale==1,"rotation preserves height and uniform scale")
  local zero=Math.transform(object,spec[1],pivot+u,pivot+u,false,1,pivot)
  check(zero.rotation[1]==rotation[1] and zero.rotation[2]==rotation[2] and zero.rotation[3]==rotation[3],"zero drag never rewrites Euler angles at gimbal boundary")
  local snapped=Math.transform(object,spec[1],pivot+u*10,pivot+(u*math.cos(math.rad(22))+v*math.sin(math.rad(22)))*10,true,1,pivot)
  local sr,su,sb=Geometry.axes(snapped.rotation)
  local changed=if spec[1]=="RotatePitch" then su else sr
  local original=if spec[1]=="RotatePitch" then up else right
  check(math.abs(dot(changed,original)-math.cos(math.rad(15)))<1e-5,"snapping applies 15 degrees around local axis at yaw=90")
 end
 check(math.abs(dot(normals[1],normals[2]))<1e-6 and math.abs(dot(normals[1],normals[3]))<1e-6 and math.abs(dot(normals[2],normals[3]))<1e-6,"three rotation planes remain distinct at 90-degree yaw")
end
for _,distance in {20,210,1600} do
 local pitch=Math.cameraPitch(-1,0,distance)
 check(math.abs(math.sin(pitch)*distance-1.5)<1e-5,"minimum pitch reaches eye level at any zoom distance")
 check(Math.cameraPitch(2,0,distance)<math.pi/2,"top-down orbit avoids camera up-vector singularity")
end
check(Math.cameraPitch(-.1,20,100)<0,"raised viewpoint can look upward while remaining above floor")
local panFrame={RightVector=Vector3.new(1,0,0),UpVector=Vector3.new(0,1,0)}
local pan=Math.cameraPan(panFrame,Vector2.new(1280,720),Vector2.new(50,25),100,48)
check(pan.X<0 and pan.Y>0 and pan.Z==0,"panning follows the screen plane, independent of terrain ray")
check((Math.cameraPan(panFrame,Vector2.new(1280,720),Vector2.new(50,25),200,48)-pan*2).Magnitude<1e-5,"pan speed scales with visible distance")
local fakeFrame={Position=Vector3.new(0,20,0),VectorToWorldSpace=function(_,v)return Vector3.new(v.X,-1,v.Y)end}
local origin,direction=Math.ray(fakeFrame,Vector2.new(800,400),Vector2.new(400,200),48)
local hit=Math.ground(origin,direction)
check(hit and hit.Magnitude<1e-6,"viewport center ray intersects isolated ground plane")
check(not Math.ground(Vector3.new(0,10,0),Vector3.new(1,0,0)) and not Math.ground(Vector3.new(0,10,0),Vector3.new(0,1,0)),"parallel and backward rays cannot place objects")
check(not Math.ray(fakeFrame,Vector2.zero,Vector2.zero,48),"zero-size viewport does not produce invalid rays")
local lifted=Math.transform(base,"MoveY",Vector3.new(0,3,0),Vector3.new(0,7.3,0),true,2)
check(lifted.position[2]==4 and lifted.position[1]==base.position[1] and lifted.position[3]==base.position[3],"vertical drag snaps only height")
local pitch=Math.transform(base,"RotatePitch",Vector3.new(0,10,0),Vector3.new(0,0,10),false,1,Vector3.zero)
local roll=Math.transform(base,"RotateRoll",Vector3.new(10,0,0),Vector3.new(0,10,0),true,1,Vector3.zero)
check(math.abs(pitch.rotation[1]-90)<1e-6 and pitch.rotation[2]==base.rotation[2] and roll.rotation[3]==90,"tilt gestures preserve other axes and support snapping")
s:change(function()local o=s:find(one);o.position[2]=6;o.rotation={15,37,-10}end)
check(Document.export(s.document,catalog).objects[1].position[2]==6,"elevated tilted authoring document validates")
local export=Document.export(s.document,catalog)
check(export.objects[1].asset=="Trees/Oak" and export.objects[1].bounds[2]==12 and export.objects[1].hp==150 and export.objects[1].solid and export.objects[1].destructible,"export preserves identity, native dimensions and gameplay properties")
export.objects[1].position[1]=100
check(s.document.objects[1].position[1]~=100,"export is detached from live editing state")
for _,bad in {function(o)o.scale=0/0 end,function(o)o.scale=-1 end,function(o)o.position[2]=math.huge end,function(o)o.rotation[1]=0/0 end,function(o)o.position[1]=114 end,function(o)o.asset="../Oak" end,function(o)o.type=b.id end,function(o)o.hp=0 end,function(o)o.position={-22,0,34.5} end} do
 local doc=State.copy(s.document);bad(doc.objects[1]);check(not pcall(Document.export,doc,catalog),"invalid or unsupported edits cannot export")
end
local doc=State.copy(s.document);doc.objects[2].id=doc.objects[1].id
check(not pcall(Document.export,doc,catalog),"duplicate IDs cannot export")
-- Test-only encoder feeds the actual Luau-produced document to the unchanged
-- Node authoring validator/compiler in scripts/check.mjs.
local function json(v)
 if type(v)=="string" then return string.format("%q",v) elseif type(v)=="number" or type(v)=="boolean" then return tostring(v) end
 local result={}
 if #v>0 then for _,n in v do table.insert(result,json(n)) end;return "["..table.concat(result,",").."]" end
 for k,n in v do table.insert(result,json(k)..":"..json(n)) end;return "{"..table.concat(result,",").."}"
end
print("EDITOR_EXPORT",json({document=Document.export(s.document,catalog),items={a,b}}))
local gimbalExport=Document.export(s.document,catalog)
local localBase={position=gimbalExport.objects[1].position,rotation={0,90,0},scale=gimbalExport.objects[1].scale}
local u,v=Math.rotationBasis(localBase,"RotatePitch")
local center=Vector3.new(table.unpack(localBase.position))
gimbalExport.objects[1].rotation=Math.transform(localBase,"RotatePitch",center+u*10,center+v*10,false,1,center).rotation
print("EDITOR_EXPORT",json({document=Document.export(gimbalExport,catalog),items={a,b}}))
local Snap=require("WorldEditorSnap")
local fittedExport=State.copy(gimbalExport)
local source=fittedExport.objects[1]
local pin=Snap.pin("A",{point={5,18,-45},normal={0,1,0}},1)
fittedExport.objects[1]=Snap.fit(source,"B",{point={20,25,-35}},pin)
check(fittedExport.objects[1].asset=="Trees/Oak","auto-fit retains hierarchical catalog reference")
print("EDITOR_EXPORT",json({document=Document.export(fittedExport,catalog),items={a,b}}))
print(string.format("In-game editor document/history/math passed: %d assertions",count))

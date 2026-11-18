-- Real GLB positions/indices are decoded by the Node runner, then production
-- world contacts, footprint support and native transform contracts execute.
local G=require("WorldObjectGeometry")
local F=require("FootprintSupport")
local Objects=require("WorldObjects")
local Contacts=require("VehicleContacts")
local Sim=require("TankSimulation")
local Components=require("VehicleComponents")
local Input=require("InputCommand")
local Motion=require("VehicleMotion")
local function nativeModel(cf,size)
 local part=Instance.new("Part");part.Name="RockMesh";part.CFrame=cf;part.Size=size;part.Transparency=0;part.Parent={}
 function part:IsA(kind)return kind=="BasePart" or kind=="MeshPart"end
 local m={Name="rocks-ramp"}
 function m:GetBoundingBox()return cf,size end
 function m:GetDescendants()return {part}end
 function m:SetAttribute()end
 return m,part
end
local function registryAt(rotation,scale)
 local cf=CFrame.new(0,11.25*scale,0)*CFrame.Angles(0,rotation,0)
 local size=Vector3.new(45,22.5,45)*scale
 local model,mesh=nativeModel(cf,size)
 local objects=Objects.new()
 local record=objects:add(model,{id="rock",rotation=Vector3.zero,interaction={fit="faces",faces=nativeProfile.faces,sourceSize=nativeProfile.sourceSize,solid=true,destructible=true,hp=100,fractions=Vector3.new(1,1,1)}})
 return objects,record,mesh
end
check(#nativeProfile.faces==107,"actual Kenney asset supplies all upward triangles, including steep obstacles")
do
 local model=nativeModel(CFrame.new(0,.25,0),Vector3.new(1,.5,1))
 function model:IsA(kind)return kind=="Model"end
 local folder={Name="Forest",GetChildren=function()return {model}end}
 local assets={GetChildren=function()return {folder}end}
 local item={id="asset.ramp",name="rocks-ramp",model="Forest/rocks-ramp",available=true,collider={fit="faces",faces=nativeProfile.faces,sourceSize=nativeProfile.sourceSize,widthFraction=1,heightFraction=1,depthFraction=1}}
 local doc=require("WorldEditorDocument").fresh();doc.id="terrain_faces"
 doc.objects={{id="rock",type=item.id,asset=item.model,position={0,0,-30},rotation={0,37,0},scale=45,solid=true,destructible=false,hp=100,bounds={.001,.001,.001}}}
 local saved,specs=require("PlayerWorldDocument").validate(doc,{item},assets)
 check(#specs[1].interaction.faces==107 and specs[1].interaction.fit=="faces","server authoring adapter carries only authoritative catalog face profiles into runtime placement")
 check(saved.objects[1].faces==nil and saved.objects[1].bounds[2]==.5,"saved world format stays unchanged and fake client bounds are replaced")
 saved.objects[1].faces={}
 check(not pcall(require("PlayerWorldDocument").validate,saved,{item},assets),"client-supplied collision face claims are rejected")
 item.collider.sourceSize={1,1,1}
 saved.objects[1].faces=nil
 check(not pcall(require("PlayerWorldDocument").validate,saved,{item},assets),"GLB/native model dimension mismatch cannot silently distort collision profiles")
end
for _,yaw in {0,math.rad(37),math.pi/2}do for _,scale in {1,2}do
 local objects,record,mesh=registryAt(yaw,scale)
 check(#record.bodies==107 and #record.geometries==107,"each source face becomes an authoritative convex prism, never the overall square")
 check(#record.proxies==1 and record.proxy==mesh and mesh.CanQuery,"real native mesh handles projectile queries without oversized invisible box")
 local walkable=0;local levels={}
 for _,face in record.geometries do
  local center=(face.vertices[1]+face.vertices[2]+face.vertices[3])/3
  local h=G.support(face,center.X,center.Z,1000)
  if h then
   walkable+=1;check(math.abs(h-center.Y)<1e-5,"source face support matches native rotation, scale and original terrace height")
   levels[math.floor(h*100+.5)]=true
  end
 end
 check(walkable==51,"only walkable faces supply support; steep rock faces remain obstacles")
 local count=0;for _ in levels do count+=1 end
 check(count>5,"multiple source terraces retain their different heights")
 if yaw==0 and scale==1 then
  local supported,empty=0,0
  for x=-21,21,3 do for z=-21,21,3 do
   local ground=objects:support(x,z,100)
   if ground then
    local footprint=objects:footprintSupport(Vector3.new(x,ground,z),0,Components.get("Boomer").Chassis)
    check(footprint and footprint>=ground-1e-5,"actual GLB terrace supports the complete chassis at its own height")
    supported+=1
   else empty+=1 end
  end end
  check(supported>30 and empty>10,"real source terrain preserves both usable terraces and open areas inside its old square")
 end
 local token={};objects:impact({Instance=mesh},25,token);objects:impact({Instance=mesh},25,token)
 check(record.health==75,"native hits still share one authoritative damage receipt")
 objects:impact({Instance=mesh},75,{})
 check(not mesh.CanQuery and #objects:obstacles()==0 and objects:footprintSupport(Vector3.new(0,30,0),0,Components.get("Boomer").Chassis)==nil,"destruction removes all face collision, support and native hit queries")
 objects:reset();check(mesh.CanQuery and #objects:obstacles()==107,"reset restores original face geometry without accumulating proxies")
end end
-- An empty triangular corner inside the old rectangular bounds is clear.
local obstacle=Contacts.polygon("triangle",{Vector3.new(-10,0,-10),Vector3.new(10,0,-10),Vector3.new(-10,0,10)},0,10)
local function bodyAt(position)
 local state=Sim.new(position,"Boomer");local body=Contacts.body("tank",state,Components.get(state).Chassis);body.halfX=1;body.halfZ=1
 return body,state
end
local body,state=bodyAt(Vector3.new(8,0,8));Contacts.solve({body},{obstacle},1/60)
check((state.position-Vector3.new(8,0,8)).Magnitude<1e-6,"empty triangle corner is not a rectangular obstacle")
body,state=bodyAt(Vector3.new(-5,0,-5));Contacts.solve({body},{obstacle},1/60)
check((state.position-Vector3.new(-5,0,-5)).Magnitude>.1,"actual triangular volume still blocks overlap")
body,state=bodyAt(Vector3.new(0,0,30));Motion.setVelocity(state,Vector3.new(0,0,-2000));state.motionStepStart=state.position;state.motionYawStart=0
Contacts.solve({body},{obstacle},.05)
check(state.position.X+state.position.Z>=1.99 and state.position.X>1,"continuous polygon collision deflects a high-speed tank along the actual diagonal instead of tunneling")
-- Two adjoining horizontal triangles at height 1 form a reachable terrain top.
local faces={{{-.5,0,-.5},{-.5,0,.5},{0,0,-.5}},{{0,0,-.5},{-.5,0,.5},{0,0,.5}},{{0,.5,-.5},{0,.5,.5},{.5,.5,-.5}},{{.5,.5,-.5},{0,.5,.5},{.5,.5,.5}}}
local model,mesh=nativeModel(CFrame.new(0,1,0),Vector3.new(30,2,30))
local objects=Objects.new();local record=objects:add(model,{id="terraces",rotation=Vector3.zero,interaction={fit="faces",faces=faces,sourceSize={30,2,30},solid=true,destructible=false,hp=100,fractions=Vector3.new(1,1,1)}})
local env={size=Vector2.new(230,230),rocks={},logs={},trees={},zones={},worldObjects=objects}
for _,kind in {"Boomer","Rattler"}do
 state=Sim.new(Vector3.new(-12,1,0),kind);state.yaw=-math.pi/2;local cmd=Input.neutral();cmd.throttle=1
 for _=1,75 do
  Sim.step(state,cmd,1/60,env.size,env,true)
  Contacts.solve({Contacts.body("tank",state,Components.get(state).Chassis)},objects:obstacles(),1/60)
  Sim.reconcileGround(state,env)
  check(state.position.Y>=.99,"tank remains supported while driving across triangulated rock tops and their shared diagonal")
 end
 check(state.position.X>5 and state.position.Y>=1.99,"both tanks drive from one reachable terrace to the next")
end
-- A steep face is not silently converted into a climbable top.
local steep=G.faces(G.from({0,0,0},{0,0,0},{10,10,10},1),{{{-.5,-.5,0},{-.5,.5,.1},{.5,-.5,0}}})[1]
check(G.planeHeight(steep,0,0)==nil,"vertical/steep terrain never becomes drivable support")
check(not G.canTraverse(steep,Vector3.zero,10),"a genuine tall rock riser remains a blocking obstacle")
local bevel=G.faces(G.from({0,0,0},{0,0,0},{1,1,1},1),{{{-.5,-.5,0},{-.5,.5,.1},{.5,-.5,0}}})[1]
check(G.canTraverse(bevel,Vector3.zero,10) and not G.support(bevel,0,0,10),"short rock bevels respect the existing step allowance without becoming fake support")
CFrame.new=saveNew;CFrame.Angles=saveAngles;CFrame.lookAt=saveLookAt
print(string.format("GLB terrain faces and authoritative collision passed: %d assertions",count))

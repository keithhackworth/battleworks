local Geometry=require("WorldObjectGeometry")
local Objects=require("WorldObjects")
local Contacts=require("VehicleContacts")
local Sim=require("TankSimulation")
local Components=require("VehicleComponents")
local Codec=require("CatalogData")
-- Production codec exercises native-sized chunk bounds and missing replication.
do
 local raw=string.rep("x",Codec.Limit-1).."界"..string.rep("x",Codec.Limit+17);local oldFactory=Instance.new
 Instance.new=function(class)
  local node={children={}}
  function node:IsA(kind)return kind==class end
  function node:FindFirstChild(name)for _,child in self.children do if child.Name==name then return child end end end
  return setmetatable(node,{__newindex=function(self,key,value)rawset(self,key,value);if key=="Parent" then table.insert(value.children,self)end end})
 end
 local node=Instance.new("StringValue");local http={JSONEncode=function()return raw end,JSONDecode=function(_,s)check(s==raw,"production catalog chunks reconstruct the exact encoded data");return {ok=true}end}
 Codec.write(node,{},http)
 check(#node.children==3 and node.Value==Codec.Prefix..3,"large catalogs are packaged into bounded native strings")
 for _,child in node.children do check(#child.Value<=Codec.Limit and utf8.len(child.Value)~=nil,"each runtime string remains bounded and valid UTF-8")end
 check(Codec.decode(node,http).ok,"server/client codec reads chunked catalogs")
 local last=table.remove(node.children)
 check(not pcall(Codec.decode,node,http),"incomplete chunk replication cannot silently produce a partial catalog")
 function node:WaitForChild(name,timeout)check(timeout==5,"client chunk wait is bounded");return last end
 check(Codec.decode(node,http,true).ok,"client waits for a missing replicated catalog chunk")
 Instance.new=oldFactory
end
for _,item in bulkItems do
 local c=item.collider;local size=Vector3.new(table.unpack(c.sourceSize))*20
 local frame=CFrame.new(0,size.Y/2,0)*CFrame.Angles(0,.4,0)
 local mesh=Instance.new("Part");mesh.Name="NativeMesh";mesh.Size=size;mesh.CFrame=frame;mesh.Transparency=0;mesh.Parent={}
 function mesh:IsA(kind)return kind=="BasePart"end
 local model={Name=item.model}
 function model:GetBoundingBox()return frame,size end
 function model:GetDescendants()return {mesh}end
 function model:SetAttribute()end
 local objects=Objects.new();local record=objects:add(model,{id="test",rotation=Vector3.zero,interaction={fit="faces",faces=c.faces,bases=c.bases,walls=c.walls,sourceSize=c.sourceSize,fractions=Vector3.new(1,1,1),solid=true,destructible=true,hp=100}})
 check(#record.geometries==#c.faces+#c.walls,"bulk profile carries actual top faces and vertical walls into runtime for "..item.model)
 check(#record.bodies>0 and mesh.CanQuery,"bulk asset remains solid and queryable")
 local walls=0
 for _,body in record.bodies do if body.surface.wall then walls+=1 end end
 check(walls>0,"actual side faces remain obstacles, including thin fence walls")
 -- A raised deck's underside remains above ground; it must not acquire the
 -- former base-to-top collision column.
 local raised=0
 for i,face in c.faces do
  if c.bases[i]>-.4 then
   raised+=1
   local box=record.geometries[i]
   check(box.position.Y-box.extents.Y>size.Y*.099,"paired underside preserves clearance beneath a raised surface")
  end
 end
 check(if item.model=="Surburban/fence" then raised==0 else raised>0,"underside clearance follows the actual mesh, including solid fence panels")
 if item.model:find("fence",1,true)then
  local largest,target=0,nil
  for _,face in record.geometries do
   if not face.wall and face.up.Y>.999 then
    local a,b,c=table.unpack(face.vertices)
    local u,v=b-a,c-a
    local area=math.abs(u.X*v.Z-u.Z*v.X)
    if area>largest then largest=area;target=(a+b+c)/3 end
   end
  end
  local height=target and objects:footprintSupport(target,0,Components.get("Boomer").Chassis)
  check(height and height>=target.Y-.001,"actual solid fence top can support a tank regardless of its asset category")
 end
 objects:impact({Instance=mesh},100,{})
 check(#objects:obstacles()==0 and not mesh.CanQuery,"all generated walls/faces share destruction lifecycle")
 objects:reset();check(#objects:obstacles()>0 and mesh.CanQuery,"bulk collision resets without stale state")
end
-- Thin wall faces remain in the existing continuous SAT solver.
local wall=Contacts.polygon("fence",{Vector3.new(0,0,-10),Vector3.new(0,10,-10),Vector3.new(0,10,10)},0,10,true)
local state=Sim.new(Vector3.new(-8,0,0),"Boomer")
local Motion=require("VehicleMotion");Motion.setVelocity(state,Vector3.new(1000,0,0));state.motionStepStart=state.position;state.motionYawStart=0
Contacts.solve({Contacts.body("tank",state,Components.get(state).Chassis)},{wall},.05)
check(state.position.X<0,"zero-thickness source wall is a query-safe blocking fence face, not a drive-through gap")
CFrame.new=saveNew;CFrame.Angles=saveAngles;CFrame.lookAt=saveLookAt
print(string.format("Bulk asset collision and catalog transport passed: %d assertions",count))

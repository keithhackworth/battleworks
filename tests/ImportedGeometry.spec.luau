-- Numeric transforms plus production geometry, fitting and collision registry.
-- Native MeshPart query fidelity is validated separately in Studio.
local Visual=require("AssetGeometry")
local Fit=require("MeshCollisionFit")
local G=require("WorldObjectGeometry")
local Objects=require("WorldObjects")
local Contacts=require("VehicleContacts")
local Sim=require("TankSimulation")
local Components=require("VehicleComponents")
local function vehicle(position)
 local state=Sim.new(position,"Boomer")
 local body=Contacts.body("probe",state,Components.get(state).Chassis)
 body.halfX=1;body.halfZ=1
 return body
end
local function part(cf,size,transparency)
 return {Name="Mesh",CFrame=cf,Size=size,Transparency=transparency or 0,IsA=function(_,kind)return kind=="BasePart"end}
end
local function model(cf,size,parts)
 local m={Name="Imported",parts=parts or {part(cf,size)}}
 function m:GetBoundingBox()return cf,size end
 function m:GetDescendants()return self.parts end
 function m:SetAttribute()end
 return m
end
for _,scale in {1,2.5}do for _,yaw in {0,37,90}do
 local cf=CFrame.new(31,9,-12)*CFrame.Angles(0,math.rad(yaw),0)
 local size=Vector3.new(12,8,6)*scale
 local visible=part(cf,size)
 local padding=part(CFrame.new(1000,1000,1000),Vector3.new(200,200,200),1)
 local proxy=part(CFrame.new(-1000,0,0),Vector3.new(100,100,100));proxy.Name="WorldObstacleHitbox"
 local source=model(cf,Vector3.new(999,999,999),{visible,padding,proxy})
 local measured,dimensions=Visual.measure(source)
 check((measured.Position-cf.Position).Magnitude<1e-6 and (dimensions-size).Magnitude<1e-6,"rotated/scaled visible bounds exclude invisible helpers and generated proxies")
 local box=G.fromBox(measured,dimensions);local planar=G.planar(box,0)
 check(math.abs(planar.hx-size.X/2)<1e-6 and math.abs(planar.yaw-math.rad(yaw))<1e-6,"custom collider orientation comes from the measured frame, including native pivot orientation")
end end
-- A rock whose narrow footprint occupies the center, but not its empty corners.
local cells=Fit.sample(Vector3.new(80,20,80),function(x,z)
 if x*x+z*z<30*30 then return -10,10 end
end)
check(#cells>1 and #cells<64,"irregular mesh produces bounded compound collision rather than one outer rectangle")
local function add(registry,id,cf,size,boxes)
 return registry:add(model(cf,size),{id=id,rotation=Vector3.zero,interaction={solid=true,destructible=true,hp=100,fractions=Vector3.new(1,1,1),boxes=boxes}})
end
for _,yaw in {0,math.pi/2}do for _,scale in {1,1.7}do
 local objects=Objects.new();local cf=CFrame.new(0,10*scale,0)*CFrame.Angles(0,yaw,0)
 local record=add(objects,"rock",cf,Vector3.new(80,20,80)*scale,cells)
 check(#objects:obstacles()==#cells and #record.proxies==#cells,"every fitted cell uses the existing authoritative solver, with no overarching bounding collider")
 local corner=cf:PointToWorldSpace(Vector3.new(37*scale,0,37*scale))
 check(objects:support(corner.X,corner.Z,100)==nil,"empty rock corner has no phantom support after rotation and scale")
 check(objects:support(0,0,100)~=nil,"actual rock volume retains support")
 local body=vehicle(Vector3.new(corner.X,0,corner.Z))
 local before=body.state.position
 Contacts.solve({body},objects:obstacles(),1/60)
 check((body.state.position-before).Magnitude<1e-6,"tank solver leaves a vehicle in the visible clearance beside an irregular rock")
 local center=vehicle(Vector3.zero)
 Contacts.solve({center},objects:obstacles(),1/60)
 check(center.state.position.Magnitude>.1,"occupied rock interior still blocks vehicles")
 local token={};objects:impact({Instance=record.proxies[1]},25,token)
 objects:impact({Instance=record.proxies[2]},25,token)
 check(record.health==75,"compound cells share one health and projectile receipt")
 objects:impact({Instance=record.proxies[#record.proxies]},75,{})
 check(#objects:obstacles()==0,"destruction removes every fitted collision cell")
 for _,proxy in record.proxies do check(not proxy.CanQuery,"destruction disables all cell hit queries")end
 objects:reset();check(#objects:obstacles()==#cells,"reset restores all cells without duplicates")
end end
-- Buildings/bridges are deliberately not subjected to the irregular rock profile.
for _,name in {"imported-building","imported-bridge","builtin-platform"}do
 local objects=Objects.new();local record=add(objects,name,CFrame.new(0,12,0),Vector3.new(40,4,60))
 check(#record.proxies==1 and record.proxy.Size.X==40 and record.proxy.Size.Z==60,"unprofiled buildings, bridges and builtins retain full physical support")
 check(objects:support(19,29,100)==14,"platform edge remains supported")
 check(objects:projectileGround(Vector3.new(19,30,29),Vector3.new(0,-1,0),100,.1,0)==14,"airborne projectile leveling still selects the elevated platform")
end
check(#Fit.sample(Vector3.new(10,10,10),function()return nil end)==0,"missing native mesh volume is detectable for conservative fallback")
-- Execute the production native-query adapter with deterministic spatial hits.
do
 local factory=Instance.new;local samples,clones,destroyed=0,0,0
 local source=model(CFrame.new(),Vector3.new(80,20,80))
 function source:Clone()clones+=1;return model(CFrame.new(),Vector3.new(80,20,80))end
 Instance.new=function(class)
  if class~="WorldModel" then return factory(class)end
  return {Destroy=function()destroyed+=1 end,Raycast=function(_,origin,direction)
   samples+=1
   if origin.X*origin.X+origin.Z*origin.Z>=30*30 then return nil end
   return {Position=Vector3.new(origin.X,if direction.Y<0 then 10 else -10,origin.Z)}
  end}
 end
 local profile=Fit.profile(source)
 check(profile and #profile==#cells,"source template native raycasts feed the same irregular shape sampler")
 local previous=samples
 check(Fit.profile(source)==profile and samples==previous and clones==1 and destroyed==1,"template fit is cached and the isolated measurement WorldModel is destroyed")
 check(source.parts[1].Anchored==nil and source.parts[1].CanQuery==nil,"fitting never mutates imported source geometry")
 Instance.new=factory
end
CFrame.new=saveNew;CFrame.Angles=saveAngles;CFrame.lookAt=saveLookAt
print(string.format("Imported geometry regression suite passed: %d assertions",count))

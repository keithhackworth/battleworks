local G=require("WorldObjectGeometry")
local F=require("FootprintSupport")
local Objects=require("WorldObjects")
local Environment=require("Environment")
local Sim=require("TankSimulation")
local Components=require("VehicleComponents")
local Contacts=require("VehicleContacts")
local Input=require("InputCommand")
local shape=Components.get("Boomer").Chassis
local function box(x,y,z,w,d,rotation)
 return G.from({x,y-.2,z},rotation or {0,0,0},{w,.2,d},1)
end
local function environment(boxes)
 local registry=Objects.new()
 for i,b in boxes do
  local id=tostring(i)
  local planar=G.planar(b)
  local body=Contacts.box(id,b.position,planar.hx,planar.hz,planar.bottom-b.position.Y,planar.top-b.position.Y,planar.yaw);body.surface=b
  registry.records[id]={solid=true,destroyed=false,proxy={Parent=true},geometries={b},bodies={body}}
 end
 return {size=Vector2.new(230,230),rocks={},logs={},trees={},zones={},worldObjects=registry}
end
local function step(state,env,command)
 Sim.step(state,command or Input.neutral(),1/60,env.size,env,true)
 Contacts.solve({Contacts.body("tank",state,Components.get(state).Chassis)},env.worldObjects:obstacles(),1/60)
 Sim.reconcileGround(state,env)
end
-- A diagonal seam passes through every point of the old five-point cross:
-- most of the footprint still lies on real faces on both sides of that seam.
local function diagonalSeam(gap)
 local r,u,b=G.axes({0,45,0})
 local result={}
 for _,sign in {-1,1}do
  local center=r*(sign*(10+gap/2))+Vector3.new(0,9.9,0)
  table.insert(result,G.fromBox(CFrame.new(center)*CFrame.Angles(0,math.pi/4,0),Vector3.new(20,.2,40)))
 end
 return result
end
for _,yaw in {0,math.pi/4,math.pi/2,math.pi*.73}do
 local faces=diagonalSeam(.05)
 local h=F.solve(faces,Vector3.new(0,10,0),yaw,shape)
 check(h and math.abs(h-10)<1e-6,"tiny gap under the center retains support for rotated chassis")
end
-- Intersecting slits defeat all five old sample positions simultaneously.
local quadrants={}
for _,x in {-1,1}do for _,z in {-1,1}do table.insert(quadrants,box(x*10.025,10,z*10.025,20,20))end end
local h,p,r=F.solve(quadrants,Vector3.new(0,10,0),0,shape)
check(h and math.abs(h-10)<1e-6 and math.abs(p)+math.abs(r)<1e-6,"cross-shaped center gap is supported by the actual footprint rather than center/axial rays")
for _,point in {{0,0},{0,-shape.ContactLength/2},{0,shape.ContactLength/2},{shape.ContactWidth/2,0},{-shape.ContactWidth/2,0}}do
 for _,face in quadrants do check(not G.support(face,point[1],point[2],11.5),"reproduction genuinely misses every original center/cross support sample")end
end
for _,kind in {"Boomer","Rattler"}do
 local env=environment(quadrants);local tank=Sim.new(Vector3.new(0,10,0),kind)
 for _=1,90 do step(tank,env);check(math.abs(tank.position.Y-10)<1e-5,"stationary tank never drops into center slit")end
 local drive=Input.neutral();drive.throttle=1
 tank=Sim.new(Vector3.new(0,10,12),kind)
 for _=1,55 do step(tank,env,drive);check(tank.position.Y>=9.99,"tank drives across perpendicular narrow platform seams")end
end
-- Two real faces at slightly different heights support both sides, not an
-- average with empty air or the floor far below.
local uneven={box(-10.05,10,0,20,40),box(10.05,10.4,0,20,40)}
h,p,r=F.solve(uneven,Vector3.new(0,10,0),0,shape)
check(h and h>=10 and h<=10.4 and r>0,"small elevation difference produces a supported suspension plane")
local env=environment(uneven);local tank=Sim.new(Vector3.new(-4,10,0),"Boomer");tank.yaw=-math.pi/2
local drive=Input.neutral();drive.throttle=1
for _=1,60 do step(tank,env,drive);check(tank.position.Y>=9.99 and tank.position.Y<10.8,"slightly uneven seam has no support drop or large launch")end
check(tank.position.X>3,"tank crosses slightly uneven surfaces without weakening planar collision: "..tank.position.X.." Y="..tank.position.Y)
-- Real imported compound cells use exactly the same support polygons, across
-- cell boundaries and small empty regions inside an irregular profile.
local outer=G.from({0,9.8,0},{0,37,0},{20,.2,20},1)
local cells={}
for _,x in {-1,1}do for _,z in {-1,1}do table.insert(cells,{center={x*.252,0,z*.252},size={.496,1,.496}})end end
local compound=G.cells(outer,cells)
check(F.solve(compound,Vector3.new(0,10,0),.3,shape)~=nil,"rotated imported compound collider seams support the chassis")
env=environment(compound);tank=Sim.new(Vector3.new(0,10,0),"Boomer");tank.yaw=.3
for _=1,60 do step(tank,env);check(math.abs(tank.position.Y-10)<1e-5,"compound mesh cells support the authoritative movement/reconciliation path over a center gap")end
env.worldObjects.records["1"].destroyed=true;env.worldObjects.records["2"].destroyed=true
env.worldObjects.records["3"].destroyed=true;env.worldObjects.records["4"].destroyed=true
step(tank,env)
check(tank.position.Y<10,"destroyed compound cells immediately stop supporting tanks")
-- Large openings, one-sided cliff contact and grazing a tiny corner do not
-- gain support from an extrapolated plane.
local large={box(-15,10,0,20,40),box(15,10,0,20,40)}
check(F.solve(large,Vector3.new(0,10,0),0,shape)==nil,"opening wider than chassis has no structural support")
local cliff={box(-10,10,0,20,40)}
check(F.solve(cliff,Vector3.new(-.1,10,0),0,shape)~=nil,"partial footprint remains supported while center of mass is over the platform")
check(F.solve(cliff,Vector3.new(.1,10,0),0,shape)==nil,"one-sided support cannot hold center of mass past a cliff")
check(F.solve({box(11,10,11,20,20)},Vector3.new(0,10,0),0,shape)==nil,"grazing one footprint corner does not suspend tank")
for _,faces in {large,cliff}do
 env=environment(faces);tank=Sim.new(Vector3.new(.2,10,0),"Boomer")
 for _=1,60 do step(tank,env)end
 check(tank.position.Y<1,"unsupported tank falls through large gap or off cliff")
end
local overhead={box(0,20,0,40,40)}
check(F.solve(overhead,Vector3.new(0,0,0),0,shape)==nil,"footprint support never pulls a grounded tank onto an overhead deck")
-- Adjacent flat/ramp surfaces, including an intentionally small join.
local ramp=G.from({0,0,0},{30,0,0},{12,.2,24},1)
local top=24*math.sin(math.pi/6)+.2*math.cos(math.pi/6)
local endZ=-12*math.cos(math.pi/6)+.1*math.sin(math.pi/6)
local faces={ramp,box(0,top,endZ-12-.1,20,24)}
for z=endZ+2,endZ-4,-.1 do
 local expected=math.min(top,G.planeHeight(ramp,0,z))
 local height=F.solve(faces,Vector3.new(0,expected,z),0,shape)
 check(height and height>=expected-.001 and height<top+2,"flat/ramp join supports full footprint throughout transition")
end
CFrame.new=saveNew;CFrame.Angles=saveAngles;CFrame.lookAt=saveLookAt
print(string.format("Footprint support regressions passed: %d assertions",count))

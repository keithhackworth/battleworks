local T=require("PlaygroundTerrain")
local Env=require("Environment")
local Sim=require("TankSimulation")
local Components=require("VehicleComponents")
local Command=require("InputCommand")
local count=0
local function check(ok,message)assert(ok,message);count+=1 end
local size=Vector2.new(230,230);local data=T.create(size)
local env=Env.create(size);env.rocks={};env.logs={};env.trees={};env.zones={};env.playground=data
check(T.sample(data,0,0)==0,"bridge spans the ravine")
check(T.sample(data,0,30)==-42,"ravine has no invisible floor at bank level")
check(T.sample(data,-50,-50)==4.5 and T.sample(data,-50,-80)==9,"sloped western overlook matches elevated plateau")
check(not T.hazard(data,Vector3.new(0,0,30)) and T.hazard(data,Vector3.new(0,-28,30))=="River","death volume uses horizontal bounds and depth, not just Y")
check(T.hazard(data,Vector3.new(-50,-30,30))=="BelowGround" and not T.hazard(data,Vector3.new(200,-30,90)),"buried vehicles use terrain-relative detection; outside arena is not a river")
for _,p in data.spawns do check(T.safe(data,p,7),"public tank starts on safe bank land")end
for _,p in data.entries do check(T.safe(data,p,7),"all designated avatar/replenishment anchors have clearance")end
check(not T.safe(data,Vector3.new(0,0,0),4),"respawns never use bridge")
check(T.safe(data,Vector3.new(0,0,0),5,true),"bridge center permits a safe exit")
check(not T.safe(data,Vector3.new(0,0,10),5,true) and not T.safe(data,Vector3.new(-23,0,30),5,true),"cliff and bridge edges reject unsafe ejection")
local function tank(x,y,z,yaw)
 local state=Sim.new(Vector3.new(x,y,z),"Boomer")
 state.yaw=yaw or 0
 return state
end
local function step(state,input,n)
 for _=1,n do Sim.step(state,input or Command.neutral(),1/60,size,env)end
end
-- Actual custom suspension/movement crosses bridge, slopes, and leaves edges.
local drive=Command.neutral();drive.throttle=1
local a=tank(-50,0,-5,-math.pi/2);local b=tank(50,0,5,math.pi/2)
local Contacts=require("VehicleContacts")
for _=1,190 do
 Sim.step(a,drive,1/60,size,env,true);Sim.step(b,drive,1/60,size,env,true)
 Contacts.solve({Contacts.body("a",a,Components.get(a).Chassis),Contacts.body("b",b,Components.get(b).Chassis)},Contacts.obstacles(env,size),1/60)
 Sim.reconcileGround(a,env);Sim.reconcileGround(b,env)
end
check(a.position.X>24 and b.position.X< -24 and math.abs(a.position.Y)<.01 and math.abs(b.position.Y)<.01,"two lanes cross opposite ways without losing support")
local edge=tank(0,0,25,0);step(edge,nil,1)
check(edge.position.Y<0 and edge.position.Y> -1,"cliff descent uses gravity rather than teleporting to the recoil height cap")
local fall=tank(0,0,0,0)
for _=1,130 do
 local previous=fall.position.Y;step(fall,drive,1)
 check(fall.position.Y>=previous-Components.get(fall).Recoil.MaxFallSpeed/60-.1,"crossing a bridge edge never teleports downward")
end
check(fall.position.Y< -27 and T.hazard(data,fall.position),"tank driving off bridge falls into hazard")
local cliff=tank(-40,0,35,-math.pi/2);step(cliff,drive,130)
check(cliff.position.Y< -27 and T.hazard(data,cliff.position),"tank driving off bank falls rather than clamping to original floor")
local slope=tank(-60,0,-32,0);step(slope,drive,130)
check(slope.position.Y>5 and slope.position.Z< -55,"tank climbs the overlook slope")
local classic=Env.create(size)
check(Env.sample(classic,0,30)==0 and not classic.playground,"Classic retains original ground and environment")
print(string.format("Playground terrain/support passed: %d assertions",count))

do
 local Starter=require("PlaygroundWorld")
 local Document=require("WorldEditorDocument")
 local Settings=require("WorldSettings")
 local State=require("WorldEditorState")
 local first=Starter.new()
 local catalog={}
 local byId={}
 for _,object in first.objects do
  if not byId[object.type] then
   byId[object.type]=true
   table.insert(catalog,{id=object.type,model=object.asset,stretchable=true,collider={widthFraction=1,heightFraction=1,depthFraction=1}})
  end
 end
 Settings.ready(first)
 local exported=Document.export(first,Document.catalog(catalog))
 check(exported.id=="playground" and #exported.objects>20 and exported.settings.terrain,"Playground starter uses the existing editable terrain, placements and starting zones")
 check(State.equal(first,exported) and State.equal(first,Starter.new()),"starting conversion is deterministic and uses independent document copies")
 exported.settings.terrain.heights[1]+=8
 check(not State.equal(first,exported),"an edited Playground save is independent of the seed")
end

do
 local Tunnel=require("WorldTunnel")
 local H=require("WorldHeightfield")
 local Contacts=require("VehicleContacts")
 local Settings=require("WorldSettings")
 local size=Vector2.new(120,120)
 local settings={width=120,depth=120,boundary=true,ground={material="Grass",color={100,112,86}},terrain=H.new(120,120),spawns={},zones={},
  tunnels={{a={-40,0,0},b={40,0,0},diameter=16,traction=35}}}
 for z=0,settings.terrain.rows do for x=0,settings.terrain.columns do
  if x>=7 and x<=13 then settings.terrain.heights[H.index(settings.terrain,x,z)]=30*H.Unit end
 end end
 Settings.validate(settings,true)
 local env=Env.create(size);env.terrainSettings=settings;env.rocks={};env.trees={};env.logs={};env.zones={}
 local floor,_,_,kind,_,material=Env.pose(env,Vector3.new(0,0,0),0)
 check(floor==0 and kind=="Tunnel" and material.authoredTraction==.35,"under the ridge the tunnel floor and traction replace the surface")
 check(Env.pose(env,Vector3.new(0,30,0),0)==30,"hill above the bore keeps its original ground")
 local bodies=Contacts.obstacles(env,size)
 check(#bodies>4 and bodies[5].id:find("tunnel:",1,true),"tunnel liner walls use the ordinary fixed obstacle solver")
 local slabs=Tunnel.compile(settings)
 local cut={}
 Tunnel.cut(slabs[1],{Vector3.new(-1,4,-1),Vector3.new(1,4,-1),Vector3.new(0,4,1)},cut)
 check(#cut==0,"terrain inside portal clearance is removed")
 Tunnel.cut(slabs[1],{Vector3.new(-1,30,-1),Vector3.new(1,30,-1),Vector3.new(0,30,1)},cut)
 check(#cut==1,"terrain above the bore remains available to terrain queries")
 local rider=Sim.new(Vector3.new(-32,0,0),"Boomer");rider.yaw=-math.pi/2
 local command=Command.neutral();command.throttle=1
 for _=1,160 do Sim.step(rider,command,1/60,size,env) end
 check(rider.position.X>0 and rider.position.Y<.1,"a tank drives through the hill without climbing the original terrain")
 local sideways=Sim.new(Vector3.new(0,0,0),"Rattler")
 sideways.yaw=math.pi
 for _=1,90 do Sim.step(sideways,command,1/60,size,env) end
 check(sideways.position.Z>0 and sideways.position.Z<8,"the side liner physically contains a tank inside the bore")
 settings.tunnels[1].diameter=4
 check(not pcall(Settings.validate,settings,true),"invalid tunnel dimensions are rejected")
end

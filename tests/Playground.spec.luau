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

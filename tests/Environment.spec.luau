local Environment=require("Environment")
local Simulation=require("TankSimulation")
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local terrain=Environment.create(Vector2.new(230,230))
check(#terrain.rocks>0 and #terrain.logs>0 and #terrain.trees>0,"default arena includes rocks, logs and woods")
local again=Environment.create(Vector2.new(230,230))
check(#terrain.rocks==#again.rocks and terrain.rocks[1].x==again.rocks[1].x,"redraw generates deterministic terrain")
for _,size in {Vector2.new(25,25),Vector2.new(40,300),Vector2.new(230,230),Vector2.new(2000,2000)} do
 local env=Environment.create(size)
 for _,list in {env.rocks,env.logs,env.trees} do for _,item in list do
  check(math.abs(item.x)<size.X/2-5 and math.abs(item.z)<size.Y/2-5,"generated obstacles remain within map")
  check(math.abs(item.z+size.Y*65/230)>10,"target row stays clear")
 end end
 for _,zone in env.zones do
  check(math.abs(zone.x)+zone.rx<size.X/2 and math.abs(zone.z)+zone.rz<size.Y/2,"surface zones fit resized arena")
 end
end
local cmd={throttle=1,steer=0,aimMode="Rate",turretX=0,turretY=0}
for index,ratio in {0.9,0.75} do
 local zone=terrain.zones[index]
 local state=Simulation.new(Vector3.new(zone.x,0,zone.z))
 Simulation.step(state,cmd,1/60,terrain.size,terrain)
 check(math.abs(state.speed-24*ratio)<1e-5,"water/mud use intended speed multiplier")
 check(state.surface==zone.kind,"surface type replicates for client effects")
 local reverse=table.clone(cmd); reverse.throttle=-1
 Simulation.step(state,reverse,1/60,terrain.size,terrain)
 check(math.abs(state.speed+24*ratio)<1e-5,"terrain slowdown applies in reverse too")
end
local flat=Simulation.new(Vector3.new(0,0,20))
Simulation.step(flat,cmd,1/60,terrain.size,terrain)
check(flat.speed==24,"grass retains base speed")
local hill={size=Vector2.new(230,230),zones={},trees={},logs={},rocks={{x=0,z=0,rx=5,rz=6,height=2.5}}}
local state=Simulation.new(Vector3.new(0,0,3))
local neutral=table.clone(cmd); neutral.throttle=0
for _=1,120 do Simulation.step(state,neutral,1/60,hill.size,hill) end
check(state.position.Y>1 and state.bodyPitch>0.1,"rock lifts and pitches tank from ground samples")
local pivot,direction=Simulation.shotPose(state)
check(pivot.Y>4.6 and direction.Y>0.1,"uneven terrain changes actual shell origin and direction")
local log={size=hill.size,zones={},trees={},rocks={},logs={{x=0,z=0,half=5,radius=0.9}}}
local height,kind=Environment.sample(log,0,0)
check(height==0.9 and kind=="Log","fallen logs provide traversable raised surface")
local tree=terrain.trees[1]
check(Environment.blocked(terrain,tree.x,tree.z,5),"trunks block movement")
check(not Environment.blocked(terrain,0,20,5),"spawn corridor remains clear")
local approach=Simulation.new(Vector3.new(tree.x,0,tree.z+6))
local before=approach.position
Simulation.step(approach,cmd,0.1,terrain.size,terrain)
check(approach.position.Z==before.Z and approach.speed==0,"tank stops at a trunk without entering it")
-- Execute the actual builders/effects against small service stand-ins.
do
 local originalNew,originalFrame,originalAngles=Instance.new,CFrame.new,CFrame.Angles
 local created={}
 Instance.new=function(class) local p=originalNew(class); table.insert(created,p); return p end
 local frameMT={}
 frameMT.__mul=function(a,b) return setmetatable({Position=a.Position+b.Position},frameMT) end
 frameMT.__index={PointToWorldSpace=function(self,p) return self.Position+p end}
 CFrame.new=function(x,y,z)
  return setmetatable({Position=if type(x)=="number" then Vector3.new(x,y,z) else x or Vector3.zero},frameMT)
 end
 CFrame.Angles=function() return CFrame.new(Vector3.zero) end
 local arena=Instance.new("Folder")
 local previous
 arena.FindFirstChild=function() return previous end
 local Builder=require("EnvironmentBuilder")
 previous=Builder.build(arena,terrain)
 local cover,water,wood=0,0,0
 for _,p in created do
  if p.Name=="Rock" or p.Name=="FallenLog" or p.Name=="TreeTrunk" then
   check(p.CanQuery and not p.CanCollide,"cover is queryable but uses scripted tank movement"); cover+=1
  elseif p.Name=="Water" then check(not p.CanQuery,"water does not block projectiles"); water+=1
  elseif p.Name=="TreeCrown" then check(not p.CanQuery,"leaves do not behave as solid cover"); wood+=1 end
 end
 check(cover>0 and water==1 and wood>0,"builder creates terrain and wooded geometry")
 local old=previous; previous=Builder.build(arena,Environment.create(Vector2.new(25,25)))
 check(old.destroyed,"redraw removes previous environment geometry")
 local savedService=game.GetService
 local removed,tweens={},{}
 game.GetService=function(self,name)
  if name=="Debris" then return {AddItem=function(_,p,age) table.insert(removed,{part=p,age=age}) end} end
  if name=="TweenService" then return {Create=function(_,p,info,goal)
   local tween={Completed=signal(),Play=function() end}; table.insert(tweens,tween); return tween
  end} end
  return savedService(self,name)
 end
 local Effects=require("TerrainEffects")
 local visual={position=Vector3.zero,yaw=0}
 local wet={position=Vector3.zero,yaw=0,speed=20,health=100,surface="Water"}
 Effects.update(visual,wet,1/60)
 check(#removed==16,"entering water emits eight ripple segments and eight splash droplets")
 for _,item in removed do check(item.age<=0.75 and not item.part.CanQuery and not item.part.CanCollide,"water effects expire and cannot affect combat") end
 Effects.update(visual,wet,0.1)
 check(#removed==16,"splash emission is throttled between frames")
 wet.speed=0; Effects.update(visual,wet,1)
 check(#removed==16,"stopped tanks do not continuously splash")
 wet.speed=18; wet.surface="Mud"; Effects.update(visual,wet,1)
 check(#removed==20,"mud emits dirt flecks without water rings")
 game.GetService=savedService
 Instance.new=originalNew; CFrame.new=originalFrame; CFrame.Angles=originalAngles
end
print(string.format("Environment suite passed: %d assertions",count))

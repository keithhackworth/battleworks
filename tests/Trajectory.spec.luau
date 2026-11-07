local Path=require("ProjectileTrajectory")
local Projectiles=require("ProjectileSimulation")
local Sim=require("TankSimulation")
local Config=require("TankConfig")
local Definitions=require("TankDefinitions")
local tuning=Definitions.Rattler.Weapon
local count=0
local function check(ok,message) assert(ok,message); count+=1 end
local function near(a,b) return math.abs(a-b)<1e-5 end
local empty={GetPartBoundsInRadius=function() return {} end,Spherecast=function() return nil end}
for _,degrees in {35,40} do
 local settings={DescentAngle=math.rad(degrees),LevelingDistance=6}
 local pivot=Vector3.new(0,Config.MuzzleHeight+24,0)
 local direction=Path.launchDirection(pivot,Vector3.new(0,0,-1),Config.MuzzleHeight,7,settings)
 check(near(direction.Y,-math.sin(math.rad(degrees))),"configured airborne descent angle is respected")
 local origin=pivot+direction*7
 local path=Path.new(origin,direction,Config.MuzzleHeight,settings)
 local begin=path.straight
 local finish=begin+path.arc
 local before,initial=Path.sample(path,begin*0.5)
 check(near(initial.Y,direction.Y) and near((before-origin).Magnitude,begin*0.5),"initial diagonal is a straight line")
 local last=origin.Y
 for i=0,120 do
  local distance=(finish+20)*i/120
  local p,v=Path.sample(path,distance)
  check(p.Y<=last+1e-5 and p.Y>=Config.MuzzleHeight-1e-5,"descent and leveling do not overshoot height")
  check(near(v.Magnitude,1) and near(v.X,0),"tangent is unit length and never changes heading")
  last=p.Y
 end
 local a,va=Path.sample(path,begin-1e-5)
 local b,vb=Path.sample(path,begin+1e-5)
 check((a-b).Magnitude<0.001 and (va-vb).Magnitude<0.001,"straight-to-curve transition is continuous")
 a,va=Path.sample(path,finish-1e-5); b,vb=Path.sample(path,finish+1e-5)
 check((a-b).Magnitude<0.001 and (va-vb).Magnitude<0.001,"curve-to-horizontal transition is smooth")
 local p,v=Path.sample(path,finish+100)
 check(near(p.Y,Config.MuzzleHeight) and near(v.Y,0) and near(v.Z,-1),"after leveling, height and original heading stay fixed")
 local curve=(begin+finish)/2
 local c=Path.sample(path,curve)
 local d=Path.sample(path,curve+0.0001)
 check(math.abs((d-c).Magnitude-0.0001)<1e-7,"curve distance parameter preserves normal speed")
end
for _,altitude in {0,0.1,1,3,6,24} do
 local state=Sim.new(Vector3.new(0,altitude,0),"Rattler")
 local pivot,direction=Sim.shotPose(state)
 local shell=Projectiles.launch(empty,pivot,direction,{},tuning)
 check(shell.position.Y>=Config.MuzzleHeight-1e-5,"low-altitude barrel never places muzzle below standard plane")
 check(near(shell.remaining,tuning.Range-tuning.MuzzleOffset),"muzzle sweep retains original range accounting")
 local traveled=0
 while not shell.done and traveled<400 do
  local before=shell.remaining
  Projectiles.step(empty,shell,1/60)
  local distance=before-shell.remaining
  check(distance<=tuning.ShellSpeed/60+1e-5,"trajectory consumes only normal speed per tick")
  traveled+=distance
 end
 check(shell.done and shell.remaining<=1e-5,"staged projectile expires at normal path range")
 check(near(shell.position.Y,Config.MuzzleHeight),"every supported airborne height eventually levels to standard muzzle height")
end
-- Below the plane means horizontal flight, not teleporting upward.
do
 local shell=Projectiles.new(Vector3.new(0,2,0),Vector3.new(0,-0.5,-1),{},tuning)
 Projectiles.step(empty,shell,0.1)
 check(near(shell.position.Y,2) and near(shell.direction.Y,0),"already-low projectile fires horizontally at its current height")
 local floorY=17
 local raised=Sim.new(Vector3.new(0,floorY+24,0),"Rattler"); raised.groundPlaneY=floorY
 local pivot,direction=Sim.shotPose(raised)
 local shell=Projectiles.launch(empty,pivot,direction,{},tuning,floorY)
 Projectiles.step(empty,shell,2)
 check(near(shell.position.Y,floorY+Config.MuzzleHeight),"level height follows standard tank geometry plus actual arena floor height")
end
-- Segment-vs-expanded-box sweeps let the real path hit cover and ground tanks.
local function worldFor(objects)
 return {
  GetPartBoundsInRadius=function() return {} end,
  Spherecast=function(_,position,radius,delta)
   local nearest
   for _,p in objects do
    local lo,hi=0,1
    for _,axis in {"X","Y","Z"} do
     local minimum=p.position[axis]-p.size[axis]/2-radius
     local maximum=p.position[axis]+p.size[axis]/2+radius
     if math.abs(delta[axis])<1e-9 then
      if position[axis]<minimum or position[axis]>maximum then lo=2 end
     else
      local a,b=(minimum-position[axis])/delta[axis],(maximum-position[axis])/delta[axis]
      if a>b then a,b=b,a end
      lo=math.max(lo,a); hi=math.min(hi,b)
     end
    end
    if lo<=hi and lo>=0 and lo<=1 and (not nearest or lo*delta.Magnitude<nearest.Distance) then
     nearest={Instance=p,Position=position+delta*lo,Distance=lo*delta.Magnitude}
    end
   end
   return nearest
  end,
 }
end
local function launched(world)
 local state=Sim.new(Vector3.new(0,24,0),"Rattler")
 local origin,direction=Sim.shotPose(state)
 return Projectiles.launch(world,origin,direction,{},tuning)
end
local wall={position=Vector3.new(0,15,-20),size=Vector3.new(12,30,2)}
local shell=launched(worldFor({wall}))
local hit
for _=1,120 do hit=Projectiles.step(worldFor({wall}),shell,1/60); if hit then break end end
check(hit and hit.Instance==wall and shell.direction.Y<0,"wall blocks the descending stage before it can pass through")
local lowWall={position=Vector3.new(0,3,-15),size=Vector3.new(12,6,2)}
local tank={position=Vector3.new(0,2.5,-65),size=Vector3.new(8,5,10)}
local world=worldFor({lowWall,tank})
shell=launched(world)
for _=1,120 do hit=Projectiles.step(world,shell,1/60); if hit then break end end
check(hit and hit.Instance==tank and near(shell.direction.Y,0),"high shot clears low cover then hits ground tank after leveling")
-- No stage can tunnel through a thin obstruction, including one inside the arc.
local path=launched(empty)
local arcPoint=Path.sample(path.trajectory,path.trajectory.straight+path.trajectory.arc/2)
local thin={position=arcPoint,size=Vector3.new(10,10,0.04)}
local curveWorld=worldFor({thin})
shell=launched(curveWorld)
hit=Projectiles.step(curveWorld,shell,1)
check(hit and hit.Instance==thin,"large time step still sweeps a thin obstacle in the leveling curve")
-- Muzzle obstruction checks remain straight, before any free-flight leveling.
local cover={position=Vector3.new(0,25,-2),size=Vector3.new(10,10,0.1)}
local blocked,obstruction=launched(worldFor({cover}))
check(obstruction and obstruction.Instance==cover and blocked.done,"cover next to barrel blocks launch")
-- Frame partitioning and enemy movement cannot change the frozen path.
local a,b=launched(empty),launched(empty)
Projectiles.step(empty,a,0.8)
for _=1,48 do Projectiles.step(empty,b,1/60) end
check((a.position-b.position).Magnitude<1e-5 and (a.direction-b.direction).Magnitude<1e-5,"trajectory is frame-partition independent")
local originalHeading=a.trajectory.heading
for _=1,30 do tank.position=Vector3.new(100,2.5,math.random()*100); Projectiles.step(empty,a,1/60) end
check((a.trajectory.heading-originalHeading).Magnitude<1e-8 and near(a.direction.X,0),"enemy movement cannot alter projectile heading")
-- Boomer's pitched straight-flight behavior does not acquire a trajectory.
local straight=Projectiles.launch(empty,Vector3.new(0,20,0),Vector3.new(0,0.2,-1).Unit,{},Definitions.Boomer.Weapon)
local before=straight.position
Projectiles.step(empty,straight,0.1)
check(not straight.trajectory and straight.position.Y>before.Y,"ground-tank projectiles retain their original straight pitched flight")
print(string.format("Two-stage trajectory suite passed: %d assertions",count))

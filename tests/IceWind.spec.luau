 -- This runs the real server with its new live IceWind preset and checks
 -- authoritative snapshots, actual renderer geometry and map redraw.
 local icyArena,icyFloor
 for _,p in created do if p.Name=="Arena" then icyArena=p elseif p.Name=="Floor" then icyFloor=p end end
 check(icyArena:GetAttribute("Weather")=="IceWind","server boots with icy/windy arena")
 check(icyFloor.Material==Enum.Material.Ice and icyFloor.Reflectance>0,"arena floor visibly matches ice physics")
 local initialB=snapshots[boomerId].position; local initialR=snapshots[rattlerId].position
 advance(120)
 local deltaB=snapshots[boomerId].position-initialB; local deltaR=snapshots[rattlerId].position-initialR
 check(deltaB.X>.3 and deltaB.X<4 and deltaR.X>.3 and deltaR.X<4,"wind gently moves both parked tanks")
 check(snapshots[boomerId].movementSpeedXZ>0 and snapshots[rattlerId].movementSpeedXZ>0,"drift is real resolved movement")
 local decorations=0
 for _,p in created do if p.Name=="IceStreak" or p.Name=="WindArrow" or p.Name=="WindArrowHead" then
  check(not p.CanQuery and not p.CanCollide,"ice/wind cosmetics do not block sensors, bullets or tanks"); decorations+=1
 end end
 check(decorations>=15,"icy arena contains visible frost and wind direction marker")
 print(string.format("Parked ice/wind drift after two seconds: Boomer %.2f, Rattler %.2f studs/sec",snapshots[boomerId].movementSpeedXZ,snapshots[rattlerId].movementSpeedXZ))
 -- Reset restores the tank state; the weather continues independently.
 reset.OnServerEvent:Fire(first); advance(6)
 local resetPosition=snapshots[boomerId].position
 advance(90)
 check(snapshots[boomerId].position.X>resetPosition.X+.2,"wind continues after battle reset")
 redraw.OnServerEvent:Fire(first,Vector2.new(120,160)); advance(6)
 check(icyFloor.Material==Enum.Material.Ice and icyArena:GetAttribute("MapWidth")==120,"map redraw preserves icy visuals")
 local redrawnStart=snapshots[boomerId].position
 advance(90)
 check(snapshots[boomerId].position.X>redrawnStart.X+.2,"map redraw preserves full-arena ice and wind")
 os.clock=savedClock; workspace.FindFirstChild=originalWorkspaceFind
end -- server fixture
print(string.format("Ice/wind production integration passed: %d assertions",count))

local Environment=require(Shared.Environment)
local Simulation=require(Shared.TankSimulation)
local Motion=require(Shared.VehicleMotion)
local Input=require(Shared.InputCommand)
local Components=require(Shared.VehicleComponents)
local Surface=require(Shared.SurfacePhysics)
local count=0
local function check(v,m) count+=1; assert(v,m) end
local cold=Environment.create(Vector2.new(230,230),"IceWind")
local ordinary=Environment.create(Vector2.new(230,230))
check(ordinary.weather=="Normal" and ordinary.wind==nil,"baseline preset stays available without environmental force")
check(Surface.sample(cold.physicsSurfaces,100,100)<.03,"ice covers arena rather than only visual patches")
local a=Simulation.new(Vector3.zero,"Boomer")
Motion.setVelocity(a,Environment.IceWind.direction*30)
Environment.applyForces(cold,a)
check(a.motionForce.Magnitude==0 and a.linearVelocity.Magnitude>29,"wind does not brake/clamp a fast downwind tank")
local b=Simulation.new(Vector3.zero,"Boomer")
Motion.setVelocity(b,Environment.IceWind.direction*(-30)); Environment.applyForces(cold,b)
check(math.abs(b.motionForce.Magnitude-cold.wind.maxForce)<1e-6,"upwind push is bounded rather than scaling without limit")
local c=Simulation.new(Vector3.zero,"Boomer")
Motion.force(c,Vector3.new(0,2,0)); Environment.applyForces(cold,c)
check(c.motionForce.Y==2 and c.motionForce.X>0,"wind composes with independent force producers")
local profile=Components.copy(Components.get("Boomer")); profile.Chassis.Mass=2; profile.Chassis.YawInertia*=2
local heavy=Simulation.new(Vector3.zero,"Boomer",1,profile)
for _=1,120 do Simulation.step(heavy,Input.neutral(),1/60,Vector2.new(2000,2000),cold) end
check(heavy.position.Magnitude<1e-6,"heavier stationary chassis can resist the same wind")
print(string.format("Ice/wind force contract passed: %d assertions",count))

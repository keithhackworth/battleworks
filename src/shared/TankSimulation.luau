local DamageEffects=require(script.Parent.DamageEffects)
-- Pure state math: no Instances, input devices, rendering, or physics ownership.
local Components = require(script.Parent.VehicleComponents)
local Drive = require(script.Parent.RattlerDrive)
local Motion = require(script.Parent.VehicleMotion)
local Surface = require(script.Parent.SurfacePhysics)
local Materials = require(script.Parent.TerrainMaterials)
local Heightfield = require(script.Parent.WorldHeightfield)
local Traversal = require(script.Parent.TerrainTraversal)
local Geometry = require(script.Parent.WorldObjectGeometry)
local Contacts = require(script.Parent.VehicleContacts)
local Config = require(script.Parent.TankConfig)
local Environment = require(script.Parent.Environment)
local TurretRecoil = require(script.Parent.TurretRecoil)
local Recoil = require(script.Parent.RattlerRecoil)
local Aim=require(script.Parent.TurretAim)
local Timing=require(script.Parent.WeaponTiming)
local Simulation = {}
function Simulation.new(position, tankType, seed, assembly)
    local c=if assembly then (if assembly.Resolved then assembly else Components.resolve(assembly)) else Components.get(tankType)
    local state=Components.bind({ recoilSeed = seed or c.Recoil.DefaultSeed, tankType = tankType or "Boomer", weaponId=c.Installed.Weapon, generation = 0, position = position, yaw = 0, turretYaw = 0, turretPitch = 0, speed = 0, health = c.Chassis.Health, maxHealth=c.Chassis.Health, cooldown = 0, bounce = 0, bounceVelocity = 0, movement = 0, bounceClock = 0, bodyPitch = 0, bodyRoll = 0 },c)
    Motion.configure(state,c.Chassis.Mass,c.Chassis.YawInertia)
    return state
end
function Simulation.forward(yaw, pitch)
	pitch = pitch or 0
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end
-- Player aim is the target orientation; actual turret pose also includes recoil.
function Simulation.turretAngles(state)
 local turret=Components.get(state).Turret
	return state.turretYaw+(state.aimRecoilYaw or 0),
		math.clamp((state.turretPitch or 0)+(state.aimRecoilPitch or 0),turret.MinPitch,turret.MaxPitch)
end
-- One authoritative flight decision shared by barrel pose and shell launch.
function Simulation.projectileFlight(state)
 return Recoil.airborne(state),state.groundHeight or state.groundPlaneY or 0
end
-- World-space barrel direction after chassis pitch/roll and actual turret aim.
function Simulation.shotPose(state)
 local yaw,pitch=Simulation.turretAngles(state)
 local relative=yaw-state.yaw
 return Aim.pivot(state),Aim.toWorld(state,Simulation.forward(relative,pitch)).Unit
end
local function suspension(state, dt)
 local tuning=Components.get(state).Mobility.Suspension
	local remaining = math.max(dt,0)
	while remaining > 0 do
		local step = math.min(remaining,1/120)
		local moving = if state.health > 0 then math.min(math.abs(state.speed)/tuning.Speed,1) else 0
		state.movement = (state.movement or 0)+(moving-(state.movement or 0))*(1-math.exp(-tuning.Response*step))
		state.bounceClock = (state.bounceClock or 0)+step*tuning.Frequency
		local target = math.sin(state.bounceClock)*tuning.Bob*state.movement
		state.bounceVelocity = (state.bounceVelocity or 0)+((target-(state.bounce or 0))*tuning.Spring-(state.bounceVelocity or 0)*tuning.Damping)*step
		state.bounce = (state.bounce or 0)+state.bounceVelocity*step
		remaining -= step
	end
	state.bodyPitch = (math.sin(state.bounceClock or 0)*tuning.Pitch*(state.movement or 0))+(state.flightPitch or 0)
	state.bodyRoll = (math.cos((state.bounceClock or 0)*tuning.RollFrequency)*tuning.Roll*(state.movement or 0))+(state.flightRoll or 0)
end
local function limitTerrainRise(state,terrain)
 if not terrain or not state.motionStepStart then return end
 local start,finish=state.motionStepStart,state.position
 local distance=math.sqrt((finish.X-start.X)^2+(finish.Z-start.Z)^2)
 if distance<=1e-6 then return end
 local a=Heightfield.sample(terrain.terrain,terrain.width,terrain.depth,start.X,start.Z)
 local b=Heightfield.sample(terrain.terrain,terrain.width,terrain.depth,finish.X,finish.Z)
 -- An airborne tank already above this ground may cross it. For a ground
 -- crossing, use a numerical tolerance only so slow motion cannot creep up a wall.
 if start.Y>b+Geometry.MaxStep or b-a<=math.min(Geometry.MaxStep,distance*Traversal.MaxGradient)+1e-6 then return end
 state.position=Vector3.new(start.X,finish.Y,start.Z)
 state.motionForwardTravel=state.motionForwardStart
 local velocity=Motion.ensure(state)
 Motion.setVelocity(state,Vector3.new(0,velocity.Y,0))
end
function Simulation.moveBody(state,command,dt,mapSize,environment,deferContacts)
 local c=Components.get(state)
 local ground,pitch,roll,_,_,material=0,0,0,nil,nil,nil
 if environment then ground,pitch,roll,_,_,material=Environment.pose(environment,state.position,state.yaw,c.Chassis) end
 local support=ground+(state.groundPlaneY or 0)
 Environment.applyForces(environment,state)
 local supported=state.position.Y<=support+0.001 and Motion.ensure(state).Y<=0 and (state.lift or 0)<=0.001
 Motion.beginStep(state,dt)
 -- A supported body's normal reaction absorbs sub-weight vertical forces.
 -- An actual launch impulse (positive velocity before this step) is not held.
 if supported and (state.motionExternalY or 0)<=state.motionMass*c.Recoil.Gravity then
  local v=Motion.ensure(state); Motion.setVelocity(state,Vector3.new(v.X,0,v.Z))
 end
 if state.position.Y>support+0.001 then state.lift=math.max(state.lift or 0,state.position.Y-support) end
 local airborne=Recoil.airborne(state)
 local speedScale,painted=1,nil
 if environment then
  local _,_,scale,_,profile=Environment.sample(environment,state.position.X,state.position.Z,state.position.Y+1.5)
  speedScale=scale;painted=profile
 end
 local base=painted or (if environment and environment.weather~="IceWind" and math.abs(pitch)+math.abs(roll)>.0001 then material else nil)
 local static,kinetic,resistance,passiveGrip,terrainScale=Surface.contact(if base then nil else environment and environment.physicsSurfaces,state.position,state.yaw,c.Chassis,c.Mobility.Kind,base)
 if environment and environment.materialTerrain then
  -- Apply the approved tracked base factor ONCE, after footprint blending.
  terrainScale*=if c.Mobility.Kind=="Tracked"then Materials.TrackedBaseSpeed else 1
 end
 speedScale*=terrainScale;state.terrainSpeedScale=speedScale
 if not airborne then
  state.terrainSpeedScale=Drive.ground(state,command,dt,speedScale,static,kinetic,resistance,passiveGrip,pitch,roll)
 end
 -- No traction, steering, coasting or ground damping is applied in the air.
 state.motionStepStart=state.position; state.motionYawStart=state.yaw
 state.motionForwardStart=state.motionForwardTravel or 0; state.motionYawTravelStart=state.motionYawTravel or 0
 Motion.integrateHorizontal(state,dt)
 local terrain=environment and environment.terrainSettings
 limitTerrainRise(state,terrain)
 if not deferContacts then
  Contacts.solve({Contacts.body("vehicle",state,c.Chassis)},Contacts.obstacles(environment,mapSize or Vector2.new(Config.ArenaLimit*2,Config.ArenaLimit*2)),dt)
  limitTerrainRise(state,terrain)
 end
 local x,z=state.position.X,state.position.Z
 local ground,pitch,roll,kind=0,0,0,"Grass"
 if environment then ground,pitch,roll,kind=Environment.pose(environment,state.position,state.yaw,c.Chassis) end
 ground+=(state.groundPlaneY or 0)
 state.position=Vector3.new(x,state.position.Y,z)
 state.groundPitch=pitch; state.groundRoll=roll; state.surface=kind
 if deferContacts then state.motionDeferredDt=dt else Recoil.step(state,dt,ground) end
 Motion.sync(state)
end
function Simulation.reconcileGround(state,environment)
 local terrain=environment and environment.terrainSettings
 if state.motionDeferredDt then limitTerrainRise(state,terrain) end
 local c=Components.get(state); local h,p,r,kind=0,0,0,"Grass"
 if environment then h,p,r,kind=Environment.pose(environment,state.position,state.yaw,c.Chassis) end
 if terrain then
  local _,gx,gz=Heightfield.sample(terrain.terrain,terrain.width,terrain.depth,state.position.X,state.position.Z,true)
  state.terrainFaceDegrees=math.deg(math.atan(math.sqrt(gx*gx+gz*gz)))
 end
 local dt=state.motionDeferredDt
 state.motionDeferredDt=nil
 if dt then
  state.groundPitch=p; state.groundRoll=r; state.surface=kind
  Recoil.step(state,dt,h+(state.groundPlaneY or 0))
  suspension(state,dt)
  state.bodyPitch+=p; state.bodyRoll+=r
 else
  state.bodyPitch=(state.bodyPitch or 0)+p-(state.groundPitch or 0)
  state.bodyRoll=(state.bodyRoll or 0)+r-(state.groundRoll or 0)
  state.groundPitch=p; state.groundRoll=r; state.surface=kind
  Recoil.step(state,0,h+(state.groundPlaneY or 0))
 end
 Motion.sync(state)
end
function Simulation.step(state, command, dt, mapSize, environment, deferContacts)
 local c=Components.get(state); local turret=c.Turret
	command=DamageEffects.input(state,command)
    if state.drivePerformance==0 or state.turretPerformance==0 then
        command=table.clone(command)
        if state.drivePerformance==0 then command.throttle=0; command.steer=0 end
        if state.turretPerformance==0 then command.aimMode="Rate"; command.turretX=0; command.turretY=0 end
    end
	state.cooldown = math.max(0, state.cooldown - dt)
	TurretRecoil.step(state,dt)
	if state.health<=0 then state.firing=false end
    Simulation.moveBody(state,command,dt,mapSize,environment,deferContacts)
    if not deferContacts then
     suspension(state,dt)
     state.bodyPitch+=state.groundPitch or 0; state.bodyRoll+=state.groundRoll or 0
    end
    if state.health<=0 then return end
 Aim.step(state,command,dt)
end
function Simulation.tryFire(state, command)
	if state.health <= 0 or not command.fire or state.cooldown > 0 or (state.weaponPerformance or 1)<=0 then return nil end
	state.cooldown = Timing.interval(Components.get(state).Weapon,state.weaponPerformance or 1)
	return Simulation.shotPose(state)
end
return Simulation

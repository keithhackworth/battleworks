-- Seeded, weapon-powered hops and world-space inertia. No animation-driven lift.
local Definitions = require(script.Parent.TankDefinitions)
local Config = Definitions.Rattler.Recoil
local TankConfig = require(script.Parent.TankConfig)
local Drive = require(script.Parent.RattlerDrive)
local Environment = require(script.Parent.Environment)
local Recoil = {}
local EPSILON = 1e-6
local function random(state)
	local seed=state.recoilSeed or Config.DefaultSeed
	if seed<=0 or seed>=2147483647 then seed=math.abs(seed)%2147483646+1 end
	state.recoilSeed=(seed*48271)%2147483647
	return state.recoilSeed/2147483647
end
local function range(a,b,t) return a+(b-a)*t end
function Recoil.airborne(state)
	return (state.lift or 0)>EPSILON or (state.verticalSpeed or 0)>EPSILON
end
function Recoil.active(state)
	return state.tankType=="Rattler" or Recoil.airborne(state)
end
local function initializeVelocity(state)
	if state.velocityX==nil then
		state.velocityX=-math.sin(state.yaw)*(state.speed or 0)
		state.velocityZ=-math.cos(state.yaw)*(state.speed or 0)
	end
end
local function launch(state,peak,ground)
	local height=math.max(0,state.position.Y-ground)
	if height>=peak then return end
	-- Replace, never accumulate, vertical impulse energy. Every hop has a
	-- ballistic apex below the safety ceiling even if shots arrive rapidly.
	state.verticalSpeed=math.sqrt(2*Config.Gravity*(peak-height))
	state.grounded=false
end
function Recoil.kick(state, _heat, direction)
	if state.tankType~="Rattler" or state.health<=0 then return end
	local intensity,timing,choice,rockPitch,rockRoll,shove=random(state),random(state),random(state),random(state),random(state),random(state)
	initializeVelocity(state)
	direction=direction or Vector3.new(-math.sin(state.turretYaw),0,-math.cos(state.turretYaw))
	local magnitude=math.sqrt(direction.X^2+direction.Z^2)
	if magnitude>EPSILON then
		local impulse=range(Config.HorizontalImpulseMin,Config.HorizontalImpulseMax,shove)
		state.velocityX-=direction.X/magnitude*impulse
		state.velocityZ-=direction.Z/magnitude*impulse
		local speed=math.sqrt(state.velocityX^2+state.velocityZ^2)
		if speed>Config.MaxHorizontalSpeed then
			state.velocityX*=Config.MaxHorizontalSpeed/speed; state.velocityZ*=Config.MaxHorizontalSpeed/speed
		end
	end
	state.flightShotSerial=(state.flightShotSerial or 0)+1
	local oldPitch,oldRoll=state.flightPitch or 0,state.flightRoll or 0
	state.flightPitch=math.clamp(oldPitch+(rockPitch*2-1)*Config.PitchJolt,-Config.MaxRock,Config.MaxRock)
	-- Each bullet throws the hull firmly to one side, rather than accumulating
	-- tiny offsets that often cancel out. Keep seeded randomness, but prevent
	-- long same-side streaks so it visibly wrestles left and right.
	local sign=if rockRoll<0.5 then -1 else 1
	if sign==state.lastRollSign and (state.rollStreak or 0)>=2 then sign=-sign end
	state.rollStreak=if sign==state.lastRollSign then (state.rollStreak or 0)+1 else 1
	state.lastRollSign=sign
	state.flightRoll=sign*range(Config.RollJoltMin,Config.RollJolt,math.abs(rockRoll*2-1))
	-- Publish the physical jolt on the release tick, not one simulation tick later.
	state.bodyPitch=(state.bodyPitch or 0)+state.flightPitch-oldPitch
	state.bodyRoll=(state.bodyRoll or 0)+state.flightRoll-oldRoll
	state.bounceVelocity=math.clamp((state.bounceVelocity or 0)+range(-2.5,3.5,intensity),-8,8)
	local ground=state.groundHeight or (state.groundPlaneY or 0)
	if not Recoil.airborne(state) then
		launch(state,range(Config.InitialHopMin,Config.InitialHopMax,intensity),ground)
		state.recoilWait=range(Config.MinKickGap,Config.MaxKickGap,timing)
		state.dropThrough=false
	elseif not state.dropThrough and not state.pendingRecoil and (state.recoilWait or 0)<=EPSILON and (state.verticalSpeed or 0)<=0 then
		if choice<Config.NearGroundChance then
			state.dropThrough=true -- let an occasional full thud happen during sustained fire
		else
			state.pendingRecoil={delay=range(Config.MinKickDelay,Config.MaxKickDelay,timing),peak=range(Config.HopMin,Config.HopMax,intensity)}
		end
		state.recoilWait=range(Config.MinKickGap,Config.MaxKickGap,timing)
	end
end
function Recoil.step(state,dt,ground)
	ground=ground or state.groundHeight or (state.groundPlaneY or 0)
	state.recoilWait=math.max(0,(state.recoilWait or 0)-dt)
	state.flightPitch=(state.flightPitch or 0)*math.exp(-Config.RockRecovery*dt)
	state.flightRoll=(state.flightRoll or 0)*math.exp(-Config.RockRecovery*dt)
	if not state.firing or state.health<=0 then state.pendingRecoil=nil end
	if state.pendingRecoil then
		state.pendingRecoil.delay-=dt
		if state.pendingRecoil.delay<=0 then
			if (state.verticalSpeed or 0)<=0 then launch(state,state.pendingRecoil.peak,ground) end
			state.pendingRecoil=nil
		end
	end
	local height=state.position.Y
	local velocity=state.verticalSpeed or 0
	local wasAirborne=Recoil.airborne(state)
	if not wasAirborne then
		height=ground; velocity=0
	else
		local available=math.max(0,Config.MaxLift-math.max(0,height-ground))
		if velocity>0 then velocity=math.min(velocity,math.sqrt(2*Config.Gravity*available)) end
		local nextHeight=height+velocity*dt-0.5*Config.Gravity*dt*dt
		velocity=math.max(-Config.MaxFallSpeed,velocity-Config.Gravity*dt)
		if nextHeight<=ground then
			state.landingSerial=(state.landingSerial or 0)+1
			state.landingImpact=math.abs(velocity)
			state.bounceVelocity=(state.bounceVelocity or 0)-math.min(math.abs(velocity)*Config.LandingCompression,Config.MaxLandingImpulse)
			height=ground; velocity=0; state.dropThrough=false; state.pendingRecoil=nil
		else
			height=math.min(nextHeight,ground+Config.MaxLift)
			if nextHeight>=ground+Config.MaxLift then velocity=math.min(0,velocity) end
		end
	end
	state.lift=math.max(0,height-ground); state.verticalSpeed=velocity
	state.grounded=state.lift<=EPSILON and velocity<=0
	state.groundHeight=ground
	state.position=Vector3.new(state.position.X,height,state.position.Z)
end
function Recoil.move(state,command,dt,mapSize,environment)
	initializeVelocity(state)
	local airborne=Recoil.airborne(state)
	if not airborne and state.health<=0 then
		local friction=math.exp(-Config.GroundFriction*dt)
		state.velocityX*=friction; state.velocityZ*=friction
	elseif not airborne then
		local surface=if environment then select(3,Environment.sample(environment,state.position.X,state.position.Z)) else 1
		local lateral=(state.velocityX*math.cos(state.yaw)-state.velocityZ*math.sin(state.yaw))*math.exp(-Config.GroundFriction*dt)
		Drive.step(state,command,dt,surface)
		state.velocityX=-math.sin(state.yaw)*state.speed+math.cos(state.yaw)*lateral
		state.velocityZ=-math.cos(state.yaw)*state.speed-math.sin(state.yaw)*lateral
	end
	-- In the air, no player yaw, drive acceleration, braking or friction.
	local desiredX=state.position.X+state.velocityX*dt
	local desiredZ=state.position.Z+state.velocityZ*dt
	local limitX=(if mapSize then mapSize.X/2 else TankConfig.ArenaLimit)-TankConfig.Radius
	local limitZ=(if mapSize then mapSize.Y/2 else TankConfig.ArenaLimit)-TankConfig.Radius
	local x,z=math.clamp(desiredX,-limitX,limitX),math.clamp(desiredZ,-limitZ,limitZ)
	if x~=desiredX then state.velocityX=0 end
	if z~=desiredZ then state.velocityZ=0 end
	if environment and Environment.blocked(environment,x,z,TankConfig.Radius) then
		x=state.position.X; z=state.position.Z; state.velocityX=0; state.velocityZ=0
	end
	local ground,pitch,roll,kind=0,0,0,"Grass"
	if environment then ground,pitch,roll,kind=Environment.pose(environment,Vector3.new(x,0,z),state.yaw) end
	ground+=(state.groundPlaneY or 0)
	state.position=Vector3.new(x,state.position.Y,z)
	state.groundPitch=pitch; state.groundRoll=roll; state.surface=kind
	Recoil.step(state,dt,ground)
	state.speed=-math.sin(state.yaw)*state.velocityX-math.cos(state.yaw)*state.velocityZ
end
function Recoil.resolveBlocked(state,previous,environment)
	state.velocityX=0; state.velocityZ=0; state.speed=0
	local ground,pitch,roll,kind=0,0,0,"Grass"
	if environment then ground,pitch,roll,kind=Environment.pose(environment,previous,state.yaw) end
	ground+=(state.groundPlaneY or 0)
	state.bodyPitch=(state.bodyPitch or 0)+pitch-(state.groundPitch or 0)
	state.bodyRoll=(state.bodyRoll or 0)+roll-(state.groundRoll or 0)
	state.groundPitch=pitch; state.groundRoll=roll; state.surface=kind
	state.position=Vector3.new(previous.X,state.position.Y,previous.Z)
	Recoil.step(state,0,ground)
end
return Recoil

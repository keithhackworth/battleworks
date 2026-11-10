-- Seeded, weapon-powered hops and world-space inertia. No animation-driven lift.
local Components = require(script.Parent.VehicleComponents)
local Motion = require(script.Parent.VehicleMotion)
local Recoil = {}
local EPSILON = 1e-6
local function random(state)
 local Config=Components.get(state).Recoil
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
	local c=Components.get(state)
 return c.Mobility.Motion=="Inertial" or c.Recoil.Kind=="Jackhammer" or Recoil.airborne(state)
end
local function launch(state,peak,ground)
 local Config=Components.get(state).Recoil
	local height=math.max(0,state.position.Y-ground)
	if height>=peak then return end
	-- Replace, never accumulate, vertical impulse energy. Every hop has a
	-- ballistic apex below the safety ceiling even if shots arrive rapidly.
	local v=Motion.ensure(state)
 Motion.setVelocity(state,Vector3.new(v.X,math.sqrt(2*Config.Gravity*(peak-height)),v.Z))
	state.grounded=false
end
function Recoil.kick(state, _heat, direction)
 local Config=Components.get(state).Recoil
	if Components.get(state).Recoil.Kind~="Jackhammer" or state.health<=0 then return end
	local intensity,timing,choice,rockPitch,rockRoll,shove=random(state),random(state),random(state),random(state),random(state),random(state)
	Motion.ensure(state)
	direction=direction or Vector3.new(-math.sin(state.turretYaw),0,-math.cos(state.turretYaw))
	local magnitude=math.sqrt(direction.X^2+direction.Z^2)
	if magnitude>EPSILON then
		local impulse=range(Config.HorizontalImpulseMin,Config.HorizontalImpulseMax,shove)
		local v=Motion.ensure(state)
        local dx,dz=-direction.X/magnitude*impulse/state.motionMass,-direction.Z/magnitude*impulse/state.motionMass
        local before=math.sqrt(v.X*v.X+v.Z*v.Z)
        local after=math.sqrt((v.X+dx)^2+(v.Z+dz)^2)
        -- Limit only newly contributed recoil, never erase existing momentum.
        if after>Config.MaxHorizontalSpeed and after>before then
            local cap=math.max(before,Config.MaxHorizontalSpeed)
            local low,high=0,1
            for _=1,20 do local t=(low+high)/2; if (v.X+dx*t)^2+(v.Z+dz*t)^2>cap^2 then high=t else low=t end end
            dx*=low; dz*=low
        end
        Motion.impulse(state,Vector3.new(dx,0,dz)*state.motionMass)
	end
	state.flightShotSerial=(state.flightShotSerial or 0)+1
	local oldPitch,oldRoll=state.flightPitch or 0,state.flightRoll or 0
	state.flightPitch=math.clamp(oldPitch+(rockPitch*2-1)*Config.PitchJolt,-Config.MaxRock,Config.MaxRock)
	-- Each bullet throws the hull firmly to one side, rather than accumulating
	-- tiny offsets that often cancel out. Keep seeded randomness, but prevent
	-- long same-side streaks so it visibly wrestles left and right.
	local sign=if rockRoll<0.5 then -1 else 1
	if sign==state.lastRollSign and (state.rollStreak or 0)>=Config.MaxRollStreak then sign=-sign end
	state.rollStreak=if sign==state.lastRollSign then (state.rollStreak or 0)+1 else 1
	state.lastRollSign=sign
	state.flightRoll=sign*range(Config.RollJoltMin,Config.RollJolt,math.abs(rockRoll*2-1))
	-- Publish the physical jolt on the release tick, not one simulation tick later.
	state.bodyPitch=(state.bodyPitch or 0)+state.flightPitch-oldPitch
	state.bodyRoll=(state.bodyRoll or 0)+state.flightRoll-oldRoll
	state.bounceVelocity=math.clamp((state.bounceVelocity or 0)+range(Config.BounceJoltMin,Config.BounceJoltMax,intensity),-Config.MaxBounceVelocity,Config.MaxBounceVelocity)
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
 local Config=Components.get(state).Recoil
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
	local velocity=Motion.ensure(state).Y
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
	state.lift=math.max(0,height-ground)
 local v=Motion.ensure(state); Motion.setVelocity(state,Vector3.new(v.X,velocity,v.Z))
	state.grounded=state.lift<=EPSILON and velocity<=0
	state.groundHeight=ground
	state.position=Vector3.new(state.position.X,height,state.position.Z)
end
-- Retained compatibility entry; there is only one tank movement coordinator.
function Recoil.move(state,command,dt,mapSize,environment)
 return require(script.Parent.TankSimulation).moveBody(state,command,dt,mapSize,environment)
end
return Recoil

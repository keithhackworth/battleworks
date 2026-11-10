-- Shared control requests, resolved against contact traction. Vehicle identity
-- never selects propulsion/mobility. Motion alone writes physical velocity.
local Components=require(script.Parent.VehicleComponents)
local Motion=require(script.Parent.VehicleMotion)
local Surface=require(script.Parent.SurfacePhysics)
local Drive={}
function Drive.ground(state,command,dt,surfaceScale,static,kinetic,resistance)
 local c=Components.get(state); local p,m=c.Drivetrain,c.Mobility
 local v=Motion.ensure(state); local omega=state.angularVelocity.Y
 local fx,fz=-math.sin(state.yaw),-math.cos(state.yaw)
 local rx,rz=math.cos(state.yaw),-math.sin(state.yaw)
 local forward=v.X*fx+v.Z*fz; local lateral=v.X*rx+v.Z*rz
 local target=command.throttle*(if command.throttle>=0 then p.Speed else p.ReverseSpeed)*surfaceScale*(state.drivePerformance or 1)
 local acceleration=p.Acceleration or 2880; local braking=p.Braking or 2880; local coast=(p.CoastDrag or 1440)*(resistance or 1)
 local rated=(if command.throttle>=0 then p.Speed else p.ReverseSpeed)*surfaceScale*(state.drivePerformance or 1)
 local rate=if command.throttle==0 then coast elseif forward*target<0 then braking elseif math.abs(forward)>math.abs(target) then (if math.abs(forward)>rated and math.abs(command.throttle)>=0.999 then coast else braking) else acceleration
 -- Over-speed motion coasts; propulsion never snaps it down to its rating.
 local desired=forward+math.clamp(target-forward,-rate*dt,rate*dt)
 local wantedOmega=0
 if m.Kind=="Wheeled" then
  local steering=(if c.Capabilities.Steer then command.steer else 0)*m.MaxSteer
  state.steeringAngle=(state.steeringAngle or 0)+(steering-(state.steeringAngle or 0))*(1-math.exp(-m.SteeringResponse*dt))
  wantedOmega=math.clamp(desired/m.Wheelbase*math.tan(state.steeringAngle),-m.MaxYawRate,m.MaxYawRate)
 else
  if c.Capabilities.Steer and (c.Capabilities.Pivot or math.abs(desired)>1e-6) then wantedOmega=command.steer*m.TurnSpeed*(state.drivePerformance or 1) end
 end
 if state.health<=0 then desired=forward*math.exp(-c.Recoil.GroundFriction*dt); wantedOmega=0 end
 local dw=math.clamp(wantedOmega-omega,-m.YawAcceleration*dt,m.YawAcceleration*dt)
 local nextYaw=state.yaw+(omega+dw)*dt
 local side=0 -- contact seeks to remove lateral slip, within shared traction budget
 if state.motionWasResting and command.throttle==0 and command.steer==0 then desired=0 end
 local vx=-math.sin(nextYaw)*desired+math.cos(nextYaw)*side
 local vz=-math.cos(nextYaw)*desired-math.sin(nextYaw)*side
 local dx,dz=vx-v.X,vz-v.Z
 local long=(dx*fx+dz*fz)/m.LongitudinalGrip
 local lat=(dx*rx+dz*rz)/m.LateralGrip
 local spin=dw*state.yawInertia/(state.motionMass*c.Chassis.Radius)
 local demand=math.sqrt(long*long+lat*lat+spin*spin)
 local normalAcceleration=math.max(0,c.Recoil.Gravity-(state.motionExternalY or 0)/state.motionMass)
 state.motionBrakeAcceleration=math.min(braking,(kinetic or Surface.Profiles.Normal.kineticFriction)*normalAcceleration*m.LongitudinalGrip)
 local staticLimit=(static or Surface.Profiles.Normal.staticFriction)*normalAcceleration*dt
 local slipping=(state.motionSlipping and not state.motionWasResting) or demand>staticLimit+1e-8
 local limit=if slipping then (kinetic or Surface.Profiles.Normal.kineticFriction)*normalAcceleration*dt else staticLimit
 local scale=if demand>0 then math.min(1,limit/demand) else 1
 state.motionSlipping=slipping and demand>1e-6
 state.motionTraction=scale
 Motion.setVelocity(state,Vector3.new(v.X+dx*scale,v.Y,v.Z+dz*scale))
 Motion.setYawVelocity(state,omega+dw*scale)
end
-- Compatibility entry for direct steering tests/older callers. Production
-- Simulation uses ground() then advances the common pose exactly once.
function Drive.step(state,command,dt,surfaceScale)
 Motion.beginStep(state,dt); Drive.ground(state,command,dt,surfaceScale or 1)
 Motion.advanceYaw(state,dt)
end
return Drive

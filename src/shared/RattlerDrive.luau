-- Shared propulsion/steering solver; historical module name retained for callers.
local Components=require(script.Parent.VehicleComponents)
local Drive={}
function Drive.step(state,command,dt,surfaceScale)
 local c=Components.get(state); local propulsion,mobility=c.Drivetrain,c.Mobility
 local target=command.throttle*(if command.throttle>=0 then propulsion.Speed else propulsion.ReverseSpeed)*surfaceScale*(state.drivePerformance or 1)
 if propulsion.Response=="Accelerated" then
  local current=state.speed or 0
  local rate=if command.throttle==0 then propulsion.CoastDrag elseif current*target<0 or math.abs(target)<math.abs(current) then propulsion.Braking else propulsion.Acceleration
  state.speed=current+math.clamp(target-current,-rate*dt,rate*dt)
 else state.speed=target end
 if mobility.Kind=="Wheeled" then
  local desired=(if c.Capabilities.Steer then command.steer else 0)*mobility.MaxSteer
  state.steeringAngle=(state.steeringAngle or 0)+(desired-(state.steeringAngle or 0))*(1-math.exp(-mobility.SteeringResponse*dt))
  local yawRate=state.speed/mobility.Wheelbase*math.tan(state.steeringAngle)
  state.yaw+=math.clamp(yawRate,-mobility.MaxYawRate,mobility.MaxYawRate)*dt
 else
  -- Differential intent: full opposing tread input pivots when supported;
  -- while moving, the same differential yaws without changing legacy speed.
  local steer=if c.Capabilities.Steer and (c.Capabilities.Pivot or math.abs(state.speed)>1e-6) then command.steer else 0
  local left,right=command.throttle-steer,command.throttle+steer
  state.yaw+=(right-left)*0.5*mobility.TurnSpeed*(state.drivePerformance or 1)*dt
 end
end
return Drive

-- Rattler is a wheeled car: acceleration, front steering and signed reverse yaw.
local Config = require(script.Parent.TankDefinitions).Rattler.Drive
local Drive = {}
function Drive.step(state, command, dt, surfaceScale)
	local target = command.throttle*(if command.throttle >= 0 then Config.Speed else Config.ReverseSpeed)*surfaceScale*(state.drivePerformance or 1)
	local current = state.speed or 0
	local rate = if command.throttle == 0 then Config.CoastDrag
		elseif current*target < 0 or math.abs(target)<math.abs(current) then Config.Braking else Config.Acceleration
	state.speed = current+math.clamp(target-current,-rate*dt,rate*dt)
	local desired = command.steer*Config.MaxSteer
	state.steeringAngle = (state.steeringAngle or 0)+(desired-(state.steeringAngle or 0))*(1-math.exp(-10*dt))
	-- No stationary pivot turn. Reversing naturally reverses the yaw response.
	local yawRate = state.speed/Config.Wheelbase*math.tan(state.steeringAngle)
	state.yaw += math.clamp(yawRate,-Config.MaxYawRate,Config.MaxYawRate)*dt
end
return Drive

-- BW intent -> existing tank controls. Nothing here changes poses or physics.
local Command=require(script.Parent.InputCommand)
local Components=require(script.Parent.VehicleComponents)
local Simulation=require(script.Parent.TankSimulation)
local Limits=require(script.Parent.BWConfig)
local Adapter={}
function Adapter.heading(yaw) local heading=(-math.deg(yaw))%360; return if heading>=360 then 0 else heading end
function Adapter.angle(state,turret)
	if not turret then return state.yaw end
	local _,direction=Simulation.shotPose(state)
	return math.atan2(-direction.X,-direction.Z)
end
function Adapter.delta(previous,current) return math.atan2(math.sin(current-previous),math.cos(current-previous)) end
function Adapter.rotation(instruction,yaw)
	local left=instruction.op:find("left",1,true)~=nil
	local sign=if left then 1 else -1
	local degrees=instruction.value
	if instruction.absolute then
		local current=Adapter.heading(yaw)
		degrees=if left then (current-degrees)%360 else (degrees-current)%360
		local tolerance=math.deg(Limits.AngleTolerance)
		if degrees<=tolerance or degrees>=360-tolerance then degrees=0 end
	end
	return sign,math.rad(degrees)
end
function Adapter.move(state,sign,remaining,dt)
	local command=Command.neutral()
	if remaining<=Limits.DistanceTolerance then return command end
	local vehicle=Components.get(state)
	local maxSpeed=if sign>0 then vehicle.Drivetrain.Speed else vehicle.Drivetrain.ReverseSpeed
	local speed=math.min(maxSpeed,remaining*4,remaining/math.max(dt,1e-6))
	if vehicle.Drivetrain.Response=="Accelerated" then
		local drive=vehicle.Drivetrain
		maxSpeed=if sign>0 then drive.Speed else drive.ReverseSpeed
		speed=math.min(maxSpeed,remaining*3,math.sqrt(2*drive.Braking*remaining)*0.65)
	end
	command.throttle=sign*math.clamp(speed/maxSpeed,0,1)
	return command
end
function Adapter.turn(state,sign,remaining,turret,dt)
	local command=Command.neutral()
    local vehicle=Components.get(state)
	if remaining<=Limits.AngleTolerance then return command end
	if turret then
		command.turretX=-sign*math.min(1,remaining/(vehicle.Turret.TraverseSpeed*math.max(dt,1e-6)))
	elseif not vehicle.Capabilities.Pivot then
		local drive=vehicle.Drivetrain
		local speed=math.min(12,math.max(0.6,remaining*10))
		command.throttle=speed/drive.Speed
		local reverse=if state.speed < -0.1 then -1 else 1
		command.steer=sign*reverse
	else
		command.steer=sign*math.min(1,remaining/(vehicle.Mobility.TurnSpeed*math.max(dt,1e-6)))
	end
	return command
end
return Adapter

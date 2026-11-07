-- Distance-parametrized, non-homing paths. Heading is frozen at launch.
local Trajectory = {}
local EPSILON = 1e-7
local function heading(direction)
	local flat=Vector3.new(direction.X,0,direction.Z)
	return if flat.Magnitude>EPSILON then flat.Unit else Vector3.new(0,0,-1)
end
local function radius(settings)
	assert(settings.DescentAngle>0 and settings.DescentAngle<math.pi/2 and settings.LevelingDistance>0,"Invalid descent/leveling tuning")
	return settings.LevelingDistance/settings.DescentAngle
end
-- Near the level plane, use the shallower portion of the leveling curve so
-- the physical seven-stud barrel cannot place its tip below the target plane.
function Trajectory.launchDirection(pivot,direction,levelHeight,muzzleOffset,settings)
	local flat=heading(direction)
	local available=pivot.Y-levelHeight
	if available<=EPSILON then return flat end
	local r=radius(settings)
	local full=settings.DescentAngle
	if muzzleOffset*math.sin(full)+r*(1-math.cos(full))<=available then
		return flat*math.cos(full)+Vector3.new(0,-math.sin(full),0)
	end
	local low,high=0,full
	for _=1,32 do
		local angle=(low+high)/2
		if muzzleOffset*math.sin(angle)+r*(1-math.cos(angle))>available then high=angle else low=angle end
	end
	return flat*math.cos(low)+Vector3.new(0,-math.sin(low),0)
end
function Trajectory.new(origin,direction,levelHeight,settings)
	local flat=heading(direction)
	local angle=math.atan2(math.max(0,-direction.Y),Vector3.new(direction.X,0,direction.Z).Magnitude)
	if origin.Y<=levelHeight+EPSILON or angle<=EPSILON then
		return {origin=origin,heading=flat,angle=0,straight=0,arc=0,levelHeight=origin.Y}
	end
	local r=radius(settings)
	local available=origin.Y-levelHeight
	-- Also handle direct callers starting midway through a leveling curve.
	angle=math.min(angle,math.acos(math.clamp(1-available/r,-1,1)))
	local drop=r*(1-math.cos(angle))
	local straight=math.max(0,(available-drop)/math.sin(angle))
	return {origin=origin,heading=flat,angle=angle,radius=r,straight=straight,arc=r*angle,levelHeight=levelHeight}
end
function Trajectory.sample(path,distance)
	local angle=path.angle
	if angle==0 then return path.origin+path.heading*distance,path.heading end
	if distance<path.straight then
		local direction=path.heading*math.cos(angle)+Vector3.new(0,-math.sin(angle),0)
		return path.origin+direction*distance,direction
	end
	local horizontal=path.straight*math.cos(angle)
	local arcDistance=distance-path.straight
	if arcDistance<path.arc then
		local current=angle-arcDistance/path.radius
		horizontal+=path.radius*(math.sin(angle)-math.sin(current))
		return Vector3.new(path.origin.X,path.levelHeight+path.radius*(1-math.cos(current)),path.origin.Z)+path.heading*horizontal,
			path.heading*math.cos(current)+Vector3.new(0,-math.sin(current),0)
	end
	horizontal+=path.radius*math.sin(angle)+arcDistance-path.arc
	return Vector3.new(path.origin.X,path.levelHeight,path.origin.Z)+path.heading*horizontal,path.heading
end
function Trajectory.segmentLength(path,distance,budget)
	if path.angle==0 then return budget end
	if distance<path.straight-EPSILON then return math.min(budget,path.straight-distance) end
	local finish=path.straight+path.arc
	if distance<finish-EPSILON then return math.min(budget,0.5,finish-distance) end
	return budget
end
return Trajectory

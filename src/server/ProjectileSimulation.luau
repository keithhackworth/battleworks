-- Server-owned swept projectiles with optional modular trajectories. No client hit claims.
local Config = require(game.ReplicatedStorage.Shared.TankConfig)
local Trajectory = require(game.ReplicatedStorage.Shared.ProjectileTrajectory)
local Projectiles = {}
function Projectiles.new(origin, direction, exclusions, tuning, groundY)
	tuning = tuning or Config
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = exclusions
	ray.RespectCanCollide = false; ray.IgnoreWater = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclusions
	overlap.RespectCanCollide = false
	local shell = { position = origin, direction = direction.Unit, remaining = tuning.Range, speed = tuning.ShellSpeed, radius = tuning.ShellRadius, damage = tuning.Damage, muzzleOffset = tuning.MuzzleOffset,
		ray = ray, overlap = overlap, done = false }
	if tuning.Trajectory then
		shell.trajectory=Trajectory.new(origin,direction,(groundY or 0)+Config.MuzzleHeight,tuning.Trajectory)
		shell.pathDistance=0
		shell.position,shell.direction=Trajectory.sample(shell.trajectory,0)
	end
	return shell
end
-- Exact point-to-solid distance for the primitive cover used by the arena.
function Projectiles.overlaps(part, point, radius)
	local q=part.CFrame:PointToObjectSpace(point)
	local half=part.Size/2
	if part.Shape==Enum.PartType.Ball then
		local ax,ay,az=half.X^2,half.Y^2,half.Z^2
		if q.X^2/ax+q.Y^2/ay+q.Z^2/az<=1 then return true end
		local function scaled(lambda)
			return ax*q.X^2/(lambda+ax)^2+ay*q.Y^2/(lambda+ay)^2+az*q.Z^2/(lambda+az)^2
		end
		local low,high=0,math.max(ax,ay,az)
		while scaled(high)>1 do high*=2 end
		for _=1,32 do local middle=(low+high)/2; if scaled(middle)>1 then low=middle else high=middle end end
		local closest=Vector3.new(ax*q.X/(high+ax),ay*q.Y/(high+ay),az*q.Z/(high+az))
		return (q-closest).Magnitude<=radius
	elseif part.Shape==Enum.PartType.Cylinder and math.abs(half.Y-half.Z)<1e-6 then
		local length=math.sqrt(q.Y^2+q.Z^2)
		local scale=if length>half.Y then half.Y/length else 1
		local closest=Vector3.new(math.clamp(q.X,-half.X,half.X),q.Y*scale,q.Z*scale)
		return (q-closest).Magnitude<=radius
	end
	local closest=Vector3.new(math.clamp(q.X,-half.X,half.X),math.clamp(q.Y,-half.Y,half.Y),math.clamp(q.Z,-half.Z,half.Z))
	return (q-closest).Magnitude<=radius
end
function Projectiles.step(world, shell, dt)
	if shell.done then return nil end
	-- Spherecast alone ignores initial overlaps. Check actual sphere-vs-solid
	-- overlap too, including a moving tank entering a shell between steps.
	-- Curved rock/log/trunk cover uses its solid shape rather than its bounding box.
	local radius = shell.radius or Config.ShellRadius
	for _, p in world:GetPartBoundsInRadius(shell.position, radius, shell.overlap) do
		if Projectiles.overlaps(p,shell.position,radius) then
			shell.done = true
			return { Instance = p, Position = shell.position, Distance = 0 }
		end
	end
	local travel = math.min((shell.speed or Config.ShellSpeed) * math.max(dt,0), shell.remaining)
	if travel <= 0 then return nil end
	if shell.trajectory then
		local left=travel
		while left>1e-7 do
			local distance=Trajectory.segmentLength(shell.trajectory,shell.pathDistance,left)
			local endpoint,direction=Trajectory.sample(shell.trajectory,shell.pathDistance+distance)
			local delta=endpoint-shell.position
			local hit=world:Spherecast(shell.position,radius,delta,shell.ray)
			if hit then
				local fraction=math.clamp(hit.Distance/delta.Magnitude,0,1)
				shell.position+=delta*fraction
				shell.pathDistance+=distance*fraction
				shell.remaining-=distance*fraction
				local _,tangent=Trajectory.sample(shell.trajectory,shell.pathDistance)
				shell.direction=tangent; shell.done=true
				return hit
			end
			shell.position=endpoint; shell.direction=direction
			shell.pathDistance+=distance; shell.remaining-=distance; left-=distance
		end
		if shell.remaining<=1e-6 then shell.done=true end
		return nil
	end
	local hit = world:Spherecast(shell.position, radius, shell.direction * travel, shell.ray)
	if hit then
		shell.position += shell.direction * hit.Distance
		shell.done = true
		return hit
	end
	shell.position += shell.direction * travel
	shell.remaining -= travel
	if shell.remaining <= 1e-6 then shell.done = true end
	return nil
end
function Projectiles.launch(world, pivot, direction, exclusions, tuning, groundY)
	local shell = Projectiles.new(pivot,direction,exclusions,tuning,groundY)
	-- The barrel itself is straight: sweep it before enabling free-flight curves.
	shell.trajectory=nil; shell.direction=direction.Unit
	-- Sweep the barrel length once for obstruction safety, then launch at its
	-- tip. Keep total range measured from pivot, as before this visual change.
	local blocked = Projectiles.step(world,shell,shell.muzzleOffset / shell.speed)
	if tuning and tuning.Trajectory and not shell.done then
		shell.trajectory=Trajectory.new(shell.position,direction,(groundY or 0)+Config.MuzzleHeight,tuning.Trajectory)
		shell.pathDistance=0
		shell.position,shell.direction=Trajectory.sample(shell.trajectory,0)
	end
	return shell, blocked
end
return Projectiles

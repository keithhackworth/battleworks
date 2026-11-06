-- Server-owned, fixed-step straight-flight artillery shells. No client hit claims.
local Config = require(game.ReplicatedStorage.Shared.TankConfig)
local Projectiles = {}
function Projectiles.new(origin, direction, exclusions)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = exclusions
	ray.RespectCanCollide = false; ray.IgnoreWater = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = exclusions
	overlap.RespectCanCollide = false
	return { position = origin, direction = direction.Unit, remaining = Config.Range,
		ray = ray, overlap = overlap, done = false }
end
function Projectiles.step(world, shell, dt)
	if shell.done then return nil end
	-- Spherecast alone ignores initial overlaps. Check actual sphere-vs-box
	-- overlap too, including a moving tank entering a shell between steps.
	local radius = Config.ShellRadius
	for _, p in world:GetPartBoundsInRadius(shell.position, radius, shell.overlap) do
		local q = p.CFrame:PointToObjectSpace(shell.position)
		local half = p.Size / 2
		local closest = Vector3.new(math.clamp(q.X,-half.X,half.X), math.clamp(q.Y,-half.Y,half.Y), math.clamp(q.Z,-half.Z,half.Z))
		if (q - closest).Magnitude <= radius then
			shell.done = true
			return { Instance = p, Position = shell.position, Distance = 0 }
		end
	end
	local travel = math.min(Config.ShellSpeed * math.max(dt,0), shell.remaining)
	if travel <= 0 then return nil end
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
function Projectiles.launch(world, pivot, direction, exclusions)
	local shell = Projectiles.new(pivot,direction,exclusions)
	-- Sweep the barrel length once for obstruction safety, then launch at its
	-- tip. Keep total range measured from pivot, as before this visual change.
	local blocked = Projectiles.step(world,shell,Config.MuzzleOffset / Config.ShellSpeed)
	return shell, blocked
end
return Projectiles

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.TankConfig)
local Command = require(Shared.InputCommand)
local Simulation = require(Shared.TankSimulation)
Players.CharacterAutoLoads = false
local network = Instance.new("Folder")
network.Name = "TankNetwork"
local function remote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name; event.Parent = network
	return event
end
local input, snapshot, shot = remote("Input"), remote("Snapshot"), remote("Shot")
network.Parent = ReplicatedStorage
local tanks, targets = {}, {}
local arena = Instance.new("Folder")
arena.Name = "Arena"; arena.Parent = workspace
local function part(name, size, position, color)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.Size = size; p.Position = position; p.Color = color; p.Parent = arena
	return p
end
for _, data in ipairs({ {Vector3.new(0, 3, -118), Vector3.new(240, 6, 4)}, {Vector3.new(0, 3, 118), Vector3.new(240, 6, 4)}, {Vector3.new(-118, 3, 0), Vector3.new(4, 6, 240)}, {Vector3.new(118, 3, 0), Vector3.new(4, 6, 240)} }) do
	part("Boundary", data[2], data[1], Color3.fromRGB(57, 66, 73))
end
for i = 1, 5 do
	local p = part("Target", Vector3.new(7, 7, 5), Vector3.new((i - 3) * 18, 3.5, -65), Color3.fromRGB(210, 102, 60))
	targets[p] = { health = Config.Health, resetAt = 0 }
	p:SetAttribute("Health", Config.Health)
end
local spawnCount = 0
local function addPlayer(player)
	if tanks[player.UserId] then return end
	spawnCount += 1
	local position = Vector3.new(((spawnCount - 1) % 8 - 3.5) * 13, 0, 35 + math.floor(((spawnCount - 1) % 32) / 8) * 13)
	local hitbox = part("TankHitbox", Vector3.new(8, 5, 10), position + Vector3.new(0, 2.5, 0), Color3.new())
	hitbox.Transparency = 1; hitbox.CanCollide = false
	tanks[player.UserId] = { state = Simulation.new(position), command = Command.neutral(), lastInput = 0,
		lastPacket = 0, hitbox = hitbox, spawn = position, respawnAt = 0 }
end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	local tank = tanks[player.UserId]
	if tank then tank.hitbox:Destroy(); tanks[player.UserId] = nil end
end)
for _, player in Players:GetPlayers() do addPlayer(player) end
input.OnServerEvent:Connect(function(player, value)
	local tank = tanks[player.UserId]
	local now = os.clock()
	if not tank or now - tank.lastPacket < 1 / 60 then return end
	tank.lastPacket = now
	local command = Command.validate(value)
	if command then tank.command = command; tank.lastInput = now end
end)
local function damageTank(tank, now)
	tank.state.health = math.max(0, tank.state.health - Config.Damage)
	if tank.state.health == 0 then tank.respawnAt = now + 3 end
end
local accumulator, snapshotClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += math.min(dt, 0.1)
	while accumulator >= Config.Step do
		accumulator -= Config.Step
		local now = os.clock()
		for _, target in targets do
			if target.health == 0 and now >= target.resetAt then target.health = Config.Health end
		end
		for _, tank in tanks do
			if tank.state.health == 0 and now >= tank.respawnAt then
				tank.state = Simulation.new(tank.spawn); tank.command = Command.neutral()
			end
			local command = if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral()
			local previous = tank.state.position
			Simulation.step(tank.state, command, Config.Step)
			for p, target in targets do
				local delta = tank.state.position - p.Position
				if target.health > 0 and math.abs(delta.X) < p.Size.X / 2 + Config.Radius
					and math.abs(delta.Z) < p.Size.Z / 2 + Config.Radius then
					tank.state.position = previous; break
				end
			end
			for _, other in tanks do
				if other ~= tank and (other.state.position - tank.state.position).Magnitude < Config.Radius * 2 then
					tank.state.position = previous; break
				end
			end
			tank.hitbox.CFrame = CFrame.new(tank.state.position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, tank.state.yaw, 0)
			tank.hitbox.CanQuery = tank.state.health > 0
		end
		for id, tank in tanks do
			local command = if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral()
			local origin, direction = Simulation.tryFire(tank.state, command)
			if origin then
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = { tank.hitbox }
				params.FilterType = Enum.RaycastFilterType.Exclude
				local hit = workspace:Raycast(origin, direction * Config.Range, params)
				local endpoint = if hit then hit.Position else origin + direction * Config.Range
				if hit then
					local target = targets[hit.Instance]
					if target and target.health > 0 then
						target.health = math.max(0, target.health - Config.Damage)
						target.resetAt = now + 3
					end
					for _, other in tanks do
						if other.hitbox == hit.Instance and other.state.health > 0 then damageTank(other, now) end
					end
				end
				shot:FireAllClients(id, origin + direction * 7, endpoint)
			end
		end
		for p, target in targets do
			p:SetAttribute("Health", target.health)
			p.Transparency = if target.health == 0 then 0.85 else 0
			p.CanQuery = target.health > 0
		end
	end
	snapshotClock += dt
	if snapshotClock >= Config.SnapshotInterval then
		snapshotClock %= Config.SnapshotInterval
		local states = {}
		for id, tank in tanks do states[tostring(id)] = tank.state end
		snapshot:FireAllClients(states)
	end
end)

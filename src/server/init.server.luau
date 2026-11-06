local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.TankConfig)
local ArenaLayout = require(Shared.ArenaLayout)
local Environment = require(Shared.Environment)
local EnvironmentBuilder = require(script.EnvironmentBuilder)
local mapSize = Vector2.new(Config.ArenaLimit*2, Config.ArenaLimit*2)
local environment = Environment.create(mapSize)
local Command = require(Shared.InputCommand)
local Simulation = require(Shared.TankSimulation)
local WeaponWindup = require(Shared.WeaponWindup)
local PracticeTargets = require(script.PracticeTargets)
local Projectiles = require(script.ProjectileSimulation)
local Debris = game:GetService("Debris")
Players.CharacterAutoLoads = false
local network = Instance.new("Folder")
network.Name = "TankNetwork"
local function remote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name; event.Parent = network
	return event
end
local input, snapshot, shot = remote("Input"), remote("Snapshot"), remote("Shot")
local prepareShot = remote("PrepareShot")
network.Parent = ReplicatedStorage
local tanks, targets = {}, {}
local arena = Instance.new("Folder")
arena.Name = "Arena"; arena.Parent = workspace
arena:SetAttribute("DebugCombat", false)
local function part(name, size, position, color)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.Size = size; p.Position = position; p.Color = color; p.Parent = arena
	return p
end
-- Build the ground with the arena rather than relying on an optional place
-- Baseplate or Terrain. Its top is exactly the simulation's ground plane Y=0.
local floor = part("Floor", Vector3.new(240, 1, 240), Vector3.new(0, -0.5, 0), Color3.fromRGB(100, 112, 86))
floor.Material = Enum.Material.Concrete
floor.Transparency = 0
floor.CanCollide = false -- anchored, scripted tanks need no supporting physics
floor.CanTouch = false
floor.CanQuery = true -- downward combat rays should still hit the ground
floor.Material = Enum.Material.Grass
EnvironmentBuilder.build(arena,environment)
local walls = {}
for _, data in ipairs({ {Vector3.new(0, 3, -118), Vector3.new(240, 6, 4)}, {Vector3.new(0, 3, 118), Vector3.new(240, 6, 4)}, {Vector3.new(-118, 3, 0), Vector3.new(4, 6, 240)}, {Vector3.new(118, 3, 0), Vector3.new(4, 6, 240)} }) do
	table.insert(walls, part("Boundary", data[2], data[1], Color3.fromRGB(57, 66, 73)))
end
local function buildTargets(size)
	local count = math.clamp(math.floor((size.X-10)/9),1,5)
	for i = 1, count do
		local p = part("Target", Vector3.new(7, 7, 5), Vector3.new((i-(count+1)/2)*math.min(18,(size.X-10)/count), 3.5, -size.Y*65/230), Color3.fromRGB(210, 102, 60))
		local target = PracticeTargets.new(p)
		targets[p] = target
		local gui = Instance.new("BillboardGui")
		gui.Name = "TargetHealth"; gui.Size = UDim2.fromOffset(100, 26)
		gui.StudsOffset = Vector3.new(0, 5, 0); gui.AlwaysOnTop = false
		gui.MaxDistance = 250; gui.Adornee = p; gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextSize = 18; label.Font = Enum.Font.GothamBold; label.Parent = gui
		target.label = label
		PracticeTargets.sync(p, target, 0)
	end
end
buildTargets(mapSize)
local spawnCount = 0
local function addPlayer(player)
	if tanks[player.UserId] then return end
	spawnCount += 1
	local position = if arena:GetAttribute("Redrawn") then ArenaLayout.spawn(mapSize,spawnCount) else Vector3.new(((spawnCount - 1) % 8 - 3.5) * 13, 0, 35 + math.floor(((spawnCount - 1) % 32) / 8) * 13)
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
local shellFolder = Instance.new("Folder")
shellFolder.Name = "ArtilleryShells"; shellFolder.Parent = workspace
local shells = {}
local function shellPart(parent, name, size, color, shape)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color; p.Shape = shape
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic; p.Parent = parent
	return p
end
local function poseShell(shell)
	local frame = CFrame.lookAt(shell.position, shell.position + shell.direction)
	shell.body.CFrame = frame * CFrame.new(0,0,0.65) * CFrame.Angles(0,math.pi/2,0)
	shell.nose.CFrame = frame
	shell.band.CFrame = frame * CFrame.new(0,0,1.1) * CFrame.Angles(0,math.pi/2,0)
end
local function launchShell(id, tank, origin, direction)
	-- Spawn at the muzzle after checking the pivot-to-tip path for cover.
	local shell, blocked = Projectiles.launch(workspace,origin,direction,{tank.hitbox,shellFolder})
	shell.pendingHit = blocked
	shell.owner = id
	shell.model = Instance.new("Model"); shell.model.Name = "Shell_" .. id; shell.model.Parent = shellFolder
	shell.body = shellPart(shell.model,"Body",Vector3.new(1.5,1.3,1.3),Color3.fromRGB(77,87,57),Enum.PartType.Cylinder)
	shell.nose = shellPart(shell.model,"Nose",Vector3.new(1.3,1.3,1.3),Color3.fromRGB(244,158,36),Enum.PartType.Ball)
	shell.band = shellPart(shell.model,"Band",Vector3.new(0.3,1.4,1.4),Color3.fromRGB(255,215,64),Enum.PartType.Cylinder)
	poseShell(shell); table.insert(shells,shell)
	shot:FireAllClients(id,shell.position,direction)
	if arena:GetAttribute("DebugCombat") then
		print("[BattleWorks shell launch]",id,"muzzle",shell.position,"direction",direction,"speed",Config.ShellSpeed)
	end
end
local function updateShells(now)
	for i = #shells,1,-1 do
		local shell = shells[i]
		local hit = shell.pendingHit
		shell.pendingHit = nil
		if not hit then hit = Projectiles.step(workspace,shell,Config.Step) end
		poseShell(shell)
		if hit then
			local _, before, after = PracticeTargets.impact(hit,targets,now)
			for _, other in tanks do
				if other.hitbox == hit.Instance and other.state.health > 0 then damageTank(other,now) end
			end
			if arena:GetAttribute("DebugCombat") then
				print("[BattleWorks shell impact]",shell.owner,hit.Instance:GetFullName(),hit.Position,
					"targetHP",before,after)
			end
			-- Cosmetic impact only: no physics Explosion, splash damage or impulse.
			local puff = shellPart(shellFolder,"Impact",Vector3.new(2,2,2),Color3.fromRGB(255,178,47),Enum.PartType.Ball)
			puff.Material = Enum.Material.Neon; puff.Position = hit.Position
			Debris:AddItem(puff,0.18)
		end
		if shell.done then shell.model:Destroy(); table.remove(shells,i) end
	end
end
-- Development redraw is server-authoritative and never exposed in published play.
arena:SetAttribute("MapWidth", mapSize.X); arena:SetAttribute("MapDepth", mapSize.Y)
arena:SetAttribute("MapRevision", 0)
if RunService:IsStudio() then
	local redraw = remote("RedrawMap")
	local lastRedraw = -math.huge
	redraw.OnServerEvent:Connect(function(player, size)
		if not tanks[player.UserId] or not ArenaLayout.validSize(size) or os.clock()-lastRedraw < 1 then return end
		lastRedraw = os.clock(); mapSize = size
		environment=Environment.create(size); EnvironmentBuilder.build(arena,environment)
		floor.Size = Vector3.new(size.X+10,1,size.Y+10)
		walls[1].Size = Vector3.new(size.X+10,6,4); walls[1].Position = Vector3.new(0,3,-size.Y/2-3)
		walls[2].Size = walls[1].Size; walls[2].Position = Vector3.new(0,3,size.Y/2+3)
		walls[3].Size = Vector3.new(4,6,size.Y+10); walls[3].Position = Vector3.new(-size.X/2-3,3,0)
		walls[4].Size = walls[3].Size; walls[4].Position = Vector3.new(size.X/2+3,3,0)
		for _, shell in shells do shell.model:Destroy() end
		table.clear(shells)
		for p in targets do p:Destroy() end
		table.clear(targets); buildTargets(size)
		local ids = {}; for id in tanks do table.insert(ids,id) end; table.sort(ids)
		for index, id in ids do
			local tank = tanks[id]
			tank.spawn = ArenaLayout.spawn(size,index); tank.state = Simulation.new(tank.spawn)
			tank.command = Command.neutral(); tank.lastInput = 0; tank.pendingShot = nil; tank.respawnAt = 0
			tank.hitbox.CFrame = CFrame.new(tank.spawn+Vector3.new(0,2.5,0)); tank.hitbox.CanQuery = true
		end
		arena:SetAttribute("Redrawn", true)
		arena:SetAttribute("MapWidth", size.X); arena:SetAttribute("MapDepth", size.Y)
		arena:SetAttribute("MapRevision", arena:GetAttribute("MapRevision")+1)
	end)
end
local accumulator, snapshotClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += math.min(dt, 0.1)
	while accumulator >= Config.Step do
		accumulator -= Config.Step
		local now = os.clock()
		for p, target in targets do PracticeTargets.update(p, target, now, tanks) end
		for _, tank in tanks do
			if tank.state.health == 0 and now >= tank.respawnAt then
				tank.pendingShot = nil
				tank.state = Simulation.new(tank.spawn); tank.command = Command.neutral()
			end
			local command = if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral()
			local previous = tank.state.position
			Simulation.step(tank.state, command, Config.Step, mapSize, environment)
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
		updateShells(now)
		for id, tank in tanks do
			local command = if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral()
			if tank.pendingShot then
				local done, origin, direction = WeaponWindup.step(tank.pendingShot, tank.state, Config.Step)
				if done then
					tank.pendingShot = nil
					if origin then launchShell(id, tank, origin, direction) end
				end
			end
			if not tank.pendingShot then
				tank.pendingShot = WeaponWindup.begin(tank.state, command)
				if tank.pendingShot then prepareShot:FireAllClients(id) end
			end
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

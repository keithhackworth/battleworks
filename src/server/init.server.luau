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
local BWController = require(script.BWController)
local Simulation = require(Shared.TankSimulation)
local MovementTelemetry = require(Shared.MovementTelemetry)
local TankDefinitions = require(Shared.TankDefinitions)
local TurretRecoil = require(Shared.TurretRecoil)
local RattlerRecoil = require(Shared.RattlerRecoil)
local RattlerWeapon = require(Shared.RattlerWeapon)
local TankSelection = require(Shared.TankSelection)
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
local selectTank = remote("SelectTank")
local bwRun,bwStop = remote("BWRun"),remote("BWStop")
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
	hitbox:SetAttribute("OwnerId",player.UserId)
	tanks[player.UserId] = { state = Simulation.new(position,"Boomer",math.abs(player.UserId)%2147483646+1), command = Command.neutral(), lastInput = 0,
		lastPacket = 0, hitbox = hitbox, spawn = position, respawnAt = 0, rattler = RattlerWeapon.new(), boomerAim = { aimSeed = math.abs(player.UserId)%2147483646+1 } }
	tanks[player.UserId].rattler.aimSeed = math.abs(player.UserId)%2147483646+1
end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	local tank = tanks[player.UserId]
	if tank then BWController.stop(tank,"Player disconnected."); tank.hitbox:Destroy(); tanks[player.UserId] = nil end
end)
for _, player in Players:GetPlayers() do addPlayer(player) end
input.OnServerEvent:Connect(function(player, value)
	local tank = tanks[player.UserId]
	local now = os.clock()
	if not tank or BWController.running(tank) or now - tank.lastPacket < 1 / 60 then return end
	tank.lastPacket = now
	local command = Command.validate(value)
	if command then
		tank.command = command; tank.lastInput = now
		if tank.requireFireRelease and not command.fire then tank.requireFireRelease = false end
	end
end)
selectTank.OnServerEvent:Connect(function(player, id)
	local tank = tanks[player.UserId]
	if tank and TankSelection.switch(tank,id,os.clock()) then BWController.stop(tank,"Tank selection changed.") end
end)
local function acceptBWRequest(tank,id)
	if type(id)~="number" or id~=id or id%1~=0 or id<1 or id>1000000000 or id<=(tank.lastBWRequest or 0) then return false end
	tank.lastBWRequest=id; tank.state.bwRequestId=id
	return true
end
bwRun.OnServerEvent:Connect(function(player,source,requestId)
	local tank=tanks[player.UserId]
	local now=os.clock()
	if not tank or not acceptBWRequest(tank,requestId) then return end
	if now-(tank.lastBWRun or -math.huge)<0.5 then
		BWController.reject(tank,"Wait half a second between Run requests.")
		return
	end
	tank.lastBWRun=now
	BWController.start(tank,source)
end)
bwStop.OnServerEvent:Connect(function(player,requestId)
	local tank=tanks[player.UserId]
	if tank and acceptBWRequest(tank,requestId) then BWController.stop(tank,"Stopped by player.") end
end)
local function damageTank(tank, now, damage)
	tank.state.health = math.max(0, tank.state.health - (damage or Config.Damage))
	if tank.state.health == 0 then tank.respawnAt = now + 3; tank.state.firing = false; BWController.stop(tank,"Tank destroyed.") end
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
	shell.body.CFrame = frame * CFrame.new(0,0,0.65*(shell.visualScale or 1)) * CFrame.Angles(0,math.pi/2,0)
	shell.nose.CFrame = frame
	shell.band.CFrame = frame * CFrame.new(0,0,1.1*(shell.visualScale or 1)) * CFrame.Angles(0,math.pi/2,0)
end
local function launchShell(id, tank, origin, direction, deferEffects)
	-- Spawn at the muzzle after checking the pivot-to-tip path for cover.
	tank.state.weaponShotSerial=(tank.state.weaponShotSerial or 0)+1
	local tuning = TankDefinitions.get(tank.state.tankType).Weapon
	local shell, blocked = Projectiles.launch(workspace,origin,direction,{tank.hitbox,shellFolder},tuning,floor.Position.Y+floor.Size.Y/2)
	local small = tank.state.tankType == "Rattler"
	shell.pendingHit = blocked
	shell.owner = id
	shell.visualScale = if small then 0.4 else 1
	shell.model = Instance.new("Model"); shell.model.Name = "Shell_" .. id; shell.model.Parent = shellFolder
	shell.body = shellPart(shell.model,"Body",Vector3.new(1.5,1.3,1.3)*(if small then 0.4 else 1),Color3.fromRGB(77,87,57),Enum.PartType.Cylinder)
	shell.nose = shellPart(shell.model,"Nose",Vector3.new(1.3,1.3,1.3)*(if small then 0.4 else 1),Color3.fromRGB(244,158,36),Enum.PartType.Ball)
	shell.band = shellPart(shell.model,"Band",Vector3.new(0.3,1.4,1.4)*(if small then 0.4 else 1),Color3.fromRGB(255,215,64),Enum.PartType.Cylinder)
	poseShell(shell); table.insert(shells,shell)
	if not deferEffects then shot:FireAllClients(id,shell.position,direction,tank.state.tankType,tank.state.generation) end
	if arena:GetAttribute("DebugCombat") then
		print("[BattleWorks shell launch]",id,"muzzle",shell.position,"direction",direction,"speed",shell.speed)
	end
	return shell
end
local function updateShells(now)
	for i = #shells,1,-1 do
		local shell = shells[i]
		local hit = shell.pendingHit
		shell.pendingHit = nil
		if not hit then hit = Projectiles.step(workspace,shell,Config.Step) end
		poseShell(shell)
		if hit then
			local _, before, after = PracticeTargets.impact(hit,targets,now,shell.damage)
			for _, other in tanks do
				if other.hitbox == hit.Instance and other.state.health > 0 then damageTank(other,now,shell.damage) end
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
			BWController.stop(tank,"Map redrawn.")
			local kind, generation = tank.state.tankType, tank.state.generation
			tank.spawn = ArenaLayout.spawn(size,index); tank.state = Simulation.new(tank.spawn,kind,math.abs(id)%2147483646+1)
			tank.state.generation = generation+1; BWController.sync(tank); tank.rattler = RattlerWeapon.new()
			tank.rattler.aimSeed = math.abs(id)%2147483646+1
			tank.boomerAim = {aimSeed=math.abs(id)%2147483646+1}
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
		for id, tank in tanks do
			if tank.state.health == 0 and now >= tank.respawnAt then
				BWController.stop(tank,"Tank respawned.")
				tank.pendingShot = nil
				local kind, generation = tank.state.tankType, tank.state.generation
				tank.state = Simulation.new(tank.spawn,kind,math.abs(id)%2147483646+1); tank.state.generation = generation+1; BWController.sync(tank); tank.command = Command.neutral()
			end
			local command = BWController.input(tank,Config.Step) or (if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral())
			tank.tickCommand=command
			local trigger = command.fire and not tank.requireFireRelease
			tank.rattlerShot = RattlerWeapon.step(tank.rattler,tank.state.tankType == "Rattler" and tank.state.health > 0,trigger,Config.Step)
			tank.state.firing = tank.state.tankType == "Rattler" and tank.rattler.firing
			tank.state.heat = tank.rattler.heat; tank.state.weaponCooldown = tank.rattler.cooldown
			tank.state.groundPlaneY=floor.Position.Y+floor.Size.Y/2
			local previous = tank.state.position
			Simulation.step(tank.state, command, Config.Step, mapSize, environment)
			for p, target in targets do
				local delta = tank.state.position - p.Position
				if target.health > 0 and math.abs(delta.X) < p.Size.X / 2 + Config.Radius
					and math.abs(delta.Z) < p.Size.Z / 2 + Config.Radius then
					if RattlerRecoil.active(tank.state) then RattlerRecoil.resolveBlocked(tank.state,previous,environment) else tank.state.position=previous end; break
				end
			end
			for _, other in tanks do
				if other ~= tank and (other.state.position - tank.state.position).Magnitude < Config.Radius * 2 then
					if RattlerRecoil.active(tank.state) then RattlerRecoil.resolveBlocked(tank.state,previous,environment) else tank.state.position=previous end; break
				end
			end
			MovementTelemetry.update(tank.state,previous,Config.Step)
			tank.hitbox.CFrame = CFrame.new(tank.state.position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, tank.state.yaw, 0)
			tank.hitbox.CanQuery = tank.state.health > 0
		end
		updateShells(now)
		for id, tank in tanks do
			local command = tank.tickCommand or Command.neutral()
			if tank.state.tankType == "Rattler" then
				if tank.rattlerShot and tank.state.health > 0 then
					local origin,direction = Simulation.shotPose(tank.state)
					tank.state.weaponActivationSerial=(tank.state.weaponActivationSerial or 0)+1
					local shell=launchShell(id,tank,origin,direction,true)
					TurretRecoil.kick(tank.state,tank.rattler)
					RattlerRecoil.kick(tank.state,tank.rattler.heat,direction)
					shot:FireAllClients(id,shell.position,direction,tank.state.tankType,tank.state.generation,
						{serial=tank.state.flightShotSerial,roll=tank.state.flightRoll})
				end
				continue
			end
			if tank.requireFireRelease then command = Command.neutral() end
			if tank.pendingShot then
				local done, origin, direction = WeaponWindup.step(tank.pendingShot, tank.state, Config.Step)
				if done then
					tank.pendingShot = nil
					if origin then
						launchShell(id, tank, origin, direction)
						TurretRecoil.kick(tank.state,tank.boomerAim)
					end
				end
			end
			if not tank.pendingShot then
				tank.pendingShot = WeaponWindup.begin(tank.state, command)
				if tank.pendingShot then
					tank.state.weaponActivationSerial=(tank.state.weaponActivationSerial or 0)+1
					prepareShot:FireAllClients(id,"Boomer",tank.state.generation)
				end
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

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
local ScannerConfig=require(Shared.ScannerConfig)
local ScannerGeometry=require(Shared.ScannerGeometry)
local ScannerValues=require(Shared.BWValue)
local DirectionalScanner=require(script.DirectionalScanner)
local ManualScanner=require(script.ManualScanner)
local DamageEffects = require(Shared.DamageEffects)
local Simulation = require(Shared.TankSimulation)
local MovementTelemetry = require(Shared.MovementTelemetry)
local TankDefinitions = require(Shared.TankDefinitions)
local TurretRecoil = require(Shared.TurretRecoil)
local RattlerRecoil = require(Shared.RattlerRecoil)
local RattlerWeapon = require(Shared.RattlerWeapon)
local Battle = require(script.LocalBattle)
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
local resetBattle = remote("ResetBattle")
local bwOutput=remote("BWOutput")
local bwHardware=remote("BWHardware")
local bwRuntimeState=remote("BWRuntimeState")
local Hardware=require(Shared.BWChassis)
network.Parent = ReplicatedStorage
local tanks, targets, battles = {}, {}, {}
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
local simulationTime=0
local scanner=DirectionalScanner.new(workspace,function()
	local geometry,records={},{}
	-- Only authoritative arena geometry participates. Projectiles, decorations,
	-- particle volumes and client render models are outside this allowlist.
	for _,p in arena:GetDescendants() do
		if (p:IsA("BasePart") or p:IsA("Part")) and p~=floor and p.CanQuery~=false then table.insert(geometry,p) end
	end
	for id,tank in tanks do records[tank.hitbox]={state=tank.state,id=id,playerName=tank.playerName,tankName=tank.tankName or tank.kind,teamId=tank.teamId} end
	return geometry,records
end)
local function publishScan(tank,angle,observation,manual)
	local values=observation.value
    -- Show the strongest completed observation; a nearby wall must not mask a
    -- visible enemy elsewhere in this same cone.
    local priority=if values.type=="tank" then (if values.relation=="enemy" then 4 else 3) elseif values.type=="wall" then 2 else 1
    for _,detection in values.detections or {} do
        local rank=if detection.type=="tank" then (if detection.relation=="enemy" then 4 else 3) else 2
        if rank>priority then values=detection; priority=rank end
    end
	local distance=if values.distance~=ScannerValues.Null then values.distance else nil
	tank.scanSerial=(tank.scanSerial or 0)+1
	-- Public decoration state contains no name, exact range, target ID or hit point.
	local visual={serial=tank.scanSerial,angle=angle,kind=if values.type~=ScannerValues.Null then values.type else "none",
		affiliation=if values.relation~=ScannerValues.Null then values.relation else nil,
		proximity=if not distance then 0 elseif distance<=ScannerConfig.NearDistance then 1 elseif distance<=ScannerConfig.MidDistance then 0.55 else 0.2,
		remaining=if manual then ScannerConfig.ManualVisualDuration else ScannerConfig.VisualDuration}
	if manual then
		ManualScanner.record(tank,angle,visual)
	else
        tank.state.scanBW=tank.state.scanBW or {}
        tank.state.scanBW[tostring(ScannerGeometry.sensorIndex(angle))]=visual
        tank.state.scanVisual=table.clone(visual) -- legacy latest event; separate expiry
    end
end
local spawnCount = 0
local function owned(player,id)
	if id~=nil and type(id)~="string" then return nil end
	local battle=battles[player.UserId]
	return battle and battle.tanks[id or battle.selected]
end
local function addPlayer(player)
	if battles[player.UserId] then return end
	spawnCount+=1
	local battle=Battle.new(player.UserId,spawnCount); battles[player.UserId]=battle
	for _,kind in {"Boomer","Rattler"} do
		local id=Battle.id(player.UserId,kind)
		local hitbox=part("TankHitbox",Vector3.new(8,5,10),Vector3.zero,Color3.new())
		hitbox.Transparency=1; hitbox.CanCollide=false
		hitbox:SetAttribute("OwnerId",player.UserId); hitbox:SetAttribute("TankId",id)
		local tank={owner=player.UserId,playerName=player.Name,kind=kind,seed=(math.abs(player.UserId)+(if kind=="Rattler" then 7919 else 0))%2147483646+1,hitbox=hitbox,lastPacket=0}
		Battle.resetTank(tank,mapSize,spawnCount,"Battle started.")
		tanks[id]=tank; battle.tanks[id]=tank
		tank.bwServices={
			getClock=function() return simulationTime end,
            cancelWeapon=function() tank.pendingShot=nil; tank.rattlerShot=false end,
            scan=function(angle,performance,time,hardware)
				local observation,err=scanner:execute(tank,angle,simulationTime,hardware)
				if observation then publishScan(tank,angle,observation,false) end
				return observation,err
			end,
            onEvent=function(event)
                if event.kind~="scan" and event.kind~="print" then bwOutput:FireClient(player,id,tank.state.generation,tank.bwRunRequestId or 0,event) end
            end,
			onValue=function(observation,line,angle,thread)
                local value=observation.value
                local text=ScannerValues.format(value)
                if value.detections then
                    local lines={string.format("%d detections • range %.6g studs",value.count,value.range)}
                    for index,detection in value.detections do table.insert(lines,string.format("[%d] %s",index-1,ScannerValues.format(detection))) end
                    text=table.concat(lines,"\n")
                end
				bwOutput:FireClient(player,id,tank.state.generation,tank.bwRunRequestId or 0,
					{thread=thread,kind="scan",angle=angle,text=text,timestamp=observation.timestamp,line=line})
			end,
			onPrint=function(text,line,thread)
				bwOutput:FireClient(player,id,tank.state.generation,tank.bwRunRequestId or 0,
					{thread=thread,kind="print",text=text,timestamp=simulationTime,line=line})
			end,
		}
	end
end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	local battle=battles[player.UserId]
	if not battle then return end
	for id,tank in battle.tanks do BWController.stop(tank,"Player disconnected."); tank.hitbox:Destroy(); tanks[id]=nil end
	battles[player.UserId]=nil
end)
for _, player in Players:GetPlayers() do addPlayer(player) end
input.OnServerEvent:Connect(function(player,value,id)
	local battle=battles[player.UserId]
	local tank=owned(player,id)
	local now=os.clock()
	if not tank or (id and id~=battle.selected) or tank.state.health<=0 or BWController.running(tank) or now-tank.lastPacket<1/60 then return end
	tank.lastPacket=now
	local command=Command.validate(value)
	if command then
		tank.command=command; tank.lastInput=now
		if tank.requireFireRelease and not command.fire then tank.requireFireRelease=false end
	end
end)
selectTank.OnServerEvent:Connect(function(player,kind)
	local battle=battles[player.UserId]
	if battle then Battle.select(battle,kind) end
end)
local function acceptBWRequest(tank,id)
	if type(id)~="number" or id~=id or id%1~=0 or id<1 or id>1000000000 or id<=(tank.lastBWRequest or 0) then return false end
	tank.lastBWRequest=id; tank.state.bwRequestId=id
	return true
end
bwRun.OnServerEvent:Connect(function(player,source,requestId,id)
	local tank=owned(player,id)
	local now=os.clock()
	if not tank or not acceptBWRequest(tank,requestId) then return end
	if now-(tank.lastBWRun or -math.huge)<0.5 then
		BWController.reject(tank,"Wait half a second between Run requests.")
		return
	end
	tank.lastBWRun=now
	BWController.start(tank,source)
end)
bwStop.OnServerEvent:Connect(function(player,requestId,id)
	local tank=owned(player,id)
	if tank and acceptBWRequest(tank,requestId) then BWController.stop(tank,"Stopped by player.") end
end)
bwHardware.OnServerEvent:Connect(function(player,configuration,id)
 local tank=owned(player,id); if not tank then return end
 local now=os.clock(); if now-(tank.lastHardwareRequest or -math.huge)<0.25 then return end
 tank.lastHardwareRequest=now
 local ok,reason=BWController.configure(tank,configuration)
 bwRuntimeState:FireClient(player,id,{configuration=Hardware.copy(tank.hardware or Hardware.forTank(tank.state.tankType)),configurationResult=if ok then "success" else reason})
end)
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
	shell.weaponType=TankDefinitions.get(tank.state.tankType).WeaponType
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
				if other.hitbox == hit.Instance then
					local battle=battles[other.owner]
					Battle.damage(battle,other,tanks[shell.owner],shell.damage,shell.weaponType,hit.Position)
				end
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
local function reset(battle,reason)
	for i=#shells,1,-1 do
		local shell=shells[i]
		if battle.tanks[shell.owner] then shell.model:Destroy(); table.remove(shells,i) end
	end
	battle.winner=nil
	for _,tank in battle.tanks do Battle.resetTank(tank,mapSize,battle.index,reason) end
end
resetBattle.OnServerEvent:Connect(function(player)
	local battle=battles[player.UserId]
	if not battle or os.clock()-(battle.lastReset or -math.huge)<0.5 then return end
	battle.lastReset=os.clock(); reset(battle,"Battle reset.")
end)
-- Development redraw is server-authoritative and never exposed in published play.
arena:SetAttribute("MapWidth", mapSize.X); arena:SetAttribute("MapDepth", mapSize.Y)
arena:SetAttribute("MapRevision", 0)
if RunService:IsStudio() then
	local redraw = remote("RedrawMap")
	local lastRedraw = -math.huge
	redraw.OnServerEvent:Connect(function(player, size)
		if not battles[player.UserId] or not ArenaLayout.validSize(size) or os.clock()-lastRedraw < 1 then return end
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
		for _,battle in battles do reset(battle,"Map redrawn.") end
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
			DamageEffects.step(tank.effects,tank.state,Config.Step)
			BWController.applyHardware(tank)
            local visual=tank.state.scanVisual
			if visual then visual.remaining=math.max(0,visual.remaining-Config.Step); if visual.remaining==0 then tank.state.scanVisual=nil end end
            for key,event in tank.state.scanBW or {} do
                event.remaining=math.max(0,event.remaining-Config.Step)
                if event.remaining==0 then tank.state.scanBW[key]=nil end
            end
            if tank.state.scanBW and next(tank.state.scanBW)==nil then tank.state.scanBW=nil end
			local command = if tank.state.health<=0 then Command.neutral() else BWController.input(tank,Config.Step) or (if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral())
			tank.tickCommand=command
			local trigger = command.fire and not tank.requireFireRelease
			tank.rattlerShot = RattlerWeapon.step(tank.rattler,tank.state.tankType == "Rattler" and tank.state.health > 0,trigger,Config.Step,tank.state.weaponPerformance)
			tank.state.firing = tank.state.tankType == "Rattler" and tank.rattler.firing
			tank.state.heat = tank.rattler.heat; tank.state.weaponCooldown = tank.rattler.cooldown
		end
		-- BW gets first use of the shared query budget. Manual sweeps run only for
		-- the selected living tank without an active program, never into BW output.
		for id,tank in tanks do
			local battle=battles[tank.owner]
			ManualScanner.step(tank,battle and battle.selected==id and not BWController.running(tank),simulationTime,Config.Step,
				function(angle)
                    local sensor=math.floor((angle%360+22.5)/45)%8*45
                    local hardware=tank.hardware.devices["sensor"..sensor]
                    if not hardware or hardware.allocation<=0 then return nil end
                    return scanner:execute(tank,angle,simulationTime,hardware)
                end,
				function(angle,observation) publishScan(tank,angle,observation,true) end)
		end
		-- All BW observations precede movement, so every hitbox/state corresponds
		-- to the same completed simulation timestamp, regardless of table order.
		for _,tank in tanks do
			local command=tank.tickCommand
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

		simulationTime+=Config.Step
	end
	snapshotClock += dt
	if snapshotClock >= Config.SnapshotInterval then
		snapshotClock %= Config.SnapshotInterval
		local states = {}
		for id, tank in tanks do states[tostring(id)] = tank.state end
		for owner,battle in battles do
            local player=Players:GetPlayerByUserId(owner)
            if player then
                for id,tank in battle.tanks do
                    if simulationTime-(tank.lastDiagnostics or -math.huge)>=0.2 then
                        tank.lastDiagnostics=simulationTime
                        bwRuntimeState:FireClient(player,id,{configuration=Hardware.copy(tank.hardware or Hardware.forTank(tank.state.tankType)),runtime=if tank.bw then tank.bw:diagnostics() else nil})
                    end
                end
            end
        end
        local battleStates={}
		for owner,battle in battles do battleStates[tostring(owner)]={selected=battle.selected,winner=battle.winner} end
		snapshot:FireAllClients(states,battleStates)
	end
end)

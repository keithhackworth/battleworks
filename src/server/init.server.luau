local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local function startup(stage) if RunService:IsStudio() then print("[BattleWorks startup/server] "..stage) end end
startup("server started")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.TankConfig)
local ArenaLayout = require(Shared.ArenaLayout)
local Environment = require(Shared.Environment)
local WorldSettings = require(Shared.WorldSettings)
local EnvironmentBuilder = require(script.EnvironmentBuilder)
local mapSize = Vector2.new(Config.ArenaLimit*2, Config.ArenaLimit*2)
local weather=workspace:GetAttribute("ArenaWeather") or "IceWind"
local environment
local singleModelWorld=false
local worldObjects
local worldSettings
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
local Components = require(Shared.VehicleComponents)
local TurretRecoil = require(Shared.TurretRecoil)
local RattlerRecoil = require(Shared.RattlerRecoil)
local RattlerWeapon = require(Shared.RattlerWeapon)
local Battle = require(script.LocalBattle)
local WeaponWindup = require(Shared.WeaponWindup)
local PracticeTargets = require(script.PracticeTargets)
local VehicleContacts=require(Shared.VehicleContacts)
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
local battleSession = remote("BattleSession")
local sessions = {}
local playerWorlds
local bwOutput=remote("BWOutput")
local bwHardware=remote("BWHardware")
local bwRuntimeState=remote("BWRuntimeState")
local Hardware=require(Shared.BWChassis)
network.Parent = ReplicatedStorage
local tanks, targets, battles = {}, {}, {}
local shells = {}
local editorPreview=workspace:FindFirstChild("BattleWorksEditorPreview"); if editorPreview then editorPreview:Destroy() end
local arena = Instance.new("Folder")
arena.Name = "Arena"; arena.Parent = workspace
local storage=game:GetService("ServerStorage")
local studioConfiguration=if storage then storage:FindFirstChild("BattleWorksStudio") else nil
local editorMetadata=if studioConfiguration then studioConfiguration:FindFirstChild("EditorAssetCatalog") else nil
if editorMetadata then
 startup("publishing editor asset library")
 local ok,reason=pcall(function() require(script.EditorAssetCatalog).publish(storage,ReplicatedStorage,editorMetadata,game:GetService("HttpService")) end)
 if ok then startup("editor asset library ready") else warn("BattleWorks editor library unavailable: "..tostring(reason)) end
end
local publishedWorld=if studioConfiguration then studioConfiguration:FindFirstChild("PublishedWorld") else nil
local productionWorld=if not RunService:IsStudio() and publishedWorld and publishedWorld:IsA("StringValue") and publishedWorld.Value~="" then publishedWorld.Value else nil
if RunService:IsStudio() or productionWorld then
 local selection=require(script.StudioWorldSelector).start(RunService,storage,arena,nil,productionWorld)
 singleModelWorld=selection.active.profile=="single-model"
 worldObjects=selection.objects
 worldSettings=selection.active.settings
 if worldSettings then mapSize=Vector2.new(worldSettings.width,worldSettings.depth) end
end
-- The imported-asset world uses ground/boundaries and registered model placements.
-- Normal arena creation, including weather and terrain, is unchanged.
if singleModelWorld then weather="Normal" end
local function createEnvironment(size)
 local data=Environment.create(size,weather)
 if singleModelWorld then data.rocks={}; data.logs={}; data.trees={}; data.zones={} end
 if worldSettings then data.zones=table.clone(worldSettings.zones) end
 data.worldObjects=worldObjects
 return data
end
environment=createEnvironment(mapSize)
arena:SetAttribute("DebugCombat", false)
arena:SetAttribute("Weather",weather)
if environment.wind then
 arena:SetAttribute("WindMaxForce",environment.wind.maxForce)
 arena:SetAttribute("WindDriftSpeed",environment.wind.driftSpeed)
end
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
EnvironmentBuilder.build(arena,environment,floor)
if worldSettings then
 floor.Size=Vector3.new(mapSize.X+10,1,mapSize.Y+10)
 floor.Material=Enum.Material[worldSettings.ground.material]
 floor.Color=Color3.fromRGB(table.unpack(worldSettings.ground.color))
end
if not singleModelWorld then
 local stick=part("CenterStick",Vector3.new(10,1,1),Vector3.new(0,.5,0),Color3.fromRGB(125,79,40))
 stick.Shape=Enum.PartType.Cylinder; stick.Material=Enum.Material.Wood
 stick.CanCollide=false; stick.CanTouch=false; stick.CanQuery=false
end
local walls = {}
for _, data in ipairs({ {Vector3.new(0, 3, -118), Vector3.new(240, 6, 4)}, {Vector3.new(0, 3, 118), Vector3.new(240, 6, 4)}, {Vector3.new(-118, 3, 0), Vector3.new(4, 6, 240)}, {Vector3.new(118, 3, 0), Vector3.new(4, 6, 240)} }) do
	table.insert(walls, part("Boundary", data[2], data[1], Color3.fromRGB(57, 66, 73)))
end
if worldSettings then
 walls[1].Size=Vector3.new(mapSize.X+10,6,4); walls[1].Position=Vector3.new(0,3,-mapSize.Y/2-3)
 walls[2].Size=walls[1].Size; walls[2].Position=Vector3.new(0,3,mapSize.Y/2+3)
 walls[3].Size=Vector3.new(4,6,mapSize.Y+10); walls[3].Position=Vector3.new(-mapSize.X/2-3,3,0)
 walls[4].Size=walls[3].Size; walls[4].Position=Vector3.new(mapSize.X/2+3,3,0)
end
local function buildTargets(size)
 if singleModelWorld then return end
	local count = math.clamp(math.floor((size.X-10)/9),1,5)
	for i = 1, count do
		local p = part("Target", Vector3.new(7, 7, 5), Vector3.new((i-(count+1)/2)*math.min(18,(size.X-10)/count), 3.5, -size.Y*65/230), Color3.fromRGB(210, 102, 60))
		local target = PracticeTargets.new(p)
        target.collisionId="target:"..i
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
    local priority=if values.type=="tank" then (if values.relation=="enemy" then 4 else 3) elseif (values.type=="wall" or values.type=="object") then 2 else 1
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
-- Existing tank collections and selection survive joining the shared battle. Studio regression
-- fixtures can explicitly retain isolated pairs; published battles cannot.
local soloFixture=RunService:IsStudio() and workspace:GetAttribute("SoloTankPairs")==true
local multiplayer=false
local function findSpawn(tank)
 local bodies=table.clone(VehicleContacts.obstacles(environment,mapSize))
 if worldObjects then for _,body in worldObjects:obstacles() do table.insert(bodies,body) end end
 for p,target in targets do if target.health>0 then table.insert(bodies,VehicleContacts.box("spawn-target",p.Position,p.Size.X/2,p.Size.Z/2,-p.Size.Y/2,p.Size.Y/2)) end end
 for _,other in tanks do
  if other~=tank and not other.state.waitingForSpawn then table.insert(bodies,VehicleContacts.body("spawn-tank",other.state,Components.get(other.state).Chassis)) end
 end
 local preferred,yaw=Battle.pose(mapSize,tank.spawnIndex,tank.kind)
 if worldSettings then
  -- Use authored headings/anchors, then the same bounded fallback search.
  for _,spawn in worldSettings.spawns do
   if spawn.tank==tank.kind then preferred=Vector3.new(table.unpack(spawn.position)); yaw=-math.rad(spawn.heading) end
  end
  local ok,position,heading=pcall(WorldSettings.spawn,worldSettings,tank.kind,tank.spawnIndex,bodies)
  if ok then preferred,yaw=position,heading end
 end
 local function clear(p)
  if math.abs(p.X)>mapSize.X/2-7 or math.abs(p.Z)>mapSize.Y/2-7 then return false end
  for _,body in bodies do if not body.plane and WorldSettings.blocked(p,body,7) then return false end end
  return true
 end
 if clear(preferred) then return preferred,yaw end
 for z=-mapSize.Y/2+7,mapSize.Y/2-7,14 do
  for x=-mapSize.X/2+7,mapSize.X/2-7,14 do
   local p=Vector3.new(x,0,z)
   if clear(p) then return p,yaw end
  end
 end
 return nil
end
local function removeTank(id,tank)
 for i=#shells,1,-1 do if shells[i].owner==id then shells[i].model:Destroy(); table.remove(shells,i) end end
 BWController.stop(tank,"Tank removed.")
 tank.hitbox:Destroy(); tanks[id]=nil
end
local function enterMultiplayer()
 multiplayer=true
 for _,battle in battles do
  battle.multiplayer=true; battle.winner=nil
  for _,tank in battle.tanks do
   tank.findSpawn=findSpawn
   if tank.state.health<=0 and not tank.respawnAt then tank.respawnAt=simulationTime+3 end
  end
 end
end
local function owned(player,id)
	if id~=nil and type(id)~="string" then return nil end
	local battle=battles[player.UserId]
	return battle and battle.tanks[id or battle.selected]
end
local function addPlayer(player)
	if battles[player.UserId] then return end
	if not soloFixture and next(battles) then enterMultiplayer() end
 spawnCount=1
 local used={}
 for _,existing in battles do used[existing.index]=true end
 while used[spawnCount] do spawnCount+=1 end
	local battle=Battle.new(player.UserId,spawnCount); battles[player.UserId]=battle
 battle.multiplayer=multiplayer
	for _,kind in {"Boomer","Rattler"} do
		local id=Battle.id(player.UserId,kind)
		local size=Components.get(kind).Chassis.Hitbox
		local hitbox=part("TankHitbox",Vector3.new(size.X,size.Y,size.Z),Vector3.zero,Color3.new())
		hitbox.Transparency=1; hitbox.CanCollide=false
		hitbox:SetAttribute("OwnerId",player.UserId); hitbox:SetAttribute("TankId",id)
		local tank={owner=player.UserId,playerName=player.Name,kind=kind,seed=(math.abs(player.UserId)+(if kind=="Rattler" then 7919 else 0))%2147483646+1,hitbox=hitbox,lastPacket=0}
		tank.worldSettings=worldSettings; tank.worldObjects=worldObjects
  tank.spawnIndex=spawnCount; tank.findSpawn=if multiplayer then findSpawn else nil
		if not Battle.resetTank(tank,mapSize,spawnCount,"Battle started.") then
   -- A full authored map leaves the player waiting for a free spawn, with no
   -- targetable or controllable body. Retry through the normal respawn path.
   tank.findSpawn=function() return Battle.pose(mapSize,spawnCount,tank.kind) end
   Battle.resetTank(tank,mapSize,spawnCount,"Waiting for a safe spawn.")
   tank.findSpawn=findSpawn; tank.state.health=0; tank.hitbox.CanQuery=false
   tank.state.waitingForSpawn=true
   tank.respawnAt=simulationTime+3
  end
        tank.state.generation=sessions[player.UserId].generation
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
-- Presence in the experience is separate from participation in a battle.
local function registerPlayer(player)
 if not sessions[player.UserId] then sessions[player.UserId]={lastRequest=0,lastEnter=-math.huge,generation=0} end
 if playerWorlds then playerWorlds:register(player) end
end
local function leaveBattle(player)
 local battle=battles[player.UserId]
 if not battle then return end
 local session=sessions[player.UserId]
 for id,tank in battle.tanks do
  if session then session.generation=math.max(session.generation,tank.state.generation+1) end
  removeTank(id,tank)
 end
 battles[player.UserId]=nil
 if not next(battles) then multiplayer=false end
end
Players.PlayerAdded:Connect(registerPlayer)
Players.PlayerRemoving:Connect(function(player)
 leaveBattle(player)
 sessions[player.UserId]=nil
 if playerWorlds then playerWorlds:remove(player) end
end)
for _,player in Players:GetPlayers() do registerPlayer(player) end
battleSession.OnServerEvent:Connect(function(player,action,requestId)
 local session=sessions[player.UserId]
 if not session or (action~="Enter" and action~="Leave") or type(requestId)~="number"
  or requestId~=requestId or requestId%1~=0 or requestId<1 or requestId>1000000000 or requestId<=session.lastRequest then return end
 session.lastRequest=requestId
 if action=="Leave" then
  leaveBattle(player)
 elseif not battles[player.UserId] then
  if playerWorlds and not playerWorlds:canEnter(player) then
   battleSession:FireClient(player,requestId,false,"Your saved world is not ready. Return to World Editor and try Play again.")
   return
  end
  local now=os.clock()
  if now-session.lastEnter<1 then
   battleSession:FireClient(player,requestId,false,"Please wait a moment before entering again.")
   return
  end
  session.lastEnter=now
  addPlayer(player)
 end
 battleSession:FireClient(player,requestId,battles[player.UserId]~=nil)
end)
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
	if not battle or (kind~="Boomer" and kind~="Rattler") then return end
 Battle.select(battle,kind)
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
 bwRuntimeState:FireClient(player,id,{configuration=Hardware.copy(tank.hardware or Hardware.forTank(tank.state)),configurationResult=if ok then "success" else reason})
end)
local shellFolder = Instance.new("Folder")
shellFolder.Name = "ArtilleryShells"; shellFolder.Parent = workspace
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
	local tuning = Components.get(tank.state).Weapon
 local airborne,ground=Simulation.projectileFlight(tank.state)
 local flight={airborne=airborne,findGround=if worldObjects then function(position,heading,range,radius,baseline)
  return worldObjects:projectileGround(position,heading,range,radius,baseline)
 end else nil}
	local shell, blocked = Projectiles.launch(workspace,origin,direction,{tank.hitbox,shellFolder},tuning,ground,flight)
	local small = Components.get(tank.state).Weapon.Operation=="Heat"
	shell.pendingHit = blocked
	shell.owner = id
	shell.weaponType=Components.get(tank.state).Weapon.WeaponType
	shell.visualScale = if small then 0.4 else 1
	shell.model = Instance.new("Model"); shell.model.Name = "Shell_" .. id; shell.model.Parent = shellFolder
	shell.body = shellPart(shell.model,"Body",Vector3.new(1.5,1.3,1.3)*(if small then 0.4 else 1),Color3.fromRGB(77,87,57),Enum.PartType.Cylinder)
	shell.nose = shellPart(shell.model,"Nose",Vector3.new(1.3,1.3,1.3)*(if small then 0.4 else 1),Color3.fromRGB(244,158,36),Enum.PartType.Ball)
	shell.band = shellPart(shell.model,"Band",Vector3.new(0.3,1.4,1.4)*(if small then 0.4 else 1),Color3.fromRGB(255,215,64),Enum.PartType.Cylinder)
	poseShell(shell); table.insert(shells,shell)
	if not deferEffects then shot:FireAllClients(id,shell.position,direction,tank.state.tankType,tank.state.generation,nil,tank.state.weaponId) end
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
   if worldObjects then
    local record,_,_,destroyed=worldObjects:impact(hit,shell.damage,shell)
    if destroyed then
     -- Lightweight wood-chip burst, never a physics Explosion or damage source.
     for index=1,8 do
      local angle=index*math.pi/4
      local chip=shellPart(shellFolder,"WoodChip",Vector3.new(.45,.3,1.2),Color3.fromRGB(157,103,53))
      chip.Material=Enum.Material.Wood
      chip.CFrame=CFrame.new(record.proxy.CFrame.Position+Vector3.new(math.cos(angle)*2,index%3,math.sin(angle)*2))*CFrame.Angles(angle,angle,0)
      Debris:AddItem(chip,.5); worldObjects:trackEffect(chip)
     end
    end
   end
			for _, other in tanks do
				if other.hitbox == hit.Instance then
					local battle=battles[other.owner]
					if Battle.damage(battle,other,tanks[shell.owner],shell.damage,shell.weaponType,hit.Position) and multiplayer and other.state.health<=0 then
                        other.respawnAt=simulationTime+3
                    end
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
	battle.lastReset=os.clock()
 if battle.multiplayer then return end
 if worldObjects then worldObjects:reset() end
 reset(battle,"Battle reset.")
end)
-- Development redraw is server-authoritative and never exposed in published play.
arena:SetAttribute("MapWidth", mapSize.X); arena:SetAttribute("MapDepth", mapSize.Y)
arena:SetAttribute("MapRevision", 0)
if RunService:IsStudio() then
	local redraw = remote("RedrawMap")
	local lastRedraw = -math.huge
	redraw.OnServerEvent:Connect(function(player, size)
		if worldSettings or not battles[player.UserId] or not ArenaLayout.validSize(size) or os.clock()-lastRedraw < 1 then return end
		lastRedraw = os.clock(); mapSize = size
  if worldObjects then worldObjects:reset() end
		environment=createEnvironment(size); EnvironmentBuilder.build(arena,environment,floor)
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
-- Player worlds are installed only into an empty battlefield. Published launches
-- use a fresh reserved server; Studio uses this same path without teleporting.
local function installPlayerWorld(player,document,specs,settings)
 assert(sessions[player.UserId] and not next(battles),"The battlefield is busy. Leave combat on every Studio client before testing a world.")
 local candidate=require(script.WorldObjects).new()
 local staging=Instance.new("Folder")
 local ok,reason=pcall(function()
  local models,err=require(Shared.ModelPlacement).placeMany(storage:FindFirstChild("BattleWorksAssets"),specs,staging,function(model,spec) candidate:add(model,spec) end)
  assert(models,err);WorldSettings.checkSpawns(settings,candidate:obstacles())
 end)
 if not ok then staging:Destroy();error(reason) end
 -- Everything below is synchronous, after native assets and spawns validate.
 local scenery=staging:FindFirstChild("WorldScenery")
 local old=arena:FindFirstChild("WorldScenery");if old then old:Destroy() end
 scenery.Parent=arena;staging:Destroy()
 for p in targets do p:Destroy() end;table.clear(targets)
 local stick=arena:FindFirstChild("CenterStick");if stick then stick:Destroy() end
 worldObjects=candidate;worldSettings=settings;singleModelWorld=true;weather="Normal"
 mapSize=Vector2.new(settings.width,settings.depth)
 environment=createEnvironment(mapSize);EnvironmentBuilder.build(arena,environment,floor)
 floor.Size=Vector3.new(mapSize.X+10,1,mapSize.Y+10)
 floor.Material=Enum.Material[settings.ground.material];floor.Color=Color3.fromRGB(table.unpack(settings.ground.color))
 walls[1].Size=Vector3.new(mapSize.X+10,6,4);walls[1].Position=Vector3.new(0,3,-mapSize.Y/2-3)
 walls[2].Size=walls[1].Size;walls[2].Position=Vector3.new(0,3,mapSize.Y/2+3)
 walls[3].Size=Vector3.new(4,6,mapSize.Y+10);walls[3].Position=Vector3.new(-mapSize.X/2-3,3,0)
 walls[4].Size=walls[3].Size;walls[4].Position=Vector3.new(mapSize.X/2+3,3,0)
 arena:SetAttribute("Weather",weather);arena:SetAttribute("WorldId",document.id)
 arena:SetAttribute("WorldName","Player world")
 arena:SetAttribute("MapWidth",mapSize.X);arena:SetAttribute("MapDepth",mapSize.Y)
 arena:SetAttribute("MapRevision",arena:GetAttribute("MapRevision")+1)
end
if editorMetadata then
 local worldRemote=Instance.new("RemoteFunction");worldRemote.Name="PlayerWorlds";worldRemote.Parent=network
 local ok,reason=pcall(function()
  local http=game:GetService("HttpService")
  local library=ReplicatedStorage:FindFirstChild("BattleWorksEditorAssets")
  assert(library,"Editor asset library unavailable")
  local studio=RunService:IsStudio()
  local teleport=if not studio then game:GetService("TeleportService") else nil
  playerWorlds=require(script.PlayerWorldService).new({
   studio=studio,reserved=not studio and game.PrivateServerId~="" and game.PrivateServerOwnerId==0,
   placeId=game.PlaceId,http=http,items=http:JSONDecode(library:FindFirstChild("Catalog").Value),assets=storage:FindFirstChild("BattleWorksAssets"),
   dataStore=if not studio then game:GetService("DataStoreService"):GetDataStore("BattleWorksPlayerWorlds_v1") else nil,
   isPresent=function(player) return sessions[player.UserId]~=nil end,
   inBattle=function(player) return battles[player.UserId]~=nil end,
   install=installPlayerWorld,
   teleport=function(player,data)
    local options=Instance.new("TeleportOptions");options.ReservedServerId=http:GenerateGUID(false);options:SetTeleportData(data)
    teleport:TeleportAsync(game.PlaceId,{player},options)
   end,
  })
  for _,player in Players:GetPlayers() do playerWorlds:register(player) end
  if teleport then teleport.TeleportInitFailed:Connect(function(player,_,message)
   -- The client remains in its editor; an event reports asynchronous failures.
   battleSession:FireClient(player,0,false,"World launch failed: "..tostring(message)..". Your saved world is safe; try Play again.")
  end) end
 end)
 if not ok then warn("BattleWorks saved worlds unavailable: "..tostring(reason)) end
 worldRemote.OnServerInvoke=function(player,action,payload)
  if not playerWorlds then return {ok=false,message="Saved worlds are unavailable in this place build."} end
  return playerWorlds:request(player,action,payload)
 end
end
startup("arena and battle services ready")
local accumulator, snapshotClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += math.min(dt, 0.1)
	while accumulator >= Config.Step do
		accumulator -= Config.Step
		local now = os.clock()
		for p, target in targets do PracticeTargets.update(p, target, now, tanks) end
		for id, tank in tanks do
			if tank.respawnAt and simulationTime>=tank.respawnAt then
                if not Battle.resetTank(tank,mapSize,battles[tank.owner].index,"Respawned.") then tank.respawnAt=simulationTime+1 end
            end
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
			tank.rattlerShot = RattlerWeapon.step(tank.rattler,Components.get(tank.state).Weapon.Operation=="Heat" and tank.state.health > 0,trigger,Config.Step,tank.state.weaponPerformance)
			tank.state.firing = Components.get(tank.state).Weapon.Operation=="Heat" and tank.rattler.firing
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
        local contactBodies={}
        local contactObstacles=table.clone(VehicleContacts.obstacles(environment,mapSize))
        if worldObjects then for _,body in worldObjects:obstacles() do table.insert(contactObstacles,body) end end
        for p,target in targets do
            if target.health>0 then table.insert(contactObstacles,VehicleContacts.box(target.collisionId,p.Position,p.Size.X/2,p.Size.Z/2,-p.Size.Y/2,p.Size.Y/2)) end
        end
		for id,tank in tanks do
			local command=tank.tickCommand
			tank.state.groundPlaneY=floor.Position.Y+floor.Size.Y/2
            if not tank.state.waitingForSpawn then
                Simulation.step(tank.state, command, Config.Step, mapSize, environment,true)
                table.insert(contactBodies,VehicleContacts.body(id,tank.state,Components.get(tank.state).Chassis))
            end
        end
        VehicleContacts.solve(contactBodies,contactObstacles,Config.Step)
        for _,record in contactBodies do
            local tank=tanks[record.id]
            Simulation.reconcileGround(tank.state,environment)
            MovementTelemetry.update(tank.state,tank.state.motionStepStart,Config.Step)
            tank.hitbox.CFrame=CFrame.new(tank.state.position+Vector3.new(0,Components.get(tank.state).Chassis.HitboxHeight,0))*CFrame.Angles(0,tank.state.yaw,0)
            tank.hitbox.CanQuery=tank.state.health>0
        end
		updateShells(now)
		for id, tank in tanks do
			local command = tank.tickCommand or Command.neutral()
			if Components.get(tank.state).Weapon.Operation=="Heat" then
				if tank.rattlerShot and tank.state.health > 0 then
					local origin,direction = Simulation.shotPose(tank.state)
					tank.state.weaponActivationSerial=(tank.state.weaponActivationSerial or 0)+1
					local shell=launchShell(id,tank,origin,direction,true)
					TurretRecoil.kick(tank.state,tank.rattler)
					RattlerRecoil.kick(tank.state,tank.rattler.heat,direction)
					shot:FireAllClients(id,shell.position,direction,tank.state.tankType,tank.state.generation,
						{serial=tank.state.flightShotSerial,roll=tank.state.flightRoll},tank.state.weaponId)
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
					prepareShot:FireAllClients(id,tank.state.tankType,tank.state.generation,tank.state.weaponId)
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
                        bwRuntimeState:FireClient(player,id,{generation=tank.state.generation,requestId=tank.bwRunRequestId or 0,configuration=Hardware.copy(tank.hardware or Hardware.forTank(tank.state)),runtime=if tank.bw then tank.bw:diagnostics() else nil})
                    end
                end
            end
        end
        local battleStates={}
		for owner,battle in battles do battleStates[tostring(owner)]={selected=battle.selected,winner=battle.winner,multiplayer=battle.multiplayer} end
		snapshot:FireAllClients(states,battleStates)
	end
end)

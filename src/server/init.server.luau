local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local studio=RunService:IsStudio()
local profileBegin=debug.profilebegin or function()end
local profileEnd=debug.profileend or function()end
local function startup(stage) if RunService:IsStudio() then print("[BattleWorks startup/server] "..stage) end end
startup("server started")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.TankConfig)
local ArenaLayout = require(Shared.ArenaLayout)
local Environment = require(Shared.Environment)
local Playground=require(Shared.PlaygroundTerrain)
local WorldSettings = require(Shared.WorldSettings)
local EnvironmentBuilder = require(script.EnvironmentBuilder)
local mapSize = Vector2.new(Config.ArenaLimit*2, Config.ArenaLimit*2)
local weather=workspace:GetAttribute("ArenaWeather") or "Normal"
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
local storage=game:GetService("ServerStorage")
local studioConfiguration=if storage then storage:FindFirstChild("BattleWorksStudio") else nil
local RoyaleConfig=require(Shared.BattleRoyaleConfig)
local gameMode=RoyaleConfig.mode(studioConfiguration,workspace:GetAttribute("BattleWorksGameMode"))
local labOwner
if not studio and game.PrivateServerId and game.PrivateServerId~="" and game.PrivateServerOwnerId==0 then
 local arriving=Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
 local join=arriving:GetJoinData()
 local data=join.TeleportData
 if join.SourcePlaceId==game.PlaceId
  and type(data)=="table" and data.mode=="InnovationLab" and data.owner==arriving.UserId then
  gameMode="InnovationLab";labOwner=arriving.UserId
 end
end
local isLab=gameMode=="InnovationLab"
local Lab=if isLab then require(script.InnovationLab) else nil
local lab=Lab and Lab.new(labOwner)
local isRoyale=gameMode=="BattleRoyale" or isLab
local diagnostics
if isRoyale and not isLab and studio then
 local setting=studioConfiguration and studioConfiguration:FindFirstChild("PlaygroundProfileWindowSeconds")
 local window=if setting and setting:IsA("IntValue") then math.clamp(setting.Value,1,30) else 5
 diagnostics=require(script.PlaygroundDiagnostics).new(window,os.clock())
end
print(string.format("[BattleWorks build] revision=%s mode=%s workspaceOverride=%s",RoyaleConfig.Revision,gameMode,tostring(workspace:GetAttribute("BattleWorksGameMode"))))
local royale
Players.CharacterAutoLoads = false -- enable native spawns after arena/pool initialization
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
local royaleControl=remote("RoyaleControl")
local royaleSprint=if isRoyale then remote("RoyaleSprint") else nil
local labTravel=if isRoyale then remote("InnovationLabTravel") else nil
local courseAction=if isRoyale and not isLab then remote("ProvingGroundsAction") else nil
network:SetAttribute("GameMode",gameMode)
network:SetAttribute("PlaygroundBWEnabled",isLab or not isRoyale or RoyaleConfig.bwEnabled(studioConfiguration))
local bwExecution
if diagnostics and network:GetAttribute("PlaygroundBWEnabled") then
 bwExecution=remote("PlaygroundBWExecution")
 bwExecution:SetAttribute("Enabled",true)
end
network:SetAttribute("BuildRevision",RoyaleConfig.Revision)
local sessions = {}
local playerWorlds
local bwOutput=remote("BWOutput")
local bwHardware=remote("BWHardware")
local garage=Instance.new("RemoteFunction");garage.Name="GarageConfiguration";garage.Parent=network
local bwRuntimeState=remote("BWRuntimeState")
local Hardware=require(Shared.BWChassis)
network.Parent = ReplicatedStorage
local tanks, targets, battles = {}, {}, {}
local shells = {}
local editorPreview=workspace:FindFirstChild("BattleWorksEditorPreview"); if editorPreview then editorPreview:Destroy() end
local arena = Instance.new("Folder")
arena.Name = "Arena"; arena.Parent = workspace
local editorMetadata=if not isLab and studioConfiguration then studioConfiguration:FindFirstChild("EditorAssetCatalog") else nil
if editorMetadata then
 startup("publishing editor asset library")
 local ok,reason=pcall(function() require(script.EditorAssetCatalog).publish(storage,ReplicatedStorage,editorMetadata,game:GetService("HttpService")) end)
 if ok then startup("editor asset library ready") else warn("BattleWorks editor library unavailable: "..tostring(reason)) end
end
local publishedWorld=if studioConfiguration then studioConfiguration:FindFirstChild("PublishedWorld") else nil
local productionWorld=if not RunService:IsStudio() and publishedWorld and publishedWorld:IsA("StringValue") and publishedWorld.Value~="" then publishedWorld.Value else nil
if not isLab and (studio or productionWorld) then
 local selection=require(script.StudioWorldSelector).start(RunService,storage,arena,nil,productionWorld)
 singleModelWorld=selection.active.profile=="single-model"
 worldObjects=selection.objects
 worldSettings=selection.active.settings
 if worldSettings then mapSize=Vector2.new(worldSettings.width,worldSettings.depth) end
end
-- The imported-asset world uses ground/boundaries and registered model placements.
-- Normal arena creation, including weather and terrain, is unchanged.
if singleModelWorld or isLab then weather="Normal" end
if isLab then mapSize=Lab.Size
elseif isRoyale and not worldSettings and not singleModelWorld then mapSize=Playground.DefaultSize end
local function createEnvironment(size)
 local data=Environment.create(size,weather)
 if singleModelWorld or isLab then data.rocks={}; data.logs={}; data.trees={}; data.zones={} end
 if worldSettings then data.zones=table.clone(worldSettings.zones);data.startPositions=worldSettings.spawns end
 if isRoyale and not isLab and not worldSettings then
  Playground.configure(data,size)
 end
 data.worldObjects=worldObjects
 return data
end
environment=createEnvironment(mapSize)
local course=if environment.playground and environment.playground.course then require(script.ProvingGrounds).new(environment.playground.course) else nil
arena:SetAttribute("DebugCombat", false)
arena:SetAttribute("Weather",weather)
if environment.wind then
 arena:SetAttribute("WindMaxForce",environment.wind.maxForce)
 arena:SetAttribute("WindDriftSpeed",environment.wind.driftSpeed)
end
local function part(name, size, position, color, deferParent)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.Size = size; p.Position = position; p.Color = color
	if not deferParent then p.Parent = arena end
	return p
end
if course then
 for i=1,3 do
  local target=part("CourseTarget",Vector3.new(3,5,5),course.layout.range+Vector3.new(i*6,3.2,(i-2)*10),Color3.fromRGB(248,126,64))
  target.CanCollide=false;target:SetAttribute("ScannerType","object")
  course.targets[target]=i
 end
end
-- Build the ground with the arena rather than relying on an optional place
-- Baseplate or Terrain. Its top is exactly the simulation's ground plane Y=0.
local floor = part("Floor", Vector3.new(240, 1, 240), Vector3.new(0, -0.5, 0), Color3.fromRGB(100, 112, 86))
floor.Material = Enum.Material.Concrete
floor.Transparency = 0
floor.CanCollide = isRoyale -- native characters need ground; scripted tanks remain non-collidable
floor.CanTouch = false
floor.CanQuery = true -- downward combat rays should still hit the ground
floor.Material = Enum.Material.Grass
EnvironmentBuilder.build(arena,environment,floor)
if environment.playground then require(script.PlaygroundBuilder).build(arena,environment.playground,floor)end
if isLab then
 floor.Size=Vector3.new(mapSize.X+8,1,mapSize.Y+8)
 floor.Material=Enum.Material.Concrete
 floor.Color=Color3.fromRGB(120,127,130)
elseif worldSettings then
 floor.Size=Vector3.new(mapSize.X+10,1,mapSize.Y+10)
 floor.Material=Enum.Material[worldSettings.ground.material]
 floor.Color=Color3.fromRGB(table.unpack(worldSettings.ground.color))
end
if not isLab and not singleModelWorld and not environment.playground then
 local stick=part("CenterStick",Vector3.new(10,1,1),Vector3.new(0,.5,0),Color3.fromRGB(125,79,40))
 stick.Shape=Enum.PartType.Cylinder; stick.Material=Enum.Material.Wood
 stick.CanCollide=false; stick.CanTouch=false; stick.CanQuery=false
end
local walls = {}
for _, data in ipairs({ {Vector3.new(0, 3, -118), Vector3.new(240, 6, 4)}, {Vector3.new(0, 3, 118), Vector3.new(240, 6, 4)}, {Vector3.new(-118, 3, 0), Vector3.new(4, 6, 240)}, {Vector3.new(118, 3, 0), Vector3.new(4, 6, 240)} }) do
	table.insert(walls, part("Boundary", data[2], data[1], Color3.fromRGB(57, 66, 73)))
end
if isLab then
 for i,wall in walls do
  local axis=if i<=2 then mapSize.Y else mapSize.X
  local edge=(axis/2+2)*(if i%2==1 then -1 else 1)
  wall.Size=if i<=2 then Vector3.new(mapSize.X+8,16,4) else Vector3.new(4,16,mapSize.Y)
  wall.Position=if i<=2 then Vector3.new(0,8,edge) else Vector3.new(edge,8,0)
 end
elseif worldSettings or environment.playground then
 walls[1].Size=Vector3.new(mapSize.X+10,6,4); walls[1].Position=Vector3.new(0,3,-mapSize.Y/2-3)
 walls[2].Size=walls[1].Size; walls[2].Position=Vector3.new(0,3,mapSize.Y/2+3)
 walls[3].Size=Vector3.new(4,6,mapSize.Y+10); walls[3].Position=Vector3.new(-mapSize.X/2-3,3,0)
 walls[4].Size=walls[3].Size; walls[4].Position=Vector3.new(mapSize.X/2+3,3,0)
end
local scannerScene=require(script.ScannerScene).new(arena,workspace,floor,tanks,targets)
local function buildTargets(size)
 if isLab or singleModelWorld then return end
	local locations=environment.playground and environment.playground.targets
 local count = if locations then #locations else math.clamp(math.floor((size.X-10)/9),1,5)
	for i = 1, count do
		local p = part("Target", Vector3.new(7, 7, 5), Vector3.new((i-(count+1)/2)*math.min(18,(size.X-10)/count), 3.5, -size.Y*65/230), Color3.fromRGB(210, 102, 60),true)
		scannerScene:markDynamic(p);p.Parent=arena
		if locations then local location=locations[i];p.Position=Vector3.new(location.x,location.y,location.z);p:SetAttribute("PracticeTargetId",location.id)
  elseif environment.playground then p.Position=Vector3.new(38+(i-1)*16,3.5,-90)end
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
local function bwClock(tank)
 return if diagnostics and tank.state.controlMode=="Auto" then diagnostics.clock else simulationTime
end
local scanner=DirectionalScanner.new(workspace,function()return scannerScene:read()end)
local function executeScan(tank,angle,hardware,observationTime)
 local started=if diagnostics then os.clock() else 0
 profileBegin("BattleWorks.Scan")
 local observation,reason=scanner:execute(tank,angle,simulationTime,hardware,observationTime)
 profileEnd()
 if diagnostics then diagnostics.scan+=os.clock()-started end
 return observation,reason
end
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
 if isRoyale then
  for _,player in Players:GetPlayers()do
   local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
   if root and not root.Anchored and player.UserId~=tank.characterUserId then table.insert(bodies,VehicleContacts.box("spawn-character",root.Position-Vector3.new(0,3,0),3,3,0,6))end
  end
 end
 local preferred,yaw=Battle.pose(mapSize,tank.spawnIndex,tank.kind)
 if isLab and tank.public then preferred,yaw=Lab.pose(tank.spawnIndex) end
 if environment.playground then preferred=environment.playground.spawns[(tank.spawnIndex-1)%#environment.playground.spawns+1]end
 if worldSettings then
  -- Use authored headings/anchors, then the same bounded fallback search.
  for _,spawn in worldSettings.spawns do
   if spawn.tank==tank.kind then preferred=Vector3.new(table.unpack(spawn.position)); yaw=-math.rad(spawn.heading) end
  end
  local ok,position,heading=pcall(WorldSettings.spawn,worldSettings,tank.kind,tank.spawnIndex,bodies)
  if ok then preferred,yaw=position,heading end
 end
 local function clear(p)
  if Playground.inCourse(environment.playground,p,8) then return false end
  local entry=environment.playground and environment.playground.characterSpawn
  if tank.public and entry and (p-entry).Magnitude<14 then return false end
  if tank.public then
   for _,other in tanks do
    if other~=tank and not other.state.waitingForSpawn and (p-other.state.position).Magnitude<14 then return false end
   end
  end
  if environment.playground and not Playground.safe(environment.playground,p,7)then return false end
  if math.abs(p.X)>mapSize.X/2-7 or math.abs(p.Z)>mapSize.Y/2-7 then return false end
  for _,body in bodies do if not body.plane and WorldSettings.blocked(p,body,7) then return false end end
  return true
 end
 local function supported(p)
  if tank.characterUserId~=nil then
   local height=Environment.sample(environment,p.X,p.Z,p.Y+1.5)
   return Vector3.new(p.X,height,p.Z)
  end
  return p
 end
 if tank.preferred then preferred=tank.preferred end
 preferred=supported(preferred)
 if environment.playground then
  if tank.public and environment.playground.provingGround then
   -- Bounded random candidates use the same land/support/obstacle checks.
   for _=1,160 do
    local x=(math.random()-.5)*(mapSize.X-28);local z=(math.random()-.5)*(mapSize.Y-28)
    local height=Playground.sample(environment.playground,x,z)
    local p=Vector3.new(x,height,z)
    if clear(p)then return p,math.random()*math.pi*2 end
   end
  end
  if clear(preferred)then return preferred,yaw end
  for _,entry in environment.playground.entries do if clear(entry)then return entry,yaw end end
 end
 if clear(preferred) then return preferred,yaw end
 if isRoyale then
  for distance=14,56,14 do for _,offset in {{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1}}do
   local p=supported(preferred+Vector3.new(offset[1]*distance,0,offset[2]*distance))
   if clear(p)then return p,yaw end
  end end
 end
 for z=-mapSize.Y/2+7,mapSize.Y/2-7,14 do
  for x=-mapSize.X/2+7,mapSize.X/2-7,14 do
   local p=supported(Vector3.new(x,0,z))
   if clear(p) then return p,yaw end
  end
 end
 return nil
end
local function removeOwnedShells(id)
 for i=#shells,1,-1 do if shells[i].owner==id then shells[i].model:Destroy(); table.remove(shells,i) end end
end
local function removeTank(id,tank)
 removeOwnedShells(id)
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
local function owned(player,id,epoch)
 if royale then return royale:controlled(player,id,epoch)end
	if id~=nil and type(id)~="string" then return nil end
	local battle=battles[player.UserId]
	return battle and battle.tanks[id or battle.selected]
end
local function zoneAt(position,clearance)
 return Playground.configurationZone(environment.playground,position,clearance)
end
local function autoBlocked(tank)
 local chassis=Components.get(tank.state).Chassis
 local x,z=(chassis.CollisionWidth or chassis.Radius*2)/2,(chassis.CollisionLength or chassis.Radius*2)/2
 local clearance=math.sqrt(x*x+z*z)+VehicleContacts.Skin
 return zoneAt(tank.state.position,clearance)~=nil or Playground.inCourse(environment.playground,tank.state.position,clearance)
end
local function syncConfigurationZone(tank)
 local state=tank.state
 local zone=zoneAt(state.position)
 local id=zone and zone.id
 if state.configurationZone==id then return end
 state.configurationZone=id
 if id and BWController.running(tank) then BWController.stop(tank,"BW is disabled in configuration zones.") end
 BWController.disarm(tank)
end
local function resetOccupiedTank(tank,player)
 tank.characterUserId=player.UserId
 local checkpoint=course and tank.course and course.layout.start
 if checkpoint then
  local safe
  for _,offset in {Vector3.zero,Vector3.new(0,0,-14),Vector3.new(0,0,14),Vector3.new(-14,0,0)} do
   local candidate=checkpoint+offset
   local occupied=false
   for _,other in tanks do
    if other~=tank and other.state.health>0 and (other.state.position-candidate).Magnitude<13 then occupied=true;break end
   end
   if not occupied then safe=candidate;break end
  end
  if not safe then tank.characterUserId=nil;return false end
  checkpoint=safe
 end
 local reset=Battle.resetTank(tank,mapSize,tank.spawnIndex,"Respawned.",checkpoint,if checkpoint then -math.pi/2 else nil)
 tank.characterUserId=nil
 if reset then
  removeOwnedShells(tank.id)
  if checkpoint then course:begin(tank,simulationTime);syncConfigurationZone(tank) end
 end
 return reset
end
local function createTank(id,player,kind,index,assembly)
 local owner=if player then player.UserId else 0

		local size=Components.get(kind).Chassis.Hitbox
		local hitbox=part("TankHitbox",Vector3.new(size.X,size.Y,size.Z),Vector3.zero,Color3.new(),true)
		scannerScene:markDynamic(hitbox);hitbox.Parent=arena
		hitbox.Transparency=1; hitbox.CanCollide=false
		hitbox:SetAttribute("OwnerId",owner); hitbox:SetAttribute("TankId",id)
		local tank={assembly=assembly,public=player==nil,owner=owner,playerName=(if player then player.Name else "Arena"),kind=kind,seed=(math.abs(owner)+(if not player then index*104729 else 0)+(if kind=="Rattler" then 7919 else 0))%2147483646+1,hitbox=hitbox,lastPacket=0}
		tank.worldSettings=worldSettings; tank.worldObjects=worldObjects
  tank.spawnIndex=index; tank.findSpawn=if not player or multiplayer or (worldSettings and WorldSettings.numbered(worldSettings)) then findSpawn else nil
		if not Battle.resetTank(tank,mapSize,index,"Battle started.") then
   if not player then hitbox:Destroy();return nil end
   -- A full authored map leaves the player waiting for a free spawn, with no
   -- targetable or controllable body. Retry through the normal respawn path.
   tank.findSpawn=function() return Battle.pose(mapSize,index,tank.kind) end
   Battle.resetTank(tank,mapSize,index,"Waiting for a safe spawn.")
   tank.findSpawn=findSpawn; tank.state.health=0; tank.hitbox.CanQuery=false
   tank.state.waitingForSpawn=true
   tank.respawnAt=simulationTime+3
  end
        if player then tank.state.generation=sessions[owner].generation end
		tanks[id]=tank
  local function sendOutput(event)
   event.programSerial=tank.state.bwProgramSerial or 0
   event.programKind=tank.state.bwProgramKind
   event.programName=tank.state.bwProgramName
   local recipient=if tank.public then Players:GetPlayerByUserId(tank.occupant or -1) else player
   if recipient then bwOutput:FireClient(recipient,id,tank.state.generation,tank.bwRunRequestId or 0,event,tank.state.controlEpoch)end
  end
		tank.bwServices={
   outputEnabled=function()return not tank.public or tank.occupant~=nil end,
			getClock=function() return bwClock(tank) end,
            getOwnTank=function()local clock=bwClock(tank);return tank,clock,math.floor(clock/Config.Step+.5),Config.Step end,
            cancelWeapon=function() tank.pendingShot=nil; tank.rattlerShot=false; tank.state.weaponPreparationRemaining=nil end,
            scan=function(angle,performance,time,hardware)
				local observation,err=executeScan(tank,angle,hardware,bwClock(tank))
				if observation then publishScan(tank,angle,observation,false) end
				return observation,err
			end,
            onEvent=function(event)
                if event.kind~="scan" and event.kind~="print" then sendOutput(event) end
            end,
			onValue=function(observation,line,angle,thread)
                local value=observation.value
                local text
                if value.detections then
                    local lines={string.format("%d detections • range %.6g studs",value.count,value.range)}
                    for index,detection in value.detections do table.insert(lines,string.format("[%d] %s",index-1,ScannerValues.format(detection))) end
                    text=table.concat(lines,"\n")
                else text=ScannerValues.format(value)end
				sendOutput(
					{thread=thread,kind="scan",angle=angle,text=text,timestamp=observation.timestamp,line=line})
			end,
			onPrint=function(text,line,thread)
				sendOutput(
					{thread=thread,kind="print",text=text,timestamp=bwClock(tank),line=line})
			end,
		}
 return tank
end
local function applyGarageConfiguration(player,tank)
 local saved=sessions[player.UserId].garage
 if not saved then return end
 local profile=Components.get(tank.state)
 local configuration=saved[tank.kind.."/"..profile.Installed.Weapon]
 if configuration then
  tank.hardware=Hardware.copy(configuration)
  tank.manualSensors=nil; tank.state.scanManual=nil
  BWController.applyHardware(tank)
 end
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
	for _,kind in {"Boomer","Rattler"}do
  local id=Battle.id(player.UserId,kind)
  local tank=createTank(id,player,kind,spawnCount)
  battle.tanks[id]=tank
  applyGarageConfiguration(player,tank)
 end
end

-- Presence in the experience is separate from participation in a battle.
local function registerPlayer(player)
 if not sessions[player.UserId] then sessions[player.UserId]={lastRequest=0,lastEnter=-math.huge,generation=0} end
 if playerWorlds then playerWorlds:register(player) end
 if royale then royale:register(player)end
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
 if lab and royale then lab:clear(royale,player,true) end
 if royale then royale:remove(player)else leaveBattle(player)end
 sessions[player.UserId]=nil
 if playerWorlds then playerWorlds:remove(player) end
end)
for _,player in Players:GetPlayers() do registerPlayer(player) end
local function saveGarage(session,key,draft,vehicle,tier)
 if isRoyale and type(draft)=="table" and type(draft.allocations)=="table" and draft.allocations.retaliatorMesh~=nil then
  return nil,"Retaliator Mesh is available in the Innovation Lab."
 end
 local configuration,reason=Hardware.fromCategories(draft,vehicle,tier)
 if not configuration then return nil,reason end
 session.garage=session.garage or {}
 session.garage[key]=configuration
 return configuration
end
garage.OnServerInvoke=function(player,action,key,draft,epoch)
 if isLab then return {ok=false,message="Lab equipment is set by the experiment."} end
 local session=sessions[player.UserId]
 if session and (action=="ReadZone" or action=="SaveZone") then
  local tank=royale and royale:controlled(player,key,epoch)
  if not tank or tank.state.controlMode~="Manual" or BWController.running(tank) or not zoneAt(tank.state.position) then
   return {ok=false,message="Manually occupy a tank inside a configuration zone."}
  end
  local vehicle=Components.get(tank.state)
  local tier=vehicle.Computer.Tier
  local weapon=vehicle.Installed.Weapon
  if action=="ReadZone" then
   return {ok=true,choices={{id=key,kind=tank.kind,weapon=weapon,tier=tier,assembly=tank.assembly,allowRetaliatorMesh=false,
    current=Hardware.copy(tank.hardware),draft=Hardware.categoryDraft(tank.hardware)}}}
  end
  local kind=if type(draft)=="table" and draft.kind~=nil then draft.kind else tank.kind
  local nextWeapon=if type(draft)=="table" and draft.weapon~=nil then draft.weapon else weapon
  local swapping=kind~=tank.kind or nextWeapon~=weapon
  local assembly
  if swapping then
   assembly=Components.zoneAssembly(tank.assembly,kind,nextWeapon)
   if not assembly then return {ok=false,message="Choose a supported drivetrain and weapon."} end
   local state=tank.state
   if not state.linearVelocity or state.linearVelocity.Magnitude>.5 or (state.angularVelocity and state.angularVelocity.Magnitude>.1) or (state.lift or 0)>.05 then
    return {ok=false,message="Bring the tank to a complete stop before changing equipment."}
   end
   vehicle=Components.resolve(assembly)
  end
  local configuration,reason=saveGarage(session,kind.."/"..nextWeapon,draft,vehicle,tier)
  if not configuration then return {ok=false,message=reason} end
  if swapping then
   local previous=tank.state
   tank.assembly=assembly;tank.kind=kind;tank.hardware=configuration
   Battle.resetTank(tank,mapSize,tank.spawnIndex,"Equipment changed.",previous.position,previous.yaw)
   local state=tank.state
   state.health=math.min(previous.health,vehicle.Chassis.Health)
   for _,key in {"public","controlEpoch","occupantUserId","controlMode","personalityName","personalityId","personalityHash","configurationZone","damageByWeapon","course"} do state[key]=previous[key] end
   tank.slot.generation=state.generation
   tank.lastInput=-math.huge;tank.tickCommand=nil;tank.lastBWRequest=0
   DamageEffects.severity(state)
   removeOwnedShells(tank.id)
  end
  BWController.clearInputs(tank)
  applyGarageConfiguration(player,tank)
  return {ok=true,draft=Hardware.categoryDraft(configuration),kind=kind,weapon=nextWeapon,assembly=tank.assembly}
 end
 if not session or battles[player.UserId] then return {ok=false,message="Open Garage from Main Menu."} end
 if action~="Read" and action~="Save" then return {ok=false,message="Invalid request."} end
 if action=="Save" and type(key)~="string" then return {ok=false,message="Invalid loadout."} end
 local choices={}
 for _,kind in {"Boomer","Rattler"} do
  local base=Components.get(kind)
  local weapons=if isRoyale then {"weapon.cannon","weapon.gatling"} else {base.Installed.Weapon}
  for _,weapon in weapons do
   local id=kind.."/"..weapon
   local vehicle=Components.forWeapon(kind,weapon)
   local tier=if isRoyale then "Bunny" else vehicle.Computer.Tier
   if action=="Save" and key==id then
    local configuration,reason=saveGarage(session,id,draft,vehicle,tier)
    if not configuration then return {ok=false,message=reason} end
    return {ok=true,draft=Hardware.categoryDraft(configuration)}
   elseif action=="Read" then
    local saved=session.garage and session.garage[id]
    local original=if isRoyale then Hardware.playgroundDefault(vehicle) else Hardware.forTank(kind)
    choices[#choices+1]={id=id,kind=kind,weapon=weapon,tier=tier,allowRetaliatorMesh=not isRoyale,draft=Hardware.categoryDraft(saved or original)}
   end
  end
 end
 if action=="Read" then return {ok=true,choices=choices} end
 return {ok=false,message="Invalid loadout."}
end
battleSession.OnServerEvent:Connect(function(player,action,requestId)
 if isRoyale then return end
 local session=sessions[player.UserId]
 if not session or (action~="Enter" and action~="Leave") or type(requestId)~="number"
  or requestId~=requestId or requestId%1~=0 or requestId<1 or requestId>1000000000 or requestId<=session.lastRequest then return end
 session.lastRequest=requestId
 if action=="Leave" then
  leaveBattle(player)
 elseif not battles[player.UserId] then
  if playerWorlds and not playerWorlds:canEnter(player) then
   battleSession:FireClient(player,requestId,false,playerWorlds:entryMessage())
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
input.OnServerEvent:Connect(function(player,value,id,epoch)
	local battle=battles[player.UserId]
	local tank=owned(player,id,epoch)
	local now=os.clock()
	if not tank or (id and id~=battle.selected) or tank.state.health<=0 or (BWController.running(tank)or tank.state.controlMode=="Auto") or now-tank.lastPacket<1/60 then return end
	tank.lastPacket=now
	local command=Command.validate(value)
	if command then
		tank.command=command; tank.lastInput=now
		if tank.requireFireRelease and not command.fire then tank.requireFireRelease=false end
	end
end)
selectTank.OnServerEvent:Connect(function(player,kind)
 if isRoyale then return end
	local battle=battles[player.UserId]
	if not battle or (kind~="Boomer" and kind~="Rattler") then return end
 Battle.select(battle,kind)
end)
local function acceptBWRequest(tank,id)
	if type(id)~="number" or id~=id or id%1~=0 or id<1 or id>1000000000 or id<=(tank.lastBWRequest or 0) then return false end
	tank.lastBWRequest=id; tank.state.bwRequestId=id
	return true
end
bwRun.OnServerEvent:Connect(function(player,source,requestId,id,epoch)
	local tank=owned(player,id,epoch)
	local now=os.clock()
	if not tank or not acceptBWRequest(tank,requestId) then return end
	if autoBlocked(tank) then
		BWController.reject(tank,"Drive clear of the configuration zone or course before running BW.")
		return
	end
	if not network:GetAttribute("PlaygroundBWEnabled") then
		BWController.reject(tank,"Playground BW execution is disabled for this server.")
		return
	end
	-- An occupant's source must never be replaced by the public Auto retry loop.
 tank.autonomyActive=false;tank.autoRestartAt=nil
 tank.state.bwProgramKind="Player";tank.state.bwProgramName="Editor program"
	if now-(tank.lastBWRun or -math.huge)<0.5 then
		BWController.reject(tank,"Wait half a second between Run requests.")
		return
	end
	tank.lastBWRun=now
 local ok=BWController.start(tank,source)
 if tank.personality and ok then
  tank.occupantBWSource=source
  tank.state.controlMode="Auto"
 end
end)
bwStop.OnServerEvent:Connect(function(player,requestId,id,epoch)
	local tank=owned(player,id,epoch)
	if tank and acceptBWRequest(tank,requestId) then BWController.stop(tank,"Stopped by player.");tank.autonomyActive=false;if tank.personality then tank.state.controlMode="Manual";tank.autoRestartAt=nil end end
end)
-- Re-request private source after a lease ACK or reopening the editor. The first
-- delivery may precede the client's control ACK; no source goes to nonoccupants.
bwRuntimeState.OnServerEvent:Connect(function(player,action,id,epoch)
 if action~="Source"then return end
 local tank=owned(player,id,epoch);if not tank then return end
 local now=os.clock()
 if tank.sourceRequestEpoch==tank.state.controlEpoch and now-(tank.lastSourceRequest or -math.huge)<.5 then return end
 tank.sourceRequestEpoch=tank.state.controlEpoch;tank.lastSourceRequest=now;tank.sourceDelivery=nil
end)
bwHardware.OnServerEvent:Connect(function(player,configuration,id,epoch)
 local tank=owned(player,id,epoch); if not tank then return end
 local now=os.clock(); if now-(tank.lastHardwareRequest or -math.huge)<0.25 then return end
 tank.lastHardwareRequest=now
 if isRoyale then
  bwRuntimeState:FireClient(player,id,{controlEpoch=tank.state.controlEpoch,configuration=Hardware.copy(tank.hardware),configurationResult="Use the Garage to configure a Playground loadout."})
  return
 end
 local ok,reason=BWController.configure(tank,configuration)
 bwRuntimeState:FireClient(player,id,{configuration=Hardware.copy(tank.hardware or Hardware.forTank(tank.state)),configurationResult=if ok then "success" else reason,controlEpoch=tank.state.controlEpoch})
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
local function addShellVisual(shell,id,small)
 shell.visualScale=if small then .4 else 1
 local scale=shell.visualScale
 shell.model=Instance.new("Model");shell.model.Name="Shell_"..id;shell.model.Parent=shellFolder
 shell.body=shellPart(shell.model,"Body",Vector3.new(1.5,1.3,1.3)*scale,Color3.fromRGB(77,87,57),Enum.PartType.Cylinder)
 shell.nose=shellPart(shell.model,"Nose",Vector3.new(1.3,1.3,1.3)*scale,Color3.fromRGB(244,158,36),Enum.PartType.Ball)
 shell.band=shellPart(shell.model,"Band",Vector3.new(.3,1.4,1.4)*scale,Color3.fromRGB(255,215,64),Enum.PartType.Cylinder)
 poseShell(shell);table.insert(shells,shell)
end
local function launchShell(id, tank, origin, direction, deferEffects)
	-- Spawn at the muzzle after checking the pivot-to-tip path for cover.
	tank.state.weaponShotSerial=(tank.state.weaponShotSerial or 0)+1
	local tuning = Components.get(tank.state).Weapon
 if zoneAt(tank.state.position) or zoneAt(origin) or zoneAt(origin+direction*tuning.MuzzleOffset) then return nil end
 local airborne,ground=Simulation.projectileFlight(tank.state)
 local flight={physical=true,speed=tank.state.projectileSpeed,muzzleHeight=Components.get(tank.state).Turret.MuzzleHeight,airborne=airborne,findGround=if worldObjects then function(position,heading,range,radius,baseline)
  return worldObjects:projectileGround(position,heading,range,radius,baseline)
 end else nil}
	local shell, blocked = Projectiles.launch(workspace,origin,direction,{tank.hitbox,shellFolder},tuning,ground,flight)
	local small = Components.get(tank.state).Weapon.Operation=="Heat"
	shell.pendingHit = blocked
 if blocked and environment.playground and environment.playground.configurationZones then
  local victim=tanks[blocked.Instance:GetAttribute("TankId") or ""]
  shell.pendingHitProtected=victim and victim.state.configurationZone~=nil
 end
	shell.owner = id
	shell.courseRun=tank.course
	shell.scoreOwner = if royale then royale:scoreActor(tank) else nil
	shell.weaponType=Components.get(tank.state).Weapon.WeaponType
	addShellVisual(shell,id,small)
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
		local protected = shell.pendingHitProtected
		shell.pendingHit = nil
		shell.pendingHitProtected = nil
		if not hit then hit = Projectiles.step(workspace,shell,Config.Step) end
		poseShell(shell)
		if hit then
   if course then course:hit(hit.Instance,tanks[shell.owner],shell.courseRun) end
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
					local battle=if other.public then royale.battle else battles[other.owner]
                    local applied=false
                    if not protected then
                     if shell.owner=="course:emitters" then
                      if other.course and other.course.phase=="Bullet Gauntlet" then applied=Battle.courseProjectileDamage(battle,other,shell.damage,hit.Position,shell.direction) end
                     elseif not shell.courseRun and not other.course then
                      applied=Battle.damage(battle,other,tanks[shell.owner],shell.damage,shell.weaponType,hit.Position,shell.direction)
                     end
                    end
					if applied and multiplayer and other.state.health<=0 then
                        if other.public then royale:destroyed(other,shell.scoreOwner)else other.respawnAt=simulationTime+3 end
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
local gauntletTuning={Range=52,ShellSpeed=34,ShellRadius=.45,Damage=14,MuzzleOffset=0}
local function fireGauntlet()
 for index=0,2 do
  local origin=course.layout.gauntlet+Vector3.new(index*8,2.5,if index%2==0 then -26 else 26)
  local direction=Vector3.new(0,0,if index%2==0 then 1 else -1)
  local shell=Projectiles.new(origin,direction,{shellFolder},gauntletTuning)
  shell.owner="course:emitters"
  addShellVisual(shell,shell.owner,false)
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
 if isRoyale then return end
	local battle=battles[player.UserId]
	if not battle or os.clock()-(battle.lastReset or -math.huge)<0.5 then return end
	battle.lastReset=os.clock()
 if battle.multiplayer then return end
 if worldObjects then worldObjects:reset();scannerScene:invalidate() end
 reset(battle,"Battle reset.")
end)
-- Development redraw is server-authoritative and never exposed in published play.
arena:SetAttribute("MapWidth", mapSize.X); arena:SetAttribute("MapDepth", mapSize.Y)
arena:SetAttribute("MapRevision", 0)
if RunService:IsStudio() then
	local redraw = remote("RedrawMap")
	local lastRedraw = -math.huge
	redraw.OnServerEvent:Connect(function(player, size)
		if isRoyale or worldSettings or not battles[player.UserId] or not ArenaLayout.validSize(size) or os.clock()-lastRedraw < 1 then return end
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
		scannerScene:invalidate()
		for _,battle in battles do reset(battle,"Map redrawn.") end
		arena:SetAttribute("Redrawn", true)
		arena:SetAttribute("MapWidth", size.X); arena:SetAttribute("MapDepth", size.Y)
		arena:SetAttribute("MapRevision", arena:GetAttribute("MapRevision")+1)
	end)
end
-- Player worlds are installed only into an empty battlefield. Published launches
-- use a fresh reserved server; Studio uses this same path without teleporting.
local function installPlayerWorld(player,document,specs,settings)
 assert(not isRoyale,"Loading saved worlds into the arena requires Classic game mode. Your saved world is unchanged.")
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
 scannerScene:invalidate()
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
  local context=require(script.WorldTestContext).resolve(RunService,game,studioConfiguration)
  local studio=context.studio
  local teleport=if not studio then game:GetService("TeleportService") else nil
  playerWorlds=require(script.PlayerWorldService).new({
   studio=studio,reserved=context.reserved,testHost=context.testHost,
   placeId=game.PlaceId,http=http,items=require(Shared.CatalogData).decode(library:FindFirstChild("Catalog"),http),assets=storage:FindFirstChild("BattleWorksAssets"),
   store=require(script.PlayerWorldStorage).create(http,studioConfiguration,studio,context),
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
if isRoyale then
 multiplayer=true
 local settings=RoyaleConfig.settings(studioConfiguration)
 local characterEntry=environment.playground and environment.playground.characterSpawn
 local nativeSpawn
 if characterEntry then
  nativeSpawn=Instance.new("SpawnLocation")
  nativeSpawn.Name="PlaygroundCharacterSpawn";nativeSpawn.Neutral=true;nativeSpawn.Duration=0
  nativeSpawn.Size=Vector3.new(6,.2,6);nativeSpawn.Position=characterEntry+Vector3.new(0,.15,0)
  nativeSpawn.Anchored=true;nativeSpawn.Transparency=1
  nativeSpawn.CanCollide=false;nativeSpawn.CanTouch=false;nativeSpawn.CanQuery=false
  nativeSpawn.Parent=arena
 end
 local Characters=require(script.RoyaleCharacters).new(function(preferred,player)
  return findSpawn({kind="Boomer",spawnIndex=1,characterUserId=player and player.UserId,preferred=preferred or characterEntry or Vector3.new(0,0,mapSize.Y*.35)})
 end)
 -- Only native characters collide with this geometry: tank bodies/art remain
 -- anchored/non-collidable and continue through VehicleContacts exclusively.
 for _,p in arena:GetDescendants()do
  if p:IsA("BasePart")and (p.Name=="Boundary" or p.Name=="Rock" or p.Name=="FallenLog" or p.Name=="TreeTrunk")then p.CanCollide=true end
 end
 if worldObjects then worldObjects.characterCollision=true;for _,record in worldObjects.records do worldObjects:sync(record)end end
 local bwEnabled=network:GetAttribute("PlaygroundBWEnabled")
 startup("Playground BW execution enabled: "..tostring(bwEnabled))
 royale=require(script.BattleRoyale).new({count=if lab then 0 else settings.count,delay=settings.delay,
  autonomy=if lab then Lab.autonomy elseif bwEnabled and settings.personalities then require(script.PlaygroundAutonomy)else nil,tanks=tanks,characters=Characters,
  startInMenu=isLab,loadout=Lab and Lab.loadout,
  nativeSpawn=nativeSpawn,
  beforeJoin=if lab then function(member,id)return lab:start(royale,member,id)end else nil,
  onMenu=if lab then function(player)lab:clear(royale,player)end else nil,
  hazard=function(position)return environment.playground and Playground.hazard(environment.playground,position)end,
  autoBlocked=autoBlocked,
  safeExit=function(tank)
   if not environment.playground then return true end
   local p=tank.state.position
   local v=require(Shared.VehicleMotion).ensure(tank.state)
   local landing=p+Vector3.new(v.X,0,v.Z)*.7
   return Playground.safe(environment.playground,p,5,true)and Playground.safe(environment.playground,landing,5,true)
  end,
  clock=function()return simulationTime end,
  autonomyClock=if diagnostics then function()return diagnostics.clock end else nil,
  create=function(id,kind,index,assembly)return createTank(id,nil,kind,index,assembly)end,remove=removeTank,
  respawn=if lab then nil else resetOccupiedTank,
  admit=function(player,member)battles[player.UserId]={owner=player.UserId,index=player.UserId,tanks={},multiplayer=true,royale=true,controlRevision=member.revision}end,
  depart=function(player)battles[player.UserId]=nil end,
  select=function(player,tank,member,preserveHardware)
   local battle=battles[player.UserId];battle.tanks={};battle.selected=if tank then tank.id else nil;battle.controlRevision=member.revision
   if tank then
    battle.tanks[tank.id]=tank
    if not preserveHardware and not isLab and tank.state.controlMode=="Manual" then applyGarageConfiguration(player,tank) end
   end
  end,
  notify=function(player,reading)royaleControl:FireClient(player,reading)end,
 })
 for _,player in Players:GetPlayers()do royale:register(player)end
 Players.CharacterAutoLoads=true
 for _,player in Players:GetPlayers()do
  if not player.Character then task.spawn(function()
   if sessions[player.UserId] and not player.Character then
    local ok,reason=pcall(player.LoadCharacterAsync,player)
    if not ok then warn("BattleWorks character spawn failed: "..tostring(reason))end
   end
  end)end
 end
 royaleControl.OnServerEvent:Connect(function(player,...)royale:request(player,...)end)
 if course and courseAction then
  courseAction.OnServerEvent:Connect(function(player,action,id,epoch)
   local tank=royale:controlled(player,id,epoch)
   if not tank or not tank.course or tank.state.controlMode~="Manual" or (action~="Restart" and action~="Return") then return end
   if simulationTime<(tank.courseActionAt or 0) then return end
   tank.courseActionAt=simulationTime+1
   local run=tank.course
   if action=="Return" then tank.course=nil end
   if resetOccupiedTank(tank,player) then
    royale:seatReplacement(royale.members[player.UserId],tank,if action=="Return" then "Returned to the Playground." else "Course restarted.")
   else tank.course=run end
  end)
 end
 local teleport=if not studio then game:GetService("TeleportService") else nil
 if teleport then
  teleport.TeleportInitFailed:Connect(function(player,_,message)
   local session=sessions[player.UserId]
   if session and session.labTravel then session.labTravel=nil;labTravel:FireClient(player,message)end
  end)
 end
 labTravel.OnServerEvent:Connect(function(player,action)
  local session=sessions[player.UserId]
  if not session or Players:GetPlayerByUserId(player.UserId)~=player or session.labTravel
   or action~=(if lab then "Return" else "Enter") then return end
  if not teleport then
   labTravel:FireClient(player,if lab then "In Studio, restart Play with GameMode set to BattleRoyale." else "In Studio, restart Play with GameMode set to InnovationLab.")
   return
  end
  session.labTravel=true
  local ok=pcall(function()
   local options=Instance.new("TeleportOptions")
   if lab then options.ForcePublicServer=true
   else
    options.ReservedServerId=game:GetService("HttpService"):GenerateGUID(false)
    options:SetTeleportData({mode="InnovationLab",owner=player.UserId})
   end
   teleport:TeleportAsync(game.PlaceId,{player},options)
  end)
  if not ok then session.labTravel=nil;labTravel:FireClient(player,"Travel failed. Try again.") end
 end)
 royaleSprint.OnServerEvent:Connect(function(player,enabled,revision)royale:sprint(player,enabled,revision)end)
 if bwExecution then
  bwExecution.OnServerEvent:Connect(function(player,enabled)
   if not RunService:IsStudio() or Players:GetPlayerByUserId(player.UserId)~=player
    or type(enabled)~="boolean" or enabled==diagnostics.enabled then return end
   diagnostics.enabled=enabled
   diagnostics:reset(os.clock())
   if not enabled then
    for _,tank in tanks do
     if tank.state.controlMode=="Auto" then BWController.suspendInputs(tank) end
    end
   end
   bwExecution:SetAttribute("Enabled",enabled)
  end)
 end
end
local layout=if isLab then "InnovationLab"elseif environment.playground and environment.playground.provingGround then "ProvingGround"elseif worldSettings or singleModelWorld then "AuthoredWorld"elseif environment.playground then "LegacyPlayground"else "ClassicArena"
local publicCount,autoCount=0,0
for _,tank in tanks do if tank.public then publicCount+=1;if tank.state.controlMode=="Auto"then autoCount+=1 end end end
arena:SetAttribute("BuildRevision",RoyaleConfig.Revision);arena:SetAttribute("StartupLayout",layout)
arena:SetAttribute("StartupPublicTanks",publicCount);arena:SetAttribute("StartupAutoTanks",autoCount)
print(string.format("[BattleWorks ready] revision=%s mode=%s layout=%s world=%s size=%dx%d publicTanks=%d autoTanks=%d",RoyaleConfig.Revision,gameMode,layout,tostring(arena:GetAttribute("WorldId")or"default"),mapSize.X,mapSize.Y,publicCount,autoCount))
startup("arena and battle services ready")
local accumulator, snapshotClock = 0, 0
RunService.Heartbeat:Connect(function(dt)
	profileBegin("BattleWorks.ServerHeartbeat")
	accumulator += math.min(dt, 0.1)
	local buffered,steps=accumulator,0
	while accumulator >= Config.Step do
		profileBegin("BattleWorks.FixedStep")
		accumulator -= Config.Step
		steps+=1
		local now = os.clock()
        local paused=diagnostics~=nil and not diagnostics.enabled
        local bwTime=0
        if diagnostics then diagnostics.scan=0 end
  if royale then royale:step(paused)end
		for p, target in targets do PracticeTargets.update(p, target, now, tanks) end
		for id, tank in tanks do
			if not tank.public and tank.respawnAt and simulationTime>=tank.respawnAt then
                if not Battle.resetTank(tank,mapSize,battles[tank.owner].index,"Respawned.") then tank.respawnAt=simulationTime+1 end
            end
            DamageEffects.step(tank.effects,tank.state,Config.Step)
            local visual=tank.state.scanVisual
			if visual then visual.remaining=math.max(0,visual.remaining-Config.Step); if visual.remaining==0 then tank.state.scanVisual=nil end end
            for key,event in tank.state.scanBW or {} do
                event.remaining=math.max(0,event.remaining-Config.Step)
                if event.remaining==0 then tank.state.scanBW[key]=nil end
            end
            if tank.state.scanBW and next(tank.state.scanBW)==nil then tank.state.scanBW=nil end
			local command
			if tank.state.health<=0 then
				command=Command.neutral()
			elseif paused and tank.state.controlMode=="Auto" then
				command=tank.command -- Neutralized on pause or when Auto started.
			elseif diagnostics and BWController.running(tank) then
				local started,scanBefore=os.clock(),diagnostics.scan
				command=BWController.input(tank,Config.Step)
				bwTime+=math.max(0,os.clock()-started-(diagnostics.scan-scanBefore))
			else
				command=BWController.input(tank,Config.Step)
			end
			command=command or (if now - tank.lastInput <= Config.InputTimeout then tank.command else Command.neutral())
			tank.tickCommand=command
			local trigger = command.fire and not tank.requireFireRelease and not tank.state.configurationZone
			tank.rattlerShot = RattlerWeapon.step(tank.rattler,Components.get(tank.state).Weapon.Operation=="Heat" and tank.state.health > 0,trigger,Config.Step,tank.state.weaponPerformance)
			tank.state.firing = Components.get(tank.state).Weapon.Operation=="Heat" and tank.rattler.firing
			tank.state.heat = tank.rattler.heat; tank.state.weaponCooldown = tank.rattler.cooldown
		end
		-- BW gets first use of the shared query budget. Manual sweeps run only for
		-- the selected living tank without an active program, never into BW output.
		for id,tank in tanks do
			local battle=battles[tank.occupant or tank.owner]
			ManualScanner.step(tank,battle and battle.selected==id and not BWController.running(tank),simulationTime,Config.Step,
				function(angle)
                    local sensor=math.floor((angle%360+22.5)/45)%8*45
                    local hardware=tank.hardware.devices["sensor"..sensor]
                    if not hardware or hardware.allocation<=0 then return nil end
                    return executeScan(tank,angle,hardware)
                end,
				function(angle,observation) publishScan(tank,angle,observation,true) end)
		end
		-- All BW observations precede movement, so every hitbox/state corresponds
		-- to the same completed simulation timestamp, regardless of table order.
        local physicsStarted=if diagnostics then os.clock() else 0
        profileBegin("BattleWorks.TankSimulation")
        local contactBodies={}
        local contactObstacles=table.clone(VehicleContacts.obstacles(environment,mapSize))
        if worldObjects then for _,body in worldObjects:obstacles() do table.insert(contactObstacles,body) end end
        for p,target in targets do
            if target.health>0 then table.insert(contactObstacles,VehicleContacts.box(target.collisionId,p.Position,p.Size.X/2,p.Size.Z/2,-p.Size.Y/2,p.Size.Y/2)) end
        end
		for id,tank in tanks do
			local command=tank.tickCommand
			tank.state.groundPlaneY=floor.Position.Y+floor.Size.Y/2
            if not tank.state.waitingForSpawn and not tank.state.publicRetired then
                Simulation.step(tank.state, command, Config.Step, mapSize, environment,true)
                local body=VehicleContacts.body(id,tank.state,Components.get(tank.state).Chassis)
                if studio and (tank.occupant or not tank.public) then
                 body.trackContacts=true
                 tank.state.motionDebugThrottle=command.throttle
                end
                body.ignoreConfigurationZones=tank.state.controlMode=="Parked" or (tank.occupant~=nil and tank.state.controlMode=="Manual" and not BWController.running(tank))
                table.insert(contactBodies,body)
            end
        end
        local solverStarted=if diagnostics then os.clock() else 0
        profileBegin("BattleWorks.VehicleContacts")
        VehicleContacts.solve(contactBodies,contactObstacles,Config.Step)
        profileEnd()
        local solverTime=if diagnostics then os.clock()-solverStarted else 0
        for _,record in contactBodies do
            local tank=tanks[record.id]
            Simulation.reconcileGround(tank.state,environment)
            MovementTelemetry.update(tank.state,tank.state.motionStepStart,Config.Step)
            tank.hitbox.CFrame=CFrame.new(tank.state.position+Vector3.new(0,Components.get(tank.state).Chassis.HitboxHeight,0))*CFrame.Angles(0,tank.state.yaw,0)
            tank.hitbox.CanQuery=tank.state.health>0
            if environment.playground and environment.playground.configurationZones then syncConfigurationZone(tank) end
        end
        profileEnd()
        local projectileStarted=if diagnostics then os.clock() else 0
        profileBegin("BattleWorks.Projectiles")
  if course then
   local gauntlet,rangeActive=false,false
   for _,tank in tanks do
    if tank.occupant and tank.state.health>0 then
     local state=tank.state
     if not tank.course and state.controlMode=="Manual" and state.configurationZone=="course:start" then course:begin(tank,simulationTime) end
     if tank.course then
      if not Playground.inCourse(environment.playground,state.position,2) and tank.course.phase~="Complete" then
       tank.course=nil;state.course=nil
      else
       course:advance(tank,simulationTime);course:publish(tank,simulationTime)
       gauntlet=gauntlet or tank.course.phase=="Bullet Gauntlet"
       rangeActive=rangeActive or tank.course.phase=="Moving Target Range"
      end
     end
    end
   end
   if not gauntlet and course.nextVolley~=0 then removeOwnedShells("course:emitters") end
   course:step(simulationTime,fireGauntlet,gauntlet,rangeActive)
  end
		updateShells(now)
		for id, tank in tanks do
			if tank.state.configurationZone or (paused and tank.state.controlMode=="Auto") then continue end
			local command = tank.tickCommand or Command.neutral()
			if Components.get(tank.state).Weapon.Operation=="Heat" then
				if tank.rattlerShot and tank.state.health > 0 then
					local origin,direction = Simulation.shotPose(tank.state)
					tank.state.weaponActivationSerial=(tank.state.weaponActivationSerial or 0)+1
					local shell=launchShell(id,tank,origin,direction,true)
					if not shell then continue end
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
						if launchShell(id,tank,origin,direction) then TurretRecoil.kick(tank.state,tank.boomerAim) end
					end
				end
			end
			if not tank.pendingShot then
				tank.pendingShot = WeaponWindup.begin(tank.state, command)
				if tank.pendingShot then
					tank.state.weaponActivationSerial=(tank.state.weaponActivationSerial or 0)+1
					prepareShot:FireAllClients(id,tank.state.tankType,tank.state.generation,tank.state.weaponId,tank.pendingShot.remaining)
				end
			end
			tank.state.weaponPreparationRemaining=tank.pendingShot and tank.pendingShot.remaining
		end

        profileEnd()
		simulationTime+=Config.Step
		if diagnostics then
			if not paused then diagnostics.clock+=Config.Step end
			local finished=os.clock()
			diagnostics:record(finished,bwTime,diagnostics.scan,projectileStarted-physicsStarted,solverTime,finished-projectileStarted,finished-now)
		end
		profileEnd()
	end
	snapshotClock += dt
	if snapshotClock >= Config.SnapshotInterval then
		profileBegin("BattleWorks.Snapshot")
		snapshotClock %= Config.SnapshotInterval
		local states = {}
		for id, tank in tanks do states[tostring(id)] = tank.state end
		for owner,battle in battles do
            local player=Players:GetPlayerByUserId(owner)
            if player then
                for id,tank in battle.tanks do
                    if simulationTime-(tank.lastDiagnostics or -math.huge)>=0.2 then
                        tank.lastDiagnostics=simulationTime
                        local source=if tank.state.bwProgramKind=="Player" then tank.bwSource
                         elseif tank.occupantBWSource then tank.occupantBWSource
                         elseif tank.personality then tank.personality.source else tank.bwSource
                        local kind=if tank.personality and tank.state.bwProgramKind~="Player" and not tank.occupantBWSource then "Personality" else "Player"
                        local previous=tank.sourceDelivery
                        local delivery
                        if source and(not previous or previous.player~=owner or previous.epoch~=tank.state.controlEpoch or previous.generation~=tank.state.generation or previous.serial~=tank.state.bwProgramSerial or previous.text~=source or previous.kind~=kind)then
                         delivery={text=source,kind=kind,name=if kind=="Personality"then tank.personality.name else "Editor program",programSerial=tank.state.bwProgramSerial or 0}
                         tank.sourceDelivery={player=owner,epoch=tank.state.controlEpoch,generation=tank.state.generation,serial=tank.state.bwProgramSerial,text=source,kind=kind}
                        end
                        bwRuntimeState:FireClient(player,id,{source=delivery,generation=tank.state.generation,requestId=tank.bwRunRequestId or 0,configuration=Hardware.copy(tank.hardware or Hardware.forTank(tank.state)),runtime=if tank.bw then tank.bw:diagnostics() else nil,controlEpoch=tank.state.controlEpoch})
                    end
                end
            end
        end
        local battleStates={}
		for owner,battle in battles do battleStates[tostring(owner)]={selected=battle.selected,winner=battle.winner,multiplayer=battle.multiplayer,royale=battle.royale,controlRevision=battle.controlRevision,score=if royale then royale.scores[owner] else nil} end
		snapshot:FireAllClients(states,battleStates,if royale then royale.scoreRevision else nil,if royale then royale.tankScores else nil)
		profileEnd()
	end
	if diagnostics then
		local now=os.clock()
		diagnostics:heartbeat(now,steps,buffered,accumulator,math.max(0,dt-0.1))
		diagnostics:report(now,tanks)
	end
	profileEnd()
end)

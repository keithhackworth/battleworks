-- Continue the production server harness before boot, supplying native character
-- lifecycle stand-ins and recording public occupancy acknowledgments.
math.randomseed(43)
check(require("BattleRoyaleConfig").mode(nil,nil)=="BattleRoyale","production startup defaults to Royale even without a configuration object")
check(require("BattleRoyaleConfig").mode(nil,"Classic")=="Classic","explicit Classic startup remains available")
check(not pcall(require("BattleRoyaleConfig").mode,nil,"bad"),"invalid startup configuration fails clearly")
require("BattleRoyaleConfig").TankCount=6
require("BattleRoyaleConfig").Personalities=false -- legacy public-pool regression; autonomous default covered separately
workspace:SetAttribute("BattleWorksGameMode","BattleRoyale")
workspace:SetAttribute("ArenaWeather",nil) -- exercise the production default
local controls={}
local tankScores
local Royale=require("BattleRoyale")
local newRoyale=Royale.new
local royale
Royale.new=function(...)
 royale=newRoyale(...)
 return royale
end
local promptFactory=Instance.new
Instance.new=function(class)
 local node=promptFactory(class)
 if class=="ProximityPrompt"then node.Triggered=signal()end
 if class=="RemoteEvent"then
  local fire=node.FireClient
  local fireAll=node.FireAllClients
  node.FireClient=function(self,player,...)
   if self.Name=="RoyaleControl"then controls[player.UserId]=({...})[1]end
   return fire(self,player,...)
  end
  node.FireAllClients=function(self,states,battles,revision,scores,...)
   if self.Name=="Snapshot" then tankScores=scores end
   return fireAll(self,states,battles,revision,scores,...)
  end
 end
 return node
end
local function character(player)
 local root={Name="HumanoidRootPart",CFrame=CFrame.new(0,3,90),Transparency=0,CanCollide=true,CanTouch=true,CanQuery=true,Anchored=false}
 setmetatable(root,{__index=function(self,key)if key=="Position"then return self.CFrame.Position end end})
 function root:IsA(kind)return kind=="BasePart"end
 local humanoid={Name="Humanoid",Health=100,WalkSpeed=16,JumpPower=50,AutoRotate=true,Died=signal()}
 local c={DescendantAdded=signal()};root.Parent=c;humanoid.Parent=c
 function c:FindFirstChild(name)return if name=="HumanoidRootPart"then root elseif name=="Humanoid"then humanoid else nil end
 c.WaitForChild=c.FindFirstChild
 function c:FindFirstChildOfClass()return humanoid end
 function c:GetDescendants()return {root}end
 player.Character=c
 return root,humanoid
end
first.Name="Keith";second.Name="Shane"
first.CharacterAdded=signal();second.CharacterAdded=signal()
local roots,humanoids={},{}
roots[101],humanoids[101]=character(first);roots[102],humanoids[102]=character(second)
local roster=players.GetPlayers
if headlessStartup then players.GetPlayers=function()return {}end end
require("ServerEntrypoint")
Royale.new=newRoyale
if headlessStartup then
 players.GetPlayers=roster;players.PlayerAdded:Fire(first);players.PlayerAdded:Fire(second)
end
local network
for _,p in created do if p.Name=="TankNetwork"then network=p end end
local remote=network:FindFirstChild("RoyaleControl")
local input=network:FindFirstChild("Input")
local bwRun=network:FindFirstChild("BWRun")
local function advance(frames)for _=1,frames do time+=1/60;heartbeat:Fire(1/60)end end
advance(4)
check((network:FindFirstChild("PlaygroundBWExecution")~=nil)==not headlessStartup,"diagnostic remote exists only in Studio")
check(players.CharacterAutoLoads and network:GetAttribute("GameMode")=="BattleRoyale","Royale is native-character automatic admission, not menu admission")
local entryTerrain=require("PlaygroundTerrain")
local layout=entryTerrain.create(entryTerrain.DefaultSize)
check(first.RespawnLocation and first.RespawnLocation==second.RespawnLocation and first.RespawnLocation.Name=="PlaygroundCharacterSpawn","Roblox spawns both avatars at the designated Playground entry")
check(entryTerrain.safe(layout,first.RespawnLocation.Position,7) and not entryTerrain.inCourse(layout,first.RespawnLocation.Position,8),"native entry is on the dry bank outside the course")
check(entryTerrain.safe(layout,roots[101].Position-Vector3.new(0,3,0),7),"server placement keeps the on-foot avatar on supported dry land")
for _,p in created do
 if p.Name=="Arena"then check(p:GetAttribute("Weather")=="Normal","default Royale arena has normal weather")end
 if p.Name=="Floor"then check(p.Material==Enum.Material.Grass,"default Royale floor is grass rather than ice")end
 check(p.Name~="WindArrow" and p.Name~="IceStreak","default arena creates no wind/ice presentation")
end
check(battleStates["101"].royale and battleStates["102"].royale and not battleStates["101"].selected,"both players join on foot without automatic tank control")
check(battleStates["101"].score.kills==0 and battleStates["101"].score.deaths==0,"each Playground server starts with a clean scoreboard")
check(#tankScores==6 and tankScores[1].kills==0 and tankScores[1].deaths==0,"every public tank has a scoreboard row before combat")
check(not snapshots["101"] and not snapshots["101:Rattler"],"no personal collection is allocated")
local ids={};for id in snapshots do table.insert(ids,id)end;table.sort(ids)
check(#ids==6,"configured arena tank pool exists before player entry")
local boxes,prompts={},{}
for _,p in created do if p.Name=="TankHitbox"then boxes[p:GetAttribute("TankId")]=p end end
for id,box in boxes do prompts[id]=box:FindFirstChild("EnterPublicTank");check(prompts[id] and prompts[id].KeyboardKeyCode==Enum.KeyCode.E and prompts[id].GamepadKeyCode==Enum.KeyCode.ButtonX,"public tank has native keyboard/gamepad/touch proximity entry")end
for i,id in ids do
 check(snapshots[id].public and boxes[id]:GetAttribute("OwnerId")==0,"arena ownership is independent from occupancy")
 for j=i+1,#ids do check((snapshots[id].position-snapshots[ids[j]].position).Magnitude>=14,"initial public spawn positions never overlap")end
end
local shapes={}
for _,event in privateRuntime do check(false,"on-foot players receive no private tank diagnostics")end
for i=1,4 do
 local kind,a=require("BattleRoyaleConfig").loadout(i);local resolved=require("VehicleComponents").resolve(a)
 check(resolved.Computer.Tier=="Bunny","all public hardware uses the Bunny computer")
 shapes[resolved.Installed.Mobility..resolved.Installed.Weapon]=true
end
local combinations=0;for _ in shapes do combinations+=1 end;check(combinations==4,"pool provides all supported cannon/Gatling and tracks/wheels combinations")
local a,b=ids[1],ids[2]
local sprint=network:FindFirstChild("RoyaleSprint")
local footRevision=controls[101].revision
sprint.OnServerEvent:Fire(first,true,footRevision-1)
check(humanoids[101].WalkSpeed==16,"stale sprint requests are ignored")
sprint.OnServerEvent:Fire(first,true,footRevision)
check(humanoids[101].WalkSpeed==24,"on-foot sprint increases normal walking speed")
sprint.OnServerEvent:Fire(first,false,footRevision)
check(humanoids[101].WalkSpeed==16,"releasing sprint restores walking speed")
sprint.OnServerEvent:Fire(first,true,footRevision)
local function approach(player,id)roots[player.UserId].CFrame=CFrame.new(snapshots[id].position+Vector3.new(0,3,0))end
local function enter(player,id,requestId)remote.OnServerEvent:Fire(player,"Enter",requestId,id,snapshots[id].controlEpoch);advance(4)end
remote.OnServerEvent:Fire(first,"Enter",1,a,snapshots[a].controlEpoch);advance(4)
check(not controls[101].selected,"server rejects across-map entry despite any client prompt settings")
approach(first,a);approach(second,a)
local initialEpoch=snapshots[a].controlEpoch
remote.OnServerEvent:Fire(first,"Enter",2,a,initialEpoch);remote.OnServerEvent:Fire(second,"Enter",1,a,initialEpoch);advance(4)
check(controls[101].selected==a and not controls[102].selected and snapshots[a].occupantUserId==101,"racing entrants produce exactly one occupant")
check(roots[101].Anchored and roots[101].Transparency==1 and not roots[101].CanCollide and not roots[101].CanQuery and humanoids[101].WalkSpeed==0,"server hides/anchors character while driving without invisible projectile interference")
sprint.OnServerEvent:Fire(first,true,controls[101].revision)
check(humanoids[101].WalkSpeed==0,"sprint requests cannot change tank occupant speed")
local epochA=controls[101].epoch
local bunnyDiagnostics=false
for _,event in privateRuntime do if event.recipient==first and event.args[1]==a and event.args[2].configuration.tier=="Bunny"then bunnyDiagnostics=true end end
check(bunnyDiagnostics,"occupied public tank reports the actual Bunny hardware through production diagnostics")
network:FindFirstChild("BWHardware").OnServerEvent:Fire(second,{},a,epochA)
network:FindFirstChild("BWHardware").OnServerEvent:Fire(first,{tier="Octa"},a,epochA)
-- Production self introspection is scoped to the currently authorized public tank.
local probeBefore=#privateOutputs
bwRun.OnServerEvent:Fire(first,'own = get_tank_state()\nprint(own.coordinates.x)\nprint(own.equipment.Weapon)\nprint(own.simulation.tick)\nprint(own.weapon.readiness.ready)\nprint(own.scanner_count)',1,a,epochA)
advance(55)
local probe={}
for i=probeBefore+1,#privateOutputs do
 local event=privateOutputs[i]
 if event.args[4].kind=="print"then
  check(event.recipient==first and event.args[1]==a,"self state output remains private to the current tank occupant")
  table.insert(probe,event.args[4].text)
 end
end
check(#probe==5 and tonumber(probe[1])==snapshots[a].position.X and probe[2]=="weapon.cannon" and tonumber(probe[3])>=0 and probe[4]=="true"and probe[5]=="8","live server getter supplies actual own pose, canonical equipment, global tick, readiness and scanner metadata")
local noEnemyOutput=#privateOutputs
bwRun.OnServerEvent:Fire(second,'print(get_tank_state())',1,a,epochA);advance(4)
check(#privateOutputs==noEnemyOutput and not snapshots[a].bwRunning,"non-occupant cannot launch private self queries on someone else's public tank")
local move={throttle=1,steer=0,fire=false,aimMode="Rate",turretX=1,turretY=0}
local neutral=require("InputCommand").neutral()
local authorizedPitch=snapshots[a].turretPitch
input.OnServerEvent:Fire(second,{throttle=0,steer=0,fire=true,aimMode="World",aim=Vector3.new(0,100,-100)},a,epochA)
bwRun.OnServerEvent:Fire(second,"turret_up(to=20)",1,a,epochA);advance(4)
check(snapshots[a].turretPitch==authorizedPitch and not snapshots[a].bwRunning,"XYZ aiming and new BW elevation cannot bypass public occupancy authorization")
local before=snapshots[a].position
input.OnServerEvent:Fire(second,move,a,epochA);bwRun.OnServerEvent:Fire(second,"forward(10)",1,a,epochA);advance(8)
check((snapshots[a].position-before).Magnitude<.001 and not snapshots[a].bwRunning,"non-occupants cannot drive, fire or execute BW against public tanks")
for _,bad in {false,{}, {throttle=0/0,steer=0,fire=false},{throttle=1,steer=0,fire="yes"}}do input.OnServerEvent:Fire(first,bad,a,epochA);advance(3)end
check((snapshots[a].position-before).Magnitude<.001,"malformed occupied input is rejected")
input.OnServerEvent:Fire(first,move,a,epochA);advance(8)
check((snapshots[a].position-before).Magnitude>.01,"authorized occupancy drives existing simulation and turret state")
advance(160);local stopped=snapshots[a].position;advance(40)
check((snapshots[a].position-stopped).Magnitude<.01,"existing stale-input timeout still stops public tank commands")
local health=snapshots[a].health;local generation=snapshots[a].generation
remote.OnServerEvent:Fire(first,"Exit",3,a,epochA);advance(4)
check(not controls[101].selected and not snapshots[a].occupantUserId and boxes[a]:FindFirstChild("EnterPublicTank").Enabled,"exit releases occupancy for another player")
check(not roots[101].Anchored and roots[101].Transparency==0 and roots[101].CanCollide and humanoids[101].WalkSpeed==16,"exit restores native character movement/collision")
check(math.abs(roots[101].Position.X-stopped.X)<.01 and math.abs(roots[101].Position.Z-stopped.Z)<.01,"voluntary exit ejects at the tank's current XZ instead of searching/teleporting elsewhere")
check(roots[101].Position.Y>stopped.Y+5 and roots[101].Position.Y<stopped.Y+14 and roots[101].AssemblyLinearVelocity.Y>0,"ejected character starts just above the tank with an upward jump")
check(snapshots[a].health==health and snapshots[a].generation==generation and (snapshots[a].position-stopped).Magnitude<.01,"abandoning preserves physical position, generation and health")
prompts[a].Triggered:Fire(first);advance(4)
check(not controls[101].selected,"a stale native prompt instance cannot reacquire a released tank")
input.OnServerEvent:Fire(first,move,a,epochA);bwRun.OnServerEvent:Fire(first,"fire(10)",2,a,epochA);advance(8)
check(not snapshots[a].firing and not snapshots[a].bwRunning and (snapshots[a].position-stopped).Magnitude<.01,"held/delayed commands cannot control an abandoned tank")
approach(first,b);enter(first,b,4)
check(controls[101].selected==b and not snapshots[a].occupantUserId,"same player can enter a different public tank")
local scoringTank=royale.options.tanks[b]
check(royale:scoreActor(scoringTank)==royale.scores[101],"manual tank credits its driver")
scoringTank.state.controlMode="Auto"
check(royale:scoreActor(scoringTank)==tankScores[scoringTank.slot.index],"occupied Auto tank credits its own row")
scoringTank.state.controlMode="Manual"
approach(second,a);prompts[a]=boxes[a]:FindFirstChild("EnterPublicTank");prompts[a].Triggered:Fire(second);advance(4)
check(controls[102].selected==a,"another player can take the abandoned tank")
local epochB=controls[101].epoch;local epochSecond=controls[102].epoch
remote.OnServerEvent:Fire(first,"Exit",3,b,epochB);advance(4)
check(controls[101].selected==b,"stale request IDs cannot release a newer occupancy")
-- Authoritative projectiles cause cross-player damage; no client hit remote.
local victim=royale.options.tanks[a]
local previousPosition=victim.state.position
local terrainFactory=require("PlaygroundTerrain")
local zone=terrainFactory.create(terrainFactory.DefaultSize).configurationZones[1]
victim.state.position=Vector3.new(zone.x,zone.y,zone.z)
local garage=network:FindFirstChild("GarageConfiguration")
local equipped=garage.OnServerInvoke(second,"SaveZone",a,{allocations={drivetrain=25,turret=15,weapon=20,scanners=15,retaliatorMesh=25},tuning={weapon=.5,scanners=.5}},epochSecond)
check(not equipped.ok and not require("BWChassis").retaliatorOperational(victim.hardware),"Playground rejects lab equipment even on a forged zone save")
do
 local before=victim.state
 local kind=if victim.kind=="Boomer" then "Rattler" else "Boomer"
 local weaponId=if before.weaponId=="weapon.cannon" then "weapon.gatling" else "weapon.cannon"
 local draft={kind=kind,weapon=weaponId,allocations={drivetrain=32,turret=15,weapon=33,scanners=20},tuning={weapon=.35,scanners=.65}}
 local motion=require("VehicleMotion")
 motion.setVelocity(before,Vector3.new(2,0,0))
 check(not garage.OnServerInvoke(second,"SaveZone",a,draft,epochSecond).ok,"moving tanks cannot change physical equipment")
 motion.setVelocity(before,Vector3.zero)
 draft.weapon="weapon.invalid"
 check(not garage.OnServerInvoke(second,"SaveZone",a,draft,epochSecond).ok,"invalid equipment selection is rejected")
 draft.weapon=weaponId
 check(garage.OnServerInvoke(second,"SaveZone",a,draft,epochSecond).ok,"stationary occupant can swap hardware")
 check(victim.state~=before and victim.state.generation==before.generation+1 and victim.state.health==before.health and victim.occupant==102,
  "equipment rebuild keeps health and ownership with a new physical generation")
 local rebuilt=require("VehicleComponents").get(victim.state)
 check(rebuilt.Mobility.Kind==(if kind=="Boomer" then "Tracked" else "Wheeled") and rebuilt.Installed.Weapon==weaponId,
  "new mobility and weapon are installed in the actual simulation")
end
victim.state.position=previousPosition
local hits=0;local weapon=require("VehicleComponents").forWeapon(snapshots[b].tankType,snapshots[b].weaponId).Weapon
local needed=math.ceil(snapshots[a].health/weapon.Damage)
workspace.Spherecast=function(_,origin,_,delta,params)
 if params.FilterDescendantsInstances[1]==boxes[b] and hits<needed then hits+=1;return {Instance=boxes[a],Position=origin+delta.Unit*.01,Distance=.01}end
end
bwRun.OnServerEvent:Fire(first,"fire(10)",1,b,epochB)
for _=1,1800 do advance(1);if snapshots[a].health<=0 then break end end
check(hits==needed and snapshots[a].health==0,"occupied public tanks damage and destroy each other through actual weapon/projectile handling")
check(battleStates["101"].score.kills==1 and battleStates["102"].score.deaths==1,"fatal projectile credits the shooter and the destroyed tank's occupant")
check(not controls[102].selected and humanoids[102].Health==0 and not boxes[a].CanQuery and not prompts[a].Enabled,"destruction releases occupant, kills character for native respawn and disables tank interaction")
input.OnServerEvent:Fire(second,move,a,epochSecond);remote.OnServerEvent:Fire(second,"Enter",3,a,snapshots[a].controlEpoch);advance(8)
check(not controls[102].selected and snapshots[a].health==0,"wreck rejects input and entry")
local deadGeneration=snapshots[a].generation
local Settings=require("WorldSettings");local originalBlocked=Settings.blocked
Settings.blocked=function()return true end
roots[102],humanoids[102]=character(second);second.CharacterAdded:Fire(second.Character)
advance(320)
check(snapshots[a].health==0 and not controls[102].selected,"blocked coordinated respawn waits for a legal spawn")
Settings.blocked=originalBlocked;advance(65)
check(snapshots[a].health==100 and snapshots[a].generation==deadGeneration+1 and snapshots[a].occupantUserId==102,"replacement preserves the slot and automatically seats the former occupant")
check(roots[102].Anchored and (roots[102].Position-snapshots[a].position-Vector3.new(0,3,0)).Magnitude<.01,"character and replacement tank spawn together")
check(controls[102].selected==a and controls[102].controlMode=="Manual","client receives the new Manual lease for camera restoration")
check(victim.hardware.allocations.drivetrain==32 and victim.hardware.tuning.weapon==.35 and victim.state.weaponId==victim.assembly.Weapon,"respawn retains the applied physical equipment and bus configuration")
check(battleStates["102"].score.deaths==1 and battleStates["101"].score.kills==1,"coordinated respawn preserves scores")
remote.OnServerEvent:Fire(second,"Exit",5,a,epochSecond);advance(4)
check(controls[102].selected==a,"old lease cannot exit a replacement tank")
humanoids[102].Health=0;humanoids[102].Died:Fire();advance(4)
check(not controls[102].selected and snapshots[a].health==0,"native character death queues coordinated replacement")
roots[102],humanoids[102]=character(second);second.CharacterAdded:Fire(second.Character);advance(25)
check(controls[102].selected==a and snapshots[a].generation==deadGeneration+2 and not snapshots[a].bwRunning,"repeated deaths produce one new generation each with no orphaned program")
for _,p in created do if p.Name=="TankHitbox" and p:GetAttribute("TankId")==a and not p.destroyed then boxes[a]=p end end
local retaliated=false;local beforeRetaliation=snapshots[b].health
workspace.Spherecast=function(_,origin,_,delta,params)
 if params.FilterDescendantsInstances[1]==boxes[a] and not retaliated then retaliated=true;return {Instance=boxes[b],Position=origin+delta.Unit*.01,Distance=.01}end
end
bwRun.OnServerEvent:Fire(second,"fire()",1,a,controls[102].epoch);advance(90)
check(retaliated and snapshots[b].health==beforeRetaliation-require("VehicleComponents").forWeapon(snapshots[a].tankType,snapshots[a].weaponId).Weapon.Damage,"second occupant retaliates through the same authoritative combat path")
workspace.Spherecast=function()return nil end
-- Late joins share the current pool, and disconnect cannot delete arena tanks.
local third={UserId=103,Name="Late",CharacterAdded=signal()};roots[103],humanoids[103]=character(third)
players.PlayerAdded:Fire(third);advance(4)
check(battleStates["103"].royale and not controls[103].selected and #ids==6,"late join is admitted on foot into the existing public battlefield")
local currentB=controls[101].epoch
local abandonedHealth=snapshots[b].health
local leavingTank=royale.options.tanks[b]
bwRun.OnServerEvent:Fire(first,[[function drive(const event):
    forward()
    wait_for_clock(get_clock().time + 20)
on_event("OnDamageTaken", drive)]],2,b,currentB)
local leavingRuntime=leavingTank.bw
for _=1,2 do check(require("BWController").emitEvent(leavingTank,"OnDamageTaken",{}),"disconnect fixture queues a handler") end
advance(8)
check(snapshots[b].bwRunning and leavingRuntime.devices:busy() and #leavingRuntime.events.queue==1,"disconnect fixture has active and queued BW work")
players.PlayerRemoving:Fire(first);advance(4)
check(snapshots[b] and not snapshots[b].occupantUserId and not snapshots[b].bwRunning and not snapshots[b].firing and not battleStates["101"],"disconnect stops AI/input and releases public tank without deleting it")
check(leavingRuntime.status=="stopped" and #leavingRuntime.events.queue==0 and not leavingRuntime.devices:busy()
 and leavingRuntime.totalCallFrames==0 and leavingTank.bw==nil,"disconnect releases the previous occupant's invocation and all remaining work")
check(snapshots[b].health==abandonedHealth,"release/disconnect never repairs an injured public tank")
local currentA=controls[102].epoch
move.fire=true
input.OnServerEvent:Fire(second,move,a,currentA);advance(4);players.PlayerRemoving:Fire(second);advance(4)
local releasedShots=#shots;advance(30)
check(snapshots[a] and not snapshots[a].occupantUserId and not snapshots[a].bwRunning and not snapshots[a].firing and #shots==releasedShots,"disconnect during movement/firing releases occupancy and cancels pending trigger commands")
players.PlayerRemoving:Fire(third);advance(4)
local remaining=0;for _ in snapshots do remaining+=1 end
check(remaining==6 and next(battleStates)==nil,"empty server keeps only its configured arena pool and no orphaned memberships")
roots[101],humanoids[101]=character(first);players.PlayerAdded:Fire(first);advance(25)
approach(first,b);enter(first,b,1)
check(controls[101].selected==b,"rejoining creates fresh participation and can reuse available arena tanks")
check(battleStates["101"].score.kills==1,"rejoining the same server preserves the player's scoreboard totals")
local rejoinPosition=snapshots[b].position
input.OnServerEvent:Fire(first,move,b,currentB);advance(6)
check((snapshots[b].position-rejoinPosition).Magnitude<.01,"a previous connection's control lease cannot drive after rejoining")
players.PlayerRemoving:Fire(first);advance(4)
-- Main Menu releases control but keeps the shared arena/pool running.
local menuPlayer={UserId=104,Name="Menu Tester",CharacterAdded=signal()}
roots[104],humanoids[104]=character(menuPlayer);players.PlayerAdded:Fire(menuPlayer);advance(25)
local c=ids[3];approach(menuPlayer,c);enter(menuPlayer,c,1)
local menuEpoch=controls[104].epoch;local menuHealth=snapshots[c].health
bwRun.OnServerEvent:Fire(menuPlayer,"forward(100)",1,c,menuEpoch);advance(4)
check(snapshots[c].bwRunning,"menu departure fixture runs occupant BW")
remote.OnServerEvent:Fire(menuPlayer,"Menu",2,c,menuEpoch);advance(4)
check(controls[104].mode=="Menu" and not battleStates["104"] and not snapshots[c].occupantUserId and not snapshots[c].bwRunning,"Main Menu removes participation, stops AI and releases the public tank")
check(roots[104].Anchored and roots[104].Transparency==1 and not roots[104].CanQuery and not roots[104].CanCollide,"menu avatar is parked without collision or invisible projectile cover")
input.OnServerEvent:Fire(menuPlayer,move,c,menuEpoch)
bwRun.OnServerEvent:Fire(menuPlayer,"fire(10)",2,c,menuEpoch)
boxes[c]:FindFirstChild("EnterPublicTank").Triggered:Fire(menuPlayer);advance(4)
check(controls[104].mode=="Menu" and not snapshots[c].occupantUserId and not snapshots[c].bwRunning and snapshots[c].health==menuHealth,"menu players cannot control or reacquire tanks through remotes or proximity prompts")
remote.OnServerEvent:Fire(menuPlayer,"Join",3);advance(25)
check(controls[104].mode=="OnFoot" and battleStates["104"].royale and not battleStates["104"].selected,"Play Battle Royale returns to the existing battle on foot")
check(not roots[104].Anchored and roots[104].Transparency==0 and roots[104].CanCollide and roots[104].CanQuery,"rejoin restores the native avatar and movement properties")
approach(menuPlayer,c);enter(menuPlayer,c,4)
check(controls[104].selected==c and controls[104].epoch~=menuEpoch,"returning player obtains a fresh public control lease")
remote.OnServerEvent:Fire(menuPlayer,"Menu",5,c,controls[104].epoch);advance(35)
remote.OnServerEvent:Fire(menuPlayer,"Join",6)
remote.OnServerEvent:Fire(menuPlayer,"Menu",7)
remote.OnServerEvent:Fire(menuPlayer,"Join",6);advance(4)
check(controls[104].mode=="Menu" and not battleStates["104"],"canceling a join fences a delayed older Join request")
roots[104],humanoids[104]=character(menuPlayer);menuPlayer.CharacterAdded:Fire(menuPlayer.Character);advance(4)
check(roots[104].Anchored and not roots[104].CanQuery and controls[104].mode=="Menu","character respawn cannot restore battlefield presence while in the menu")
local poolCount=0;for _ in snapshots do poolCount+=1 end
check(poolCount==6,"menu round trips neither reset nor duplicate arena tanks")
players.PlayerRemoving:Fire(menuPlayer);advance(4)
-- Environmental hazards run through production physics, damage and pool lifecycle.
local Terrain=require("PlaygroundTerrain");local terrain=Terrain.create(Terrain.DefaultSize)
local bridge
for _,part in created do
 if part.Name=="Bridge"then bridge=part end
 if part.Name=="Floor"then check(not part.CanCollide and not part.CanQuery and part.Transparency==1,"default Playground removes continuous floor support/query geometry")end
 if part.Name=="WestSlope"then
  local top=part.CFrame:PointToWorldSpace(Vector3.new(0,part.Size.Y/2,0))
  check(math.abs(top.Y-Terrain.sample(terrain,top.X,top.Z))<.001,"native sloped top matches authoritative terrain plane")
 end
end
check(bridge and bridge.CanCollide and bridge.Size.Z<16,"native bridge has a narrow deck for a single tank")
local hazardPlayer={UserId=105,Name="Hazard Tester",CharacterAdded=signal()}
roots[105],humanoids[105]=character(hazardPlayer);players.PlayerAdded:Fire(hazardPlayer);advance(25)
check(Terrain.safe(terrain,roots[105].Position-Vector3.new(0,3,0),7),"new character spawns on designated land clear of water/cliffs")
approach(hazardPlayer,a);enter(hazardPlayer,a,1)
check(controls[105].selected==a,"hazard occupant acquires a real public tank")
local liveStates={};local realStep=Sim.step
Sim.step=function(state,...)liveStates[state]=true;return realStep(state,...)end
advance(4);Sim.step=realStep
local activeState
for state in liveStates do if state.occupantUserId==105 then activeState=state end end
check(activeState~=nil,"hazard fixture uses actual authoritative tank state")
local priorGeneration=activeState.generation
activeState.controlMode="Manual"
local fallingTankScore=royale:scoreActor(royale.options.tanks[a])
activeState.position=Vector3.new(0,0,34)
remote.OnServerEvent:Fire(hazardPlayer,"Exit",2,a,controls[105].epoch);advance(4)
check(controls[105].selected==a and string.find(controls[105].message,"Cannot exit"),"falling or edge exit stays occupied and returns clear feedback")
for _=1,180 do advance(1);if snapshots[a].health<=0 then break end end
check(snapshots[a].health==0 and snapshots[a].fatalWeapon=="Cannon" and snapshots[a].publicRetired,"falling public tank uses existing fatal explosion state and retirement")
check(humanoids[105].Health==0 and not controls[105].selected and not snapshots[a].occupantUserId,"environmental death releases occupant and invokes native character death")
check(fallingTankScore.deaths==1 and battleStates["105"].score.deaths==1,"occupied Manual death counts against the driver")
local serial=snapshots[a].damageSerial;advance(30)
check(snapshots[a].damageSerial==serial,"remaining in hazard cannot record repeated deaths")
advance(330)
check(snapshots[a].health==0 and fallingTankScore.deaths==1,"no replacement before the new character exists")
roots[105],humanoids[105]=character(hazardPlayer);hazardPlayer.CharacterAdded:Fire(hazardPlayer.Character);advance(25)
check(snapshots[a].health==100 and snapshots[a].generation==priorGeneration+1 and Terrain.safe(terrain,snapshots[a].position,7),"environmental destruction restores the driver and tank to a safe position")
check(controls[105].selected==a and snapshots[a].controlMode=="Manual","environmental respawn restores Manual control")
local falling
Sim.step=function(state,...)if state.occupantUserId==105 then falling=state end;return realStep(state,...)end
advance(4);Sim.step=realStep
check(falling~=nil,"respawned hazard tester can re-enter")
do
 local course=terrain.course
 local tank=royale.options.tanks[a]
 falling.position=course.start;advance(4)
 check(tank.course and tank.course.phase=="Ravine Crossing","entering the course start pad starts the timer")
 falling.position=Vector3.new(0,2.2,21);advance(2)
 falling.position=course.range;advance(2)
 check(tank.course.phase=="Moving Target Range","reaching the range after the deck advances the run")
 local hitTargets={}
 for _,target in created do if target.Name=="CourseTarget" then table.insert(hitTargets,target) end end
 check(#hitTargets==3,"three physical course targets exist")
 local hitIndex=0
 workspace.Spherecast=function(_,origin,_,delta,params)
  local target=hitTargets[hitIndex+1]
  if target and params.FilterDescendantsInstances[1]==boxes[a] then
   hitIndex+=1;return {Instance=target,Position=origin+delta.Unit*.01,Distance=.01}
  end
 end
 local driveAndFire={throttle=0,steer=0,fire=false,aimMode="Rate",turretX=0,turretY=0}
 input.OnServerEvent:Fire(hazardPlayer,driveAndFire,a,controls[105].epoch);advance(4)
 driveAndFire.fire=true
 for _=1,1200 do
  input.OnServerEvent:Fire(hazardPlayer,driveAndFire,a,controls[105].epoch)
  advance(1)
  if tank.course.hits==3 then break end
 end
 check(tank.course.hits==3,"authoritative shell impacts credit the three unique targets")
 falling.position=course.gauntlet;advance(4)
 check(tank.course.phase=="Bullet Gauntlet","range completion unlocks the gauntlet")
 workspace.Spherecast=function(_,origin,_,delta,params)
  if params.FilterDescendantsInstances[1]~=boxes[a] and math.abs(origin.X-course.gauntlet.X)<18 then
   return {Instance=boxes[a],Position=origin+delta.Unit*.01,Distance=.01}
  end
 end
 local health=falling.health
 advance(80)
 check(falling.health<health and falling.health>0,"gauntlet projectiles use authoritative damage")
 workspace.Spherecast=function()return nil end
 falling.position=Vector3.new(course.finish+1,0,0);advance(4)
 check(tank.course.phase=="Complete","reaching the gauntlet exit alive records completion")
 network:FindFirstChild("ProvingGroundsAction").OnServerEvent:Fire(hazardPlayer,"Restart",a,controls[105].epoch)
 falling=tank.state;advance(4)
 check(tank.course.phase=="Ravine Crossing" and tank.course.hits==0 and (falling.position-course.start).Magnitude<.1,"Replay resets course state and returns the occupied tank to the start")
 falling.position=Vector3.new(0,-30,34);advance(4)
 check(not controls[105].selected,"course ravine fall uses the coordinated respawn path")
 roots[105],humanoids[105]=character(hazardPlayer);hazardPlayer.CharacterAdded:Fire(hazardPlayer.Character);advance(4)
 falling=tank.state
 check(controls[105].selected==a and (falling.position-course.start).Magnitude<.1,"after falling the driver respawns in their tank at the course start")
end
falling.position=Vector3.new(0,-30,34);players.PlayerRemoving:Fire(hazardPlayer);advance(180)
check(not snapshots[a].occupantUserId and snapshots[a].health==0 and not battleStates["105"],"disconnect during a fall releases control but does not spare the public tank")
advance(330)
check(snapshots[a].generation==priorGeneration+4 and snapshots[a].health==100,"disconnect/fall replenishes exactly once")
local safeCalls=0
local characterAdapter=require("RoyaleCharacters").new(function()safeCalls+=1;return Vector3.zero end)
characterAdapter:hide(first,Vector3.new(40,50,-20))
characterAdapter:restore(first,nil,false,{position=Vector3.new(40,61,-20),velocity=Vector3.new(8,25,-3)})
check(safeCalls==0 and (roots[101].Position-Vector3.new(40,61,-20)).Magnitude<1e-6,"raised-tank ejection bypasses the global spawn search and preserves its world height")
check((roots[101].AssemblyLinearVelocity-Vector3.new(8,25,-3)).Magnitude<1e-6,"ejection retains configured upward and inherited horizontal velocity")
characterAdapter:restore(first,nil,false)
check(safeCalls==1 and roots[101].Position.Y==3,"ordinary character respawn still uses the safe-spawn path")
local unavailable=require("RoyaleCharacters").new(function()return nil end)
unavailable:restore(first,nil,false)
check(humanoids[101].Health==0 and roots[101].Anchored,"exhausted safe anchors never leave an avatar at an unsafe default origin")
os.clock=savedClock
print(string.format("Battle Royale production server integration passed: %d assertions",count))
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService

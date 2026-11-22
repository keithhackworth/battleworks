local Terrain=require("PlaygroundTerrain")
local terrain=Terrain.create(Terrain.DefaultSize)
local westZone=terrain.configurationZones[1]
local live={}
local runtimeTanks={}
local BW=require("BWController");local bwInput=BW.input
BW.input=function(tank,...)if tank.personality then runtimeTanks[tank.personality.id]=tank end;return bwInput(tank,...)end
local Sim=require("TankSimulation");local step=Sim.step
Sim.step=function(state,...)if state.personalityId then live[state.personalityId]=state end;return step(state,...)end
advance(4);Sim.step=step;BW.input=bwInput
check(network:GetAttribute("BuildRevision")=="playground-15-auto-v4","startup exposes the packaged revision to connected clients")
local arenaNode
for _,p in created do if p.Name=="Arena"then arenaNode=p end end
check(arenaNode:GetAttribute("StartupLayout")=="ProvingGround"and arenaNode:GetAttribute("StartupPublicTanks")==15 and arenaNode:GetAttribute("StartupAutoTanks")==15,"ready diagnostic reports actual proving layout and live public pool")
local Hardware=require("BWChassis")
local Components=require("VehicleComponents")
local signature={P04="turret",P06="drivetrain",P07="scanners",P10="scanners",P15="scanners"}
local unused={P02="scanners",P03="drivetrain"}
local function checkRoll(personality,actual)
 local total=0
 for _,category in Hardware.Categories do
  local points=actual.allocations[category]
  check(points%1==0 and (if category==unused[personality] then points==0 else points>=5),"whole bus points honor unused devices and active minimum")
  total+=points
 end
 check(total==100 and Hardware.validate(actual),"spawn hardware uses one validated 100-point bus")
 if signature[personality] then
  check(actual.allocations[signature[personality]]==75,"signature device receives 75 points")
 end
 local scannerTotal=0
 for _,angle in Hardware.Angles do scannerTotal+=actual.devices["sensor"..angle].allocation end
 check(math.abs(scannerTotal-actual.allocations.scanners)<1e-8,"the eight lenses share the array allocation")
end
local boxes={};local ids={};local names={};local generalistLeads={}
for _,p in created do if p.Name=="TankHitbox"and not p.destroyed then boxes[p:GetAttribute("TankId")]=p end end
for id,s in snapshots do
 table.insert(ids,id);check(s.public and s.controlMode=="Auto"and s.bwRunning,"all default public tanks start autonomous")
 check(not Terrain.inCourse(terrain,s.position,8),"public tanks spawn clear of the course")
 check(not names[s.personalityId],"one independently assigned personality per tank");names[s.personalityId]=true
 check(require("VehicleComponents").get(live[s.personalityId]).Computer.Tier=="Bunny","single-thread computer")
 local hardware=runtimeTanks[s.personalityId].hardware
 checkRoll(s.personalityId,hardware)
 if not signature[s.personalityId] and not unused[s.personalityId] then
  for category,points in hardware.allocations do
   if points>=50 and points<=70 then generalistLeads[category]=true end
  end
 end
end
for _,category in Hardware.Categories do check(generalistLeads[category],"initial generalists cover every lead category")end
table.sort(ids);check(#ids==15,"default pool has all fifteen personalities")
for i,id in ids do
 local s=snapshots[id]
 check(Terrain.safe(terrain,s.position,7),"random spawn is safe solid land")
 for j=i+1,#ids do check((s.position-snapshots[ids[j]].position).Magnitude>=14,"random pool spawns do not overlap")end
end
local reboot=runtimeTanks.P15;local oldRuntime=reboot.bw
oldRuntime.elapsed=180
advance(3)
check(not reboot.state.bwRunning and reboot.state.controlMode=="Auto","native180s execution guard still stops autonomous invocation")
advance(65)
check(reboot.bw~=oldRuntime and reboot.state.bwRunning,"Auto restarts a fresh bounded invocation after timeout")
local a,b=ids[1],ids[2]
local function enter(player,id,requestId)
 local s=snapshots[id];roots[player.UserId].CFrame=CFrame.new(s.position+Vector3.new(0,3,0))
 remote.OnServerEvent:Fire(player,"Enter",requestId,id,s.controlEpoch)
 advance(4)
end
local injured=runtimeTanks[snapshots[a].personalityId]
injured.state.health=25;injured.state.damageByWeapon={Cannon=75};injured.state.immobilized=true;injured.state.immobilizedRemaining=2
injured.state.cooldown=2
local beforeEntry=injured.state.position;local entryGeneration=injured.state.generation
enter(first,a,1)
check(snapshots[a].health==require("VehicleComponents").get(injured.state).Chassis.Health and not snapshots[a].immobilized,"successful entry restores actual chassis max HP and clears damage immobilization")
check(injured.state.cooldown>1 and injured.state.generation==entryGeneration and (injured.state.position-beforeEntry).Magnitude<1,"entry repair preserves cooldown/generation/location")
check(controls[101].selected==a and controls[101].controlMode=="Manual"and not snapshots[a].bwRunning,"entry automatically selects Manual and terminates personality")
local epoch=controls[101].epoch
local cfg
for _,event in privateRuntime do if event.recipient==first and event.args[1]==a then cfg=event.args[2].configuration end end
-- Use the actual diagnostics emitted by the production server.
if not cfg then advance(15);for _,event in privateRuntime do if event.recipient==first and event.args[1]==a then cfg=event.args[2].configuration end end end
local actualSource
for _,event in privateRuntime do if event.recipient==first and event.args[1]==a and event.args[2].source then actualSource=event.args[2].source end end
check(actualSource and actualSource.kind=="Personality"and actualSource.text==runtimeTanks[snapshots[a].personalityId].personality.source,"occupied tank privately delivers exact expanded personality source even after entering Manual")
check(actualSource.text:find("function travel(",1,true)and actualSource.text:find("# P01 Marauder",1,true)and require("BWParser").parse(actualSource.text),"Marauder source is one complete valid public BW program with travel definition and personality body")
check(cfg and cfg.tier=="Bunny"and Hardware.validate(cfg),"real diagnostic configuration is valid Bunny hardware")
for name,device in cfg.devices do
 check(device.bus==1 and device.allocation==injured.spawnHardware.devices[name].allocation,"diagnostics report the current rolled allocation")
end

remote.OnServerEvent:Fire(second,"Auto",1,a,epoch);advance(3)
check(snapshots[a].controlMode=="Manual","nonoccupant cannot change control mode")
injured.state.health=60
remote.OnServerEvent:Fire(second,"Enter",2,a,epoch);advance(3)
check(snapshots[a].health==60,"failed entry cannot repair an occupied tank")
-- Allow action cooldown without stepping physics to avoid incidental combat.
local oldClock=os.clock;local wall=oldClock()+1;os.clock=function()return wall end
remote.OnServerEvent:Fire(first,"Auto",2,a,epoch);advance(4)
check(controls[101].controlMode=="Auto"and snapshots[a].bwRunning and snapshots[a].health==60,"mode change starts personality without granting another repair")
local autoEpoch=controls[101].epoch
check(autoEpoch>epoch,"mode change fences old manual packets")
local move=require("InputCommand").neutral();move.throttle=1;move.fire=true
input.OnServerEvent:Fire(first,move,a,epoch);advance(3)
check(snapshots[a].controlMode=="Auto","stale manual lease cannot seize autonomous control")
wall+=1;remote.OnServerEvent:Fire(first,"Manual",3,a,autoEpoch);advance(4)
check(controls[101].controlMode=="Manual"and not snapshots[a].bwRunning,"Manual stops all BW work")
wall+=1
-- Move to safe land before testing the established exit/ejection path.
live[snapshots[a].personalityId].position=Vector3.new(110,0,-17)
remote.OnServerEvent:Fire(first,"Exit",4,a,controls[101].epoch);advance(4)
check(not controls[101].selected and snapshots[a].controlMode=="Auto"and snapshots[a].bwRunning,"vacating restores personality without ownership")
enter(first,b,5)
check(controls[101].selected==b and snapshots[b].controlMode=="Manual","switching tanks always returns to Manual")
local generation=snapshots[b].generation;local personality=snapshots[b].personalityId
local previous=runtimeTanks[personality].spawnHardware.allocations
royale:release(royale.members[101],"Test vacates tank before autonomous death.",false,true)
local execution=network:FindFirstChild("PlaygroundBWExecution")
BW.input=function(tank,...)if tank.id==b then runtimeTanks[personality]=tank end;return bwInput(tank,...)end
-- The offline runner has a fixed heap. Age the wreck with interpreters paused,
-- then resume them to check that the replacement actually runs its personality.
execution.OnServerEvent:Fire(first,false)
live[personality].health=0;advance(305)
execution.OnServerEvent:Fire(first,true);advance(5);BW.input=bwInput
local replacement=runtimeTanks[personality].spawnHardware
checkRoll(personality,replacement)
local changed=false
for _,category in Hardware.Categories do if previous[category]~=replacement.allocations[category] then changed=true end end
check(changed,"replenishment rerolls the bus while preserving the personality's rules")
check(snapshots[b].generation>generation and snapshots[b].personalityId==personality and snapshots[b].controlMode=="Auto"and snapshots[b].bwRunning,"replenishment preserves personality and starts Auto with fresh state")
check(not royale.members[101].tank,"unoccupied autonomous replacement remains available")
enter(second,a,3)
runtimeTanks[snapshots[a].personalityId].state.position=Vector3.new(110,0,-12)
players.PlayerRemoving:Fire(second);advance(4)
check(not snapshots[a].occupantUserId and snapshots[a].controlMode=="Auto"and snapshots[a].bwRunning,"disconnect releases tank back to Auto")
check(execution and execution:GetAttribute("Enabled")==true,"Studio starts with live BW execution ON")
local auto=runtimeTanks[snapshots[a].personalityId]
local manual=runtimeTanks[snapshots[b].personalityId]
roots[101],humanoids[101]=character(first)
first.CharacterAdded:Fire(first.Character)
wall+=1;enter(first,b,6)
check(controls[101].selected==b and manual.state.controlMode=="Manual","manual tank is occupied during the diagnostic")
auto.state.position=Vector3.new(110,0,-17)
check(BW.start(auto,"marker = 42\nforward()\nlook = Scanner(0)\nwait_for_clock(get_clock().time + 10)"),"fixture schedules persistent drive, scan and clock wait")
local runtime=auto.bw
for _=1,40 do
 if auto.tickCommand.throttle>0 and runtime.scanCount>0 then break end
 advance(1)
end
check(auto.tickCommand.throttle>0 and runtime.scanCount==1,"continuous BW drive and scanner request are active before pause")
local pending={remaining=0.5};auto.pendingShot=pending
local tankState,hardware,health=auto.state,auto.hardware,auto.state.health
local elapsed,clock,completed=runtime.elapsed,runtime.time,runtime.devices.devices.sensor0.scanSuccesses
local shotsBefore=auto.state.weaponShotSerial
execution.OnServerEvent:Fire({UserId=first.UserId},false)
execution.OnServerEvent:Fire(first,"false")
check(execution:GetAttribute("Enabled")==true,"toggle rejects a different sender object and non-boolean input")
execution.OnServerEvent:Fire(first,false)
check(execution:GetAttribute("Enabled")==false and auto.tickCommand.throttle==0 and not auto.tickCommand.fire,"server OFF immediately clears autonomous intent")
local manualInput=require("InputCommand").neutral();manualInput.throttle=1;manualInput.turretX=.5
wall+=1
input.OnServerEvent:Fire(first,manualInput,b,controls[101].epoch)
advance(55)
check(auto.state==tankState and auto.hardware==hardware and auto.state.health==health and auto.bw==runtime and runtime.variables.marker==42,"OFF preserves the physical tank, hardware, and invocation")
check(runtime.elapsed==elapsed and runtime.time==clock and runtime.devices.devices.sensor0.scanSuccesses==completed,"OFF freezes interpreter clock and pending scanner")
check(auto.tickCommand.throttle==0 and auto.tickCommand.steer==0 and auto.tickCommand.turretX==0 and auto.tickCommand.turretY==0 and not auto.tickCommand.fire,"OFF emits neutral drive, steering, turret and fire input")
check(auto.pendingShot==pending and pending.remaining==0.5 and auto.state.weaponShotSerial==shotsBefore,"an accepted cannon preparation never advances or fires while OFF")
check(manual.tickCommand.throttle==1 and manual.tickCommand.turretX==.5,"manual player movement and turret commands still dispatch while OFF")
local populated=0;for _ in snapshots do populated+=1 end
check(populated==15,"OFF retains the 15-tank pool")
execution.OnServerEvent:Fire(first,true)
advance(2)
check(execution:GetAttribute("Enabled")==true and auto.bw==runtime and runtime.elapsed>elapsed and runtime.time-clock<.1,"ON resumes the same invocation with no clock jump")
check(auto.tickCommand.throttle>0 and manual.tickCommand.throttle==1,"continuous BW and regular manual input both run after resume")
local sensor=auto.hardware.devices.sensor0
advance(math.ceil(60*sensor.acquisition/Hardware.effective(auto.hardware,"sensor0",Components.get(auto.state)))+10)
check(runtime.devices.devices.sensor0.scanSuccesses==1 and runtime.variables.look~=nil,"the same queued scan completes after resume")
local garage=network:FindFirstChild("GarageConfiguration")
check(not garage.OnServerInvoke(first,"Read").ok,"Garage cannot change equipment while occupying a public tank")
local loadout=snapshots[b].tankType.."/"..snapshots[b].weaponId
wall+=1;remote.OnServerEvent:Fire(first,"Menu",7);advance(4)
local choices=garage.OnServerInvoke(first,"Read")
check(choices.ok and #choices.choices==4,"Playground Garage lists registered chassis and weapon combinations")
local setup={allocations={drivetrain=5,turret=15,weapon=50,scanners=30},tuning={weapon=1,scanners=0}}
check(garage.OnServerInvoke(first,"Save",loadout,setup).ok,"public tank preference is saved in the server session")
wall+=1;remote.OnServerEvent:Fire(first,"Join",8);advance(4);enter(first,b,9)
check(controls[101].selected==b and snapshots[b].weaponPerformance==.75,"the matching public tank uses the saved power when manually occupied")
wall+=1;remote.OnServerEvent:Fire(first,"Auto",10,b,controls[101].epoch);advance(4)
check(snapshots[b].controlMode=="Auto" and snapshots[b].weaponPerformance==Hardware.weaponStats(replacement,Components.get(manual.state)),"built-in Auto restores the tank's spawn roll")
wall+=1;remote.OnServerEvent:Fire(first,"Manual",11,b,controls[101].epoch);advance(4)
local zoneEpoch=controls[101].epoch
check(not garage.OnServerInvoke(first,"ReadZone",b,nil,zoneEpoch).ok,"live settings are unavailable outside the zone")
manual.state.position=Vector3.new(westZone.x,westZone.y,westZone.z)
require("VehicleMotion").setVelocity(manual.state,Vector3.zero)
manual.pendingShot={remaining=.001};advance(4)
check(snapshots[b].configurationZone=="config:west" and manual.pendingShot==nil,"zone entry cancels pending fire before projectile release")
local zoneReading=garage.OnServerInvoke(first,"ReadZone",b,nil,zoneEpoch)
check(zoneReading.ok and zoneReading.choices[1].weapon==snapshots[b].weaponId and zoneReading.choices[1].draft.allocations.weapon==50,"zone settings read the held tank's exact weapon and configuration")
check(not garage.OnServerInvoke(first,"SaveZone",b,setup,zoneEpoch-1).ok,"stale leases cannot configure a tank")
check(not garage.OnServerInvoke(first,"SaveZone",b,{allocations={drivetrain=100,turret=100,weapon=0,scanners=0},tuning={weapon=.5,scanners=.5}},zoneEpoch).ok,"zone applies the shared allocation cap")
local updated={allocations={drivetrain=5,turret=0,weapon=90,scanners=5},tuning={weapon=1,scanners=1}}
check(garage.OnServerInvoke(first,"SaveZone",b,updated,zoneEpoch).ok,"valid zone settings apply without changing the lease")
advance(4)
check(controls[101].epoch==zoneEpoch and snapshots[b].weaponPerformance==.99 and snapshots[b].turretPerformance==0,"live weapon and turret state immediately reflect applied hardware")
bwRun.OnServerEvent:Fire(first,"fire()",1,b,zoneEpoch);advance(4)
check(not snapshots[b].bwRunning and snapshots[b].controlMode=="Manual","BW cannot execute while the tank remains in a zone")
wall+=1;remote.OnServerEvent:Fire(first,"Auto",12,b,zoneEpoch);advance(4)
check(controls[101].mode=="Tank" and controls[101].epoch==zoneEpoch and snapshots[b].controlMode=="Manual","Auto cannot take over an occupied zone")
local health=manual.state.health
check(not require("LocalBattle").damage({multiplayer=true},manual,auto,25,"Cannon",manual.state.position) and manual.state.health==health,"an incoming projectile impact cannot damage a protected tank")
manual.state.cooldown=0;manual.rattler.cooldown=0;manual.rattler.shotClock=0
wall+=1;input.OnServerEvent:Fire(first,require("InputCommand").neutral(),b,zoneEpoch)
wall+=1;input.OnServerEvent:Fire(first,move,b,zoneEpoch);local serial=manual.state.weaponShotSerial
advance(20)
check(manual.state.weaponShotSerial==serial and manual.pendingShot==nil and not manual.state.firing,"held fire cannot prepare or launch from the zone")
wall+=1;remote.OnServerEvent:Fire(first,"Exit",13,b,zoneEpoch);advance(4)
check(snapshots[b].controlMode=="Parked" and not snapshots[b].bwRunning,"vacating inside parks the tank without starting Auto")
wall+=1;enter(first,b,14)
check(snapshots[b].controlMode=="Manual" and snapshots[b].weaponPerformance==.99,"a new manual lease recovers the same session setup")
manual.state.position=Vector3.new(westZone.x+westZone.halfX+12,westZone.y,westZone.z);require("VehicleMotion").setVelocity(manual.state,Vector3.zero);advance(4)
check(not snapshots[b].configurationZone and not garage.OnServerInvoke(first,"SaveZone",b,updated,controls[101].epoch).ok,"leaving the zone revokes the live settings permission")
check(require("LocalBattle").damage({multiplayer=true},manual,auto,25,"Cannon",manual.state.position),"the same damage path resumes once the tank exits")
BW.stop(auto,"Parked test target.")
auto.state.controlMode="Parked";auto.state.position=Vector3.new(westZone.x,westZone.y,westZone.z)
require("VehicleMotion").setVelocity(auto.state,Vector3.zero)
advance(4)
local targetHealth=auto.state.health
local impacted=false
local oldCast=workspace.Spherecast
workspace.Spherecast=function(_,origin,_,delta,params)
 if not impacted and params.FilterDescendantsInstances[1]==manual.hitbox and delta.Magnitude<2 then
  impacted=true
  return {Instance=auto.hitbox,Position=origin+delta.Unit*.01,Distance=.01}
 end
end
local fire=require("InputCommand").neutral();fire.fire=true
wall+=1;input.OnServerEvent:Fire(first,require("InputCommand").neutral(),b,controls[101].epoch)
wall+=1;input.OnServerEvent:Fire(first,fire,b,controls[101].epoch)
serial=manual.state.weaponShotSerial or 0;advance(40)
check((manual.state.weaponShotSerial or 0)>serial,"normal firing resumes with a fresh trigger after leaving")
workspace.Spherecast=oldCast
check(impacted and targetHealth>0 and auto.state.health==targetHealth,"an actual in-flight shell hits and is consumed without harming the protected tank")
check(snapshots[b].weaponPerformance==.99,"new bus tuning remains active in combat")
os.clock=oldClock
print("Playground fifteen-personality integration passed: "..count.." assertions")
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService

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
local boxes={};local ids={};local names={}
for _,p in created do if p.Name=="TankHitbox"and not p.destroyed then boxes[p:GetAttribute("TankId")]=p end end
for id,s in snapshots do
 table.insert(ids,id);check(s.public and s.controlMode=="Auto"and s.bwRunning,"all default public tanks start autonomous")
 check(not names[s.personalityId],"one independently assigned personality per tank");names[s.personalityId]=true
 check(require("VehicleComponents").get(live[s.personalityId]).Computer.Tier=="Bunny","single-thread computer")
 local actual=runtimeTanks[s.personalityId].hardware;local devices=0
 for _ in actual.devices do devices+=1 end
 check(Hardware.validate(actual),"every tank uses validated real hardware")
 for _,device in actual.devices do check(device.bus==1 and math.abs(device.allocation-100/devices)<1e-8,"every personality has equal component allocations")end
end
table.sort(ids);check(#ids==15,"default pool has all fifteen personalities")
for i,id in ids do
 local s=snapshots[id]
 check(require("PlaygroundTerrain").safe(require("PlaygroundTerrain").create(Vector2.new(800,640)),s.position,7),"random spawn is safe solid land")
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
local n=0;for _ in cfg.devices do n+=1 end
for _,device in cfg.devices do check(device.bus==1 and math.abs(device.allocation-100/n)<1e-8,"all installed components have equal single-bus shares")end

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
live[snapshots[a].personalityId].position=Vector3.new(110,0,40)
remote.OnServerEvent:Fire(first,"Exit",4,a,controls[101].epoch);advance(4)
check(not controls[101].selected and snapshots[a].controlMode=="Auto"and snapshots[a].bwRunning,"vacating restores personality without ownership")
enter(first,b,5)
check(controls[101].selected==b and snapshots[b].controlMode=="Manual","switching tanks always returns to Manual")
local generation=snapshots[b].generation;local personality=snapshots[b].personalityId
live[personality].health=0;advance(310)
check(snapshots[b].generation>generation and snapshots[b].personalityId==personality and snapshots[b].controlMode=="Auto"and snapshots[b].bwRunning,"replenishment preserves personality and starts Auto with fresh state")
check(not controls[101].selected,"destroyed occupant is released")
enter(second,a,3);players.PlayerRemoving:Fire(second);advance(4)
check(not snapshots[a].occupantUserId and snapshots[a].controlMode=="Auto"and snapshots[a].bwRunning,"disconnect releases tank back to Auto")
local execution=network:FindFirstChild("PlaygroundBWExecution")
check(execution and execution:GetAttribute("Enabled")==true,"Studio starts with live BW execution ON")
local auto=runtimeTanks[snapshots[a].personalityId]
local manual=runtimeTanks[snapshots[b].personalityId]
-- Capture the replacement the next time its existing input dispatcher runs.
BW.input=function(tank,...)if tank.id==b then manual=tank end;return bwInput(tank,...)end
advance(2);BW.input=bwInput
roots[101],humanoids[101]=character(first)
first.CharacterAdded:Fire(first.Character)
wall+=1;enter(first,b,6)
check(controls[101].selected==b and manual.state.controlMode=="Manual","manual tank is occupied during the diagnostic")
auto.state.position=Vector3.new(110,0,40)
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
advance(50)
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
check(snapshots[b].controlMode=="Auto" and snapshots[b].weaponPerformance<.2,"built-in Auto restores the personality default bus")
os.clock=oldClock
print("Playground fifteen-personality integration passed: "..count.." assertions")
end
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService

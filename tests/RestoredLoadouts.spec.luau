-- Real current assemblies and production entrypoint; no baseline substitution.
local Components=require("VehicleComponents")
local Assemblies=require("VehicleAssemblies")
local Input=require("InputCommand")
local Recoil=require("RattlerRecoil")
check(Assemblies.Boomer.Weapon=="weapon.cannon" and Assemblies.Boomer.Mobility=="mobility.tracks","Boomer restores cannon and tracks")
check(Assemblies.Rattler.Weapon=="weapon.gatling" and Assemblies.Rattler.Mobility=="mobility.wheels","Rattler restores Gatling and four wheels")
check(snapshots[boomerId].weaponId=="weapon.cannon" and snapshots[rattlerId].weaponId=="weapon.gatling","server snapshots publish restored weapons")
check(Components.get("Boomer").Installed.Drivetrain=="drive.hyper_p35" and Components.get("Rattler").Installed.Drivetrain=="drive.car","existing engine upgrades retained")
local steer=Input.neutral();steer.steer=1
local tracks=Sim.new(Vector3.zero,"Boomer")
local wheels=Sim.new(Vector3.zero,"Rattler")
for _=1,30 do Sim.step(tracks,steer,1/60);Sim.step(wheels,steer,1/60)end
check(math.abs(tracks.yaw)>.5 and math.abs(wheels.yaw)<1e-6,"restored tracks pivot while wheels require forward travel")
local full=Input.neutral();full.throttle=1
local hyper=Sim.new(Vector3.zero,"Boomer")
for _=1,180 do Sim.step(hyper,full,1/60,Vector2.new(2000,2000))end
check(math.abs(hyper.speed-35)<1e-6,"tracked Boomer retains Hyper P35 speed")
local function named(renderer,name)
 local result={};for _,part in renderer.model:GetChildren()do if part.Name==name then table.insert(result,part)end end;return result
end
local boomer=Renderer.new("restored-boomer","Boomer",snapshots[boomerId].weaponId)
local rattler=Renderer.new("restored-rattler","Rattler",snapshots[rattlerId].weaponId)
check(not boomer.gatling and #named(boomer,"Cannon")==1 and #boomer.treads==56 and #named(boomer,"ChunkyTire")==0,"Boomer renders cannon and track belts")
check(rattler.gatling and #named(rattler,"GatlingBarrel")==6 and #rattler.treads==0 and #named(rattler,"ChunkyTire")==4,"Rattler renders six-barrel Gatling and four tires")
tick(false)
local shotsBefore,preparesBefore=#shots,#prepared
for _=1,180 do tick(true)end
check(#shots>shotsBefore and prepared[preparesBefore+1].weaponId=="weapon.cannon","restored Boomer prepares and fires cannon through server")
check(shots[shotsBefore+1].weaponId=="weapon.cannon" and snapshots[boomerId].lift==0,"Boomer cannon attribution and non-hopping behavior restored")
tick(false);select.OnServerEvent:Fire(first,"Rattler");advance(5);tick(false)
shotsBefore=#shots
local maxLift=0
for _=1,183 do tick(true);maxLift=math.max(maxLift,snapshots[rattlerId].lift or 0)end
check(#shots-shotsBefore>=25 and shots[shotsBefore+1].weaponId=="weapon.gatling","restored Rattler uses rapid Gatling fire")
check(maxLift>3 and maxLift<=6 and snapshots[rattlerId].weaponCooldown>1.9,"Rattler retains Gatling hops, rattling and heat lockout")
tick(false);advance(180)
check(snapshots[rattlerId].lift==0,"Rattler settles after releasing Gatling")
reset.OnServerEvent:Fire(first);advance(6)
check(snapshots[boomerId].weaponId=="weapon.cannon" and snapshots[rattlerId].weaponId=="weapon.gatling" and snapshots[rattlerId].heat==0,"reset preserves restored loadouts and clears firing state")
bwRun.OnServerEvent:Fire(first,"fire(1)",1,rattlerId);advance(75)
check((snapshots[rattlerId].weaponShotSerial or 0)>2 and (snapshots[rattlerId].flightShotSerial or 0)>2,"BW drives restored Gatling and recoil")
bwStop.OnServerEvent:Fire(first,2,rattlerId);advance(180)
check(not snapshots[rattlerId].bwRunning and snapshots[rattlerId].lift==0,"BW stop releases restored Gatling and lands")
local alternative=Components.forWeapon("Boomer","weapon.gatling")
local experimental=Sim.new(Vector3.zero,"Boomer",123,alternative)
Recoil.kick(experimental,1,Vector3.new(0,0,-1))
check(experimental.verticalSpeed>0,"component system still supports optional future weapon swaps")
boomer:destroy();rattler:destroy()
os.clock=savedClock;workspace.FindFirstChild=originalWorkspaceFind
end -- production fixture
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
print(string.format("Live restored-loadout integration passed: %d assertions",count))

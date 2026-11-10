 -- Continuation of the shared production server fixture (live assemblies).
 local Components=require("VehicleComponents")
 local Catalog=require("ComponentCatalog")
 local Assemblies=require("VehicleAssemblies")
 local Recoil=require("RattlerRecoil")
 check(Assemblies.Boomer.Weapon=="weapon.gatling" and Assemblies.Rattler.Weapon=="weapon.cannon","live assemblies swap installed weapon IDs")
 check(snapshots[boomerId].weaponId=="weapon.gatling" and snapshots[rattlerId].weaponId=="weapon.cannon","server publishes installed weapon descriptor")
 check(Components.get("Boomer").Mobility.Kind=="Wheeled" and Components.get("Rattler").Mobility.Kind=="Tracked","live assemblies swap mobility independently from weapons")
 local Input=require("InputCommand")
 local hyper=Sim.new(Vector3.zero,"Boomer")
 local fullThrottle=Input.neutral(); fullThrottle.throttle=1
 for _=1,180 do Sim.step(hyper,fullThrottle,1/60,Vector2.new(2000,2000)) end
 check(math.abs(hyper.speed-35)<1e-6,"live Boomer reaches Hyper P35 forward rating")
 check(Components.get(hyper).Installed.Drivetrain=="drive.hyper_p35","live Boomer resolves installed Hyper hardware")

 local steer=Input.neutral(); steer.steer=1
 local wheelState=Sim.new(Vector3.zero,"Boomer")
 local trackState=Sim.new(Vector3.zero,"Rattler")
 for _=1,30 do
  Sim.step(wheelState,steer,1/60); Sim.step(trackState,steer,1/60)
 end
 check(math.abs(wheelState.yaw)<1e-6 and math.abs(trackState.yaw)>.5,"installed wheels cannot pivot; installed tracks pivot on either body")
 steer.throttle=1
 for _=1,30 do Sim.step(wheelState,steer,1/60) end
 check(math.abs(wheelState.yaw)>.1 and wheelState.position.Magnitude>1,"wheeled Boomer drives a steering arc through shared simulation")
 check(Components.get("Boomer").Drivetrain.Speed==35 and Components.get("Rattler").Drivetrain.Speed==30,"Boomer installs Hyper P35 independently from mobility")
 -- Exercise the render-loop HUD against the actual swapped assemblies, not
 -- legacy fixtures: tracked Rattler intentionally has no legacy Drive view.
 local SpeedHud=require("SpeedDebugHud")
 local speedHud=SpeedHud.new(Instance.new("ScreenGui"))
 for _,kind in {"Boomer","Rattler","Boomer","Rattler"} do
  speedHud:update({tankType=kind,movementSpeedXZ=36,movementPeakXZ=36})
  local expected=if kind=="Boomer" then "BOOST +1.0 (+3%)" else "BOOST +6.0 (+20%)"
  check(string.find(speedHud.label.Text,expected,1,true)~=nil,"speed HUD follows installed propulsion when switching to "..kind)
 end
 speedHud:update(nil)
 check(string.find(speedHud.label.Text,"waiting",1,true)~=nil,"speed HUD handles selection handoff without a tank")
 speedHud:destroy()
 local cannon=Catalog["weapon.cannon"].Properties
 local gatling=Catalog["weapon.gatling"].Properties
 tick(false)
 local firstShot=#shots; local maxLift,maxRoll=0,0
 for _=1,183 do
  tick(true)
  maxLift=math.max(maxLift,snapshots[boomerId].lift or 0)
  maxRoll=math.max(maxRoll,math.abs(snapshots[boomerId].flightRoll or 0))
 end
 check(shots[firstShot+1].weaponId=="weapon.gatling","release event identifies installed Gatling")
 check(#shots-firstShot>=10 and #prepared==0,"tracked Boomer fires Gatling without cannon preparation")
 check(maxLift>=3 and maxLift<=6 and maxRoll>0.1,"weapon rattles and launches tracked Boomer")
 check(snapshots[boomerId].weaponCooldown>1.9,"Gatling heat cutoff follows weapon on Boomer")
 local locked=#shots
 for _=1,114 do tick(true) end
 check(#shots==locked,"Gatling enforces mandatory lockout on other vehicle")
 tick(false); advance(180)
 check(snapshots[boomerId].lift==0 and math.abs(snapshots[boomerId].flightRoll or 0)<0.01,"tracked victim of gun recoil slams down and settles after release")
 local boomer=Renderer.new("swap-boomer","Boomer",snapshots[boomerId].weaponId)
 local rattler=Renderer.new("swap-rattler","Rattler",snapshots[rattlerId].weaponId)
 local function named(renderer,name)
  local found={}; for _,p in renderer.model:GetChildren() do if p.Name==name then table.insert(found,p) end end; return found
 end
 check(boomer.gatling and boomer.jackhammer and #named(boomer,"GatlingBarrel")==6 and #named(boomer,"Cannon")==0,"orange tracked body mounts visible Gatling assembly")
 check(#boomer.treads==0 and #named(boomer,"ChunkyTire")==4 and boomer.chassis.Color[1]==245,"Boomer mounts wheels and keeps orange palette")
 check(not rattler.gatling and not rattler.jackhammer and #named(rattler,"Cannon")==1 and #named(rattler,"GatlingBarrel")==0,"green wheeled body mounts visible cannon")
 check(#rattler.treads==56 and #named(rattler,"ChunkyTire")==0 and rattler.chassis.Color[2]==144,"Rattler mounts tracks and keeps green palette")
 local rstate=Sim.new(Vector3.zero,"Rattler")
 rattler:resetPose(rstate); rattler:fire(); rattler:update(rstate,0.1)
 check(rattler.barrelBulge.Transparency<1 and rattler.shotAge~=nil,"cannon swell transfers to wheeled body")
 rattler:update(rstate,0.3)
 check(rattler.barrelBulge.Transparency==1,"cannon swell cleans up")
 local bs=Sim.new(Vector3.new(0,4,0),"Boomer"); bs.lift=4; bs.flightRoll=.15; bs.flightShotSerial=1; bs.bodyRoll=.15; bs.firing=true
 boomer:resetPose(bs); boomer:fire({serial=2,roll=-.16}); boomer:update(bs,1/60)
 check(boomer.rotorAngle>0 and boomer.visualRollKick< -0.2,"Gatling rotation and exaggerated rocking transfer to tracked body")
 check(math.abs(named(boomer,"ChunkyTire")[1].CFrame.UpVector.X)>0.05,"wheeled hull inherits weapon-induced rocking")
 local effectsAt=#created
 Renderer.shot(Vector3.zero,Vector3.new(0,0,-1),"Boomer","weapon.gatling")
 local rapidFlash=false; for i=effectsAt+1,#created do if created[i].Name=="RattlerFlash" then rapidFlash=true end end
 check(rapidFlash,"Gatling muzzle effect follows weapon on Boomer")
 effectsAt=#created
 Renderer.shot(Vector3.zero,Vector3.new(0,0,-1),"Rattler","weapon.cannon")
 local coughFlash=false; for i=effectsAt+1,#created do if created[i].Name=="MuzzleFlash" then coughFlash=true end end
 check(coughFlash,"cannon muzzle effect follows weapon on Rattler")
 select.OnServerEvent:Fire(first,"Rattler"); advance(5); tick(false)
 local beginTime=time; local preparedStart=#prepared; local shotStart=#shots; local wheeledLift=0
 for _=1,150 do tick(true); wheeledLift=math.max(wheeledLift,snapshots[rattlerId].lift or 0) end
 check(prepared[preparedStart+1] and prepared[preparedStart+1].kind=="Rattler" and prepared[preparedStart+1].weaponId=="weapon.cannon","preparation event identifies carrier and installed cannon")
 check(#prepared>preparedStart and #shots>shotStart,"Rattler prepares and fires cannon")
 check(shots[shotStart+1].kind=="Rattler" and shots[shotStart+1].time-prepared[preparedStart+1].time>=cannon.FireWindup-1e-5,"cannon release follows windup and correct model identity")
 check(wheeledLift==0 and (snapshots[rattlerId].flightShotSerial or 0)==0,"cannon-equipped Rattler no longer jackhammers")
 check(math.abs(snapshots[rattlerId].aimRecoilYaw or 0)>0,"cannon still displaces actual turret")
 -- Weapon tuning/attribution travels into the actual server projectile records.
 local shells
 for _,p in created do if p.Name=="ArtilleryShells" then shells=p end end
 check(shells~=nil,"production projectile scene exists")
 tick(false); advance(30); reset.OnServerEvent:Fire(first); advance(6)
 check(snapshots[boomerId].weaponId=="weapon.gatling" and snapshots[rattlerId].weaponId=="weapon.cannon","reset preserves swapped loadouts")
 check((snapshots[boomerId].flightShotSerial or 0)==0 and (snapshots[boomerId].heat or 0)==0 and snapshots[boomerId].health==100,"reset clears transferred recoil/weapon state")
 -- Exercise BW with the swapped guns through the real server input adapter.
 bwRun.OnServerEvent:Fire(first,'fire(1)',1,boomerId); advance(75)
 check((snapshots[boomerId].weaponShotSerial or 0)>2 and (snapshots[boomerId].flightShotSerial or 0)>2,"BW drives transferred Gatling and recoil")
 bwStop.OnServerEvent:Fire(first,2,boomerId); advance(180)
 check(not snapshots[boomerId].bwRunning and snapshots[boomerId].lift==0,"BW stop releases transferred gun and lands")
 -- The inverse profile also proves recoil can follow the same gun on either body.
 local back=Components.forWeapon("Rattler","weapon.gatling")
 local inverse=Sim.new(Vector3.zero,"Rattler",123,back)
 Recoil.kick(inverse,1,Vector3.new(0,0,-1)); check(inverse.verticalSpeed>0,"gun recoil is reusable on either mobility")
 local noGun=Sim.new(Vector3.zero,"Boomer",123,Components.forWeapon("Boomer","weapon.cannon"))
 Recoil.kick(noGun,1,Vector3.new(0,0,-1)); check((noGun.verticalSpeed or 0)==0,"removing gun removes recoil behavior from either body")
 local registry=require("TankRenderers")
 boomer.generation=0
 local art={test=boomer}; local visualState=Sim.new(Vector3.zero,"Boomer",123,Components.forWeapon("Boomer","weapon.cannon"))
 local oldModel=boomer.model
 registry.sync(art,{test=visualState},Renderer.new)
 check(oldModel.destroyed and not art.test.gatling and #art.test.treads==0 and #art.test.wheels==4,"weapon descriptor change rebuilds gun without changing body type")
 -- Function-bearing source through production networking and runtime snapshots.
 reset.OnServerEvent:Fire(first); advance(6)
 local functionSource=[[function twice(const n):
    return n * 2
function observe(const slot):
    snapshot = Scanner(position=slot)
    return snapshot.status
with thread(1):
    print(twice(21))
with thread(2):
    print(observe(0))]]
 bwRun.OnServerEvent:Fire(first,functionSource,901,rattlerId); advance(120)
 check(snapshots[rattlerId].bwStatus=="completed","server accepts concurrent user functions and scanner-return continuation")
 local sawReturn,sawScan=false,false
 for _,event in privateOutputs do
  if event.args[1]==rattlerId and event.args[3]==901 then
   local entry=event.args[4]
   if type(entry)=="table" and entry.kind=="print" then
    if entry.text=="42" and entry.thread==1 then sawReturn=true end
    if entry.text=="success" and entry.thread==2 then sawScan=true end
   end
  end
 end
 check(sawReturn and sawScan,"function returns reach correct thread/request private IDE logs")
 bwRun.OnServerEvent:Fire(first,"function hold():\n    clock = get_clock()\n    wait_for_clock(clock.time + 100)\nhold()",902,rattlerId); advance(30)
 check(snapshots[rattlerId].bwRunning and snapshots[rattlerId].bwLine==3,"public execution highlighting follows current function source line")
 local foundDepth=false
 for _,event in privateRuntime do
  local reading=event.args[2]
  if event.args[1]==rattlerId and reading.requestId==902 and reading.runtime then
   local thread=reading.runtime.threads[1]
   if thread.callDepth==1 and thread.functionName=="hold" and thread.line==3 then foundDepth=true end
  end
 end
 check(foundDepth,"private runtime diagnostics replicate function name/depth/line")
 bwStop.OnServerEvent:Fire(first,903,rattlerId); advance(12)
 check(not snapshots[rattlerId].bwRunning,"server Stop cleans suspended function and returns control")
 check(snapshots[rattlerId].variables==nil,"function locals stay private rather than entering public snapshots")
 boomer=art.test
 boomer:destroy(); rattler:destroy()
 os.clock=savedClock; workspace.FindFirstChild=originalWorkspaceFind
end -- server fixture
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
print(string.format("Live swapped-weapon integration passed: %d assertions",count))

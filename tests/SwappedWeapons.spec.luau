 -- Continuation of the shared production server fixture (live assemblies).
 local Components=require("VehicleComponents")
 local Catalog=require("ComponentCatalog")
 local Assemblies=require("VehicleAssemblies")
 local Recoil=require("RattlerRecoil")
 check(Assemblies.Boomer.Weapon=="weapon.gatling" and Assemblies.Rattler.Weapon=="weapon.cannon","live assemblies swap installed weapon IDs")
 check(snapshots[boomerId].weaponId=="weapon.gatling" and snapshots[rattlerId].weaponId=="weapon.cannon","server publishes installed weapon descriptor")
 check(Components.get("Boomer").Mobility.Kind=="Tracked" and Components.get("Rattler").Mobility.Kind=="Wheeled","bodies retain original mobility")
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
 check(#boomer.treads==56 and #named(boomer,"ChunkyTire")==0 and boomer.chassis.Color[1]==245,"Boomer keeps original body/tracks/palette")
 check(not rattler.gatling and not rattler.jackhammer and #named(rattler,"Cannon")==1 and #named(rattler,"GatlingBarrel")==0,"green wheeled body mounts visible cannon")
 check(#rattler.treads==0 and #named(rattler,"ChunkyTire")==4 and rattler.chassis.Color[2]==144,"Rattler keeps wheeled body/palette")
 local rstate=Sim.new(Vector3.zero,"Rattler")
 rattler:resetPose(rstate); rattler:fire(); rattler:update(rstate,0.1)
 check(rattler.barrelBulge.Transparency<1 and rattler.shotAge~=nil,"cannon swell transfers to wheeled body")
 rattler:update(rstate,0.3)
 check(rattler.barrelBulge.Transparency==1,"cannon swell cleans up")
 local bs=Sim.new(Vector3.new(0,4,0),"Boomer"); bs.lift=4; bs.flightRoll=.15; bs.flightShotSerial=1; bs.bodyRoll=.15; bs.firing=true
 boomer:resetPose(bs); boomer:fire({serial=2,roll=-.16}); boomer:update(bs,1/60)
 check(boomer.rotorAngle>0 and boomer.visualRollKick< -0.2,"Gatling rotation and exaggerated rocking transfer to tracked body")
 check(math.abs(boomer.left.CFrame.UpVector.X)>0.05,"track assemblies inherit weapon-induced rocking")
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
 check(oldModel.destroyed and not art.test.gatling and #art.test.treads==56,"weapon descriptor change rebuilds gun without changing body type")
 boomer=art.test
 boomer:destroy(); rattler:destroy()
 os.clock=savedClock; workspace.FindFirstChild=originalWorkspaceFind
end -- server fixture
CFrame.new,CFrame.Angles,CFrame.lookAt=saveNew,saveAngles,saveLookAt
Instance.new,game.GetService=saveInstance,saveService
print(string.format("Live swapped-weapon integration passed: %d assertions",count))

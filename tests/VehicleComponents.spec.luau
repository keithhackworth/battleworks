local C=require(Shared.VehicleComponents)
local Catalog=require(Shared.ComponentCatalog)
local Assemblies=require(Shared.VehicleAssemblies)
local Sim=require(Shared.TankSimulation)
local Input=require(Shared.InputCommand)
local P=require(Shared.BWParser)
local R=require(Shared.BWExecution)
local H=require(Shared.BWChassis)
local G=require(Shared.ScannerGeometry)
local Windup=require(Shared.WeaponWindup)
local Weapon=require(Shared.RattlerWeapon)
local Recoil=require(Shared.RattlerRecoil)
local checks=0
local function check(v,m) checks+=1; assert(v,m) end
local function near(a,b) return math.abs(a-b)<1e-7 end
local function upgrade(base,category,edit,capabilities)
 local catalog=C.copy(Catalog); local a=C.copy(Assemblies[base]); local old=catalog[a[category]]
 local id=old.Id..".test"; local entry=C.copy(old); entry.Id=id; catalog[id]=entry; a[category]=id
 edit(entry.Properties)
 if capabilities then entry.Capabilities=capabilities end
 return C.resolve(a,catalog),catalog,a
end
local function state(profile,model) return Sim.new(Vector3.zero,model or "Rattler",123,profile) end
local function drive(s,throttle,steer,n)
 local command=Input.neutral(); command.throttle=throttle; command.steer=steer
 for _=1,n do Sim.step(s,command,1/60,Vector2.new(2000,2000)) end
end
local function runtime(s,source)
 local instructions,e=P.parse(source); assert(instructions,e and e.message)
 local config=H.forTank(s)
 for device,field in {drivetrain="drivePerformance",turret="turretPerformance",weapon="weaponPerformance"} do s[field]=H.performance(config.devices[device].allocation,C.get(s).Bus) end
 return R.new(instructions,s,nil,config)
end
local function run(r,s,n)
 for _=1,n do Sim.step(s,r:step(s,1/60),1/60,Vector2.new(2000,2000)) end
end
for id,entry in Catalog do
 check(entry.Id==id and #entry.Type>0 and #entry.DisplayName>0 and type(entry.Properties)=="table","component identity and interface")
 check(not pcall(function() entry.Properties.Test=1 end),"immutable catalog")
end
check(Catalog["drive.classic"].DisplayName=="Scamper v0.1" and Catalog["drive.car"].DisplayName=="Stride 3.0","existing drivetrains have hardware names")
check(Catalog["drive.hyper_p35"].DisplayName=="Hyper P35","Hyper hardware identity")
local hyperAssembly=C.copy(Assemblies.Rattler); hyperAssembly.Drivetrain="drive.hyper_p35"
local hyperProfile=C.resolve(hyperAssembly)
local hyperTank=state(hyperProfile)
drive(hyperTank,1,0,180)
check(near(hyperTank.speed,35),"Hyper P35 reaches 35 studs/sec via existing simulation")
check(C.default("Rattler").Drivetrain.Speed==30 and C.default("Boomer").Drivetrain.Speed==24,"catalog addition does not replace installed drivetrains")
check(C.default("Boomer").Drivetrain.Speed==24 and C.default("Rattler").Drivetrain.Speed==30,"baseline propulsion preserved")
check(C.default("Boomer").Capabilities.Pivot and not C.default("Rattler").Capabilities.Pivot,"mobility pivot capability")
local boom=Sim.new(Vector3.zero,"Boomer"); drive(boom,1,0,60)
check(near(boom.position.Z,-24) and near(boom.speed,24),"Boomer legacy instant speed")
local car=Sim.new(Vector3.zero,"Rattler"); drive(car,1,0,60)
check(near(car.speed,22) and car.position.Z< -10 and car.position.Z> -12,"Rattler legacy acceleration")
local fast,catalog,assembly=upgrade("Rattler","Drivetrain",function(p) p.Speed=60; p.ReverseSpeed=36; p.Acceleration=44 end)
local f=state(fast); drive(f,1,0,180); check(near(f.speed,60),"drivetrain-only speed/acceleration upgrade")
local rev=state(fast); drive(rev,-1,0,120); check(near(rev.speed,-36),"independent reverse rating")
check(fast.Mobility.MaxSteer==C.default("Rattler").Mobility.MaxSteer and fast.Weapon.Damage==6,"unrelated components unchanged")
catalog[assembly.Drivetrain].Properties.Speed=900
check(fast.Drivetrain.Speed==60 and C.get(car).Drivetrain.Speed==30,"resolution copy isolation")
check(not pcall(function() C.get(f).Drivetrain.Speed=1 end),"runtime profile immutable")
check(f.components==nil and f.configuration==nil,"no configuration graph added to public simulation state")
local short=upgrade("Rattler","Mobility",function(p) p.Wheelbase=2.6; p.MaxYawRate=4 end)
local normalCar=state(C.default("Rattler")); local shortCar=state(short)
drive(normalCar,1,0.5,90); drive(shortCar,1,0.5,90)
check(math.abs(shortCar.yaw)>math.abs(normalCar.yaw)*1.9 and near(shortCar.speed,normalCar.speed),"mobility-only radius change without propulsion multiplier")
local trackedAssembly=C.copy(Assemblies.Rattler); trackedAssembly.Mobility="mobility.tracks"
local tracks=C.resolve(trackedAssembly); local disguised=state(tracks,"Rattler")
drive(disguised,0,1,60)
check(near(disguised.yaw,1.8) and disguised.position.Magnitude==0,"installed tracked mobility pivots on Rattler model")
local wheelsAssembly=C.copy(Assemblies.Boomer); wheelsAssembly.Mobility="mobility.wheels"
local wheels=C.resolve(wheelsAssembly); local disguisedBoomer=state(wheels,"Boomer")
drive(disguisedBoomer,0,1,60); check(near(disguisedBoomer.yaw,0),"installed wheels cannot pivot on Boomer model")
drive(disguisedBoomer,1,1,60); check(disguisedBoomer.yaw>0 and disguisedBoomer.steeringAngle>0,"installed wheels curve on Boomer model")
local tank=state(C.default("Boomer"),"Boomer"); local tr=runtime(tank,'steer_right(20)\nforward()'); run(tr,tank,120)
check(tank.yaw< -1 and tank.speed>0 and tr.status=="running" and tr.cyclesSpent==2,"tracked persistent steering while driving at unchanged CPU cost")
local centered=state(C.default("Boomer"),"Boomer"); local cr=runtime(centered,'steer_right(20)\nforward()\nc = get_clock()\nwait_for_clock(c.time + 1)\nsteer_center()'); run(cr,centered,180)
local yaw=centered.yaw; run(cr,centered,60); check(near(yaw,centered.yaw) and centered.speed>0,"tracked centering without stop")
local noSteer=upgrade("Boomer","Mobility",function() end,{Steer=false,Pivot=false})
local ns=state(noSteer,"Rattler"); local nr=runtime(ns,'a = steer_left(20)\nb = turn_right(30)\nforward()'); run(nr,ns,60)
check(nr.variables.a.reason=="unsupportedDrivetrain" and nr.variables.b.reason=="unsupportedDrivetrain" and ns.speed>0 and ns.yaw==0,"unsupported capability determined by component, not model")
local noPivot=upgrade("Boomer","Mobility",function() end,{Steer=true,Pivot=false})
local np=state(noPivot,"Boomer"); drive(np,0,1,60); check(np.yaw==0,"tracked pivot disabled")
drive(np,1,1,60); check(np.yaw>1,"nonpivot tracks still steer while moving")
local nav=runtime(np,'turn_left(30)'); run(nav,np,600); check(nav.status=="completed",nav.message)
local turret=upgrade("Boomer","Turret",function(p) p.TraverseSpeed=1.75; p.MuzzleHeight=7.2 end)
local t=state(turret,"Boomer"); local cmd=Input.neutral(); cmd.turretX=1
for _=1,60 do Sim.step(t,cmd,1/60) end
check(near(t.turretYaw,-1.75) and near(select(1,Sim.shotPose(t)).Y,7.2),"independent turret traverse and mount height")
local cannon=upgrade("Boomer","Weapon",function(p) p.FireWindup=0.4; p.Cooldown=1.3; p.Damage=50; p.ShellSpeed=48 end)
local cs=state(cannon,"Boomer"); cmd=Input.neutral(); cmd.fire=true; local pending=Windup.begin(cs,cmd)
check(near(pending.remaining,0.4) and near(cs.cooldown,1.3) and C.get(cs).Weapon.Damage==50,"cannon consumes resolved weapon timing/damage")
local heated=upgrade("Rattler","Weapon",function(p) p.Cooldown=0.2 end)
local w=Weapon.new(heated.Weapon); local shots=0
for _=1,60 do if Weapon.step(w,true,true,1/60) then shots+=1 end end
check(shots==5,"heat weapon consumes installed firing interval")
local noJack=C.copy(Assemblies.Rattler); noJack.Weapon="weapon.cannon"
local nj=state(C.resolve(noJack),"Rattler"); Recoil.kick(nj,1,Vector3.new(0,0,-1))
check((nj.verticalSpeed or 0)==0,"Rattler model does not imply jackhammer recoil")
local jack=C.copy(Assemblies.Boomer); jack.Weapon="weapon.gatling"
local js=state(C.resolve(jack),"Boomer"); Recoil.kick(js,1,Vector3.new(0,0,-1))
check(js.verticalSpeed>0,"installed weapon enables jackhammer independently of model")
local sensor=upgrade("Boomer","Sensor",function(p) p.Range=90; p.ConeWidth=30; p.Acquisition=0.2; p.Cooldown=0.4 end)
local ss=state(sensor,"Boomer"); local hardware=H.forTank(ss)
check(hardware.devices.sensor0.range==90 and hardware.devices.sensor0.coneWidth==30 and hardware.devices.sensor0.acquisition==0.2 and hardware.devices.sensor0.cooldown==0.4,"sensor hardware reaches BW device configuration")
local target=Vector3.new(math.sin(math.rad(12)),0,-math.cos(math.rad(12)))
check(not G.inCone(0,0,target) and G.inCone(0,0,target,sensor.Sensor.ConeWidth),"geometry respects component cone")
local acquiredAt
local scanR=R.new(assert(P.parse('s = Scanner(0)')),ss,{scan=function(angle,performance,time,props)
 acquiredAt=time; check(props.range==90 and props.coneWidth==30 and props.cooldown==0.4,"configured sensor acquisition arguments")
 local V=require(Shared.BWValue); return V.observation(V.result(nil,{count=0,sensor=angle,timestamp=time}),time,ss.position,ss.yaw)
end},hardware)
run(scanR,ss,360); check(acquiredAt and acquiredAt>=0.2 and scanR.status=="completed","physical acquisition uses configured timing")
local mounts=C.copy(Assemblies.Boomer); mounts.Sensors={[90]="sensor.standard"}
local ms=state(C.resolve(mounts),"Boomer"); local mh=H.forTank(ms)
check(mh.devices.sensor0==nil and mh.devices.sensor90~=nil,"installed sensors determine available pipelines")
local cpu=C.copy(Assemblies.Boomer); cpu.Computer="computer.Octa"
local cp=state(C.resolve(cpu),"Boomer"); local cpur=runtime(cp,'with thread(8):\n    done = true'); run(cpur,cp,12)
check(cpur.variables.done and cpur.config.tier=="Octa" and cpur.threads[8].state=="finished","computer component independent of vehicle identity")
local bus=upgrade("Boomer","Bus",function(p) p.PerformanceExponent=1 end)
check(near(H.performance(50,bus.Bus),0.5) and near(H.performance(50),0.75),"bus performance curve consumes component")
local hull=upgrade("Boomer","Chassis",function(p) p.Health=200; p.Radius=7; p.Hitbox.X=10 end)
local hs=state(hull,"Boomer"); check(hs.health==200 and C.get(hs).Chassis.Radius==7 and C.get(hs).Chassis.Hitbox.X==10 and C.get(hs).Drivetrain.Speed==24,"chassis durability/dimensions independent from propulsion")
local lifecycle=runtime(hs,'a = forward()\nb = back(5)'); run(lifecycle,hs,6)
check(lifecycle.devices:status(lifecycle.variables.a.commandId).state=="cancelled","component pipeline replacement status")
lifecycle:stop(); check(not lifecycle.devices:busy() and lifecycle.devices.steering==0 and lifecycle:step(hs,1/60).throttle==0,"component lifecycle cleanup")
local malformed={
 function(a,c) a.Drivetrain="weapon.cannon" end,
 function(a,c) a.Mobility="missing" end,
 function(a,c) c[a.Drivetrain].Properties.Speed=0 end,
 function(a,c) c[a.Mobility].Properties.MaxSteer=0 end,
 function(a,c) c[a.Chassis].Properties.Radius=math.huge end,
 function(a,c) c[a.Sensor].Properties.ConeWidth=181 end,
 function(a,c) c[a.Computer].Properties.ticks=10000 end,
 function(a,c) c[a.Bus].Properties.Capacity=200 end,
 function(a,c) a.Sensors={[0]="weapon.cannon"} end,
 function(a,c) a.Sensors={[100]="sensor.standard"} end,
 function(a,c) c[a.Chassis].Properties.MountingSlots.Sensor=1 end,
 function(a,c) c[a.Weapon].Properties.Aim.YawKick=nil end,
 function(a,c) c[a.Sensor].Properties.Acquisition=10 end,
}
for _,edit in malformed do local a=C.copy(Assemblies.Boomer); local c=C.copy(Catalog); edit(a,c); check(not pcall(C.resolve,a,c),"invalid component assembly rejected before physics") end
local stopTrack=state(C.default("Boomer"),"Boomer")
local str=runtime(stopTrack,'steer_right(20)\nforward()\nc = get_clock()\nwait_for_clock(c.time+1)\nstop()\nc = get_clock()\nwait_for_clock(c.time+2)')
run(str,stopTrack,90); local stoppedYaw=stopTrack.yaw; run(str,stopTrack,60)
check(near(stopTrack.yaw,stoppedYaw) and stopTrack.speed==0,"tracked stop releases both treads even while another instruction waits")
local beforeComputer=C.get(boom)
C.withComputer(f,"Quad")
check(C.get(f).Computer.Tier=="Quad" and C.get(boom)==beforeComputer and C.get(car).Computer.Tier=="Octa","dev computer selection isolates profiles")
local shell=require("ProjectileSimulation").new(Vector3.zero,Vector3.new(0,0,-1),{},cannon.Weapon)
check(shell.speed==48 and shell.damage==50,"projectiles consume resolved component tuning")
local Effects=require(Shared.DamageEffects); local effectState=state(hull,"Boomer"); Effects.new(effectState); effectState.health=100
check(Effects.severity(effectState)==1,"progressive damage thresholds scale with chassis durability")
local eighth=assert(P.parse('with thread(8):\n    done = true'))
local defaultBunny=R.new(eighth,Sim.new(Vector3.zero,"Boomer"))
local defaultOcta=R.new(eighth,Sim.new(Vector3.zero,"Rattler"))
check(defaultBunny.status=="error" and defaultOcta.config.tier=="Octa","runtime default derives installed computer without controller override")
local busState=state(bus,"Boomer"); local busRuntime=runtime(busState,'forward()'); run(busRuntime,busState,6)
check(near(busState.speed,24*0.4),"bus performance applied once to unscaled propulsion rating")
print('Vehicle component suite passed: '..checks..' assertions')

local Hardware=require("BWChassis")
local Components=require("VehicleComponents")
local Simulation=require("TankSimulation")
local Windup=require("WeaponWindup")
local Gatling=require("RattlerWeapon")
local Projectiles=require("ProjectileSimulation")
local Self=require("BWSelfState")
local Devices=require("BWDevices")
local Manual=require("ManualScanner")
local Scan=require("DirectionalScanner")
local Geometry=require("ScannerGeometry")
local Execution=require("BWExecution")
local Parser=require("BWParser")
local Command=require("InputCommand")
local Controller=require("BWController")
local Timing=require("WeaponTiming")
local count=0
local function check(ok,message) assert(ok,message);count+=1 end
local function near(a,b) return math.abs(a-b)<1e-7 end
local function draft(drive,turret,weapon,scanner,bias)
 return {allocations={drivetrain=drive,turret=turret,weapon=weapon,scanners=scanner},tuning={weapon=bias,scanners=bias}}
end
local boomer=Components.get("Boomer")
local function compile(profile,drive,turret,weapon,scanner,bias)
 return assert(Hardware.fromCategories(draft(drive,turret,weapon,scanner,bias),profile,"Bunny"))
end
check(not Hardware.fromCategories(draft(30,30,30,30,.5),boomer,"Bunny"),"overallocated master bus is rejected")
check(not Hardware.fromCategories(draft(30,0,20,50,0/0),boomer,"Bunny"),"invalid tuning is rejected")
check(not Hardware.fromCategories(draft(0,0,math.huge,0,.5),boomer,"Bunny"),"invalid master power is rejected")
local legacy=Hardware.forTank("Rattler")
local converted=Hardware.categoryDraft(legacy)
local sum=0;for _,n in converted.allocations do sum+=n end
check(near(sum,100) and converted.tuning.weapon==.5 and converted.tuning.scanners==.5,"legacy multibus reservations normalize into a balanced single budget")
local public=Hardware.playgroundDefault(boomer)
check(near(public.allocations.scanners,800/11) and near(public.devices.sensor315.allocation,100/11) and Hardware.validate(public),"public default retains eight equal subdivisions and four categories")
local twoLenses=Components.copy(require("VehicleAssemblies").Boomer)
twoLenses.Sensors={[0]="sensor.standard",[180]="sensor.standard"}
local partial=compile(Components.resolve(twoLenses),0,0,0,40,.5)
check(partial.devices.sensor0.allocation==20 and partial.devices.sensor180.allocation==20 and partial.devices.sensor45==nil,"scanner budget is divided only among installed physical lenses")
for _,anchor in {{5,5},{30,90},{50,110},{100,180}} do
 local master,cone=anchor[1],anchor[2]
 for _,bias in {0,.5,1} do
  local config=compile(boomer,0,0,0,master,bias)
  check(Hardware.validate(config) and near(config.devices.sensor0.coneWidth,cone*(1-.25*bias)),"array aperture follows master power and slider position")
  check(config.devices.sensor315.coneWidth==config.devices.sensor0.coneWidth and config.devices.sensor0.allocation==master/8,"array aperture does not multiply the per-lens bus share")
 end
end
local wideAngle=compile(boomer,0,0,0,100,0).devices.sensor0.coneWidth
for _,anchor in {{0,0,40},{30,.5,100},{50,.5,120},{100,1,200}} do
 local config=compile(boomer,0,0,0,anchor[1],anchor[2])
 check(Hardware.validate(config) and near(config.devices.sensor0.range,anchor[3]),"scanner range matches calibration")
end
check(Geometry.inCone(0,0,Vector3.new(1,0,-.01),wideAngle) and not Geometry.inCone(0,0,Vector3.new(1,0,.01),wideAngle),"wide cone reaches the sides and excludes targets behind it")
for _,bias in {0,.5,1} do
 for _,kind in {"Boomer","Rattler"} do
  local profile=Components.get(kind)
  local low=compile(profile,5,5,10,10,bias)
  local high=compile(profile,5,5,40,40,bias)
  local rate,windup,speed=Hardware.weaponStats(low,profile)
  local highRate,highWindup,highSpeed=Hardware.weaponStats(high,profile)
  check(rate<highRate and windup<highWindup and speed<highSpeed,"all weapon capabilities improve with master power")
  local before,after=low.devices.sensor0,high.devices.sensor0
  check(before.range<after.range and before.coneWidth<after.coneWidth,"both scanner capabilities improve with master power")
  check(after.range>=40 and after.range<=200 and after.coneWidth>0 and after.coneWidth<=180,"scanner remains within useful limits")
  check(highSpeed>=.65*profile.Weapon.ShellSpeed and highSpeed<=profile.Weapon.ShellSpeed,"projectile speed stays within useful limits")
  check(after.allocation==5 and high.devices.sensor315.allocation==5 and high.devices.sensor0.bus==1,"40 percent array grants five percent per physical mount")
  check(near(Hardware.driveRates(profile,Hardware.effective(low,"drivetrain",profile)),15),"five percent retains the drivetrain anchor")
 end
end
local narrow=compile(boomer,5,5,40,40,1)
local wide=compile(boomer,5,5,40,40,0)
check(narrow.devices.sensor0.range>wide.devices.sensor0.range and narrow.devices.sensor0.coneWidth<wide.devices.sensor0.coneWidth,"range competes with cone")
local rate,windup,speed=Hardware.weaponStats(narrow,boomer)
local otherRate,otherWindup,otherSpeed=Hardware.weaponStats(wide,boomer)
check(rate>otherRate and speed<otherSpeed and windup==otherWindup,"weapon rate competes with speed without changing master windup")
local _,_,speedAtLimit=Hardware.weaponStats(compile(boomer,0,0,100,0,0),boomer)
local rateAtLimit=Hardware.weaponStats(compile(boomer,0,0,100,0,1),boomer)
check(speedAtLimit==boomer.Weapon.ShellSpeed and Timing.interval(boomer.Weapon,rateAtLimit)==boomer.Weapon.Cooldown,"full master power reaches each respective weapon mechanical cap")
local state=Simulation.new(Vector3.zero,"Boomer")
local tank={state=state,hardware=narrow}
Controller.applyHardware(tank)
local stateReading=Self.read("get_tank_state",state,narrow,0)
check(stateReading.bus.bus_count==1 and stateReading.bus.allocations.scanners==40 and stateReading.bus.tuning.scanners==1,"inspection reports canonical allocations")
check(near(stateReading.scanners[1].effective_range,narrow.devices.sensor0.range) and stateReading.scanners[1].effective_cone_degrees==narrow.devices.sensor0.coneWidth,"inspection reports the same scan geometry as dispatch")
check(near(stateReading.turret.effective_rotation_speed,math.deg(boomer.Turret.TraverseSpeed*state.turretPerformance)),"turret observation agrees with applied power")
local nozzle=Command.neutral();nozzle.fire=true
local pending=assert(Windup.begin(state,nozzle))
check(near(pending.remaining,stateReading.weapon.readiness.effective_preparation_seconds) and near(state.cooldown,stateReading.weapon.readiness.effective_fire_interval_seconds),"cannon uses actual published windup and reload")
local bullet=Projectiles.new(Vector3.zero,Vector3.new(0,0,-1),{},boomer.Weapon,0,{speed=state.projectileSpeed})
check(bullet.speed==stateReading.weapon.projectile_speed and Self.read("get_weapon_speed",state,narrow,0).speed==bullet.speed,"effective speed is used by projectile and both BW reads")
local rattler=Components.get("Rattler")
local gatlingConfig=compile(rattler,0,0,60,40,1)
local heat=Gatling.new(rattler.Weapon)
local gatlingRate,_,gatlingSpeed=Hardware.weaponStats(gatlingConfig,rattler)
check(Gatling.step(heat,true,true,.01,gatlingRate) and near(heat.shotClock,rattler.Weapon.Cooldown/gatlingRate),"Gatling cadence uses weapon tuning")
heat.heat=rattler.Weapon.MaxHeat
check(not Gatling.step(heat,true,true,.01,gatlingRate) and heat.cooldown==rattler.Weapon.OverheatCooldown,"Gatling retains mechanical overheat recovery")
local weak=compile(rattler,0,0,.001,0,.5)
local weakPower=Hardware.weaponStats(weak,rattler)
local weakHeat=Gatling.new(rattler.Weapon)
Gatling.step(weakHeat,true,true,.01,weakPower)
check(weakHeat.shotClock==Timing.interval(rattler.Weapon,weakPower),"very low-power timing respects the shared mechanical timer bound")
check(Projectiles.new(Vector3.zero,Vector3.new(0,0,-1),{},rattler.Weapon,0,{speed=gatlingSpeed}).speed==gatlingSpeed,"Gatling keeps physical projectile launch")
local disabled=compile(boomer,0,0,0,0,.5)
check(Hardware.validate(disabled) and disabled.devices.sensor0.coneWidth==0,"disabled array reports zero aperture")
local off={state=Simulation.new(Vector3.zero,"Boomer"),hardware=disabled}
Controller.applyHardware(off)
check(off.state.projectileSpeed==0 and off.state.turretPerformance==0 and off.state.drivePerformance==0 and not Windup.begin(off.state,nozzle),"zero power disables actuation and weapon")
local queue=Devices.new(disabled,off.state)
check(queue:submit("sensor0",{op="Scanner",value=0},0,1).reason=="deviceDisabled","zero-power array rejects BW scans")
local lowScanPower=compile(boomer,0,0,0,5,.5)
local scannerProgram=assert(Parser.parse("sector = 0\nobservation = Scanner(sector * 45)\nfinished_scan = true"))
local runtime=Execution.new(scannerProgram,state,{scan=function() return nil,"scannerBusy" end},lowScanPower)
runtime:step(state,.1)
local waiting=runtime:diagnostics()
check(waiting.threads[1].waiting=="scan" and waiting.devices.sensor0.active.acquisitionRemaining>4,"a 5% array shows a roughly four-second pending scan")
for _=1,44 do runtime:step(state,.1) end
check(runtime.variables.finished_scan and runtime.variables.observation.reason=="scannerBusy","a scan budget rejection resumes the waiting BW program with a failure result")
local manualCalls=0
local function scan() manualCalls+=1 end
Manual.step(off,true,0,.01,scan,function()end)
Manual.step(off,true,1,.01,scan,function()end)
check(manualCalls==0,"zero-power array cannot scan manually")
Manual.step(tank,true,0,.01,scan,function()end)
check(manualCalls==0,"manual radar waits for tuned acquisition")
Manual.step(tank,true,2,.01,scan,function()end)
check(manualCalls==8,"all physical manual scanning directions remain available")
local world={GetPartBoundsInRadius=function()return {}end,Raycast=function()return nil end}
local result=assert(Scan.new(world,function()return {},{},{}end):execute(tank,0,1,narrow.devices.sensor0)).value
check(result.range==stateReading.scanners[1].effective_range and result.cone_degrees==stateReading.scanners[1].effective_cone_degrees,"scanner uses exact configured geometry and emits effective metadata")
local copy=Hardware.copy(narrow)
check(copy.tuning.weapon==1 and copy.allocations.scanners==40 and copy.devices.sensor0~=narrow.devices.sensor0,"diagnostic copy preserves resolved configuration")
print("Bus configuration and live device tuning passed: "..count.." assertions")

local Garage=require("ShellGarage")
local created={}
local oldCreate=Instance.new
Instance.new=function(class)local obj=oldCreate(class);created[#created+1]=obj;return obj end
local saved
local function request(action,id,value)
 if action=="Read" then
  return {ok=true,choices={{id="Boomer/weapon.cannon",kind="Boomer",weapon="weapon.cannon",tier="Bunny",draft=draft(15,10,25,30,.5)}}}
 end
 saved=assert(Hardware.fromCategories(value,boomer,"Bunny"))
 return {ok=true,draft=Hardware.categoryDraft(saved)}
end
local view=Garage.new({parent=Instance.new("Frame"),home=function()end,garageRequest=request});view:enter()
local masters,secondary={},{}
for _,item in created do
 if item.Name=="Slider" then
  local name=item.Parent.Name
  if masters[name] then secondary[name]=item else masters[name]=item end
 end
end
local function findChild(parent,kind)
 for _,item in created do if item.Parent==parent and kind(item) then return item end end
end
local scanner=masters.Allocation_scanners
local thumb=findChild(secondary.Allocation_scanners,function(item)return item.Name=="Thumb" end)
local scannerTip=findChild(scanner.Parent,function(item)return item.ZIndex==5 and item.Text:find("Range") end)
local initial=scannerTip.Text
local input={UserInputType=Enum.UserInputType.MouseButton1,Position=Vector3.new(640,0,0)}
scanner.InputBegan:Fire(input)
check(scannerTip.Text~=initial and thumb.Position.X.Scale==.5,"master drag updates calculated tooltip while preserving the tuning thumb")
UIS.InputEnded:Fire(input)
local save,meshButton
for _,button in view.buttons do
 if button.Name=="SaveBus" then save=button elseif button.Name=="RetaliatorMesh" then meshButton=button end
end
save.Activated:Fire()
check(saved and saved.allocations.scanners==50 and saved.tuning.scanners==.5,"Garage clamps the sum and saves the same configuration the server compiles")
check(scannerTip.Text==string.format("Cone %.1f° | Range %.1f studs",saved.devices.sensor0.coneWidth,saved.devices.sensor0.range),"Garage tooltip equals server effective lens geometry")
input.Position=Vector3.new(scanner.AbsolutePosition.X,0,0)
scanner.InputBegan:Fire(input);UIS.InputEnded:Fire(input)
meshButton.Activated:Fire()
local meshSlider=masters.Allocation_retaliatorMesh
check(meshSlider.Parent.Visible,"equipping the Mesh opens its bus allocation slider")
input.Position=Vector3.new(meshSlider.AbsolutePosition.X+.25*meshSlider.AbsoluteSize.X,0,0)
meshSlider.InputBegan:Fire(input);UIS.InputEnded:Fire(input)
save.Activated:Fire()
check(saved.allocations.retaliatorMesh==25 and Hardware.retaliatorOperational(saved),"the Garage equips and powers the actual device")
meshButton.Activated:Fire();save.Activated:Fire()
check(not meshSlider.Parent.Visible and saved.devices.retaliatorMesh==nil,"the Garage removes the device and frees its bus allocation")
view:destroy();Instance.new=oldCreate
print("Garage dynamic preview and save passed")

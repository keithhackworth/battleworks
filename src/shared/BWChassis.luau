-- Gameplay hardware, independent of tank model and physical acceleration/recoil.
local ScannerConfig=require(script.Parent.ScannerConfig)
local Catalog=require(script.Parent.ComponentCatalog)
local Components=require(script.Parent.VehicleComponents)
local Assemblies=require(script.Parent.VehicleAssemblies)
local C={}
C.CyclesPerSecond=10
C.MaxOperationsPerCycle=512
C.CreditCycles=2
C.MaxInstructionCredit=1024
C.AcquisitionSeconds=Catalog["sensor.standard"].Properties.Acquisition
C.Tiers={}
for _,entry in Catalog do if entry.Type=="Computer" then C.Tiers[entry.Properties.Tier]=entry.Properties end end
C.Costs={read=0.1,write=0.2,arithmetic=0.2,comparison=0.2,logical=0.1,access=0.1,branch=1,loop=1,switch=2,print=0,sync=0.2,queue=1,
 aim_at=1,steer_left=1,steer_right=1,steer_center=1,stop=1,forward=1,back=1,turn_left=1,turn_right=1,turret_left=1,turret_right=1,turret_up=1,turret_down=1,Scanner=1,fire=2,get_clock=0,get_facing_direction=0.1,call=0}
C.IntrospectionCycles={is_weapon_ready=1,get_tank_state=2}
for _,name in {"get_weapon_speed","get_current_coordinates","get_weapon_type","get_turret_direction","get_drivetrain_type","get_bus_configuration"}do C.Costs[name]=1 end
C.Costs.get_tank_direction=C.Costs.get_facing_direction
function C.cost(name,tier)
 local cycles=C.IntrospectionCycles[name]
 return if cycles then cycles*C.Tiers[tier].ticks else C.Costs[name]or 0
end
C.TankTiers={}
for id,assembly in Assemblies do C.TankTiers[id]=Catalog[assembly.Computer].Properties.Tier end
C.Angles={0,45,90,135,180,225,270,315}
function C.performance(percent,bus) local a=math.clamp(percent/100,0,1); return 1-(1-a)^(if bus then bus.PerformanceExponent else Catalog["bus.standard"].Properties.PerformanceExponent) end
-- Forward-speed anchor before terrain/mobility modifiers. Only propulsion uses
-- this curve; scanner, weapon, turret, CPU budgets and bus capacity are unchanged.
C.DrivetrainCurve=table.freeze({allocation=5,speed=15})
function C.devicePerformance(name,percent,vehicle)
 if name~="drivetrain"then return C.performance(percent,vehicle.Bus)end
 local a=math.clamp(percent,0,100);local rating=vehicle.Drivetrain.Speed
 if rating<=0 then return 0 end
 local anchor=C.DrivetrainCurve
 local floor=math.min(anchor.speed,rating)/rating
 if a<=anchor.allocation then return floor*a/anchor.allocation end
 local fraction=(a-anchor.allocation)/(100-anchor.allocation)
 return floor+(1-floor)*(1-(1-fraction)^vehicle.Bus.PerformanceExponent)
end
function C.default(tier,vehicle)
 local budget=if vehicle then vehicle.Bus else Catalog["bus.standard"].Properties
 local sensor=if vehicle then vehicle.Sensor else Catalog["sensor.standard"].Properties
 local spec=C.Tiers[tier or "Hexadeca"]; assert(spec,"Unknown chassis")
 local devices={drivetrain={bus=1,allocation=100},turret={bus=math.min(2,spec.threads),allocation=100},weapon={bus=math.min(3,spec.threads),allocation=100}}
 if spec.threads<4 then
  devices.drivetrain.allocation=budget.SharedDrive; devices.turret.allocation=budget.SharedTurret; devices.weapon.allocation=budget.SharedWeapon
  if spec.threads==2 then devices.weapon.bus=2 end
 end
 local sensorBuses={}; local counts={}
 for index in C.Angles do
  local bus=if spec.threads>=4 then 4+(index-1)%math.min(#C.Angles,spec.threads-3) else spec.threads
  sensorBuses[index]=bus; counts[bus]=(counts[bus] or 0)+1
 end
 for index,angle in C.Angles do
  if vehicle then sensor=vehicle.Sensors[angle]; if not sensor then continue end end
  local bus=sensorBuses[index]
  devices["sensor"..angle]={bus=bus,allocation=if spec.threads>=4 then 100/counts[bus] else budget.SharedSensor,
   acquisition=sensor.Acquisition,range=sensor.Range,distancePercent=sensor.DistancePercent,coneWidth=sensor.ConeWidth,cooldown=sensor.Cooldown,originHeight=sensor.OriginHeight}
 end
 return {tier=tier or "Hexadeca",devices=devices}
end
function C.forTank(vehicle) local profile=Components.get(vehicle); return C.default(profile.Computer.Tier,profile) end
C.Categories={"drivetrain","turret","weapon","scanners"}
C.RetaliatorMesh=Catalog["sensor.retaliator_mesh"]
local ProjectileFloor,TradeoffFloor=.65,.75
local function boosted(base,floor,power)
 return base*(floor+(1-floor)*power)
end
-- Aperture is a shared array setting. Interpolate between the wide-end
-- calibration points, then apply the cone/range slider's tradeoff.
local ConeCurve={{0,0},{5,5},{30,90},{50,110},{100,180}}
local BalancedRangeCurve={{0,40},{30,100},{50,120},{100,180}}
local function interpolate(curve,master)
 for i=2,#curve do
  local lower,upper=curve[i-1],curve[i]
  if master<=upper[1] then
   local position=(master-lower[1])/(upper[1]-lower[1])
   return lower[2]+(upper[2]-lower[2])*position
  end
 end
 return curve[#curve][2]
end
function C.weaponStats(config,vehicle)
 local allocation=config.devices.weapon and config.devices.weapon.allocation or 0
 local power=C.devicePerformance("weapon",allocation,vehicle)
 local weapon=vehicle.Weapon
 if not config.tuning then return power,power,weapon.ShellSpeed end
 local bias=config.tuning.weapon
 local rate=power*(TradeoffFloor+(1-TradeoffFloor)*bias)
 local speed=if power>0 then boosted(weapon.ShellSpeed,ProjectileFloor,power*(1-(1-TradeoffFloor)*bias)) else 0
 return rate,power,speed
end
function C.effective(config,name,vehicle)
 local device=config.devices[name]
 if not device then return 0 end
 if name=="retaliatorMesh" then return if C.retaliatorOperational(config) then 1 else 0 end
 if name=="weapon" then return (C.weaponStats(config,vehicle)) end
 return C.devicePerformance(name,device.allocation,vehicle)
end
function C.retaliatorOperational(config)
 local device=config and config.devices.retaliatorMesh
 return device~=nil and device.componentId==C.RetaliatorMesh.Id
  and device.allocation>=C.RetaliatorMesh.Properties.MinimumAllocation
end
function C.driveRates(vehicle,power)
 local mobility=vehicle.Mobility
 local forward,reverse=vehicle.Drivetrain.Speed*power,vehicle.Drivetrain.ReverseSpeed*power
 local maximum=if not vehicle.Capabilities.Steer then 0 elseif mobility.Kind=="Wheeled" then mobility.MaxYawRate else mobility.TurnSpeed
 local turn=if mobility.Kind=="Wheeled" then math.min(maximum,forward/mobility.Wheelbase*math.tan(mobility.MaxSteer)) else maximum*power
 return forward,reverse,turn,maximum
end
function C.categoryDraft(config)
 if config.allocations then
  return {allocations=table.clone(config.allocations),tuning=table.clone(config.tuning)}
 end
 local allocations={drivetrain=0,turret=0,weapon=0,scanners=0}
 local sum=0
 for _,name in {"drivetrain","turret","weapon"} do
  local device=config.devices[name]
  if device then allocations[name]=device.allocation;sum+=device.allocation end
 end
 for _,angle in C.Angles do
  local device=config.devices["sensor"..angle]
  if device then allocations.scanners+=device.allocation;sum+=device.allocation end
 end
 if sum>100 then for name,value in allocations do allocations[name]=value*100/sum end end
 return {allocations=allocations,tuning={scanners=.5,weapon=.5}}
end
local function bounded(value,maximum)
 return type(value)=="number" and value>=0 and value<=maximum
end
function C.fromCategories(draft,vehicle,tier)
 if type(draft)~="table" or type(draft.allocations)~="table" or type(draft.tuning)~="table" or not C.Tiers[tier] then return nil,"invalidConfiguration" end
 local allocations,tuning={},{}
 local total=0
 for _,name in C.Categories do
  local value=draft.allocations[name]
  if not bounded(value,100) then return nil,"invalidAllocation" end
  allocations[name]=value;total+=value
 end
 local meshAllocation=draft.allocations.retaliatorMesh
 if meshAllocation~=nil then
  if not bounded(meshAllocation,100) then return nil,"invalidAllocation" end
  allocations.retaliatorMesh=meshAllocation
  total+=meshAllocation
 end
 if total>100+1e-8 then return nil,"busOverallocated" end
 for _,name in {"scanners","weapon"} do
  local bias=draft.tuning[name]
  if not bounded(bias,1) then return nil,"invalidTuning" end
  tuning[name]=bias
 end
 local count=0
 for _ in vehicle.Sensors do count+=1 end
 if count==0 and allocations.scanners>0 then return nil,"noScanners" end
 local config={tier=tier,devices={},allocations=allocations,tuning=tuning}
 for _,name in {"drivetrain","turret","weapon"} do config.devices[name]={bus=1,allocation=allocations[name]} end
 if meshAllocation~=nil then
  config.devices.retaliatorMesh={bus=1,allocation=meshAllocation,componentId=C.RetaliatorMesh.Id}
 end
 if count>0 then
  local allocation=allocations.scanners/count
  local bias=tuning.scanners
  local master=allocations.scanners
  local coneWidth=interpolate(ConeCurve,master)*(1-(1-TradeoffFloor)*bias)
  local rangeWeight=TradeoffFloor+(1-TradeoffFloor)*bias
  local balancedWeight=(1+TradeoffFloor)/2
  local range=40+(interpolate(BalancedRangeCurve,master)-40)*rangeWeight/balancedWeight
  for angle,sensor in vehicle.Sensors do
   config.devices["sensor"..angle]={bus=1,allocation=allocation,acquisition=sensor.Acquisition,
    range=range,
    distancePercent=sensor.DistancePercent,
    coneWidth=coneWidth,
    cooldown=sensor.Cooldown,originHeight=sensor.OriginHeight}
  end
 end
 return config
end
function C.playgroundDefault(vehicle)
 local legacy=C.default("Bunny",vehicle)
 local count=0
 for _ in legacy.devices do count+=1 end
 for _,device in legacy.devices do device.allocation=100/count end
 return assert(C.fromCategories(C.categoryDraft(legacy),vehicle,"Bunny"))
end
function C.validate(config)
 if type(config)~="table" or not C.Tiers[config.tier] or type(config.devices)~="table" then return nil,"invalidChassis" end
 local spec=C.Tiers[config.tier]; local sums={}; local count=0
 local maxDevices=if config.devices.retaliatorMesh then 12 else 11
 for name,d in config.devices do
  count+=1
  if count>maxDevices or type(name)~="string" or not (name=="drivetrain" or name=="turret" or name=="weapon" or name=="retaliatorMesh" or (name:match("^sensor%d+$") and table.find(C.Angles,tonumber(name:sub(7))))) then return nil,"invalidDevice" end
  if type(d)~="table" or type(d.bus)~="number" or d.bus%1~=0 or d.bus<1 or d.bus>spec.threads then return nil,"invalidBus" end
  if type(d.allocation)~="number" or d.allocation~=d.allocation or d.allocation<0 or d.allocation>100 then return nil,"invalidAllocation" end
  if name=="retaliatorMesh" and (d.componentId~=C.RetaliatorMesh.Id or d.bus~=1
   or type(config.allocations)~="table" or d.allocation~=config.allocations.retaliatorMesh) then return nil,"invalidDevice" end
  if d.acquisition~=nil and (type(d.acquisition)~="number" or d.acquisition~=d.acquisition or d.acquisition<0 or d.acquisition>5) then return nil,"invalidAcquisition" end
  if d.range~=nil and (type(d.range)~="number" or d.range~=d.range or d.range<=0 or d.range>ScannerConfig.MaxHardwareRange) then return nil,"invalidRange" end
  if d.distancePercent~=nil and (type(d.distancePercent)~="number" or d.distancePercent~=d.distancePercent or d.distancePercent<0 or d.distancePercent>100) then return nil,"invalidRange" end
  if d.coneWidth~=nil and (not bounded(d.coneWidth,180) or (d.coneWidth==0 and d.allocation>0)) then return nil,"invalidCone" end
  if d.cooldown~=nil and (type(d.cooldown)~="number" or d.cooldown~=d.cooldown or d.cooldown<=0 or d.cooldown>5) then return nil,"invalidCooldown" end
  if d.originHeight~=nil and (type(d.originHeight)~="number" or d.originHeight~=d.originHeight or math.abs(d.originHeight)>50) then return nil,"invalidOrigin" end
  sums[d.bus]=(sums[d.bus] or 0)+d.allocation
  if sums[d.bus]>100+1e-8 then return nil,"busOverallocated" end
 end
 return true
end
function C.copy(config)
 local out={tier=config.tier,devices={}}
 if config.allocations then out.allocations=table.clone(config.allocations);out.tuning=table.clone(config.tuning) end
 for k,d in config.devices do out.devices[k]={bus=d.bus,allocation=d.allocation,acquisition=d.acquisition,range=d.range,distancePercent=d.distancePercent,coneWidth=d.coneWidth,cooldown=d.cooldown,originHeight=d.originHeight,componentId=d.componentId} end
 return out
end
return C

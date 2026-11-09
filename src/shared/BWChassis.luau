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
 steer_left=1,steer_right=1,steer_center=1,stop=1,forward=1,back=1,turn_left=1,turn_right=1,turret_left=1,turret_right=1,Scanner=1,fire=2,get_clock=0,get_facing_direction=0.1,call=0}
C.TankTiers={}
for id,assembly in Assemblies do C.TankTiers[id]=Catalog[assembly.Computer].Properties.Tier end
C.Angles={0,45,90,135,180,225,270,315}
function C.performance(percent,bus) local a=math.clamp(percent/100,0,1); return 1-(1-a)^(if bus then bus.PerformanceExponent else Catalog["bus.standard"].Properties.PerformanceExponent) end
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
function C.validate(config)
 if type(config)~="table" or not C.Tiers[config.tier] or type(config.devices)~="table" then return nil,"invalidChassis" end
 local spec=C.Tiers[config.tier]; local sums={}; local count=0
 for name,d in config.devices do
  count+=1
  if count>11 or type(name)~="string" or not (name=="drivetrain" or name=="turret" or name=="weapon" or (name:match("^sensor%d+$") and table.find(C.Angles,tonumber(name:sub(7))))) then return nil,"invalidDevice" end
  if type(d)~="table" or type(d.bus)~="number" or d.bus%1~=0 or d.bus<1 or d.bus>spec.threads then return nil,"invalidBus" end
  if type(d.allocation)~="number" or d.allocation~=d.allocation or d.allocation<0 or d.allocation>100 then return nil,"invalidAllocation" end
  if d.acquisition~=nil and (type(d.acquisition)~="number" or d.acquisition~=d.acquisition or d.acquisition<0 or d.acquisition>5) then return nil,"invalidAcquisition" end
  if d.range~=nil and (type(d.range)~="number" or d.range~=d.range or d.range<=0 or d.range>ScannerConfig.MaxHardwareRange) then return nil,"invalidRange" end
  if d.distancePercent~=nil and (type(d.distancePercent)~="number" or d.distancePercent~=d.distancePercent or d.distancePercent<0 or d.distancePercent>100) then return nil,"invalidRange" end
  if d.coneWidth~=nil and (type(d.coneWidth)~="number" or d.coneWidth~=d.coneWidth or d.coneWidth<=0 or d.coneWidth>180) then return nil,"invalidCone" end
  if d.cooldown~=nil and (type(d.cooldown)~="number" or d.cooldown~=d.cooldown or d.cooldown<=0 or d.cooldown>5) then return nil,"invalidCooldown" end
  if d.originHeight~=nil and (type(d.originHeight)~="number" or d.originHeight~=d.originHeight or math.abs(d.originHeight)>50) then return nil,"invalidOrigin" end
  sums[d.bus]=(sums[d.bus] or 0)+d.allocation
  if sums[d.bus]>100+1e-8 then return nil,"busOverallocated" end
 end
 return true
end
function C.copy(config)
 local out={tier=config.tier,devices={}}
 for k,d in config.devices do out.devices[k]={bus=d.bus,allocation=d.allocation,acquisition=d.acquisition,range=d.range,distancePercent=d.distancePercent,coneWidth=d.coneWidth,cooldown=d.cooldown,originHeight=d.originHeight} end
 return out
end
return C

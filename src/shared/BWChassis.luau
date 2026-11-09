-- Gameplay hardware, independent of tank model and physical acceleration/recoil.
local ScannerConfig=require(script.Parent.ScannerConfig)
local C={}
C.CyclesPerSecond=10
C.MaxOperationsPerCycle=512
C.CreditCycles=2
C.MaxInstructionCredit=1024
C.AcquisitionSeconds=0.05
C.Tiers={Bunny={threads=1,ticks=10,queue=1},Dual={threads=2,ticks=15,queue=2},Quad={threads=4,ticks=20,queue=4},Octa={threads=8,ticks=30,queue=8},Hexadeca={threads=16,ticks=40,queue=16}}
C.Costs={read=0.1,write=0.2,arithmetic=0.2,comparison=0.2,logical=0.1,access=0.1,branch=1,loop=1,switch=2,print=0,sync=0.2,queue=1,
 forward=1,back=1,turn_left=1,turn_right=1,turret_left=1,turret_right=1,Scanner=1,fire=2,get_clock=0,get_facing_direction=0.1,call=0}
C.TankTiers={Boomer="Bunny",Rattler="Octa"}
C.Angles={0,45,90,135,180,225,270,315}
function C.performance(percent) local a=math.clamp(percent/100,0,1); return 1-(1-a)^2 end
function C.default(tier)
 local spec=C.Tiers[tier or "Hexadeca"]; assert(spec,"Unknown chassis")
 local devices={drivetrain={bus=1,allocation=100},turret={bus=math.min(2,spec.threads),allocation=100},weapon={bus=math.min(3,spec.threads),allocation=100}}
 if spec.threads<4 then
  devices.drivetrain.allocation=40; devices.turret.allocation=20; devices.weapon.allocation=20
  if spec.threads==2 then devices.weapon.bus=2 end
 end
 local sensorBuses={}; local counts={}
 for index in C.Angles do
  local bus=if spec.threads>=4 then 4+(index-1)%math.min(#C.Angles,spec.threads-3) else spec.threads
  sensorBuses[index]=bus; counts[bus]=(counts[bus] or 0)+1
 end
 for index,angle in C.Angles do
  local bus=sensorBuses[index]
  devices["sensor"..angle]={bus=bus,allocation=if spec.threads>=4 then 100/counts[bus] else 2.5,
   acquisition=C.AcquisitionSeconds,range=ScannerConfig.MaxRange,distancePercent=ScannerConfig.DistancePercent}
 end
 return {tier=tier or "Hexadeca",devices=devices}
end
function C.forTank(tankType) return C.default(C.TankTiers[tankType] or C.TankTiers.Boomer) end
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
  sums[d.bus]=(sums[d.bus] or 0)+d.allocation
  if sums[d.bus]>100+1e-8 then return nil,"busOverallocated" end
 end
 return true
end
function C.copy(config)
 local out={tier=config.tier,devices={}}
 for k,d in config.devices do out.devices[k]={bus=d.bus,allocation=d.allocation,acquisition=d.acquisition,range=d.range,distancePercent=d.distancePercent} end
 return out
end
return C

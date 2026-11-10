-- Resolve once, then consume immutable flat component records in simulation.
-- The weak registry deliberately keeps configuration out of public state packets.
local Catalog=require(script.Parent.ComponentCatalog)
local Assemblies=require(script.Parent.VehicleAssemblies)
local ScanPolicy=require(script.Parent.ScannerConfig)
local C={}
local bound=setmetatable({},{__mode="k"})
local defaults={}
local weaponProfiles={}
local categories={"Chassis","Drivetrain","Mobility","Turret","Weapon","Sensor","Computer","Bus"}
local function copy(v)
 if type(v)~="table" then return v end
 local out={}; for k,item in v do out[k]=copy(item) end; return out
end
C.copy=copy
local function freeze(v)
 if type(v)=="table" and not table.isfrozen(v) then for _,item in v do freeze(item) end; table.freeze(v) end
 return v
end
local function finite(v)
 if type(v)=="number" then assert(v==v and math.abs(v)<math.huge,"Non-finite component property")
 elseif type(v)=="table" then for _,item in v do finite(item) end
 else assert(type(v)=="string" or type(v)=="boolean","Component properties must be data") end
end
local function positive(t,key) assert(type(t[key])=="number" and t[key]>0,"Expected positive component property "..key) end
local function nonnegative(t,key) assert(type(t[key])=="number" and t[key]>=0,"Expected nonnegative component property "..key) end
function C.resolve(assembly,catalog)
 catalog=catalog or Catalog
 if type(assembly)=="string" then assembly=assert(Assemblies[assembly],"Unknown vehicle assembly") end
 assert(type(assembly)=="table","Vehicle assembly required")
 local out={Id=assembly.Id or "Custom",DisplayName=assembly.DisplayName or assembly.Id or "Custom",Installed={},Resolved=true}
 for _,kind in categories do
  local entry=assert(catalog[assembly[kind]],"Missing installed "..kind)
  assert(entry.Id==assembly[kind] and entry.Type==kind and type(entry.DisplayName)=="string","Invalid component identity/type: "..kind)
  out[kind]=copy(entry.Properties); finite(out[kind]); out.Installed[kind]=entry.Id
  if kind=="Mobility" then out.Capabilities=copy(entry.Capabilities or {}) end
 end
 nonnegative(out.Chassis,"HitboxHeight")
 positive(out.Chassis,"Health"); positive(out.Chassis,"Radius"); positive(out.Chassis,"ContactLength"); positive(out.Chassis,"ContactWidth")
 out.Chassis.Mass=out.Chassis.Mass or 1
 positive(out.Chassis,"Mass")
 out.Chassis.YawInertia=out.Chassis.YawInertia or out.Chassis.Mass*(out.Chassis.Hitbox.X^2+out.Chassis.Hitbox.Z^2)/12
 positive(out.Chassis,"YawInertia")
 out.Chassis.CollisionWidth=out.Chassis.CollisionWidth or out.Chassis.Radius*2
 out.Chassis.CollisionLength=out.Chassis.CollisionLength or out.Chassis.Radius*2
 positive(out.Chassis,"CollisionWidth"); positive(out.Chassis,"CollisionLength")
 for _,slot in {"Turret","Weapon","Drivetrain","Mobility","Computer","Bus"} do assert((out.Chassis.MountingSlots[slot] or 0)>=1,"Missing chassis mounting slot: "..slot) end
 for _,axis in {"X","Y","Z"} do positive(out.Chassis.Hitbox,axis) end
 positive(out.Drivetrain,"Speed"); positive(out.Drivetrain,"ReverseSpeed")
 assert(out.Drivetrain.Response=="Immediate" or out.Drivetrain.Response=="Accelerated","Unsupported propulsion response")
 if out.Drivetrain.Response=="Accelerated" then for _,k in {"Acceleration","Braking","CoastDrag"} do positive(out.Drivetrain,k) end end
 assert(out.Mobility.Kind=="Tracked" or out.Mobility.Kind=="Wheeled","Unsupported mobility solver")
 assert(out.Mobility.Motion=="Immediate" or out.Mobility.Motion=="Inertial","Unsupported motion solver")
 assert(type(out.Capabilities.Steer)=="boolean" and type(out.Capabilities.Pivot)=="boolean","Mobility capabilities required")
 for key,default in {LongitudinalGrip=1,LateralGrip=1,YawAcceleration=120} do
  out.Mobility[key]=out.Mobility[key] or default; positive(out.Mobility,key)
 end
 positive(out.Mobility,"MaxSteer")
 for _,key in {"Speed","Frequency","RollFrequency","Response","Spring","Damping"} do positive(out.Mobility.Suspension,key) end
 for _,key in {"Bob","Pitch","Roll"} do assert(type(out.Mobility.Suspension[key])=="number" and out.Mobility.Suspension[key]>=0,"Invalid suspension amplitude") end
 for _,key in {"Gravity","MaxFallSpeed","GroundFriction","MaxLift","RockRecovery","MaxLandingImpulse","DefaultSeed"} do positive(out.Mobility.Inertia,key) end
 if out.Mobility.Kind=="Wheeled" then
  assert(not out.Capabilities.Pivot,"Wheeled mobility cannot pivot in place")
  assert(out.Mobility.MaxSteer<math.pi/2,"Wheel steering must stay below 90 degrees")
  for _,k in {"Wheelbase","MaxYawRate","SteeringResponse"} do positive(out.Mobility,k) end
 else positive(out.Mobility,"TurnSpeed") end
 for _,k in {"TraverseSpeed","PitchSpeed","MuzzleHeight"} do positive(out.Turret,k) end
 assert(out.Turret.MinPitch<=out.Turret.MaxPitch,"Invalid turret limits")
 for _,k in {"Recovery","HeatReference"} do positive(out.Weapon.Aim,k) end
 for _,k in {"MaxYaw","MaxPitch","YawKick","PitchKick","HeatScale"} do nonnegative(out.Weapon.Aim,k) end
 assert(out.Weapon.Visual.Kind=="Cannon" or out.Weapon.Visual.Kind=="Gatling","Unsupported weapon visual")
 nonnegative(out.Weapon.Visual,"Recoil")
 assert(type(out.Weapon.Visual.Swelling)=="boolean","Weapon swelling flag required")
 assert(out.Weapon.Operation=="Windup" or out.Weapon.Operation=="Heat","Unsupported weapon operation")
 for _,k in {"Cooldown","Damage","Range","MuzzleOffset","ShellSpeed","ShellRadius"} do positive(out.Weapon,k) end
 if out.Weapon.Operation=="Heat" then for _,k in {"MaxHeat","MaxBurst","OverheatCooldown","RecoveryRate"} do positive(out.Weapon,k) end
 else nonnegative(out.Weapon,"FireWindup"); nonnegative(out.Weapon,"PreparationImpulse") end
 if out.Weapon.Trajectory then
  local path=out.Weapon.Trajectory
  assert(path.Kind=="DescendThenLevel" and path.DescentAngle>0 and path.DescentAngle<math.pi/2,"Unsupported projectile trajectory")
  positive(path,"LevelingDistance")
 end
 for _,k in {"Range","ConeWidth","Cooldown"} do positive(out.Sensor,k) end
 assert(out.Sensor.ConeWidth<=180 and out.Sensor.Acquisition>=0 and out.Sensor.Acquisition<=5 and out.Sensor.Cooldown<=5 and out.Sensor.Range<=ScanPolicy.MaxHardwareRange and math.abs(out.Sensor.OriginHeight)<=50 and out.Sensor.DistancePercent>=0 and out.Sensor.DistancePercent<=100,"Invalid scanner hardware")
 for _,key in {"SharedDrive","SharedTurret","SharedWeapon","SharedSensor"} do assert(type(out.Bus[key])=="number" and out.Bus[key]>=0 and out.Bus[key]<=100,"Invalid default bus allocation") end
 assert(out.Bus.Capacity==100,"Bus allocation uses a 100 percent capacity")
 positive(out.Bus,"PerformanceExponent")
 local computer=assert(Catalog["computer."..out.Computer.Tier],"Unsupported computer tier")
 for _,k in {"threads","ticks","queue"} do assert(out.Computer[k]==computer.Properties[k],"Computer must use a registered execution tier") end
 out.Recoil=copy(out.Mobility.Inertia)
 if out.Weapon.Recoil then for k,v in out.Weapon.Recoil do out.Recoil[k]=copy(v) end end
 if out.Weapon.Recoil then
  local kick=out.Recoil
  assert(kick.Kind=="Jackhammer","Unsupported recoil model")
  for _,key in {"MaxLift","MaxFallSpeed","InitialHopMin","InitialHopMax","HopMin","HopMax","MaxHorizontalSpeed","MaxBounceVelocity","MaxRollStreak"} do positive(kick,key) end
  for _,key in {"MinKickGap","MaxKickGap","MinKickDelay","MaxKickDelay","NearGroundChance","HorizontalImpulseMin","HorizontalImpulseMax","PitchJolt","RollJoltMin","RollJolt","MaxRock","LandingCompression"} do nonnegative(kick,key) end
  assert(kick.InitialHopMin<=kick.InitialHopMax and kick.InitialHopMax<=kick.MaxLift and kick.HopMin<=kick.HopMax and kick.HopMax<=kick.MaxLift,"Recoil peaks exceed safe lift")
  assert(kick.MinKickGap<=kick.MaxKickGap and kick.MinKickDelay<=kick.MaxKickDelay and kick.NearGroundChance<=1,"Invalid recoil timing")
 end
 out.Aim=out.Weapon.Aim
 out.Sensors={}
 local sensorCount=0
 local mounts=assembly.Sensors
 if mounts then
  assert(type(mounts)=="table","Sensor mounts must be a table")
  for angle in mounts do assert(type(angle)=="number" and angle>=0 and angle<=315 and angle%45==0,"Invalid sensor mounting angle") end
 end
 for _,angle in {0,45,90,135,180,225,270,315} do
  local id=if mounts then mounts[angle] else assembly.Sensor
  if id then
   local entry=assert(catalog[id],"Missing mounted sensor")
   assert(entry.Id==id and entry.Type=="Sensor","Invalid mounted sensor type")
   local sensor=copy(entry.Properties); finite(sensor)
   for _,k in {"Range","ConeWidth","Cooldown"} do positive(sensor,k) end
   assert(sensor.ConeWidth<=180 and sensor.Acquisition>=0 and sensor.Acquisition<=5 and sensor.Cooldown<=5 and sensor.Range<=ScanPolicy.MaxHardwareRange and math.abs(sensor.OriginHeight)<=50 and sensor.DistancePercent>=0 and sensor.DistancePercent<=100,"Invalid mounted sensor")
   sensorCount+=1
   out.Sensors[angle]=sensor; out.Installed["sensor"..angle]=id
  end
 end
 assert(sensorCount<=(out.Chassis.MountingSlots.Sensor or 0),"Sensor mounting capacity exceeded")
 return freeze(out)
end
function C.default(id)
 id=if Assemblies[id] then id else "Boomer"
 if not defaults[id] then defaults[id]=C.resolve(id) end
 return defaults[id]
end
-- Small client visual descriptor resolves a registered weapon on existing art.
function C.forWeapon(model,id)
 local profile=C.default(model)
 if not id or profile.Installed.Weapon==id then return profile end
 local key=(model or "Boomer").."/"..id
 if not weaponProfiles[key] then
  local assembly=copy(Assemblies[model] or Assemblies.Boomer); assembly.Weapon=id
  weaponProfiles[key]=C.resolve(assembly)
 end
 return weaponProfiles[key]
end
function C.bind(state,configuration)
 assert(configuration.Resolved,"Resolved components required"); bound[state]=configuration
 return state
end
-- Existing dev hardware selector installs a registered computer profile. It
-- cannot supply arbitrary budgets, and running programs cannot be reconfigured.
function C.withComputer(state,tier)
 local entry=assert(Catalog["computer."..tier],"Unsupported computer tier")
 local profile=C.get(state)
 if profile.Computer.Tier==tier then return profile end
 local updated=copy(profile); updated.Computer=copy(entry.Properties); updated.Installed.Computer=entry.Id
 updated=freeze(updated); C.bind(state,updated); return updated
end
function C.get(state)
 if type(state)=="string" or state==nil then return C.default(state) end
 return bound[state] or C.default(state.tankType)
end
return C

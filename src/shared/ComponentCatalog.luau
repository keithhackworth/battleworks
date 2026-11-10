-- Immutable tuning catalog. Assemblies install IDs; no vehicle-name dispatch here.
local C={}
local function freeze(value)
 if type(value)=="table" and not table.isfrozen(value) then for _,v in value do freeze(v) end; table.freeze(value) end
 return value
end
local function add(id,kind,name,properties,capabilities)
 C[id]={Id=id,Type=kind,DisplayName=name,Properties=properties,Capabilities=capabilities or {}}
end
add("chassis.standard","Chassis","Standard toy hull",{Mass=1,Health=100,Radius=5,ContactLength=5.6,ContactWidth=5,Hitbox={X=8,Y=5,Z=10},HitboxHeight=2.5,MountingSlots={Turret=1,Weapon=1,Sensor=8,Drivetrain=1,Mobility=1,Computer=1,Bus=1}})
add("drive.classic","Drivetrain","Scamper v0.1",{Speed=24,ReverseSpeed=24,Response="Immediate",Acceleration=2880,Braking=2880,CoastDrag=1440})
add("drive.car","Drivetrain","Stride 3.0",{Speed=30,ReverseSpeed=18,Response="Accelerated",Acceleration=22,Braking=38,CoastDrag=14})
-- Hyper shares Stride response tuning; only its forward rating differs.
add("drive.hyper_p35","Drivetrain","Hyper P35",{Speed=35,ReverseSpeed=18,Response="Accelerated",Acceleration=22,Braking=38,CoastDrag=14})
local inertia={Gravity=180,MaxFallSpeed=65,GroundFriction=8,MaxLift=6,RockRecovery=10,LandingCompression=0.3,MaxLandingImpulse=14,DefaultSeed=13579}
add("mobility.tracks","Mobility","Differential tracks",{LongitudinalGrip=1,LateralGrip=1,YawAcceleration=120,Kind="Tracked",Motion="Immediate",MaxSteer=math.rad(45),TurnSpeed=1.8,Inertia=inertia,
 Suspension={Bob=0.38,Pitch=0.05,Roll=0.035,Speed=24,Frequency=8,RollFrequency=0.8,Response=8,Spring=150,Damping=12}}, {Steer=true,Pivot=true})
add("mobility.wheels","Mobility","Steering wheels",{LongitudinalGrip=1,LateralGrip=1,YawAcceleration=120,Kind="Wheeled",Motion="Inertial",MaxSteer=0.55,Wheelbase=5.2,MaxYawRate=1.9,SteeringResponse=10,Inertia=inertia,
 Suspension={Bob=0,Pitch=0,Roll=0,Speed=24,Frequency=8,RollFrequency=0.8,Response=8,Spring=150,Damping=12}}, {Steer=true,Pivot=false})
add("turret.standard","Turret","Toy turret",{TraverseSpeed=3.5,PitchSpeed=1.1,MinPitch=math.rad(-12),MaxPitch=math.rad(30),MuzzleHeight=3.6})
add("weapon.cannon","Weapon","Cough cannon",{WeaponType="Cannon",Operation="Windup",Visual={Kind="Cannon",Swelling=true,Recoil=1},PreparationImpulse=0.6,FireWindup=0.20,Cooldown=0.65,Damage=25,Range=320,MuzzleOffset=7,ShellSpeed=24,ShellRadius=0.65,
 Aim={YawKick=math.rad(8),PitchKick=math.rad(6),MaxYaw=math.rad(12),MaxPitch=math.rad(9),Recovery=5,HeatScale=0,HeatReference=3}})
add("weapon.gatling","Weapon","Jackhammer Gatling",{WeaponType="Gatling",Operation="Heat",Visual={Kind="Gatling",Swelling=false,Recoil=0.65},
		Cooldown = 0.1, Damage = 6, Range = 320,
		MuzzleOffset = 7, ShellSpeed = 85, ShellRadius = 0.22,
		Trajectory = table.freeze({ Kind = "DescendThenLevel", DescentAngle = math.rad(35), LevelingDistance = 6 }),
		MaxHeat = 3, MaxBurst = 3, OverheatCooldown = 2,
		RecoveryDelay = 0.4, RecoveryRate = 0.6,
 Aim={YawKick=math.rad(2.4),PitchKick=math.rad(1.4),MaxYaw=math.rad(6),MaxPitch=math.rad(4),Recovery=4,HeatScale=0.4,HeatReference=3},
 Recoil={
		Kind = "Jackhammer", MaxLift = 6, BounceJoltMin=-2.5,BounceJoltMax=3.5,MaxBounceVelocity=8,MaxRollStreak=2,
		InitialHopMin = 4, InitialHopMax = 5, HopMin = 3.4, HopMax = 5.1,
		MinKickGap = 0.12, MaxKickGap = 0.24, MinKickDelay = 0.015, MaxKickDelay = 0.05,
		NearGroundChance = 0.18, HorizontalImpulseMin = 0.65, HorizontalImpulseMax = 1.15,
		MaxHorizontalSpeed = 36, DefaultSeed = 13579,
		PitchJolt = math.rad(7), RollJoltMin = math.rad(7), RollJolt = math.rad(10), MaxRock = math.rad(12), RockRecovery = 10,
		LandingCompression = 0.3, MaxLandingImpulse = 14,}})
add("sensor.standard","Sensor","Directional scanner",{Range=150,ConeWidth=15,Acquisition=0.05,Cooldown=0.1,OriginHeight=2.5,DistancePercent=100})
for name,spec in {Bunny={threads=1,ticks=10,queue=1},Dual={threads=2,ticks=15,queue=2},Quad={threads=4,ticks=20,queue=4},Octa={threads=8,ticks=30,queue=8},Hexadeca={threads=16,ticks=40,queue=16}} do
 spec.Tier=name; add("computer."..name,"Computer",name.." computer",spec)
end
add("bus.standard","Bus","Standard chassis bus",{Capacity=100,PerformanceExponent=2,SharedDrive=40,SharedTurret=20,SharedWeapon=20,SharedSensor=2.5})
return freeze(C)

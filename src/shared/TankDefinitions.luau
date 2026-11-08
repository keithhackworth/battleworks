-- Explicit allowlist and weapon tuning. Boomer retains the original tuning table.
local Config = require(script.Parent.TankConfig)
local Definitions = {}
Definitions.Boomer = table.freeze({
	Id = "Boomer", WeaponType = "Cannon", DisplayName = "Boomer", Weapon = Config,
	Aim = table.freeze({ YawKick = math.rad(8), PitchKick = math.rad(6), MaxYaw = math.rad(12), MaxPitch = math.rad(9), Recovery = 5 }),
})
Definitions.Rattler = table.freeze({
	Id = "Rattler", WeaponType = "Gatling", DisplayName = "Rattler",
	Weapon = table.freeze({
		Cooldown = 0.1, Damage = 6, Range = Config.Range,
		MuzzleOffset = 7, ShellSpeed = 85, ShellRadius = 0.22,
		Trajectory = table.freeze({ Kind = "DescendThenLevel", DescentAngle = math.rad(35), LevelingDistance = 6 }),
		MaxHeat = 3, MaxBurst = 3, OverheatCooldown = 2,
		RecoveryDelay = 0.4, RecoveryRate = 0.6,
	}),
	Aim = table.freeze({ YawKick = math.rad(2.4), PitchKick = math.rad(1.4), MaxYaw = math.rad(6), MaxPitch = math.rad(4), Recovery = 4 }),
	Drive = table.freeze({ Speed = 30, ReverseSpeed = 18, Acceleration = 22, Braking = 38, CoastDrag = 14, MaxSteer = 0.55, Wheelbase = 5.2, MaxYawRate = 1.9 }),
	Recoil = table.freeze({
		Gravity = 180, MaxLift = 6, MaxFallSpeed = 65,
		InitialHopMin = 4, InitialHopMax = 5, HopMin = 3.4, HopMax = 5.1,
		MinKickGap = 0.12, MaxKickGap = 0.24, MinKickDelay = 0.015, MaxKickDelay = 0.05,
		NearGroundChance = 0.18, HorizontalImpulseMin = 0.65, HorizontalImpulseMax = 1.15,
		MaxHorizontalSpeed = 36, GroundFriction = 8, DefaultSeed = 13579,
		PitchJolt = math.rad(7), RollJoltMin = math.rad(7), RollJolt = math.rad(10), MaxRock = math.rad(12), RockRecovery = 10,
		LandingCompression = 0.3, MaxLandingImpulse = 14,
	}),
})
function Definitions.valid(id) return type(id) == "string" and (id == "Boomer" or id == "Rattler") end
function Definitions.get(id) return if id == "Rattler" then Definitions.Rattler else Definitions.Boomer end
return table.freeze(Definitions)

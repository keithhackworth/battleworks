return table.freeze({
	Speed = 24, TurnSpeed = 1.8, TurretSpeed = 3.5, TurretPitchSpeed = 1.1,
	MinPitch = math.rad(-12), MaxPitch = math.rad(30),
	Radius = 5, ArenaLimit = 115, Health = 100,
	FireWindup = 0.20, -- cannon swell before shell release
	Cooldown = 0.65, Damage = 25, Range = 320,
	MuzzleHeight = 3.6, -- standard turret pivot/muzzle height above the arena floor
	MuzzleOffset = 7, -- turret pivot to cannon tip, before cosmetic recoil
	ShellSpeed = 24, ShellRadius = 0.65, -- server swept-sphere projectiles; studs/sec and studs
	Step = 1 / 60, SnapshotInterval = 1 / 20, InputTimeout = 0.35,
})

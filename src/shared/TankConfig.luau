return table.freeze({
	Speed = 24, TurnSpeed = 1.8, TurretSpeed = 3.5, TurretPitchSpeed = 1.1,
	MinPitch = math.rad(-12), MaxPitch = math.rad(30),
	Radius = 5, ArenaLimit = 115, Health = 100,
	Cooldown = 0.65, Damage = 25, Range = 320,
	Step = 1 / 60, SnapshotInterval = 1 / 20, InputTimeout = 0.35,
})

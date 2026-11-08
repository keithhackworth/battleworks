-- All tuning for attributed injuries, episodic handicaps and their bounded BW grace.
return table.freeze({
	Health=100,
	Thresholds={50,25,10},
	Weapons={Cannon={Effect="smoke",Destruction="Explosion"},Gatling={Effect="rattle",Destruction="Collapse"}},
	Smoke={Duration={1,1.5,2},Recovery={4.5,4,3.5},FirstDelay=0.8,MinRecovery=3.5},
	Rattle={Duration={0.3,0.6,1},Recovery={5,4,3},FirstDelay=0.5,MinRecovery=3},
	RattleVisualScale=2.5,
	MaxBWPausePerInstruction=8,
	MaxBulletHoles=36,
	BulletHoleScale=2,
	SmokePresentation={
		Texture="rbxasset://textures/particles/smoke_main.dds",
		VolumePadding=Vector3.new(1.6,1.5,1.6),
		BurstRate=48,InitialBurst=28,BurstScale=1.2,StreamRate=8,
	},
})

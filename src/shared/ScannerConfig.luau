-- BW observations are explicit; the selected manual tank gets a bounded sweep.
local Hardware=require(script.Parent.ComponentCatalog)["sensor.standard"].Properties
return table.freeze({
	ConeWidth=Hardware.ConeWidth,MaxRange=Hardware.Range,DistancePercent=Hardware.DistancePercent,MaxHardwareRange=1000,MinRange=0,OriginHeight=Hardware.OriginHeight,
	SurfaceTolerance=0.002,AngularEpsilon=1e-7,
	MaxSpatialParts=256,MaxCandidates=64,MaxRaycasts=512,
	SensorCooldown=Hardware.Cooldown,ServerRate=64,ServerBurst=16,
	ScannerCost=5, -- informational hook only; no CPU budget enforcement
	VisualDuration=1.2,SensorCount=8,MaxTremble=0.4,
	LensSize=1.3,ActiveLensSize=1.6,
	ManualSensorInterval=0.4,ManualStep=15,ManualVisualDuration=3,
	NearDistance=30,MidDistance=80,
})

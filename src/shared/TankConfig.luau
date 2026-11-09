-- Legacy default/transport facade. Runtime vehicles consume resolved components.
local Catalog=require(script.Parent.ComponentCatalog)
local C={Drivetrain=Catalog["drive.classic"].Properties,Mobility=Catalog["mobility.tracks"].Properties,Turret=Catalog["turret.standard"].Properties,Chassis=Catalog["chassis.standard"].Properties,Weapon=Catalog["weapon.cannon"].Properties}
local out={Speed=C.Drivetrain.Speed,TurnSpeed=C.Mobility.TurnSpeed,TurretSpeed=C.Turret.TraverseSpeed,TurretPitchSpeed=C.Turret.PitchSpeed,
 MinPitch=C.Turret.MinPitch,MaxPitch=C.Turret.MaxPitch,Radius=C.Chassis.Radius,Health=C.Chassis.Health,MuzzleHeight=C.Turret.MuzzleHeight,
 ArenaLimit=115,Step=1/60,SnapshotInterval=1/20,InputTimeout=0.35}
for k,v in C.Weapon do out[k]=v end
return table.freeze(out)

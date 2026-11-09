-- Explicit historical loadouts for unchanged weapon/physics regression baselines.
-- Live assemblies are tested separately in SwappedWeapons with no substitution.
return table.freeze({
 Boomer=table.freeze({Id="Boomer",DisplayName="Boomer",Chassis="chassis.standard",Drivetrain="drive.classic",Mobility="mobility.tracks",Turret="turret.standard",Weapon="weapon.cannon",Sensor="sensor.standard",Computer="computer.Bunny",Bus="bus.standard"}),
 Rattler=table.freeze({Id="Rattler",DisplayName="Rattler",Chassis="chassis.standard",Drivetrain="drive.car",Mobility="mobility.wheels",Turret="turret.standard",Weapon="weapon.gatling",Sensor="sensor.standard",Computer="computer.Octa",Bus="bus.standard"}),
})

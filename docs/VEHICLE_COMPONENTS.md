# Vehicle components: migration plan and configuration reference

## Current installed weapons

The live assemblies now install **weapon.gatling on Boomer** and **weapon.cannon on Rattler**. Bodies, turrets, computers and bus allocations stay unchanged. Mobility has subsequently been swapped: Boomer installs mobility.wheels; Rattler installs mobility.tracks. Propulsion components remain independently installed (Boomer drive.hyper_p35, Rattler drive.car). Rendering and wheel/tread animations follow installed mobility rather than the model name. Jackhammer physics and cosmetic firing personality belong to the weapon; a tracked vehicle carrying that gun also hops/rattles. The cannon carries its windup, swell, reload, turret kick and muzzle burst onto the wheeled vehicle. The pre-migration notes and original baseline verification below describe the historical loadouts, not this intentional test swap.

Weapon `Properties.Visual` selects Kind, Swelling and cosmetic Recoil. Physical `Recoil.Kind=Jackhammer` is independent of mobility and selects the shared recoil overlay. The renderer now composes body/turret art separately from mounted gun art and receives a compact weaponId descriptor; full custom component profiles remain private. Event/HUD effects follow the descriptor. TankConfig and the default heat-weapon helper are canonical cannon/Gatling compatibility defaults, not aliases for whichever tank currently carries a gun.

## Drivetrain models

| Display name | Component ID | Forward studs/sec | Reverse studs/sec |
|---|---|---:|---:|
| Scamper v0.1 | `drive.classic` | 24 | 24 |
| Stride 3.0 | `drive.car` | 30 | 18 |
| Hyper P35 | `drive.hyper_p35` | 35 | 18 |

Boomer installs Hyper P35 and Rattler retains Stride 3.0. Scamper v0.1 remains available in the catalog. It initially shares Stride's acceleration (22), braking (38), and coast drag (14). Mobility remains independent of drivetrain model. Existing component IDs are retained for compatibility.

## Inspection and proposed boundaries (before implementation)

Current tuning is split between TankConfig (Boomer propulsion, all turret rates, health/radius, cannon, simulation/network constants), TankDefinitions (Rattler propulsion/steering, Gatling heat/trajectory, both aim kicks and jackhammer recoil), ScannerConfig (hardware plus spatial-query safety), and BWChassis (computer tiers, bus allocation, CPU costs). TankSimulation chooses tracked versus inertial wheeled motion by tank name via RattlerRecoil; BWDevices and BWTankAdapter also select steering by name. BWExecution submits to the existing single drivetrain pipeline and tracks command IDs through BWDevices; finite BWRuntime observes actual authoritative movement/heading. RattlerDrive supplies car curvature and RattlerRecoil supplies inertia/ground collision integration. These algorithms will be reused.

Plan: add an immutable ComponentCatalog with typed IDs/properties/capabilities; separate VehicleAssemblies containing installed IDs; VehicleComponents resolves and validates once on construction into immutable chassis/drivetrain/mobility/turret/weapon/sensor/computer/bus configurations. Keep resolved state in a weak-key registry rather than duplicating full hardware configuration into every public snapshot. Default profiles can be cached. Simulation and BW read this resolved configuration. Keep TankConfig/TankDefinitions as compatibility facades for existing rendering and default fixtures, not independent tuning sources.

Propulsion owns speed/reverse/acceleration/braking/coast. Mobility owns tracked/wheeled steering, wheelbase/yaw limits, pivot capability and suspension tuning. Chassis owns existing health/radius/hitbox dimensions; mass/mount slots are metadata extension points, not new multipliers (the current kinematic engine has no force/mass or mount validation). Turret owns traverse/pitch/limits/pivot height. Weapon owns projectile/reload/heat/aim kicks/jackhammer tuning. Sensor owns range/cone/acquisition/cooldown/origin. Computer owns existing tier budgets/queues; bus owns allocation curve/capacity/default wiring policy. World size, fixed-step/network intervals, query safety and instruction costs remain global policies.

Wheeled and tracked steering use a common degree API. Track steering maps a physical-style control angle to differential tread intent through existing yaw/speed math, preserving pivot and full-input manual tuning. Existing tracked steering was explicitly unsupported in BW; enabling it is the only intended capability change. No player upgrade UI, new models or new physics engine.

## Verification checklist

- [x] Inspect configuration/physics/BW/server boundaries and write proposed design before code.
- [x] Catalog, assembly resolver, validation and isolated runtime configuration.
- [x] Shared simulation and component-driven drivetrain/mobility/navigation.
- [x] Component-driven turret/weapon/sensor/computer/bus defaults and server integration.
- [x] Regression and upgrade/capability/isolation/lifecycle tests.
- [x] Both Rojo builds and documentation.
- [ ] Native Studio manual/BW/visual/terrain/recoil verification (Studio unavailable).

## Implemented modules and runtime contract

- `src/shared/ComponentCatalog.luau`: the single immutable tuning catalog. Each entry has `Id`, `Type`, `DisplayName`, `Properties`, and `Capabilities`.
- `src/shared/VehicleAssemblies.luau`: Boomer/Rattler installed IDs only. Neither record contains behavior functions.
- `src/shared/VehicleComponents.luau`: validates categories/IDs, numerical safety, supported solver kinds, mount capacity and registered computer profiles; copies and recursively freezes resolved properties. Defaults are cached. Resolved profiles are bound privately to states with weak keys. `copy` is a construction helper, not used in the simulation loop.
- `TankSimulation.new(position, modelId, seed, assemblyOrResolvedProfile)` resolves/binds once. Omit the fourth argument for the existing default assembly. `VehicleComponents.get(state)` returns the existing profile without building tables. A model ID still selects art/lifecycle identity, not physics capabilities.
- `RattlerDrive` is the retained compatibility filename for the shared propulsion/steering solver. It consumes `Drivetrain` and `Mobility`, with two existing response/steering branches. `RattlerRecoil` retains the existing inertia/collision integration and only enables jackhammer kicks when the installed weapon requests them. Historical filenames are not tank-name dispatch.
- `BWTankAdapter` plans movement using component ratings/pivot capability. `BWDevices` retains its per-device pipelines and captures the resolved profile. All steerable mobility tracks finite movement along actual signed tangent displacement. No wheel spinning, vertical motion or lateral drift counts as distance.
- `BWChassis` retains its public name/API and CPU-cost registry. Registered computer components supply its tier table. Bus properties supply default allocation and the performance exponent. `BWController` applies the bus-derived operating performance once; base component ratings remain unscaled. The existing development hardware selector installs the registered computer matching its selected tier, without accepting arbitrary CPU budgets. No new upgrade UI exists.
- Server weapon dispatch uses `Weapon.Operation` and damage attribution uses `Weapon.WeaponType`; the projectile system receives that resolved weapon tuning. Turret rates/pitch bounds/mount height, cannon preparation and aim/recoil settings likewise consume the profile.
- Scanner geometry accepts a hardware cone width. BW and manual scans use installed range/cone/origin/cooldown; independent sensor cooldowns and the global bounded-query safety policy remain separate. Geometry supports total cone widths up to 180 degrees. Default width/range remain 15 degrees/150 studs.

The state registry keeps full configuration out of every snapshot. Existing snapshots gain only `maxHealth`, needed for component-backed health bars; chassis hitbox dimensions/radius/contact footprint are consumed server-side. The engine remains authoritative and clients still render actual replicated state. No new remote protocol or client upgrade authorization is added.

## Component reference and boundaries

| Category / IDs | Properties consumed now | Capabilities / boundaries |
| --- | --- | --- |
| Chassis: `chassis.standard` | `Health=100`, `Radius=5`, `Hitbox={X=8,Y=5,Z=10}`, `HitboxHeight=2.5`, `ContactLength=5.6`, `ContactWidth=5`, `MountingSlots` | Slots cover the existing single drivetrain/mobility/turret/weapon/computer/bus and eight sensors. `Mass` may be recorded as positive metadata, but is deliberately not a new force multiplier. |
| Drivetrain: `drive.classic`, `drive.car` | `Speed`, `ReverseSpeed`, `Response` (`Immediate` or `Accelerated`); accelerated response also uses `Acceleration`, `Braking`, `CoastDrag` | Classic retains 24/24 instant propulsion; car retains 30/18, acceleration22, braking38, coast14. Torque is not modeled by the existing engine. |
| Mobility: `mobility.tracks`, `mobility.wheels` | `Kind`, `Motion`, `MaxSteer`, `TurnSpeed` for tracks; `Wheelbase`, `MaxYawRate`, `SteeringResponse` for wheels; `Inertia` gravity/ground friction/safety and `Suspension` spring/damping/bob/rock settings | `Steer`, `Pivot` are explicit capabilities. Wheels use 0.55-radian lock, 5.2-stud wheelbase and 1.9-rad/sec yaw cap. Tracks retain 1.8-rad/sec full differential yaw and gain a 45-degree BW steering control range. |
| Turret: `turret.standard` | `TraverseSpeed=3.5`, `PitchSpeed=1.1`, `MinPitch=-12°`, `MaxPitch=30°`, `MuzzleHeight=3.6` | Standard ground muzzle height remains the projectile leveling reference, independent of upgraded firing turret height. |
| Weapon: `weapon.cannon`, `weapon.gatling` | `Operation`, `WeaponType`, `FireWindup`/`PreparationImpulse`, `Cooldown`, `Damage`, `Range`, `MuzzleOffset`, `ShellSpeed`, `ShellRadius`; heat/burst/recovery fields, optional trajectory, `Aim`, optional jackhammer `Recoil` | Cannon remains25 damage/.65 reload/.20 preparation/24 projectile speed. Gatling remains6 damage/.1 interval/85 speed/3-second heat limit/2-second cooldown. Seeded kick/jolt and trajectory algorithms are unchanged. |
| Sensor: `sensor.standard` | `Range=150`, `ConeWidth=15`, `Acquisition=.05`, `Cooldown=.1`, `OriginHeight=2.5`, `DistancePercent=100` | A default sensor component supplies all eight mounts unless assembly `Sensors` explicitly lists installed positions. Hardware mounts are still 0..315 in 45-degree steps. |
| Computer: `computer.Bunny`, `.Dual`, `.Quad`, `.Octa`, `.Hexadeca` | `Tier`, `threads`, `ticks`, `queue` | Existing 1/2/4/8/16 thread profiles and budgets/queue depths unchanged. Boomer installs Bunny; Rattler installs Octa. Custom catalogs cannot manufacture unregistered CPU budgets. |
| Bus: `bus.standard` | `Capacity=100`, `PerformanceExponent=2`, single/dual-bus default drive/turret/weapon/sensor reservations | The existing percentage capacity and nonlinear curve are preserved. Idle reservations are not donated. No electrical power simulation is added. |

Global policy remains global: fixed 60Hz physics/10Hz BW cycles, network cadence, world size, operation limits, CPU instruction costs, scanner query-work limits, terrain material definitions, and combat effects scheduling. A drivetrain upgrade does not silently change steering geometry, recoil, CPU throughput or weapon damage. Chassis mass does not secretly change acceleration.

## Constructing upgrades and assemblies

To add a drivetrain, add an entry in `ComponentCatalog.luau` using an existing response model. For example:

```lua
add("drive.rally", "Drivetrain", "Rally propulsion", {
    Speed=36, ReverseSpeed=20, Response="Accelerated",
    Acceleration=25, Braking=38, CoastDrag=14,
})
```

To add mobility, copy the complete properties of an existing mobility entry, change tuning such as wheelbase/steering limits, give it a unique ID, and set `Capabilities={Steer=true,Pivot=false}` for wheels or the desired tracked pivot flag. Use the supported `Kind`/`Motion` models. A genuinely different locomotion algorithm needs an explicit solver extension, not an arbitrary behavior function in a catalog entry. Do not multiply propulsion ratings by mass/traction again.

Install IDs in an assembly. Keep model identity separate when testing an alternate assembly with existing art:

```lua
local Components = require(Shared.VehicleComponents)
local Assemblies = require(Shared.VehicleAssemblies)
local Simulation = require(Shared.TankSimulation)
local assembly = Components.copy(Assemblies.Boomer)
assembly.Id = "WheeledTest"
assembly.Drivetrain = "drive.car"
assembly.Mobility = "mobility.wheels"
assembly.Computer = "computer.Octa"
assembly.Sensors = { [0]="sensor.standard", [90]="sensor.standard" }
local profile = Components.resolve(assembly)
local state = Simulation.new(Vector3.zero, "Boomer", 123, profile)
```

Omitting `Sensors` installs the assembly's default `Sensor` component on all eight mounts. An explicit map installs only those positions and can name different sensor component IDs per mount. Missing hardware fails normally. Mounting capacity is validated. Custom server-side catalogs can be passed as the second `resolve` argument for isolated configuration/testing; normal gameplay uses the registered catalog. Resolve before simulation, never per frame. Resolved values cannot be mutated or alias an editable catalog.

For server lifecycle integration, supply `tank.assembly` before `LocalBattle.resetTank`. Reset retains the configured assembly but creates a fresh state and clears active commands, recoil, damage and execution state. The existing hardware development configuration is preserved, including its selected registered computer tier. If an upgrade changes installed devices or hardware ratings, deliberately regenerate/reconcile `tank.hardware` with `BWChassis.forTank(newState)` rather than retaining stale development overrides. Runtime hot-swapping while driving is not provided.

## Tracked BW steering and compatibility

Both default vehicles accept steer_left/right/center, continuous forward/back and stop. Wheel requests position wheels; tracked requests alter differential tread intent. Tracks support high-level pivot turns; wheels use curvature and must move. A steering-disabled component returns `unsupportedDrivetrain` even on a Rattler model. Tracked idle steering is a saved target, not a free-running pivot; stop releases both treads. High-level turn commands still pivot when the installed tracks allow it.

Continuous drive replacement/FIFO rules, command IDs/status, lifecycle cleanup, CPU tick costs, independent scanners and bus reservation semantics remain unchanged from the previous runtime. Only enabling tracked BW steering and the resulting curved finite track travel are intended new capabilities. Legacy default facades remain available for visual/model code and older tests, but derive tuning from the catalog.

## Remaining assumptions and future work

- No mass/force/torque simulation exists. Mass can be metadata; adding inertia or torque formulas is a separate balance/physics task. Traction currently consists of existing terrain speed factors and mobility ground-friction behavior; no unused new traction multiplier was added.
- Rendering still uses the two existing handcrafted models and attachment layouts. Swapping components changes simulation, not mesh construction. Arbitrary new hull/turret/weapon art and upgrade visuals require compatible attachment/model definitions later.
- Full custom component profiles are not replicated. Current clients render authoritative poses and existing models; custom mount geometry or weapon-specific art/aim-preview upgrades will need a small versioned visual descriptor, rather than replicating whole catalogs every frame.
- Computer upgrades select registered tier profiles. New tiers must be registered in the catalog and reviewed against existing scheduler/UI limits (currently at most16 threads); bus capacity remains percentage-based at100. The existing developer hardware editor is an override surface, not a player upgrade entitlement system.
- Tank selection, local battle spawn slots, names and art are still the two-tank PoC. They are presentation/lifecycle policy, not capability dispatch. Historical Rattler module names remain compatibility filenames.
- Native Roblox Studio verification of steering, wheels/treads, terrain, recoil, effects and manual/mobile handoff remains required. Unit simulations and successful builds do not establish native visual/play behavior.

## Verified acceptance results

All automated groups pass: 84 new component assertions, existing steering57/CONST405, renderer140, server integration4876, physics/trajectory/recoil, BW parser/scheduler/scanner/control and damage suites. Thirteen runtime documentation programs complete on both default tank simulations. Boomer/Rattler physical demonstration timings and shot counts remain unchanged (5 cannon shots and21 Gatling shots in the existing demonstrations). Both `.rbxl` and `.rbxlx` Rojo formats build, and whitespace checks pass. Studio runtime/visual testing remains unchecked above.

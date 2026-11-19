# BW core self-introspection API — Stage 1

Status: **Stage 1 implemented and automatically verified**. Native Studio acceptance remains pending. Stage2 G1–G5 and all15 personalities are implemented and automatically verified. Stage3 is unimplemented. Scope: own tank only; no map, opponents, targets or privileged geometry. Existing syntax and value types suffice. The existing const/alias analyzer receives static shapes for these immutable results; scalar fields and array/map entries can be passed to ordinary numeric functions without being mistaken for unknown object aliases. Existing mutable/const and shared-reference restrictions remain unchanged.

## Runtime, values and authority

Production BWExecution evaluates calls on the authoritative bound tank. Every read occurs synchronously **after its CPU charge succeeds**, selecting fresh entity/state/hardware values at that invocation. Nothing is cached per tick. A single snapshot is constructed without yields, so its values share one read instant; two reads can differ even within the same tick if trusted server state changed. Returned nested dictionaries/zero-based arrays are deep immutable BWValue values, never Luau Instances, Vector3, device handles or references into live state. Missing/not-computable information is BW null, not misleading zero/infinity. No API takes a tank/user/world argument.

All results use existing `status: "success"|"fail"`, `reason: null|string` conventions. Normal reads succeed even if a subsystem is absent/disabled; fields describe that condition. Invalid argument counts/named arguments are parse errors. Existing runtime lifecycle stops BW when its tank dies/replaces; standalone read-only adapter tests can inspect destroyed state without granting gameplay control.

`get_facing_direction()` remains unchanged: chassis `world_direction` in degrees, cost 0.1 tick. `get_clock()` remains unchanged: server simulation seconds where supplied, otherwise runtime elapsed seconds, cost 0. New `get_tank_direction()` is the discoverable alias, not a different heading model.

## Signatures and per-call cost

All calls have **zero arguments**, no named arguments and no best_effort parameter.

| Signature | Result payload in addition to status/reason | Cost |
|---|---|---|
| `get_weapon_speed()` | `kind: "projectile"`, `speed: number|null`, `units: "studs/second"` | 1 tick |
| `get_current_coordinates()` | `x, y, z: number` | 1 tick |
| `get_weapon_type()` | `weapon_type: string` (installed canonical ID, e.g. weapon.cannon) | 1 tick |
| `is_weapon_ready()` | `ready: boolean|null`, `state: string`, `remaining_seconds: number|null` | 1 CPU cycle |
| `get_turret_direction()` | `world_direction: number|null`, `mount_yaw, mount_pitch: number`, `world_pitch: number`, `max_rotation_speed, effective_rotation_speed, min_pitch, max_pitch: number` | 1 tick |
| `get_tank_direction()` | `world_direction: number` | 0.1 tick (same as existing alias) |
| `get_drivetrain_type()` | `drivetrain_type: "Tracked"|"Wheeled"`, `drivetrain_id, mobility_id: string` | 1 tick |
| `get_bus_configuration()` | `tier: string`, `bus_count: number`, `buses: array<bus>`, `devices: dictionary<device>` | 1 tick |
| `get_tank_state()` | Full nested schema below | 2 CPU cycles |

One cycle is a 10 Hz scheduling/grant interval; one tier-relative cycle costs its per-thread ticks: Bunny10, Dual15, Quad20, Octa30, Hexadeca40. Thus snapshot costs20/30/40/60/80 ticks. Credit accumulates/reserves through the existing scheduler, bounded by 1,024 ticks per instruction. Calls do not add a forced sleep or skip simulation ticks. Assignment/expression overhead is additional: `s = get_tank_state()` costs 2×tier ticks+0.2 and may need a third grant from zero credit. Each reached call is charged once, including inside print/user functions/conditions; short-circuited calls cost zero. Ordinary assignment/read/access/comparison/etc. charges remain (write0.2, read/access0.1 ticks). Snapshot fields incur **no second introspection fee**, only normal expression access. Existing costs do not change.

## Existing CPU accounting inventory

The 60 Hz simulation and 10 Hz CPU grants are separate clocks. The legacy `cyclesSpent` member is a **tick-charge total**, despite its historical name. Charge and reservation use the same Hardware.cost lookup; reservations include worst-case expression cost and only reached operations charge actual ticks.

| Existing category | Tick cost |
|---|---:|
| Variable read / field or array access | 0.1 each |
| Variable write / mutable parameter binding | 0.2 each |
| Arithmetic / comparison | 0.2 each |
| Logical operation | 0.1 |
| Branch / while test | 1 |
| Switch | 2 |
| Movement, steering, stop, chassis/turret turn, Scanner submission | 1 each |
| Fire submission | 2 |
| Synchronization / queue management/status | 0.2 / 1 |
| get_facing_direction | 0.1 |
| get_clock / print / user-function call and return | 0 |

Constant parameters retain their existing read-cost waiver. Side-effect-free debug-only printed expressions retain their existing fee waiver, but **an introspection call is never debug-only**; its own fee and argument/expression work remain charged. Scanner acquisition/cooldown is physical time, not a repeated CPU charge. The legacy serial interpreter's informational CycleCosts/ScannerCost hooks remain for historical programs and are not production budgeting policy; introspection through that facade uses BWExecution.

| CPU tier | Buses/threads | Ticks/grant/thread | Readiness fee | Snapshot fee |
|---|---:|---:|---:|---:|
| Bunny | 1 | 10 | 10 | 20 |
| Dual | 2 | 15 | 15 | 30 |
| Quad | 4 | 20 | 20 | 40 |
| Octa | 8 | 30 | 30 | 60 |
| Hexadeca | 16 | 40 | 40 | 80 |

## Coordinates and directions

Coordinates are the authoritative chassis origin/base position, not the muzzle or hitbox center. World coordinates are Roblox studs: +Y up, heading0 points -Z, heading90 points +X. World headings increase clockwise and normalize to [0,360). Speeds use studs/second. Public angular rates and angles use degrees or degrees/second, never radians.

Chassis heading follows state yaw through the existing adapter. Turret world heading/pitch is the actual recoil-adjusted barrel direction composed with chassis pitch/roll. An exactly vertical barrel has null world heading. `mount_yaw` is the recoil-adjusted relative mount heading, normalized [0,360); `mount_pitch` is actual barrel pitch relative to the tilted mount. Mechanical travel stops are mount-relative. No aim or orientation is modified by a read.

## Snapshot schema

Top-level payload: `coordinates`, `chassis`, `turret`, `motion`, `weapon`, `health`, `equipment`, `bus`, `scanners`, `scanner_count`, `simulation`.

- `coordinates`: `{x,y,z}` studs.
- `chassis`: `{world_direction, turn_rate, max_turn_rate, effective_max_turn_rate}`; signed current clockwise turn rate, physical rated maximum and nominal bus-limited maximum in degrees/second. Wheeled effective bound also respects forward speed/wheelbase/steering geometry and MaxYawRate; traction, air and surface conditions can reduce actual ability.
- `turret`: direction fields above plus `{max_rotation_speed,effective_rotation_speed,min_pitch,max_pitch}`. Both axes share traverse speed × turret bus performance; effective stops already intersect weapon/mount limits.
- `motion`: `{speed,forward_speed,vertical_speed,max_speed,max_reverse_speed,effective_max_speed,effective_reverse_speed,terrain_speed_scale,ground_max_speed,drivetrain_type,drivetrain_id,mobility_id,steering_mode,steering_angle,max_steering_angle,wheelbase,wheel_count,turning_radius,min_turning_radius,can_pivot,can_reverse,immobilized,airborne}`. `speed` is current horizontal velocity magnitude; `forward_speed` signed yaw-plane chassis-forward projection (the engine speed convention); vertical speed is separate. Ratings are physical drivetrain ratings; effective ratings multiply bus performance only, not a promise of traction/surface/slope speed. Recoil/pushing can exceed ratings. Steering mode is differential for tracks, front_wheel for wheels, none if capability absent. Angles degrees; wheel steering angle is positive left, as with existing steeringDegrees. Steering angle/max_steering_angle are null for tracks or absent steering capability: differential tread intent is not a physical wheel angle. Wheelbase/radii studs. Wheel count is null (not authoritative). Current nominal geometric wheel radius respects actual steer angle, current forward speed and yaw cap; straight/stationary/undefined radius is null. It is not a measured trajectory radius under slip. Tracked moving radius is null unless a stationary pivot is directly identifiable. Pivot-capable tracks have min_turning_radius=0; non-pivot tracked geometry cannot supply a finite minimum and returns null.
- `weapon`: `{id,kind,projectile_speed,projectile_model,range,readiness,ammo}`. id is canonical installed ID; kind is existing WeaponType (Cannon/Gatling). range studs; speed studs/second independent of bus (allocation changes timing, not shell speed). readiness has the individual read's payload. ammo `{mode:"unlimited",remaining:null,capacity:null}` for both current weapons; no fabricated empty/reload states. `projectile_model:"projectile"` for all supported engine weapons. Reserved future hitscan representation is model/kind `"hitscan"` and speed null, never math.huge/0; **no hitscan hardware/behavior is introduced or claimed supported now**.
- `health`: `{current,max,damage}` HP and max-current HP.
- `equipment`: immutable dictionary of the resolver's actual installed IDs (`Weapon`, `Mobility`, `Drivetrain`, `Turret`, `Computer`, `Bus`, `Chassis`, `Sensor`, mounted sensorN keys as installed). It describes equipment, not enabled bus-device presence.
- `bus`: individual bus-configuration payload. Devices are keyed by actual names drivetrain/turret/weapon/sensor0..315, each `{bus,allocation,performance}` (bus 1-based, allocation percent, performance0..1 through existing curve). Buses are a **zero-based BW array** of `{index,allocated,available}`; index is the actual 1-based bus ID. No new categories. Absent devices remain absent, not fabricated. Performance is `1 - (1 - allocation/100)^PerformanceExponent`; the exponent comes from the installed bus.
- `scanners`: zero-based array in ascending physical mounting angle. Each `{device,id,mounting_degrees,reference,world_direction,cone_degrees,catalog_range,max_range,distance_percent,configured_range,effective_range,performance,enabled,acquisition_seconds,cooldown_seconds,origin_height}`. reference is `"chassis"`; world_direction=(chassis heading+mounting)%360. Catalog range is installed sensor rating; max_range is the current hardware record's override or rating. configured_range=max_range×distance_percent/100. Allocation affects enablement/acquisition; it does **not shrink range**. effective_range is configured range when enabled, otherwise0. Acquisition scales by performance; disabled acquisition is null. Cooldown is the configured per-lens cooldown. Origin height is above chassis origin in studs. No installed scanners returns an empty array with scanner_count=0; absent bus entries disable a mounted lens.
- `simulation`: `{time,tick,step_seconds}`. Server time/tick refer to the current completed fixed-step boundary read before movement/combat. Same-frame consecutive queries can share timestamp/tick but are freshly built. Standalone execution without a server step clock exposes runtime time and null tick/step_seconds, rather than pretending a server tick exists.

## Weapon readiness

The production reader receives the own tank's current server heat/windup/trigger state, not only replicated snapshot telemetry. State values: ready, destroyed, unavailable (no weapon bus device), disabled (zero allocation), release_required, preparing, overheated, cooldown, unknown. `ready` is true only for ready; false for known blockers; null for unknown due to missing private heat timing in a standalone harness. remaining_seconds reports active preparation/cooldown when known. The check is at the invocation instant, not a guarantee that a future trigger will succeed after simulation, obstruction, damage or occupancy changes. No finite ammunition/magazine mechanic exists, so out_of_ammunition/reloading is not invented.

## Scanner coverage and drivetrain limits

Scanner(angle) selects installed chassis-mounted lenses at fixed45° positions; Scanner(position=index) selects one of eight mount slots. It does not continuously rotate the scanner, and turret yaw does not rotate its reference. The current 15° cones at45° spacing leave gaps. Rotating/driving the chassis and rescanning can cover gaps, subject to obstacles, acquisition, cooldown and supported steering. For hypothetical freely selectable36° cones ceil(360/36)=10 is only an ideal tiling calculation; it does not make Scanner(36) legal or imply actual complete coverage. No new privileged spatial algorithms are added.

Wheeled tanks use wheelbase/steer/yaw constraints and cannot pivot; tracked pivoting depends on the installed capabilities. Hardware configuration while BW runs remains rejected; stop/configure/restart is the supported reconfiguration workflow. Query freshness does not authorize new equipment mutation from BW.

## Real BW examples

```text
state = get_tank_state()
print(state.coordinates.y)
print(state.weapon.id)
if state.scanner_count > 0:
    print(state.scanners[0].cone_degrees)
ready = is_weapon_ready()
if ready.ready == true:
    fire()
heading = get_tank_direction()
print(heading.world_direction)
```

Use scanner_count (and bus.bus_count) with an existing while loop and zero-based indexing; an empty BW array cannot be indexed. No privileged map/enemy data is returned. Backward compatibility keeps every existing signature/cost and ordinary movement/fire/scan semantics. The nine new builtin names become reserved identifiers; external user functions/variables with those formerly unused names must be renamed. Programs containing new introspection may enter via the legacy Runtime facade but execute on the production scheduler rather than duplicating its value APIs.

## Gaps / deliberate omissions

No enemy state/map lookup, pathfinding/cover/intercept helper, hitscan implementation, finite ammo, authoritative wheel count, unsupported tracked turning geometry, or guaranteed terrain-limited speed/turn capability is fabricated. Stage2 programs and Stage3 living arena are not part of Stage1.


## Verification and native acceptance

Automated evidence and exact commands are tracked in [BW_ROADMAP_CHECKLIST.md](BW_ROADMAP_CHECKLIST.md). The production server getter is exercised through authorized BWRun/private output in Playground; the pure module suite covers values, clocks, mechanical/hardware distinctions, cooldown/windup/heat/damage, real BW motion and scheduler behavior on every tier. Static shape conformance ensures declared scalar/container paths match actual emitted snapshot values, without relaxing existing const/mutable safety.

Native Roblox acceptance still required:

1. In two-player Playground, enter separate tanks and run the real example above in each. Verify coordinates are each player's own chassis base, equipment matches their tank, and only the occupant gets that program's output. An unauthorized BWRun for the other tank must fail through the existing lease check.
2. Read before/after driving, steering, turret yaw/elevation and going up/down slopes. Check chassis/world/mount headings, coordinates, signed motion, native fixed-step time and tick; a retained prior snapshot must stay unchanged.
3. Observe cannon preparing/cooldown and Gatling shot pacing/overheat while firing; compare with HUD and actual timing. Damage the occupied tank and read current/max HP and damage. No ammo count or hitscan behavior should be invented.
4. Stop a program, change supported bus allocation/computer configuration, restart and compare physical/effective ratings and CPU fees. Changing hardware while running must still be rejected. Public Playground hardware restrictions stay in place; use the existing Classic hardware workflow where necessary.
5. Check sensor metadata with installed/removal/override fixtures: chassis-relative fixed mounting, cone gaps, configured range/distancePercent, disabled devices and acquisition delay. Terrain occlusion and wheeled steering still constrain any scan sweep; the API does not promise full coverage or map knowledge.
6. Repeat existing Classic programs, custom worlds, mode transitions, deaths, disconnects and owned/public tank lifecycles. Gameplay, chat, editor and 3D aiming remain outside this Stage 1 change.

No native Studio execution is claimed by automated tests/builds. Stage 2 personalities and Stage 3 living Playground remain TODO and must not be started here.

## Stage 2 approved additions (2026-11-19)

G1: `get_turret_direction()` and `get_tank_state().turret` additionally return immutable world-space `pivot`, `muzzle_position`, and unit `direction` xyz records, from the existing authoritative shot/mount geometry. The existing projectile launch sweeps from pivot to muzzle tip for obstruction safety, then enters free flight at `pivot + direction * MuzzleOffset`. The metadata describes that unobstructed muzzle position; it performs no scene query and cannot promise the barrel is clear. Existing fees and field-read costs are unchanged.

G2: `aim_at(x, y, z, best_effort=true)` accepts three finite positional world coordinates (studs, absolute value <=100000) and optional boolean keyword. Submission costs **1 tick**, plus ordinary expressions. Returns standard acceptance/failure and commandId, using the existing turret FIFO. `command_status(id)` reports completed with `completionReason="mountLimited"` when the physical stop prevents reaching the point; normal alignment has null reason. Disabled/missing devices and queue limits return existing errors. Timeout/stuck/cancellation/generation/death handling is unchanged. Both axes use the ordinary mount solver and identical existing bus-limited angular speed. It samples no surroundings, tracks no enemy, predicts nothing, and never redirects a shot. The requested point remains fixed; the mount solver recomputes against the current chassis pose. Clients gain no new authority.

G3: `is_weapon_ready()` and snapshot `.weapon.readiness` additionally expose `operation`, `heat`, `max_heat`, `burst_seconds`, `max_burst_seconds`, `overheat_seconds`, `fire_interval_seconds`, `effective_fire_interval_seconds`, `preparation_seconds`, `effective_preparation_seconds`. Timing units are seconds; current heat units are active-fire seconds. `overheat_seconds` is the remaining native overheat lockout. Inapplicable/unavailable fields are null; zero weapon performance yields null effective intervals. Effective interval/preparation divides the real component duration by bus performance. No ammunition/reload mechanics are added. Existing readiness one-cycle/snapshot two-cycle fees remain unchanged.

```text
request = aim_at(20, 8, -40)
wait_for_clock(get_clock().time + 2)
result = command_status(request.commandId)
pose = get_turret_direction()
weapon = is_weapon_ready()
print(result.completionReason)
print(pose.direction.y)
print(weapon.effective_preparation_seconds)
```

## G4/G5 continuation

The source-statement and line ceilings are removed. Technical guards are256KiB upload,65,536 compiled instructions,1-second compilation deadline and250,000 analysis updates. Existing50-frame recursive limit, CPU grants/costs, memory/container/variable bounds, nesting,512 source-operations/thread/cycle, queues and180-second runtime remain. These are technical resources, not source-length gameplay fees.

Existing own-state scanner entries add `ground_observations` and `ground_operational` booleans. Existing `Scanner` successes add immutable `.terrain`; no new command or player-facing fee. See [terrain/elevation contract](SCANNER_TERRAIN.md). Unsupported hardware/occlusion/range/missing normals report unsupported/null/unknown, never invented slope, depth, water or safe-driving advice.

Stage2.5 own motion additions (same snapshot cost): `terrain_speed_scale` is the last authoritative movement contact multiplier (material/surface and the single proving-ground tracked.90 factor); null before a contact update. `ground_max_speed` is physical drivetrain forward rating × current bus performance × that multiplier, studs/second, or null before contact. It is a ground target limit, not guaranteed actual speed or an airborne limit. Existing `max_speed` and `effective_max_speed` remain physical and bus-only ratings. See [terrain formulas](PLAYGROUND_PROVING_GROUND.md).

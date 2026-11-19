# BW Scanner terrain observations (G5)

`Scanner(angle)` / `Scanner(position=index)` are unchanged. Their successful immutable result now includes `.terrain`, alongside the existing count/detections/nearest-object fields. No `scan_ground` command exists. Submission remains **one tick**, plus ordinary argument/field/expression costs and existing sensor acquisition/queue/cooldown time. Terrain is collected in the same authoritative operation/timestamp; it adds no player CPU fee or separate scan.

## Equipment, geometry and query budget

`sensor.standard` explicitly supports `GroundObservations=true`. Other installed sensor definitions without that flag return unsupported terrain observations. Own-state scanner metadata exposes `ground_observations` (equipped capability) and `ground_operational` (capability with nonzero allocation/range). Disabled/absent devices still return the existing Scanner failure before acquisition. Terrain never bypasses bus performance, mounting, range, field of view, cooldown, server rate limits or occupancy authorization.

Queries use the existing scanner origin (chassis position + installed OriginHeight) and chassis-relative azimuth. 0 is forward,90 right,180 rear,270 left, clockwise from chassis heading. World axes: +Y up,0 world heading faces -Z,90 faces +X. The existing cone has vertical planes limiting azimuth; G5 does not invent an independent panoramic or downward camera.

At forward distances **2,4,6,8,12,18,26,40 studs**, sample the center and two lateral contact-footprint edges. Projected span uses the existing custom-physics ContactWidth/ContactLength and scanner direction, rather than the cosmetic mesh bounds. Lanes outside the cone or range are omitted, not synthesized. Close side lanes usually cannot be seen with the default15-degree lens. Consequently a center sample never proves full-width support.

Each candidate uses a vertical ray up to12 studs above sensor height and40 below, clipped to the actual range sphere, followed by a line-of-sight ray from the actual scanner origin. Accepted hits must lie inside the actual three-dimensional range and azimuth cone. Hidden upper/lower surfaces, objects behind occluders, and other tanks' concealed ground yield unknowns. An additional visibility probe can test whether a previously observed supporting plane is absent. Candidate probes alone do not reveal hidden elevations. Ground candidates and occlusion use authoritative query geometry, including the real floor, Playground parts, fitted model proxies/native face meshes and native Terrain when present. Dead/destroyed and nonqueryable geometry remains excluded. World-object non-solid flags distinguish visible non-supporting surfaces without changing collision/destruction behavior.

At most **64 terrain raycasts** and24 sample records, within the existing **512-ray total scan budget**, are permitted. Remaining object-query budget limits terrain; a partial result is explicit. Existing object detections are collected first and retain their ordering and query priority. This is a bounded near-field sampling stencil, not exhaustive coverage to the full scanner range or a map. Small gaps between stations may be missed.

## Result contract

All containers use existing immutable BW dictionaries/zero-based arrays. Unknown numbers/booleans/points are `null`, not0 or invented measurements.

| `.terrain` field | Meaning |
|---|---|
| supported / operational | Equipped ground capability; operational also needs positive effective range. A returned scan already passed ordinary bus/device checks. |
| status | `unsupported`, `unknown`, `observed`, or `partial_budget`. Missing query-provider geometry in a harness is unknown. |
| reference_elevation | Current authoritative chassis-base world Y, in studs. It may be airborne; this is not a claim of support. |
| footprint_width | Projected contact-footprint span perpendicular to the scan heading, studs. |
| count / samples | Number of actual samples; zero-based immutable array. |
| max_distance | Furthest attempted forward station, studs; not a promise of observation or continuity. |
| max_rise / max_drop | Technical vertical search extents above/below sensor origin (12/40 studs). |
| continuity | `sampled`, `discontinuity`, or `unknown`. `sampled` never guarantees continuous ground between rays. |
| edge_near / edge_far | Forward-distance bracket from last observed support to observable absence/drop; nearest bracket across lanes. Null unless observed. |
| distance_to_edge | Alias of **edge_near**, a quantized lower bound, NOT a precise edge point. Programs should retain both bracket endpoints. |
| drop_depth | Visible downward elevation difference between adjacent samples at an observed discontinuity, studs. Null if hidden/unmeasurable. Not an unseen ravine-depth lookup. |

Each sample contains:

| Field | Meaning |
|---|---|
| lane / lateral_offset | Lane0 left,1 center,2 right relative to the scanner direction; signed sideways offset in studs. |
| horizontal_distance | Actual XZ distance from scanner origin to sample column, studs. |
| forward_distance | Distance along horizontal scanner heading, studs. Adjacent samples in one lane differ along this axis. |
| confidence | `observed` or `unknown`. Observed reference-plane absence can have no visible surface point. |
| point / elevation | Accepted visible world xyz / world Y, studs; null if occluded/unresolved. |
| relative_elevation_change | Visible elevation minus current chassis-base Y, studs; positive above, negative below. |
| elevation_rate | **Local signed rise per horizontal forward stud**, derived from the actual hit normal and scan heading. Dimensionless studs/stud; positive uphill, negative downhill. Null without a reliable upward normal. |
| slope_angle | `atan(elevation_rate)` in **degrees**, positive uphill, negative downhill. No horsepower/traction or traversability judgment. |
| interval_elevation_rate | Difference quotient between adjacent observed samples only when consistent with one local plane. Null across steps, slope changes, occlusion and gaps. |
| transition | `first`, `sampled`, `discontinuity`, `slope_change`, `missing_reference_support`, `unknown_interval`, or `unknown`. Local slopes are never replaced with an average across a discontinuity. |
| ground_detected | True for a visible supporting surface, false for visible water/non-supporting geometry, null when unresolved. False does not assert that there is no hidden ground underneath. |
| reference_support | Same as visible ground detection, or false when the previously observed support plane is visibly absent at this station. |
| drop_depth | Measured visible downward step from the previous sample when applicable; otherwise null. |
| surface_type | Native hit material name (e.g. Grass/WoodPlanks), recognized modeled `ScannerSurface` (Pavement/Dirt/Grass/Snow/Ice/Mud), explicit queryable Water, or `unknown`. No inference from color/name. |
| wetness | Visible modeled surface wetness0..1, or null without an explicit measurement. |
| material_depth | Measured layer thickness in studs0..5, or null. Not ground elevation or hidden mud/snow depth. |
| consistency | Measured firmness0..1, or null. Not a traversability judgment. |

Queryable native water is detectable with IgnoreWater=false. The current Playground river and some Classic water patches are cosmetic, nonqueryable Glass parts: they cannot be truthfully classified as water by this scanner. Their water classification remains unknown; observed ravine geometry/edges remain available. Do not fabricate river depth or change combat/collision queries to make cosmetic water detectable.

## Player BW example

```text
scan = Scanner(0)
if scan.status == "success" and scan.terrain.supported:
    print(scan.terrain.continuity)
    print(scan.terrain.edge_near)
    print(scan.terrain.edge_far)
    index = 0
    while index < scan.terrain.count:
        sample = scan.terrain.samples[index]
        print(sample.elevation)
        print(sample.elevation_rate)
        print(sample.slope_angle)
        index = index + 1
```

An algorithm may decide to stop/turn using these observations, but scanning itself never changes throttle, steering, turret or physics. Hunter maps observations in its own BW arrays; Trailblazer compares support observations with actual progress. Duelist intentionally ignores terrain. Future player algorithms may compare these measurements to truthful vehicle capabilities; G5 adds no horsepower/climbing restriction or privileged navigation command.

## Verification and native acceptance

Group55 exercises the real DirectionalScanner/terrain collector using analytic ray-plane fixtures: flat/uphill/downhill terrain, abrupt and small steps, gaps/cliffs/hidden vs measurable drops, elevated/narrow bridges, water, footprint/cone/range limits, unsupported/missing hardware, disabled bus, invalid arguments, immutable values, existing result compatibility, scalar consumption in BW functions and shared query budgets. Explicit BW can react to an edge. Real Playground custom physics still allows bridge falls. Existing scanner/server/combat tests cover the unchanged acquisition and authority paths.

Native Studio remains required: verify raycast normals/occlusion on rotated/scaled imported MeshParts/compound colliders; bridge top versus ground below; default narrow-cone side-lane unknowns; native Terrain water versus cosmetic river unknowns; two-player scanner privacy, rates and frame cost. Compare world elevations and signed slope samples against ramps in both directions. Ensure normal keyboard/touch/gamepad controls and deliberate cliff falls remain unchanged.

Stage2.5: material scalars require an accepted visible hit, finite in-range attribute (`TerrainWetness`, `TerrainDepth`, `TerrainConsistency`) and matching boolean `*Observable=true`. Proving-ground wetness is exposed; depth/firmness remain unknown because buried properties are not measured. Labels are for human comparison only. Queryable terrain occludes object rays without becoming obstacle detections. See [layout, tuning and native tests](PLAYGROUND_PROVING_GROUND.md).

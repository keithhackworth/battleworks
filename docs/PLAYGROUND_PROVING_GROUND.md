# Stage 2.5: Playground proving ground

The default Playground is an anchored, deterministic 800 × 640 stud battlefield. It retains the six public Bunny tanks, existing bridge, ravine, river hazards, safe entry/exit rules and continuous replenishment. Stage 3 population management, onboarding, redemption and garage persistence are not implemented.

Only the default Playground selects this layout. Classic, startup-selected authored worlds, asset imports, JSON schemas and World Builder saves are preserved. An existing server must restart to select the expanded default layout.

## Layout and modification points

`src/shared/PlaygroundProvingLayout.luau` extends the existing `PlaygroundTerrain` description. Edit its coordinates/profiles to tune the proving ground; the existing native builder and custom contact solver consume the same wall/trunk dimensions.

- **Open field:** x50..350, z−135..145; 300 × 280 studs of flat grass, free of central obstacles. Pavement along the west access route, dirt along the south boundary. Perimeter targets include a roughly 290-stud clear firing route. There is space for later 15/50/100-tank tests; no autonomous population is added here.
- **Barracks:** x90..250, z195..295, height12. Four rooms branch from a connected 32-stud-wide hall. Opposing exterior doors have 24-stud clearance; room doors have18. Windows have actual openings, sill height2 and top9. The southern divider has an internal window; northern rooms are dead ends. There is no roof to obstruct the overhead camera. Walls and headers are solid for characters, tanks, scanners and shots. Barracks wall segments share one scanner object identity to avoid redundant detection work; this grants no visibility through walls.
- **Forest:** western bank, approximately x−333..−225, z152..269. Irregular anchored box trunks use the existing native/custom tree paths. Decorative foliage neither collides nor participates in queries. A continuous lane near x−270 and tighter side routes support steering practice.
- **Material comparison lanes:** twelve equal 22 × 160 stud strips, centered at z−220 and x−370 +28×index (zero-based). The west plateau is nine studs high; normal existing access slopes connect it. Six-stud grass separators and labels identify the conditions. These are thin queryable visual skins over the existing land, not collision bridges or new terrain support.

Access uses the existing open banks, ramps and bridge. None of these additions carry navigation hints, a map, or routes to BW programs.

## Terrain parameters and calculation

`src/shared/TerrainMaterials.luau` centralizes all tuning. Units: speed factors are dimensionless, depth is studs (0..5), wetness/consistency are0..1. Greater consistency represents firmer material. Mud is saturated dirt and always has wetness1; there is no fabricated dry mud. Colors/materials are presentation only.

| Surface | Dry speed | Fully wet speed | Static/kinetic grip coefficients | Wet grip factor | Depth drag | Tracked depth benefit |
|---|---:|---:|---:|---:|---:|---:|
| Pavement |1|.92|16 /12|.72|0|0|
| Dirt |.94|.74|10 /7|.70|.25|.10|
| Grass |1|.85|12 /8|.65|.10|.04|
| Snow |.80|.62|5 /3|.80|.50|.25|
| Ice |.90|.78|.04 /.025|.65|0|0|
| Mud |.65|.45|4 /2.5|.80|.70|.35|

For definition `d`, wetness `w`, depth `h`, firmness `c`:

```
wetSpeed = lerp(d.speed, d.wetSpeed, w)
drag = 1 + d.depthDrag * h * (1.5 - c)
wheeledFactor = max(.12, wetSpeed / drag)
trackedFactor = max(.12, wetSpeed / (1 + (drag - 1) * (1 - d.trackBenefit)))
gripFactor = lerp(1, d.wetGrip, w)
# Snow/Mud additionally multiply gripFactor by (.7 + .3*c)
coastResistance = 1 + h*d.depthDrag
```

Tracked grip coefficients additionally multiply by `1 + d.trackBenefit*h`. `SurfacePhysics` blends the appropriate speed and grip values at the existing four chassis contact corners. The approved **tracked base speed multiplier .90 is applied exactly once, after contact blending**, in opt-in proving-ground simulation. It does not mutate hardware ratings or apply once per wheel/contact. Grass baseline remains1 for wheels; otherwise equivalent tracks target.90. This opt-in keeps existing Classic/authored-world handling unchanged.

The resulting material factor multiplies the existing surface and bus-limited drive target. Bus power, acceleration, steering, braking, recoil, traction/slip and collision remain in the existing drive solver. Positive material speed/grip allows powered progress even in deep mud; zero bus power still cannot drive. Slope reduces contact grip using the existing pitch/roll normal projection (cosines, minimum.1). Existing slope following and cliff falls remain unchanged; no horsepower climbing restriction, automatic route choice or artificial cliff barrier is added. Ice produces much longer braking/sliding rather than an instant velocity clamp. This is an initial gameplay tuning model, not deformable snow, fluid mud, or a full suspension model.

The lanes compare dry/wet pavement, dirt, grass, snow and ice, plus shallow/deep saturated mud. Snow variants also compare depth and firmness; profile settings are intentionally configurable. Physical elevation still comes from the existing region geometry, independently of material depth.

## Scanner and own-state data

The existing `Scanner` operation returns terrain observations in the same immutable result, at the same CPU cost and within the same range/cone/bus/LOS/query limits. See [the exact scanner contract](SCANNER_TERRAIN.md).

Samples can report `surface_type`, `wetness`, `material_depth`, `consistency`, ground presence, elevation, relative elevation, signed rise per horizontal stud, slope degrees and observed edge brackets. A scalar material property requires a visible surface hit and an explicit observable measurement marker. Wetness is modeled as visible on these surfaces. **Buried snow/mud depth and firmness are not measured by the standard scanner:** those fields remain null on the comparison strips despite the human-readable labels. No hidden region or map lookup supplies missing observations. Actual queryable water remains detectable; the existing cosmetic river is nonqueryable and is not fabricated as water data.

Ground can occlude detection rays but is not reported as a fake wall/object. Openings remain genuine line of sight. Own `get_tank_state().motion` adds `terrain_speed_scale` and `ground_max_speed`; nominal physical/bus-only ratings retain their established meaning.

## Practice targets

Ten anchored targets cover field perimeter/long-range shooting, room windows, the hall end, partial tree occlusion and a terrain transition. They reuse the existing server-authoritative hit/damage registry, health labels, destroyed appearance and single `PracticeTargets` update timer. After destruction they return to full health and their original pose after **five seconds**. If a live tank overlaps the original anchor, existing short occupancy retries delay restoration to avoid spawning collision inside it. Hits on an already dead target cannot create another timer. Targets produce no accumulating debris and consume neither player tank ownership nor autonomous population slots.

## Automated and native verification

`ProvingGround.spec.luau` exercises production layout/building/contact/scanner/weapon/target modules with numeric transform and analytic ray fixtures: door traversal, wall/window LOS, trunk collision, partial forest visibility, field routes, long-range cannon damage, target restoration and occupancy retry. 15/50/100-position grid/contact checks demonstrate layout capacity only, **not server performance**. `TerrainMaterials.spec.luau` drives actual wheeled/tracked simulation through wet/dry/depth/firmness conditions, bus limits, turning, braking, ramps and legacy environments. Existing full movement/aiming/BW/multiplayer/editor suites remain required; commands and results are in the [roadmap](BW_ROADMAP_CHECKLIST.md).

Native Roblox Studio has not been run. Acceptance procedure:

1. Restart the default Playground in Server & Clients with two players. Verify six public tanks, safe foot spawns, entry/exit/switching, chat and Main Menu return. Check Classic and a saved custom world separately.
2. Drive both drivetrain types across the bridge and forest lanes, then each opposing barracks entrance and room doorway. Verify no trunk/door collision mismatch or unavoidable spawn trap. Check the open roof/camera and strip-label readability.
3. Park one tank behind a room window. Scan/aim from outside: visible through the opening, blocked when moved behind the neighboring wall. Repeat at the hall end, through the internal window and behind a tree. Verify cannon and Gatling shots respect those openings and walls.
4. Use identical hardware/buses to compare equal-length lanes. Confirm tracks are.90 on dry grass, wet surfaces differ, deep/soft mud and snow slow powered tanks without locking them, ice slides/brakes longer, and material seams do not create false drops. Test ramps, cliff/river deaths, safe respawn and public tank replenishment.
5. Run normal BW scans over visible strips/edges/bridge. Confirm type/wetness/elevation/slope; unmeasured depth/firmness and cosmetic water stay unknown, and occluded geometry stays hidden. Check native thin-skin hit fidelity and query cost.
6. Destroy each target, including through windows and at long range. Confirm destroyed state, five-second full-health original-position restoration, no duplicate timers/debris and safe delay when a tank occupies the anchor.
7. Later benchmark actual server frame time/query counts/network load at15/50/100 tanks using explicit test tooling. This stage does not create that population or claim a performance benchmark.

# Stage 2.5: Playground proving ground

The default Playground is **462 × 369 studs**, about one third of the area of the 800 × 640 reference layout. It includes the barracks, forest, terrain lanes, practice targets, and the Proving Grounds course. The course bridge uses single-lane switchback sections with two grades. The dimensions below describe the reference layout, except where noted.

Only the default Playground selects this layout. Classic, startup-selected authored worlds, asset imports, JSON schemas and World Builder saves are preserved. An existing server must restart to load the smaller default layout.

## Layout and modification points

`src/shared/PlaygroundProvingLayout.luau` extends the existing `PlaygroundTerrain` description. Edit its coordinates/profiles to tune the proving ground; the existing native builder and custom contact solver consume the same wall/trunk dimensions.

- **Open field:** x50..350, z−135..145; 300 × 280 studs of flat grass, free of central obstacles. Pavement along the west access route, dirt along the south boundary. Perimeter targets include a roughly 290-stud clear firing route. There is space for later 15/50/100-tank tests; no autonomous population is added here.
- **Barracks:** x90..250, z195..295, height12. Four rooms branch from a connected 46-stud-wide hall. Exterior entrances are 42 studs wide and room doorways are 36 studs wide (about 24 and 21 studs in the default Playground). Practice targets sit outside the barracks and clear of its entrances. Windows have actual openings, sill height2 and top9. The southern divider has an internal window; northern rooms are dead ends. There is no roof to obstruct the overhead camera. Walls and headers are solid for characters, tanks, scanners and shots. Barracks wall segments share one scanner object identity to avoid redundant detection work; this grants no visibility through walls.
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

## Follow-up: fifteen autonomous public tanks

The default pool is now15, one for each P01–P15 personality. This follow-up supersedes the original six-tank baseline above. These are the same arena-owned authoritative public tanks, not a second population or local visual copies. Each slot randomly chooses one of the existing tracked/wheeled × cannon/Gatling assemblies, always with the single-thread Bunny computer. The build and assigned personality persist across that slot's replacements. Spawns use bounded random candidates around the battlefield, existing land support/obstacle/character/tank clearance, then existing safe-anchor fallbacks/retry; no spawn may bypass collision validation.

All installed devices (drivetrain, turret, weapon and each mounted sensor) share bus1 equally: `allocation = 100 / device_count` (normally eleven devices, approximately9.09% each). This explicit setup overrides the Stage2 personality min/max/forced-zero profiles; those original profiles and programs remain available. No CPU or bus boost compensates for Bunny performance: complex personalities run more slowly. Hardware editing is rejected for these tanks to preserve this configuration. Classic hardware editing is unchanged.

Every available tank starts in **Auto**. Entering stops its interpreter/queued commands and switches to **Manual**. The large bottom-center **Auto | Manual** button requests a server-authorized change while retaining occupancy/camera. Switching fences old input with a new control epoch and clears held movement/fire/preparation. Auto suspends manual providers. Exiting, returning to the menu, character death or disconnect restarts the original personality on a surviving abandoned tank; destruction stops it and the replacement starts fresh in Auto. Health and position are not reset simply by switching or exiting.

Auto invocations retain the existing180-second runtime safety limit. A finished/expired invocation restarts with fresh variables after a one-second delay; failed starts retry after five seconds and log the personality ID/reason. No runaway/memory/recursion/CPU guard is removed. Hunter's map resets at each invocation/replacement. AI has exactly the existing legal scanner, terrain and weapon APIs. The supplied single-thread Crazy variant (`programs/variants/02-crazy-bunny.bw`) queues random movement/rotation and blind native bursts without a second CPU thread, target checks, or engine-side intelligence.

`node tools/build-bw-personalities.js --playground` packages editable sources plus their used BW libraries into `src/server/PlaygroundPrograms.luau` for Rojo. Regenerate after changing a source/library; a Node test checks exact parity. `PlaygroundAutonomy` only handles hardware and invocation policy; ordinary BWController/BWExecution and existing combat execute everything. Snapshot metadata includes personality ID/name/source hash/controlMode. Proximity prompts identify personalities. Existing BW IDE Run uses the occupied tank's ordinary execution/authorization; Stop selects Manual. Auto restarts the occupant's last successful BW Editor run if there is one for that possession. Vacating restores the assigned original program.

ServerStorage/BattleWorksStudio `PublicTankCount` defaults to 15 and accepts 2–100. The assignment cycles through the packaged personality list in order and uses the list size as the cycle length. Repeated personalities keep independent tank scores. Optional BoolValue `PlaygroundPersonalities=false` restores the original nonautonomous public-pool behavior for regression/testing. Default true. No onboarding, redemption, garage persistence, economy or general Stage3 population framework is implemented.

Native acceptance additions: restart/sync, verify15 named tanks distributed across safe land; enter one and confirm Manual, use the bottom button to ride in Auto and back to Manual on keyboard/touch/gamepad, exit/disconnect and confirm the original behavior resumes; destroy it and confirm the same personality/build returns in Auto after the normal delay. Check a second client cannot toggle someone else's tank, rapid toggles cannot retain old inputs, and UI remains clear of touch controls. Observe all personalities for several180-second cycles and profile actual server scanner/CPU/frame load. Automated tests do not establish native15-tank performance or claim these deliberately limited Bunny builds are competitively tuned.

## Entry repair and movement diagnosis (2026-11-20)

Successful server-authorized entry restores the actual installed chassis maximum HP (currently100) and clears injury smoke/immobilization through DamageEffects. It preserves position, generation, momentum, weapon heat/reload and hardware. Failed/remote/stale/occupied entry requests, control-mode toggles and exiting do not grant repair. This intentionally supersedes the original no-repair-on-entry behavior; replacement still follows its normal destruction lifecycle.

Production movement tests reproduce the current equal-per-device bus limit on dry grass with a single tank:9.09% movement allocation yields17.355% bus performance,5.467 studs/sec for tracked HyperP35 (35 rating × bus ×.90),5.207 for wheeled Stride3.0 (30 × bus). Grass contributes no extra penalty. Eight scanners collectively receive72.7% of the single bus. This establishes a substantial configuration slowdown independently of population; it does not establish native server frame performance. Bunny CPU grants and intentionally stationary/scanning personalities additionally affect observed activity.

A four-system equal split (movement/turret/weapon/scanner suite25% each, sensors splitting their25%) has been proposed to the user. Allocation remains unchanged pending that preference; do not claim the speed issue is fixed or bypass CPU/bus limits. Initial tuning would yield43.75% movement performance if approved. Single-thread computers and all existing mechanical constraints remain.

## Approved drivetrain curve update (2026-11-20)

The user chose a drivetrain curve change rather than changing equal bus allocations. The prior four-system allocation proposal is superseded: all eleven devices still share the bus equally on Bunny. A5% drivetrain allocation now supplies a15-stud/sec forward rating before terrain/mobility modifiers;100% retains each installed drivetrain's existing maximum, and0% grants no propulsion. The monotonic two-segment calculation is in BWChassis.devicePerformance; see BW_CORE_API_SPEC.md. Turret/weapon/scanner/CPU curves are unchanged. At the current9.09% share, actual dry-grass simulation measures tracks15.017 and wheels16.264 studs/sec. At5%, tracks travel13.5 after their existing.90 terrain factor, wheels15. This is a speed cap at full commanded throttle, not automatic motion or guaranteed minimum through severe terrain.

The reported all-tank burstiness is investigated separately from the editor display: BW CPU decisions are scheduled at10Hz with normal credit limits, while existing device commands and tank physics advance every60Hz fixed tick. A continuous forward/clock-wait regression checks uninterrupted drive output across CPU grants. Personality stop/scan/wait behavior remains intentional, complex single-thread code can wait for credits, and native frame/query load has not been measured. No safety limits or scheduler behavior are changed on an unverified performance assumption.

### Editor programs versus built-in Auto

Follow-up bug fix: editor Run previously marked the tank Auto, and the public Auto loop restarted its personality after the player's program ended, reusing the same request identity. That could make a simple program unexpectedly turn and mix logs. `autonomyActive` now explicitly gates only built-in personality invocations. Player-source completion/failure restores Manual; Stop is persistent. Explicit Auto, exit/disconnect and replacement still restart the personality. Log invocation serials/origin labels and control-lease fencing prevent mixed histories. The live editor is draggable, stays open on Run and highlights matching executing source; see BW_RUNTIME.md.


The default layout includes six blue-striped protected configuration pads. Stop inside a pad in Manual and use the tank HUD gear to swap between wheels and tracks, choose a cannon or Gatling, or tune the shared bus. A swap rebuilds the tank simulation and its client model while preserving the current hull health and driver. [Zone layout and safety rules](BUS_CONFIGURATION.md#in-world-configuration-zones)

## Obstacle course

From the dry west-bank spawn, follow the Proving Grounds sign to **A / Ravine Trial**. Drive a Manual tank through the five numbered gates on the 10-stud-wide timber decks. Follow the east-bank sign to **B / Moving Target Range**. Hit the steel plates from the firing line at 43, 88, and 146 studs. They move laterally at 7, 15, and 23 studs per second. Follow the orange route north to **C / Cannon Court**, a 112 × 112 stud square. Enter at the orange start line and reach the green finish line while eight side-mounted cannons fire staggered crossing shots. The HUD tracks section progress and offers Restart, Replay, and Return to Playground.

The server excludes public spawns from the course and uses the vehicle contact solver to keep autonomous public tanks out. Progress belongs to each participating tank. The range and gauntlet share physical targets and emitters across participants, and their patterns reset when their section becomes idle. Manual runs use the same tank movement, line of sight, weapons, and damage pipeline as the surrounding arena. BW execution is currently blocked in the course, and BW receives no hidden route or challenge state. There is no new mode or Place.

Falling or dying returns the driver to a fresh Manual tank at the course start with their applied equipment and bus setup. Elsewhere in the Playground, occupied tanks and their drivers respawn together on safe ground. Innovation Lab keeps its experiment lifecycle.

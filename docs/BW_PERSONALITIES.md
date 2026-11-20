# Fifteen real player BW personalities — Stage 2

All fifteen approved sources are implemented. G1–G3 provide own geometry/timing and physical `aim_at`; G4 removes statement/line ceilings while retaining technical/CPU/recursion safety; G5 adds bounded terrain observations to the existing Scanner. Nothing populates The Playground automatically. Stage3 remains out of scope.

## Build, inspect and run

```
node tools/build-bw-personalities.js /tmp/bw-personalities
```

Each output `.bw` is a complete, editable player program: referenced functions from `programs/lib/*.bw` followed by the original source in `programs/personalities/*.bw`. Paste an expanded output into the existing BW editor and Run with compatible existing hardware. No native imports, hidden Luau AI, special compiler or personality-specific privileges. The builder includes only referenced helpers; it does not minify intelligence or exempt library costs.

`manifest.json` records original source, library and generated-source SHA256 hashes, initial example hardware/tier, seed and bus constraints for reproducibility. The generator also prints each output hash. Original bodies/libraries remain versioned source; do not paste just a body without its required helpers.

## Personalities, diagnostics and deliberate limitations

All programs print phase changes to the existing private BW history. Ordinary variables expose sector, seed, progress, target association, map, traffic, health/threat or movement estimates as applicable. Output uses existing bounded/rate-limited history; debug printing adds no sensing or free command execution. Each body contains2–3 contextual improvement hints. `travel()` returns horizontal displacement squared in studs²; Trailblazer intentionally uses a squared-distance progress ratio to avoid an extra square root.

| ID / source | Behavior | Example CPU; key limitation |
|---|---|---|
| P01 `01-marauder.bw` | Advance about20 studs, settle, scan, shoot, repeat; recover using actual progress/status. | Dual; equal lens scanning and repeated recovery choices can improve. |
| P02 `02-crazy.bw` | Seeded random movement/turret headings; independent blind firing thread. Gatling holds through native burst/heat limit, resumes after cooldown. No scanner or target/alignment check. | Dual **minimum** for two threads; Bunny safely rejects excess thread capacity. PRNG/routes are intentionally simple. |
| P03 `03-tower.bw` | No drive commands. Match timestamped surface hits, estimate velocity, predict finite projectile flight/preparation/turn delay, physically aim and reacquire before fire. | Octa recommended; no anchoring, default15-degree fixed lenses retain gaps. Nearest valid contact and approximate90-degree turning allowance are improvable. |
| P04 `04-sniper.bw` | Random reposition, settle/non-airborne check, shared Tower predictor, bounded search then relocate. | Octa recommended; no crouch/hitbox reduction or promised cover. Moving-surface/noisy-hit assumptions remain. |
| P05 `05-cat-and-mouse.bw` | Remember a legal obstacle hit, choose its side away from observed enemy, fire then try short cover retreat/rescan; evade without known cover. | Quad; one surface point does not reveal a whole obstacle or guarantee occlusion. |
| P06 `06-hunter.bw` | Initially unknown25-cell BW map, legal obstacle/ground samples, movement-conflict updates, bounded parent/queue BFS, observed trajectory projected toward a corner cell; fresh-scan gunnery/shared prediction. | Octa recommended;60×60 local area/coarse cells may be wrong. Returns toward its own origin outside map. Unknown routes remain hypotheses, not certified support. |
| P07 `07-sentinel.bw` | Methodical eight-sector watch and small physical chassis sweeps to fill lens gaps. | Quad example; predictable equal-sector rhythm. No velocity prediction. |
| P08 `08-skirmisher.bw` | Distance-band hysteresis, oblique approaches, short withdrawals and shooting through independent device queues. | Dual; fixed bands/directions are improvable and turning can lose the observed lens contact. |
| P09 `09-wallflower.bw` | Right-side wall following, front-obstacle corner turns, side-distance steering corrections and short progress-checked moves. | Dual; sparse hits can confuse doorways/corners. No global route map. |
| P10 `10-prospector.bw` | Bounded local observation-age/visit scores choose less-known directions; memory resets after significant displacement. | Quad; a new direction is not proof of safe ground. Turning is not included in the novelty score. |
| P11 `11-gatekeeper.bw` | Own initial-coordinate home tether, short patrol, observed approach classification, return after displacement or bounded pursuit. | Dual; circular tether and one-contact approach history can improve. |
| P12 `12-duelist.bw` | Sticky legal identity, timeout/reacquisition, intentionally simple same-side orbiting pursuit. | Dual; **deliberately ignores terrain**, including G5. May circle off a cliff. Not an engine safety bug. |
| P13 `13-survivor.bw` | Own health/damage and observed enemy count adjust aggression. Critical damage prompts bounded escape attempts; blocked escape returns to fighting. | Dual; never waits for nonexistent regeneration. Escape direction/thresholds are simple and can be improved. |
| P14 `14-ambusher.bw` | Eight aged spatial traffic clusters from legal sightings, brief repeated observation, bounded relocation toward promising approaches, fire only on current visible enemy. | Quad; repeated sightings are a crude traffic measure; stale clusters decay and no blind prefire occurs. |
| P15 `15-trailblazer.bw` | Measure short drive pulses/settling, adapt pulse length, compare ground/edge evidence with poor progress to distinguish observed support blockage from uncertainty/missing terrain. | Dual; learned pulse performance may not transfer to other ground; unknown terrain is not certified safe. |

Tower/Sniper share the exact same visible `prediction.bw`. Hunter's arrays, BFS and interception remain BW, including failure/replanning. No engine map/path/cover/intercept primitive exists. Prediction assumes approximately constant velocity of observed surface hits, uses actual finite projectile speed and bus-limited turret/preparation metadata, and falls back to observed-point aim for missing/noisy/implausible motion. Current airborne Gatling trajectories curve, so straight-line lead is approximate. There are no actual hitscan weapons or finite clips; neither is invented.

## Equipment and bus constraints

`profiles.json` is a declarative **future-host data contract**, not an allocator or population implementation. Each ID preserves original source/libraries, example initial CPU/weapon/mobility, seed, actual drivetrain/turret/weapon/sensor min/max/forced-zero constraints and priorities. `sensor*` expands to remaining installed physical mounts in angle order, excluding already listed priority names. Per-bus capacity is100; maxima are ceilings, not permission to allocate every maximum simultaneously. Actual production hardware validation tests the minimum configurations.

Tower forces drivetrain allocation0; Crazy forces every scanner0. Programs do not repair/replace hardware or change bus allocations. CPU tiers above Bunny are explicit example/initial equipment choices, never a silent live public-tank upgrade. Except Crazy's two-thread minimum, slower CPUs execute the same algorithms more slowly under normal fees. Existing missing/disabled device results are handled without inventing contacts: stationary defense where drive is absent, no non-Crazy shooting without observations, and normal failure/readiness behavior for an unavailable gun/turret. Both current tracked/cannon and wheeled/Gatling assemblies are covered by runtime tests.

For later Stage3: preserve original source/library/generated hashes and actual installed equipment/device-to-bus topology. Record an `allocation_seed` and respawn index for valid deterministic allocation choices. Never randomize source/personality or swap equipment at respawn. Program PRNG seeds are editable source scalars now, recorded in profiles/manifest; no hidden runtime seed API was added. A fresh runtime recreates map/traffic/target memory. Existing180-second program lifetime remains; a future population host must decide restart policy. No such host is implemented here.

## Verification and native acceptance

The existing harness compiles all fifteen generated programs and executes them independently on both current drivetrain/weapon assemblies with normal CPU/device queues, native TankSimulation/WeaponWindup/RattlerWeapon and legal-schema cone/range scanner fixtures. Focused scenarios cover movement/recovery, predictor leading, coverage sweep, approach bands, wall corners, novelty memory, physical push/home return, sticky identity, critical-health blocked escape, traffic visibility/decay, terrain reaction, Hunter map reset and the actual BW BFS routing around walls/enclosure. All fifteen also exercise disabled scanner/drive fallbacks, actual profile minimum validation and transient scannerBusy responses in a fresh harness group. Crazy's blind overheat/resume and seed replay are verified. These fixtures are not native Roblox raycasting.

Scanner geometry/elevation, unknowns, water limitations and separate production query tests are detailed in [SCANNER_TERRAIN.md](SCANNER_TERRAIN.md). Large-source/recursion/editor/CPU safety is covered separately. Existing server/ownership/combat/Classic/editor regressions remain required.

Native Studio acceptance (not performed here):

1. Build expanded sources, configure explicit example hardware, paste each into the existing editor and verify private phase logs, bus limits and Stop. Check the ordinary insufficient-thread message for Crazy on Bunny.
2. Run Tower/Sniper against a second player's moving/elevated tank; observe real barrel alignment, finite projectile travel, preparation, Gatling heat and occlusion. Assess their intentionally approximate lead, not guaranteed hits.
3. Exercise Hunter against actual imported walls/corners/ramps/bridges. Inspect/reset its BW map; verify it cannot sense unseen enemies or hidden ground. Exercise Trailblazer at support edges and blocked obstacles. Duelist may fall while pursuing.
4. Verify Survivor escapes when possible and continues firing when cornered at critical health without healing. Verify Ambusher never shoots remembered hidden traffic. Test all programs' wheel turning/reversing limitations and manual takeover.
5. Test real MeshPart/compound terrain raycasts, native water versus cosmetic-water unknowns, narrow-lens side lanes and frame/query cost with two players.
6. Stop, switch tanks, exit, destroy and disconnect during program execution; confirm existing authoritative cleanup releases every device/input. Check Classic/custom-world loading and keyboard/touch/gamepad regression behavior. No automatic Playground population should appear.

## Steering follow-up

The shared `turn_to(heading)` helper branches on actual own drivetrain metadata. Wheels use continuous forward plus signed heading-error feedback through steer_left/right, bounded by installed max wheel angle and30s deadline; tracks keep turn_right(to=heading). Wheels center and stop after turning. The single-thread Crazy variant also uses steering for wheels; its tracked turn queues an ordinary bounded forward leg so it does not spend every random change stationary. No physics changes or automatic navigation. Duelist continues its deliberately simple pursuit and ignores terrain. All original sources/hints/profiles remain editable, and the generated Playground bundle is refreshed with `node tools/build-bw-personalities.js --playground`.

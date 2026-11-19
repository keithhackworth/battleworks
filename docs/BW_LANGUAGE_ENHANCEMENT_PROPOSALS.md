# Stage 2 — personality and BW capability review proposals

**Review gate: P01–P15 and G1–G5 APPROVED and IMPLEMENTED (2026-11-19). Stage2 complete; Stage3 out of scope.**

This document records the approved pre-code checkpoints. All15 sources and G1–G5 are implemented and verified. The original G4 checkpoint below is historical and superseded by the approved removal, not a256 ceiling. Stage3 remains out of scope. Any additional command or limit increase requires a new review. Original proposal rationale is retained below; approval decisions supersede the historical review questions.

## Actual architecture and constraints reviewed

Reviewed docs/BW_CORE_API_SPEC.md, docs/BW_ROADMAP_CHECKLIST.md, BW_LANGUAGE, BWParser/BWLexer/BWExpression/BWCommands, BWExecution/BWDevices/BWTankAdapter, BWSelfState, BWChassis/BWConfig, ComponentCatalog/VehicleAssemblies, DirectionalScanner/ScannerGeometry, RattlerWeapon/TankSimulation and existing BW/physics/server tests.

- Real syntax is `function name(parameters):`, four-space blocks, `with thread(n):`, `while`, immutable API results, mutable fixed-size player arrays/dictionaries, zero-based indexing. No imports, closures, append/resize, `for`, `break`, `continue`, native random/trig/sqrt/floor/modulo operators. Shared library delivery must concatenate **visible editable BW source** before normal compilation; no secret Luau controller. Expanded source must still meet the ordinary limits.
- Limits: 16,384 bytes, 400 lines, **128 total source statements including functions**, 512 compiled instructions, 64 items per array/dictionary, 128 variables, 50 call frames/thread, 180 simulated seconds/run, normal device timeout and queue bounds. Nested small fixed arrays are supported. None of these limits is silently raised for personalities.
- CPU grants10Hz; per-thread ticks/grant Bunny10, Dual15, Quad20, Octa30, Hexadeca40. Readiness consumes one tier-relative cycle; full snapshot two cycles plus expression/assignment costs. Cheap own queries are1 tick except chassis heading0.1. Cached immutable equipment metadata is useful; dynamic reads/observations must be refreshed deliberately. Polling readiness or rebuilding full snapshots every iteration is not free.
- `forward/back`, persistent steering, heading turns and `command_status` are available. Commands return acceptance, not completion. Tracks pivot only when capability permits; wheels must turn along a moving arc. `stop()` releases drive intent; it does not erase physical momentum. Recovery must use observed displacement/time/status, not a fabricated collision flag or teleport.
- Eight standard sensors have chassis-relative mounting angles0..315 at45° intervals and15° cones. Scanner selects a physical mount, not an arbitrary direction. Turret rotation does not sweep these sensors. Chassis movement may fill coverage gaps; a zero-drive Tower cannot do so. All programs must admit blind sectors and stale observations. Existing configurable cone/range fields are real hardware settings, not permissions to invent different installed equipment.
- Successful Scanner results expose timestamp, count, zero-based detections, visible hit `point.{x,y,z}`, distance, world/relative direction, relation and stable observed tank `player` identity. These legal observations can support velocity estimates and occupancy maps. They are **visible surface hits**, not exact enemy centers, velocity, health, hull dimensions or future positions. No hidden enemy state, preloaded geometry, map bounds, team knowledge or target health is supplied to the programs.
- Existing cannon and Gatling launch finite-speed projectiles (currently24 and85 studs/s). Cannon timing, Gatling heat/recoil, bus performance, platform leveling, mount stops and server hits remain authoritative. There are no hitscan weapons, magazines or ammunition capacity. Cannon/Gatling depression limits are mount-relative. No crouch/low-profile mechanism exists.
- Public Playground tanks currently use Bunny CPUs. Recommended higher tiers below are **Stage2 example/harness requirements or explicit initial hardware choices**, not authorization to upgrade live public tanks. Stage3 must resolve population hardware policy separately. No tier/equipment replacement occurs on autonomous respawn.

## Proposed reusable BW libraries — no native commands requested

Keep seeded PRNG, normalization, absolute value/clamp/min/max, floor/remainder, bounded Newton square root, angle math, constant-velocity interception, observation matching, local grid operations, cover scoring and recovery in player-visible BW functions. Only each program's needed helpers are inlined. PRNG is reproducible, not cryptographic. Match tank identity before differencing timestamped points; reject zero/negative dt, stale samples and implausible changes.

A native math package could reduce CPU/source cost, but BW libraries can express these calculations. **No native math/random, pathfinding, cover or interception command is proposed now.** Hunter's complete flattened statement count and all library costs must be measured after this review. If required functionality cannot fit normal limits, stop with measured evidence and a separate narrowly scoped proposal; do not silently truncate its algorithm, hide logic in the host, or raise limits.

No `map_world`, `find_cover`, `predict_intercept`, `find_path`, automatic target selection/tracking, unseen-target lookup, global terrain probe or privileged navigation builtin is permitted.

## General-purpose capability proposals — approval required

### G1 — Exact own barrel geometry on existing introspection

**Proposal:** extend existing `get_turret_direction()` and the same `get_tank_state().turret` record with `pivot`, `muzzle_position`, `direction`, each an immutable `{x,y,z}` world-coordinate/vector record. Pivot/muzzle are studs; direction is a unit vector. No arguments; existing status/reason semantics. Keep current fees:1 tick for individual direction read, two tier-relative cycles for full snapshot. Ordinary field reads retain normal cost. Update static result shapes and tests.

**Why players benefit:** correct close-range/elevated shot calculations, own line-of-fire diagnostics and projectile travel-time estimation, including recoil/body movement. These are facts about the player's own hardware, not a query of surroundings.

**Why a BW library alone does not suffice:** Stage1 exposes chassis-base coordinates and barrel angles but not actual pivot/muzzle offsets, bounce or the complete chassis transform. A library cannot reconstruct exact release origin without hard-coded assumptions about hidden component geometry. The engine already computes that pose; return the existing authoritative calculation, without changing firing.

**Use cases:** shared direct/predictive gunnery for every personality except Crazy. Crazy must not add an aiming check.

### G2 — Generic simultaneous physical coordinate aiming

**Proposed signature:** `aim_at(x, y, z, best_effort=true)`; three finite positional world coordinates in studs, same coordinate bounds as existing World intent. Return normal acceptance/failure dictionary with commandId; one submission tick plus ordinary argument costs. Existing turret FIFO/abort/status/authorization, bus-limited angular speed on both axes, mount stops and instruction timeout apply. No scene query, target handle, prediction, target selection, tracking or guaranteed hit. A finite point command ends when physically aligned within existing tolerance. If mount stops prevent reaching the point, complete at the stop with an explicit proposed `mountLimited` completion reason so the script can withhold fire; confirm this result convention during implementation review.

**Why players benefit:** any script can aim at a point it legally measured or calculated, including geometry experiments, elevated coordinates and player-written predictors. It uses the existing World aiming solver, not a parallel turret engine.

**Why a BW library alone does not suffice:** BW currently queues single-axis yaw/elevation commands on one turret device. A function can calculate angles and issue them sequentially, but cannot emit simultaneous World yaw/pitch intent through that device. Manual World input already has that physical capability. This proposal exposes the same primitive to scripts, with no mechanical advantage or pre-alignment bullet redirection.

**Use cases:** direct aiming for non-Crazy bots and player-library interception for Tower/Sniper/Hunter. It does not implement interception inside the engine.

### G3 — Own weapon timing/heat metadata, not a clip mechanic

**Proposal:** extend existing `is_weapon_ready()` and `get_tank_state().weapon.readiness` with `operation`, `heat`, `max_heat`, `burst_seconds`, `max_burst_seconds`, `overheat_seconds`, `fire_interval_seconds`, `effective_fire_interval_seconds`, `preparation_seconds`, `effective_preparation_seconds`. Use actual component/private own weapon values; inapplicable or unavailable fields are null. Heat/burst use the current engine's active-fire-seconds convention; intervals/preparation are seconds. Effective intervals divide by weapon bus performance; zero allocation yields null, not infinity. Keep existing fees (one tier-relative readiness cycle, two-cycle full snapshot) and existing fields/readiness meanings. No weapon state mutation.

**Why players benefit:** equipment-adaptive burst planning, heat-aware diagnostics and latency/lead estimates for the player's own cannon windup. Other programs still use one-second Gatling bursts by default.

**Why a BW library alone does not suffice:** current readiness identifies blockers but does not expose the installed gun's maximum burst/heat or preparation parameters. A library cannot discover those exact values without hard-coded catalog numbers or wasteful live firing calibration. They are already engine-owned own-equipment facts.

**Crazy interpretation approved (2026-11-19):** no clip exists. “Empty available clip” means **hold the native Gatling trigger through its remaining burst/heat allowance until native overheat**, wait for readiness, repeat. Do not create ammo counts or weaken cooling limits. Cannon fires whenever ready. Crazy never checks for an enemy, target validity or turret alignment; all scanners may be0%. If true finite magazine behavior is intended instead, that is a separate weapon milestone, not silently included here.

## Shared firing and diagnostics contract

All non-Crazy programs prefer a legally scanned enemy when ready, using `type == "tank"` and `relation == "enemy"`, stable observed identity, observation age, mechanical reachability and a clear/reacquired legal observation before release. They must not shoot blindly at indefinitely remembered contacts. Target disappearance/occlusion clears or ages their actionable target; memory may guide navigation only. Gatling default burst is one second (or the native shorter remaining heat allowance); cannon uses normal fire activation. Readiness is checked just in time and does not bypass windup, cooldown, heat, obstruction or bus gating.

Tower and Sniper use **the same visible BW predictor**: match two observations by identity/time, estimate velocity from observed hit points, solve finite projectile interception with bounded iteration/quadratic math, include observation age, anticipated CPU/turn time and actual preparation time, and recompute near release. Turning uses effective turret speed; do not assume an instant snap. If motion samples are missing/noisy/stale or no positive finite intercept exists, use observed-point direct aiming or withhold. A future actual hitscan model would use direct observed-point aiming rather than dividing by null speed; none is implemented now. Current airborne downward Gatling curves mean a straight-line predictor is approximate; do not invent a reliable curved-flight solver or promised hits.

Each source will contain a bounded diagnostic record such as mode, target identity, observation time/age, action/status/fallback reason, seed, last progress and relevant personality metrics. Print only on mode changes or at a bounded cadence. The player can inspect/change these variables. Every program gets2–3 natural improvement comments near its actual algorithm, not artificial bugs.

## P01 — Marauder (user-defined)

**Review: APPROVED (2026-11-19).** Behavior: advance about20 studs, release drive, measure settling, scan and engage, repeat. Use commandId/status plus own displacement to detect blocked/stuck progress; back/turn/retry with bounded attempts and a logged fallback. Wheeled recovery uses reverse/arcs, not pivot promises.

Algorithm/primitives: finite forward/back, stop, steering/heading turns, command_status, get_clock, coordinates/state, mounted Scanner, readiness/fire and the shared direct-aim library. Missing facts: no collision/stall flag or forward cliff probe; infer progress, never claim safe ground ahead. Proposed additions: G1/G2 for honest3D gunnery; no Marauder-specific commands. Mathematics/recovery fit editable BW helpers; no extra native convenience is justified.

Bus profile: D20–50, T10–25, W15–35, each S1–4; priority D/W/T/front sensors/other sensors. Bunny minimum, Dual recommended. Missing drivetrain -> stationary scan/fire; no scanner -> recovery/patrol only without blind shots; no gun -> navigation diagnostics only.

Tests: ~20-stud segments under supported traction, coasting/settle, blocked route recovery, wheeled/tracked distinction, scan-to-shot and all-tier CPU pacing. Planned hints: “This works, but it's not the smartest way to choose a route.” “Try learning which recovery direction worked last time.”

## P02 — Crazy (user-defined)

**Review: APPROVED (2026-11-19).** Behavior: seeded random movement and a new random desired turret heading whenever movement changes. Fire whenever the weapon is ready, regardless of enemies; no aiming/target/scanner check. Gatling runs to its real native heat/burst stop; cannon activates whenever ready. Weapon and movement work asynchronously through the normal device queues.

Algorithm/primitives: visible bounded PRNG, forward/back/steer/turn, turret_left/right/up/down, command_status, get_clock, own weapon type/readiness, fire. Missing facts: finite clip does not exist; exact remaining heat/burst parameters are not in Stage1. Proposed additions: **G3 only**. G1/G2 are unnecessary here; no privileged random or special “Crazy fire” command. A BW PRNG suffices and preserves reproducibility.

Bus profile: D25–55, T15–35, W20–50, **all S forced0**; priority W/T/D. Bunny minimum. If mobility absent, continue random turret/fire; if turret disabled, keep firing current barrel direction and report it; if weapon absent/disabled, continue movement with a diagnostic. Never substitute an enemy-gated behavior.

Tests: zero scans at0% sensor power; shots with no enemies; fires before alignment when ready; native cannon pacing; Gatling remaining-heat-to-overheat and normal recovery; deterministic seed replay; no growing device queue. Planned hints: “A better random walk might avoid repeating the same corner.” “What if random headings favored places we haven't aimed at recently?”

## P03 — Tower (user-defined)

**Review: APPROVED (2026-11-19).** Stationary means no requested driving, not anchoring or immunity to pushes/recoil; cannon is recommended for a stable post. Behavior: stationary intelligent targeting with the shared player-written velocity/interception library. Rank legal contacts by observation quality, achievable angular travel and time of flight; refine when reacquired. Do not use enemy HP or future trajectories.

Primitives: Scanner detections/point/timestamp/identity, own state/speed/readiness/turret direction, command_status, clocks, fire, BW math/predictor. Gaps: exact own muzzle/preparation geometry/timing absent; one-axis BW turns cannot match simultaneous physical aiming. Proposals: G1/G2/G3; no native interception/tracking. Scalar math in BW suffices; budget must be measured.

Bus profile: **D forced0**, T25–100, W25–100, each S4–20; priority T/W/sensors. Quad recommended for full predictor; low-compute fallback is slower observed-point aiming with a clear diagnostic. No movement bus means no chassis scan sweep: default15° cones retain blind gaps. Wider cones can be an explicit initial existing hardware configuration, never a hidden per-respawn change. If no sensors/gun, remain stationary and report unavailable subsystem.

Tests: stationary pose, timestamped moving contacts, turn delay/cannon preparation, shared predictor parity with Sniper, hit-point noise/staleness, unreachable pitch and default blind sectors. Planned hints: “We're assuming the enemy keeps moving in the same direction. What if it turns?” “Try spending less time following a contact we can't reach quickly.”

## P04 — Sniper (user-defined)

**Review: APPROVED (2026-11-19).** Behavior: seeded random bounded reposition, settle, then use exactly Tower's BW predictor; optionally relocate after firing or contact loss. “Low profile” means choosing an observed low/exposed position or holding still; **there is no crouch mechanism**. Never claim reduced collision size.

Primitives: coordinates/motion, legal observations, clocks/status, ordinary movement/aim/fire, shared PRNG/predictor. Gaps/proposals: G1/G2/G3; no native reposition/hide/crouch command. BW functions suffice for relocation choice and interception. Query own Y changes only as feedback, not a map of hidden elevations.

Bus profile: D10–35, T25–65, W25–65, each S1–8; priority T/W/S/D. Quad recommended; slower direct-aim fallback on limited CPU. No drive -> Tower-style stationary behavior; no sensors -> hold without blind fire. Original equipment remains installed.

Tests: bounded reposition/settling on inertia, legal wait, same predictor as Tower, optional relocation, no crouch illusion, hardware fallback. Planned hints: “This waiting spot may be low, but is it actually less exposed?” “Relocating after every shot isn't always worth the travel time.”

## P05 — Cat and Mouse (user-defined)

**Review: APPROVED (2026-11-19).** Behavior: remember legally observed nearby obstacles, choose a candidate point behind a recently seen obstacle relative to the latest enemy bearing, peek/engage, then retreat/reposition. A cover candidate is a hypothesis checked by movement and rescanning, not guaranteed occlusion.

Primitives: object/wall detections and hit points, coordinates, fixed small memory, vector math in BW, movement/status/recovery, readiness/fire. Missing: obstacle extent, full silhouette, hidden side geometry and a guarantee a position is safe. Proposals G1/G2 for direct gunnery; no find_cover/line-of-sight shortcut. Candidate scoring and testing belong in BW.

Bus profile: D25–55, T10–30, W15–35, each S1–6; priority D/side+front S/W/T. Quad recommended. No known cover -> short evasion/re-scan; no drive -> reactive defense; no sensors -> retreat only from movement/own damage feedback, no invented targets.

Tests: discover cover through actual Scanner, occluded target not supplied, failed-cover fallback, obstacle extent uncertainty, wheeled retreat and bounded retries. Planned hints: “This hiding spot looks good, but are we exposed from another direction?” “Try remembering which obstacles actually blocked incoming sight lines.”

## P06 — Hunter (user-defined)

**Review: APPROVED (2026-11-19).** Behavior: build a bounded local occupancy/confidence grid from legal wall/building points, scan paths and observed motion, then plan short navigable routes toward a projected corner interception. Distinguish unknown/free/blocked; unknown is never assumed safe. Replan when progress conflicts with memory. Map begins unknown and lives only in this runtime; new runtime on respawn resets it.

Algorithm: tentative5×5 or7×7 nested BW arrays (each dimension under64), bounded frontier/parent storage and bounded breadth-first/best-first search, temporal enemy track, local route following with real wheel/track geometry. Grid size/search budget must pass ordinary source/CPU/memory limits; not pre-approved to raise them. Gaps: sparse surface hits are not obstacle hulls; scans do not prove support over open ravines; no hidden route, enemy velocity or map bounds. Proposals G1/G2/G3; no map_world/find_path/predict_intercept. Mapping/search/prediction stay visible BW code. If a complete readable implementation cannot fit128 statements, report measured failure and seek a separate general-purpose proposal rather than hide logic or drop the behavior.

Bus profile: D25–70, T15–60, W15–50, each S2–12; priority front/side S/D/T/W. Octa recommended for full behavior. Lower CPU -> explicitly bounded small-map/direct pursuit fallback or an explicit unsupported-hardware diagnostic; no silent claim to full Hunter. No scanning -> no map, conservative movement/diagnostic only.

Tests: map starts unknown; only observed obstacles populate it; walls/corners/change/recovery; paths constrained by wheel radius; interception uses legal time-series only; fresh runtime resets map; source expansion and CPU cap. Planned hints: “Our map is only as good as what we've actually observed.” “This local search works, but a larger or better-prioritized frontier could find another route.” “We're guessing which corner the enemy will choose.”

## Nine additional personalities — names and concepts approved (2026-11-19)

### P07 — Sentinel

**Review: APPROVED (2026-11-19).** Simple scan-sector sentry: hold position between deliberate chassis coverage sweeps, engage first valid contact and use a bounded lost-contact timeout. Different from Tower: no velocity prediction or target scoring beyond current validity; sweep is the algorithm lesson. Use Scanner, can_pivot metadata, chassis turns/status, readiness/fire and direct aim. G1/G2 proposed; no unique commands. Library normalization suffices. No unseen sectors are treated as empty; wheels sweep only by a small observed arc and then settle.

Bus D10–25, T15–40, W20–45, each S2–6; priority S/T/W/D; Bunny minimum. Missing drive -> fixed-lens stationary fallback with gaps; missing scanner -> no fire. Tests: gaps/sweep, acquisition timeout, no unsupported wheel pivot. Hints: “Scanning every sector equally wastes time when one is busy.” “How long should we remember a contact we can't see now?”

### P08 — Skirmisher

**Review: APPROVED (2026-11-19).** Range-band kiting: compare observed range against a preferred band, alternate short oblique advances/withdrawals, reacquire, burst. Teach feedback control/hysteresis without a map. Use range/timestamp, own motion and steering capability, queued moves/status, readiness and direct aim. G1/G2; no native kiting/control command. Speed limits and noise belong in the BW feedback loop.

Bus D35–60, T15–35, W15–35, each S1–4; priority D/W/T/S; Dual recommended. No drive -> stationary firing; no sensor -> no target chase. Tests: band transitions, avoiding oscillation, moving target, reverse and wheel arcs. Hints: “A fixed distance band isn't ideal for every weapon.” “Try smoothing noisy range changes before reversing.”

### P09 — Wallflower

**Review: APPROVED (2026-11-19).** Boundary/wall following with corner recovery: keep a legally observed wall on one side, adjust movement pulses from side/front ranges, engage visible enemies opportunistically. Teach local reactive navigation rather than Hunter's explicit search or Cat's cover scoring. Use selected real sensor mounts, coordinates/status and steering. G1/G2 for firing; no wall-follow builtin. Gaps: sensor hits don't guarantee a continuous wall; stop/reacquire at uncertainty.

Bus D25–55, T10–25, W15–35, each S1–6; priority chosen side/front S/D/W/T; Bunny/Dual. No side lens -> front-pulse/turn fallback; no steering -> stop and report, not pivot. Tests: inner/outer corners, lost wall, narrow gaps and no fabricated wall distance. Hints: “Following the same wall forever can make us predictable.” “A sudden empty scan could be a doorway—or a blind spot.”

### P10 — Prospector

**Review: APPROVED (2026-11-19).** Information-driven exploration: maintain a tiny visit/observation-age table and prefer stale/unknown local sectors, stopping to scan and fight when an enemy appears. Optimize new legal observations rather than pursue a target or compute paths. Use fixed arrays, clock, own coordinates, scanner metadata/detections, simple BW novelty scoring and ordinary controls. G1/G2 for firing; no information/map oracle. Unknown ground remains risky; partial visibility is not proof of a safe corridor.

Bus D15–45, T10–35, W15–40, each S3–10; priority S/D/T/W; Quad recommended. Low memory/CPU -> coarse sector counters; no scanning -> no claimed exploration knowledge. Tests: repeated sector penalties, aging, target interruption, no prefilled world cells. Hints: “A sector can be unfamiliar without being safe to enter.” “Try balancing new information against the cost of turning.”

### P11 — Gatekeeper

**Review: APPROVED (2026-11-19).** Home-tether defense: record its own starting coordinate, patrol a bounded neighborhood and intercept legally observed approaches toward that area, returning after bounded pursuit. Different from stationary defense: coordinate tether and approach classification govern movement. Use own position/clock, visible point history, BW vector math and normal movement/status. G1/G2; G3 if predictive timing is used, otherwise direct reactive fallback. No privileged objective position; home is self-observed.

Bus D15–35, T20–50, W20–50, each S1–6; priority T/W/S/D; Dual recommended. No drive -> fixed post; no sensors -> return/hold, no enemy invention. Tests: tether overshoot/recovery, approach/recede classification, wheel return route and stale contact. Hints: “A circle around home is a crude definition of what matters.” “Chasing one intruder can leave another approach unattended.”

### P12 — Duelist

**Review: APPROVED (2026-11-19).** Sticky one-on-one orbit: choose a valid scanned enemy, retain identity with hysteresis, move around a preferred side and re-engage; switch only after loss/timeout or a substantially better legal contact. Teach target association and sustained geometry, unlike Skirmisher's radial zigzag. Use stable observed identity/range, clocks, own turn radius/capabilities and persistent steer. G1/G2; no orbit/lock-on builtin. Other tanks' private health is unavailable and not used.

Bus D30–55, T20–45, W15–35, each S1–4; priority T/D/W/S; Dual. No mobility -> sticky stationary target; no identifiable observations -> direct reactive fire without a fake persistent lock. Tests: target crossing/occlusion, avoiding identity swaps, genuine wheel orbits and no behind-wall tracking. Hints: “Always orbiting the same side makes us easier to lead.” “Sticking with one opponent can ignore a closer threat.”

### P13 — Survivor

**Review: APPROVED (2026-11-19).** Own-damage-driven state machine: compare fresh own HP/time, reduce exposure after a recent damage spike, retreat briefly, then cautiously resume ordinary scan/fire. No invented repair/healing. It still fires on a valid scanned enemy when ready, including during a legal withdrawal. Use own health/motion/time, legal sightings and normal controls. G1/G2 for aiming; no threat-source/damage-direction oracle. BW thresholds/state transitions suffice.

Bus D20–50, T10–30, W15–30, each S1–5; priority D/S/W/T; Bunny minimum. No reverse -> forward turning escape; no drive -> hold defense; no scanner -> no target inference from damage alone. Tests: damage spike/hysteresis, quiet timeout, HP preserved, no hidden attacker location. Hints: “A fixed damage threshold may retreat too early—or too late.” “Backing away isn't always the direction that reduces exposure.”

### P14 — Ambusher

**Review: APPROVED (2026-11-19).** Traffic-learning ambush: keep a bounded histogram of legal repeated crossing points/times, relocate to an observed reachable waiting area and wait for a new visible contact. Teach temporal aggregation rather than Tower's immediate velocity solution. No blind shots at a predicted return; ordinary validity/readiness still gate fire. Use observed points/timestamps/identity, fixed BW arrays, own coordinates and candidate-position scoring. G1/G2, G3 if reusing predictor; no traffic or hidden-spawn API.

Bus D10–30, T25–60, W25–60, each S2–8; priority S/T/W/D; Quad. Insufficient history -> reactive sentry with bounded relocation; no drive -> learn from current post. Tests: repeat versus one-off contacts, stale traffic decay, unobserved lanes remain unknown and no blind prefire. Hints: “Yesterday's busy crossing may be quiet now.” “This waiting spot watches one route but leaves other approaches exposed.”

### P15 — Trailblazer

**Review: APPROVED (2026-11-19).** Self-calibrating cautious traversal: estimate commanded-versus-achieved travel and settling from own position/time, adapt pulse length/turn conservatism when slipping, blocked or bouncing, and opportunistically engage legal contacts. Teach online physical feedback rather than a map, route oracle or constant movement pattern. Use own coordinates/motion/bus ratings, command_status/clock, legal front scans and BW arithmetic. G1/G2 for firing; no traction/terrain-ahead builtin. Y changes are feedback after motion, not advance knowledge of a cliff.

Bus D25–55, T15–35, W15–35, each S1–5; priority D/front S/T/W; Dual. No drive -> stationary scan/fire; insufficient samples -> short conservative moves rather than false calibration. Tests: tracked/wheeled inertia, low grip and slopes, blocked feedback, bounded estimates, gravity remains real. Hints: “We're learning from a few recent moves; different ground may behave differently.” “A shorter step is cautious, but it can also waste time.”

## Profile and seed data contract for later Stage 3

The D/T/W/S ranges above are percentage constraints, **not allocations to a new scanner bus/category**. D=`drivetrain`, T=`turret`, W=`weapon`; “each S” applies individually to actual installed `sensor0`..`sensor315`. Resolve priorities to exact existing device names. Validate the sum on **each actual bus**, never one cross-bus fictitious100% pool. Forced-zero is exact. Ranges alone do not authorize allocating every maximum simultaneously. All proposed minimum sums are feasible on a100% shared bus; actual CPU-tier bus topology must still be checked.

For Stage2 delivery, provide declarative profile data and validation fixtures; do not install a live respawn allocator/population. Stage3 contract:

- Stable `personality_id`, immutable original BW source/hash, visible shared-library source/hash, flattened editable bundle/hash/version. The persistent original program is never randomized/replaced.
- Initial equipment IDs, CPU tier, installed sensor mounts and fixed device-to-bus mapping captured explicitly. Respawn preserves them; unsupported prerequisites use that same source's visible fallback branch, not an invisible replacement AI.
- For each actual device: min/max percent, forced-zero flag, priority; per-bus capacity comes from actual installed hardware. Validate conflicts, missing devices, feasibility and total≤100% before admission.
- Later allocator produces deterministic valid percentages from `allocation_seed` + respawn index, preserving forced-zero/min/max and topology. Invalid/infeasible profiles are rejected with a traceable reason, not silently repaired into another personality.
- Program randomness is separate: an editable base seed mixed with own legal startup tick/coordinates, or a fixed test seed, using visible BW code. Program prints the derived seed once. No missing external-parameter API is assumed. Stage3 records program seed/start tick, allocation seed, realized allocations, source/equipment hashes and fallback reason for replayable tests/debugging.
- Each run's runtime/variables/map/tracks begin fresh, so Hunter memory resets on autonomous respawn. Source/profile remain persistent. Stage3 owns autonomous admission/restart/cleanup and must respect the existing180-second program limit; Stage2 does not add unattended tanks or raise the lifetime.

## Test plan after review

Compile every flattened source with the real parser/const analysis and ordinary source bounds. Run through BWExecution/BWDevices and actual tank physics/projectile/hit paths; native API boundaries may be mocked, never replace the algorithms with Luau AI. Control own clocks, seeds and legal Scanner observations for reproducibility; include live server/scanner geometry integrations for occlusion/authority. Measure per-thread tick costs, sensor acquisition/cooldowns, command queues, bounded map/search memory and180-second lifecycle behavior. No special exemptions for these programs.

Each personality gets positive behavior, missing-hardware, stale/occluded target, bus-minimum/max-sum, wheel/track, diagnostics and deterministic replay tests, plus its specific tests above. Tower/Sniper share predictor-source parity tests and finite projectile travel versus future explicit hitscan fallback; Crazy must show enemy-independent fire and zero sensor use. Keep2–3 code improvement hints in the actual source after approval. Run existing Node/Luau/syntax/Rojo/diff checks and update the roadmap per personality. Native Studio acceptance remains distinct.

## Review requested

1. Approve/adjust G1 (own geometry), G2 (physical aim_at primitive), and G3 (own timing/heat metadata). No implementation has started.
2. Approve P01–P06 interpretations, particularly Crazy's native-heat “clip,” Sniper's lack of crouch, Tower's fixed-lens blind sectors and Hunter's bounded unknown map.
3. Approve/replace the nine proposed P07–P15 concepts and their hardware/fallback constraints.
4. After review, implement only approved personalities/capabilities; pause again for new commands, source-limit changes or material algorithm compromises. Stage3 is not authorized.


### Baseline verification for this review pass

`node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js 52` passes697 Stage1 API assertions; the same runner with17 passes381 existing function/const assertions across105 programs. `git diff --check` passes. These are baseline checks, not personality behavior tests. No program/runtime code changed, so no new Rojo/game build was necessary for this proposal-only checkpoint. Full personality verification begins only after approval.

## Approved decisions — 2026-11-19

User approved all P01–P15 and G1–G3. Implement APIs/tests first, then personalities in order. G1 is authoritative own geometry. G2 is mechanical aiming only, with actual bus/rates/stops/queues and unreachable feedback. G3 reports existing heat/burst/cooldown/timing only at existing fees. Crazy fires blind through native heat limits, resuming whenever possible. Survivor adjusts aggression using health and observed threats, attempts escape at critical health, never waits for regeneration, and fights if escape fails. Each source gets 2–3 contextual improvement hints. Prediction, mapping and planning remain visible BW. New capabilities still require another approval. Stage3 remains unauthorized.

## G4 — Historical256-statement proposal (superseded; NOT implemented)

**Historical status: superseded by the approved removal below. The256 proposal was not implemented.**

Measured with the real production BW parser after pruning unreferenced library functions:

| Program | Expanded source statements | Bytes | Lines | Result |
|---|---:|---:|---:|---|
| P01 Marauder | 83 | 3154 | 95 | Compiles |
| P02 Crazy | 52 | 2080 | 63 | Compiles |
| P03 Tower | 80 | 3531 | 89 | Compiles |
| P04 Sniper | 114 | 4698 | 127 | Compiles |
| P05 Cat and Mouse | 117 | 4627 | 134 | Compiles |
| P06 Hunter draft | 146 | 5798 | 161 | Rejected: Line143, Too many statements (maximum128) |

Counts exclude blank/comment lines and else labels, matching this subset of the parser's statement counting. P06 is explicitly a draft: target-directed route priority, blocked-route learning and interception refinement still need completion/testing. The current146 statements already include a bounded unknown25-cell map, legal obstacle observations, parent/queue BFS, physical navigation and visible gunnery. It must not be advertised as a completed Hunter. No live population references this draft; the exporter warns and excludes it. Tests explicitly assert that the unchanged compiler rejects it.

**Proposed capability:** raise the ordinary per-program source-statement ceiling from128 to256 **for all player BW code**. No new callable signature or privileged command. Keep16KB source,400 lines,512 compiled instructions,64-item containers,128 variables,50 call frames,180-second lifetime, queue/history bounds, CPU grants, operation accounting and all authorization unchanged. Update the parser diagnostic to derive its number from configuration and add exact boundary/regression tests if approved.

**CPU cost:** no new fee or free work. Every existing statement/expression/function/queue operation keeps its normal charge; source capacity does not increase execution throughput. Existing compiled-instruction and runtime budgets remain independent guards.

**Player benefits:** room for readable general algorithms combining bounded data structures, ordinary arithmetic, navigation and gunnery. This is not an AI-specific exception. Player-written sorting/search/state machines and reusable math helpers face the same limit.

**Why another reusable library is insufficient:** these helpers already are visible BW libraries and the builder includes only referenced functions. Their statements count after expansion, exactly as handwritten player code does. Hiding mapping/search in Luau or exempting library bodies would violate the approved intelligence/CPU boundaries. Further compression could obscure the educational code or drop required behavior; neither is proposed as a workaround.

**Historical decision request (resolved below):** approve G4's256-statement general ceiling, or retain128 and explicitly reduce Hunter's required algorithm scope. No limit has been changed, no runtime command beyond approved G1–G3 has been introduced, and P07–P15 remain TODO to preserve the requested implementation order. Stage3 remains untouched.

## G4/G5 final approval — 2026-11-19

G4 supersedes the256 proposal: remove statement/line ceilings; retain reasonable technical upload/compile resource safeguards and existing recursion50/CPU/runtime/memory/nesting restrictions. G5 extends existing Scanner only, additive terrain record, unchanged cost/sensors/buses/detections/authority. No scan_ground callable. Include bounded footprint lanes, elevations relative to chassis base, signed local slope degrees and rise per horizontal stud, separate discontinuities/unknowns, no climbing or automatic navigation logic. Implement/test first, then finish P06–P15 in order.

## Final implementation decisions/evidence

- G4 removes MaxInstructions/MaxLines altogether. Technical upload/compiler-allocation/work/time bounds (256KiB/65536 instructions/250000 analysis updates/1s) replace the old restrictive technical sizes. No source-size CPU fee or balancing mechanism. Existing50-frame recursion and execution/memory/nesting safeguards remain. Large programs >128,>256,>1000 statements, nested calls/recursion, overflow cleanup and editor history pass18 focused checks.
- Revised G5 adds only `.terrain` to existing Scanner, not scan_ground. Hardware capability is explicit; CPU fees/rates/acquisition/FOV/range/authorization and existing detections are preserved. Bounded physical probes/LOS provide contact-footprint samples, elevations, signed local rise-per-horizontal-stud and degree slopes, discontinuities/edge brackets/nullable depth. No engine avoidance or horsepower rule. Exact contract and173 focused tests are in SCANNER_TERRAIN.md.
- All P01–P15 original/editable BW sources, profiles, visible shared helpers, private phase diagnostics and reproducible manifest are complete. Hunter owns map/BFS/interception; Tower/Sniper share visible prediction; Duelist deliberately ignores terrain. Survivor never assumes healing. Ambusher briefly reobserves legal traffic before sweeping; no hidden prefire. Crazy native heat-limited blind firing remains scanner-free. See BW_PERSONALITIES.md for per-program behavior/equipment/limits/native tests.
- Full verification:106 Node tests, all57 Luau groups,131-source syntax; final personality group143516 checks; main binary/XML and plugin Rojo builds/diff check pass. No Studio validation, no Stage3, no commits/pushes; no new approval blocker remains.

Final evidence adds10845 isolated transient-scanner failure assertions across all15 sources and exact visibility/range checks. Terrain suite173; compiler safety18; all57 groups/full Node106/syntax131/builds pass. No new proposals remain awaiting approval.

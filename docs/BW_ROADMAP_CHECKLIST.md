# BW expansion roadmap

Current scope: **Stage 1 COMPLETE; Stage 2 COMPLETE (P01–P15 and G1–G5, 2026-11-19).** Stage 2.5 proving ground authorized; Only the explicit fifteen-tank Auto/Manual follow-up is authorized; other Stage3 features remain out of scope. No commits/pushes.

## Stage 1 — Core APIs

| # | Task | Status | Evidence / decision |
|---|---|---|---|
| 1.1 | Inspect syntax, value types, production/legacy runtime, scheduler, components, buses, physics, weapons/scanners and authority | DONE | BWExecution is the production cooperative CPU; BWRuntime is a legacy physical executor; BWValue already supports dictionaries, arrays, null and immutability. Existing get_facing_direction/get_clock reused. |
| 1.2 | Specify exact public signatures, schema, units, costs and truthful gaps | DONE | docs/BW_CORE_API_SPEC.md; finalize costs in actual ticks/cycles, fixed sensor mounts and no-ammo/no-hitscan limitations. |
| 1.3 | Implement read-only own-state snapshot/individual operations using existing BW values | DONE | No world/opponent input arguments; whitelist only own state and hardware. |
| 1.4 | Wire fresh production entity/hardware/weapon context and coherent simulation timestamp | DONE | Read after CPU charge/resumption; no once-per-tick snapshot cache. |
| 1.5 | Integrate signatures, CPU charge/reservation, compatibility entry and in-game handbook | DONE | One cycle = one tier's per-thread tick grant. Readiness one cycle, snapshot two; field access remains normal expression cost. |
| 1.6 | Test freshness, types/immutability, buses/equipment, readiness, scanners/drivetrains, CPU budget, authority and backward compatibility | DONE | New BWCoreAPI group52 passes697 assertions; Royale production server group43 passes5065. Covers real getter/output privacy and denied non-occupant BW, same-tick freshness, immutable values, actual BW motion/turrets, heat/windup/damage/configure, all-tier cost/reservation, print/short circuit/legacy, real spec syntax. |
| 1.7 | Run relevant/full Node+Luau, syntax, Rojo, whitespace checks; update handoff | DONE | 101 Node tests, all53 Luau groups, syntax130, main rbxl/rbxlx + plugin builds, diff check pass; command log below. Native Studio not run. |
| 1.8 | Stage 1 completion audit; stop before Stage 2 | DONE | Nine specified own-read APIs, complete contract/handbook, freshness/budget/authority coverage. No new gameplay/equipment mechanics or personality/living-arena implementation. Stop here. |

## Stage 2 — Fifteen personality programs (complete; stop before Stage3)

| # | Task | Status | Evidence / decision |
|---|---|---|---|
| 2.1 | Re-audit actual Stage1 API, grammar/limits, scanner results, equipment, CPU and physics | DONE | Read current modules/docs; Scanner already returns legal timestamped hit points/stable observed tank identity. Eight fixed mounts/default cone gaps, no clip/crouch/import/native math remain important. |
| 2.2 | Present a separate proposal for all15 personalities and nine new concepts | DONE | docs/BW_LANGUAGE_ENHANCEMENT_PROPOSALS.md P01–P15 includes behavior/algorithm, real primitives, gaps, G1–G3 dependencies, bus/hardware/fallback constraints, tests and planned improvement hints. |
| 2.3 | User review of every personality and proposed API addition | DONE | Approved P01–P15 and G1–G3 on 2026-11-19. Original gate: “Pause for user review … before implementing that personality.” All checkpoints reviewed; new missing capabilities still require approval. |
| 2.4 | Implement only approved general-purpose additions, with spec/fees/authority tests | DONE | G1 additive own barrel geometry; G2 generic aim_at; G3 additive own timing/heat metadata. Implemented G1/G2/G3; core API group52 passes817 assertions including bus-limited simultaneous aiming and mountLimited feedback. |
| 2.5 | Write15 original player-editable BW programs and only visible shared BW libraries | DONE | All15 sources, ordinary BW helpers and reproducible expanded outputs; no privileged intelligence. |
| 2.6 | Deliver declarative profiles, seed/source trace contract and per-personality diagnostics | DONE | profiles.json min/max/forced-zero/priorities and initial hardware; private phase logs; manifest original/library/generated hashes. No Stage3 allocator. |
| 2.7 | Run reproducible actual-runtime/physics, CPU, fallback and integration tests | DONE | All57 Luau groups/106 Node tests/131-source syntax pass. Final targeted personality group53:143,516 assertions, including frame checks; API817, large-source18, terrain173, scanner-failure10845. See final evidence below. |
| 2.8 | Finalize descriptions/limitations, record all tests, STOP before Stage3 | DONE | BW_PERSONALITIES.md and SCANNER_TERRAIN.md; native Studio steps explicitly unverified. No Stage3 integration, commit or push. |

### Per-personality review checkpoints

All P01–P15 checkpoints and G1–G3 were approved together; subsequent G4 removal and revised G5 scanner/elevation additions were explicitly approved. No outstanding API approval.

| ID | Personality | Source status | Review | Proposed capability dependencies |
|---|---|---|---|---|
| P01 | Marauder | DONE | Approved | G1/G2; no unique commands |
| P02 | Crazy | DONE | Approved | G3; no scanner/target/alignment checks; approved native heat-limit interpretation |
| P03 | Tower | DONE | Approved | G1/G2/G3; player-written shared predictor |
| P04 | Sniper | DONE | Approved | G1/G2/G3; same predictor; no invented crouch |
| P05 | Cat and Mouse | DONE | Approved | G1/G2; cover algorithm stays in BW |
| P06 | Hunter | DONE | Approved | G1/G2/G3; unknown bounded map/search in BW; G4 resolves source capacity; BW-only search |
| P07 | Sentinel | DONE | Approved | G1/G2; no unique commands |
| P08 | Skirmisher | DONE | Approved | G1/G2; no unique commands |
| P09 | Wallflower | DONE | Approved | G1/G2; no unique commands |
| P10 | Prospector | DONE | Approved | G1/G2; no unique commands |
| P11 | Gatekeeper | DONE | Approved | G1/G2; G3 if predictor used |
| P12 | Duelist | DONE | Approved | G1/G2; no unique commands |
| P13 | Survivor | DONE | Approved | G1/G2; no unique commands |
| P14 | Ambusher | DONE | Approved | G1/G2; G3 if predictor used |
| P15 | Trailblazer | DONE | Approved | G1/G2; no unique commands |

## Stage 3 — Living Playground (not authorized now)

| # | Task | Status | Evidence / decision |
|---|---|---|---|
| 3.1 | Specify admission/occupancy/AI lifecycle and resource limits | TODO | Public tanks and existing authority remain unchanged in Stage 1. |
| 3.2 | Integrate living population using existing arena lifecycle | TODO | Separately authorized milestone. |
| 3.3 | Validate multiplayer, long-running behavior and cleanup in Studio | TODO | No Stage 3 implementation in this task. |

## Decisions and unresolved questions

- Existing dictionaries, immutable result records, zero-based arrays and field access suffice: no language extension. Registered static shapes in the existing const/alias analyzer allow nested scalar/dynamic-array fields in ordinary functions without relaxing mutable/const protection. A conformance test checks the runtime schema against every static snapshot field. scanner_count/bus_count follow the existing Scanner count pattern so while/index loops can safely traverse empty/nonempty arrays.
- get_tank_direction aliases the existing chassis-heading read without changing get_facing_direction or its cost. Turret heading uses actual barrel projection; mount-relative pitch is exposed separately.
- CPU accounting distinguishes ticks from 10 Hz grant cycles. New cycle-cost reads scale by tier and must be included in conservative instruction reservations; printing must not waive them.
- All current weapons fire finite-speed projectiles and have unlimited ammunition. No hitscan implementation or finite ammo system will be invented. Explicit projectile model/nullable speed and ammo mode document those facts.
- Sensors are chassis-mounted at discrete 45° positions with 15° default cones. Narrow cones leave coverage gaps. Metadata will not imply that Scanner(36) or turret rotation sweeps a freely steerable scanner.
- Wheel count is cosmetic, absent from authoritative hardware. Return null rather than infer physics capabilities from art. Turning radius is derived only where the actual wheelbase/steer/yaw model permits.
- Hardware reconfiguration while a program runs is currently rejected. Freshness tests must distinguish genuine supported reconfiguration/restart from test-controlled changes to the read context.
- Stage1/Stage2 have no architectural blocker. P01–P15/G1–G5 are approved and implemented. G4 removes statement/line ceilings rather than replacing128 with256. Crazy uses approved native sustained heat-limited fire. No native math or privileged AI shortcut is introduced. Stage3 hardware/population policy remains unresolved and out of scope.

## Verification log

Implemented BWSelfState, tier-relative Hardware.cost and charge/reservation integration, own-entity server getter, existing serial facade delegation and handbook entries. Production BW regression group5 passes (6094 language/runtime +104 best-effort +40 local battle/IDE +61 damage +202 scanner assertions); handbook group8 passes545 assertions. Exact commands: `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js 5` and same with `8`; syntax130 sources passes. Group52 `... 52` now passes697 after static-shape/const-consumption coverage; production server `... 43` passes5065; Initial full run passes101 Node and all53 Luau groups (log /tmp/bw-core-api-checks.log), plus main rbxl/rbxlx and plugin builds. Final full rerun also passes101 Node tests/all53 Luau groups, covering static shape integration (log /tmp/bw-core-api-final.log). Final focused group52 passes697 assertions after constant-map-field/scalar-consumption and inexpensive-call accounting checks; existing function/const suite17 passes381 assertions across105 programs. Existing uncommitted Playground chat changes and user .gitignore changes must be preserved.


### Final command results

| Command | Result |
|---|---|
| `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js` | PASS: 101 Node tests and all53 Luau groups; logs `/tmp/bw-core-api-checks.log`, `/tmp/bw-core-api-final.log` |
| Same runner with `52` | PASS: 697 new own-state API assertions (latest focused check) |
| Same runner with `17` | PASS: existing functions/const suite381 assertions/105 programs after final shape lookup integration |
| Same runner with `43` / `47` | PASS: production Playground server5065 / headless5064, including authorized own getter, global ticks and private outputs; both included in full run |
| Same runner with `--syntax` | PASS: 130 source files plus plugin parsing |
| `rojo build default.project.json -o /tmp/battleworks-bw-core-api.rbxl` | PASS |
| `rojo build default.project.json -o /tmp/battleworks-bw-core-api.rbxlx` | PASS |
| `rojo build world-builder.project.json -o /tmp/battleworks-bw-core-api-world-builder.rbxm` | PASS |
| `git diff --check` | PASS |
| Native Roblox Studio multiplayer/equipment/UI acceptance | NOT RUN; exact procedure in BW_CORE_API_SPEC.md |

No Stage 1 blockers remain. Hitscan, finite ammo, authoritative wheel counts and moving tracked turning radii are documented unsupported gaps, not invented capabilities. Existing shared-reference restrictions for const function parameters remain; programs can use function-local snapshots or scalar fields. Stage1 final results remain valid. Current Stage2 authorization/review checkpoint is above; Stage3 questions remain for separately authorized work. All earlier chat/user edits preserved; no commits/pushes and no user place overwritten.


## Stage 2 pre-code review pass

Only planning/tracking/handoff documents changed in this pass. The actual-code audit found: own muzzle position/preparation/heat limits are not exposed; BW single-axis turret queues cannot supply simultaneous World aim; mathematical/path algorithms can remain visible BW helpers; Hunter must still fit128 statements and ordinary bounds. Full proposals and per-personality evidence/questions are in BW_LANGUAGE_ENHANCEMENT_PROPOSALS.md. No new commands, personality sources, profile allocator or Playground behavior implemented before approval. No personality tests/build verification is claimed at this gate.

Baseline recheck for this Stage2 review: runner group52 passes697, group17 passes381/105 programs, git diff --check passes. These do not constitute personality tests. Proposal-only changes require no game build; no Stage2 code/build result is claimed.

2026-11-19: User approved all personality/API proposals, native Crazy heat-limit semantics, and Survivor threat/health aggression without regeneration. APIs first; sources follow in documented order. No Stage3 or commits.

P01–P05: visible sources, helpers, declarative profiles and actual VM/native movement/heat/windup harness added. Group53 passes40,254 assertions across both drivetrains; Crazy blind overheat/resume, Tower stationary fire and Marauder20-stud displacement verified. More scenario/profile tests remain. Sources include contextual improvement hints. G1 muzzle metadata follows existing barrel obstruction sweep to true unobstructed tip.

### Historical G4 review checkpoint (superseded by approval below)

G1/G3 are additive immutable own metadata at unchanged fees. G2 uses existing mount solver, FIFO, bus limits and physical simulation; mount-limited completion is actionable. New source calls through the legacy facade delegate to the production CPU; the device physical executor does not recursively delegate. API group52 passes785 assertions.

P01–P05 are source-complete with baseline runtime tests, not a claim of complete Stage2 acceptance or native Studio validation. P06 draft has146 statements/5798 bytes/161 lines and production compilation fails at line143 for the128-statement limit. Source exporter explicitly warns/skips it. G4 in BW_LANGUAGE_ENHANCEMENT_PROPOSALS.md requests a general256-statement budget, with all other CPU/compiled/source/runtime limits unchanged. Do not change BWConfig or proceed to P07 until user review. Hunter's final interception/replanning refinement and advanced scenario tests remain unfinished.

Profile/seed/source contract and native manual steps are in BW_PERSONALITIES.md. No allocator, autonomous respawn/population, equipment mutation or Stage3 behavior was added.

### Verification at G4 pause (2026-11-19)

- `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js > /tmp/bw-stage2-checks.log 2>&1` — PASS after approved escalation for sandbox `spawnSync EPERM`:105 Node tests,130 Luau source syntax checks, all54 Luau groups including new personality group53. Existing multiplayer/authority/Classic/editor/3D aiming/chat regression groups pass. Full run API782, personality49,653 assertions.
- Added three focused own-heat/burst/interval/lockout freshness assertions afterward; targeted group52 — PASS785 assertions. No production code changed after successful full run.
- New Node personality tests cover expanded budgets, deterministic hashes, real bus-topology minimum feasibility, shared predictor parity, Crazy's missing sensor/target dependency and explicit Hunter draft rejection.
- `node tools/build-bw-personalities.js /tmp/bw-stage2-programs` — PASS for five sources; explicit warning skips blocked P06. No15-program completion claim.
- `rojo build default.project.json -o /tmp/bw-stage2.rbxl`, same project to `/tmp/bw-stage2.rbxlx`, and `rojo build world-builder.project.json -o /tmp/bw-stage2-plugin.rbxm` — PASS, repeated after final production edits.
- `git diff --check` — PASS.
- Native Roblox Studio not run. Manual steps and remaining personality-specific scenario limitations are in BW_PERSONALITIES.md. G4 is awaiting user approval; no Stage3 implementation, no commits/pushes.

## G4/G5 continuation authorized — 2026-11-19

G4 APPROVED as removal of arbitrary statement ceiling, NOT256. Preserve50-frame recursion, CPU/runtime/memory/nesting guards; audit source/upload/editor/persistence/compiler enforcement. Technical256KiB upload and65536 bytecode allocation guards,1s compilation budget/250000 analysis updates proposed implementation as resource safeguards, not gameplay fees. G5 APPROVED as additive terrain/elevation observations in existing Scanner, no scan_ground command or extra CPU charge, no movement control. Both IN PROGRESS; finish/test before P06–P15. Duelist intentionally ignores terrain. Stage3 unauthorized.

G4 focused validation DONE: group54 accepts129/257/1001 statements and1100 lines, nested function calls/recursion, real CPU fees,50-frame overflow cleanup, retained upload/nesting guards (14 assertions). G5 focused group55 passes155 terrain/elevation assertions. Existing scan API/cost/detections preserved; sensor.standard explicitly declares ground observation support. P06 now implemented against G4 with BW-only map/BFS/velocity/nav and optional terrain sampling. P07–P11 sources/profiles added in order with contextual hints; runtime validation in progress.

P12 Duelist added: sticky visible identity/orbiting pursuit deliberately ignores terrain. P13 Survivor added: observed threat count/own damage/critical health, bounded escape attempts and cornered fighting, no regeneration wait. P14 Ambusher added: bounded aged spatial traffic clusters/visible-contact-only fire. P15 Trailblazer added: measured movement pulses/settling and G5 missing-terrain vs supported-blockage feedback. All are editable BW with contextual hints/profiles; runtime/scenario validation in progress. No Stage3 integration.

## Final Stage2 evidence — 2026-11-19

| Task | Status | Implementation/evidence |
|---|---|---|
| G4 all-enforcement audit | DONE | BWConfig/BWParser statements and lines removed, bytecode bound moved to65536 technical allocation guard;256KiB upload,1s deadline,250000 analysis-update budget. No editor truncation/persistent BW store ceiling found; IDE/history retain source in memory. Server uses same parser after ownership/rate checks. Docs/handbook/tests updated. |
| G4 preserved safety | DONE | Existing50-frame recursion/aggregate frame cleanup, CPU costs/grants/hard512 ops per cycle,180s lifetime, arrays64/variables128, expression/block nesting, queue/history/output bounds retained. Group54:18 checks,129/257/1001 statements,1100 lines, nested calls/recursion, overflow, zero-fee source size, zero-cost yielding, editor undo and technical bounds. Nested function definitions remain unsupported; nested calls are tested. |
| G5 additive Scanner terrain | DONE | New ScannerTerrain collector, same command/CPU/device queue, old fields/detections unchanged. Explicit equipped capability and own metadata; bounded footprint lanes, raycast/LOS, normal-derived slope, visible steps/edge brackets and null unknowns. Up to64 terrain rays within existing512 total. |
| G5 geometry/authority tests | DONE | Group55:173 assertions covering flat/up/down slopes, small/sharp steps, hidden/visible depth, gaps/cliffs, elevated/narrow bridges, water, fields/units, hardware/bus/cone/range/cost/memory/query guards, BW reaction, real bridge falls. Existing production server/scanner/combat tests pass. Lifecycle fixture gained missing nil Raycast stub; no production safety weakening. |
| P01–P15 validation | DONE | All15 compile and independently execute on both actual drivetrain/weapon assemblies under normal CPU. Disabled drive/scanner fallback, actual profile minima, Crazy blind native heat recovery/determinism, moving-target Tower lead, Sentinel sweep, Skirmisher approach, Wallflower corner, Prospector memory, Gatekeeper physical push return, Duelist identity, Survivor critical blocked escape, Ambusher no hidden prefire, Trailblazer edge response, Hunter BW map/reset/actual BFS. Final group53:143516 assertions, mostly per-frame runtime-error checks. |
| Final docs/handoff | DONE | BW_PERSONALITIES.md (all descriptions/limits/profile/seed/hash contract/native steps), SCANNER_TERRAIN.md (exact schema/units/query limits/unknowns), core/runtime/language/README/handbook updated. |

Commands/results:

- `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js > /tmp/bw-g45-verified.log 2>&1` — PASS:106 Node tests,131 Luau source syntax compilations, all57 Luau groups. Approved escalation needed for existing subprocess tests. First attempt exposed a lifecycle mock without Raycast; fixture corrected and full rerun passed.
- Final targeted group53 after final profile-priority/minimum checks — PASS143516; Node personality tests — PASS5. The final full run includes these checks and all57 groups; source-program transient scanner failures are isolated in group56 (10845 checks) to respect the test runner's fixed heap. No production memory limit was raised.
- `node tools/build-bw-personalities.js /tmp/bw-g45-programs` — PASS, all15 complete sources + hash/seed/profile manifest.
- `rojo build default.project.json -o /tmp/bw-g45.rbxl` and `.rbxlx`, `rojo build world-builder.project.json -o /tmp/bw-g45-plugin.rbxm` — PASS.
- `git diff --check` — PASS.
- Native Roblox Studio not performed. Follow both acceptance guides; imported/native raycast fidelity, real-world avoidance/lead quality, platform controls, two-player privacy and query frame cost remain native validation. Current cosmetic river water is unqueryable and cannot be fabricated as detected water.

Stage2 complete; STOP before Stage3. No new unapproved command, map/route/prediction privilege, population allocator, autoplay host, equipment-on-respawn change, commit or push.

Final verification refresh: `/tmp/bw-g45-verified.log` exits0 with106 Node tests/all57 Luau groups/131-source syntax. Group53:143516; group54:18; group55:173; group56:10845. Added strict same-surface LOS and range-sphere clipping tests; no hidden surface data accepted through thin occluders. Transient scannerBusy guards added in player BW (Hunter/Prospector/Ambusher); every personality's failure scenario passes. The extra scenarios exceeded Luau Web's fixed WASM heap when combined with existing retained fixtures; using a fresh existing-harness group fixes the test environment without deleting assertions or changing production safety. Final main binary/XML/plugin Rojo builds and diff check pass. No code remains pending.

## Stage 2.5 — Playground proving ground

| # | Task | Status | Evidence |
|---|---|---|---|
| 2.5.1 | Audit Playground/World Builder/physics/scanner/targets | DONE | Shared PlaygroundTerrain regions, Environment/SurfacePhysics, VehicleContacts boxes, native PlaygroundBuilder and PracticeTargets existing five-second lifecycle reused. |
| 2.5.2 | Deterministic expanded default Playground/open combat field | DONE |800x640 default only; old ravine/bridge/spawns preserved, open300x280 field and connecting banks. Authored worlds/Classic not replaced. |
| 2.5.3 | Four-room open-roof barracks/window/door LOS | DONE | Shared static box segments feed native parts + existing contact solver;24-stud opposing entrances/32-stud hall/18-stud room doors. |
| 2.5.4 | Navigable forest | DONE | Existing tree renderer/contact path, deterministic box trunks/nonquery foliage and clear lanes. |
| 2.5.5 | Central terrain properties and drivetrain effects | DONE | Reuse SurfacePhysics footprint blending; TerrainMaterials profiles wetness/depth/consistency, positive speed/grip, tracked .90 exactly once in opt-in proving-ground physics; Classic/authored handling preserved. |
| 2.5.6 | Existing Scanner material metadata | DONE | Visible surface classification/wetness; depth/consistency null unless explicitly observable measurement, no hidden region lookup/extra fee/automatic navigation. |
| 2.5.7 | Existing practice target hit/5s respawn | DONE | Ten placements use PracticeTargets; original pose restored, shared timer/occupancy retry, no population slots/debris. |
| 2.5.8 | Automated regression/build/docs/native steps | DONE | Full106 Node tests,133-source syntax and59 Luau groups pass; geometry839/material54 checks. Main binary/XML/plugin Rojo builds and diff check pass. Native Studio remains pending; see PLAYGROUND_PROVING_GROUND.md. |

### Stage2.5 final verification — 2026-11-19

- `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js > /tmp/bw-proving-ground-full.log 2>&1` — PASS, exit0:106 Node tests,133 Luau source syntax compilations, all59 existing-harness Luau groups. ProvingGround839; TerrainMaterials54; own-state API821; existing Royale server5236, Playground174, 3D aiming321, mouse modes33, chat51, personalities143516, scanner173 and scanner-failure10845 assertions pass. Production solver/raycast fixtures are automated evidence, not native Studio validation.
- Initial full run exhausted Luau Web's fixed heap in the existing large native building fixture. That group now compiles only its actual transitive production dependencies; assertions, geometry, full syntax coverage and production memory limits are unchanged. Full rerun passes.
- `node --check scripts/check.mjs` — PASS.
- `/home/studio/.rokit/bin/rojo build default.project.json -o /tmp/bw-proving-ground.rbxl`, same project to `.rbxlx`, and `rojo build world-builder.project.json -o /tmp/bw-proving-ground-plugin.rbxm` — PASS.
- `git diff --check` — PASS.
- TerrainMaterials/PlaygroundProvingLayout, existing native builder/contacts/surface-drive/scanner/target modules, tests and docs implement the complete slice. Classic/custom worlds, six public tanks, priorStage1/2/chat/user work retained. No authored-world migration/storage change.
- Limitations: native Studio multiplayer/visual/camera/collision/query fidelity and actual15/50/100-tank performance remain unverified. Grid capacity checks are not benchmarks. Standard sensors cannot measure buried depth/firmness, so those fields remain null; existing nonqueryable cosmetic river cannot report water. No deformable terrain/horsepower climbing model. Depth/consistency are configurable material resistance properties, not new support geometry.
- Follow docs/PLAYGROUND_PROVING_GROUND.md native acceptance steps. Stage2.5 implementation/automated verification DONE; native acceptance pending. Stage3 remains TODO/unauthorized. No commit or push.

## Fifteen-tank autonomous Playground follow-up

User explicitly authorized15 public personalities, random existing builds, equal component bus shares, all single-thread computers, Manual on entry and Auto on exit/replacement. This supersedes the six-tank baseline and default personality constraint profiles for this setup only; it does not authorize onboarding/redemption/garage or a general population framework.

| Task | Status | Evidence |
|---|---|---|
| Audit current pool/BW/occupancy/snapshot/HUD | DONE | Reused BattleRoyale, BWController, existing compiler/VM, safe spawn checks and RoyaleClient navigation. |
| Package15 ordinary BW personalities | DONE | Generated PlaygroundPrograms from editable source/libraries with hash parity test; Crazy single-thread BW queue variant. No new intelligence builtins. |
| Random hardware/safe positions, equal Bunny bus | DONE | Existing four weapon/drivetrain combinations, stable per-slot random build, validated100/device_count allocations on bus1; bounded safe random spawn candidates. |
| Authoritative Auto/Manual/lifecycle and HUD | DONE | New control epochs and cleared commands; same physics/combat, Auto on vacancy/replenishment/disconnect,180s guard retained; bottom switch uses existing remote. |
| Production integration/regression/build/native handoff | DONE | Full108 Node tests/135-source syntax/all60 Luau groups pass; production15-tank2444, final client100 and legacy5237 checks. Main binary/XML/plugin Rojo and diff checks pass. Native testing remains required. |

Follow-up final verification (2026-11-19): `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js > /tmp/bw-playground-auto-full.log 2>&1` PASS exit0:108 Node tests,135 Luau syntax checks, all60 isolated groups. Existing legacy six-tank nonautonomous fixture explicitly selects that configuration; no assertions removed. Separate default15 production boot verifies all assignments, real Bunny configurations/equal shares, land/nonoverlap, authorized switching/stale leases, vacancy/disconnect, destruction/replacement and180s stop/fresh restart (2444 assertions). Full run client99 plus Studio-client100; after final duplicate-click debounce, focused published-client100 and Studio-client101 checks pass. Node source generation parity/Crazy variant tests pass. `node --check` for generator/runner, refreshed `--syntax`, main `.rbxl`/`.rbxlx` and plugin `.rbxm` Rojo builds to `/tmp/bw-playground-auto*`, `git diff --check` PASS. Native multiplayer, UI layout/input devices, sustained15-tank CPU/query performance and several Auto runtime cycles still require Studio; see proving-ground follow-up. No onboarding, redemption, garage persistence, commit or push.

### 2026-11-20 entry HP and movement investigation

- DONE: server entry restores installed chassis max HP and clears injury effects only after successful occupancy/character transition. No location/generation/weapon cooldown reset; no repair on rejected entry or Auto/Manual switching.
- DONE: real simulation with one tank/dry grass reproduces current bus-only slowdown: Boomer5.467/Rattler5.207 studs/sec at9.09% allocation. Terrain test58 assertions. Not a native population-performance benchmark.
- DONE: production15-pool entry/authority/respawn test2464 assertions and legacy public-pool5237 pass. Syntax and Classic/headless regression results recorded in current handoff. Spawn clearance now explicitly enforces existing14-stud public center spacing before random placement acceptance.
- PENDING USER PREFERENCE: proposed four equal system shares instead of eleven equal device shares. Preserve requested equal-per-device/single-thread policy until answered. No speed/bus/CPU tuning silently applied.

### 2026-11-20 drivetrain curve / editor counter fixes

User approved drivetrain5%=15 pre-terrain forward studs/sec, same maximum. Four-system bus proposal superseded: equal per-device allocation and Bunny CPU retained. Central BWChassis.devicePerformance feeds Controller/Devices/SelfState; other curves unchanged,0% powerless, below5% linear, above5% smooth monotonic capped interpolation. Focused actual material/curve94 checks and own API821 pass. Existing literal old-curve assertions now assert the new device-specific contract using actual hardware, while old generic curve tests remain.

Editor root cause: BWIDE.current read state.bwLine/bwIndex/bwCount from the tank VM, while the TextBox retained a separate draft. It was not a cursor offset calculation. Header now follows actual source/cursor and debounced compiler map; callbacks revision-fenced, switches clear runtime association. New BWEditorStatus group covers10-line draft vs140/93/145 VM, cursor/edit/replace/switch/comment/invalid source/out-of-order callbacks/cleanup. Native Studio caret/UI validation pending. Shared scheduler investigation confirms device step runs every physics tick outside10Hz CPU grant block; new continuous-drive test covers no command pulsing during CPU waits. No CPU-limit boost or unverified scheduler rewrite.

Final combined validation: `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js > /tmp/bw-drive-curve-full.log 2>&1` PASS exit0:108 Node tests,135 Luau source syntax checks, all61 isolated groups. Includes drivetrain/material94, own-state821, all personality/multiplayer/BW/editor regressions and new editor status9 assertions; continuous-drive CPU-wait checks pass in BWExecution. Focused final client44 passes100 after last diagnostics fence; refreshed --syntax and git diff --check PASS. No place compilation (Rojo sync workflow), commit or push. Native editor caret/clipboard and live burstiness/performance remain unverified. Asked whether burstiness affects Manual as well as Auto; answer pending. Do not automatically alter scheduler/CPU allowances based on observed personality stop/wait behavior.

### Execution-line follow-up (2026-11-20)

User reports line number no longer increments. Previous fix intentionally made the header cursor-only; execution progress was visible only in Hardware diagnostics. Added separate ExecutionPosition row under cursor status, showing live VM line/instruction for exact submitted source/run/generation/lease match. Other/expanded personality programs are explicitly labeled different rather than mapped to the draft. No scheduler/gameplay change. Tests cover line2→7 while cursor1, generation/lease invalidation and immediate tank-switch clearing. Group60 now13 assertions; existing BW/IDE/scanner group5, client44 (100),135-source syntax and diff check pass. Native caret/execution row display acceptance pending. No rebuild, commit or push.

### Live editor / exact-source execution / wheeled steering follow-up (2026-11-20)

User observed `forward` L20 / `turn_right` L21 while displaying the10-line independent-device draft, and confirmed an actual chassis turn. Audit found two production bugs: Run silently did nothing while a built-in personality was active, and a completed player program marked Auto was subsequently replaced by the personality retry loop under the same request identity. Fixed with explicit autonomyActive lifecycle, Player/Personality metadata and monotonic invocation serial. Player programs no longer restart personalities on completion/failure/Stop; they return Manual. Explicit Auto, exit/disconnect/replacement retain built-in behavior. Editor Run can replace a built-in personality with the displayed source; ordinary player edit locks remain.

Private output stays selected-tank/occupant/lease scoped. Histories now reset for invocation serial, reject delayed older runs and identify tank/program/run. Control-epoch changes clear per-tank request fences, including equal epoch numbers on different tanks, while preserving drafts. Isolated two-tank production test executes the exact posted default program, waits through completion, asserts unchanged VM/serial and no right-turn logs, then checks Stop persistence. Existing fifteen-tank startup/lifecycle tests retained.

User requested draggable live window and running-line highlight: BWEditorWindow mouse/touch title-bar dragging clamps reachable safe-inset title area; close hides without stopping, Run releases text focus/handbook but retains code window. Highlight is a noninteractive native TextBox backdrop only for matching source/run/generation/lease. Cursor stays independent. Existing close-on-Run assertions updated to the explicitly requested keep-open behavior; focus/command assertions retained. Native visual alignment/device behavior still pending.

User approved wheeled BW steering and CONST command alias convenience. Shared player-visible turn_to now uses own heading feedback/forward/steer/center for wheels, physical turn for tracks; Crazy Bunny branches correctly and queues a travel leg after tracked turns. No engine turn semantics changed, no privileged planner. Compile-time top-level built-in aliases preserve signatures/validation/results/fees/source line and immutable declaration protections. No runtime function values or conditional alias reassignment. Parser/CPU/recursion/memory/upload guards retained. Generated personality sources refreshed.

Focused evidence: personality143520 checks including real Bunny wheeled/tracked heading completion and steering-vs-turn command distinction; aliases17; window/status25; exact-source two-tank production916; published client100. Large native/personality fixtures use their actual transitive production module graphs to fit fixed Luau Web heap; longer editor lifecycle isolated in its own two-tank production group. No assertion/geometry/production limit reduced. Final full result follows.

Combined final verification — `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js > /tmp/bw-steer-alias-full.log 2>&1` PASS exit0:108 Node tests,136 Luau source syntax checks, all63 isolated groups. Actual personality runtime143516 plus drivetrain helper4 checks=143520; aliases17; live editor/status/drag/highlight/lease25; exact-source lifecycle916. Existing Classic/multiplayer/3D aiming/terrain/chat/BW regressions pass. Refreshed final --syntax/group60 and Node personality source-parity tests pass after final source-package/version refresh. git diff --check PASS. Old full attempt hit fixed WASM heap in personality fixture; production dependency isolation fixes the harness without deleting assertions/raising production limits. No Rojo build per sync workflow; native mouse/touch safe-inset dragging, highlight alignment, input focus and actual multiplayer gameplay/performance remain pending. No commit/push.

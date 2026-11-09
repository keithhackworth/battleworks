# BW runtime implementation checklist

Source of truth for this change. Checked means verified, not merely written. Native Roblox Studio checks remain separate. No automatic commit/push.

## Phase 1 — inspection and architecture
- [x] Inspect existing grammar, AST, expressions, command dispatch and runtime (`src/shared/BW{Lexer,Parser,Expression,Commands,Runtime}.luau`). v0.2 variables/arrays/if/switch exist; threads/dictionaries/CPU throttling do not.
- [x] Inspect authoritative loop, ownership, scanners and IDE (`src/server/{init.server,BWController,DirectionalScanner,ManualScanner}.luau`, `src/client/BWIDE.luau`). Existing fixed 60 Hz simulation owns time.
- [x] Inspect test runner and documentation (`scripts/check.mjs`, `README.md`, `CODEX_HANDOFF.md`).
- [x] Inspect exact weapon/drive scaling integration points before edits.
Acceptance: record reuse boundaries and decisions below; no replacement physics engine.

## Phase 2 — simulation clock, CPU scheduling
- [x] Central chassis tiers and instruction cost specification (`BWChassis`, `BWExecution`).
- [x] Fixed-cycle deterministic tick budgets, bounded credit, hard per-cycle safety, atomic resumable evaluation.
- [x] Verify varying frame subdivisions, carryover and zero-cost safety with automated tests.
Acceptance: same simulated timeline produces same outputs; device time is independent of instruction ticks.

## Phase 3 — threads, shared state, synchronization
- [x] Parse/validate `with thread(n)` and legacy thread 1 (`BWParser`).
- [x] Independent deterministic streams and atomic shared writes (`BWExecution`).
- [x] Reference-preserving clock/change/truthy waits with documented versions.
- [x] Verify Bunny/Dual/Quad, waits, conflicts, completion, cancellation and variable cleanup.
Acceptance: waiting/finished thread never prevents another from executing; no task-order dependence.

## Phase 4 — buses and devices
- [x] Data-driven device assignments/allocation validation and performance curve (`BWChassis`).
- [x] Integrate drivetrain/turret/scanner/weapon performance with existing simulation only.
- [x] Verify allocations, independent operation, cross-bus commands and unchanged full-performance physics.
Acceptance: allocation 50% => 75% performance; overcommitted bus rejected; acceleration/projectile speed/recoil unchanged.

## Phase 5 — device command pipelines
- [x] Active + bounded FIFO per physical device, including independent sensors (`BWDevices`).
- [x] Nonblocking submissions, nonfatal queue-full and lifecycle diagnostics.
- [x] Clear/abort/death/reset/respawn cleanup, including prepared weapon cancellation.
- [x] Verify FIFO, rejection invariance, cancellation, timeout and continued device operation.
Acceptance: accepted commands never overwritten; zero allocation cannot operate; no stale lifecycle work.

## Phase 6 — values/results
- [x] Dictionary literals, property/key access and mutation; immutable snapshots (`BWValue`, `BWExpression`, `BWParser`).
- [x] Universal success/fail result contract and command IDs/status query.
- [x] Verify expected failures continue; genuine errors safely stop with source diagnostics.
Acceptance: all public calls return status/reason; submission success distinguished from completion.

## Phase 7 — scanners
- [x] Dictionary observations with actual acquisition time and hit point (`DirectionalScanner`).
- [x] Physical mounted-angle static/runtime validation, installed hardware, acquisition duration and range allocation.
- [x] Preserve separate physical sensor cooldowns and manual scanner/occlusion behavior.
- [x] Verify immutable empty/hit results, ownership, timing, independent requests and geometry regressions.
Acceptance: no hidden locations, no speculative scans, no shared sensor cooldown.

## Phase 8 — IDE/instrumentation
- [x] Chassis/bus/device configuration inspection and validated editing (`BWIDE`, server remotes).
- [x] Thread lines/states/ticks, devices/queues/allocation and timestamped thread logs.
- [x] Preserve run/stop, editor, per-tank history, manual switching and privacy.
- [x] Verify UI/server integration with mocks; identify Studio-only ergonomics checks.
Acceptance: developer can identify why a thread waits or submission fails without replacing existing UI.

## Phase 9 — acceptance/documentation
- [x] Add comprehensive new runtime automated suite and deliberately update changed contracts.
- [x] Run all existing suites and static compilation (`scripts/check.mjs`).
- [x] Both Rojo builds and `git diff --check`.
- [x] Document configuration, costs, ordering, lifecycle, limits and all requested sample programs (`docs/BW_RUNTIME.md`).
- [x] Final checklist audit with completed/incomplete/untested results.
- [ ] Roblox Studio play tests: native UI, two tanks, real raycasts, recoil/terrain/collisions, smoke/destruction, mobile inputs, network ownership/privacy.
Acceptance: report actual results, never infer Studio success from mocks.

## Architecture decisions / open details
- Reuse existing `BWRuntime` as one physical-command executor per active device; new `BWExecution` owns thread scheduling/shared environment and `BWDevices` owns queues. Keep legacy module tests as regression evidence.
- BW cycle clock derives exclusively from fixed simulation dt. Ascending thread ID order within each cycle; assignments commit atomically in that order (later write wins).
- `wait_for(name)` waits for a truthy assigned value (null/false are false); version-change checks observe assignments, including equal-value assignments. Missing names may be waited on without undefined-variable errors.
- Device configurations must reserve allocation even while idle. The arena defaults to a Hexadeca development chassis: drivetrain, turret, weapon and eight sensors each reserve 100% on a dedicated bus. This preserves existing full-performance manual/BW physics. Lower-tier presets reserve shared fractions; device caps apply equally to manual and BW controls.
- Legacy action submission semantics deliberately change from blocking to accepted/queued; update demonstration to use command-status/clock waits where completion is required. No user functions/loops are added.

## Verified phase evidence
- Phases 2–7: `tests/BWExecution.spec.luau` passes 82 assertions for CPU/thread/shared/device/result/acquisition/lifecycle contracts, including atomic budget reservation and the if/switch cost tradeoff. Existing physical executor regressions still complete the exact Boomer/Rattler demos with 5/21 shots. Existing geometry/value/scanner suite passes 126 assertions after deliberate dictionary-contract updates.
- Phase 8: mocked IDE tests verify config editing/validation, hardware inspection and timestamp/thread logs. Production server integration exercises hardware ownership/capacity validation, live-config rejection, private diagnostics and concurrent streams, in addition to existing independent tanks/BW, manual switching, combat and cleanup.
- Documentation: all ten Python sample programs are extracted from `docs/BW_RUNTIME.md` by the check runner and execute against both physical tank simulations, including Bunny/Dual presets where relevant.
- Implementation detail: resumable expressions use explicitly scheduler-resumed Luau coroutines, never task scheduling. Each source instruction reserves bounded worst-case credit before execution; actual charges follow reached operations. Ordinary assignments cannot split across CPU exhaustion. Explicit waits/physical observations suspend without replaying calls or partially committing assignments.
- Test-harness adjustment: renderer and production-server fixtures now run in separate fresh Luau VMs. The Luau Web build has a fixed ~18 MB heap; retaining both fixtures exhausted it. Both fixture suites remain enabled; diagnostics retained by mocks are bounded.

## Remaining validation / limitations
- **Studio play tests remain unchecked:** Studio is unavailable in this environment. Next action: sync the Rojo build into Studio, restart Play, run the default and documented Bunny/Dual examples, inspect native editor/hardware scrolling and mobile controls, and verify two-client output privacy plus real-world raycast/filtering, recoil, terrain, smoke and destruction continuity.
- No public blocking command-completion wait is added; `command_status()` and explicit clock/shared readiness coordination are available. No loops/user functions/smart tracking are implemented, as scoped.
- Clock/change-check return values follow the universal dictionary contract (`get_clock().time`, `variable_has_changed(name).changed`). This is an explicit interpretation of the requested universal result rule.
- Compact hardware editor exposes tier/bus/allocation, while per-scanner acquisition duration remains server-data configurable. This is a UI limitation, not an unimplemented device timing path.
- Mutable dictionary equality is identity-based; scanner snapshots and nested points are immutable. Root variable versions track assignments/property writes through that name; aliases do not synthesize extra notifications.

## Final automated acceptance results — 2026-11-08
- `node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js`: PASS, all suites; 62 production Luau sources compile. New runtime: 82 assertions; scanner geometry/value: 126; v0.2: 123; retained physical BW: 6,095; production server integration: 3,950; renderer: 122. Existing camera, input, tanks, terrain, recoil, trajectory, weapons, combat, damage and telemetry suites pass as well.
- All ten documented programs execute successfully on both tank simulations (20 sample runs), with Bunny/Dual hardware presets tested where specified. The shipped default is also exercised by the real server-entrypoint integration fixture.
- `rojo build -o battleworks.rbxl`: PASS.
- `rojo build -o battleworks.rbxlx`: PASS.
- `git diff --check`: PASS.
- Completed: phases 1–8 and automated/documented acceptance in phase 9. Incomplete/unverified: the single Studio play-test item above. No requested core runtime feature is knowingly left as a stub; the explicitly documented compact-UI and language scope limitations remain.
- Existing full-performance physical executor demos retain 5/21 shots. Physics/model/weapon/terrain/camera regressions pass; native engine and visual continuity cannot be claimed without Studio.
- No commit or push performed.

## Follow-up — multi-object scanner / explicit radar distance
- [x] Replace global nearest-hit pruning with per-object visibility collection; immutable sorted `detections`, `count`, `range`, and nearest convenience fields (`DirectionalScanner`).
- [x] Preserve occlusion and bounded queries, deduplicate hits, and reject safety overflow rather than return incomplete success (`ScannerGeometry`, `ScannerConfig`).
- [x] Add validated/copied hardware `range`/`distancePercent`; default 150 studs at 100%, independent of bus performance (`BWChassis`, `BWDevices`, server manual/BW paths).
- [x] Display every detection in private IDE scan logs; prioritize visible enemy reactions over neutral cover (`init.server`).
- [x] Final follow-up automated suites, both builds and whitespace check. All suites pass; scanner tests 138 assertions, runtime tests 84, and 11 documentation examples execute on both tanks. Both Rojo formats and git diff --check pass.
- [ ] Studio: multiple tanks and cover in one cone, copy/paste complete multi-hit output, and full 150-stud range on shared-bus chassis. Studio unavailable; next action is native Play testing.
Acceptance: visible separated tanks/walls appear once each in nearest-first order, fully hidden tanks remain absent, and configurable hardware range affects both probes and raycasts.

## Follow-up — in-game language handbook
- [x] Inspect actual command contracts, costs, CPU scheduler, device performance and timing before writing help.
- [x] Add data-driven reference (`src/shared/BWHandbook.luau`) covering all 16 callables, syntax/expressions/branches/threads, result fields, CPU versus physical time, buses, busy devices, queues, cancellation and log interpretation.
- [x] Add BW Handbook popup (`src/client/BWHandbookView.luau`, `BWIDE.luau`): ten navigable topics, horizontal topic scrolling, wrapped vertical content, selectable read-only text, explicit Close and lifecycle cleanup.
- [x] Automated verification (`tests/BWHandbook.spec.luau`): 159 assertions; every command signature parses and no callable reference is missing. Dynamic costs, navigation, source/control preservation, live execution updates and cleanup pass.
- [x] All project suites pass; 64 production sources compile; both Rojo formats build; git diff --check passes.
- [ ] Studio: verify native automatic text height/canvas scrolling, selecting/copying handbook text, responsive tabs, touch/gamepad navigation, and reading while BW continues. Studio unavailable; next action is Play testing the BW Handbook button.

## Follow-up — handbook completeness and scrolling
- [x] Audit actual rendered content rather than only the command registry; add missing dedicated print reference.
- [x] Add complete command directory plus top-of-topic signatures/costs for all 16 callable commands, with dedicated detailed headings beneath. Movement includes back and both chassis rotations; Turret includes both relative/absolute left/right commands.
- [x] Replace automatic TextBox/canvas height with explicit TextService measurement, resize updates, bottom padding, enabled scrolling and a high-contrast 10px vertical scrollbar.
- [x] Test complete rendered signatures/inputs/behavior/returns, expected topic placement, whole-document canvas bounds, width changes and popup lifecycle: 294 handbook assertions pass. All other suites and both Rojo builds pass; whitespace check passes.
- [ ] Studio: confirm real-font measurement, mouse/touch scrolling to the final command, horizontal topic navigation and copying long sections. Native Studio remains unavailable; next action is Play testing the revised handbook.

## Follow-up — free debug output
- [x] Set print submission cost to zero; automatic logging remains uncharged.
- [x] Waive pure debug display reads/access/calculations while preserving ordinary costs for expressions containing gameplay device/query/wait calls, and for assignments outside print.
- [x] Match instruction cost reservations to actual charging; retain source/output/per-cycle safety bounds.
- [x] Update handbook and runtime guide; verify free printing does not throttle a Bunny and cannot bypass scanner/command/conditional-control costs. Runtime suite now 91 assertions; handbook 295. All project suites, both Rojo builds and whitespace checks pass.

## Follow-up — scanner position and while (2026-11-09)
- [x] Add exclusive Scanner(position=0..7) literal/expression alias, angle conversion and validation through existing command/device path.
- [x] Add block-aware while AST and backward control flow, per-test CPU cost, falsey semantics, nested branches/loops and asynchronous conditions. Preserve existing strict if/logical contracts.
- [x] Verify no server starvation: per-thread budgets, hard zero-cost cap, shared-state stop condition, explicit Stop, runtime timeout and controller/device cleanup.
- [x] Add scanner alias and While loops handbook entries, costs/limits and executable guide example.
- [x] Final full suites, both Rojo builds and whitespace checks. New loop/position suite: 65 assertions; handbook: 299; twelve guide programs run on both tank simulations. Existing physics/combat/BW/scanner suites remain passing.
- [ ] Studio: position-indexed scans on real sensor geometry, loop highlighting, polling during recoil and manual Stop/reset/tank switching. Studio unavailable; next action is native Play testing.

## Follow-up — tank-specific core/bus defaults
- [x] Add centralized Boomer=Bunny (1 core/bus) and Rattler=Octa (8 cores/buses) mapping; use it for spawn/controller/diagnostic defaults.
- [x] Distribute Rattler sensors over buses 4–8 with valid reserved sums, keeping drive/turret/weapon on buses 1–3. Boomer uses the existing one-bus preset. Explicit development configuration persists through reset.
- [x] Verify tier/tick/queue values, all buses used, valid allocations and server rejection of threads above 1/8. Runtime suite now 103 assertions. Update manual Boomer integration timing to follow existing shared-bus performance.
- [x] Update runtime guide, handbook and handoff with defaults and Boomer allocation consequences.
- [x] Final full suites, both Rojo builds and whitespace checks. All suites pass with tank-specific defaults, including production default diagnostics and configured Boomer firing timing.
- [ ] Studio: restart Play and inspect both chassis panels, run thread(8) on Rattler, reject thread(2) on default Boomer, and assess shared-bus Boomer handling/reload feel. Studio unavailable.

## Follow-up — standalone language Markdown
- [x] Create `docs/BW_LANGUAGE.md` as a standalone programming reference: full syntax, all 16 callable commands, inputs/returns/costs, current chassis/bus defaults, queues, multi-object scanners, position aliases, loops/truthiness, threads/sync, free debugging and limits.
- [x] Link from README and runtime architecture guide.
- [x] Verify all 12 executable examples parse and run on applicable default hardware (23 tank-simulation runs; thread-8 example runs on Rattler only), and every callable has its own detailed entry. Documentation-only change; no gameplay code or build changes.

## Follow-up — world bearings and own-facing query
- [x] Add get_facing_direction() to grammar/runtime/costs, returning the standard immutable result with world_direction from current authoritative chassis yaw (base 0.1 ticks).
- [x] Rename scanner direction to relative_direction and add world_direction on each detection and nearest convenience fields; empty scans return null bearings, old direction is absent. Capture one acquisition yaw and derive both bearings from the same visible hit point.
- [x] Migrate handbook, language Markdown, runtime guide and examples. All 17 callables have detailed reference entries; 14 standalone handbook examples parse/run on applicable tank configurations.
- [x] Verify compass cardinals/wraparound, chassis rotation, immutable snapshots, queue-target versus actual facing, new getter arguments/cost and direct scan-world-bearing turret aiming on BOTH tank types. Scanner suite: 179 assertions; runtime: 140; handbook: 312.
- [x] All automated suites and both Rojo formats pass; git diff --check passes. Physics/projectile directions and scanner geometry filtering remain unchanged.
- [ ] Studio: restart Play, rotate each chassis, compare relative/world bearings, use world_direction with to= aiming while moving/recoiling, and verify native log/handbook display. Native Studio remains unavailable.

## Follow-up — user's eight continuous scanner threads
- [x] Reproduce exact source on Rattler: old production runtime fails on accepted scan 129 with Scanner observation limit exceeded; old output256/command512 ceilings would also terminate useful loop activity.
- [x] Replace lifetime quotas with bounded rolling scan, IDE log and terminal command histories; retain active/queued records and direct pending-scan ownership. IDs continue increasing; expired terminal queries fail normally.
- [x] Bound network logging per CPU cycle with an explicit omission diagnostic, without adding CPU tick costs or terminating execution. Expose progress/omission/retained counters privately.
- [x] Run exact program for 30 simulated seconds: 2,400 scans, 4,784 log attempts; all eight variables retain correct sensor ownership and histories remain bounded. Verify Stop, global timeout, transient scannerBusy recovery, log-rate recovery, active-command protection and terminal eviction.
- [x] Preserve single-core Boomer rejection; update handbook/language/runtime docs to distinguish rolling retention from execution safety limits.
- [x] Final full suites, both Rojo builds and whitespace checks. All project suites pass, including exact eight-thread reproduction, 30-second rollover, rate-limit recovery and timeout.
- [ ] Studio: restart Play and run exact source on selected Rattler, watch rolling/copyable logs and counters, confirm all sensor reactions, Stop/reset, and no memory growth over a full program. Studio unavailable.

## Follow-up — sensor cooldown, activity and missing output
- [x] Audit actual per-sensor cooldowns and real global query guard with all eight loops; identify visual last-event overwrite and lexical query-priority bias.
- [x] Retain/replicate at most eight coarse BW lens events; independent expiry and start/death/reset cleanup; deduplicate legacy alias in renderer.
- [x] Rotate sensor acquisition priority deterministically without changing CPU thread order, FIFO, cooldowns or shared safety rate. Real10-second audit improves previously starved sensor from6 to59 successes, all8 at least50.
- [x] Add private per-sensor attempt/success/failure/last-result diagnostics and visible UI rows.
- [x] Fix focused log without selection freezing live output; preserve actual text selection for copying.
- [x] Test real production eight-thread scan/print with actual hitboxes, all8 replicated lens states/private scan angles and explicit opponent print; test renderer simultaneous lenses/expiry, close tank geometry and fixed-cone blind gaps.
- [x] Final full suites, both Rojo builds and whitespace checks. All suites pass: renderer139, scanner193, handbook315, production server4392; real scanner audit confirms progress on every lens.
- [ ] Studio: restart Play, run exact code on Rattler, verify all8 lenses pulse, inspect each sensor result row, copy logs, and distinguish blind cones/cover from cooldown or query-budget failures. Studio unavailable.

## Follow-up — unconditional print after Scanner
- [x] Reproduce exact clarified source through actual server Run/controller/interpreter/scanner/private output and real BWIDE receiver/update; validate visible explicit output with hits AND with zero detections. Detection guard cannot explain the unconditional print.
- [x] Add server print execution/emission and per-thread loop/print counters; client receipt counts and generation/run-aware visible log status.
- [x] Page displayed history into bounded TextBoxes with Older/Latest controls and UTF-8-safe splitting; preserve read-only selection and all retained ordinary lines.
- [x] Add regression checks for paging, explicit counts, actual source/empty scenes and loop entry.
- [x] Final full suites, both Rojo builds and whitespace checks pass; exact server-to-IDE reproduction covers populated and empty scans, handbook paging suite passes 339 assertions.
- [ ] Native Studio blank-output cause remains unverified: restart Play (not merely Reset Battle), run exact snippet and report Prints run/received/page plus T1 scan wait/loop counters. Mocked path is verified; no confirmed native diagnosis is claimed.

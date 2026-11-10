## Boomer Hyper installation (2026-11-10)
Boomer now installs drive.hyper_p35 (Hyper P35): forward35, reverse18, acceleration22, braking38, coast14. Wheels, Gatling, Bunny and bus allocations unchanged; Rattler retains Stride drive.car. Live integration1288 checks includes simulated Boomer full-throttle35 and speed HUD baselines;13 docs programs on both live assemblies pass. Both builds/diff check pass. Native driving feel still requires Studio validation.

## Speed HUD after mobility swap (2026-11-10)
User Studio trace exposed SpeedDebugHud dereferencing Definitions.Rattler.Drive.Speed after Rattler became tracked (legacy Drive view is wheeled-only). Replaced vehicle-name dispatch with Components.get(state).Drivetrain.Speed. Audited production .Drive reads: remaining TouchInput.sticks.Drive is unrelated UI input. Live swap suite now explicitly updates HUD across repeated Boomer/Rattler switches and nil selection:1286 assertions pass. Existing speed11, trajectory1855 and recoil6015 checks pass; both Rojo builds and diff check pass. Native Studio retest pending.

# Mobility swap (2026-11-10)
Boomer now installs mobility.wheels; Rattler mobility.tracks. Propulsion, weapons and computers remain installed as before. Renderer selects wheel/tread assembly, animation and inertial pose by component capabilities instead of body name. Live integration tests cover wheel/no-pivot versus track pivot, moving wheel arcs and unchanged propulsion tuning. Full regression run passed all groups except a handbook assumption exposed in editor group; replaced name-specific wheel limit with catalog mobility limit, then editor175 and handbook391 pass. Live swap1281 and all13 documentation programs on both simulations pass. Both Rojo builds and whitespace checks pass. Studio visual/driving validation pending. User confirms E3.2 CtrlZ works but flashes; undo flash remains outstanding, no further history changes in this mobility swap.


Undo follow-up (E3.2): keyboard undo/redo retains an authoritative history snapshot beyond key release and settling frames. Late native history callbacks restore that snapshot on the next Heartbeat and cannot become new edits. The next non-modifier editing/navigation input or explicit lifecycle release relinquishes ownership. Native Studio Ctrl+Z/Ctrl+Y retesting remains required.
# BattleWorks game and Codex handoff

Last reviewed: 2026-11-08. This document records the implemented prototype, user requirements, development workflow, and unresolved questions for future sessions. Read [README.md](README.md) for player setup and the detailed Android test checklist. Source code is the authority if either document becomes stale.

## 2026-11-10: CtrlZ/Y native history conflict; E3.1

User reports CtrlZ no effect, CtrlY removes typing and cannot redo reliably; ShiftDelete works. Short key guards cleared at key-up let late native undo become a new app edit and wipe redo. Keyboard undo/redo now changes one logical app-history target and defers widget writes across stable Heartbeats, retaining ownership past key release/native property callbacks. Rapid successive chords update the same app history without recording the native intermediate buffer. Ordinary native edit history commits also wait stable frames so native-first keyboard callbacks aren't prematurely recorded as typing. Buttons use the same history directly. Non-history keys, bind/release settle pending history ownership. Confirmed E3 Enter and ShiftDelete paths retained. UI label E3.1-history. New reproduction tests include typing, late after key-up native callbacks, native-first redo, empty redo, immediate undo before native commit, Control-modifier flush before native undo and rapid undo/redo. Editor suite171 assertions passes. Native user confirmation still needed; do not claim Studio success from mocks.

## User confirmed E3 Enter; line-delete shortcuts added

User said Enter is perfect. Preserve that native/frame-boundary path. Ctrl/Cmd+Z/Y undo/redo are verified; Shift+Delete now removes the caret's entire line (including following newline, or preceding newline for final line). It ignores selection extent, preserves CRLF and valid Unicode caret, and is one undo transaction. Native-first line deletion/cut/default-delete echoes are recognized so two lines are not removed. Editor suite158 assertions and all regressions pass; both Rojo builds/whitespace pass. New shortcut behavior remains native-user-test pending. No commit/push.

## Enter E3: actual frame boundary and stale caret beside existing newline

User again saw a blank line followed by caret on next line at column0. Found a missing case: cached caret can already advance past an existing newline while underlying old Text is still cached, so the old formatter decorated the wrong line. E3 derives the insertion location from SETTLED native caret + validated old/new text. It only inserts whitespace; newline bytes are copied verbatim. Formatting waits across two stable Heartbeats via task.delay(0), not same-frame task.defer. Deferred own-write Text signals are skipped by text identity. Caret restore is later-frame and assigns SelectionStart before CursorPosition. Invalid/unmatched native changes fall back rather than freezing editor history. Toolbar toggle now visibly reads BW Editor • E3; ScreenGui EditorVersion=E3-frame-enter. User can confirm actually loaded client version.

Editor tests now123 assertions with separate deferred/frame queues, stable-caret waiting, stale-cache Enter just before an EXISTING newline, both normal and colon indentation, native own-write echoes, undo caret, and newline-count invariants (LF/CRLF, native indent, repeat payloads). Existing immediate-only mocks were insufficient; do not repeat claims native behavior fixed solely from tests. Native Studio remains unavailable. Async question asks whether user tests Studio+Rojo, built place or published game; answer pending. Need real E3 user retest.

## Enter failure correction: native insertion is the only newline producer

User's first Studio test added two lines and put caret at column zero. Previous eager custom Text.enter on InputBegan plus native echo guard was unsafe. Replaced Enter path entirely: record intent without writing Text, wait for actual native newline, then decorate it with indentation. Intent is retained after key release. A late-caret latch repairs only the expected raw native caret offset; next real input clears it. Native-first insertions already committed before InputBegan are recognized as recent newline events and coalesced into the same undo gesture. Enter selection replacement and raw-format undo echoes are covered. Other shortcuts/paste modes remain intact. BWEditor tests now105 assertions, including explicit proof InputBegan alone cannot add a newline, four/eight-space delayed insertion, committed-native-first and late column-zero updates. Actual Studio keyboard behavior remains unverified; ask user to restart Play and repeat, not claim native success from mocks/builds.

## IDE editing / AI paste workflow

BWEditorText now contains pure Enter/Backspace/line-indent/paste/history operations; BWEditorController owns native TextBox keyboard/clipboard transactions, deferred caret restoration and source-only shortcuts. Removed full-buffer leading-tab rewriting and all Run normalization. Enter retains indentation/adds4 after a real trailing colon, Backspace removes to previous indent stop, Tab/ShiftTab operate on current/selected lines and preserve selection orientation. Native ordinary/grapheme deletion and IME/clipboard remain native.

Latest user steering: AI code should align to the prepared insertion point. Paste: align is now default, rebasing common outer indentation while retaining relative nesting/inline strings/line endings. Multiline insertion directly before old code adds a separating newline if needed; obsolete code is never automatically removed. Paste: exact toggles literal received whitespace preservation. Controller captures Ctrl/Cmd+V insertion identity; multiline context paste can align too. History records final payload/formatting as one operation, not per-line steps. Native first/last key echoes, raw-before-format undo echoes and rapid typing before indentation have tests. Undo/Redo buttons plus Ctrl/Cmd+Z/Y/ShiftZ are supported, with per-tank text/caret/history retained. No BW CPU cost. Histories96 entries/512KiB plus current/last raw echo; source size validation remains compiler-side.

BWEditor suite90 assertions and all regression groups pass. Both Rojo formats and whitespace checks pass; results tracked in docs/BW_RUNTIME_IMPLEMENTATION_CHECKLIST.md. Native Studio OS clipboard/focus/key repeat/mobile/IME behavior remains unverified; restart Play to test actual event ordering. Source toolbar has Undo/Redo and Paste mode; editor minimum height260 avoids negative source canvas after adding tools. No commit/push.

## Current loadouts: guns deliberately swapped

Live VehicleAssemblies now has Boomer weapon.gatling, Rattler weapon.cannon. Bodies/turrets/wheels/tracks/computers/bus allocations remain original. Gun-related hop/rattle behavior belongs to ComponentCatalog weapon.Recoil.Kind=Jackhammer and visual style/recoil/swell to weapon.Visual. Shared recoil overlay is active on tracks when that weapon is installed, preserving horizontal state/landing across hops. Cannon-equipped wheeled Rattler no longer hops.

Found/fixed renderer and client event/HUD assumptions equating Rattler with Gatling. Body/turret art is built independently of gun art; descriptor weaponId in state/events selects gun construction, muzzle effects, barrel spin/cannon swell, rocking and landing dust. TankRenderers rebuilds on descriptor change. Existing turret colors/silhouettes and mobility art remain. Cannon PrepareShot sends the real carrier identity; client uses weapon metadata for heat/reload/firing effects. Components.forWeapon caches resolved visual profiles. TankConfig and RattlerWeapon default tuning are canonical cannon/Gatling compatibility views rather than whichever gun their historical names now carry. No new damage/balance tuning; Boomer shared20% weapon allocation means Gatling fires slower there.

Regression groups0–13 explicitly load tests/fixtures/LegacyVehicleAssemblies.luau to preserve historical weapon timing baselines without substituting physics. Groups14–15 use actual live assemblies: production server + renderer swap scenario1278 assertions and all13 docs programs on both live tank simulations. Shared server setup reused by runner; marker changes fail loudly. All regressions/builds/whitespace pass. Studio actual visuals/play still pending. Restart Play, not only Reset Battle, to reload cached modules. No commit/push.

## Vehicle component migration (2026-11-09)

Read docs/VEHICLE_COMPONENTS.md for the pre-code inspection, implemented reference, examples and verification checklist. ComponentCatalog is the single immutable tuning source; VehicleAssemblies install IDs; VehicleComponents validates/copies/freezes profiles and binds them privately to state in a weak registry. TankConfig/TankDefinitions remain catalog-backed compatibility facades, not independent tuning stores. Simulation.new fourth parameter accepts an assembly or resolved profile. No full profile is added to public state; maxHealth is replicated for correct component-backed durability display.

Propulsion belongs to Drivetrain; steering/pivot/inertia/suspension belong to Mobility; hull health/radius/hitbox/contact footprint/slots belong to Chassis. Turret, weapon/aim/jackhammer, individual mounted sensors, registered computer tiers and bus allocation/performance defaults are resolved independently. TankSimulation/BWTankAdapter/BWDevices/server weapon dispatch now use installed capabilities/operation, not model names. Historical RattlerDrive/Recoil/Weapon filenames remain shared/compatibility modules. Default numerical tuning and demo shot counts/timings remain unchanged. Boomer now supports tracked BW steering; track idle/stop releases both tread intents instead of continuing to pivot. Finite curved track movement uses signed tangent progress like wheels. CPU costs, queue/replacement lifecycle and server authority stay intact. The existing dev hardware tier selector installs a registered computer profile, preserving its overrides through reset.

84 component assertions and all existing regression groups pass; renderer140, handbook391, server4876, steering57, CONST405,13 runtime-doc programs on both tanks. Both Rojo builds and diff whitespace pass. No commit/push. Studio visual/manual/terrain/recoil/mobile checks are NOT verified. Important debt: engine is kinematic (optional Mass is metadata, no torque/force model); art/attachment layouts still handcrafted for two models; full arbitrary custom profiles are not replicated, so future upgrade art/aim previews need a versioned visual descriptor. Upgrades should construct a fresh state and reconcile existing hardware overrides; no runtime hot-swap or new player upgrade UI was added.

## Persistent wheel steering / continuous BW driving

BWCommands/Chassis add steer_left/right(degrees), steer_center(), stop(), distance-free forward()/back(), all 1 tick per issue. BWDevices retains a radian wheel target and converts to existing normalized InputCommand at the boundary. Angle requests 0..180 clamp to installed Rattler MaxSteer0.55 (~31.5deg); Boomer steering fails unsupportedDrivetrain. Setpoints bypass queues and complete immediately, returning commandId/steeringDegrees (+left/-right), without altering physics poses. Existing smoothing, car motion, coasting, recoil, airborne controls and damage input filtering remain untouched.

Continuous movement occupies the single active drivetrain slot indefinitely (global180s program bound), keeps BW ownership after threads finish, and spends no recurring CPU ticks. A new continuous request or stop cancels active+pending drive work; finite navigation replaces an active continuous request, while finite-versus-finite stays FIFO. Steering can change immediately while moving, including when FIFO is full. High-level chassis turns temporarily control actual wheels, then saved steering resumes. Stop retains steering but releases throttle; program lifecycle cancellation clears intent. Existing Controller cleanup/manual handoff is reused. IDs/status/history include all new commands/cancellations. IDE diagnostics display wheel target.

Rattler finite movement uses existing BWRuntime with followSteering flag to accumulate signed actual displacement along changing heading tangents; lateral/vertical drift excluded, full circles can finish. Boomer/legacy serial finite executor retains start-axis semantics. New BWSteering suite57 assertions covers primary demos, finite/reverse arcs, limits, CPU/bus performance, command transitions/FIFO/cancellation, deterministic threads, controller lifecycle/manual restoration, damage/smoothing, and uninterrupted scan-loop steering. Full regression suites, handbook391, 13 runtime-doc examples on both tank simulations, both Rojo builds and diff whitespace pass. Updated old invalid forward()/forward(best_effort=true) fixtures for the intentional new valid forms. Studio driving/visual/mobile validation is still pending and must not be inferred from builds/tests.

## Compile-time scalar CONST

BWParser now supports uppercase `CONST name = expression`, resolving previous constants in textual source order with program-wide scope matching shared mutable BW names. Source AST retains declarations; runtime streams omit them and references become literal nodes. Scalar-only, no function calls/indexing/collections, no runtime/self/forward dependencies (including short-circuited operands). Reject duplicates, mutable-assignment name conflicts and direct/property/index writes, including unreachable branches and other threads. Sync variable-reference built-ins reject substituted constants via existing signature checks. Runtime variables/versions contain no constants; CPU reservation and actual evaluation use the same literal AST without new free-variable rules. Commands stay lowercase/case-sensitive. Constants in branch/thread blocks are unconditional compile-time declarations; recommend top-level definitions.

Dedicated BWConstants suite passes 405 assertions, including physical per-tick equivalence, CPU exhaustion/reservation, scalars/operators, errors/lines, cross-thread use, zero storage/read/declaration costs and unchanged ordinary variable charges. Full regression suites, both Rojo builds and whitespace pass. Language/runtime Markdown and in-game handbook updated. IDE remains plain TextBox with existing compiler diagnostics; no highlighting/profiler introduced. Studio native CONST entry/run validation remains pending.

## Unconditional loop-print tracing and bounded log pages

User clarified print(scan0) immediately after Scanner is unconditional and missing, so target-detection guard is not an explanation. Added production entrypoint -> actual client BWIDE test using EXACT source for both detected and completely empty scenes; loop runs and server prints reach visible UI in the mocked integration path. Native blank output is not reproduced here; do not claim a proven native root cause without the user's live evidence.

BWExecution diagnostics now expose total printCount/emittedLogCount and per-thread prints/loopTests. Private runtime packets include generation/request identity. BWIDE counts received print events, shows Prints run/received/page status (unknown '?' if counters are unavailable), and marks selection pauses/rate suppression. This gives a native user a concrete execution-versus-delivery trace.

IDE output now uses bounded pages (MaxOutputPageBytes8192, MaxOutputPageLines120), instead of one giant TextBox containing the full retained history. Older browses prior pages; Latest resumes following. Full bounded event history stays cached, UTF-8 splits are safe, and selection remains read-only/copyable. Restart Studio Play to load changed module caches; Reset Battle alone does not reload scripts. Studio native rendering still unverified.

## Eight-sensor activity visibility / shared-budget fairness

Verified cooldown is already per-sensor: source.sensorScanTimes and each BWDevices device.readyAt are independent. Found actual light bug: init.server published all BW reactions into ONE scanVisual, so six .0667s and two .05s Rattler acquisitions overwrote each other before 20 Hz snapshots, exposing only the last lens of each group. New state.scanBW retains one coarse actual-completed event per physical lens; legacy scanVisual remains a cloned latest-event alias. Each expires independently; renderer observes the map and deduplicates serials to avoid double-aging the alias. Start/death/reset cleanup includes the map.

A real Scanner/Runtime 10-second workload audit also showed shared64/s safety-budget lexical bias: one sensor succeeded only6 times while most got100. BWDevices now rotates ONLY sensor acquisition order each cooldown interval; thread order/FIFO/cooldowns/overall safety budget remain. All sensors exceed50 successes in the same audit. Device diagnostics expose attempts/success/fail totals and lastScan {status,count or reason,timestamp}, all private; public lens map contains no exact observations.

Exact user program in production server fixture now verifies all eight map events, all eight private scan angles, and explicit printing of a real opponent; renderer tests verify eight simultaneous Neon lenses, alias deduplication and independent expiry. Analytic geometry tests verify close body detections around the chassis. Existing15-degree cones at45-degree mounting increments DO have blind gaps; no widening was authorized. Docs now explain this and how to inspect empty versus failed scans.

Also corrected log selection: simply focusing the output TextBox no longer freezes live output. Updates pause only for a nonempty selection, preserving copy/paste; clearing selection resumes.

## Continuous scanner-loop failure fix

Reproduced the user's exact eight-thread scanner/print source on default Rattler: prior production BWExecution stopped at scan 129 (Scanner observation limit exceeded). Absolute log limit 256 and device command-ID ceiling 512 would also break continuous loops. Production now uses rolling histories: MaxScannerHistory128 snapshots, MaxOutputEvents256 IDE rows, MaxCommandHistory512 terminal records plus ALL active/queued commands. IDs increase without a lifetime submission cap; expired terminal status IDs return invalidArgument. Waiting scanner threads retain direct command references so eviction cannot lose ownership/results.

Output attempts are counted but do not terminate execution. MaxLogEventsPerCycle64 bounds emitted logs per tank/CPU cycle, reserving a slot for an explicit diagnostic when excess logs are omitted. CPU budgets, scanner per-sensor cooldown/global work limits, device queue depths, output formatting bounds, and the 180-second program timeout remain. Diagnostics expose total scans/log attempts/omitted logs and retained sizes. BWConfig.MaxScannerCalls remains for the legacy serial-interpreter fixture only. New BWScanLoops suite runs exact user source for 30 seconds beyond all old caps, and tests rolling command history, log suppression/recovery, Stop and rejection on single-core Boomer.

## World/relative scanner bearings and facing query

Latest instruction renames scanner direction to relative_direction and adds world_direction, on every immutable detection AND nearest convenience fields. Empty scans return both as Null; old direction is absent. ScannerGeometry.worldBearing derives compass bearing directly from the observed world hit point; relative bearing uses the captured acquisition yaw. No geometry/raycast behavior changes. Snapshots retain acquisition values when tanks subsequently turn/move.

get_facing_direction() is a no-argument explicit own-chassis state query returning {status,reason,world_direction}; base cost 0.1 ticks. BWExecution reads the current authoritative state yaw through BWTankAdapter.heading, not cursor/turret/queued desired orientation. Standard dictionary return format is retained. Print wrappers do not waive gameplay query costs. Absolute commands are turn_left/right(to=world_heading) and turret_left/right(to=world_heading); no rotate_right alias added. Handbook and standalone Markdown references migrate to these keys/direct aiming examples.

## Tank-specific chassis defaults (2026-11-09)

Latest user requests Rattler eight cores/buses and Boomer single-threaded. BWChassis.TankTiers maps Rattler=Octa, Boomer=Bunny; forTank returns fresh validated presets. Production controller/spawn/diagnostic fallbacks use forTank; explicit editor configurations persist across reset. Generic default() remains Hexadeca for explicit development/test fixtures.

Octa assigns drivetrain/turret/weapon to buses 1/2/3 at 100%, then evenly places the eight sensors on buses 4–8 (paired sensors get 50% each, singles 100%). Bunny retains its existing valid one-bus allocations: drive40%, turret20%, weapon20%, eight sensors2.5% each. Thus Boomer physical caps/preparation follow .64 drive/.36 turret/weapon performance. This is the existing bus performance model, not altered weapon/base-physics tuning. Radar range remains 150 at 100% effectiveness. The handbook hardware section lists current tank defaults dynamically.

## Scanner position alias and while loops (2026-11-09)

Latest user explicitly authorizes while, superseding the prior no-loop restriction. `Scanner(position=index)` accepts literal/computed integers 0..7, normalizes to degrees index*45, and shares the same physical device/cost/result path as Scanner(angle). Mixed inputs/invalid literal indices are static errors; invalid computed indices return invalidSensor. Results still expose sensor in degrees.

BWParser emits $while tests and backward $jump instructions. BWExecution rechecks conditions with Expression.truthy: false/null/zero/empty string/empty array/empty dictionary are false; other supported values true. Undefined reads stay errors; existing if/logical/wait_for semantics stay unchanged. Tests cost BWChassis.Costs.loop (initially 1) plus expression evaluation, including final false test. CPU reservation, per-cycle hard limits and global timeout bound loops; no task waits or recursive interpreter execution. Existing device queues/asynchronous calls are reused; shared-thread condition changes work deterministically. The retained BWRuntime helper understands $while too.

Handbook adds a While loops topic and both scanner signatures. No break/continue/for/while-else or user functions. Existing output/observation/command-history limits still apply. Test suite BWLoops covers parser/errors/aliases/truthiness/nesting/async conditions/polling/cancellation/budget starvation; native Studio testing remains needed.

## Free debug output

Latest instruction: print/debug logging costs zero gameplay ticks. `BWChassis.Costs.print=0`. Production `BWExecution` waives pure display-expression reads/access/arithmetic/comparisons/logicals in print; variables/assignments outside it remain normal. If the print expression contains a real device/query/wait call, its entire expression keeps normal costs, preventing free conditional control paths or nested-scanner bypasses. Automatic logs were already uncharged. Output limits, safety caps and normal side effects/errors remain. Cost reservation mirrors actual charging; handbook and runtime guide explain the exception.

## In-game BW handbook

`shared/BWHandbook` provides ten reference topics and sixteen command contracts with costs generated from `BWChassis.Costs` and current timing/limit configs. `client/BWHandbookView` renders the IDE's BW Handbook popup: horizontally scrollable topic tabs and vertically scrolling, wrapped, selectable/read-only text. The CPU intro includes a complete command directory; each command topic starts with signatures/costs and contains full INPUT/HOW IT WORKS/RETURNS blocks for every assigned callable, including print. Content height/canvas are explicitly measured via TextService and remeasured on resize, with a visible 10px vertical scrollbar; automatic TextBox sizing is no longer used. Opening releases old text focus and leaves execution untouched; closing, Run, tank switching and IDE destruction cleanly dismiss it. `BWIDE` preserves existing Hardware / threads alongside the new button. No gameplay/runtime changes in this feature.

Automated handbook checks cover every supported command/signature, dynamic cost updates, topic navigation, scrolling setup, focus, read-only text, live status updates, source/control preservation and cleanup. Native text autosizing/tab scrolling and touch/gamepad ergonomics still need Studio testing.

## Multi-object radar results (follow-up)

DirectionalScanner now gathers/deduplicates visible physical objects throughout the cone and returns an immutable nearest-first `detections` array, `count` and effective `range` on the standard result dictionary. Each entry retains accurate surface bearing/distance, tank identity/relation and immutable world hit point. Existing top-level fields remain nearest-hit conveniences. Walls still occlude; no hidden tank positions are exposed. All detections share actual acquisition time. Bounded safety overflow returns scannerBusy rather than partial success.

Scanner hardware supports validated/copied `range` and `distancePercent`; defaults are 150 studs/100%, now independent of bus performance (latest user instruction overrides the earlier allocation-driven range rule). Bus allocation still determines availability and acquisition time. Manual and BW scans both use the hardware range. The visual reaction prioritizes visible enemy tanks; private IDE output prints all indexed detections rather than clipping a multi-hit snapshot to the generic 2 KB formatter. No pre-battle allocation UI was added.

## Concurrent BW runtime (2026-11-08)

The latest mission supersedes the earlier parallel-command and scanner-array restrictions. Read `docs/BW_RUNTIME.md` and `docs/BW_RUNTIME_IMPLEMENTATION_CHECKLIST.md` first. Production `BWController` now uses `BWExecution`; `BWDevices` reuses old `BWRuntime` strictly for physical command completion. CPU budgets and devices are independent. Chassis tiers/allocations/costs live in `BWChassis`; default development hardware is Hexadeca at full device performance, preserving existing controls and physics by default.

Thread streams run deterministically in ascending ID order at 10 Hz CPU cycles over the existing 60 Hz server simulation. Source instructions reserve bounded credit atomically, charge actual reached operations and suspend only for explicit waits/physical observations. Shared variables have per-root versions. All callable results are dictionaries; scanner snapshots include acquisition time and world hit point. Literal physical scanner angles are restricted to 45-degree mounts; manual sweeping remains an internal driver-only implementation. Each physical device owns its active command/FIFO/cooldown. Operational failures are results, including legacy best_effort=false. Stop/death/reset cancel device work and prepared shots.

BWHardware intent is ownership/rate/config validated; BWRuntimeState diagnostics go privately at bounded 5 Hz, separate from BWOutput history. The IDE hardware panel uses a compact editable tier/device/bus/allocation text format. No loops/user functions/smart tracking are added. Existing gameplay suites and physical demo regressions remain; server and renderer fixtures now run in separate fresh VMs because Luau Web's fixed heap cannot retain both. All ten documentation Python examples are automatically extracted and executed on both tank simulations. See checklist for final checks and Studio-only remaining work. No commit/push.

## BW v0.2: values, expressions and decisions (2026-11-08)

The latest user explicitly authorizes variables, expressions, nested if/elif/else and switch/case, superseding all earlier v0.1 restrictions on those features. Loops, user-defined functions, automatic targeting/tracking, parallel commands, extra tank types and arbitrary Luau remain excluded. The default eight-action demonstration retains its behavior/source lines; its comment/version badge now says v0.2.

### Parsing and evaluation

`shared/BWLexer` is quote-aware (single/double strings, common escapes, # comments), with finite decimal/scientific numbers and bounded tokens/string sizes. `BWExpression` builds a bounded Pratt AST, checks function signatures and constant argument types/ranges, and evaluates strict typed values with zero-based array access and short-circuit logic. Precedence follows arithmetic/comparisons, then not/and/or; unary signs bind above arithmetic. Booleans are required for conditions/logicals. No implicit coercion; arrays compare by contents, ordering supports same-type numbers/strings, and chained comparisons require explicit and. Scanner is the only function allowed in value expressions. Movement/weapon calls and print are standalone statements.

`BWCommands` centralizes the existing action argument contracts for both parse-time constants and runtime expressions, including to= and best_effort. `BWParser` is replaced by a real four-space indentation/block parser, producing an AST (third return from parse) and forward-only flat control instructions compatible with the existing runtime interface. Assign/print/branch/switch/jump nodes carry original source lines/text; ordinary v0.1 numeric instructions retain their old op/value/absolute/bestEffort fields and execution timing. Switch tests evaluate once and choose one constant scalar label with no fallthrough; duplicate labels/defaults are rejected. Labels may be simple constant expressions. Full source is syntax/constant-argument checked before actions, including unreachable bodies, without invoking Scanner. Undefined variables/type errors dependent on runtime values remain line-numbered runtime failures.

`BWValue` now supports immutable tagged arrays, null, general readable scalar/array formatting and bounded deep equality/formatting of shared nested arrays. Null remains an explicit frozen sentinel. `BWRuntime` owns a fresh variables dictionary per execution, evaluates only reached control statements/operands, and passes selected asynchronous actions to the existing begin/step completion logic. Action arguments resolve once, not every tick. Expression scanner calls use the existing authoritative service/cooldowns and retain immutable observations/timestamps/results. New informational charge hooks/counts cover reads, writes, arithmetic, comparisons, logical operations, branches and function calls; scanner cost stays 5 and no real CPU enforcement or delays were added.

All expression/type/index/undefined-variable errors stop execution safely. Standalone operational scan/action failures retain best_effort; scanner failures inside expressions fail that statement rather than synthesizing an observation. Best-effort physical skips preserve variables and enclosing branch flow. Stop/error/death/reset discard variable environments; completed programs retain their private environment only until Stop/replacement/reset, never exposing it in public tank state or sharing it with another runtime. The existing server cleanup still releases throttle/steer/trigger and pending weapon preparation.

### IDE and output

`BWEditorText` converts leading tabs to four-space stops and inserts/preserves indentation after a newline, adding four spaces after block colons. Native caret updates are read after Text through task.defer; Run normalizes leading tabs before submission. No whole-editor syntax highlighting or general editor framework was introduced. Line gutter, multiline source, auto-close Run, Stop, per-tank source/history, scroll preservation and current source-line display remain.

A trusted onPrint service writes private BWOutput records using the same run/generation identity as scans. Scan diagnostics are explicitly labeled Scanner(angle) -> and print records are labeled separately; explicit print(result) remains an intentional second record. History keeps both in order with source lines/simulation timestamps and terminal status at the bottom. No printed values/variables are copied into public BW status. Value formatting truncates at 2,048 displayed bytes. Native input/scroll/caret behavior remains a Studio check.

### Bounds and verification

Limits: 16,384 source bytes, 400 lines, 128 source statements, 512 compiled forward instructions, 12 block levels, 32 expression levels, 512 tokens/line, 64 array items, 128 variables, 128 scanner observations and 256 output records. Overall/per-action/stuck and immobilization-grace limits remain unchanged. No backward jumps are generated. Informational costs are centralized in BWConfig.CycleCosts.

All regressions pass, including the original two demos and their unchanged 5/21 weapon counts. A dedicated BW02 suite covers every value/operator, precedence, static and dynamic errors/source lines, quote-aware comments, immutable scanner assignment/indexing/timestamps, short-circuit/no speculative scans, all scalar switch types/nesting/default/no fallthrough, constant labels, expressions in both tanks' actual asynchronous actions, exact acceptance A/B/C programs on both tanks, best-effort inside a branch, independent environments, Stop/reset, safe input cleanup, cycle counters, bounded output, mixed IDE history and editor indentation. Production server tests run independent scanner-assignment/if/print/movement programs on both tanks with private-only output and no public variable leakage. Legacy invalid-source tests were updated only for constructs now intentionally legal (expressions/assignments/scientific literals/variable boolean arguments); gameplay checks remain. 59 sources compile; both Rojo place formats and whitespace checks pass. Studio still required for native editing/caret/tab/paste/focus, scrolling/current-line display, two-client print privacy, conditional branches during real recoil/terrain/collision/heat, cooldowns and cancellation mid-action. Nothing committed or pushed.

## Unique tank identities in scanner results (2026-11-08)

The fourth public Scanner field now identifies the tank, using `player_name.tank_name#stable_tank_id` rather than player name alone. `DirectionalScanner.identity` uses an optional instance tankName (defaults to the model/type name) plus the existing authoritative tank-record ID. Those IDs are unique keys in the current game's tanks map and survive switching and battle reset; future multiple same-type tanks must likewise be assigned distinct record IDs. Unowned/name-unavailable tanks use `AI.tank_name#stable_tank_id`. The field remains an opaque string; the five-element array and affiliation/bearing/range are unchanged. Server scene records now carry the tank name as well as owner name/ID. Exact identities still go only to the requesting IDE/runtime, not public sensor reactions.

Tests cover actual returned identities, unowned fallback, two same-owner/same-type records with distinct IDs, movement/reset stability and optional instance names. All regressions and both Rojo builds pass. Nothing committed or pushed.

## Independent sensor cooldowns and overhead header (2026-11-08)

The user clarified that cooldowns belong to each physical sensor, not the tank as a whole. `ScannerGeometry.sensorIndex` provides the common nearest-45° channel mapping for queries, manual warning coalescing and client presentation. `DirectionalScanner` now tracks eight independent `sensorScanTimes`: a .1-second cooldown on one channel does not prevent calls through another, even at the same simulation timestamp. Equivalent/wrapped/nearby angles cannot evade a single channel's cooldown. A shared performance budget remains (64 queries/sec, burst 16); it is a server workload bound, not a shared sensor cooldown.

`ManualScanner` replaces its global sweep clock/angle with eight independent slot timers and sub-cone phases. Each polls every .4 seconds and checks center, +15°, -15° around its 45° sector, giving full 360° coverage over about 1.2 seconds. One slot cooling/blocked never stops the other seven. Mode transitions/reset clear scheduler slots; BW handoff clears preceding manual channel timestamps as before. Existing 3-second warning retention, eight-event public bound, occlusion, private BW history and CPU accounting remain intact.

The user briefly requested doubled range, then explicitly withdrew that change after recognizing a geometry issue. **Range remains 150 studs**. No wider cone or through-wall detection was introduced.

Overhead health/damage banners move from a 6- to a 10-stud offset above the chassis. Text/track backgrounds now have .65 transparency; the HP fill has .25 transparency. HP text, damage and combat behavior are unchanged.

All checks pass (55 source compilations; scanner/value/runtime suite 122 assertions), including concurrent eight-channel queries, same-channel and wrapped-angle cooldown enforcement, independent manual slot timing and full sub-cone coverage, plus all prior regressions. Both Rojo builds and whitespace checks pass. Studio should verify the faster independent sensor reactions, shared-budget behavior under load and raised translucent headers at the normal camera distance. Nothing committed or pushed.

## Automatic manual scanning and visible indicators (2026-11-08)

The user explicitly authorized continuous scanner operation **for manual drivers**. `server/ManualScanner` schedules the selected, living, non-BW tank through the same `DirectionalScanner.execute` service: one 15° cone every .12 simulated seconds, sweeping 360° in about 2.9 seconds. Fixed-step scheduling avoids long-term drift and catches up without a query burst after delays. Busy/over-budget attempts advance the sweep without publishing fake empty readings. BW queries get first use of the shared budget each tick. Automatic scans do not create runtime values, charge BW cycles or produce private BWOutput/IDE history.

Manual public reactions hold at most eight coarse warnings, one per physical indicator, for up to 3 seconds. An empty neighboring cone cannot erase a stronger recent enemy; rechecking the original angle can replace it. This bounds snapshot traffic instead of replicating every sampled direction separately. Unselection, destruction and active BW clear these manual reactions. BW start also clears old visual data and waives the immediately preceding manual per-tank query timestamp so the first explicit instruction can execute; the shared server budget remains enforced. Reset clears sweep scheduling/angle with existing tank state. Stopping/finishing BW resumes manual sweeps on the selected tank automatically.

`ScannerVisual` lenses grew from .5 to **1.3 studs**, reaching **1.6 studs** with Neon during active readings. Mounted arms/posts and larger sockets position them outside the turret (radius 4.2 Boomer / 3.8 Rattler). The client combines recent directional reactions, choosing stronger enemy indications without querying the scene. Each cached reading's timer runs locally even under a stale snapshot; expired entries remain tombstones until removed/replaced, preventing old packets from restarting a pulse. Death greys the enlarged lenses and clears glow.

All checks pass: 55 sources compile, renderer/server suite 5,610 assertions, scanner/value/runtime/manual suite 77 assertions, all other regressions. Coverage checks complete sweeps/query spacing, no automatic BW/unselected/dead scanning, eight-warning replication bound, neighbor-warning retention/original-angle clearing, busy-scan behavior, larger indicators, multiple simultaneous warnings, stale-packet expiry, production manual→BW→Stop transition and no automatic IDE-output flooding. Both Rojo formats build and whitespace checks pass. Still requires Studio verification of manual sweep readability, mounts/lens visibility at 135-stud camera distance, LOS/occlusion, continuous warning colors while driving, tank switching/death/reset and shared-budget load with multiple drivers. Nothing committed or pushed.

## Complete IDE scan history (2026-11-08)

The IDE now retains every completed Scanner result in a run, including tank, wall and empty observations, in a chronological scrollable output pane with source line and measurement time. The output occupies the bottom quarter of the responsive editor, supports both scroll axes and follows new output only while already at the bottom. Scrolling back is preserved across status/progress updates. Each tank retains its own history through selection and Stop; a new Run or reset clears it. History is naturally bounded by BWConfig.MaxInstructions (128), not an arbitrary latest-reading limit. Cached formatted history avoids rebuilding every row during each render tick.

Added a stable bwRunRequestId alongside the existing monotonic bwRequestId, so a Stop acknowledgment no longer discards the current program's earlier readings. The server private-output callback labels readings with this run ID; request ordering/validation and runtime control behavior are unchanged. The client rejects delayed output from an earlier Run and clears stale generation logs. MaxIDEReadings was removed from ScannerConfig.

All checks and both Rojo formats pass. New tests retain tank→wall→empty output after Stop, preserve all 128 potential scan readings, exercise scrolling/auto-follow without dragging the reader back down, clear on new Run, reject late prior-run results and clear on reset. Studio still needs to verify native wheel/touch scrolling, long horizontal lines, output layout on small viewports and live history while switching tanks. Nothing committed or pushed.

## Universal explicit directional scanner (2026-11-08)

This explicitly lifts the earlier sensor deferral for **`Scanner(angle)` only**. No variables, expressions, loops, conditions, tracking or targeting were added. The existing parser accepts case-sensitive Scanner with a required finite numeric literal (including scientific notation), modulo-360 normalization and the shared optional best_effort keyword. Existing command syntax/semantics remain unchanged.

- `shared/ScannerConfig`: 15° horizontal cone, range 0–150, origin tank position + (0,2.5,0), surface pruning tolerance .002, bounded spatial/candidate/ray counts (256/64/192), 0.1-second per-tank query spacing, shared 24/sec rate with 8 burst, informational ScannerCost=5 and 1.2-second visual decay.
- `shared/ScannerGeometry`: clockwise chassis-relative directions/bearings; clips six oriented box faces against the cone's two vertical planes, including edge-only overlap, and derives nearest/edge/interior probe points. Real raycasts confirm actual physical surfaces, preventing bounding-box corners from inventing curved-cover visibility. Probing curved/complex surfaces is bounded, not an exhaustive tiny-aperture solver. Scalar range/bearing values use the actual ray hit with full precision; there is no noise or center-bearing substitution.
- `shared/BWValue`: frozen five-element values with an explicit frozen Null sentinel (Luau cannot store trailing nil array entries); logical zero indexing through get(). Observations retain timestamp, own scanner origin/yaw and value, all frozen/native immutable. Runtime keeps lastValue, lastObservation and bounded results history for future value-consuming language support.
- `server/DirectionalScanner`: one synchronous observation against the authoritative arena geometry allowlist, nearest-hit selection, own-body/cosmetic/projectile exclusion, team classification and strict per-tank/shared budgets. Failed/throttled/over-budget scans return errors and follow best_effort; they never masquerade as empty observations. Queryable walls/cover/practice targets count as walls. Floor and current non-queryable wrecks are excluded. Active tanks default enemy even if they share an owner in this local PoC; explicit matching non-nil record.teamId enables teammate classification. Names use player.Name with stable tank ID fallback.
- `BWRuntime` accepts trusted services.scan/onValue/chargeCycles. Scanner executes once, returns the structured observation, charges informational cycles and advances through the usual neutral release tick. No waits or passive queries. The optional cycle hook does not enforce a budget. `BWController` installs per-record services via the existing start path.
- `server/init`: collects all inputs/BW observations before movement, keeping scans tied to a consistent completed fixed-step simulation timestamp and synchronized hitboxes. Existing regression physics paths still run unchanged afterward. Exact formatted results/timestamps go through a private BWOutput FireClient to the owner. Public tank snapshots carry only an expiring decoration reaction (serial, requested angle, kind/affiliation, three coarse proximity levels), without target ID/name, exact range/hit point or velocity. Existing global render snapshots are unchanged; this is not a fog-of-war redesign.
- `client/BWIDE`: private per-tank/per-generation/per-request result cache; displays the latest array with measurement time after completion/Stop, clears stale outputs on new Run/reset and preserves source switching. Run still closes the editor. `client/ScannerVisual` adds eight harmless body-mounted lenses; completed scans alone trigger amber/red proximity trembling, cyan teammates, grey walls or empty blue pulses, fading to idle. No world queries or hidden-position knowledge in presentation. Death clears reaction/glow; reset/replacement destroys all decorations and stale result generations.

Verification: 54 Luau sources compile; all regressions pass. Scanner fixtures analytically intersect oriented boxes/ellipsoids and cover normalization (including tiny negative/exponent literals), chassis rotation, true bearings/ranges, cone-edge bodies, rounded-cover real-surface confirmation, walls/near tanks occluding farther tanks, iteration-independent selection, empty/range endpoints, airborne/moving/reversing/firing origins, name/team fallback, cosmetic/projectile/self exclusions, immutable values/time snapshots, per-tank/global/scene budgets, explicit one-shot runtime execution, cancellation/death, best-effort and cycle hooks, IDE privacy/reset. Production entrypoint tests verify both tanks can independently scan, private owner-only delivery, no precise reading in public status/reactions, expiry, Stop and reset. Renderer tests verify lens noncollision/nonqueryability, direction selection, near-enemy red/tremble amplification, teammate/wall/empty colors, local decay without fresh snapshots, grey wreck cleanup and model destruction.

The growing mock fixtures exceeded Luau Web's fixed heap. `scripts/check.mjs` now runs isolated test groups in child processes (fresh VMs), retaining the existing Input/Camera group dependency; syntax compiles once and all checks still execute. This avoids retained mock GUI/event graphs from previous suites contaminating server tests. Both Rojo formats and whitespace checks pass. Studio still required for native overlap/raycast filtering, cone-edge and tiny/curved apertures, airborne/terrain LOS, scanner lens readability/tremble/decay at actual camera distance, two-client private output and concurrent-program performance. No automatic target tracking or real CPU enforcement. Nothing committed or pushed.

## Larger bullet holes (2026-11-08)

`DamageEffectsConfig.BulletHoleScale=2` doubles the diameter of bullet holes and their scar rims, including those retained on wreckage. Thickness, placement, count, attribution and combat behavior are unchanged. Existing checks and both Rojo formats pass. Nothing committed or pushed.

## Stronger victim rattling (2026-11-08)

Rattler-injury panel jolts, armor rocking, wheel wobble and tread shaking now use `DamageEffectsConfig.RattleVisualScale=2.5`, multiplying previous visible displacement/rotation by 2.5 in every injury band and during immobilization. This scales presentation only; status duration/recovery, audio volume, controls, authoritative movement/aim, firing and recoil are unchanged. Existing regression checks and both Rojo formats pass. Studio still needs to judge the exaggerated shake at normal camera distance. Nothing committed or pushed.

## Continuous smoke stream and larger puffs (2026-11-08)

Injury smoke now has an always-emitting engine plume while cannon injury is active, rather than intermittent wisps. Its separate invisible vent follows the rear deck; particles are world-space/unlocked, rise and drift for 1.2–1.8 seconds, and leave a trailing stream when driving. Rate is 8 plus injury severity per second. The occasional dense whole-turret burst keeps the existing authoritative episode/recovery schedule, but its emission volume and particle sizes are scaled by **1.2**. `SmokePresentation.StreamRate` and `BurstScale` centralize the new settings. Recovery clears only the dense blanket, leaving the lighter stream visible. Reset/death destroys both source volumes and emitters.

All regression suites pass, including checks for a continuous stream during burst recovery, unlocked trail particles and exactly 20% larger puff bounds/sprites. Both Rojo formats build. Studio is still needed to judge plume density, trail length and enlarged puff coverage while driving. Nothing committed or pushed.

## Soft whole-turret smoke (2026-11-08)

The user rejected the hard black spheres and muzzle-only smoke placement. `client/SmokeVisual` replaces injury smoke with two native ParticleEmitters (dense blanket and intermittent wisps), using the built-in soft `smoke_main.dds` texture, grey color gradients, transparent birth/death edges, expanding sprites, random rotation and upward drift. One invisible noncolliding/nonqueryable box follows the complete molded turret bounds (`ArmorSize` metadata plus padding), lowered slightly to encompass the turret base as well as sides/roof. Box-volume emission distributes smoke across that entire region; it no longer originates at the cannon tip. Particles lock to this moving volume during the episode. Dense bursts prefill once with 28 particles and emit at 48/second with at most 1.1-second lifetimes; the dense population stays below 100 particles per tank. Wisps are a separate low-rate emitter. Server schedules and all controls/aiming/physics remain unchanged.

`DamageEffectsConfig.SmokePresentation` centralizes texture, volume padding and emission budgets. On the server's burst end, emission stops and dense particles clear immediately; severity reset/death removes the volume and both emitters. Recreation resets cached styling. Cannon impact smoke and the large explosion's grey smoke also reuse soft textured bursts; orange fireball/shockwave effects are preserved. No uploaded assets or image generation needed.

All regression suites pass with 49 source compilations. Renderer tests cover full-turret coverage on both vehicles, following movement/aiming, soft fade/expansion and drift properties, one bounded initial fill per episode, clear/recovery, styling after recreation, invisible/query-free volume and reset/destruction cleanup. Both Rojo place formats build. Native particle rasterization is not emulated by the tests: Studio must verify texture rendering, cloud density/readability at the normal 135-stud camera, graphics-quality scaling, mobile particle budgets, complete turret coverage while moving and dense-to-recovery transitions. Nothing committed or pushed.

## Progressive attributed injuries and weapon-selected deaths (2026-11-08)

This supersedes the universal-explosion notes below. `TankDefinitions` now labels weapons `Cannon` / `Gatling` without changing tuning. Projectiles capture that ID at launch; the impact path passes it, actual applied damage and hit position to `LocalBattle.damage`. `shared/DamageEffects` accumulates `state.damageByWeapon`, serial/last-impact fields and `fatalWeapon`; overkill never inflates history. Unknown future weapon IDs can accumulate history without assuming an existing effect. The profile registry is `DamageEffectsConfig.Weapons`; no future weapons or BW syntax added.

Severity bands use 50/25/10 remaining HP. Each band (1/2/3) is multiplied by that effect's share of all applied damage; smoke and rattling can coexist with proportionate strengths. Episode durations are band-specific (smoke 1/1.5/2 seconds, rattling .3/.6/1) multiplied by that damage share. All status tuning lives in `shared/DamageEffectsConfig`. A per-record server ledger advances once per fixed tick before BW and simulation; flat severity, serial, active and remaining-duration fields replicate in existing 20 Hz snapshots. Hits do not refresh episodes. Minimum recovery is 3 seconds for rattling and 3.5 for smoke, with longer mild-tier windows and deterministic small interval variation. Destruction clears all active statuses immediately; reset creates a new empty attribution/schedule state.

`TankSimulation.step` masks only throttle/steer while immobilized, cloning the input so held manual intent resumes after recovery. Turret/fire, existing friction/coasting, airborne momentum and recoil remain intact. `BWRuntime` preserves instruction/targets and tracks actual displacement/rotation while waiving instruction/stuck time during immobilization for at most eight total seconds per movement/chassis-turn instruction. It never counts unfinished moves as completed. Turret/fire instructions continue normally. The existing overall 180-second cap, instruction limits and best-effort behavior still bound execution.

`client/DamageVisual` delegates smoke to `client/SmokeVisual` (see the latest whole-turret particle update above) and owns bounded perforation scars (maximum 36 paired discs), panel rattle, wheel/tread wobble, impact puffs/sparks and short built-in sputter/clatter audio. Visual noise never changes state/muzzle aim. Dense clouds follow server episode flags and expire immediately when the burst ends; wisps remain intermittent. Smoke is world-space and visible to every client, with no full-screen/UI overlay or artificial BW blindness. There is no BW sensing or smoke LOS implementation yet; replicated injury/episode data provides a future integration point.

`TankCombatVisual` chooses fatal behavior from the weapon profile. Cannon preserves its large fireball/shockwave and ballistic turret/wheel breakup, now also ejecting both Boomer track-belt assemblies. Gatling instead gives a short violent shake, lets the perforated turret/wheels/tracks drop apart, sinks the chassis onto its belly and plays one final clink; no fireball. Scars follow their host parts as those fall. Both remain grey solid wrecks. Transient effects and persistent marks are model-owned folders; death stops injury smoke/audio immediately, and normal generation reset/disconnect destroys all visuals without extra connections.

Verification: 48 Luau sources compile; all existing regression suites pass. Added status tests cover attribution/mixed injury, all HP bands, exact durations/expiration/recovery, repeated-impact anti-stun-lock, input filtering/airborne momentum, movement/chassis-turn grace/resume, turret/fire availability, bounded repeated immobilization, best-effort, fatal attribution and reset. The production server harness checks actual projectile attribution, independent owners' injuries, scheduled immobilization duration, manual movement suppression with aim/weapon activation retained, automatic recovery and reset/death cleanup. Renderer tests exercise dense smoke and nonqueryability, bounded scars, invariant muzzle/physics, weapon-specific collapse without explosion, belly drop, scars following detached parts, final clink and cleanup. Both Rojo builds and whitespace checks pass. Still requires Studio: meaningful smoke obstruction/readability, sound quality, episode fairness, both victim models/weapon finishes, native collisions, two-client visibility/latency, manual vs BW behavior under repeated hits, and repeated reset during active effects. This is no claim of Studio playtesting or established balance. No commit or push.

## Spectacular destruction (2026-11-08)

`client/TankCombatVisual` now presents death as a large 24-stud fireball, 40-stud ground shockwave, 16 fiery bursts, eight rising smoke clouds and a low-pitched built-in landing thud. The transient effect folder belongs to the tank model, expires after 2.5 seconds, and also disappears immediately when the renderer is destroyed/reset. No new assets, server explosions, physical debris or combat changes.

Breakup uses existing renderer parts and anchors: turret/barrel/rotor parts form one flying assembly; Boomer road-wheel/hub/axle details form eight wheel groups, while Rattler’s wheel anchors keep each complete tire/spoke/hub assembly together in four groups. Captured world frames are rotated around group centers and offset along analytic ballistic arcs, followed by a short damped landing bounce and a stable scattered resting pose. This runs in the existing renderer update without extra event connections. Attached parts no longer visually remain on the hull. The entire vehicle becomes solid neutral grey (dark grey tires/treads), including detached assemblies; cannon swell helpers stay hidden. Newly observed already-dead tanks appear as settled wrecks without replaying explosions. Normal reset destroys the model and all attached debris, restoring paint/parts through generation rebuilding.

All regression suites pass (45 sources compile; renderer/server suite 4,956 assertions). Coverage checks grey opaque wrecks, one burst per death, whole turret/wheel group counts for both tanks, dramatic upward travel and wheel scatter, settled motion, non-queryable/noncolliding blasts, restoration of paint and destruction cleanup. Both Rojo formats build and whitespace checks pass. Studio is still needed to judge camera-distance spectacle, the audio, wheel/turret tumbling and terrain intersection; the debris is cosmetic and uses the tank’s actual local support height for its landing plane rather than engine physics collisions. Nothing committed or pushed.

## BW editor focus follow-up (2026-11-08)

Run now calls `BWIDE:close()` before submission: releases native TextBox focus and hides the editor panel. The tank selector also closes the editor before requesting selection, ensuring its overlay/text focus cannot block manual gameplay on the other tank. The authoritative ownership rules and snapshot-selected BW input lock are unchanged: only the selected running/destroyed tank suspends manual providers. Reopen BW Editor to inspect output/errors or Stop.

Regression coverage exercises Run, editor focus release, selection, fresh keyboard W/mouse aim/fire, continued independent BW execution, and returning to BW input lock in both Boomer-to-Rattler and Rattler-to-Boomer directions. All checks pass (45 source compilations; local battle/IDE suite 38 assertions); both Rojo formats build. Native GUI focus and event processing still need a Studio check after reopening the rebuilt place. Nothing committed or pushed.

## Current local combat PoC (2026-11-07)

This section supersedes the historical single-tank/respawn/selection notes below. Each connected player owns **two persistent records**: Bullet Boomer (`tostring(UserId)`) and Rattler (`UserId .. ":Rattler"`). `server/LocalBattle` owns pair selection, spawn/reset poses, damage and winner lifecycle; it does not implement movement or weapons. All records run through the existing fixed-step simulation, terrain/target/tank collision and projectile code. The pair spawns inward-facing, separated by up to 44 studs within actual map bounds. Each player's local pair fights itself; other players' pairs cannot damage or command it. This is a solo combat test, not matchmaking or teams.

Selection changes only the pair's selected ID. It clears departing/arriving manual inputs and unreleased manual preparation, but preserves poses, generations, HP, cooldown/heat, recoil/momentum and running BW runtimes. Idle unselected tanks still simulate, coast and land. BWRun/BWStop and Input carry explicit stable tank IDs; server ownership checks reject foreign IDs and stale manual packets for unselected tanks. BW may address either owned tank independently. Runtime, request sequencing/rate limiting and cleanup are per record; no BW language changes.

Snapshots carry all tank states plus a separate per-owner map of selected ID and winner. The client follows the selected record using the existing camera, speed/debug and controls. Both renderers remain alive when switching; reset increments generation and reconstructs visuals using the existing registry. `BWIDE:bind` retains source and pending acknowledgments per tank. Starting a program on one tank, selecting the other, and starting another program runs both through the same authoritative input loop.

Both tanks have 100 HP. The projectile impact path routes 25-damage Boomer shells and 6-damage Rattler rounds through `LocalBattle.damage`; no self damage or repeat damage after zero HP. Existing swept collisions, trajectory, damage rates, muzzle/recoil effects and practice targets remain unchanged. Zero HP stops BW, clears all input/pending fire, disables further hit queries and leaves a visible wreck. `client/TankCombatVisual` presents overhead numeric HP/bar and one expanding cartoon burst per death; no damaging Explosion or physical debris. Winner is reported in the main HUD. Already-released shells continue and can cause a double-KO Draw.

**Reset Battle**, below BW Editor, clears the owner's pair's shells, stops both programs, restores HP/spawn headings, fresh deterministic weapon/recoil/suspension/telemetry state, queryable hitboxes and neutral input with a fresh trigger release. The selector and editor sources persist. Map redraw uses the same reset lifecycle for all pairs and retains existing practice-target rebuilding behavior. Disconnect removes both records/hitboxes and stops both programs. There is no automatic tank respawn now. Legacy `shared/TankSelection` remains unused by the production server; it describes the earlier type-replacement experiment.

Verification: 45 sources compile; all regression suites pass, including production server checks with two mocked owners, live pair state/BW isolation, firing rates, damage/KO/wreck/reset, stale request ownership, hitbox synchronization, map redraw and departure. `tests/Battle.spec` adds local lifecycle and independent editor-source coverage; renderer tests cover numeric/bar HP, a single bounded destruction burst and visible wrecks. Both Rojo formats build and whitespace checks pass. Engine sweeps and GUI/layout remain mocked. Studio checks: select while driving/preparing/firing/airborne and during BW; run BW on both and Stop only one; visually shoot both tanks and terrain/targets; confirm one death effect/winner/wreck; reset during recoil, cooldown and active projectiles; verify original camera distance policy, touch/gamepad controls, HP readability, source switching, network latency and pair ownership with two clients. Nothing committed or pushed.

## Start here in a future session

1. Read this file, the README, `default.project.json`, and any applicable `AGENTS.md` instructions present in that session.
2. Inspect the current source and `git status` before editing. The repository now has tracked files and commits; the earlier handoff recorded an untracked starting state, which is no longer current. Preserve existing user changes and do not discard new/untracked modules. This camera update has not been committed, published, or deployed; do not infer any remote/publication state from a successful local build.
3. Preserve desktop controls, the shared input contract, server-authoritative gameplay, and the separation between simulation, input, and rendering.
4. Keep compatibility with **Rojo 7.7.1**, pinned in `rokit.toml`.
5. **BW v0.2 is explicitly authorized and implemented.** Variables, expressions, conditional/switch branching and explicit Scanner values are supported. Loops, custom functions, automatic tracking/targeting, extra/passive BW sensors, parallel actions and arbitrary Luau remain out of scope.
6. Do not claim Studio or Android play testing has passed. The checks so far are builds, compilation, and mocked tests, not Roblox runtime execution.
7. After gameplay changes, run the checks below, rebuild both place formats, and update the relevant documentation. The latest gameplay update replaced the tank-follow camera with a modular fixed-world Battlefield Camera; its runtime visuals remain unverified.

## What this game is

BattleWorks is currently a Roblox Luau tank-combat prototype: one controllable tank per connected player in a flat practice arena. It supports solo target practice and the code paths for multiple player-owned tanks. It is not yet a complete competitive game.

The first requested milestone was one working controllable tank with a chassis, two tracks, rotating turret, and cannon. The second added Android touch controls, runtime input preferences, gamepad support, and an input relay/debug display. Future BW autonomous programs motivated the input abstraction, but no autonomous controller or BW execution exists yet.

There are no rounds, teams, matchmaking, score, progression, inventory, account saves, custom assets, sounds, or monetization systems. There is no known published Roblox experience ID or external backend in this project. The game uses Roblox networking and primitive parts; the place needs no external runtime packages.

## Gameplay and arena

- Each player owns one server state and an invisible anchored hitbox. Normal character spawning is disabled using `Players.CharacterAutoLoads = false`.
- Tanks move on the XZ plane at Y = 0, turn in place, reverse, and aim independently of chassis direction.
- Firing launches slow server-simulated shells at 24 studs/second. There is no gravity/drop, splash damage, ammo limit, or reload magazine. Holding FIRE repeats shots at the cooldown.
- Tanks and targets have 100 health; a hit deals 25 damage. Four successful hits destroy a full-health target/tank.
- Destroyed tanks appear translucent and respawn at their assigned initial position after three seconds, with fresh state and a neutral command.
- Five orange targets stand at X = -36, -18, 0, 18, 36 and Z = -65. Their size is 7 × 7 × 5 studs, centered at Y = 3.5.
- Targets reset three seconds after destruction. Their `Health` attribute is updated; destroyed targets become mostly transparent and stop participating in ray queries.
- Four anchored boundary walls are centered at X or Z = ±118, with height 6 and thickness 4. The baseplate top is at Y = 0.
- Player spawn positions use eight columns spaced 13 studs apart and four repeating rows starting at Z = 35. They are assigned by join order, not player choice.
- On player departure, the server removes their hitbox/state; subsequent snapshots remove their visual tank on other clients.
- The HUD shows health and Ready/Reloading/Respawning status. The Battlefield Camera uses a fixed 50° elevation / 45° counterclockwise world azimuth. Maps are fully framed only when tank readability permits; otherwise they pan immediately at a central 20% dead-zone boundary. See the camera section below.

### Current tuning

Most values are in `src/shared/TankConfig.luau`. Durations for respawn/target reset, input send rate, and some geometry/animation values are currently hardcoded elsewhere.

| Setting | Value |
| --- | --- |
| Drive speed | 24 studs/second; immediate throttle response |
| Chassis turn speed | 1.8 radians/second |
| Turret yaw speed | 3.5 radians/second |
| Turret pitch speed | 1.1 radians/second |
| Pitch range | -12° to +30° |
| Collision radius | 5 studs |
| Arena limit | 115; center clamped to ±110 after radius allowance |
| Health | 100 |
| Shot damage | 25 |
| Shot cooldown | 0.65 seconds |
| Shell range / speed / collision radius | 320 studs / 24 studs per second / 0.65 studs |
| Simulation step | 1/60 second |
| Snapshot interval | 1/20 second |
| Client input send interval | 1/30 second |
| Accepted input packet spacing | At least 1/60 second per player |
| Stale-command timeout | 0.35 seconds |
| Tank respawn / target reset | 3 seconds |

## Controls and settings

### Keyboard and mouse

W/S drive forward/reverse. A/D turn left/right, including while stationary. The mouse aims at its ray intersection with the horizontal plane at cannon height (Y = 3.6). Hold left mouse button to fire.

Desktop uses world-position aiming and keeps cannon pitch at zero. Its original movement and aiming conventions were deliberately retained. Input ignores processed begins, clears held keys when a text field gains focus, and releases on focus loss. Mode gating prevents inactive keyboard/mouse input from leaking into touch/gamepad commands.

### Android / touch

The requested layout is intentionally **LEFT = turret** and **RIGHT = drive**. Do not silently swap it to the more common movement-left layout.

- Left stick: X controls turret yaw; up/down controls cannon pitch. This is angular-rate input. Releasing holds the last turret orientation.
- Right stick: up/down controls throttle; left/right controls steering. Turning does not depend on forward/reverse direction.
- Large central FIRE control: press and hold. A finger may drag off the button and remain held until end/cancel; it does not transfer to another control.
- Every captured `InputObject` belongs to exactly one control. Each stick and FIRE has independent ownership. A second finger cannot steal an occupied control. Three fingers can operate all controls concurrently.
- Stick travel is radially clamped and normalized. Each stick has its own configurable dead zone, passed from `InputController` to `TouchInput`; both default to 0.15. Travel outside the dead zone remaps to the full output range.
- End/cancel clears just the owning control. Mode switches, window focus loss, text entry, Roblox menus, and layout resize clear held inputs. Returning requires a fresh press.
- Cancel is handled through captured InputObject state changes; release outside the widget is handled by `UserInputService.TouchEnded`. Movement uses `TouchMoved`.
- Local FIRE clears immediately on release. Server response still waits for the next input packet plus network/server latency; there is no separate immediate-fire network channel.

Mobile starts in `LandscapeSensor`, allowing both landscape rotations. The HUD uses `ScreenInsets.CoreUISafeInsets`. Sticks fit the safe-area dimensions, capped at 170 pixels; FIRE is capped at 96 pixels. Controls have a 16-pixel edge margin. The relay panel fits above FIRE in the gap between sticks, with text shrinking on short screens. Orientation/size changes release touches instead of teleporting held input across the layout.

The debug panel is visible with active touch controls and uses this format:

```text
INPUT: Touch
THROTTLE:  +0.82
STEERING:  -0.14
TURRET X:  +0.35
TURRET Y:  -0.20
FIRE:      TRUE
```

These are **local command values**, sampled every render frame for transmission at 30 Hz. They are not server acknowledgments or a readout of authoritative tank state.

### Input preferences

The top-right Input button cycles `Auto → KeyboardMouse → Touch → Gamepad → Auto`. It is a selectable GUI button for gamepad navigation as well as click/tap.

Auto uses `UserInputService.PreferredInput` and its property-change signal. **Do not replace this with `TouchEnabled`:** touchscreen laptops should retain desktop controls while keyboard/mouse is preferred. Explicit preferences ignore changes in PreferredInput until Auto is selected again. All transitions reset providers and send neutral intent.

Preferences are session-local and reset to Auto on rejoin. No DataStore/device identifier is implemented. Future account-level persistence and genuinely per-device persistence are separate design decisions; do not claim either already exists.

While Touch is selected, the controller disables the stock PlayerModule movement controls and hides the stock `TouchGui` only. It records previous enabled states and restores them on leaving Touch. It does not disable menus/chat/other CoreGui. PlayerModule acquisition is asynchronous with a 10-second module wait and warning fallback; default TouchGui hiding still works if module acquisition fails. This integration depends in part on stock PlayerModule implementation details, including `controlsEnabled`, and needs real-runtime verification.

Window blur, text focus, and Roblox menu opening suspend the selected adapter and send neutral input. Closing/resuming reactivates it without restoring held presses. Default movement remains suppressed while Touch is selected, even when its custom overlay is temporarily suspended.

### Gamepad

Gamepad1 only: left stick drives, right stick rotates/elevates the turret, R2 fires above a trigger threshold of 0.2. Both sticks use a 0.15 radial dead zone. Disconnect clears values. Extra gamepads, binding customization, haptics, and polished controller settings navigation are not implemented or runtime-verified.

## Architecture and file map

| File | Responsibility |
| --- | --- |
| `default.project.json` | Rojo DataModel mapping, baseplate/lighting/sound defaults, mobile orientation |
| `rokit.toml` | Pins Rojo 7.7.1 |
| `src/shared/TankConfig.luau` | Frozen gameplay tuning table |
| `src/shared/InputCommand.luau` | Neutral intent and validation/clamping used at the server boundary |
| `src/shared/TankSimulation.luau` | Instance-free state math, movement, turret integration, cooldown, firing eligibility/origin/direction |
| `src/server/init.server.luau` | Arena/target creation, ownership, remote handling, simulation scheduling, collision, hits/damage, lifecycle, snapshots |
| `src/client/init.client.luau` | Network reception/send loop, renderer lifecycle, camera orchestration, HUD, controller setup |
| `src/client/BattlefieldCameraConfig.luau` | Camera orientation, competitive view/footprint policy, map metadata, zoom and dead-zone tuning |
| `src/client/CameraMath.luau` | Pure projection/framing, ground trapezoid, rotated-map clamping, dead-zone projection and discontinuity math |
| `src/client/BattlefieldCamera.luau` | Roblox camera CFrame/Focus/FOV ownership, safe-area bars, snapshot tracking and camera replacement |
| `src/client/InputController.luau` | Preferences, provider activation/reset, settings button, suspension and stock-control coordination |
| `src/client/KeyboardMouseInput.luau` | Existing desktop adapter |
| `src/client/TouchInput.luau` | Touch UI, independent capture ownership, analog sampling, relay display |
| `src/client/GamepadInput.luau` | Gamepad1 adapter |
| `src/client/Analog.luau` | Radial dead-zone remap and circular clamping shared by touch/gamepad |
| `src/client/TankRenderer.luau` | Local tank geometry, smoothing, track animation, recoil/wobble, muzzle-flash effects |
| `scripts/check.mjs` | Node development runner: compile sources, bundle modules with mock services, execute tests |
| `tests/RobloxMock.luau` | Minimal Roblox stand-ins for deterministic tests |
| `tests/Input.spec.luau` | Shared contract, simulation, adapters, transition/release and layout math tests |
| `tests/Camera.spec.luau` | Perspective math, footprint parity/cap, small/large/rotated/thin map framing/clamping, camera integration stand-ins |
| `README.md` | Build/open instructions, controls, architecture overview, runtime testing checklist |
| `CODEX_HANDOFF.md` | This detailed game/session handoff |
| `battleworks.rbxl` / `battleworks.rbxlx` | Generated Roblox place artifacts |

Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to `ServerScriptService.Server`, and `src/client` to `StarterPlayer.StarterPlayerScripts.Client`. The `init.server.luau` and `init.client.luau` files make Server a Script and Client a LocalScript; neighboring files become their child ModuleScripts. Preserve those paths or update requires accordingly.

Arena, targets, hitboxes, network events, tank models, and UI are created at runtime. A built place viewed before Play therefore does not contain the fully assembled gameplay scene. Tests and Node dependencies are outside the mapped tree and are not shipped to players.

### Data flow

```text
KeyboardMouse / Touch / Gamepad adapter
    → shared command intent
    → Input RemoteEvent
    → server rate limit + InputCommand.validate
    → TankSimulation.step + server collision
    → TankSimulation.tryFire + server raycast/damage
    → Snapshot and Shot RemoteEvents
    → client renderer / camera / HUD
```

Only the server advances gameplay state. Shared placement of the simulation module does not imply client authority. Input adapters never duplicate movement, cooldown, damage, or projectile logic.

A future BW controller can eventually generate the same intent on the server and pass it through the same simulation path. There is currently no registration API, scheduler, sandbox, parser, interpreter, or BW program storage.

## Shared input contract and coordinates

A command has these fields:

```luau
{
    throttle = 0, -- [-1, +1], positive forward
    steer = 0, -- [-1, +1], positive chassis left
    fire = false,
    aimMode = "Rate", -- "World" or "Rate"
    aim = Vector3.new(0, 0, -1), -- used in World mode
    turretX = 0, -- Rate: [-1, +1], positive right
    turretY = 0, -- Rate: [-1, +1], positive up
}
```

`Command.neutral()` uses Rate with all axes zero and fire false. This stops drive/turn input while preserving turret orientation, including during stale-command timeout. Do not replace it with a fixed world aim point that makes an idle turret rotate unexpectedly.

World mode projects aim to XZ. Missing `aimMode` is accepted as World for backward compatibility with the original desktop contract. Desktop explicitly selects World and simulation resets pitch to zero in that mode. Rate mode requires finite turretX/Y values; World mode requires a finite Vector3 aim. Extra client fields are not copied into authoritative state.

Validation requires numeric axes, a boolean fire value, a recognized aim mode, no NaN/infinity, and numeric magnitudes below 1,000,000. Relevant axes are then clamped to [-1, +1]. This finite-value helper intentionally also rejects extremely large finite numbers.

Yaw/pitch are radians. At yaw zero, forward is world -Z. Forward direction is `(-sin(yaw)*cos(pitch), sin(pitch), -cos(yaw)*cos(pitch))`. Chassis steering adds yaw; rightward turret input subtracts yaw. Touch screen Y points down, so adapters negate it for positive throttle/elevation. Confusing these sign conventions can silently reverse one mode.

Tank state contains `position`, `yaw`, `turretYaw`, `turretPitch`, `speed`, `health`, and `cooldown`. It contains no Instances. Spawns and respawns use `Simulation.new`.

## Networking and authority

The server creates `ReplicatedStorage.TankNetwork` with three RemoteEvents:

| Event | Direction | Payload |
| --- | --- | --- |
| `Input` | Client → server | Command table; Roblox supplies sender Player |
| `Snapshot` | Server → all clients | Table keyed by stringified UserId, each value a tank state |
| `Shot` | Server → all clients | Numeric shooter UserId, visual muzzle origin, authoritative endpoint |

The server looks up ownership from the sender's UserId. Clients do not submit a target tank ID, damage, health, position, shot direction, cooldown, or hit result. Incoming packets closer than 1/60 second to the prior processed packet are ignored; invalid packets do not refresh the last valid command timestamp. A valid command is used until it is replaced or exceeds the 0.35-second timeout.

Simulation uses a Heartbeat accumulator with 1/60-second steps and caps incoming frame time at 0.1 seconds. It does not attempt unlimited catch-up after a long stall. Snapshots are sent at roughly 20 Hz; the client renders smoothly between latest states using exponential smoothing. There is no client prediction, reconciliation, timestamped interpolation buffer, lag compensation, or retransmission/acknowledgment protocol.

Firing eligibility and cooldown are computed by the server. Raycasts start at turret center `(position + (0, 3.6, 0))`, exclude the shooter's hitbox, and extend 320 studs along authoritative yaw/pitch. Starting inside the turret prevents a protruding barrel bypassing nearby cover. The client receives a cosmetic muzzle origin seven studs forward; this is not the actual raycast start. Walls and other queryable geometry can block shots.

Server hitboxes are invisible anchored parts (8 × 5 × 10), rotated with chassis yaw and positioned at Y = 2.5. Dead tank hitboxes have ray queries disabled on the movement update. Rendered client geometry is anchored, noncollidable, nontouching, and excluded from ray queries. There is no reliance on client physics ownership for combat.

## Rendering and scripted animation

Tanks are generated locally from Metal parts: olive chassis and turret, dark left/right tracks, cannon, and seven top track shoes on each side. Local tank models are named `Tank_<UserId>`.

The renderer smooths position and angles with `1 - exp(-18 * dt)`. It scrolls track shoes with movement, applies a small sinusoidal chassis wobble, retracts the cannon during recoil, and adds a small recoil pitch to the chassis. Shot events set recoil to 1, which decays with `exp(-12 * dt)`. These effects do not change collision, aiming, or damage.

Muzzle flashes are Neon balls (0.06 seconds), cleaned up by Debris. Moving shells are replicated server models, removed on impact or range expiry; there are no laser tracers. There is no complex suspension physics, constraints, mesh rig, animation asset, or imported model.

## Battlefield Camera: policy, math, and integration

The previous camera had a fixed world offset but followed the rendered tank continuously. It is now replaced; do not reintroduce the old `(0,68,48)` follow offset in the client entrypoint.

**Direction convention:** +Y up, overhead view with -Z north/top and +X right. Azimuth measures the camera's position around the target: 0° on +Z, positive counterclockwise toward +X. At the configured 45° azimuth the camera sits on +X/+Z and looks toward -X/-Z. Elevation is 50° above the ground. `CameraMath.basis` constructs orthonormal forward/right/up vectors independent of chassis/turret rotation. Tank yaw convention remains unchanged and is different from this camera convention.

**Competitive visibility:** a centered opaque-masked 16:9 battlefield window gives all normal desktop/mobile aspect ratios the same perspective ground region. Symmetric safe-area padding takes the larger inset on each opposing side; this keeps the optical center at the physical viewport center. The window fits within that usable area. Physical `Camera.FieldOfView` is calculated from configured window FOV and window-height/fullscreen-render-height fraction. `Camera.ViewportSize` is device-safe size, not fullscreen size on a notched device; the integration uses `GetInsetArea(None).Max - Min` for rendering dimensions and ViewportSize for readiness/cache invalidation. Ultrawide screens get side bars; narrower screens get top/bottom bars. The HUD and touch controls render above bars, not underneath them. No input adapter or combat logic was changed for this policy. Desktop mouse aiming samples after camera update.

The configured 40° vertical FOV belongs to the competitive window, not necessarily the full device screen. Roblox's physical FOV is clamped to [1°,120°]. For extreme tall windows hitting that limit, effective window tangent is recalculated; the footprint remains capped and all fitting tests are rerun with that lens, but exact normal-device trapezoid parity can differ. Mobile is still landscape.

**Framing:** project every expanded map rectangle corner at ground and `HeightAllowance` into fixed camera axes. Given ground-relative point q, distance d, forward f, right r, up u, require positive depth `d + dot(q,f)`, `abs(dot(q,r)) <= depth*tanH`, and `abs(dot(q,u)) <= depth*tanV`. Solve the lower distance bound for every corner/height. Map corners are transformed by map center and Roblox-style yaw; rectangular/rotated maps are not approximated as an axis-aligned world square.

**Footprint:** intersect rays through all four competitive window corners with the map's horizontal ground plane. This is an asymmetric trapezoid relative to the optical-axis ground target. All offsets scale linearly with camera distance. `MaxGroundFootprint` is the largest pairwise distance between any of those ground corners, in studs. It is not a diameter around the tank, an AABB side, or an area. The 900-stud hard cap alone permits the current 230-square map to fit, but the stricter readability cap now forces pan mode.

Whole-map readability uses the full tank silhouette at the farthest playable map depth; follow readability retains a stricter chassis budget across the visible ground window. If the full-map fit distance (including margin and height allowance, raised to MinZoom) is under the maximum zoom, footprint and overview readability caps, lock focus to map center and disable panning. Otherwise use DefaultZoom clamped to MinZoom/MaxZoom and the safety caps. Narrow maps can reduce distance below the preferred minimum to avoid excessive empty side regions. There were no manual zoom controls; input continues to leave distance/orientation under this controller's ownership.

**Tracking:** the central **20%** of the visible battlefield window is the dead zone, from 40% through 60% of width and height. CameraMath explicitly projects the authoritative tank ground position into normalized screen coordinates. Inside the zone it preserves focus exactly. Outside, it projects the previous focus into the nearest valid ground-focus polygon that places the tank on the screen boundary. Correction is immediate, with no smoothing, speed limit or stop drift. Map-local optical focus is clamped to playable bounds when feasible; the oblique footprint may show outside ground near walls. Tank visibility takes priority if out-of-bounds state makes both constraints impossible.

Tracking has no time integration, so displacement is corrected independently of frame duration and tank speed. Missing tanks hold the last focus (map center at startup). Viewport/inset changes and replacement cameras recompute projection. First snapshots, respawn and large jumps still reset the cosmetic renderer pose through the existing observe path. No tank rotation, turret, recoil or wobble changes camera orientation. Renderer smoothing, input and authoritative simulation remain unchanged.

`init.client.luau` now uses `BindToRenderStep("BattleWorksFrame", Enum.RenderPriority.Camera.Value + 1, ...)`. Every frame sets `CameraType.Scriptable`, vertical FieldOfViewMode, calculated physical FOV, camera CFrame and Focus. Camera update precedes input sampling, preserving the world mouse aiming path. The desktop adapter now converts raw fullscreen mouse coordinates to core-safe coordinates before ScreenPointToRay; this fixes top-bar/notch aim displacement without changing control mappings or world-aim behavior. ProjectionType is set to Perspective through a protected call when camera/layout initializes; classic engines already default to perspective and do not need the newer orthographic-camera beta. Stock mouse/touch/gamepad camera actions cannot rotate/zoom this script-owned camera. GUI bars block new mouse presses on the masked region while HUD/touch overlays remain usable.

### Camera tuning defaults

| Field | Default / meaning |
| --- | --- |
| Elevation / Azimuth | 50° / 45° under the convention above |
| FieldOfView / AspectRatio | 40° window vertical FOV / 16:9 competitive window |
| MaxGroundFootprint | 900 studs maximum ground-corner separation |
| Margin / HeightAllowance | 8 studs / 8 studs, for full-map framing |
| MinZoom / MaxZoom / DefaultZoom | 45 / 260 / 100 studs camera-to-focus distance |
| MinTankPixels / ReferenceWindowHeight / TankReadableWidth | 18 px / 320 px / 6 studs (follow-mode far-ground chassis budget) |
| WholeMapMinTankPixels / TankSilhouetteWidth | 12 px / 8 studs (overview full-tank budget at farthest playable point) |
| SnapDistance | 40 studs between raw snapshots; respawn also snaps |
| TankViewInset | 0.20: central 20% of visible battlefield width and height |
| MapCenter / MapSize / MapYaw | `(0,0,0)` / `2*TankConfig.ArenaLimit` in each axis / 0° |

`BattlefieldCameraConfig` metadata must match actual gameplay geometry. Rectangle/yaw support belongs to camera math; the server still builds the original square arena. Changing camera metadata alone does not change the map or movement bounds. The layout is cached by viewport, inset and Camera object. Studio dimension overrides invalidate it immediately; restart Play after editing other source tuning. Invalid FOV/elevation combinations whose visible window crosses the horizon fail an explicit math assertion rather than creating unbounded ground intersections.

The camera is modular, but masks are a client viewing policy, **not server-enforced fog of war**. Existing full-state broadcasts remain unchanged. Bars reduce usable pixels on mismatched screens; GUI overlap/readability and projection/inset behavior need real visual testing. The test mocks do not reproduce Roblox rasterization, ScreenPointToRay, actual safe-area units, stock camera/input scripts, VR behavior, network jitter or device gestures. No publication or device testing has occurred.

Camera tests cover 16:9, ultrawide, 4:3, narrow landscape, portrait and extreme tall viewports; safe insets; translated/rotated rectangles; map-center lock; ground-ray projection; diameter limits and competitive parity; large-map edges/corners; thin-map containment; exact dead-zone correction and hold; teleports/respawns; and mocked controller CFrame/Focus/FOV/camera-replacement behavior, full-render versus device-safe notched-screen sizes, legacy projection API compatibility, and desktop ray coordinate conversion. See the README camera runtime checklist for pending Studio/Android/multiplayer validation.

## Collision and implementation caveats

These are code-review observations and prototype limitations, not newly verified runtime bugs:

- Movement is direct kinematic state integration with instant speed changes. Terrain, slopes, gravity, traction, acceleration, and realistic tank-track steering are absent.
- Arena clamping, expanded XZ target boxes, and tank-to-tank radius checks provide simple movement blocking. A blocked move reverts position; yaw/speed are not rolled back. Collision is conservative and differs from the rotated rectangular shot hitbox.
- Tank-to-tank collision checks iterate other tanks regardless of health. Dead tanks can therefore still block driving until they respawn, even though shots can pass through their disabled query hitboxes.
- Destroyed targets are ignored by movement collision and ray queries, but their Part `CanCollide` value is not switched off. Tanks use custom movement, so physical collision flags do not define their movement.
- Spawn allocation repeats after 32 slots and does not resolve overlap with existing tanks on respawn. Do not assume support for a large player population.
- Server tank collision and damage lookup involve nested iteration. Snapshot broadcasts include all states for all clients. No scalability/load testing has been performed.
- The shot hitbox primarily represents the hull; elevated shots may visibly pass through turret/cannon geometry without hitting it. Revisit hit volumes if expanding combat fidelity.
- The camera observes raw snapshots and snaps on dead-to-alive transitions or jumps over 40 studs. The local renderer also resets its pose on those transitions. Remote tank renderers still use their existing smoothing; no general server teleport-generation protocol exists.
- Adapters/controller are intended to live for the LocalScript lifetime. They lack a full destroy/disconnect interface; hot reconstruction or multiple controller instances would require lifecycle work.
- PlayerModule/default TouchGui coordination, GUI event propagation, safe-area coordinate handling, gamepad UI navigation, and physical thumb reach need runtime verification. Do not infer those guarantees from mocks.
- No authoritative “relay debug” telemetry exists; the mobile overlay shows local intent only.

## Build, open, and live-edit workflow

Run commands from the repository root. This session's workspace is `/home/studio/battleworks`; future clones can use a different path.

```bash
# Install pinned tools if needed, then verify the version.
rokit install
rojo --version

# Regenerate both deliverable formats.
rojo build -o battleworks.rbxl
rojo build -o battleworks.rbxlx

# Optional source map and live sync.
rojo sourcemap -o /tmp/battleworks-sourcemap.json
rojo serve
```

In Roblox Studio, use **File → Open from File**, select either generated place, and press **Play (F5)**. Run without a player is insufficient for controlling a tank. A Rojo plugin is not required just to open a place. For live editing, use the matching Studio plugin and connect to `localhost:34872`; restart Play after script changes when necessary. Studio-only edits are not automatically written back to source.

Edit source files and the project JSON rather than treating binary place edits as the source of truth. Rebuild after source changes. `.gitignore` currently excludes `battleworks.rbxlx`, Studio lock files, and root `sourcemap.json`; it does **not** exclude `battleworks.rbxl`. Do not silently change artifact/version-control policy or discard the binary.

No publication, Roblox account operation, or remote deployment was performed. Testing a private published place in the Android app requires a future Studio/account workflow.

## Automated checks and what they prove

The existing development runner uses Node.js and **luau-web 1.4.0**, installed outside the repository. It is not a game dependency or an implementation of BW.

```bash
npm install --prefix /tmp/battleworks-luau-check luau-web@1.4.0 --no-audit --no-fund
node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js
git diff --check
```

Temporary directories may disappear between sessions; reinstall the test tool if the module is missing. No native `luau`, `luau-analyze`, `lune`, or `selene` executable was found in the previous implementation session. The runner performs syntax compilation, not Roblox-aware type analysis.

The last implementation checks passed:

- Rojo 7.7.1 builds for `.rbxl` and `.rbxlx`.
- Syntax compilation of all **14** source Luau files.
- **94 input** and **901 camera** assertions using mock Roblox services and vector/CFrame stand-ins.
- Source map generation.
- Inspection of the generated XML for the expected twelve ModuleScripts, LandscapeSensor enum value, and exclusion of tests from the place.
- Source whitespace inspection and `git diff --check`. Note that Git diff alone does not inspect untracked files.

Tests exercise malicious/invalid command values and clamping, old desktop contract compatibility, pitch bounds and shot direction, neutral turret hold, cooldown/death firing gates, dead-zone remapping, diagonal clamping, simultaneous stick/FIRE capture, cancellation, release/recentering, touch stealing prevention, resize cleanup, Auto/explicit preferences, default-control restore behavior, menu/focus/text suspension, gamepad disconnect, desktop input, relay formatting, and small-screen layout formulas.

The mocked layout dimensions checked are 480×200, 568×240, 640×280, and 960×480 safe-area sizes. These checks prove arithmetic spacing, not actual rendered legibility or touch hit testing.

The runner compiles the server/client entrypoints but does not execute the complete server loop or a real Roblox world. There is no automated engine-level multiplayer, raycast, respawn, networking, live GUI, or Android hardware test. Updating module names or require topology may also require changes in the mock loader and mock module tables.

## Runtime validation still needed

See the full checklist in the README. Priority checks for the next session with Roblox access:

1. Solo Studio Play: fixed-world camera, readable tank framing/panning, camera bars/HUD stacking, tank assembly, desktop movement/aim/fire, walls/targets, four-hit destruction and three-second reset/respawn.
2. Two-client server: ownership, movement and turret pitch replication, collision, damage, fire pacing, respawn, departure cleanup, client/server Output.
3. Small/notched Android landscape screens and tablets: safe-area layout, stick/FIRE separation, debug readability, settings accessibility, both landscape rotations.
4. Physical three-finger use: independent turret/drive/FIRE, release outside widgets, cancel, app switching/lock, menu/text focus, no stale presses after resume.
5. Runtime preference transitions and Auto behavior with Bluetooth mouse/keyboard/gamepad and a touchscreen laptop; default controls restored when leaving Touch.
6. Gamepad sticks/trigger/disconnect and settings selection; artificial latency if available. Local relay values must not be mistaken for server acceptance.
7. Camera-specific README checklist: no zoom/orbit on any input, identical visible region across aspect ratios, mouse aiming after camera updates, large/rotated/thin-map panning and corner exceptions using matching test geometry, respawn/teleport snap and CurrentCamera replacement.

## Where future changes belong

| Change | Primary location |
| --- | --- |
| Speed, health, damage, pitch limits, cooldown | `TankConfig.luau` and relevant server timing constants |
| New input device or remapping | Adapter plus `InputController`; preserve shared command semantics |
| New authoritative intent field | `InputCommand`, simulation/server consumer, every affected adapter, tests/docs |
| Better mobile layout/debug | `TouchInput`; retain per-touch ownership and safe-area behavior |
| Camera orientation/framing/visibility | `BattlefieldCameraConfig`, `CameraMath`, `BattlefieldCamera`, camera tests |
| Better visuals/recoil/wobble | `TankRenderer`; keep gameplay state unaffected |
| New arena/targets, collision, respawn rules | Server entrypoint; keep authority on server |
| Persistent settings | Explicit design first: session/account/device scope, then client/server storage integration |
| BW autonomous programs | Deferred until requested; reuse intent/simulation boundary when authorized |

Keep gameplay claims tied to evidence: build success is not runtime success, a mock assertion is not a physical Android test, and local intent is not authoritative telemetry. Update this handoff when architecture, requirements, or validation status changes.

## Runtime framing diagnosis and readability policy (2026-11-05)

Reported Studio evidence: client/server Output is clean; HUD, firing/reloading and tank movement work. Visible tank parts exist. Holding W moved the tank from approximately (-44.8, 2.3, 19.8) to (-45.5, 2.3, -32.6). These observations support a framing/readability problem rather than a missing tank or failed simulation.

The reported camera (217.223, 366.107, 217.223), focus (0,0,0), is about 478 studs from focus and matches the required 50° elevation / 45° azimuth. Distance alone is not evidence of incorrect projection. Full framing of the diagonal 230×230 playable rectangle with margin/height produces this distance. Walls extend to ±120 (240×240 outer bounds); the 8-stud margin covers them. The baseplate is 512×512, top Y=0, so a large green polygon is expected beyond the walls. Camera metadata describes playable bounds, not baseplate bounds. Olive body colors compounded the tiny projected chassis against green ground. No gameplay geometry was resized.

At 812×362, a 16:9 window has at most 362 pixels of height, fewer after symmetric Core UI padding. A six-stud chassis at the old distance spans only a few pixels. FOV 56.3469 can result from compensating for a masked window's reduced height; viewport dimensions alone do not identify the actual safe rectangle. Log both GuiService inset rectangles in Studio when comparing results. Manually writing CFrame is immediately overwritten by design: BattlefieldCamera owns CFrame, Focus and FOV every render frame.

**Explicit policy: readable tanks take priority over full small-map framing.** CameraMath limits distance using a six-stud camera-right chassis chord and the farthest visible ground depth, in addition to the existing 900-stud ground-diameter cap and thin-map containment. The budget is 24 horizontal pixels at a fixed 320-pixel battlefield-window height. Full-map mode is allowed only if both limits permit it; the current arena therefore pans. This reference budget is fixed across clients: a smaller viewport never causes zoom-out. At other window heights the guaranteed geometric span scales as `24 * windowHeight / 320`. For example, an 812×362 viewport with 58-pixel symmetric vertical padding has a 246-pixel window and an 18.45-pixel minimum. Very narrow/tall viewports remain degraded; the 120° physical FOV clamp can narrow coverage further. No universal absolute pixel guarantee is possible on arbitrarily tiny windows while preserving equal world coverage.

TankRenderer uses brighter chassis/turret/cannon colors for ground contrast, with unchanged dimensions, tracks, animation and combat behavior. No through-wall highlights or enlarged hitboxes were added. The width budget measures geometric projection before clipping, lighting, occlusion or rasterization; it does not guarantee cannon/track-shoe detail. Existing corner fallback guarantees the tank ground point is onscreen, not the entire model silhouette. Test wall occlusion and silhouette clipping at corners in Studio. If tuning needs adjustment, change the shared fixed budget rather than adapting zoom to a client's current pixel count.

Automated coverage includes 812×362, safe-area-reduced Studio windows, small readable maps, current-arena pan mode, actual 6×8 chassis corner projection at multiple yaws, minimum projected width at far ground corners, and coverage parity across normal aspect ratios. Full suite: 15 source modules compile, 94 input assertions and 901 camera assertions pass. Both Rojo place formats are rebuilt. These checks use mock engine services and do not establish Roblox visual success.

Still requires Studio runtime verification: compare tank recognition before/after at 812×362 and phone sizes; record actual inset rectangles, FOV, focus and camera position; drive the reported route and all arena edges/corners; verify lighting/contrast, full tank clipping, wall occlusion, mouse aim during panning, HUD/mask stacking, respawn, camera replacement and two-client behavior. Check no zoom/orbit across mouse, touch and gamepad. Networking, controls and server simulation are preserved. This remains a client viewing policy rather than server-enforced fog of war; existing full-state broadcasts are unchanged.

## Studio rendering investigation controls (2026-11-05)

The newer reported camera position `(6.9014,58.4761,6.9014)` alone does not identify its look direction, focus, FOV or projected tank size. If orientation is correct and focus Y=0, its height implies about 76.3 studs along the viewing axis; its focus would be approximately `(-27.8,0,-27.8)`. This is compatible with tank tracking, not evidence that the camera faces the wrong direction. The reported tiny green dots and small rectangular world patch are still unresolved runtime observations, not verified rendering fixes.

Source inspection confirms four opaque black Frames in `PlayerGui.BattlefieldCameraBars`. They deliberately mask the world outside the 16:9 window. The baseplate is green; no black surround geometry is generated. That establishes a possible source, not that all observed black pixels are these masks. Compare with masks disabled to distinguish game GUI from world background or Studio's device-emulator surround. Other game GUIs contain HUD/controls, not a full-screen black cover.

A targeted correction uses `DeviceSafeInsets` for the world window rather than `CoreUISafeInsets`: top-bar UI reservation no longer removes the same amount from both top and bottom. The HUD still uses Core UI safe coordinates. For 812×362 without a device notch, the battlefield now uses all 362 pixels of height (643.6 pixels of width, with ~84.2-pixel side masks), instead of shrinking further for top-bar clearance. Required fixed orientation, lens policy, readability cap, competitive aspect ratio, large-map limits and controls are unchanged. This does not establish the cause of the entire reported visual problem. Device safe/fullscreen coordinate behavior must be checked on the actual Studio configuration. API semantics: https://create.roblox.com/docs/reference/engine/classes/GuiService and https://create.roblox.com/docs/reference/engine/classes/Camera .

In Play mode select the **client** context in Studio. Under your player's PlayerGui select `BattlefieldCameraBars`. Three temporary boolean attributes are initialized in Studio only:

- `DebugEnabled=true`: prints every two seconds. Reports actual camera position/look/focus/FOV/mode/viewport, GUI size, layout rectangle/distance, all three inset rectangles, playable bounds, actual boundary/baseplate positions and sizes, replicated tank position, rendered chassis position and eight-corner screen rectangle/size/depth, model projected bounds, mask absolute rectangles, and actual viewport corner/center rays intersected with ground Y=0. Projection rectangles are unclipped bounds, not a guarantee of unoccluded pixels.
- `HideMasks=true`: hides only this camera-mask ScreenGui. Camera projection stays unchanged for a controlled A/B comparison. If black disappears, masks caused those pixels; if it remains, inspect Studio emulation surround/other GUIs/world background.
- `PauseCamera=true`: stops all controller writes to CFrame, Focus, FOV and CameraType; gameplay, renderer and diagnostics continue. Set before experimenting with manual camera positions. Returning false snaps to the normal policy. These bypasses are ignored outside Studio.

Example in the **client** Command Bar after Play:

```lua
local g = game.Players.LocalPlayer.PlayerGui.BattlefieldCameraBars
g:SetAttribute("DebugEnabled", true)
g:SetAttribute("HideMasks", true)
g:SetAttribute("PauseCamera", true)
local c = workspace.CurrentCamera
local tank = workspace:FindFirstChild("Tank_" .. game.Players.LocalPlayer.UserId)
local target = tank.Chassis.Position
local e, a = math.rad(50), math.rad(45)
local offset = Vector3.new(math.sin(a)*math.cos(e), math.sin(e), math.cos(a)*math.cos(e))
c.CameraType = Enum.CameraType.Scriptable
c.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
c.FieldOfView = 40
c.CFrame = CFrame.lookAt(target + offset * 65, target)
c.Focus = CFrame.new(target)
```

Then restore PauseCamera and HideMasks to false. This manual position is a diagnostic, not a new production camera. Compare the printed chassis pixels with its visible silhouette: a large projected rectangle but tiny visible dots suggests occlusion/GUI/appearance; a tiny projected rectangle suggests projection, position or dimension mismatch. If masking is responsible, compare printed mask absolute rectangles with the actual patch. Include Output samples both before/after HideMasks and while manual positioning is paused. Check Rendered chassis position versus authoritative position for stale/misaligned geometry. Brightened full-sized chassis/turret and dark tracks are retained; tank recognizability still needs actual visual confirmation.

Checks now compile 15 sources, pass 94 input and 901 camera assertions, and build both place formats. Added regressions cover manual-pose preservation, independent mask suppression, ownership resumption and full-height short-viewport use despite Core UI top-bar reservation. Real engine projection, look direction, actual inset values, GUI scaling, lighting, wall occlusion, ground intersections and rasterized tank recognition cannot be verified by the mocks. No Roblox Studio session was executed here.

## Arena floor correction (2026-11-05)

The server previously generated targets, boundaries and hitboxes but **no ground**. Ground depended entirely on `Workspace.Baseplate` supplied by `default.project.json` (512×512, top Y=0). No source creates or fills Terrain. Therefore an existing Studio place synchronized without that project-level Baseplate can have working scripted movement and combat over empty space. Missing ground under `Arena` alone did not prove the root Workspace lacked a Baseplate, but the runtime arena had no self-contained floor guarantee. Sky/black outside geometry can also include the existing camera GUI masks; this fix does not remove those masks.

Arena creation now explicitly creates `Workspace.Arena.Floor`: a visible anchored Concrete Part sized 240×1×240, centered at `(0,-0.5,0)`, so its top is exactly Y=0 and its X/Z edges align with the outer boundary edges at ±120. CanCollide/CanTouch are false; the unchanged Scriptable camera has no collision response, and server tanks move mathematically rather than relying on floor physics. CanQuery remains true for downward shot rays. The obsolete project-only Baseplate was removed from the Rojo mapping to avoid overlapping ground surfaces. No Terrain changes, camera changes or control changes were made for this fix.

Rebuild/reconnect and restart Play. Verify `Workspace.Arena.Floor` exists on server and client, is opaque, covers the battlefield, and is visible under tanks from the existing camera. If using an older manually edited Studio place, remove its legacy Baseplate to avoid a coplanar duplicate surface. Outside the finite 240×240 floor, sky or camera masks can still be visible by design. Real Studio visibility/lighting, ray hits on the new floor and multiplayer replication remain runtime checks; automated tests and Rojo builds do not render the scene.

## Practice target combat investigation (2026-11-05)

Server shots originate at the authoritative tank position plus `(0,3.6,0)` and follow the authoritative turret yaw/pitch up to 320 studs. They exclude the shooter's hitbox and damage only the first raycast hit. The cosmetic muzzle/tracer originates seven studs ahead and cannot prove that the target was the server's hit instance. At horizontal pitch a center-aligned ray crosses a practice target's Y range 0..7; walls, other tank hitboxes, aim convergence, and pitched shots can change the first hit. Actual Studio first-hit identity remains to be measured.

The previous server code already subtracted 25 HP from a directly hit target, but offered no partial-hit feedback: 100, 75, 50 and 25 HP looked identical. Destroyed targets were still faintly visible (Transparency 0.85) and reset after three seconds. These are confirmed feedback/lifecycle defects. The reported lack of damage does not by itself prove a raycast failure; no original server hit log was supplied.

`src/server/PracticeTargets.luau` now owns the server target lifecycle and first-hit resolution. Targets have 100 HP, take exactly 25 per accepted hit, flash for 0.15 seconds and display a replicated HP readout. Their color darkens as health drops. Four hits make them completely invisible, disable their health label and queries/collision immediately, and schedule a full reset five seconds after the lethal hit. Dead-target hits cannot extend this deadline. Tank damage/respawn, movement, camera and input remain unchanged. Raycast RespectCanCollide=false is explicit so noncolliding live tank hitboxes remain queryable. Target death updates query state before any subsequent shot in the same step.

For temporary combat diagnostics, in Studio's **server** context enable `workspace.Arena:SetAttribute("DebugCombat", true)`. Each accepted shot logs shooter ID, actual ray origin/direction, first hit instance/full path, hit position and target HP before/after. `nil->nil` means the first hit was not a registered practice target; `MISS` means no server intersection. A target hit should report `100->75`, then `75->50`, `50->25`, `25->0`. Disable the attribute after testing. The diagnostic is server-only and clients cannot submit damage or hit identity.

Automated checks: 16 source files compile; 94 input, 901 camera and 40 combat assertions pass. Combat tests cover the server origin/direction, cooldown, first-hit dispatch with injected raycast results, shooter exclusion/query settings, four-hit destruction, immediate query removal, wall occlusion dispatch, misses, flash expiry, replicated HP text, no early respawn and exact five-second restoration. These mocks do not execute Roblox spatial queries. Both Rojo place formats build and whitespace checks pass.

Still requires real Studio verification: enable diagnostics, fire at each target, confirm logged target intersections and HP progression, observe flashes/readouts and fourth-hit disappearance, verify it stays absent five seconds then returns, and repeat with two clients. Check a wall/other tank blocking the shot and pitched fire hitting the floor. If a visible tracer seems to hit but diagnostics report another instance or MISS, preserve that log plus tank/target coordinates to diagnose actual engine geometry/aiming; a visual tracer alone is not a damage acknowledgment.

## Occupied target respawn fix (2026-11-05)

Previously a target reset unconditionally five seconds after destruction. A tank could enter the absent target's space, then become embedded in the restored obstacle. PracticeTargets now checks all living tanks in the server's authoritative tank table before restoring a target. The check expands each target's X/Z half-size by TankConfig.Radius (5 studs), matching the existing conservative movement collision rectangle, including its corners; it does not merely check tank centers. Exact boundary contact is also treated as occupied. This uses the game's existing flat-ground collision footprint rather than visual tank animation or client-reported positions.

If occupied, the target remains at zero HP, invisible, noncolliding and nonqueryable with its label hidden. It retries every 0.25 seconds until clear, then restores health, visibility, label and collision together. Five seconds remains the minimum delay; leaving the space can add up to one retry interval. Dead tanks do not block respawn, and the current server table naturally handles multiple players and departures. This check runs in the same non-yielding server simulation loop as target restoration, before movement; no movement, aiming, firing, camera or input behavior was changed.

Validation: 16 sources compile; 94 input, 901 camera and 55 combat assertions pass. New cases cover occupied center, partial footprint overlap, diagonal overlap, boundary contact, repeated delays, no early retry, complete state restoration, clear X/Z bounds, dead tanks, multiple players and departure. Both Rojo builds and whitespace checks pass. Still verify in Studio: destroy a target, drive into its center or partially across its edge, wait beyond five seconds, and confirm it stays absent; drive clear and confirm restoration within 0.25 seconds. Repeat with two clients where either player's tank occupies the space.

## Camera early-stop correction (2026-11-05)

The old CameraMath target solver clipped focus against bounds derived from the full perspective ground trapezoid. It correctly used ground-plane footprint rather than camera world position, but assigned strict containment higher priority than smooth tank tracking. As the far ground edge reached the map border, focus stopped while the tank kept moving. The 0.85 inset allowed the tank to approach the screen edge; fallback permitted outside ground only after even that inset/full window became infeasible. This explains early tracking limits despite targets at Z=-65 being inside the arena.

Pan mode now targets the authoritative tank position throughout the playable map. BattlefieldCamera retains exponential smoothing, then CameraMath projects focus into the comfort polygon generated from rays through the central half of the lens (`TankViewInset=0.5`). This prevents tank drift toward screen edges, including at corners and after displacement. The actual asymmetric ground footprint and map rotation are still used to measure outside-ground extent. Outside-arena space is explicitly permitted for playability; map containment no longer freezes tracking. Fixed 50° elevation / 45° azimuth, distance/readability/ground-diameter caps, competitive window, no manual zoom and readable small-map full framing are unchanged. Panning changes which region is seen, not the maximum amount of ground seen. Long/thin maps retain the existing distance reduction.

Bug 2 was already fixed: server target restoration checks every living tank's complete existing collision footprint and retries every 0.25 seconds while occupied. That code is preserved. Movement, aiming, firing and input were not changed in this camera update.

Validation: 16 sources compile, 94 input / 5,378 camera / 55 combat assertions pass. Tests include continuous smoothed routes to all four current-arena edges and four corners on 812×362, 568×320 and ultrawide viewports; central comfort projection throughout each route; continued north tracking beyond the target row; nearby target visibility; rotated-map edges/corners; unchanged distance and ground cap; and existing multiplayer respawn occupancy cases. Both Rojo builds and whitespace checks pass.

Studio verification remains: drive north from spawn past the practice targets and to every boundary/corner; verify smooth camera motion, readable tank/nearby targets, aiming and no zoom/orbit. Some sky or outside-floor space is now intentionally visible near map edges because the finite floor is 240×240; walls may still occlude geometry. The policy does not promise to show all five targets simultaneously at any distance. Check camera diagnostics for correct look direction, actual ground intersections and unchanged distance. Repeat occupied-target respawn with two clients to confirm the existing server fix in the engine. Automated projection tests do not establish rendered visual quality or runtime replication behavior.

## Orange reference tank visual update (2026-11-05)

TankRenderer now uses the orange tank at bottom center of `references/tank-styles.png` as its visual reference: bright orange hull/deck, broad stepped turret with yellow hatch and side stripes, gray cylindrical cannon/collar with dark muzzle, charcoal tracks, exposed gray road wheels and dark hubs, raised fenders/deck ribs and yellow front accents. Built from ordinary smooth Roblox Parts, without generated textures, meshes or asset dependencies. This is a primitive-geometry interpretation rather than an exact reproduction of the reference's bevels.

Cosmetic details are attached to the existing chassis, turret or pitched/recoiling barrel transforms. Track shoes now circulate around full capsule-shaped belts. Existing smoothing, chassis wobble, recoil, death transparency and renderer cleanup remain. The cannon's forward axis remains local -Z and its tip stays approximately seven studs from the turret pivot; cylinder orientation is adjusted locally, without changing shot math. Server hitboxes, movement collision radius, health/damage, networking, camera, controls and firing mechanics are unchanged. Orange paint supersedes the earlier olive renderer descriptions.

Validation: 16 sources compile; 94 input, 5,378 camera and 55 combat assertions pass; both Rojo builds and whitespace checks pass. The existing tests do not rasterize the new geometry. Studio checks still needed: compare the assembled silhouette to the reference from the fixed camera; rotate chassis and turret independently; aim/elevate/fire to verify barrel alignment and attached details; verify tread motion, death/respawn visuals, readability at 812×362 and phone sizes, and performance with several tanks. Added wheel/tread/decorative Parts increase per-tank rendering cost; no multiplayer runtime performance measurement was performed here.

### Cartoon proportion pass

The orange tank now has an oversized rounded turret (5.8-stud shoulder width and 2.7-stud body height), a much thicker 1.8-stud cannon with a 2.2-stud muzzle rim, a large stacked yellow hatch, chunky cheek buttons, a crooked periscope with blue glass, round headlights, oversized bolts, yellow wheel-hub buttons and stubby exhausts. Smooth plastic and saturated orange/yellow keep the style toy-like. These additions follow existing cosmetic attachment transforms; the turret pivot, barrel forward axis and seven-stud muzzle endpoint are retained. Server collision, aiming/firing math, controls, networking and camera are unchanged. The visual body is deliberately exaggerated relative to the unchanged gameplay hitbox.

All 5,527 assertions and both Rojo builds pass; 16 source files compile and whitespace checks pass. Studio verification remains necessary for silhouette/readability, independent turret/pitch motion, muzzle alignment, nearby cosmetic overlap and multiplayer rendering cost. No new Studio rendering or performance result is claimed.

## Taller rounded turret and slow artillery shells (2026-11-05)

The cartoon turret body height increased exactly 30%, from 2.7 to 3.51 studs. A flattened ellipsoid crown rounds the upper section, and the hatch/periscope move upward to sit on it. The gameplay turret pivot remains at Y=3.6; barrel direction, tank hitbox and movement/camera controls are unchanged.

Hitscan fire is replaced by visible server-owned artillery shells at **24 studs/second**, configurable via `TankConfig.ShellSpeed`. Each round has an olive cylindrical body, oversized orange nose and brass band. It follows the turret's launch direction at constant speed, with no gravity or homing, preserving current mouse/pitch aiming. At 96 studs, travel takes about four seconds, giving opponents time to evade. Existing 0.65-second cooldown, 25 direct-hit damage, 320-stud range, target health/respawn and occupied-spawn checks remain. There is no area damage or physical blast force. Shells persist after the shooter dies/departs and ignore their original shooter's hitbox; they expire after traveling their range (about 13.33 simulation seconds).

`ProjectileSimulation` advances authoritative shell state at the existing fixed step. Every segment uses a swept sphere of radius 0.65, so thin obstacles are not skipped. Initial overlaps are checked too, using sphere-vs-oriented-box geometry on broadphase candidates; this also catches tanks moving into a shell. The current arena/hitboxes use box geometry; the overlap approximation would need refinement for future irregular meshes. The sphere is centered on the visible rounded nose; the body/band trail cosmetically. Collisions ignore the shooter and visual shell folder, query noncolliding live tank hitboxes, and resolve the first actual obstruction. Server damage happens only on impact, never at launch. The old hitscan cast helper and laser tracer were removed. Shot RemoteEvent now carries shooter ID and cosmetic muzzle origin only, triggering recoil/flash. Shell position/appearance replicate as anchored server Parts; clients cannot submit projectile paths or damage.

Shell simulation starts at the authoritative turret pivot rather than the seven-stud cosmetic muzzle to preserve cover blocking. Consequently a slow round is initially concealed by the barrel for about 0.29 seconds before emerging; no advance-to-muzzle shortcut bypasses nearby cover. `Arena.DebugCombat` now logs shell launches and actual impacts with target HP before/after. The impact flash is cosmetic, with no Roblox Explosion instance. Reference API for swept collision and its initial-overlap limitation: https://create.roblox.com/docs/reference/engine/classes/WorldRoot .

Checks compile 17 sources and pass 94 input, 5,378 camera, 37 target-combat and 43 projectile assertions. Target tests now exercise impact dispatch rather than the removed full-range hitscan helper; projectile tests cover speed, delayed impact damage, dodging, cover, query exclusions, single-use impact, range expiry, zero time, subdivided steps, pitched flight and initial overlap. Both Rojo formats build and whitespace checks pass.

Studio verification remains necessary: inspect the taller rounded silhouette; fire toward all five targets and verify delayed damage/four-hit destruction; use two clients to dodge rounds and verify server damage only on contact; test walls, close cover, pitched floor shots and overlapping respawns; observe shell replication smoothness under latency and performance with multiple simultaneous rounds. Server anchored-Part replication has no dedicated client interpolation/prediction, so smoothness under network load is unverified. Historical hitscan/tracer descriptions above refer to the previous weapon and are superseded by this section.

## Map camera with persistent dead zone (2026-11-05)

This replaces the previous chase behavior. The camera now retains its previous map focus, rather than calculating a new tank-centered goal every frame. Its central dead zone spans 65% of the **visible battlefield window's** width and height (17.5% margins on each side), measured in projection, not world X/Z distances or the masked portions of an ultrawide screen. Rays intersecting the ground plane produce the actual asymmetric trapezoid at 50° elevation / 45° azimuth, so diagonal motion and rotated maps use the correct screen-space boundary.

Inside the dead zone, focus remains unchanged. Outside it, CameraMath projects the previous focus to the nearest feasible focus that puts the tank back at the boundary. BattlefieldCamera smoothly pans toward that minimal correction. It never targets tank center merely because movement stops or reverses: a stopped tank just outside the zone completes its small correction to the boundary, while reversing into the zone immediately stops camera movement. A separate 90% visibility guard prevents abrupt movement from taking the tank offscreen. Normal smooth tracking can temporarily place the tank slightly beyond 65%; clamping every rendered frame directly to 65% would eliminate the requested smoothing.

Map-local bounds constrain the optical ground focus, not the camera's elevated world position or the full ground trapezoid. The nearest valid dead-zone focus is selected within those bounds when possible. Visibility wins if an out-of-bounds state makes both constraints impossible. Actual outside-ground extent is measured from all footprint corners and can be positive near edges. No zoom/distance/ground-diameter cap is increased. Small maps remain stationary at map center and show the entire expanded playable rectangle **when it fits within existing zoom and readability limits**; those preserved limits still classify the current 230×230 practice arena as pan mode. Teleports, respawns and layout changes snap only as needed to regain a valid dead-zone view, not a continuously centered chase view.

Camera behavior remains modular: window/ground geometry, minimal target correction, bounds and tracking are pure functions in CameraMath; BattlefieldCamera owns state and engine writes; tuning is in BattlefieldCameraConfig (`TankViewInset=0.65`, `VisibilityInset=0.9`). Projectile simulation, combat, target respawn occupancy, input and aiming are untouched.

Validation: 17 sources compile; 94 input, 10,093 camera, 37 target-combat and 43 projectile assertions pass. New tests cover unchanged focus inside the zone, exact 65% projected boundary after minimal correction, eased pan, indefinite boundary hold, no recenter on reversal, stationary small-map framing, and routes to all edges/corners on current/rotated maps across 812×362, phone and ultrawide viewports. Existing zoom/readability caps, camera ownership and combat tests pass. Both Rojo place formats build and whitespace checks pass.

Still verify in Studio: move across the screen inside the zone, cross each edge diagonally and straight, stop just outside it, reverse direction, and drive to every arena edge/corner. Confirm the camera holds its map position without a slow center drift, pan speed feels appropriate, mouse aim remains aligned, and the fixed orientation/zoom limits hold. Outside-floor space near boundaries remains intentional. Check on phone/ultrawide screens and under network latency; mocks verify geometry/state transitions rather than engine rendering or feel. Historical chase-policy notes above are superseded by this section.

## Elastic barrel swell and muzzle launch (2026-11-05)

Firing triggers a 0.22-second client-only swelling animation through the existing Shot event. A rounded bulge travels down the barrel, followed by a brief muzzle flare and elastic diameter bounce. Two reusable Parts are allocated per tank; no mesh regeneration, per-frame Instances or accumulating tweens. BarrelAnimation samples fixed base dimensions; repeated fire restarts the animation and completion restores the exact shape. Original turret recoil is retained. Respawn/teleport clears the effect, and dead tanks hide it.

Shells now launch at the authoritative muzzle, seven studs forward along turret yaw/pitch. A server swept-sphere check from pivot to tip prevents firing through nearby cover; an obstruction resolves on the next simulation step. The same Shot event starts client swelling, flash and recoil when the shell is spawned. The cosmetic animation does not delay launch. Projectile speed (24 studs/second), trajectory, collision radius, damage, reload timing and total 320-stud range from pivot remain unchanged. The muzzle advance counts against that existing range. The pre-recoil tip defines launch position. Earlier pivot-origin launch notes are superseded.

Validation: 18 sources compile; 94 input, 10,093 camera, 37 target-combat, 56 projectile and 203 barrel-animation assertions pass. Tests cover duration, bounded dimensions, bulge direction, muzzle flare, bounce, restoration, repeated firing, muzzle origin/pitch, speed/range and close-cover safety. Both Rojo builds and whitespace checks pass.

Studio checks remain: view the bulge and flare from the elevated camera at 30/60 FPS, repeat fire, rotate/elevate turret, die/respawn, compare two-client timing and network smoothness, and fire near walls/targets. Verify shells visibly leave the tip and cannot bypass cover. Engine-rendered visual quality is not established by mocks.

Barrel swell tuning: increased peak diameter from 3.5 to 4.6 studs, length from 2.1 to 2.6 studs, and strengthened the muzzle flare. The animation now lasts 0.264 seconds (20% longer), with travel, flare and bounce stretched together. Projectile timing and recoil are unchanged.

## Strict 20% camera and wider zoom (2026-11-05)

This section supersedes historical 65% dead-zone, smoothing, 90% guard and 24-pixel budget notes above. Source inspection found that the old conservative readability cap limited follow distance to 76.34 studs; its large dead zone and eased pan allowed the tank to approach the edge. The controller now uses a default 100-stud distance (31% more linear ground coverage), with configurable preferred minimum 45 and maximum 125. The conservative far-ground readability budget is 18 horizontal pixels at a 320-pixel battlefield-window height, scaling with actual window height; the tank near the central dead zone is larger. This is a geometric budget, not a measured visual result. Current 230×230 arena still uses follow mode; smaller readable maps are fully framed with 8-stud margins and 8-stud height allowance.

For normalized projection u,v spanning [-1,1], the dead zone is abs(u),abs(v) <= 0.20. Conversion to pixels gives [0.40W,0.60W] and [0.40H,0.60H], offset by the existing visible battlefield window origin. Each span is exactly 0.20 of its dimension. Opaque bars are outside that window. Inverse rays produce a perspective ground polygon, so projection, diagonal motion, aspect changes and rotated map bounds agree. The nearest feasible focus yields only the required pan, without easing or continued motion after stopping.

Verification: 18 source files compile; 94 input, 11,046 camera, 37 combat, 56 projectile and 203 barrel-animation assertions pass. Both Rojo place formats build. Camera tests include exact 40–60% pixel limits, all boundary directions, speeds 24/240/2400 studs per second at 15/30/60/144 FPS, no drift, rotated edges/corners, map margin/height, zoom limits/readability, missing references, respawn, resizing, replacement cameras and existing mouse-ray conversion. No Roblox Studio session was run. Immediate correction follows the existing 20 Hz authoritative snapshots; network jitter and cosmetic renderer lag may be visible and need runtime assessment. Some outside-floor space near boundaries is intentional; tiny/portrait screens have fewer pixels under the preserved 16:9 policy.

Manual camera checklist in Roblox Studio:

1. Open the rebuilt place, Play, and check wider surroundings and recognizable tank size at desktop and phone landscape sizes.
2. Move within the central 40–60% rectangle: camera holds. Cross every side and corner: camera immediately holds the tank at the boundary. Stop and reverse: no drift or recentering.
3. Drive at all walls/corners, aim and fire while panning, and check WASD, touch and gamepad input. Confirm fixed orientation and usable HUD.
4. Resize, change emulated aspect ratio, die/respawn, and run two clients with latency; watch Output and assess snapshot jitter/renderer lag.
5. Temporarily use a small MapSize matching a smaller playable map and restart Play: verify whole-map lock, margins and tank readability. Restore metadata to match the actual arena afterward.

## Softer hull silhouette (2026-11-05)

Chassis, upper deck, front armor/inset and track fenders now use ellipsoid Parts instead of blocks, softening the main hull silhouette without adding Parts. Their sizes and attachment transforms are preserved. The turret and every turret/barrel detail are unchanged, as requested. Movement, collision/hitboxes, camera, firing and animation logic are unchanged. Existing automated checks and both Rojo builds pass; Studio visual testing remains necessary to assess curved-panel overlap, hull readability and fender/deck detail placement.

## Studio camera testing panel and production overview correction (2026-11-05)

In Studio Play, click **Camera Tests (Studio)** below the HUD to expand the developer-only panel. Map Width and Map Depth sliders span 100–2,000 studs in one-stud increments and show numeric values. Drag with mouse or touch. The panel shows Whole Map / Follow, effective distance and active dimensions. Reset to Actual Map clears the override and restores the configured actual MapSize (currently 230×230). The scrollable panel fits shorter windows, and collapsing it keeps the current override active.

`CameraTestPanel` has no framing/tracking calculations. `BattlefieldCamera:setMapSizeOverride` invalidates the cached layout; the next existing render update clones configuration, replaces only MapSize, and invokes production CameraMath. MapCenter and MapYaw stay intact. Real terrain/objects, tank movement, turret aiming, projectiles and server state are untouched. Overrides survive viewport changes, camera replacement and respawn, and reset on a fresh client session. Both UI creation and the override setter reject non-Studio clients. This follows the existing IsStudio debug convention; there is no live-game developer allowlist.

Investigation: a 100×100 square at the unchanged 50°/45° orientation, 40° window FOV, 8-stud margin and 8-stud height allowance needs **225.36 studs** of camera distance. The previous MaxZoom=125 disallowed it. The shared 18-pixel six-stud chassis budget, measured at empty far viewport corners, also capped distance around 101.79. Projection/framing itself was correct. A 100-square overview cannot meet that old chassis budget at reference height: its farthest playable depth is 270.81, giving only 9.74 chassis pixels.

Production now allows MaxZoom=260 and evaluates overview readability using a conservative eight-stud **full tank silhouette**, including tracks, at actual playable map corners. WholeMapMinTankPixels=12 at the fixed 320-pixel reference window height. The 100-square overview yields **12.99 silhouette pixels minimum** (about 14.69 at a 362-pixel-high window), before lighting/occlusion/rasterization. Existing track geometry is 9.3 studs wide and 8.6 long; tests independently project track corners across 36 chassis orientations to check the conservative eight-stud span. This is an explicit overview/action readability tradeoff. Follow mode retains its 18-pixel chassis budget, 100-stud default distance and strict central 20% dead zone.

The overview pixel calculation is `H * width / (2 * tan(verticalFOV/2) * (distance + farthestForwardOffset))`. Under normal unclamped lens settings, an unrotated square remains in Whole Map through **109×109** studs, then switches to Follow at **110×110**. Smaller squares fit more easily; there is no lower fit cutoff within the sliders' range. Non-square/rotated maps and extreme aspect ratios use the actual production solver, so their threshold differs. Current 230-square arena remains in Follow. The raised distance maximum does not make larger maps unreadably tiny: the overview budget remains a hard limit.

Verification: 19 sources compile; 94 input, 12,079 camera, 37 combat, 56 projectile and 203 barrel-animation assertions pass. Both Rojo place formats build and whitespace checks pass. Tests use actual production settings for mode transitions, plus shifted/rotated map metadata; cover dimension changes, margins/object height, tank silhouette budget, all simulated boundaries, slider endpoints/values/mouse/touch ownership, reset, resizing/respawn, listener cleanup and normal-client isolation. No relaxed camera tuning is used to establish transitions.

Roblox Studio was not run. GUI layout, slider hit areas/dragging, touch scrolling and rendered tank recognizability remain unverified. To test: expand the panel; set both dimensions to 100 and confirm Whole Map; raise both to 110 or larger and confirm Follow; drive and check the 20% boundary; resize and respawn with an override; reset and confirm 230×230 Follow. Simulated boundaries do not move real walls or restrict tank movement, so a tank can physically leave a simulated small map; Whole Map intentionally stays centered in that case. Test on phone landscape and desktop, check Output, and adjust WholeMapMinTankPixels upward if the overview looks too small. This section supersedes earlier 125-stud maximum/shared-readability policy notes.

## Original tank design restored (2026-11-05)

The tank design is restored from commit `0c6f891` (also the local `origin/master` reference): olive Metal block chassis and turret, dark rectangular tracks, the original narrow rectangular cannon, and seven scrolling top track shoes per side. This supersedes the orange reference, cartoon proportions, taller rounded turret, softer hull and barrel-swelling visual updates above. The barrel-animation module and its sampling tests remain on disk but are no longer used by the renderer.

The newer camera and Studio test panel, controls, target behavior and slow server-owned projectiles are preserved. The renderer retains the `fire` and `resetPose` methods required by the current client; shots trigger the original recoil and muzzle flash without restoring hitscan tracers. Camera silhouette checks now use the restored 9-stud-long, 2.4-stud-high track boxes; camera tuning is unchanged.

Verification: all 19 Luau sources compile; 94 input, 12,079 camera, 37 combat, 56 projectile and 203 retained barrel-sampling assertions pass. Both Rojo place formats rebuild successfully and `git diff --check` passes. Roblox Studio was not run; open the rebuilt place and restart Play to inspect the restored design.

## Reference-based orange tank redesign (2026-11-05)

The tank is orange and cartoony again, following the middle-bottom tank in `references/tank-styles.png`. This supersedes the original-design restoration above. A broad 5.8×2.8×4.8 turret has flat faces with rounded edges/corners, a yellow circular hatch, three side stripes and circular cheek mounts. The low orange hull has a rounded deck, sloped front plate, dark inset and small bolts. A thick gray cylindrical cannon has a collar, dark bands and dark muzzle bore. Four exposed gray wheels per side sit within charcoal capsule tracks with 28 moving shoes per side, plus orange deck ribs and yellow light strips.

Rounded hull/deck/turret surfaces use overlapping solid primitive boxes, cylinders and spheres rather than flattened ellipsoids. Cosmetic parts follow the existing chassis wobble, turret yaw, cannon pitch/recoil and death transparency. The gameplay turret pivot and nominal seven-stud cannon tip remain intact. Controls, camera, collision/hitboxes and server projectiles are unchanged. The earlier barrel swelling remains inactive.

Validation: 19 sources compile; all existing input, camera, combat, projectile and barrel-sampling suites pass. Both Rojo place formats build and whitespace checks pass. Roblox Studio was not run. Inspect the assembled silhouette, rounded seams, wheel/tread visibility, independent turret rotation, pitched/recoiling cannon and phone-size readability in Studio. The composite rounded parts increase rendering cost; multiplayer performance remains unmeasured.

## Cartoon cannon cough, suspension and body details (2026-11-06)

The existing 0.264-second BarrelAnimation is active again. Firing restarts a rounded bulge traveling from the barrel base to the muzzle, followed by a swelling gray muzzle lip with a dark expanding bore and elastic barrel recovery. Reusable cosmetic Parts follow cannon yaw, pitch and recoil. Death, respawn and pose resets clear the effect; repeated shots restart it without accumulating scale. This restores the previous visual cough; server shells still launch immediately on the accepted shot, as they did before, rather than waiting for the cosmetic bulge to arrive.

The hull and its broad deck now bob vertically on a damped cosmetic spring, with smaller accompanying turret motion and existing roll/pitch wobble. Tracks remain grounded. Movement blends into the bounce, stopping lets it settle, and firing adds a small suspension impulse. Render-time substeps keep the spring stable through long frames. This changes visual poses only; authoritative aiming, collision, camera and projectile trajectory remain unchanged.

Reference-inspired decoration adds a raised yellow border around the dark sloping front panel, metal deck fasteners, fender seams, a rear engine grille with eight slats, small red rear lamps and front tow mounts. The large rounded orange turret, yellow hatch/side markings, exposed gray wheels and chunky track belts remain.

Verification: all 19 source files compile; 94 input, 12,079 camera, 37 combat, 56 projectile and 203 barrel-animation assertions pass. Both Rojo formats rebuild and whitespace checks pass. Studio was not run. Check cannon cough visibility and its timing against replicated shells, muzzle alignment while pitching, hull bounce/settling at different frame rates, death/respawn cleanup, body decoration visibility and phone-size readability in Play. Rendering quality and multiplayer performance remain unverified.

## Shot release timing and visible suspension correction (2026-11-06)

Shell release now waits 0.20 seconds (`TankConfig.FireWindup`) after accepted firing intent. A server PrepareShot event starts the cosmetic swell; the existing Shot event flashes the muzzle only when the server releases the shell. WeaponWindup reserves the existing cooldown at preparation, advances on fixed simulation steps, cancels on death/removal/respawn, and uses current authoritative position/aim at release. Pivot-to-muzzle cover checks still occur at release. Releasing FIRE after preparation does not cancel that committed round. This supersedes immediate-launch notes above. Network timing still needs Studio multiplayer testing.

The earlier movement-phase target oscillated too quickly for the damped spring to follow visibly. Suspension now uses a continuous 1.27 Hz clock and a 0.38-stud target amplitude, with blended movement intensity, substeps and settling. The turret shares the hull's vertical motion to avoid sliding between them; tracks stay grounded. Camera tracking policy is unchanged, so this does not claim to resolve snapshot/camera jitter.

Front armor now slopes downward toward the nose and projects ahead of the deck so the front inset is not buried beneath it. The yellow inset border, dark panel and bolts are larger and raised; deck ribs are thicker yellow strips and front lights are larger. These are deliberate silhouette/contrast changes for the distant gameplay camera.

Validation: 20 sources compile; all existing suites pass, plus weapon-windup tests proving no early release, release at 0.20 seconds, current pose/aim, cooldown enforcement and death cancellation. Both place formats build and whitespace checks pass. Studio was not run. Reopen the rebuilt place or reconnect Rojo and stop/restart Play; inspect front-panel visibility, obvious slow deck bob/settling, cough-before-shell timing, pitched/turning shots, death during windup and multiplayer timing. Runtime smoothness and visual quality remain unverified.

## Follow camera distance increased to 150 studs (2026-11-06)

The requested change concerns the HUD camera distance, not the Map Depth slider threshold. DefaultZoom is now 150 instead of 100. The follow-mode reference readability budget is 12 instead of 18 chassis pixels, permitting that distance; tanks appear smaller as more ground becomes visible. Whole-map readability/settings and its existing mode transitions remain unchanged.

The old map-axis containment limit also capped the 230-square arena around 131 studs. It now applies only to long/thin maps (long axis more than twice the short axis). Regular maps can reach 150 with outside-map ground visible; long/thin maps retain their narrow-axis reduction. Ground-footprint and maximum-distance safety caps remain. Camera orientation and central 20% dead zone are unchanged.

Verification: all 20 source files compile; 12,331 camera assertions and all input, combat, projectile, windup and barrel-animation suites pass. New cases verify 150-stud follow distance for a 230-stud width at depths 200/230/300/400 on desktop, phone and ultrawide windows, including footprint limits. Both place formats rebuild and whitespace checks pass. Studio was not run; rebuild/reconnect and restart Play to verify the HUD distance and visual framing.

Follow-distance tuning (2026-11-06): DefaultZoom is now **135 studs**, replacing 150. Other camera settings are unchanged. Camera distance regression expectations are updated; all automated suites pass, both Rojo place formats rebuild and whitespace checks pass. Studio was not run.

## Level 1 cute toy-tank proportion refinement (2026-11-06)

Visual/model changes only: the existing orange turret is shorter and wider (6.5×2.25×5 studs instead of 5.8×2.8×4.8), with corner radius increased from 0.5 to 0.85 for a molded-plastic silhouette. Its lower seating plane stays fixed; the hatch is lowered and cheek mounts/stripes move outward to suit the wider shell. The chassis is 6.6×1.5×7.6 (previously 6×1.7×7.8), with 0.65-stud rounding. The deck is slightly wider/thicker with softer edges, and the front plate is wider and rounder. Orange/yellow paint, dark tracks, exposed road wheels, grille, bolts, lights and mechanical trim remain.

The cannon diameter increases from 1.1 to 1.6 studs, with matching larger mantlet, collar, bands and bore. Shared renderer diameter constants keep construction, pose reset and elastic animation consistent. Barrel length, local attachment transforms, turret/aim pivot and muzzle position are preserved. The traveling swelling/bulge, expanding mouth, recoil, chassis spring/bounce and tread/wheel setup retain their existing animation behavior. No server, projectile, firing timing, combat, input or camera settings change; follow distance remains 135 studs.

Validation: 20 sources compile; 94 input, 12,331 camera, 37 combat, 56 projectile and 203 barrel-animation assertions plus the windup suite pass. Both Rojo place formats build and whitespace checks pass. Studio was not run. Inspect the shorter rounded turret, hatch/cheek placement, thick cannon and cough, extreme pitch clearance, independent aiming, bounce, tracks and death/respawn in Play. Automated checks do not establish rendered appearance or visual clearance.

## Minimum-fit camera with a hard 135-stud maximum (2026-11-06)

MaxZoom is now 135 for both whole-map and follow modes; previously overview could reach 260 even with DefaultZoom=135. The solver prefers the smallest fitting distance (with the existing 45-stud preferred minimum), and follow mode also considers the fitting distance before applying its distance/readability/footprint limits. Orientation, 20% dead zone and gameplay are unchanged. At production orientation/FOV/margins, a 40-square map fits at 108.79 studs; a 53-square still fits below the cap, while a 54-square requires follow mode. A 100-square requires about 225 studs to frame fully, so it remains capped at 135 and pans.

Camera Tests sliders now start at 25 rather than 100, permitting tests of small maps within this tighter distance limit; the maximum remains 2,000. This supersedes older overview transition and slider-range notes. Tests verify minimum-fit selection, monotonic zoom for 25–400 square maps, the hard 135 cap, overview corner framing and updated slider values. All automated suites pass, both Rojo formats rebuild and whitespace checks pass. Studio was not run.

## Studio Redraw Map button (2026-11-06)

In Studio Play, expand **Camera Tests (Studio)**, choose width/depth, then press **Redraw Map (resets tanks)**. Sliders remain local camera previews until pressed. Redraw resizes the actual floor/walls and rectangular authoritative movement bounds, rebuilds practice targets, clears active/preparing shells, and resets every tank's health/pose/spawn/command. Targets keep their normal dimensions and combat rules; narrow maps use fewer targets to avoid overlapping target geometry. Very small maps are intended for solo or small-client framing tests; many tanks can crowd their limited spawn space.

The server creates the redraw RemoteEvent only in Studio, validates integer Vector2 dimensions from 25 to 2,000, requires a connected tank owner, and rate-limits redraws to once per second. Arena dimensions and a revision attribute synchronize the actual camera map on every Studio client and clear previews after each redraw, including repeated same-size redraws. Late joiners read current dimensions. Reset to Actual Map only clears a camera preview; it does not undo a redraw. Stop Play to restore the default 230×230 arena. Published play has no redraw remote or developer panel.

TankSimulation accepts optional rectangular dimensions while retaining its original square fallback. Shared ArenaLayout validates dimensions and computes bounded development spawns. Camera projection, the hard 135-stud maximum, dead zone, input and combat rules remain unchanged.

Verification: 21 sources compile; all existing suites pass, plus arena dimension validation, spawn bounds, rectangular movement, redraw-button payload, actual-camera update/preview clearing and published-client isolation checks. Both Rojo formats build and whitespace checks pass. Studio was not run. Verify real wall/floor resizing, target placement, tank reset, edge collision and camera match at 40×40, 230×100 and large rectangular dimensions; test two clients, repeat same dimensions, join after redraw, and stop/restart Play to confirm default restoration. Network/GUI behavior still needs engine validation.

## Cartoon muzzle spark burst (2026-11-06)

The delayed shell-release event now creates a small yellow/orange eight-spark starburst and a fading warm flash at the cannon opening. Sparks expand sideways and fade in 0.16 seconds, behind the departing shell. The effect uses the rendered cannon tip/direction (including bounce/recoil) when available, with authoritative shot origin/direction as fallback. Temporary Neon parts are noncolliding/nonqueryable, tweened and cleaned by Debris. The Shot event adds direction for effect alignment; projectile timing, flight, damage, cannon swelling and all other mechanics remain unchanged.

All automated suites pass, both Rojo formats build and whitespace checks pass. Studio was not run. Check burst visibility, pitch/yaw alignment, emission behind the exiting shell and cleanup during held fire in Play.

Muzzle-burst visibility tuning (2026-11-06): enlarged the flash from 1.1 to 3.2 studs initially, expanding to 5.5; increased sparks from eight to twelve, with 0.55-stud thickness, 2.2-stud length and 4.2–5.5-stud radial travel. Brief initial holds and 0.24/0.32-second fades make the burst more readable at the normal 135-stud camera distance. Effect parts cast no shadows. Gameplay and shot timing are unchanged. All automated suites and both builds pass; Studio visibility still requires checking.

## Suspension affects turret and release-time aim (2026-11-06)

Bounce is now server-owned shared simulation state, because hull motion affects actual firing. The existing damped suspension supplies vertical bounce plus movement-dependent chassis pitch (up to about 2.9 degrees) and roll (about 2 degrees), blending out when stopped. The renderer smooths replicated suspension and gives both hull and turret the same translation/tilt. Independent turret yaw and cannon elevation remain attached on top of the tilted chassis; recoil and cannon cough remain. Tracks remain grounded and camera policy is unchanged.

TankSimulation.shotPose computes turret-pivot height and world barrel direction from suspension, chassis yaw and turret yaw/pitch. WeaponWindup samples this pose at actual release after the existing 0.20-second delay, then the existing cover sweep launches the shell. Once released, a shell retains its straight launch direction; later hull/turret movement does not steer it. No random spread, gravity, homing or automatic stabilization is added. Movement now makes aiming harder through real barrel tilt. The arena is still flat; rocky terrain traversal/terrain-normal sampling is not implemented by this change. Previous notes calling bounce purely cosmetic are superseded.

Validation: all 21 sources compile and all automated suites pass. New suspension-firing tests cover raised/lowered origin, pitch, roll when firing sideways, chassis-yaw transformation, changed pose during windup, fixed post-launch direction, movement aim oscillation and settling to stable aim. Both Rojo place formats build and whitespace checks pass. Studio was not run. Check turret/hull rocking together, aim while moving versus stationary, pitched shots and close cover, muzzle/spark alignment, and two-client behavior under latency. Cosmetic snapshot smoothing can still create small transient differences from the authoritative release pose.

## Mixed terrain test arena (2026-11-06)

The arena now has deterministic terrain regenerated on startup and every Studio Redraw Map:

- **Shallow water, east:** blue reflective water patch with surface glints; driving/reversing is 10% slower. Moving tanks create expanding hollow ripples and droplets, with a stronger entry splash.
- **Mud, west:** brown patch and ruts; 25% slower in both directions, with short dirt flecks while moving.
- **Rocks, northwest/west:** rounded gray boulders that tanks can climb. Ground samples lift/pitch/roll the hull and turret, changing authoritative release-time aim.
- **Fallen logs, west of center:** low brown cylinders with pale cut ends; traversable bumps that also affect suspension/aim.
- **Woods, northeast:** a green patch with spaced trunks and rounded foliage. Trunks block driving and shots; decorative crowns do not block projectile queries.

`src/shared/Environment.luau` creates scaled terrain descriptions and supplies surface speed, ground height/tilt and trunk collision. `src/server/EnvironmentBuilder.luau` builds matching ordinary Roblox Parts. `src/client/TerrainEffects.luau` emits throttled local ripple/splash/mud effects with tweening and Debris cleanup. No imported assets or voxel Terrain water are required: water is a shallow surface effect, with no swimming, buoyancy, drowning or current. Ground height and pitch/roll use a smoothed scripted contact approximation, not physical suspension or a general terrain mesh solver.

Target rows, the center passage and southern spawn approach are reserved when placing rocks/logs/trees. On maps smaller than 60 studs along either axis, solid terrain props are omitted to preserve room to drive; scaled water/mud/woods surface patches remain. Extremely small maps may have adjacent terrain regions. Redraw removes the old environment rather than accumulating it. Rock/log/trunk projectile initial overlaps now test ellipsoid/cylinder solids instead of treating their empty bounding-box corners as hits. Existing shell speed, 0.20-second windup, cooldown, damage, cannon cough and 135-stud camera cap remain.

Verification: 24 source files compile; all existing suites pass, plus **202 environment assertions** for deterministic generation, resized-map containment, target clearance, water/mud forward/reverse speed, normal grass speed, rock elevation/tilt/actual aim, traversable logs, trunk collision, real builder geometry/replacement and water/mud effect emission/throttling/cleanup. Curved-cover tests exercise rock/log overlap boundaries. Both Rojo place formats build and whitespace checks pass.

Roblox Studio was not run. Reopen/reconnect and restart Play. Drive through water/mud in both directions and compare pace, check entry splash/ripples at normal zoom, climb rocks/logs while aiming/firing, drive between trees and shoot at trunks, and redraw square/rectangular/small maps. Inspect target/spawn clearance, visual ground contact, foliage occlusion, multiplayer replication and effect/render cost. The mocks do not establish real engine rendering, spherecasts or performance.

## Boomer and Rattler: two playable test vehicles (2026-11-06)

The orange cannon tank is now named **Boomer**. Its model dimensions, orange/yellow paint, tracks, road wheels, suspension, turret, cannon swelling/recoil, muzzle burst and original weapon tuning are preserved. The second vehicle is **Rattler**, based on the bottom-left green concept in `references/tank-styles.png`. Following the user's clarification, Rattler has **four chunky wheels and no track belts**, a distinct sloped green hood with ivory-framed panels, rounded fenders, a narrow raised turret, side ammo drums and a six-barrel Gatling assembly. The model is a practical primitive-Part interpretation of the artwork, not an imported mesh.

### Driving and selection

Boomer retains its original instant throttle and pivot steering. Rattler uses a separate bicycle steering model: 30-stud/second forward and 18 reverse limits, acceleration, braking, coasting drag, smoothed front steering and signed reverse yaw. It cannot pivot turn at rest. Wheels roll with speed; only the front pair steers. Both reuse the terrain/contact, suspension, aiming contract and world collision paths. Horizontal control remains available during cartoon recoil flight; this is kinematic game movement, not a tire/traction physics simulation.

The two named selector buttons sit below Input on the HUD and support click/touch/gamepad activation. The server owns selection, accepts only the two allowed IDs and limits switches to once per 0.5 seconds. Switching preserves health, pose, air velocity and weapon cooldowns; it cancels pending cannon preparation and releases input. Rattler's heat ledger lives on the player's tank record and survives switching away/back. Already-launched shells retain their original weapon's speed/damage and continue flying. Snapshots carry type and generation; TankRenderers destroys the old model once and creates one replacement. Late shot/preparation events cannot animate an older vehicle generation. Respawn and Redraw Map preserve the chosen type; the explicit development redraw resets the round and heat. This selector is available in the test experience, not a pre-battle garage or saved account preference.

### Rattler weapon, heat and recoil flight

Rattler fires 10 rounds per second, with 6 damage, 85-stud/second speed, 0.22-stud collision radius, the existing 320-stud range and checked seven-stud muzzle advance. It uses the same server swept collision, cover obstruction, target damage and tank damage paths as Boomer; no client damage/hit claims are accepted. Its rotor spins visibly during firing and coasts down afterward. Muzzle flashes, chunky sparks, smoke, ejected brass and layered pitched built-in Roblox sounds give it an exaggerated mechanical chatter. Audio audibility/asset availability and visual feel remain Studio checks.

Firing accumulates heat measured in seconds. At 3 continuous firing seconds or 3 accumulated heat seconds, firing stops and a mandatory 2-second lockout begins. The held trigger cannot fire during the lockout; it may resume automatically only after the full cooldown. Releasing early stops rounds immediately, but heat persists: recovery starts only after 0.4 seconds idle and removes 0.6 firing-seconds per idle second. Rapid tapping cannot reset heat. During the forced cooldown heat drains fully over two seconds, even with the trigger held. Switching tanks ticks the same ledger rather than creating fresh heat state. HUD text shows heat percentage, BRRR while firing and cooldown countdown.

Server-owned recoil flight progressively lifts Rattler, with increasing thrust as heat rises. Vertical speed is bounded (+12/-24 studs per second), lift is capped at 24 studs, and gravity is 18 studs/second squared. Releasing or overheating removes thrust; inertia carries it briefly before it falls. Landing clamps at the sampled terrain height, adds a suspension compression impulse and lets the existing spring rebound. The whole vehicle and hitbox rise, so authoritative release-time shot origin changes with the vehicle. Bounds and conservative obstacle checks still apply; this is not unrestricted flying or Roblox physical network ownership. Switching in the air preserves the fall instead of teleporting to the ground.

### Module map

- `shared/TankDefinitions`: allowlisted vehicle IDs and per-vehicle drive/weapon/flight tuning; Boomer points directly to the original TankConfig.
- `shared/RattlerDrive`: car acceleration and steering.
- `shared/RattlerWeapon`: deterministic heat/burst/recovery/lockout state.
- `shared/RecoilFlight`: bounded ascent, gravity and landing impulse.
- `shared/TankSelection`: validated selection and state preservation.
- `client/RattlerVisual`: distinct wheeled model, Gatling rotation, muzzle effects and audio.
- `client/TankRenderers` and `client/TankSelector`: model lifecycle and simple server-confirmed selection UI.

Boomer's existing weapon windup remains separate. Projectiles and practice-target impact functions accept optional server weapon tuning/damage, preserving their original defaults. Camera angle, dead zone, zoom limits, world, targets and terrain generation are unchanged.

### Verification and remaining runtime checks

All **32 Luau sources compile**. Existing input, camera, target combat, projectile, windup, suspension firing, barrel animation and environment suites pass. Added vehicle tests cover continuous fire/cooldown at 30/60/120 simulation Hz, bounded rising/falling, early release, landing compression/rebound, idle recovery, tap abuse, switch abuse, health/altitude preservation, forward/reverse car steering, no stationary pivot, mud speed, per-weapon projectile damage/speed, repeated model replacement and selector cleanup. Production model tests execute both constructions/animation paths, wheel roll/front steering, rotor motion, Boomer cough, muzzle effects, sounds and timed cleanup using mocks. The production server entrypoint also runs with two mocked players, checking actual Boomer preparation/release, Rattler rapid fire/lockout/lift, airborne switching, invalid selection, ownership and departure cleanup.

A separate pre-change baseline audit compared Boomer's complete Part geometry/colors/anchor transforms/animation visibility over 30 frames and movement, aiming, suspension and firing over 360 simulation steps. It passed over 112,000 assertions, including the renderer/integration checks. Both Rojo place formats build and whitespace checks pass. No commit or push was performed.

Roblox Studio/device play testing was not available. Next, open the rebuilt place and restart Play: compare both models with the reference; drive Boomer and Rattler forward/reverse/around terrain; steer at rest and rolling; aim/fire while bouncing; hold Rattler fire through 3 seconds plus the full 2-second cooldown; release early and observe landing; tap rapidly; switch while hot/airborne; redraw and respawn; and test two clients. Verify audio, visuals at the 135-stud camera distance, UI fit on phones, camera framing during flight, real spatial query behavior and multiplayer rendering/replication cost. Mocked checks do not establish those runtime results.

## Rattler actual-turret recoil drift (2026-11-07)

Each released Rattler round kicks the actual turret slightly in yaw and pitch, affecting subsequent rounds. Shared RattlerAim supplies bounded, server-seeded per-shot displacements and recovery: base yaw/pitch kick strengths are 2.4°/1.4°, growing up to 40% with heat, with maximum offsets of ±6° yaw and ±4° pitch. Offset recovery decays at 4 per second (0.25-second time constant), so sustained fire wanders and idle aim settles. At a displacement limit the next outward kick bounces inward rather than sticking to the clamp. Per-player pseudo-random state lives with the heat ledger; no client chooses kicks or hit directions.

Cursor/stick input continues to control the desired turret aim. TankSimulation.turretAngles adds the actual recoil offset (respecting cannon pitch limits), and shotPose uses that direction plus hull pitch/roll. The renderer consumes the same angles, including on reset/switch. The server launches a straight round from the current actual pose, then applies its kick to the turret for the next round; there is no invisible projectile-only spread or post-launch steering. Existing snapshot smoothing can still create brief visual/network interpolation differences. Boomer's actual aim and weapon behavior are unchanged, as are Rattler drive, flight, heat and cooldown.

Verification: all 33 sources compile; existing suites pass, with 2,362 vehicle assertions and 85 model/server-integration assertions. New tests cover per-round displacement, actual-angle/shot-direction agreement, desired-aim separation, bounded offsets, left/right wandering, recovery, visible muzzle alignment, server replication and production shot variation. Both Rojo place formats build and whitespace checks pass. Studio was not run. Hold the cursor steady and fire in Play to assess turret shake/spread at normal zoom, release and observe recovery, then check touch/gamepad aiming and two-client latency. No commit or push was performed.

## Boomer cannon aim recoil (2026-11-07)

Boomer now also kicks its actual turret after each shell leaves the barrel. Its yaw/pitch kick strengths are 8°/6° (versus Rattler's 2.4°/1.4° before heat scaling), bounded at ±12°/±9°. Its recovery rate of 5 per second removes over 95% of displacement during the existing 0.65-second interval between shell releases. The existing 0.20-second preparation, damage, cannon swelling/retraction and muzzle effects remain unchanged. A shell is launched from the pre-kick actual pose, then the kick displaces the turret; subsequent rounds use its recovering pose rather than cursor direction directly.

The shared aim-recoil module is now named `TurretRecoil` (replacing `RattlerAim`), with per-vehicle tuning in TankDefinitions. Rattler retains its existing heat-scaled kicks and recovery. Both renderers already use TankSimulation.turretAngles, so the visible orientation matches the shared firing-pose calculation. This supersedes earlier statements that Boomer has no turret aim kick.

Verification: all 33 sources compile; all existing suites pass, including new Boomer strength, 95% reload recovery, near-restored firing direction and production shell-release kick checks. Both Rojo formats build and whitespace checks pass. Studio was not run; inspect the larger Boomer turret knock and recovery while holding the cursor steady, and compare it with Rattler's sustained wandering. No commit or push was performed.

## Rattler violent per-round jumps and hard landing (2026-11-07)

Rattler no longer rises under continuous smooth thrust. Each actual released bullet adds an immediate upward velocity impulse (14 studs/second, rising to 17 with heat), plus an alternating 5° pitch/7° roll impulse and a suspension jolt. Body rotation kicks are bounded and decay rapidly, and because they feed shared suspension pose they also disturb actual aim. No impulse is applied just for holding the trigger during a cooldown. Lift remains capped at 24 studs and upward velocity at 28 studs/second; downward velocity is capped at 72.

Gravity is now 90 rather than 18 studs/second squared. A maximum-height drop from rest reaches ground in about 0.73 seconds with a strong impact. Landing safely clamps to sampled ground, adds a much stronger compression impulse (up to 14), and rebounds through the existing suspension spring. A radial dust burst and low thump emphasize the slam. Rattler uses faster vertical/suspension rendering and snaps its vertical pose to ground on a new landing event, rather than smoothing away the impact. Horizontal movement/camera behavior remain unchanged; Boomer's ordinary movement and recoil are unchanged. Switching while recoiling preserves the remaining air momentum and lets the shake decay rather than leaving a tilted replacement model.

Verification: all 33 sources compile; all existing suites pass, including 2,372 vehicle assertions and 98 renderer/server-integration assertions. Added tests prove that trigger state alone causes no lift, individual rounds immediately change velocity and shake, early release falls/lands, the 24-stud drop is fast and hard, landing clamps safely, model pose snaps at impact and dust is emitted only once per landing. Existing 3-second burst/2-second cooldown checks still pass. Both Rojo place formats build and whitespace checks pass. Studio was not run; restart Play to assess violent firing motion and slam at normal zoom. No commit or push was performed.

## Rattler descent-to-level projectiles (2026-11-07)

Rattler's weapon now uses `Trajectory.Kind="DescendThenLevel"` in TankDefinitions. Default descent is **35° below horizontal**, configurable via `Rattler.Weapon.Trajectory.DescentAngle` (try 40°); `LevelingDistance=6` controls the short curved transition. With sufficient altitude, the barrel and rounds point down at the configured angle, travel diagonally in a straight line, then enter a tangent-continuous circular leveling arc ending at horizontal flight. Heading is captured once from actual launch aim/recoil and remains fixed. No enemy lookup, homing, target seeking or post-launch heading adjustment exists.

The shared standard muzzle height is now `TankConfig.MuzzleHeight=3.6`, used by Boomer's actual pivot/rendering as well as Rattler's leveling plane. The server adds the actual arena floor top (`Floor.Position.Y + Floor.Size.Y/2`), rather than using an unexplained absolute world Y. Ground relief still blocks shots normally; this does not track terrain height or guarantee hitting enemies on hills. At/below that plane, a projectile stays horizontal at its current height. At low altitudes above it, the physical seven-stud barrel begins with a shallower portion of the leveling profile so the muzzle cannot be placed below the target plane; full 35° is used once there is room for both barrel and leveling arc.

`shared/ProjectileTrajectory` supplies distance-based launch direction, straight descent, smooth curve and horizontal samples. `ProjectileSimulation` first sweeps the straight barrel for close cover, then enables the free-flight path. It splits sweeps at stage boundaries and into at-most-half-stud segments within the curve, checking obstacles throughout instead of teleporting to the level plane. Speed stays constant along the path; range/lifetime accounting, shell radius, damage, exclusions, initial-overlap checks and impact effects are preserved. The server poses the visible shell from the same actual position/tangent every update. Rattler's articulated Gatling assembly uses the same shared firing-pose calculation, so the model points down with its initial trajectory. The weapon constrains vertical launch pitch; yaw recoil and actual horizontal heading still determine where each round goes. Boomer remains on the original straight-flight path, with its existing recoil, windup and damage unchanged.

Verification: all **34 source files compile**, all existing suites pass, and **1,855 trajectory assertions** cover 35°/40° configuration, low/below-plane launch, shared/shifted floor height, continuous leveling, unit tangent/constant speed, range expiry, descent collisions, clearing low walls and hitting a ground tank after leveling, thin cover in the curve, close barrel obstruction, large-step/frame partition behavior, frozen heading despite enemy movement and unchanged Boomer straight flight. Model tests verify the airborne Gatling visibly points down at 35°. Both Rojo place formats build and whitespace checks pass. Studio was not run. Test Rattler above a wall versus directly into one, hold cursor steady through ascent/descent, inspect barrel clearance and shell turning at normal zoom, and compare Boomer. Network smoothing/visual feel still need real engine verification. No commit or push was performed.

## Rattler jackhammer recoil: low chaotic hops and air inertia (2026-11-07)

This replaces the flying/hovering recoil behavior. `shared/RattlerRecoil` owns Rattler's weapon-powered motion; its tuning is now `TankDefinitions.Rattler.Recoil`, separate from car drive and weapon tuning. `RecoilFlight` remains only a compatibility module returning the new behavior.

The first grounded shot applies a ballistic velocity calculated for a seeded **4–5 stud hop**. Sustained firing uses independently seeded hop peaks of 3.4–5.1 studs, varied minimum kick gaps (0.12–0.24 seconds), and small response delays (0.015–0.05 seconds). While descending, eligible rounds can kick it back up; some deliberately allow a full thud before the next hop. Rising shots do not stack upward velocity. Gravity is 180 studs/second squared, and the absolute local-ground height cap is **6 studs**. A cap is only a safety guard; normal hops use velocity integration and ballistic energy budgets, not animated/teleported heights. No sinusoidal target drives Rattler's body: suspension and rocking respond to irregular recoil/terrain/landing impulses and settle physically.

Every actual round adds a small horizontal impulse opposite its captured world firing heading, regardless of chassis yaw. Airborne world X/Z velocity is preserved, with no player steering, throttle acceleration, braking or air drag; turret input remains active. Driving/traction resumes only at contact. World bounds, trees, targets and other tanks still block movement and stop the blocked momentum. Recoil state carries through midair selection changes rather than enabling an air-control bypass. Landing clamps to the sampled support surface, compresses the suspension, rebounds and emits the existing dust/thump once per impact.

Ground support comes from the existing Environment surface/contact geometry at the actual X/Z position, plus the real arena floor elevation. Rattler no longer smooths that support into a fictitious flat Y=0 base. Its hitbox follows the authoritative simulated position every step. Boomer retains its original movement/suspension path. Projectile trajectories, damage, firing cadence, heat/cooldown, aim recoil and camera settings are unchanged.

Motion randomness is a separate per-player seeded stream advanced only by recoil events. It varies physical intensity/timing/rocking, never consumes the weapon accuracy stream or adds projectile spread. Replaying the same seed and fixed-step inputs reproduces the same motion. Actual movement/pose still affects muzzle origin/heading through the established shared shot-pose code.

Verification: all 35 source files compile and all suites pass, including **5,743 jackhammer assertions** covering first-hop apex, six-stud ceiling, repeated-shot abuse, forward/back/side recoil, airborne steering/braking lockout, turret control, terrain support at nonzero elevation, hard landing/settling, obstacle momentum stops and exact deterministic replay. The representative sustained-fire test recorded 10 irregular hops, with 105 samples in the 3–5 stud band and 16 near-ground samples. Production-server checks now verify hitbox/snapshot position alignment. All previous projectile trajectory tests remain passing. Both Rojo formats build and whitespace checks pass. No commit or push was performed.

Studio was not run. Restart Play and hold Rattler fire while stationary, driving, firing sideways and firing backward; try steering/braking mid-hop, release early and compare heavy landings, cross rocks/logs, fire near obstacles, and test two clients. Check normal-zoom shake/dust visibility, the low hop envelope and grounded handling resumption. Visual feel, real collision queries and network interpolation still require engine validation.

## Rattler exaggerated left/right lurch (2026-11-07)

Every Rattler round now throws the hull/turret to a seeded random **7–10° roll** left or right. This replaces small accumulating roll deltas that could cancel and become hard to see. Two consecutive throws may favor the same side, but the next must go the other way, preserving irregularity without long one-sided runs. Roll recovery is 10 per second so the lurch remains readable between rounds. Physical body pitch/roll updates immediately on the shot tick. Existing pitch jolts, jackhammer height/velocity, horizontal shove, terrain contact, projectiles and Boomer behavior remain unchanged.

All suites pass, including 6,015 recoil assertions for per-round roll strength, both directions, streak limits, immediate physical pose and settling. Both Rojo place formats build and whitespace checks pass. Studio was not run; restart Play to assess the exaggerated struggling-with-an-oversized-gun personality at normal zoom. Nothing committed or pushed.

## Rattler visible full-vehicle rocking correction (2026-11-07)

The old renderer kept all wheels on a level base while only body/turret panels tilted; short server roll impulses also decayed between snapshots and were smoothed again. Rattler now applies a common rocking transform to wheels, hull and turret around its weapon mount. The shot event carries the full seeded physical roll and shot serial immediately after recoil is calculated. The renderer exaggerates that roll 1.8× (roughly 13–18°), holds briefly, then recovers between rounds. Snapshot serials provide fallback without replaying stale jolts. Ground clearance limits exaggeration near contact to avoid visibly burying a grounded tire.

Only presentation/event metadata changed: approved horizontal shove and vertical hop physics, seeds/timing, hitboxes, damage, projectile trajectories and camera remain unchanged. The common visual pivot keeps the muzzle origin fixed, and the barrel still uses the authoritative firing-direction calculation. Boomer's renderer path and shot effects are unchanged.

Verification: all 35 sources compile; all suites pass, including 547 renderer/server checks proving opposite wheel pairs visibly separate by over two studs on a 10° input jolt, hull/turret roll together, opposite shots reverse the visible lurch, stale events cannot reset it, movement position and barrel direction stay unchanged, and visual motion settles. Existing deterministic recoil metrics remain exactly 10 hops / 16 near-ground samples / 105 mid-band samples. Both Rojo formats build and whitespace checks pass. Studio was not run; restart Play to assess the full-vehicle rocking at normal zoom. Nothing committed or pushed.

## Studio movement-speed HUD and recoil boost measurement (2026-11-07)

A Studio-only speed readout appears below the vehicle selector. It displays **XZ SPEED** in studs/second, **PEAK** horizontal speed, normal **DRIVE** speed, signed **VERT** speed, total **3D** speed and a highlighted **BOOST** above the vehicle's normal forward driving limit. This separates actual horizontal travel from jumping: vertical recoil cannot masquerade as a horizontal speed bonus. Peak resets on vehicle switch, respawn or development redraw generation.

`shared/MovementTelemetry` measures resolved position differences each server simulation step, after terrain/target/tank/boundary collision correction. It does not use requested throttle or intended longitudinal speed. Snapshots carry the measurements; `client/SpeedDebugHud` only renders them and changes no simulation settings. The server peak captures short boosts between snapshots.

The deterministic speed test confirms the existing side effect: full-speed Rattler driving forward while firing backward can reach the **36-stud/second recoil cap**, compared with **30** normal forward drive (**+20%**). Forward firing opposes forward motion instead. Airborne control restrictions remain, so line up steering before hopping. Boomer's normal drive reference remains 24 studs/second.

Verification: 37 source files compile and all suites pass. Eleven telemetry/HUD tests cover XZ versus vertical/3D measurement, blocked movement, peak reset, recoil boost, forward-fire comparison, formatting, missing state, cleanup and Studio isolation. Both Rojo place formats build and whitespace checks pass. Studio was not run; restart Play and check the new panel below the selector, including normal speed, backward-firing boost and peak reading. No commit or push was performed.

## BW v0.1 proof of concept (2026-11-07)

The user explicitly lifted the prior BW deferral and supplied a first language specification. BW is now an additional server-authoritative control mechanism, using the existing tank simulation rather than replacing movement, aiming, collision or weapons.

### Modules and execution

- `shared/BWConfig`: limits, tolerances and the exact default demonstration source.
- `shared/BWParser`: data-only, case-sensitive command validation with source line numbers; decimal numbers, whitespace, blank lines, CRLF and inline `#` comments. Converts to instruction records, never evaluates code.
- `shared/BWTankAdapter`: compass conversion and bounded normal input generation. World headings increase clockwise from north; internal yaw remains the existing counterclockwise radians. Rattler receives throttle plus steering for chassis turns; Boomer gets pivot input. Distance approach slows/brakes through existing drive response, without changing acceleration or coordinates.
- `shared/BWRuntime`: one instruction state, starting pose/axis, signed displacement or accumulated angular progress, timer/stuck budgets, trigger acceptance/release tracking and terminal status. It advances in the existing fixed server tick without waits or coroutines.
- `server/BWController`: owns programs per player tank, source parsing, run/stop/status metadata and input/pending-shot cleanup. BWRun/BWStop remotes use sender ownership, monotonic request IDs and a half-second Run rate limit. A newer Stop prevents an older delayed Run from starting afterward.
- `client/BWIDE`: multiline monospaced TextBox in a scrolling editor with line gutter, Run/Stop, source-line/current-instruction display and output/errors. Its separate safe-area ScreenGui coexists with the existing tank selector, camera and speed/debug UI. Source is initialized from BWConfig and remains local to this session.

Manual input packets are ignored by the server while BW owns a tank. InputController also suspends/resets manual providers until the server reports BW stopped. Text entry uses the normal focus suspension. Terminal cleanup clears throttle, steering and trigger intent, pending Boomer preparation and stale tick input, requiring fresh manual fire release. Destruction, respawn, selection, redraw and disconnect cancel the program. Current physical momentum and already-released shells are preserved.

Each move projects authoritative position displacement onto its starting forward/back axis, counting recoil along that axis and excluding sideways/vertical motion and wheel spin. Rotations add signed per-tick angular deltas, allowing multiple revolutions and 0/360 crossing; absolute target headings are normalized and converted to the requested directed distance. Turret headings use actual world gun direction, independent of chassis/camera. Tolerances are 0.12 studs and 0.8 degrees.

Weapon counters report accepted activation and released shells without changing existing mechanics. Single fire holds only until one logical activation is accepted, releases immediately and waits for that shot. Timed fire holds for the requested simulated duration, then releases and waits for any committed preparation to finish. Consecutive commands have a neutral tick between them. Overheated Rattler waits through its real cooldown; Boomer retains its 0.20-second windup and 0.65-second interval. Stop cancels an unreleased preparation, but does not delete released shells.

### Bounds and limitations

Limits are 16,384 source bytes, 400 source lines, 128 commands, 1,000 studs per distance, 1,440 degrees per relative rotation, absolute arguments ±36,000 normalized modulo 360, and 10 seconds per timed fire. Runtime allows 180 simulated seconds per program, a bounded per-instruction budget up to 90 seconds (fire waits up to 15), and errors after 3 seconds without meaningful movement/rotation progress. Runtime/syntax errors include the original source line. Execution is quantized to the existing 60 Hz simulation tick; very short positive firing durations last at least one tick.

This PoC has no pathfinding, collision avoidance, storage, language variables, loops, conditions, sensors, tracking, custom functions, parallel instructions or AI code generation. Rattler's inertia and airborne restrictions remain real: neutral intent on Stop or completion does not instantly freeze its physical velocity. Initial momentum, terrain, recoil and obstacles can affect the physical path; unreachable instructions stop with a line-numbered error. The demo is not a promise to hit particular targets.

### Verification

All **43 Luau sources compile** and all existing suites pass. **6,098 BW assertions** cover valid/invalid syntax, comments/blank lines, limits and normalization, relative/absolute/directional/multi-revolution turns, actual projected travel, movement tolerance, sequential execution, single/timed/zero fire, cooldown waits, stuck/program/weapon timeouts, cancellation, death/generation cleanup, IDE submission/errors/status/gutter/lifecycle, provider ownership and tank-specific behavior. Default programs execute through the real movement and weapon modules: open-map Boomer ~7.82 seconds / 5 rounds, Rattler ~15.85 / 21; with the actual terrain profile from the original spawn, ~8.63 and ~18.05 seconds respectively. Different rates/timing are intentional consequences of existing physics.

The production server entrypoint is also exercised with two mocked players. Its integration checks run both default programs with actual target/collision/control loops, verify shot counts, ignore conflicting manual inputs, cancel a preparing Boomer shell, reject stale Run after Stop, preserve per-player ownership, and cancel on selector/redraw/disconnect. The combined model/server suite passes 1,766 assertions. These tests stub engine spatial queries and are not Studio play tests.

Both `.rbxl` and `.rbxlx` Rojo builds and whitespace checks pass. No commit or push was performed. Reopen/reconnect and restart Play, open BW Editor and run the default on each selected vehicle. Still verify native TextBox editing/caret/scrolling, source-line display, focus transitions and Run/Stop with mouse/touch/gamepad; repeat while moving, reloading, overheated, blocked and airborne; confirm selection/death/respawn/redraw return control; and test two clients with latency. Confirm the existing visual camera/controls/terrain/combat remain usable. Future work should refine editor ergonomics and control feedback only after those runtime results, before considering additional language features.

## BW best_effort option (2026-11-07)

Every command now accepts `best_effort=true` by default. Examples:

```python
forward(20)                              # try; skip if stuck/timed out
back(5, best_effort=false)                # stop program if this fails
turn_right(to=90, best_effort=true)
turret_left(45, best_effort=false)
fire(best_effort=true)                    # one logical activation
fire(2, best_effort=false)                # hold the normal trigger for 2 seconds
```

The parser supports named `best_effort` alongside numeric arguments or `to=heading`; named arguments may be reordered, but positional values must come first. Boolean literals are lowercase `true`/`false`. Duplicate, unknown, malformed or missing arguments remain syntax errors. Existing source needs no edits and now gets the requested best-effort default.

On instruction stuck/timeout failure, best effort issues a neutral input tick, cancels abandoned prepared fire, increments the skipped count, records a line-numbered warning and advances. BW retains ownership for the following command, including another fire command. `best_effort=false` preserves fail-fast behavior. The IDE keeps the most recent warning visible through subsequent instructions/completion; completion reports the skipped count. Fire success still means weapon activation/release or held-trigger duration, not a guaranteed target hit.

This option does not disable source validation, the 180-second overall budget, Stop, destruction, respawn, selection, redraw or disconnect cancellation. Those remain terminal. Cooldown, heat, accuracy, projectile and movement mechanics are unchanged.

Verification: all 43 sources compile and all existing suites pass. A new 108-assertion suite covers defaults/true/false for all command forms, keyword order and validation, skip continuation, strict failures, every instruction timeout including single/timed fire, pending-shot/input cleanup, continued weapon ownership, global safety and IDE warnings. Both default demonstrations still complete without skipped instructions on both tanks, including the production server tests. Both Rojo formats build and whitespace checks pass. Studio was not run; verify visible warnings and continuation by blocking a movement command, then compare `best_effort=false`. Nothing committed or pushed.

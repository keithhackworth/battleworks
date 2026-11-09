# BattleWorks: Boomer and Rattler

**BW language reference:** [BW_LANGUAGE.md](docs/BW_LANGUAGE.md) — syntax, all commands, inputs/returns, CPU costs, buses, loops, scanners and examples.


## Continuous scanning loops

Valid scan/print loops now use rolling histories instead of lifetime scan/log/command quotas: 128 recent scan snapshots, 256 IDE output entries, and 512 terminal command records plus active/queued work. Excessive logging is rate-limited with an explicit notice; it does not stop the tank program. The eight-thread scanner example requires Rattler (Octa); Boomer remains single-core. CPU/queue/scanner-rate limits and the normal 180-second program timeout still apply.

## Compass bearings and facing query

`get_facing_direction()` now returns the tank body's authoritative compass heading in `.world_direction` (0 north, 90 east, 180 south, 270 west). Scanner `direction` has been renamed to `relative_direction`; each detection and nearest result now also includes `world_direction`. You can pass a hit's world_direction directly to `turn_right(to=...)` or `turret_right(to=...)`, without knowing your chassis heading. Update existing programs that read scan.direction. See [BW_LANGUAGE.md](docs/BW_LANGUAGE.md) for the full contract.

## Scanner positions and while loops (2026-11-09)

`Scanner(position=0..7)` selects a physical sensor by index: 0 = 0°, 1 = 45°, …, 4 = 180°, 7 = 315°. It is an alias for the existing degree argument, with the same cost, hardware validation, cooldown and result; the returned `sensor` remains degrees. Do not supply both angle and position.

`while condition:` now supports repeated execution with four-space indentation. It stops on false, null, 0, an empty string, an empty list or an empty dictionary. The condition is reevaluated each iteration and costs one tick plus expression costs. Existing CPU budgets, Stop, lifecycle cleanup and execution limits apply. See the in-game **While loops** handbook topic and [runtime guide](docs/BW_RUNTIME.md). Earlier historical “no loops” notes below are superseded; if/logical operators retain their strict boolean contracts.

## Concurrent BW runtime (2026-11-08)

The BW editor now supports deterministic chassis threads, shared variables/waits, CPU tick budgets, bus allocations, independent device queues and dictionary command results. Scanner arrays are replaced by immutable dictionaries with acquisition timestamps and visible world hit points. Each scan now includes a nearest-first `detections` list and `count` for all visible tanks/walls in its cone. Radar distance defaults to 150 studs at 100% effectiveness, independently of current bus allocation; hardware range fields are ready for future equipment configuration. Movement/turret/fire calls submit work without blocking; inspect `command_status()` for completion.

Open **BW Editor → BW Handbook** for a selectable, read-only reference popup. Its topic tabs explain CPU cycles/ticks, chassis buses and reservations, device busy/queue timing, every command's inputs/returns/base tick cost, scanner result fields, shared-state waits, and practical programs. Costs and tuning values come from the current runtime configuration. Reading it does not pause execution.

Open **BW Editor → Hardware / threads** to inspect or edit the selected tank's chassis, device buses and allocations while its program is stopped. Boomer defaults to Bunny (1 core/bus); Rattler defaults to Octa (8 cores/buses). Their device allocations follow the existing performance curve; Boomer shares its one bus, while Rattler spreads devices across all eight. The existing tank simulation, recoil, weapons and combat remain in place.

See [runtime guide and executable examples](docs/BW_RUNTIME.md) and the [verified implementation checklist](docs/BW_RUNTIME_IMPLEMENTATION_CHECKLIST.md), which supersede older BW contracts below. Native Studio validation remains necessary; nothing was committed or pushed automatically.

Two persistent tanks per player in a local combat test arena. Current component test loadouts are **Bullet Boomer**, the orange tracked body carrying the Gatling, and **Rattler**, the green four-wheeled body carrying the cannon. The weapons were intentionally swapped to verify that recoil/rattling and firing effects follow the gun; older development notes below describe the original loadouts. Built from Roblox Parts with shared server-authoritative combat; no external packages are required. BW v0.2 provides an in-game editor and bounded server-authoritative programs with variables, expressions and branching.

For detailed implementation notes, known limitations, and future-session context, read [the Codex handoff](CODEX_HANDOFF.md).


## BW v0.2 decisions

Programs can store observations, calculate values and choose actions. This runs through the same authoritative movement/weapon runtime as v0.1:

```python
result = Scanner(45)

if result[0] == "tank" and result[4] == "enemy":
    distance = result[1]
    print(result[3])
    if distance < 30:
        fire(2)
    elif distance < 75:
        fire(1)
    else:
        forward(10)
elif result[0] == "wall":
    turn_right(90)
else:
    forward(20)
```

Variables are dynamically typed and scoped to one program. Numbers, single/double-quoted strings, lowercase `true`/`false`, `null` and immutable arrays are supported. Arrays (including scanner results) use **zero-based indexing**. Reassignment works, for example `shots = shots + 1`. Undefined variables, invalid indexes/types and division by zero stop execution with a source line. Program variables never appear in public tank snapshots; new runs/reset do not inherit them.

Expressions support parentheses, unary `+`/`-`, `*`/`/`, `+`/`-`, `==`/`!=`/`<`/`<=`/`>`/`>=`, `not`, `and`, then `or` in that precedence order. `not a == b` means `not (a == b)`. Conditions and logical operands must be booleans; no truthiness or implicit numeric/string conversion is applied. Ordering accepts two numbers or two strings. Equality preserves types and compares arrays by contents. Use `and` between comparisons instead of chained comparisons. `and`/`or` short-circuit, so skipped operands/bodies never read variables or scan.

Use **exactly four spaces per indentation level**, colons on block headers, and one statement/expression per line. Blank lines and quote-aware `#` comments are allowed. The editor expands leading tab characters to four-space stops and maintains indentation after Enter, adding a level after a colon. Raw tab-indented programs submitted outside the IDE are rejected. Dedent with spaces for `elif`, `else`, `case` and `default`. Nested `if`/`elif`/`else` and switches are supported:

```python
result = Scanner(90)
switch result[0]:
    case "tank":
        print("Tank detected")
    case "wall":
        print("Wall detected")
    case null:
        print("Nothing detected")
    default:
        print("Unknown object")
```

A switch evaluates its expression once, runs the first matching case and never falls through. Default is a fallback. Labels must be constant scalar expressions (such as `case 1 + 1:`); determinable duplicates are validation errors. All source, including skipped branches, is syntax/argument validated before any tank action; validation never invokes Scanner.

Existing commands accept evaluated expressions, including `forward(distance)`, `fire(duration)`, `Scanner(direction)` and `turn_left(to=angle)`. Each asynchronous command resolves its arguments once on entry and retains its physical target until completion; variables/branches do not replace tank physics. Movement/weapon calls cannot be used as values. Scanner is the sole value-returning function; `print(value)` is a standalone output statement. Printed strings are readable text; arrays retain quoted strings and explicit nulls.

The IDE keeps scanner diagnostics and explicit prints in one chronological, private, scrollable history, with source lines/timestamps and completion/error status below. Scanner diagnostics have `Scanner(angle) ->` labels and print records have separate labels, so explicit `print(result)` is recognizable. Run still closes the editor; reopen it to inspect output. Stop preserves history and clears execution variables/inputs. Per-tank histories and independent programs remain supported.

The interpreter accounts for reads/writes, arithmetic/comparisons/logical operations, branches and calls through configurable informational cycle hooks. The existing scanner cost remains 5; no CPU-budget enforcement or artificial cycle delays were added. Individual sensor cooldowns are unchanged. A scan operational failure inside an expression fails the statement safely rather than inventing a value; standalone scan/action failures retain `best_effort`. Expression/type/undefined-variable errors are always terminal.

Safety limits: 16 KiB source, 400 lines, 128 source statements, 512 forward-only compiled instructions, 12 nested block levels, 32 expression levels, 512 tokens per line, 64 items per array, 128 variables, 128 completed scanner observations and 256 output records per program. String literals and displayed records are capped at 2,048 bytes; long formatted output is visibly truncated, without altering stored values. Overall 180-second timeout, per-action/stuck limits, immobilization grace, input cleanup and all movement/weapon argument limits remain. Stop, death, reset and disconnect cancel safely. No loops, custom functions, automatic tracking/targeting or arbitrary Luau exist.

Studio checks remain: native keyboard/paste/Enter/caret indentation, touch/gamepad editor focus, current-line/status visibility while actions are pending, mixed output scrolling, private two-client outputs, Stop/reset/death mid-branch, scanner occlusion/cooldowns and both vehicles' physical behavior.

## Directional scanner

Both tanks support the case-sensitive **`Scanner(angle)`** BW command. In BW it takes one explicit observation; it never turns on passive radar for a program. For example:

```python
Scanner(45)
forward(5)
Scanner(90)
```

**Manual driver assistance:** the selected living tank runs all eight sensors independently. Each polls every 0.4 simulated seconds and cycles its center/left/right 15° cones, covering the full circle in about 1.2 seconds. Recent warnings are retained for up to 3 seconds across the eight indicators, so a neighboring empty cone does not immediately erase an enemy reading. Automatic scans stop for unselected, destroyed or BW-controlled tanks. They use the same authoritative scanner and shared query limits, but never create BW values, consume BW cycles or fill the IDE log. A new BW Run clears the driver-only readings and immediately hands control to explicit Scanner instructions.

The indicators now have **1.3-stud lenses**, expanding to **1.6 studs** with a bright Neon reaction. Short arms/posts place them farther around and above the hull, outside the turret silhouette. Multiple directions can show recent warnings together during a manual sweep. Stale readings still expire if updates stop.

Reopen the IDE after Run to see **all scan results from that run**, in chronological order with source lines and simulation timestamps. The output pane scrolls vertically and horizontally, follows new results while you are at the bottom, and lets you scroll back without interruption. Stop preserves the log; a new Run or battle reset clears it. Each tank keeps its own history:

```text
["tank", 58, 39.6, "player3.Rattler#tank-17", "enemy"]
["wall", 22, 87.4, null, null]
[null, null, null, null, null]
```

These are illustrative readings. The five logical fields (indexes 0–4) are type, surface distance, actual surface bearing, unique tank identifier, and affiliation. **Scanner bearings are chassis-relative**, clockwise: forward 0°, right 90°, backward 180°, left 270°. This is separate from BW's world-compass `to=` turns. Finite decimal/scientific angle literals are normalized modulo 360, including negatives. `best_effort` works as on other commands.

The scanner origin is the authoritative collision-body center: tank position + **2.5 world-Y studs**, independent of turret aim, cosmetic rocking and camera. Its initial cone is **15° horizontally**, ±7.5°, and range is **0–150 studs** measured in 3D to a visible surface. Vertical LOS rays can reach the actual body of a ground tank while the scanner is airborne. Oriented collision bounds are clipped against the cone, including partially intersecting bodies whose centers lie outside it. Server raycasts against authoritative arena geometry confirm the first actual surface, so solid walls, rocks/logs/trees, targets and nearer tanks compete in the same nearest-hit search. Ground floor, cosmetic components, smoke, projectiles and the scanner's own body are excluded. Current wrecks are not projectile cover (`CanQuery=false`), so they are excluded too.

All active tanks are enemies in the current local-pair PoC, including the other tank owned by the same player. Detected tanks return **`player_name.tank_name#stable_tank_id`**, such as `player3.Rattler#tank-17`. The suffix is unique within the game and stays stable across control switches and battle resets, distinguishing multiple same-type tanks owned by one player. Unowned tanks use `AI.tank_name#stable_tank_id`. The current tank name defaults to Boomer/Rattler; future instance names can override it without changing the ID. An explicit matching non-nil `teamId` on tank records is supported for future friendly relationships; this adds no team system.

Every successful call retains an immutable structured value and observation (timestamp plus the scanner's own origin/yaw) in the server BW runtime. The five-element array uses a frozen null sentinel internally so empty/trailing fields survive Luau array storage; `BWValue.get(value, index)` uses logical zero-based indexing. It is not just an output string. Variables, zero-based indexing and conditional decisions are supported by BW v0.2; loops, automatic tracking, velocity estimates and predictive aiming are not built in. The timestamp is taken before movement at a completed fixed simulation step, with all tanks' hitboxes synchronized; it is not the IDE display time.

Exact output goes only to the requesting player's IDE through `BWOutput`. Other clients get a short sensor reaction containing the requested direction, hit category/affiliation and **coarse** proximity (near/mid/far), without an identity, exact range, target position or velocity. Eight small decorative lenses react: enemy amber-to-red and increasingly shaky at close range, friendly cyan, wall neutral grey, empty blue pulse. BW reactions fade after 1.2 seconds; manual sweep readings expire after at most 3 seconds. Both are based on completed scans, not client-side knowledge of nearby tanks. Decorations cannot collide, intercept bullets or affect scans. Existing prototype-wide tank snapshots for rendering remain unchanged; this feature does not add fog-of-war replication.

`ScannerConfig` centralizes cone/range, precision, query and visual limits. Each physical sensor has its own 0.1-second cooldown; different sensors can scan at the same timestamp. Nearby requested angles use the same nearest 45° sensor channel, so small angle changes cannot bypass its cooldown. A shared 64-per-second / 16-burst server work budget bounds total query load and at most 192 rays per scan. Overfull scenes or too-fast requests return a line-numbered runtime failure, not a fabricated empty observation; default best-effort warns and continues, while `best_effort=false` stops. Repeated calls through the same sensor need its cooldown to expire; scanning another direction through a different sensor does not. There are no artificial CPU delays. Each invocation accounts for configurable `ScannerCost=5` informational cycles via a future accounting hook; no CPU-budget enforcement exists.

Coverage uses bounded face-derived probes with real physical ray confirmation, rather than exhaustive pixel visibility. Box surfaces use clipped closest-point geometry with a 0.002-stud pruning tolerance; curved/complex cover can have sub-probe slivers that require future refinement. Returned hit measurements retain full precision with no measurement noise. Studio must verify native spatial-query behavior at cone boundaries, rotated/curved cover and airborne LOS, private output with two clients, sensor readability/decay, cancellation/reset and throughput under concurrent programs.

## Progressive weapon damage

Cannon hits create smoke; Gatling rounds leave bullet scars and loosen armor. At **50, 25 and 10 HP**, surviving tanks enter progressively stronger injury bands. Each weapon's share of actual HP damage scales only its own injury: 30 cannon + 40 Gatling damage at 30 HP gives smoke strength 30/70 and rattle strength 40/70, rather than maximum effects from both. Overkill is excluded. Weapon damage, fire rates, acceleration and recoil tuning are unchanged.

For a single-weapon injury, the initial episode durations are:

| Remaining HP | Dense smoke | Immobilization |
| --- | --- | --- |
| 50–26 | 1 second | 0.3 seconds |
| 25–11 | 1.5 seconds | 0.6 seconds |
| 10–1 | 2 seconds | 1 second |

Mixed injuries multiply those durations by the contributing weapon's damage share. Smoke uses soft textured particles emitted throughout the full turret volume, covering its base, sides and roof. A continuous engine plume rises and trails behind the moving tank, with occasional dense whole-turret puffs that are 20% larger. The clouds expand, drift upward, rotate and fade; it obscures the local aim view while leaving UI, movement, turret rotation and weapons available. Other clients see the same active smoke status. BW has no visual sensors and gets no artificial blindness penalty. Intermittent wisps become darker/denser as cannon injury grows.

Gatling injuries add bounded bullet-hole/scar decals made from thin Parts, loose panel shakes, wheel/tread wobble and irregular comic clattering. During **RATTLED** episodes, the server suppresses throttle and chassis steering through the normal simulation input path. Aim/fire and existing coasting, airborne momentum and weapon recoil remain available. Inputs resume automatically. Hits never refresh an active episode; immobilization has at least 3 seconds of recovery, smoke at least 3.5 seconds. Thresholds, durations/recovery, presentation budgets and BW grace are centralized in `src/shared/DamageEffectsConfig.luau`.

BW retains a blocked move/turn instruction and target while temporarily immobilized. Its instruction/stuck clocks receive up to **8 total seconds** of grace per movement/chassis-turn instruction; real displacement/rotation still counts. Turret/fire commands continue normally. Genuine obstruction still follows `best_effort`, and the 180-second overall safety limit remains active.

The **fatal projectile's weapon** selects the finish. Cannon: giant explosion, flying turret/gun, scattered wheels and track belts. Gatling: violent final rattle, a perforated turret falling off, wheels/tracks collapsing, the hull dropping onto its belly, and one final metallic clink. Both leave grey wrecks with existing scars attached. Perforations are visual; they do not change hitboxes. Reset Battle clears damage attribution, handicaps, schedules, smoke, audio, scars and broken assemblies along with the existing physics/weapons reset.

Studio still needs to verify smoke actually makes aiming harder at the normal camera distance without covering UI; episode fairness; both vehicles' damage/fatal animations; live/native collision and replicated visibility with two clients; audio quality; and repeated resets during smoke, immobilization and collapse. Automated checks use mocked engine/GUI services and do not establish play balance.

## Basic tank commands (v0.1 compatible)

Open **BW Editor** below the tank selector/debug readout. The editor contains the default demonstration program. Choose Boomer or Rattler, press **Run**; the editor closes and releases text focus so you can play. Reopen it to watch the current line/output. Each tank keeps its own editor source and server execution state. Switching tanks also closes the editor and releases text focus. Switch to the other tank to drive it manually or start its independent program; switching leaves the first program running. **Stop** releases BW control; press movement/fire controls again to resume manually. Editing text also suppresses driving keys through the normal input-focus handling.

Every command accepts optional `best_effort=true` (the default). For example, `forward(10, best_effort=false)` stops the program if blocked, while `fire(best_effort=true)` skips an activation that cannot complete. Absolute turns support `turn_right(to=90, best_effort=false)`. `best_effort` also accepts boolean expressions/variables; boolean literals are lowercase `true` and `false`.

BW supports `forward(studs)`, `back(studs)`, `turn_left(degrees)`, `turn_right(degrees)`, `turret_left(degrees)`, `turret_right(degrees)`, directional `to=heading` turns, `fire()` and `fire(seconds)`. Use one command per line; blank lines and `#` comments are allowed. Compass headings are world-relative: North 0°, East 90°, South 180°, West 270°. Left/right absolute turns honor the requested route, including a longer rotation. Rattler drives through chassis turns; Boomer pivots.

The server parses and runs the program through existing controls. Distances use actual net horizontal displacement projected along the command's starting direction; sideways drift and vertical hopping do not count. Turn progress accumulates across revolutions. `fire()` waits for one accepted/released shot; `fire(seconds)` holds the real trigger and respects reload/heat. Inputs release between instructions. Already-prepared shots finish before a fire instruction advances; Stop cancels preparation that has not released yet. Already-launched projectiles continue normally.

Limits: 16 KiB source, 400 lines, 128 source statements, 1,000 studs per move, 1,440° per relative turn, absolute arguments within ±36,000° (normalized), and 10 seconds per timed fire. A program is bounded to 180 simulated seconds, each instruction to at most 90 seconds (weapon waits at most 15), and no-progress movement/rotation fails after 3 seconds. By default, instruction failures release inputs, warn with the source line, and continue; `best_effort=false` makes them terminal errors. Syntax errors and global safety/lifecycle stops are never skipped. Death, battle reset, redraw and disconnect stop execution. Switching control preserves running programs. BW changes inputs, never teleports or cancels physics: Rattler can still coast or finish a recoil hop after Stop. There is no pathfinding; blocked instructions report a warning and skip by default, or stop the program with `best_effort=false`.

Statements still execute sequentially; variables and branches are supported. Loops, passive BW sensors, automatic enemy tracking, custom functions, parallel actions and arbitrary Luau remain out of scope. Source is session-local and is not saved to an account.

## Build and open in Roblox Studio

The toolchain is pinned in `rokit.toml` to **Rojo 7.7.1**. With Rokit installed, run `rokit install` from this directory, then:

```bash
rojo --version
rojo build -o battleworks.rbxl
```

Open Roblox Studio, choose **File → Open from File**, and select the generated `battleworks.rbxl` in this project directory. Press **Play (F5)** to spawn your tank. Use Play rather than Run: the tank belongs to a connected player. You can also build XML with `rojo build -o battleworks.rbxlx` and open that file the same way. No plugin is required to open either generated place.

For live source updates, install the matching Rojo Studio plugin, run `rojo serve`, and connect the plugin to `localhost:34872`. Rebuild or reconnect and restart Play after changing scripts. Changes made only in Studio are not automatically written back to source files.

## Controls

- **W / S:** forward / reverse along the chassis direction.
- **A / D:** Boomer rotates left/right, including while stationary. Rattler steers its front wheels while moving; steering reverses naturally when backing up.
- **Mouse:** aim the turret at the cursor's intersection with cannon height; rotation has a server-enforced speed limit.
- **Left click (hold):** The Gatling (currently Boomer) fires rapidly and launches/rattles its carrier, with a 3-second burst limit and mandatory 2-second cooldown. The cannon (currently Rattler) swells for0.20 seconds and has a0.65-second base interval. Existing bus allocation scales firing/preparation speed.
- **Boomer / Rattler buttons:** select control/camera focus below the Input button. Both tanks remain in the arena; switching releases manual controls without resetting either tank or stopping BW.
- **Reset Battle:** restore both tanks to 100 HP, their original inward-facing spawns, fresh weapons/cooldowns and no residual recoil or active projectiles. Stops both programs; editor source is retained.

The fixed 50°/45° map camera uses a strict central 20% dead zone and a wider default view; small readable maps remain fully framed. The HUD shows health and reload state. Overhead health headers sit 10 studs above the chassis, with 65% transparent label/track backgrounds to avoid covering the tank. Five orange practice targets each take four hits and reset five seconds after destruction when their space is clear. Both tanks start at 100 HP and show a health bar plus numeric HP. The cannon deals25 damage per shell; the Gatling deals6 per round, regardless of carrier. Opposing tanks can destroy each other, without self-damage or duplicate impact damage. For a fatal cannon hit, a 24-stud fireball, 40-stud shockwave, fiery bursts, rising smoke and a low boom accompany the complete turret/gun launching off the hull. Boomer’s eight road wheels or Rattler’s four tire assemblies scatter, tumble and settle. All vehicle pieces turn grey and remain as a solid wreck; controls/BW stop and the HUD announces the winner (or a double-KO draw). The breakup is cosmetic and cannot deal damage or block projectiles. Press Reset Battle to try again. The arena walls, targets, and other tanks block movement. Controls clear when the window loses focus or a text field gains focus. Server commands expire after 0.35 seconds without a valid update.

## Android, touch, and input settings

Mobile orientation is **LandscapeSensor** (either landscape direction). The `ScreenGui` uses `CoreUISafeInsets` so controls stay within the Roblox/device safe area. Stick diameter scales with safe-area width and height, capped at 170 pixels. FIRE sits in the center gap with separate space above it for the relay display.

- **LEFT joystick — turret:** right/left changes yaw; up/down changes cannon pitch. This is rate control, not a world-position reticle. Centering holds orientation.
- **RIGHT joystick — drive:** up/down is throttle/reverse; right/left steers the chassis. Steering is independent of forward/reverse.
- **Center FIRE:** hold to repeat fire at the server cooldown. Release/cancel clears local fire immediately; it reaches the server on the next 30 Hz input packet, subject to network latency.
- Each finger belongs to exactly one control. Dragging outside a stick still controls that stick, with circular clamping. Another finger cannot steal it. Each joystick has its own configurable radial dead zone (`turretDeadZone`/`driveDeadZone` passed in `InputController.luau`, default 0.15). Output remaps the remaining travel to full range.
- Release, cancel, mode change, resize/orientation change, focus loss, text entry, and the Roblox menu clear held controls. A fresh press is needed after resuming.

Tap/click the **Input** button at the top right to cycle **Auto → KeyboardMouse → Touch → Gamepad → Auto**. The button is also selectable with gamepad UI navigation. Auto follows `UserInputService.PreferredInput` and listens for changes; it does not choose Touch from `TouchEnabled`. A touchscreen laptop using keyboard/mouse therefore keeps desktop controls. Explicit preferences stay selected when another device is used. Modes can be changed while playing; every transition releases prior intent.

Gamepad mode currently supports **Gamepad1**: left stick drives, right stick controls turret yaw/pitch, right trigger fires. A 0.15 radial dead zone applies. Disconnect clears held axes/fire. No gamepad remapping or additional gamepads are implemented.

Only while Touch mode is selected, the client temporarily disables the default PlayerModule movement controller and hides the default `TouchGui` (thumbstick/jump). It restores their prior enabled states when leaving Touch. Roblox menus, chat, and other CoreGui remain available. PlayerModule is loaded asynchronously; if unavailable, the client warns and still hides default TouchGui. This integration must be verified against the live Roblox PlayerModule in Studio/on-device.

The preference is **session-local** and resets to Auto on rejoin. No device identifier or settings DataStore is used. Roblox does not expose general arbitrary local-file storage to experience scripts; a future account-level setting would not automatically be a separate preference for each device.

Touch mode includes a live relay panel, for example:

```text
INPUT: Touch
THROTTLE:  +0.82
STEERING:  -0.14
TURRET X:  +0.35
TURRET Y:  -0.20
FIRE:      TRUE
```

These are the local normalized command values sampled for the outbound relay, **not server acknowledgments**. The debug display updates each render frame; gameplay input is transmitted at 30 Hz. Server validation clamps all four axes and rejects NaN, infinity, invalid modes/types, and malformed world aim. Cooldown/damage/hit results remain exclusively server-owned.

## Component configuration

See [VEHICLE_COMPONENTS.md](docs/VEHICLE_COMPONENTS.md) for the typed catalog, ID-based vehicle assemblies, resolver, component boundaries and upgrade examples. Steering/pivot capabilities now follow installed mobility; both default tanks support persistent BW steering. Existing model-specific art remains unchanged.

## Architecture

| Module | Responsibility |
| --- | --- |
| `src/shared/InputCommand.luau` | Shared intent contract and server validation. World-position aiming for desktop; normalized turret-rate axes for touch/gamepad. Steer is positive left. |
| `src/shared/TankSimulation.luau` | Instance-free state transitions, movement, turret rotation, cooldown and firing eligibility. Only the server advances gameplay state. |
| `src/shared/TankConfig.luau` | Simulation and combat tuning. |
| `src/server/init.server.luau` | Player ownership, fixed 60 Hz simulation, arena collision, input validation/rate limiting, authoritative raycasts/damage, target resets, local battle lifecycle, 20 Hz state snapshots. |
| `src/client/KeyboardMouseInput.luau` | Existing WASD/mouse adapter, gated by selected mode. |
| `src/client/TouchInput.luau` | Two independent virtual sticks, hold-to-fire, per-InputObject ownership/cancel cleanup, safe-area layout, input relay display. |
| `src/client/GamepadInput.luau` | Gamepad1 analog sticks and right-trigger adapter. |
| `src/client/Analog.luau` | Shared radial dead zone, normalized output and circular clamping. |
| `src/shared/BWLexer.luau`, `BWExpression.luau`, `BWCommands.luau` | Bounded lexical/expression AST, strict evaluation and shared static/runtime command contracts. |
| `src/shared/BWParser.luau`, `BWRuntime.luau`, `BWEditorText.luau` | Indentation AST/forward-only compilation, program-local variables/branch execution and four-space editor assistance. |
| `src/shared/ScannerConfig.luau`, `ScannerGeometry.luau`, `BWValue.luau` | Scanner tuning, clipped collision-bound probes and immutable runtime arrays/observations. |
| `src/server/DirectionalScanner.luau` | Authoritative spatial queries, nearest visible surface, identification and query budgets; invoked only by BW Scanner. |
| `src/client/ScannerVisual.luau` | Nonphysical sensor decorations driven solely by completed scan reactions. |
| `src/server/LocalBattle.luau` | Persistent pair ownership, selection, inward-facing spawn/reset poses, HP/destruction/winner lifecycle. Reuses the existing simulation and weapons. |
| `src/client/TankCombatVisual.luau` | Snapshot-driven overhead HP bar/numbers and a bounded cosmetic destruction burst. |
| `src/client/InputController.luau` | Auto/explicit mode selection, settings button, focus/menu release, temporary default movement suppression. |
| `src/client/TankRenderer.luau` | Anchored cosmetic geometry, state smoothing, scrolling track shoes, scripted chassis wobble, cannon recoil and muzzle flashes. |
| `src/client/init.client.luau` | Input transport at 30 Hz, snapshot reception, renderer lifecycle, camera and HUD. |

All adapters return the same command contract and send intent through the existing input RemoteEvent. A future BW program can generate commands on the server and feed them into the same simulation path. BW execution is not implemented.

The shared command includes `throttle`, `steer`, `fire`, and `aimMode`. `World` uses `aim` (XZ world position) and preserves horizontal desktop aiming. `Rate` uses `turretX` (positive right) and `turretY` (positive up), both in [-1, +1]. Rate release holds the last turret orientation. The server integrates turret yaw/pitch, limits pitch to -12°…+30°, and applies pitch to authoritative shot direction. The renderer consumes the resulting state; adapters contain no movement or weapon simulation. Missing `aimMode` still accepts the original world-aim contract. Neutral/expired commands now hold the turret instead of aiming at a fixed world point.

Clients submit intent only: they cannot choose tank IDs, positions, health, hit results, damage, or cooldowns. The server validates finite values, clamps axes, enforces input rate and timeout, and uses its own turret direction for slow server-authoritative projectile sweeps. Shells launch from the cannon tip after a server obstruction check from turret to muzzle. Client visual parts have collision and ray queries disabled. Server hitboxes are anchored; no physics ownership or constraints are involved. Recoil and wobble affect visuals only.

This prototype supports a flat arena, simple conservative tank/target collision, and slow straight-flight projectile combat. It does not implement terrain traversal, projectile ballistics, client movement prediction, or BW execution.

## Verification

The current checks compile 59 Luau sources and cover simultaneous tanks, independent manual/BW control, persistent selection, damage/death/self-damage protection, reset/projectile cleanup, per-tank editor source and health/destruction visuals, attributed progressive injuries, bounded status scheduling and BW immobilization grace. The production server is tested with mocked engine sweeps; native Roblox spatial queries and presentation still require Studio.

`rojo build -o battleworks.rbxl` and `rojo build -o battleworks.rbxlx` succeed with Rojo 7.7.1. A build validates the Rojo data model; it does not execute Luau. The development check compiles every source file using Luau Web and executes deterministic input/contract/simulation tests with mock Roblox services:

```bash
npm install --prefix /tmp/battleworks-luau-check luau-web@1.4.0 --no-audit --no-fund
node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js
```

The npm package is a development-only tool outside the place. Tests cover axis clamping and malicious values, legacy desktop aim, turret pitch limits and shot direction, cooldown, dead zones, three-finger input, cancellation, recentering, mode/focus/menu transitions, default-control restoration, gamepad disconnect and desktop input regression. Mock services do not verify actual GUI layout, Roblox event ordering, network timing, or hardware behavior. Studio and Android play testing are still required.

In Studio:

1. Play solo; verify both tracks, chassis, turret and cannon appear, and the HUD is visible.
2. Drive and reverse, turn while stationary, and aim independently of the chassis. Confirm the tank stops at walls and targets.
3. Hold fire on an orange target: four hits destroy it; it returns after at least five seconds when unoccupied. Confirm reload pacing and visual recoil/wobble.
4. Release keys, focus a text field, and switch windows; confirm driving/firing stops.
5. Switch control while driving/firing and while BW runs. Both models must remain in place with their own HP, heat, cooldown and program progress. Run BW on both; Stop on one must leave the other running.
6. Shoot the opposing tank: verify 25/6 damage, readable HP bars, one destruction burst, a visible disabled wreck and winner status. Reset during flight/reload/BW and confirm both spawns, HP, weapons and inputs reset; practice targets remain.
7. Use Studio's **Server & Clients** test with two players. Each player gets a separate local pair and can only command/damage their own pair. Confirm replication, ownership and departure cleanup of both tanks. This is not multiplayer matchmaking.
8. Watch client and server Output for runtime errors throughout these checks.

Roblox references: [remote events](https://create.roblox.com/docs/scripting/events/remote), [server boundary validation](https://create.roblox.com/docs/scripting/security/client-server-boundary), and [raycasting](https://create.roblox.com/docs/workspace/raycasting).

## Android testing checklist (requires Roblox runtime)

1. Build/open the place as above. In Studio's device emulator, select a small Android phone in landscape; also check a notched phone and tablet. Start **Play**, confirm Auto resolves to Touch (or select Touch manually if the emulator reports keyboard input). Confirm both sticks, FIRE, debug panel, settings, and Roblox top bar fit without overlap; no default movement/jump controls should be visible.
2. Drag the left joystick right/up and then left/down. Verify yaw/pitch direction, pitch limits, and that release holds orientation. With the right stick, test throttle, reverse, stationary steering, dead zone, diagonal full travel and dragging far outside its circle. Confirm the released stick recenters and its relay axes return to zero.
3. On a real Android device, hold **three fingers simultaneously**: turret, drive and FIRE. Move each independently; release/repress one while holding the other two. The other controls must stay active. Four level shots should destroy a target; elevated/depressed shots should follow the cannon. A single mouse pointer in Studio cannot prove multi-touch.
4. Slide the FIRE finger off the button and release outside it; firing must stop. Switch apps/lock the screen while holding controls, open/close the Roblox menu, rotate to the other landscape orientation, and resume. Verify no stuck throttle/steering/turret/FIRE; fresh touches must work. Cancellation event delivery needs actual device testing.
5. While holding controls, cycle all four preferences. Check release, correct resolved mode, Touch-only UI, and default movement-control restoration. Test Auto with Bluetooth keyboard/mouse and controller; verify `PreferredInput` changes select the corresponding adapter. On a touchscreen laptop, mouse/keyboard use must not show the touch overlay just because touch hardware exists.
6. Re-test desktop WASD, mouse aiming, held left click, chat focus, and focus loss. In Gamepad mode test both sticks/trigger together, disconnect/reconnect, menu navigation and explicit mode selection.
7. Use a two-client Studio server to check replicated turret pitch, fire pacing, damage/reset and ownership. Watch client/server Output for errors. Add network latency if available: the relay is local intent and the server remains authoritative, so visual/gameplay response may lag.
8. Publish privately through Studio for testing in the Roblox Android app on physical hardware. Rejoin and confirm preference resets to Auto. Publication is not performed by this repository's build/check commands.

API references: [PreferredInput and cross-platform input](https://create.roblox.com/docs/input), [mobile orientation](https://create.roblox.com/docs/input/mobile), [safe-area UI containers](https://create.roblox.com/docs/ui/in-experience-containers).

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

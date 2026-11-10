
Undo follow-up (E3.2): keyboard undo/redo retains an authoritative history snapshot beyond key release and settling frames. Late native history callbacks restore that snapshot on the next Heartbeat and cannot become new edits. The next non-modifier editing/navigation input or explicit lifecycle release relinquishes ownership. Native Studio Ctrl+Z/Ctrl+Y retesting remains required.
# BW concurrent runtime

For the standalone programmer handbook, see [BW_LANGUAGE.md](BW_LANGUAGE.md).

BW programs now submit work to independent physical devices. This intentionally changes the old blocking movement-command contract. Existing tank models, recoil, terrain/collision resolution, damage, weapon heat and projectiles still use the existing fixed server simulation. No task-based gameplay scheduling or new movement engine is introduced.

## Compile-time CONST lowering

`BWParser` resolves `CONST name = expression` in textual source order using a per-compilation table. Scope is program-wide, matching the existing shared variable namespace; declarations in branches/threads are unconditional at compile time. Initializers are recursively checked to allow only scalar literals, previous constants and existing operators/groups. The checker rejects runtime identifiers, all calls (no pure built-ins yet), collections and indexing even in unreachable operands. `BWExpression.constant` performs evaluation with existing type/error semantics. Duplicate names, assignment-name conflicts and writes to visible constants fail with source-line diagnostics.

Every reference is replaced with an ordinary literal AST node. The source AST retains a `const` declaration for diagnostics, but the instruction compiler emits nothing for it. No constants enter `BWExecution.variables` or synchronization versions. Both production reservation (`expressionCost`) and actual charging evaluate the same lowered tree: constants need no runtime cost-model exception. Ordinary variables and expressions outside initializers keep normal costs. The IDE's existing Run parser diagnostics handle CONST; the current plain TextBox editor has no syntax-highlighting or standalone cost-profiler infrastructure to extend. The in-game language handbook documents the syntax and zero cost.

See [constant examples and rules](BW_LANGUAGE.md#compile-time-constants). `tests/BWConstants.spec.luau` checks literal-equivalent instruction tables, per-step scheduling/physics/ticks, scalars, compile diagnostics, concurrency and ordinary variable costs. Constant declarations still count toward existing source statement/size limits; they consume no runtime operations.

## Clock and execution

The server's existing 60 Hz fixed simulation drives BW. CPU cycles occur at 10 Hz, configurable in `src/shared/BWChassis.luau`. Each bus runs one instruction stream, independently budgeted:

| Chassis | Buses/threads | Ticks/cycle/thread | Pending queue/device |
| --- | ---: | ---: | ---: |
| Bunny | 1 | 10 | 1 |
| Dual | 2 | 15 | 2 |
| Quad | 4 | 20 | 4 |
| Octa | 8 | 30 | 8 |
| Hexadeca | 16 | 40 | 16 |

The IDE opens with a one-thread demonstration of independent movement, turret, scan, clock/status inspection and firing. The original eight-command demo is retained as `LegacyDefaultSource` for physical-executor regression tests.

Tank defaults are **Boomer: Bunny (1 core/bus, 10 ticks/cycle, queue 1)** and **Rattler: Octa (8 cores/buses, 30 ticks/cycle/thread, queue 8)**. Boomer reserves 40% drivetrain, 20% turret, 20% weapon and 2.5% for each of eight sensors on its single bus. Under the existing curve, drive performance is 64% and turret/weapon performance is 36%. Rattler has full drivetrain/turret/weapon buses; its eight scanners share buses 4–8 with each bus totaling 100%. Radar range remains 150 studs at full distance effectiveness. These are defaults; the development editor can override hardware. Configuration persists through battle reset; program state does not. Generic `BWChassis.default()` still supplies a full-performance Hexadeca fixture for explicit development/tests.

At each CPU cycle, threads execute in ascending numeric order until their available instruction credit is exhausted, they wait, finish, or hit the hard operation cap. Later conflicting writes in this order win. No Roblox task ordering is involved. Finished streams do not terminate other streams or devices. The program completes only when every stream finishes and all accepted device work drains. Stop releases ownership immediately and cancels pending/prepared operations; existing physical momentum and already released projectiles remain real.

Unused credit is normally capped at two cycles. A larger next instruction may accumulate its bounded required credit (absolute maximum 1,024). Each source instruction conservatively reserves its worst-case expression cost before starting. Actual charges follow reached operations, so short-circuited operations cost nothing. Ordinary assignments and read/modify/write expressions cannot be split by CPU exhaustion. Physical observations and explicit waits suspend evaluation without repeating earlier calls. An assignment containing a physical wait commits only when its expression finishes; other threads can change shared variables during that wait.

A hard cap of 512 executed source operations/thread/cycle bounds even zero-cost programs. Existing source/expression/block bounds and 180 simulated seconds/program remain. Waiting for a variable forever is therefore bounded. Physical executors retain distance/angular tolerances, stuck detection, timeouts and immobilization grace. CPU time, device operation time and queue wait time are separate.

`get_clock()` returns `{status: "success", reason: null, time: ...}` using **arena simulation seconds**, not render or wall time. As required by the universal result contract, read `.time` for the numeric clock. Scanner `.timestamp` is acquisition time, which can precede the thread's result-consumption time. Waits resume on the first CPU cycle at/after the requested time; device operation advances every fixed simulation tick.

## Threads and synchronization

```python
with thread(1):
    ready = true
with thread(2):
    wait_for(ready)
    print("ready")
```

Four spaces per indentation level. Thread blocks must be top-level, have unique integer IDs within chassis capacity, and start together. Legacy top-level statements append to thread 1 in source order. User-defined functions use independent call stacks within these threads (see Function compilation and execution below). No locks or events are added. Nested while loops are supported and scheduled under the same CPU/safety budgets.

All streams share one variable environment for this tank/run. Other tanks/programs have separate environments. Stop, error, death, replacement and reset clear variables and versions. Completed values remain private until Stop/replacement/reset.

- `wait_for(name)` retains the **variable reference**. It waits for an assigned value other than `false` or `null`; zero/empty string/dictionaries are truthy. An already-ready variable returns immediately, avoiding lost notifications. Returns `{status, reason, value, version}`. It is a readiness wait, not a request to wait for the next assignment.
- `variable_has_changed(name)` returns `{status, reason, changed, version}`. Each thread keeps its own last-observed version, initially zero. Every root assignment increments that variable's version, including equal-value assignments. This call updates that thread's observed version. `wait_for` also observes the version when it returns. Missing variables have version zero.
- Mutating `data.key` increments the named root's version. Aliases share dictionary contents, but version counters belong to the root name written, not every possible alias. No deep automatic change notifications are implied.
- `wait_for_clock(time)` suspends only its caller until the absolute simulation time and returns a standard success result.

## Own facing and scan bearings

`get_facing_direction()` returns `{status: "success", reason: null, world_direction: degrees}` immediately from the authoritative chassis orientation. It costs 0.1 ticks, plus ordinary expression/storage costs. This is the body heading, independent of turret aim and camera. It reads actual orientation, not the target of a queued turn.

Scanner detections and nearest convenience fields now use `relative_direction` and `world_direction`. Both describe the SAME visible hit point at acquisition. Use `world_direction` directly with `turn_right(to=...)`, `turn_left(to=...)` or turret absolute-heading commands. Snapshot bearings do not update as either tank later moves. A later facing query may differ from the scanner's acquisition orientation.

## Devices and allocation

Installed device names are `drivetrain`, `turret`, `weapon`, and `sensor0`, `sensor45`, …, `sensor315`. A device belongs to one bus; any thread can command it, regardless of bus. Bus allocations must sum to at most 100%. Idle reservations are not redistributed.

`performance = 1 - (1 - allocation/100)^2`

50% allocation gives 75% performance. Allocation affects drivetrain propulsion target speed (and tracked pivot request rate), turret rotation rate, scanner acquisition time, and weapon preparation/firing interval. Drivetrain acceleration/braking ratings and steering geometry remain component-defined; contact traction and world linear/yaw momentum resolve actual motion. Airborne recoil/landing policy is retained. Projectile speed/damage and heat/overheat rules are unchanged. Weapon timing is divided by performance; zero allocation disables operation without dividing by zero. Manual controls respect the same configured hardware. Manual scanner's internal three-angle sweep remains driver-only; BW addresses physical mounting angles only.

Open **BW Editor → Hardware / threads**. Left side is editable:

```text
Dual
drivetrain 1 40
turret 2 20
weapon 2 20
sensor0 1 20
```

First line is chassis name; other lines are `device bus allocationPercent`. Omitted devices are uninstalled. Apply while the program is stopped. Client feedback validates structure and bus totals; the server independently validates ownership, capacity, sums and finite bounds. Invalid configurations leave existing hardware intact. Acquisition duration is also supported by the server data model (`acquisition`, 0–5 seconds/device); the compact editor currently uses the default 0.05 seconds. Scanner hardware also supports `range` and `distancePercent`, defaulting to 150 studs and 100%. Detection range currently stays at full effectiveness independently of bus allocation; future pre-battle equipment configuration can tune these fields.

## Device queues and results

Movement and chassis turns share the drivetrain. Turret turns use the turret; fire uses weapon. Each physical sensor has its own queue, acquisition operation and existing cooldown. Devices operate concurrently; active movement does not continuously spend CPU ticks.

```python
move = forward(100)      # accepted, immediately starts drive
turn = turn_right(90)    # queues behind move
observation = Scanner(0) # waits for this observation only; drive continues
```

Each device has one active command plus the chassis-defined number of pending commands. Finite submissions never wait for space or overwrite accepted work. Explicit continuous-drive replacement and stop cancellation follow the rules below. `deviceQueueFull` is a nonfatal result. Queue capacity is attached to the device, not the submitting thread. Rejections do not consume command IDs or mutate accepted work.

Every callable returns a dictionary with `status` (`"success"` or `"fail"`) and `reason` (always null on success, stable code on failure). Movement/turret/fire success means **accepted**, not physically completed:

```python
accepted = forward(10)
print(accepted.status)
print(accepted.commandId)
state = command_status(accepted.commandId)
print(state.state)
```

Command IDs are scoped to this program run. `command_status(id)` returns status/reason plus `commandId`, `device`, `state`, `completionReason`. States: `accepted` → `running` → `completed`/`failed`/`cancelled`, or `queued` → `running`. Diagnostics retain a rolling history of 512 terminal command records plus all active/queued work; command IDs keep increasing. Expired terminal IDs return invalidArgument, while new work continues. No public blocking `wait_for_command` is added in this phase; use time/readiness coordination and status inspection. A while loop can poll state, ideally using a short wait_for_clock delay between queries.

`clear_queue("drivetrain")` cancels pending work, preserving the active command. `abort_command("drivetrain")` cancels active work; accepted pending work starts at the next fixed simulation tick. New submissions cannot jump ahead of older queued work. Sensor cancellation wakes its waiting caller with a failure dictionary. Weapon cancellation clears an unreleased preparation. Destruction/reset/respawn clear all queues and waiters.

Stable reasons currently used: `deviceQueueFull`, `deviceUnavailable` (including uninstalled sensor), `deviceDisabled`, `invalidSensor`, `invalidArgument`, `commandCancelled`, `tankDestroyed`, `sensorCooldown`, `scannerBusy`, `stuck`, `commandTimedOut`, `executionFailed`. `deviceDamaged` is reserved for future per-device damage. Runtime operational failures continue execution even with legacy `best_effort=false`; existing syntax is accepted, but asynchronous lifecycle failure does not retroactively throw in its submitting thread. Syntax/type/undefined-variable failures remain fatal. Genuine service/invariant errors stop safely and retain an explicit internal-error diagnostic.

## Dictionaries and scanner snapshots

Dictionaries support literals, dot access, string-key access and mutation:

```python
data = {"shots": 0}
data.shots = data.shots + 1
print(data["shots"])
```

Keys are strings; missing keys yield null. Scanner/result dictionaries are immutable; attempting to mutate one is a line-numbered runtime error. Nested hit points are immutable too. Existing arrays remain zero-based values, but **Scanner no longer returns arrays**. Dictionary equality is identity equality in this version; compare individual fields. Case labels remain constant scalars.

Valid mounted angles are exactly 0, 45, 90, 135, 180, 225, 270, 315 after normalization modulo 360. Alternatively use Scanner(position=index), where index is an integer 0..7 and angle=index*45. For example Scanner(position=4) is Scanner(180). Choose either positional angle or named position, never both. Position indices do not wrap; expressions are allowed and validated at runtime. The returned sensor field stays in degrees. A literal `Scanner(100)` is rejected before any tank action, with nearby valid angles suggested. Computed invalid positions return `invalidSensor`; valid uninstalled hardware returns `deviceUnavailable`.

A scanner reserves its queue slot and acquires after hardware duration / performance. The existing server spatial query/raycast implementation samples the actual current scene at acquisition. All sensors retain independent cooldowns and a separate bounded shared server query safety budget. Ready-sensor acquisition order rotates deterministically each cooldown interval so the safety budget cannot repeatedly favor the same lexical sensor names. Queued acquisitions honor that physical sensor’s cooldown before querying. Queue overflow or a global geometry budget yields a nonfatal failure; no hidden result is invented.

Each successful scan includes an immutable `detections` array containing **all visible tanks and walls found within the scan cone/range**, sorted nearest first. BW arrays are zero-indexed. `count` is its length and `range` is the effective hardware range. Each detection has `type`, `distance`, `relative_direction`, `world_direction`, `player`, `relation` and an immutable world `point`. Occluded objects are excluded, duplicate hits are consolidated, and all entries belong to the same acquisition timestamp. For compatibility, the top-level type/distance/relative_direction/world_direction/player/relation/point fields still describe the nearest detection. Empty scans have `count=0` and an empty detections list.

Automatic IDE scanner output lists every detection on its own indexed line rather than truncating the complete snapshot through the generic value formatter. The sensor decoration prioritizes the closest visible enemy over neutral cover in the same cone. Completed BW reactions are stored independently per physical lens (at most eight), so multiple acquisitions between snapshots remain visible together; empty scans pulse too. Private device diagnostics include per-sensor success/failure totals and last count/reason/time. The bounded geometry/raycast safety limits still apply; exceeding them yields `scannerBusy`, never a silently partial list.

```python
scan = Scanner(0)
if scan.status == "success":
    print(scan.count)
    print(scan.range)
    if scan.count > 0:
        print(scan.detections[0].type)
        print(scan.detections[0].distance)
```

Example nearest convenience fields (the full response also contains `detections`, `count` and `range`):

```text
{status: "success", reason: null,
 type: "tank", distance: 58, relative_direction: 39.6, world_direction: 129.6,
 player: "player3.Boomer#stable_id", relation: "enemy",
 sensor: 45, timestamp: 12.345,
 point: {x: 15.2, y: 3.6, z: -42.1}}
```

Empty observations are success with an empty detections array and null nearest type/distance/relative_direction/world_direction/player/relation/point. `sensor` and `timestamp` remain present. Origin is the authoritative tank position + 2.5 studs world Y. Distance is 3D range to the visible surface. relative_direction is the precise clockwise bearing relative to chassis forward at acquisition. world_direction is the compass bearing to the same observed surface, with north=0/east=90/south=180/west=270. The old direction key is removed. Point is that visible surface in world coordinates, not a target center. The existing `player` field retains the unique `owner.tank#id` identity. A wreck is an obstacle only if gameplay still includes it as solid/queryable cover. Cosmetic sensors, smoke and projectiles do not enter the geometry allowlist.

Snapshots contain no target velocity, prediction or hidden position. Future fields can be added without changing this contract.

## Costs

Costs in `BWChassis.Costs` are gameplay ticks, independent of actual Luau execution time:

| Operation | Ticks |
| --- | ---: |
| if decision | 1 |
| while condition test (including final false test) | 1 |
| switch dispatch, any number of cases | 2 |
| forward/back/chassis turn/turret turn | 1 |
| scanner submission | 1 |
| fire submission | 2 |
| get_clock | 0 |
| get_facing_direction | 0.1 |
| variable read | 0.1 |
| assignment/property write | 0.2 |
| arithmetic or comparison | 0.2 |
| logical operation or dictionary/array access | 0.1 |
| print / automatic debug logging | 0 |
| initiate wait/change check | 0.2 |
| clear/abort/status query | 1 |

Expression operand costs are normally additional. Debug printing is free, including pure reads, property/index access, arithmetic and logical expressions used only to display a value. Expressions containing real calls inside print (such as Scanner, movement, status queries or waits) execute and charge normally, including conditional logic/arguments/result access, so printing cannot bypass gameplay costs; assigning the print result still costs an ordinary write. Automatic result/scan/error logs add no ticks. Histories roll instead of imposing lifetime scan/log/command quotas: 128 recent scanner snapshots, 256 IDE output entries, and 512 terminal command records plus active/queued work. At most 64 log events are emitted per tank per CPU cycle, including an explicit rate-limit notice when excessive output is omitted. Total activity and omitted-output counts are available in private diagnostics. Per-cycle CPU safety and the 180-second runtime bound remain. Switch labels have no hidden per-case charges. Short-circuiting skips both side effects and charges. Physical acquisition, cooldowns, queue waits and movement do not charge repeated ticks. The legacy `BWConfig.CycleCosts`/`ScannerConfig.ScannerCost` remain only for the retained physical-executor regression harness; the production scheduler uses the table above.

## Sample programs

### Bunny: single stream and concurrent device operation

Use the Bunny preset; drivetrain, turret and weapon share its bus and keep their reservations while idle.

```python
move = forward(10)
aim = turret_right(45)
clock = get_clock()
wait_for_clock(clock.time + 2)
print(command_status(move.commandId))
fire()
```

### Dual: scanner and targeting coordination through a shared result

Install sensor0. The scan supplies a world compass bearing directly, so no chassis-heading offset is required. The runtime still does not aim automatically. Fire is conditional on the normal turret command having completed after the explicit delay.

```python
with thread(1):
    target = Scanner(0)

with thread(2):
    wait_for(target)
    if target.status == "success" and target.type == "tank":
        if target.relation == "enemy":
            aim = turret_right(to=target.world_direction)
            clock = get_clock()
            wait_for_clock(clock.time + 2)
            state = command_status(aim.commandId)
            if state.status == "success" and state.state == "completed":
                fire()
```

### Shared readiness and version observations

```python
with thread(1):
    clock = get_clock()
    wait_for_clock(clock.time + 0.5)
    ready = true
with thread(2):
    wait_for(ready)
    print(ready)
    print(variable_has_changed(ready)) # already observed by wait_for
```

### Concurrent devices and queue-full handling

On Bunny, one active drivetrain command plus one pending command fills the pipeline. Other devices continue independently.

```python
a = forward(100)
b = turn_right(90)
c = back(5)
if c.status == "fail" and c.reason == "deviceQueueFull":
    print("Drive queue full; other devices still work")
turret_left(45)
fire(1)
```

### Scanner dictionary fields and timestamp comparison

Use full-performance sensors (e.g. a configured Hexadeca development rig). The observation points are visible surfaces, so changing target orientation/visible face can affect this estimate. This is programmer computation, not a built-in tracker.

```python
first = Scanner(0)
clock = get_clock()
wait_for_clock(clock.time + 0.5)
second = Scanner(0)
if first.status == "success" and second.status == "success":
    if first.type == "tank" and second.type == "tank":
        if first.player == second.player:
            dt = second.timestamp - first.timestamp
            if dt > 0:
                vx = (second.point.x - first.point.x) / dt
                vz = (second.point.z - first.point.z) / dt
                print(vx)
                print(vz)
                print(second.relative_direction)
                print(second.world_direction)
```

### Clear queues and abort active operations from another thread

```python
with thread(1):
    forward(100)
    turn_right(90)
    fire(2)
with thread(2):
    clock = get_clock()
    wait_for_clock(clock.time + 0.5)
    print(clear_queue("drivetrain"))
    print(abort_command("drivetrain"))
    print(abort_command("weapon"))
```

## While loops and position-indexed scans

```python
position = 4
remaining = 2
while remaining:
    result = Scanner(position=position)
    print(result)
    remaining = remaining - 1
```

`while condition:` reevaluates its expression before each iteration. Falsey values are false, null, numeric zero, the empty string, an empty array and an empty dictionary. All other supported values are truthy. Undefined variable reads remain errors. This conversion is specific to while; existing if and logical operators still require booleans, and wait_for keeps its documented readiness semantics.

The test costs one tick plus expression costs every time, including the final false test; the backward jump costs zero. Body commands keep their existing semantics: movement submissions do not wait for completion, and device queues can fill. Loops may nest and contain if/switch/scan/wait statements. CPU exhaustion yields to other threads; Stop/reset/death cancel the loop and device work. The existing 180-second timeout and hard per-cycle operation cap remain. Snapshot/log/terminal-command histories are bounded rolling buffers; their lifetime counts do not end valid continuous loops. break, continue, for and while-else are not implemented.

## Integration and remaining validation

`BWExecution` owns CPU streams/shared variables. `BWDevices` owns physical commands/queues and reuses `BWRuntime`/`BWTankAdapter` for physical completion. `BWController` owns lifecycle and hardware validation. Server `BWHardware` accepts configuration intent only; private `BWRuntimeState` sends bounded 5 Hz diagnostics to the owner. Public tank snapshots contain no variables or exact scan results. `BWOutput` history retains thread IDs, lines, simulation timestamps, prints, scans and recoverable submission failures.

The fixed 15-degree cones have gaps between their 45-degree mounting directions. A conditional print for successful nonempty scans will skip both empty cones and scannerBusy failures; inspect individual sensor rows to tell them apart.

The log pane now pages retained output into bounded native TextBoxes (8,192 bytes / 120 lines), with Older/Latest controls. It shows separate server print execution and client print receipt counters; thread diagnostics include loop-test and print counts. These distinguish a blocked scan, conditional skip and output display/delivery.

The hardware panel shows current source line, running/waiting/finished/failed state, wait reason, charged ticks, device allocations, active command IDs, queue contents and recent terminal failures. Configuration and diagnostic UI is deliberately compact text rather than a new visual garage.

Automated evidence and final results are in [BW_RUNTIME_IMPLEMENTATION_CHECKLIST.md](BW_RUNTIME_IMPLEMENTATION_CHECKLIST.md). Roblox Studio remains necessary for native TextBox/tab/caret/scroll ergonomics, mobile controls, real spatial-query/filtering behavior, two-client privacy/latency, and subjective visual/physics continuity under terrain, recoil, smoke and destruction. No future smart scanner, user functions, for loops, CPU enforcement based on wall time, or automatic tracking is implemented.

## Persistent steering and continuous drivetrain ownership

`BWCommands` accepts `forward()`/`back()` and steer_left/right(degrees), steer_center(), stop(). Each submission costs 1 tick in the existing hardware cost registry. No per-frame CPU costs are added. Expressions, CONST substitution and normal validation/reservation continue to use the existing compiler/runtime. All new calls return standard results and command IDs.

`BWDevices` owns one persistent wheel target in radians, converting physical degrees to normalized existing InputCommand.steer only at the input boundary. Requests 0..180 degrees clamp to the installed Drive.MaxSteer (Rattler 0.55 radians, approximately 31.5 degrees). Both default tanks support steering; installed mobility without the capability returns unsupportedDrivetrain. The existing RattlerDrive smoothing, speed allocation, acceleration/coasting, recoil, collision and airborne behavior are untouched. No direct pose/velocity writes are introduced. Steering targets and commands obey drivetrain availability; zero allocation rejects operation, while stop remains accepted for safe release. Existing damage input filtering still has final authority.

Steering commands complete immediately and bypass queue capacity, without changing active navigation. Their result includes steeringDegrees (+left/-right); this reports a target, not physical wheel completion. High-level navigation turns temporarily override actual wheel control; forward/reverse and idle steering use the saved target. Runtime diagnostics expose that target in the IDE hardware panel.

Continuous movement occupies the drivetrain active-command slot without a finite physical executor or repeated tick charges. It keeps the runtime alive after instruction streams finish, bounded by the unchanged 180-second global safety timeout. Steering can change while this slot runs. A new continuous drive or stop cancels active plus pending drive work; finite movement/turn cancels an active continuous command and starts navigation. Finite-versus-finite work remains FIFO. Cancelled IDs report commandCancelled and remain in bounded history. clear_queue preserves the active command; abort_command releases it and lets queued work start next fixed tick. Ascending thread scheduling determines competing replacements and wheel-target writes. Other devices remain independent.

Finite forward/back commands for steerable mobility reuse BWRuntime with followSteering enabled: progress is accumulated from actual displacement projected onto the midpoint heading's signed tangent each fixed tick. This permits full arcs/circles while excluding sideways/vertical drift. The legacy serial regression executor retains its original start-axis distance behavior; straight finite BW motion remains equivalent. Tracked BW steering now supports curved travel too. No wheel-spin distance or position teleport is used. Normal stuck/deadline and damage pause behavior remains.

stop releases throttle without zeroing velocity and preserves the wheel target. Program cancellation/destruction/reset/respawn clears active/queued work and the target; existing BWController restores manual ownership. Program replacement creates a fresh device manager. Physical momentum and projectiles remain real.

This complete demonstration runs on Rattler (also works with Boomer differential tracks):

```python
steer_right(20)
forward()
clock = get_clock()
wait_for_clock(clock.time + 3)
steer_left(20)
clock = get_clock()
wait_for_clock(clock.time + 3)
steer_center()
clock = get_clock()
wait_for_clock(clock.time + 1)
stop()
```

See the [movement reference](BW_LANGUAGE.md#movement-commands) for continuous circle, tighter radius, sensor-based steering and ownership tables. Automated pure-simulation/controller tests cover these control paths; native Roblox Studio driving, wheel visuals, damage/recoil combinations and touch/manual handoff still require Play testing. Builds alone do not validate that experience.

## Resolved vehicle components

See [VEHICLE_COMPONENTS.md](VEHICLE_COMPONENTS.md) for catalog IDs, assembly/resolver contracts, source boundaries, migration tests and extension examples. BWDevices captures an immutable resolved profile at creation. Steering availability/limits and navigation pivot behavior come from mobility capabilities, not tankType; finite arcs project signed movement along changing headings. Installed sensor mounts populate independent pipelines using their own hardware properties. Computer components select registered instruction/queue tiers. Bus components supply the existing allocation curve and default reservations; instruction costs remain global BW policy.

BWController applies hardware allocation exactly once to state performance factors. Its existing development-tier selector installs the matching registered computer profile; component base ratings remain unscaled. No mass multiplier or duplicate propulsion modifier is introduced. Destruction/reset create a fresh state/profile binding and new pipelines. Model identifiers remain for visuals, identity and lifecycle checks, not for selecting movement or weapon mechanics. Full component tables are retained privately in a weak-key state registry; public snapshots include maxHealth, current physical velocity and motion diagnostics; full resolved component tables remain private.


## Current weapon-swap test loadouts

VehicleAssemblies now installs weapon.gatling on Boomer and weapon.cannon on Rattler. Gun behavior is not inferred from body identity. The Gatling's Recoil.Kind=Jackhammer selects the shared inertial recoil overlay even on tracks, so ground momentum/landing remains synchronized between hops. Without that gun, wheeled Rattler still drives normally but no longer hops or rattles on firing. Default weapon attributes/rates are unchanged; existing bus allocations still scale actual operation.

A small public weaponId descriptor selects client gun construction and effects independently of hull/turret/wheel art. Shot/preparation events identify their carrier and installed gun; cannon preparation no longer hardcodes Boomer. Renderer firing, cannon bulge, Gatling rotation, rocking, landing dust and muzzle effects use weapon metadata. HUD heat/reload displays use weapon operation. Body colors, tracks/wheels and computer tiers are preserved. The registry rebuilds a renderer if the weapon descriptor changes.

Regression infrastructure retains explicit historical assembly fixtures for existing physics/weapon baseline scenarios (groups0–13), without substituting simulation code. Separate groups14–15 load the actual live assemblies: production server + renderer swap tests and all13 documentation programs on both current tank simulations. Thus historical timing assertions remain meaningful while current swapped gameplay is verified independently. Native Studio visual/play validation is still pending.


## Source editor transactions

BWEditorText provides pure byte-indexed Enter, leading-indent Backspace, selected-line indent/outdent, smart-paste alignment and bounded history. BWEditorController keeps native TextBox clipboard/IME handling and records edits separately from game/BW execution. Tab/Backspace/undo shortcuts use a key-scoped native-echo guard. Enter has a separate native-newline transaction: InputBegan never writes a newline; the native insertion is decorated with indentation afterward. Intent survives key release, and a caret latch repairs a late native column-zero update. Recently committed native-first newline events are folded into the same undo transaction. Ordinary Backspace/selection/grapheme deletion stays native. Roblox caret offsets are bytes, including UTF-8 strings ([TextBox reference](https://create.roblox.com/docs/reference/engine/classes/TextBox/CursorPosition)).

Default Paste: align rebases an identified insertion from its common nonblank indentation to the prepared whitespace-only line prefix, preserving relative nesting. It supports a retained obsolete suffix, CRLF and leading tab columns; a multiline insertion directly before code gets a separating newline when needed. Inline or blank-only paste stays literal. Paste: exact bypasses reindentation. Neither mode rewrites source at Run. The compiler remains the four-space indentation authority; the editor is not a general code formatter. Native payloads and the final aligned result form one application undo transaction; no per-line paste rewriting or intermediate history entries occur.

Each selected tank retains its own text/caret/selection and undo/redo history. Histories are bounded to96 retained pre-edit states and512KiB of pre-edit text, retaining at least the most recent pre-edit state even for oversized input. UI editing never charges BW ticks. Undo/Redo toolbar buttons also support touch; shortcuts are source-focus-only and do not affect the hardware editor or selectable logs. Deferred callbacks are guarded across tank switches/destruction.

Automated BWEditor tests cover pure edits, reversed selections, exact and aligned AI paste, existing suffix preservation, CRLF/Unicode, atomic undo/redo, native-first/native-last echoes, late caret changes, immediate paste undo, per-tank isolation and raw Run submission. Roblox Studio is still required to verify real OS clipboard delivery, key repeat, modifier/focus ordering, mobile keyboard/IME and copy interactions; the mock event ordering is not native engine validation.


### Enter E3 frame-boundary correction

The previous task.defer-based correction was still within the native input resumption; it did not establish a frame boundary. E3 waits across two real Heartbeats with stable native Text/caret before writing indentation. Queued property events from its own Text writes are ignored by text identity as well as the immediate writing flag. Caret restoration is also scheduled on a later Heartbeat, with SelectionStart set before CursorPosition. See Roblox's [task scheduler documentation](https://create.roblox.com/docs/scripting/scheduler) and [deferred engine events](https://create.roblox.com/docs/scripting/events/deferred).

A second concrete bug was stale caret data adjacent to an existing newline: the cached cursor could identify the following existing line instead of the newly inserted line, leaving a blank line and moving the caret below it. E3 derives the insertion span from the settled native caret and validates it against previous/native text. The Enter decorator copies all native newline bytes verbatim and inserts whitespace only; it cannot generate another newline. Unmatched native edits fall back to ordinary native history rather than trapping future typing.

The toggle reads BW Editor • E3 and the ScreenGui has EditorVersion=E3-frame-enter. These identify the loaded client code after restart. Tests use separate same-resumption and later-Heartbeat queues, cover indented/colon lines followed by existing code, stale cached carets, late caret signals, native indentation, deferred own-write signals and newline-count invariants. Studio verification is still required; previous immediate mocks did not model this scheduler distinction.


Shift+Delete uses BWEditorText.deleteLine to remove the caret line and its newline (or the preceding newline for the final line). It preserves LF/CRLF and a valid UTF-8 caret, and ignores selection extent. The operation participates in the same undo history as Ctrl/Cmd+Z and Ctrl/Cmd+Y. Source-focus routing leaves hardware/log shortcuts native. Editor regression tests cover first/middle/final/empty lines, CRLF, Unicode, native delete echoes and keyboard undo/redo.


### E3.1 keyboard history ownership

Ctrl/Cmd+Z/Y now chooses one application-history target without rewriting the TextBox during native shortcut processing. The target remains authoritative past key release and across stable Heartbeat observations; native undo/redo Text/caret callbacks cannot create new edit records or clear redo. Repeated history chords advance the same logical history, and non-history input/lifecycle release settles the pending target first. Toolbar actions use the same history without a native-key transaction. Normal native text edits also wait for a stable frame boundary before automatic history recording, letting native-first shortcut intent arrive before recording a native undo as typing. Pressing Control/Command commits any pending ordinary typing before native Z/Y can erase its redo snapshot; pending Enter formatting stays on its own confirmed path. Enter's confirmed E3 path and Shift+Delete operation are preserved. Editor version label is E3.1.


## Function compilation and execution

`BWParser` pre-registers top-level function headers before parsing expressions. `BWCommands.signature` validates exact positional arity and records const/mutable parameter metadata. `BWExpression` keeps calls as AST nodes; user calls are never passed to device command resolution. Each function body is compiled with the existing `$assign`, `$set`, `$branch`, `$switch`, `$while`, `$jump`, `$call` instructions and the new `$return`. A final implicit `$return null` terminates fallthrough. Function definitions emit no top-level execution instruction. Names assigned in a function and its parameters form its lexical local set. Compile-time scalar constants are still substituted, except where shadowed by local bindings.

`BWFunctionAnalysis` performs bounded fixed-point, allocation-site points-to inference over the AST, followed by deep const/alias validation. Reference sets, unknown reference flows, readonly views, heap fields (including conservative dynamic-field slots), transitive function writes, and returns are propagated. Known built-in result metadata is scalar; unknown extension fields are not optimistically scalar. Conflicting const/mutable views, const-derived mutation and shared const references in multithread programs are rejected. This analysis intentionally merges branches/rebindings/call sites: false-positive rejection is possible, particularly for polymorphic helpers and allocation sites reused recursively. The compiler rejects nonconvergence rather than running unchecked code. There is no runtime const exception mechanism for parameter enforcement and no newly invented clone API.

`BWExecution.invoke` evaluates argument expressions exactly once, checks both stack guards before push, reserves mutable binding initialization, and executes compiled bodies through the **same** `instruction` method. The existing coroutine retains the expression continuation, return destination, evaluated operands and pending scanner acquisition. Explicit frames hold caller instruction stream/index/line, caller frame, local bindings, local variable versions and synchronization observations. A locals proxy reads shared globals only when a name is not lexically local. On return, the frame is popped and the caller's stream/index/line restored. The legacy `BWRuntime.new` delegates function-bearing programs to this production execution path; device navigation's single-instruction physical executor remains unchanged.

Top-level execution consumes no frame. Default server `BWConfig.MaxCallDepthPerThread=50`; runtime constructor argument five may supply a trusted `{MaxCallDepthPerThread=N}` override. The server never accepts it from BW source or a client hardware configuration. The aggregate guard is derived from installed computer thread capacity, not the number of used source streams. No push/count change occurs on rejected overflow. Stack overflow fails only its thread, cancels only commands owned by that thread, reports the function/thread/line, and lets other threads complete; final program status remains error. Other runtime errors retain the existing program-wide cleanup contract. Stop/destruction/replacement/reset clear all coroutines, pending evaluations, frames and devices.

Cost reservation and execution consume the same annotated AST. User call reservation includes arguments and normal writes for mutable bindings; body statements reserve separately. Const parameter variable nodes are explicitly annotated so neither cost estimation nor execution charges a variable read. Calls and returns have no fixed cost. Mutable arguments, ordinary locals, global reads/writes, property traversal, arithmetic and devices retain `BWChassis.Costs`; no costs were normalized to the illustrative one-tick read/write examples. Literal collection allocation keeps its existing zero cost. CPU exhaustion suspends before an operation, preserving evaluated operands and preventing duplicated side effects. Atomic ordinary body assignments retain their statement reservation. Device waits may suspend a larger expression, matching existing asynchronous expression semantics.

Free internal returns/statement transitions still count against `MaxOperationsPerCycle`; they cannot cause an unbounded dispatch loop. Diagnostics include current function, depth, peak depth, total/peak frames and derived limits. IDE thread rows show function/depth and the current function source line. Compiler tips for unmodified scalar parameters are metadata and zero-cost log events, not automatic edits.

### Function and device example

Commands remain asynchronous. This helper explicitly polls physical completion while yielding simulated time; wrapping `forward()` alone would merely return its acceptance dictionary.

```python
function await_command(const id):
    state = command_status(id)
    while state.state == "running" or state.state == "accepted" or state.state == "queued":
        clock = get_clock()
        wait_for_clock(clock.time + 0.1)
        state = command_status(id)
    return state

function drive_and_wait(const distance):
    accepted = forward(distance)
    if accepted.status == "fail":
        return accepted
    return await_command(accepted.commandId)

move = drive_and_wait(10)
print(move)
```

`tests/BWFunctions.spec.luau` executes real compiler output through the production VM, including recursion, alias validation, exact category totals, CPU starvation, independent stacks, physical device work, scanner waits, lifecycle cleanup, source locations and deterministic traces. Unit/server mocks do not validate native Studio input, rendering, mobile controls or transport timing.


## Flat-ground motion integration

The physics extension preserves BW syntax, CPU/device allocation, asynchronous queues and scanner timing. `BWTankAdapter` uses the resolved available braking acceleration when planning finite accelerated movement. `BWRuntime` uses resolved forward-travel odometry for changing-tangent progress and subtracts cumulative `motionCorrection` changes for fixed-axis/legacy fallback progress. Actual unwrapped-yaw odometry preserves full revolutions even within one update. The correction ledger separates split collision depenetration from physical travel; signed backward drift remains negative progress. Turn progress uses actual yaw, including angular impulses. Releasing a device or program does not zero physical momentum.

The server still uses its 60Hz fixed step. It predicts all tank poses, then resolves dynamic pairs and authoritative static cover in stable-ID order before committing all hitboxes and movement telemetry. Existing scanner observations occur before movement, as before; weapon recoil is applied at release after contact resolution and affects subsequent integration. Contact substeps do not advance BW or weapon/scanner clocks. Manual input and BW input feed the same `TankSimulation` path. No workspace physics ownership or client-supplied force results are introduced.

See [PHYSICS_FORCES_IMPLEMENTATION.md](PHYSICS_FORCES_IMPLEMENTATION.md) for the concrete state, surface/force interfaces, compatibility choices and tests. Native Studio behavior is not established by mocked tests/builds.

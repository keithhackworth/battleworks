# BW concurrent runtime

For the standalone programmer handbook, see [BW_LANGUAGE.md](BW_LANGUAGE.md).

BW programs now submit work to independent physical devices. This intentionally changes the old blocking movement-command contract. Existing tank models, recoil, terrain/collision resolution, damage, weapon heat and projectiles still use the existing fixed server simulation. No task-based gameplay scheduling or new movement engine is introduced.

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

Four spaces per indentation level. Thread blocks must be top-level, have unique integer IDs within chassis capacity, and start together. Legacy top-level statements append to thread 1 in source order. No user-defined functions, locks or events are added. Nested while loops are supported and scheduled under the same CPU/safety budgets.

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

50% allocation gives 75% performance. Allocation affects drivetrain maximum speed (and Boomer pivot rate), turret rotation rate, scanner acquisition time, and weapon preparation/firing interval. Rattler acceleration, braking, steering geometry, airborne momentum and recoil remain existing physics. Projectile speed/damage and heat/overheat rules are unchanged. Weapon timing is divided by performance; zero allocation disables operation without dividing by zero. Manual controls respect the same configured hardware. Manual scanner's internal three-angle sweep remains driver-only; BW addresses physical mounting angles only.

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

Each device has one active command plus the chassis-defined number of pending commands. Submissions never wait for space or overwrite accepted work. `deviceQueueFull` is a nonfatal result. Queue capacity is attached to the device, not the submitting thread. Rejections do not consume command IDs or mutate accepted work.

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

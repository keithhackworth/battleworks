# BattleWorks BW Language Handbook

Current implementation: **2026-11-09**.

BW is BattleWorks' small, server-authoritative tank programming language. Programs control the same movement, turret, weapon and scanner devices used by the game. They do not replace tank physics.

This handbook describes implemented features. [BW_RUNTIME.md](BW_RUNTIME.md) contains architecture notes and additional examples. The IDE also includes a **BW Handbook** popup.

## Contents

- [Getting started](#getting-started)
- [Syntax and values](#syntax-and-values)
- [Compile-time constants](#compile-time-constants)
- [Coordinates and angles](#coordinates-and-angles)
- [CPU cycles and instruction ticks](#cpu-cycles-and-instruction-ticks)
- [Chassis buses and device performance](#chassis-buses-and-device-performance)
- [Busy devices and command queues](#busy-devices-and-command-queues)
- [Command results and failures](#command-results-and-failures)
- [Movement commands](#movement-commands)
- [Turret commands](#turret-commands)
- [Weapon command](#weapon-command)
- [Scanner command](#scanner-command)
- [Clock and synchronization commands](#clock-and-synchronization-commands)
- [Queue and status commands](#queue-and-status-commands)
- [Debug output](#debug-output)
- [If, elif and else](#if-elif-and-else)
- [Switch and case](#switch-and-case)
- [While loops and truthiness](#while-loops-and-truthiness)
- [Threads and shared variables](#threads-and-shared-variables)
- [Safety limits and unsupported features](#safety-limits-and-unsupported-features)

## Getting started

1. Select the tank you want to program.
2. Open **BW Editor**, enter your program, and click **Run**.
3. BW takes control of that tank. Reopen the editor to inspect logs or the handbook.
4. Click **Stop** to cancel its program and device commands and return to manual control.

You can run a program on one tank and manually control the other. Each tank has its own program state. Switching selection does not stop the other tank's program.

```python
# Move and aim concurrently, then inspect the drive command.
move = forward(10)
turret_right(45)

clock = get_clock()
wait_for_clock(clock.time + 2)

print(command_status(move.commandId))
fire()
```

Movement and turret calls submit work immediately; they do not block until completion. The two-second delay above is explicit, not a guarantee that movement finished. Inspect command status when completion matters.

## Syntax and values

### Basic rules

- One statement per line; blank lines are allowed.
- Names are case-sensitive: `Scanner` is valid; `scanner` is not.
- `#` starts a comment outside a string, including an inline comment.
- Indent blocks with **four spaces**. Nested blocks add four more spaces.
- Variables require no declaration and may be reassigned.
- An undefined variable read is a runtime error, except when passed by name to the reference-aware synchronization functions described below.

Arguments called `studs`, `degrees`, `seconds`, `value` or `device` in this document are positional placeholders. They are not named-argument keywords. Supported named arguments are `to=`, `position=` and `best_effort=`, only on commands that list them. Put positional arguments before named ones.

### Value types

| Type | Examples | Notes |
| --- | --- | --- |
| Number | `10`, `1.5`, `-45`, `1e2` | Must be finite; no automatic string conversion. |
| String | `"enemy"`, `'hello'`, `""` | Single/double quotes; common escaped characters supported. |
| Boolean | `true`, `false` | Lowercase. |
| Null | `null` | Explicit absence of a value. |
| Array/list | `[10, 20]`, `[]` | **Zero-based indexing**; program-created arrays are mutable references. Scanner/result arrays remain immutable. |
| Dictionary | `{"shots": 0}` | String keys; programmer-created dictionaries can be mutable. |

```python
shots = 0
shots = shots + 1

numbers = [10, 20]
print(numbers[0])

stats = {"shots": shots}
stats.shots = stats.shots + 1
print(stats["shots"])
```

Dictionary properties support both `result.status` and `result["status"]`. Missing dictionary keys return `null`. Invalid array indexes or indexing a non-container are errors.

Scanner snapshots, their detection lists and hit points, and callable result dictionaries are immutable. Assigning a snapshot to a variable does not make it editable.

Arrays compare by contents; dictionaries compare by identity. Compare dictionary fields when checking observations.

### Operators

| Precedence, highest first | Operators |
| --- | --- |
| Grouping, calls, indexing/properties | `(...)`, `Scanner(...)`, `[index]`, `.field` |
| Unary signs | `-`, `+` |
| Multiplication/division | `*`, `/` |
| Addition/subtraction | `+`, `-` |
| Comparisons | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Logical negation | `not` |
| Logical conjunction | `and` |
| Logical disjunction | `or` |

Use `=` to assign and `==` to compare. Arithmetic requires numbers. Ordering requires two numbers or two strings of the same type. Division by zero is an error. Write `a < b and b < c`, not chained comparisons.

`and`/`or` short-circuit: skipped expressions do not scan, submit commands or consume expression ticks. Existing `if` and logical operators require actual booleans. `while` has the broader truthiness rules documented below.

## IDE editing and AI code replacement

- **Enter:** retain the current indentation. After a trailing `:` outside strings/comments, add one four-space level. Inline comments after a block header are supported.
- **Backspace in leading indentation:** remove back to the previous four-column stop. Ordinary text/selection deletion stays native.
- **Shift+Delete:** delete the caret’s entire line, including its line break. Ctrl/Cmd+Z restores it in one step; Ctrl/Cmd+Y reapplies the deletion. Other selected lines are not deleted.
- **Tab / Shift+Tab:** indent/outdent the current line or all selected lines. A selection ending at the following line's column one excludes that following line.
- **Paste: align** (default): prepare the insertion indentation, then Ctrl/Cmd+V. The snippet's common outer indentation is removed and its internal nesting is rebased to that point. Leading tabs in the snippet are interpreted as four-column tab stops; strings, inline whitespace and LF/CRLF endings are preserved. Following obsolete code remains aligned rather than moving to column one. A multiline snippet inserted directly before code gets a separating newline when the AI clipboard omitted its final newline. Blank-only and inline/mid-expression pastes stay literal. Multiline native/context-menu paste uses the same alignment where an insertion can be identified.
- **Paste: exact:** click the paste-mode button to disable alignment and preserve the received text byte-for-byte. No conversion is performed on Run either. BW still requires four-space block indentation; exact pasted tabs/invalid indentation produce normal compiler diagnostics.
- **Undo / Redo:** toolbar buttons or Ctrl/Cmd+Z, Ctrl/Cmd+Y, Ctrl/Cmd+Shift+Z. A multiline or aligned paste is one undo operation. History and selections stay separate for each selected tank.

Typical replacement workflow: move to the indentation where the new block belongs, paste the AI snippet, then remove obsolete code yourself. The editor preserves relative nesting; it does not infer missing indentation inside malformed code or remove Markdown fences.

```text
Before (| is the prepared insertion caret):
with thread(1):
    |old_command()

Clipboard:
if true:
    forward(10)

After paste:
with thread(1):
    if true:
        forward(10)
    old_command()
```

## Compile-time constants

`CONST name = expression` declares an immutable scalar at compilation:

```python
CONST move = 10
CONST turn = 90
CONST half_turn = turn / 2
forward(move)
back(move)
turn_left(half_turn)
forward(move)
```

The commands above have exactly the same runtime CPU cost and behavior as `forward(10)`, `back(10)`, `turn_left(45)`, `forward(10)`. Declarations emit no runtime instructions or storage. References become literal values before execution and before CPU reservations are calculated. Arithmetic, comparisons and logical work inside an initializer are evaluated once during compilation and cost zero runtime ticks. An expression outside a declaration still pays its normal costs: `forward(move + 1)` computes an addition; declare `CONST next_move = move + 1` to precompute it. Ordinary mutable variables retain their read/write costs.

Allowed values are numbers, strings, booleans and null. Initializers accept existing arithmetic, comparison, logical and unary operators, parentheses and previously declared constants. Existing strict operand typing and boolean logical semantics apply. No function is currently compile-time pure: calls, runtime variables, arrays, dictionaries and indexing are rejected, including in short-circuited initializer branches. Self/forward references and circular definitions are rejected; declarations require an initializer.

Names use existing case-sensitive identifier rules and cannot be keywords or built-in command names. Constants share the program-wide namespace across threads, are visible after declaration in textual source order, and cannot shadow/redeclare constants or mutable assignment names. A declaration inside a thread or conditional is still compile-time and unconditional; prefer declarations at the top of the program. Constants do not leak across compilations. Reassignment, property/index assignment and using a constant as a synchronization variable reference are compile errors. Scalars have no mutable aliases. Commands remain case-sensitive: use `forward`, `back`, `turn_left`, not `Forward`, `Back`, `Rotate_left`.

## Coordinates and angles

Movement distances are **studs**. Times are **simulation seconds**. Angles are **degrees**.

| World heading | Direction | World axis |
| ---: | --- | --- |
| 0° | North | −Z |
| 90° | East | +X |
| 180° | South | +Z |
| 270° | West | −X |

World headings increase clockwise, independently of the camera.

- Chassis/turret `to=heading` commands use **world headings**.
- Relative rotations start from the actual heading when the physical command begins.
- Scanner angles and returned detection bearings are **chassis-relative**: 0° forward, 90° right, 180° backward, 270° left.

Scanner results expose both relative_direction and world_direction. Use world_direction directly with a to= heading command; no chassis-heading conversion is required. get_facing_direction().world_direction reads the tank body's current compass heading. The old scanner direction key has been renamed to relative_direction.

## CPU cycles and instruction ticks

The arena uses its existing fixed **60 Hz server simulation**. BW instruction budgets replenish at **10 CPU cycles per simulation second**, one cycle every **0.1 seconds**.

A **tick** is a gameplay instruction cost, not a real processor clock tick or a fixed delay. Each thread receives its own chassis-defined ticks per cycle. Several commands may execute in the same cycle.

If the next instruction cannot fit, it waits for sufficient credit. Unused credit normally carries for up to two cycles; a larger instruction can accumulate its bounded reservation, up to 1,024 ticks. Instructions reserve sufficient credit before starting, then charge only the operations actually evaluated. Physical observations and explicit waits can suspend evaluation without repeating earlier side effects.

CPU throughput is separate from physical time. Issuing `forward(100)` costs one base tick; driving the distance does not repeatedly consume CPU ticks. Queue waiting, acquisition and reload time are separate from instruction cost.

### Tick costs

| Operation | Ticks |
| --- | ---: |
| `forward`, `back`, `steer_left`, `steer_right`, `steer_center`, `stop` | 1 |
| Chassis rotation | 1 |
| Turret rotation | 1 |
| `Scanner` submission | 1 |
| `fire` submission | 2 |
| `get_clock` | 0 |
| `get_facing_direction` | 0.1 |
| `print` and automatic debug logging | **0** |
| `wait_for_clock`, `wait_for`, `variable_has_changed` initiation | 0.2 |
| `clear_queue`, `abort_command`, `command_status` | 1 |
| `if` / `elif` decision | 1 |
| Each `while` condition test, including final false test | 1 |
| `switch` dispatch, regardless of case count | 2 |
| Variable read | 0.1 |
| Assignment/property write | 0.2 |
| Arithmetic or comparison | 0.2 |
| Logical operation | 0.1 |
| Dictionary/array access | 0.1 |

Command costs are base costs; evaluated expressions and assignments normally add their costs. A switch has no hidden per-case comparison fee. Literals and control-flow jumps add no ticks.

Examples:

- `forward(10)` costs 1 tick.
- `forward(distance)` costs 1 + 0.1 = 1.1 ticks.
- `result = forward(10)` costs 1 + 0.2 = 1.2 ticks.
- `distance = 10 + 5` costs 0.2 + 0.2 = 0.4 ticks.
- `if distance < 30:` costs 1 + 0.1 + 0.2 = 1.3 ticks for its test.

**Debug exception:** printing existing values and pure display calculations is free, including reads, indexing, comparisons and arithmetic. An expression containing a real device/query/wait call inside `print()` keeps its normal expression costs. Thus printing a saved scan is free, while `print(Scanner(0))` still performs and pays for a scan. Assigning the return value from `print()` still costs a variable write. Rolling histories, log-rate protection and hard execution limits still apply.

## Chassis buses and device performance

Each bus has two independent responsibilities: run one BW thread and provide a reserved allocation budget for devices.

| Chassis | Cores/threads/buses | Ticks/cycle/thread | Pending commands/device |
| --- | ---: | ---: | ---: |
| Bunny | 1 | 10 | 1 |
| Dual | 2 | 15 | 2 |
| Quad | 4 | 20 | 4 |
| Octa | 8 | 30 | 8 |
| Hexadeca | 16 | 40 | 16 |

Default tanks:

- **Boomer:** Bunny, one thread/bus.
- **Rattler:** Octa, eight threads/buses.

Bunny receives 100 ticks/second for its one thread. Octa receives 300 ticks/second **per thread**. These are throughput figures, not guaranteed delays for individual commands.

Each physical device belongs to exactly one bus. Devices on a bus must reserve no more than **100% total allocation**. Idle devices do not donate their reservation. Multiple devices on the same bus can operate concurrently. Any thread can command any installed device, regardless of which bus hosts it.

Effective device performance is:

```text
a = allocationPercent / 100
performance = 1 - (1 - a)^2
```

| Allocation | Performance |
| ---: | ---: |
| 0% | 0%, disabled |
| 25% | 43.75% |
| 50% | 75% |
| 75% | 93.75% |
| 100% | 100% |

Performance affects movement speed caps, turret rotation rate, weapon preparation/firing intervals and scanner acquisition time. It does not increase projectile speed or damage, or replace acceleration, recoil, collisions and airborne momentum.

Radar range currently remains **150 studs at 100% distance effectiveness**, independently of bus sharing. Hardware has configurable range/effectiveness fields for future equipment selection.

### Default allocations

Boomer shares bus 1: drivetrain 40%, turret 20%, weapon 20%, and each of its eight sensors 2.5%. Its effective drivetrain performance is 64%; turret/weapon performance is 36%.

Rattler reserves buses 1/2/3 for drivetrain/turret/weapon at 100% each. Its eight sensors share buses 4–8; paired sensors reserve 50% each and single sensors reserve 100%.

The development **Hardware / threads** editor can override defaults while a program is stopped. Configuration persists across battle reset; program variables and active work do not.

## Busy devices and command queues

| Device | Commands sharing its pipeline |
| --- | --- |
| `drivetrain` | Forward, reverse, chassis left/right rotations |
| `turret` | Turret left/right rotations |
| `weapon` | Single/timed firing |
| `sensor0` … `sensor315` | That physical sensor's scans; each has an independent queue/cooldown |

A device is **busy** while it has an active operation. This can include movement, preparation, waiting for a usable weapon, firing, acquisition or scheduled sensor cooldown.

Each device has one active command plus a chassis-limited FIFO pending queue. Queue depth excludes the active command.

- Idle: accepted work can begin.
- Busy with room: accepted work queues.
- Busy with full queue: immediate `deviceQueueFull` failure. Existing work is unchanged; the thread does not wait for room.

A rejected full-queue submission still spends its submission ticks. Accepted queued movement captures its starting pose when it begins, not when it was submitted.

```python
first = forward(20)
second = turn_right(90)
observation = Scanner(position=0)
```

The drivetrain moves, the turn waits behind it, and the scanner acquires while the drivetrain continues. Scanner observation waits only its requesting thread.

Physical duration is not a fixed per-command tax. Distance, terrain, actual acceleration, recoil, allocation, weapon readiness and acquisition settings determine device time. Neither an active device nor queue waiting repeatedly spends instruction ticks.

Finishing a thread does not stop another thread or accepted device work. The program completes when all threads finish and devices drain. Stop cancels outstanding operations, including an unreleased weapon preparation, while preserving physical inertia and already launched projectiles.

## Command results and failures

Every callable returns a dictionary containing:

```json
{"status": "success", "reason": null}
```

or:

```json
{"status": "fail", "reason": "deviceQueueFull"}
```

Movement, turret and weapon success means **accepted**, not necessarily physically completed. These results include a `commandId`, scoped to this program run. Use `command_status(id)` to inspect its later outcome.

Scanners return acquired observations. Clock/change functions return dictionaries with `.time` or `.changed`, not bare scalar values.

Normal operational failures return values and allow execution to continue. You can inspect or ignore them. Syntax errors, undefined variables, invalid expression operations and immutable-value mutation stop safely with source lines.

Supported legacy `best_effort=true/false` arguments do not make asynchronous device failures fatal. Default is `true`. Lifecycle cancellation, safety limits and genuine runtime errors are never bypassed.

### Failure codes

| Code | Meaning |
| --- | --- |
| `deviceQueueFull` | Device's pending queue is full. |
| `deviceUnavailable` | Device is unknown or not installed. |
| `unsupportedDrivetrain` | Installed mobility lacks the requested steering capability. |
| `deviceDisabled` | Device has 0% operating allocation. |
| `invalidSensor` | Scanner angle/index is invalid. |
| `invalidArgument` | Invalid computed operational argument or unknown command ID. |
| `scannerBusy` | Bounded server scanner/geometry budget is exhausted. |
| `sensorCooldown` | Physical sensor is cooling down; normally handled by its pipeline. |
| `commandCancelled` | Work was cancelled. |
| `tankDestroyed` | Tank lifecycle terminated work. |
| `stuck` | An accepted movement/turn made no meaningful progress. |
| `commandTimedOut` | Accepted physical work exceeded its safety deadline. |
| `executionFailed` | Other physical execution failure. |

`deviceDamaged` is reserved for future device-specific damage.

## Movement commands

| Command | Required input | Base ticks |
| --- | --- | ---: |
| `forward(studs)` | Distance | 1 |
| `back(studs)` | Distance | 1 |
| `forward()` / `back()` | None; continuous throttle | 1 |
| `steer_left(degrees)` / `steer_right(degrees)` | Physical wheel angle | 1 |
| `steer_center()` | None; straight wheels | 1 |
| `stop()` | None; release drivetrain | 1 |
| `turn_left(degrees)` / `turn_left(to=heading)` | Relative or absolute rotation | 1 |
| `turn_right(degrees)` / `turn_right(to=heading)` | Relative or absolute rotation | 1 |

Distance/navigation commands and steer_left/right accept optional `best_effort=true`; `stop()` and `steer_center()` take no arguments. All use the drivetrain device and return acceptance/failure dictionaries; accepted work includes `commandId`. Steering updates bypass its queue. Operational failures remain nonfatal.

### forward(studs)

**Input:** finite distance from 0 to 1,000 studs.

Drive forward for the requested actual distance. Installed mobility follows its persistent steering target. Finite BW driving accumulates signed movement along its changing forward tangent, so full arcs/circles can complete on wheels or tracks. Sideways/vertical drift and wheel spin do not count; real recoil along the commanded direction does. Walls can prevent completion. The command does not teleport or wait for the full drive.

### back(studs)

**Input:** finite distance from 0 to 1,000 studs.

Reverse for the requested actual distance. Installed mobility follows the changing reverse tangent with persistent steering. Uses normal vehicle physics, including naturally reversed yaw while backing. Progress and failure rules match `forward`.

### forward() / back()

**Input:** no distance (optional `best_effort` remains accepted). **Cost:** 1 tick per submission.

Drive continuously forward/reverse at normal configured performance. The thread continues immediately; other threads/devices/scanners can run. An active continuous command reports `running` and keeps BW in control even after all instruction streams finish. It ends when replaced, stopped, aborted, or cancelled by Stop, reset, destruction, respawn, program replacement/error or the existing 180-second safety timeout. No repeated CPU charge occurs while driving. `forward(0)` is a finite zero-distance operation, distinct from `forward()`.

### steer_left(degrees) / steer_right(degrees)

**Input:** a finite angle 0..180 degrees; requests above the installed physical maximum are clamped. Default Boomer tracks use a 45° steering control range, mapped to relative tread intent. Rattler wheels have a current physical maximum of approximately 31.5°, so `steer_right(35)` requests full available lock. **Cost:** 1 tick per update.

Set an absolute steering target relative to straight ahead. Wheeled mobility positions the front wheels; tracked mobility changes relative tread intent through the existing differential steering model. Repeating a command does not add angles. `steer_right(20)` sets steering; `turn_right(20)` requests 20° of chassis heading change. Steering itself does not move/rotate the chassis. It reaches actual wheels through the existing steering smoothing, car physics and airborne control restrictions. New steering takes effect during continuous or finite driving, without restarting throttle. A high-level turn temporarily controls actual steering; the persistent wheel target resumes afterward.

Success includes `commandId` and `steeringDegrees`, the applied signed target (positive left, negative right). The steering command record immediately becomes `completed`: this confirms the target was accepted, not that wheels have physically reached it. Both default tanks support steering. A mobility component with steering disabled returns `fail / unsupportedDrivetrain`, regardless of model identity. Computed invalid arguments return `invalidArgument`; invalid literals are compile errors. Steering requires an installed, enabled drivetrain and remains subject to server damage restrictions on actual controls.

### steer_center()

**Input:** none. **Cost:** 1 tick.

Set the persistent steering target to zero without stopping. Wheels straighten through existing smoothing; tracks return to equal tread intent. Same result shape as steer_left/right, with `steeringDegrees: 0`. Requires the installed mobility component to support steering.

### stop()

**Input:** none. **Cost:** 1 tick.

Cancel active and pending drivetrain commands and release throttle. Actual momentum/recoil is preserved; existing coasting handles the stop. The steering target is retained until changed or program lifecycle cleanup. With no active drive operation, tracked steering produces no tread movement; `stop()` releases both treads and does not leave a pivot running. Turret, weapon and scanner work continue. Returns a completed command ID; cancelled movement IDs report `cancelled / commandCancelled`. Stop requires an installed drivetrain but is accepted at zero allocation for safe release.

### Drivetrain ownership rules

| Issued operation | Active/queued drivetrain behavior |
| --- | --- |
| Steering setpoint | Updates the shared wheel target immediately, including when the queue is full. Does not cancel navigation. |
| `forward()` / `back()` | Cancels all active and pending drivetrain work, then becomes its sole active command. |
| Finite drive or chassis turn while continuously driving | Cancels continuous drive and starts navigation. |
| Finite drive or chassis turn while navigating | Existing bounded FIFO and queue-full failure rules. |
| `stop()` | Cancels active/pending drive work and releases throttle. |
| `clear_queue("drivetrain")` | Removes pending work, preserving the active command and wheel target. |
| `abort_command("drivetrain")` | Cancels active work; any pending navigation starts next fixed tick. |
| Program Stop/replacement/reset/death | Clears queues, active drive and persistent target; manual control returns through existing ownership rules. |

Different threads share one drivetrain and one wheel target. Ascending thread execution order makes competing submissions deterministic: the last reached replacement/setpoint wins. Accepted cancellation records remain queryable within normal history limits. Devices on other buses remain independent. Bus allocation still scales maximum driving speed; acceleration, braking, steering smoothing, recoil and collision physics are unchanged. Immobilization filters throttle/steering server-side without erasing the persistent intent.

### Continuous steering examples (Rattler)

Circle continuously:

```python
steer_right(20)
forward()
```

Change turning radius without stopping (35° clamps to current physical lock):

```python
steer_right(20)
forward()
clock = get_clock()
wait_for_clock(clock.time + 5)
steer_right(35)
```

Change direction of curvature, straighten and coast to a stop:

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
wait_for_clock(clock.time + 3)
stop()
```

Sensor-based radius adjustment (introductory control, not a complete orbit controller):

```python
steer_right(20)
forward()
while true:
    scan = Scanner(position=2)
    if scan.status == "success" and scan.count > 0:
        target = scan.detections[0]
        if target.type == "tank":
            if target.distance < 40:
                steer_right(10)
            elif target.distance > 60:
                steer_right(30)
            else:
                steer_right(20)
```

### turn_left(degrees) / turn_left(to=heading)

**Input:** choose either relative degrees from 0 to 1,440, or absolute world heading from −36,000 to 36,000, normalized modulo 360.

Rotate counterclockwise. Relative turns accumulate rotation, including multiple revolutions. Absolute turns honor the left direction even if it takes the longer route.

Installed mobility determines turning: default Boomer tracks can pivot, while default Rattler wheels must drive a curved path and retain existing airborne restrictions. Changing components changes these capabilities independently of model identity.

### turn_right(degrees) / turn_right(to=heading)

**Input:** same ranges as `turn_left`.

Rotate clockwise using the corresponding relative or absolute semantics. `turn_right(360)` requests a full revolution; `turn_right(to=360)` targets north.

## Turret commands

| Command | Required input | Base ticks |
| --- | --- | ---: |
| `turret_left(degrees)` / `turret_left(to=heading)` | Relative or absolute rotation | 1 |
| `turret_right(degrees)` / `turret_right(to=heading)` | Relative or absolute rotation | 1 |

Both support `best_effort=true`, use the turret pipeline and return acceptance/failure dictionaries with `commandId` on acceptance.

### turret_left(degrees) / turret_left(to=heading)

**Input:** relative degrees from 0 to 1,440, or absolute heading from −36,000 to 36,000 normalized modulo 360.

Rotate the actual turret counterclockwise. Absolute headings are world-relative, independently of chassis and camera orientation. Relative rotation starts when the queued operation begins. Recoil and chassis motion remain part of actual barrel orientation.

### turret_right(degrees) / turret_right(to=heading)

**Input:** same ranges as `turret_left`.

Rotate clockwise. The specified direction is honored for absolute targets; it is not automatically the shortest route. It can operate concurrently with drivetrain or weapon commands.

## Weapon command

| Command | Input | Base ticks |
| --- | --- | ---: |
| `fire()` | None: single logical activation | 2 |
| `fire(seconds)` | Hold duration | 2 |

### fire() / fire(seconds)

**Optional:** `best_effort=true`. Uses the weapon pipeline.

**Input:** omitted for one logical weapon activation, or finite seconds from 0 to 10. `fire(0)` fires nothing.

**Returns:** acceptance/failure dictionary, including `commandId` on acceptance. Acceptance is not proof a shell hit anything.

Timed firing holds the tank's normal trigger for the duration, respecting reload, preparation, firing rate, heat and overheat cooldown. Submission costs ticks once, not per bullet.

At full performance the cannon (currently mounted on Rattler) prepares for 0.20 seconds and has a 0.65-second firing interval. The Gatling (currently mounted on Boomer) has a 0.10-second shot interval; sustained fire stops after at most 3 seconds, followed by a mandatory 2-second cooldown. Bus allocation can lengthen preparation/firing intervals. Neither BW nor bus allocation increases projectile speed or bypasses weapon rules.

## Scanner command

| Form | Input | Base ticks |
| --- | --- | ---: |
| `Scanner(angle)` | Mounted chassis-relative angle | 1 |
| `Scanner(position=index)` | Mounted sensor index | 1 |

### Scanner(angle) / Scanner(position=index)

Supports optional `best_effort=true`. Choose **one** angle or position argument.

| Position index | Angle | Relative direction |
| ---: | ---: | --- |
| 0 | 0° | Forward |
| 1 | 45° | Forward-right |
| 2 | 90° | Right |
| 3 | 135° | Back-right |
| 4 | 180° | Back |
| 5 | 225° | Back-left |
| 6 | 270° | Left |
| 7 | 315° | Forward-left |

Angles may be any finite number that normalizes to a valid mounted angle modulo 360. Position must be an integer **0–7** and does not wrap. Literal invalid inputs fail validation; computed invalid inputs return `invalidSensor`. A valid location still requires installed hardware.

Each sensor owns an independent pipeline and 0.1-second cooldown. A separate shared query/geometry safety budget can return scannerBusy; this is not a global sensor cooldown. Device acquisition priority rotates deterministically to avoid always favoring the same sensors. Default acquisition is **0.05 seconds / effective device performance**, scheduled on a fixed simulation step. Acquisition/cooldown do not repeatedly spend CPU ticks.

An accepted request suspends only the requesting thread until its observation is acquired. Other threads/devices continue. Queue rejection returns immediately.

### Successful scanner result

```json
{
  "status": "success",
  "reason": null,
  "sensor": 45,
  "timestamp": 12.345,
  "range": 150,
  "count": 1,
  "detections": [
    {
      "type": "tank",
      "distance": 58,
      "relative_direction": 39.6,
      "world_direction": 129.6,
      "player": "player3.Rattler#stable_id",
      "relation": "enemy",
      "point": {"x": 15.2, "y": 3.6, "z": -42.1}
    }
  ],
  "type": "tank",
  "distance": 58,
  "relative_direction": 39.6,
      "world_direction": 129.6,
  "player": "player3.Rattler#stable_id",
  "relation": "enemy",
  "point": {"x": 15.2, "y": 3.6, "z": -42.1}
}
```

The numbers above illustrate the shape; they are not a guaranteed reading.

| Field | Meaning |
| --- | --- |
| `sensor` | Physical mounting angle **in degrees**, even when using position index. |
| `timestamp` | Actual authoritative acquisition time in arena seconds. |
| `range` | Effective range in studs; currently defaults to 150. |
| `count` | Number of visible detections. |
| `detections` | Immutable zero-based array, sorted nearest first. |
| `detections[i].type` | `"tank"` or `"wall"` (solid obstacle). |
| `.distance` | 3D range from scanner origin to observed visible surface. |
| `.relative_direction` | Actual chassis-relative bearing to that surface, measured at acquisition. |
| `.world_direction` | World compass bearing to the same surface: north 0°, east 90°, south 180°, west 270°. |
| `.player` | Unique `owner.tank#id` tank identity, or null for walls. |
| `.relation` | `"enemy"` / `"teammate"` for tanks, otherwise null. |
| `.point` | Immutable world-space visible surface position `{x, y, z}`. |

Top-level `type`, `distance`, `relative_direction`, `world_direction`, `player`, `relation` and `point` are conveniences describing the nearest detection. Empty scans are successful with `count=0`, `detections=[]` and null nearest-object fields.

The origin is authoritative tank position + 2.5 studs world Y. The cone is 15° total, ±7.5°. Fixed sensor mounts are 45° apart, so eight simultaneous fixed scans still leave gaps between cones. An object between cones can be missed even within range; nearby is not the same as inside a cone. All visible tanks and obstacles found within the cone/range compete, with occluded objects excluded. Multiple hits on the same object are consolidated. Objects need not have their centers inside the cone if part of their physical body is visible.

Walls and nearer bodies block hidden objects. Your own tank, projectiles, smoke and cosmetic components are ignored. Current non-queryable wrecks are excluded. Geometry/raycast work is bounded; a safety overflow returns `scannerBusy`, never silently partial success.

All entries share one observation time. The timestamp is not submission, queue-entry, display or consumption time. Scans do not continuously update after returning and provide no automatic velocity estimate, tracking or aiming.

```python
scan = Scanner(position=4)
if scan.status == "success":
    print(scan.count)
    if scan.count > 0:
        first = scan.detections[0]
        print(first.player)
        print(first.distance)
        print(first.relative_direction)
        print(first.world_direction)
```

Check `status` before using `count` or `detections`: a failure dictionary is not a successful snapshot. Each completed sensor has its own decaying light event, including an empty-scan pulse; multiple simultaneous scans do not overwrite one another. Hardware / threads shows per-sensor acquisition totals and the latest count or failure code/time. A print guarded by success and count > 0 intentionally skips empty/failed scans; inspect those rows or print the scan unconditionally when debugging.

## Clock and synchronization commands

| Command | Input | Base ticks |
| --- | --- | ---: |
| `get_facing_direction()` | None | 0.1 |
| `get_clock()` | None | 0 |
| `wait_for_clock(targetTime)` | Absolute simulation time | 0.2 |
| `wait_for(variable)` | Variable reference | 0.2 |
| `variable_has_changed(variable)` | Variable reference | 0.2 |

### get_facing_direction()

**Input:** no arguments. **Base cost:** 0.1 ticks. No device queue or physical wait.

**Returns:** `{status: "success", reason: null, world_direction: number}`.

Reads the authoritative tank **chassis** compass heading, normalized to 0–359.999…°. North is 0°, east 90°, south 180° and west 270°. This is actual current body orientation, not turret direction, camera orientation or a queued turn's requested target. The getter does not rotate the tank.

```python
facing = get_facing_direction()
print(facing.world_direction)
```

For a detected target, its scan already contains an absolute bearing, so you can issue an absolute turn without doing conversion math:

```python
scan = Scanner(position=0)
if scan.status == "success" and scan.count > 0:
    hit = scan.detections[0]
    turret_right(to=hit.world_direction)
```

Use `turn_right(to=hit.world_direction)` to rotate the chassis instead. The command names are `turn_right` and `turret_right`; a positional rotation argument is still a relative amount. Scanner bearings reflect acquisition time, while a later facing query reflects the current tank heading.

### get_clock()

**Returns:** `{status: "success", reason: null, time: number}`.

Reads authoritative arena simulation seconds. Arena time can already be nonzero when the program starts. Read `.time`; the result itself is a dictionary, not a number.

### wait_for_clock(targetTime)

**Input:** finite absolute arena time, usually `clock.time + delay`.

**Returns:** standard success dictionary after the wait, or `invalidArgument` for an invalid computed input.

Suspends only the caller until the first CPU cycle at/after the target. A target already reached returns immediately. The wait is not repeatedly charged.

```python
clock = get_clock()
wait_for_clock(clock.time + 0.5)
print("half a second or more has elapsed")
```

### wait_for(variable)

**Input:** an actual variable name, not an evaluated expression. The variable may not exist yet.

**Returns:** `{status: "success", reason: null, value: sharedValue, version: number}`.

Waits until the variable is assigned something other than `false` or `null`. An already-ready value returns immediately. **Unlike while**, zero, empty strings and empty containers count as ready here. This is a readiness wait, not a wait for the next assignment.

Returning observes that variable's current version for this thread. Missing variables may be waited on without an undefined-variable error.

### variable_has_changed(variable)

**Input:** an actual variable name.

**Returns:** `{status: "success", reason: null, changed: boolean, version: number}`.

Checks whether the variable has been assigned since this thread last observed its version. Each thread starts with observed version zero; missing variables have version zero. Every root assignment increments the version, even if the new value equals the old value.

Calling this function updates that thread's observation. `wait_for` also observes a version when it returns. It does not wait. Test `.changed`, not the result dictionary as a boolean.

Property writes increment the version of the named root. Aliases share dictionary contents but do not synthesize version changes for every alias.

## Queue and status commands

| Command | Input | Base ticks |
| --- | --- | ---: |
| `command_status(commandId)` | Accepted command ID | 1 |
| `clear_queue(device)` | Device name string | 1 |
| `abort_command(device)` | Device name string | 1 |

### command_status(commandId)

**Input:** command ID returned from a successful movement/turn/fire submission in this run.

**Returns:**

```json
{
  "status": "success",
  "reason": null,
  "commandId": 1,
  "device": "drivetrain",
  "state": "running",
  "completionReason": null
}
```

States are `accepted`, `queued`, `running`, `completed`, `failed` or `cancelled`. `completionReason` is null while pending/running and after successful completion; a failed/cancelled command carries its terminal code.

Query success means the command was found, not that it completed. Unknown or expired IDs return `invalidArgument`. The 512 most recent terminal command records are kept in a rolling history, plus every active/queued command; old terminal IDs can expire without stopping execution. There is no built-in blocking command-completion wait; use a while loop to poll, preferably with clock waits between queries.

### clear_queue(device)

**Input:** installed device name string, such as `"drivetrain"`, `"turret"`, `"weapon"` or `"sensor45"`.

**Returns:** standard success dictionary, or `deviceUnavailable`.

Cancels pending commands without interrupting active work. A cancelled pending scan wakes its caller with `commandCancelled`.

### abort_command(device)

**Input:** same device-name strings as `clear_queue`.

**Returns:** standard success dictionary, or `deviceUnavailable`. Aborting an idle installed device succeeds.

Cancels the active operation; pending commands remain. The oldest pending command may begin at the next device update. Cancels an unreleased weapon preparation, not an already launched projectile. Physical momentum remains.

To cancel all device work:

```python
clear_queue("drivetrain")
abort_command("drivetrain")
```

## Debug output

| Command | Input | Base ticks |
| --- | --- | ---: |
| `print(value)` | One supported value or expression | **0** |

### print(value)

**Returns:** `{status: "success", reason: null}`.

Writes readable output to this tank's private IDE history. No `best_effort` argument is supported. Formatting existing values and pure display calculations is free. Expressions containing real device/query/wait operations retain their normal costs; printing is not a way to bypass gameplay costs.

```python
data = {"distance": 20}
print(data.distance)
print(data.distance * 2)
```

Generic formatting is bounded at 2,048 displayed bytes without changing the stored value. Automatic scanner diagnostics list every detection separately. Explicit `print(scan)` is an additional entry after automatic scan output.

Log prefixes identify:

- **Command:** submission/result such as forward or fire.
- **Scanner(angle):** actual acquired observation; indexed lines below it are detections from that snapshot.
- **print:** explicit output.
- **L3:** source line 3.
- **t=5.833:** authoritative simulation timestamp.
- **T1:** thread 1.

Logging and scan counts are not lifetime execution quotas. Valid continuous loops can scan and print repeatedly until Stop or the normal program timeout. To protect performance, excessive logging emits a rate-limit notice and omits further entries in that CPU cycle; execution and scanner results continue. Hardware diagnostics show total scans/log attempts and omitted log count.

The IDE execution log is selectable and read-only. Long histories use bounded pages (8,192 bytes / 120 lines per displayed text box) to avoid an oversized UI element. Use **Older** for earlier entries and **Latest** to follow live output. The header distinguishes **Prints run** on the server from **received** print events on the client; thread diagnostics show loop-test and print counts. Click it and use Ctrl+A/Ctrl+C, or platform equivalents, to copy. Display updates pause only while text is selected to preserve copying; simply focusing the log does not freeze updates. Clear the selection or click away to catch up.

## If, elif and else

**Cost:** one tick for each reached `if`/`elif` decision, plus condition-expression costs.

Conditions must evaluate to booleans. Exactly one matching branch executes; unselected bodies are not evaluated. `else` is optional; nested blocks and multiple `elif` branches work.

```python
distance = 40
if distance < 30:
    fire(1)
elif distance < 75:
    print("medium range")
else:
    forward(10)
```

## Switch and case

**Cost:** two ticks for dispatch plus evaluation of the switch expression. No per-case charge.

The expression is evaluated once. Only the first matching case executes, with no fallthrough or required `break`. Case labels are constant scalar values/simple constant expressions. Duplicate determinable values are validation errors. `default` is optional.

```python
scan = Scanner(position=0)
if scan.status == "success":
    switch scan.type:
        case "tank":
            print("tank detected")
        case "wall":
            print("obstacle detected")
        case null:
            print("empty scan")
        default:
            print("unknown type")
```

## While loops and truthiness

**Syntax:** `while condition:` followed by a four-space-indented body.

**Cost:** one tick plus expression costs **each time the condition is tested**, including the final false test. The backward jump costs zero; body operations retain their normal costs.

The condition is evaluated before the first iteration and again after every body execution. Falsey values are:

| Value | Falsey example |
| --- | --- |
| Boolean false | `false` |
| Null | `null` |
| Numeric zero | `0`, `0.0` |
| Empty string | `""` |
| Empty array/list | `[]` |
| Empty dictionary | `{}` |

Other supported values are truthy, including negative numbers, nonempty strings, `[false]` and dictionaries with entries. An undefined variable is still an error.

This truthiness conversion belongs to **while**. Existing `if`, `and`, `or` and `not` remain strict booleans, and `wait_for` has its separate readiness rule.

```python
remaining = 3
while remaining:
    scan = Scanner(position=4)
    print(scan)
    remaining = remaining - 1
print("finished")
```

Loops may contain nested loops, branches, scanner calls and explicit waits. A scanner condition acquires once per reached test, not repeatedly while suspended. CPU exhaustion yields so other threads can run and change shared conditions.

Movement/fire calls inside loops remain submissions. They can fill device queues. This example waits by polling real completion:

```python
move = forward(10)
if move.status == "success":
    state = command_status(move.commandId)
    pending = state.state == "accepted" or state.state == "queued" or state.state == "running"
    while pending:
        clock = get_clock()
        wait_for_clock(clock.time + 0.1)
        state = command_status(move.commandId)
        pending = state.state == "accepted" or state.state == "queued" or state.state == "running"
    print(state.state)
```

Stop, destruction, reset and safety limits terminate loops. `while true` is not permitted to monopolize the server. There is no `break`, `continue`, `for` or `while ... else` syntax yet.

## Threads and shared variables

```text
with thread(1):
    # first instruction stream

with thread(8):
    # eighth instruction stream; requires an eight-core or larger chassis
```

Thread blocks must be top-level, unique literal integer IDs within chassis capacity. They start together in simulation time and run serially within each thread. Top-level statements outside blocks map to thread 1 in source order.

Each thread has its own CPU budget but shares the tank-level variables. At a CPU cycle, threads run in ascending ID order. Conflicting writes are deterministic; later writes win. Ordinary assignments are atomic. During a physical observation/wait inside an expression, other threads may change shared variables before the suspended expression finishes.

This example works on default Rattler, but not single-core Boomer:

```python
with thread(1):
    observation = Scanner(position=0)

with thread(8):
    wait_for(observation)
    if observation.status == "success":
        print(observation.detections)
```

A waiting/finished thread does not stop other streams or device work. Variables belong to one tank's run and cannot leak to another tank/program. Stop, errors, replacement, destruction and reset clear the environment. Completed values remain private until Stop/replacement/reset.

## Safety limits and unsupported features

| Limit | Current value |
| --- | ---: |
| Source size | 16,384 bytes |
| Source lines | 400 |
| Source statements | 128; loop iterations do not add source statements |
| Compiled instructions | 512 |
| Block nesting | 12 levels |
| Expression nesting | 32 levels |
| Tokens/line | 512 |
| Array/dictionary items | 64 |
| Program variables | 128 |
| Retained scanner snapshots | Latest 128; total scans do not stop the program |
| Retained IDE output | Latest 256 entries; older entries roll out |
| Emitted logs/tank/CPU cycle | Up to 64, including an omission notice when rate-limited |
| Retained terminal command history | Latest 512, plus all active/queued work |
| Hard source-operation cap/thread/cycle | 512 |
| Program duration | 180 simulation seconds |
| Physical instruction timeout | Bounded, up to 90 seconds; depends on operation |
| Movement/turn stuck detection | 3 seconds without meaningful progress |
| Distance tolerance | 0.12 studs |
| Angular tolerance | 0.8° |

Temporary Rattler-damage immobilization can pause movement/turn progress expectations for bounded grace time; it does not silently complete the command. Overall program limits still apply.

Not implemented: function values/closures, imports, arbitrary Luau, `for`, `break`, `continue`, locks/events, automatic targeting/tracking, future smart-scanner velocity fields, or general-purpose language features beyond the commands and syntax documented here.

Tuning values come from `src/shared/BWChassis.luau`, `BWConfig.luau`, `ScannerConfig.luau` and tank definitions. The implementation and automated tests remain the authority if these values change.

## Component-backed vehicle configuration

Vehicle assemblies install independently configured chassis, drivetrain, mobility, turret, weapon, sensor, computer and bus components. Drivetrain determines propulsion; mobility determines steering/pivot behavior. The same BW commands and costs apply to both. Model names do not decide capabilities. Default Boomer/Rattler tuning is unchanged, apart from enabling persistent tracked steering. The existing development hardware selector remains available; its tier selects a registered computer component and its bus allocations reserve device performance.

There is no new upgrade UI. See [VEHICLE_COMPONENTS.md](VEHICLE_COMPONENTS.md) for the technical catalog/assembly reference and server-side configuration examples. Chassis mass/torque force calculations remain outside the current kinematic simulation.

Current test loadouts intentionally swap guns: **Boomer = Gatling**, **Rattler = cannon**. Recoil/jackhammer movement, turret kicks, heat limits, trajectory, damage and visual effects follow the installed weapon. Chassis/mobility/computer/bus allocations stay unchanged, so the Gatling on Boomer's shared20% weapon allocation fires more slowly than on Rattler's former dedicated weapon bus.


## User-defined functions

Define reusable code with `function name(parameters):` and four-space indentation. Calls and identifiers remain case-sensitive. Definitions are top-level, may appear after their calls, and do not run until called. Built-in names cannot be redefined. Calls accept positional arguments only, with exact arity. Functions can call themselves or each other and can be used in expressions, conditions, command arguments, and return expressions.

```python
function advance(const distance):
    return forward(distance)

function twice(const n):
    return n * 2

move = advance(twice(10))
print(move.status)
```

Movement commands still return **acceptance**, not physical completion. Wrapping a command in a function does not wait for the device or bypass its queue. `return expression` exits immediately; `return` and falling off the body return `null`. False, zero and empty strings are preserved as return values.

### Parameters and scope

Numbers, strings, booleans and null are copied. Ordinary parameters are mutable local bindings; passing a literal or compile-time constant to one is valid. Dictionaries and arrays preserve object identity. Rebinding a parameter changes only the local binding; property/element writes change the caller's object. Arrays use in-bounds zero-based writes, without append/resize methods. Object literals accept quoted or identifier keys.

```python
function mark(location):
    location.done = true
    location = {done: false}  # Only rebinds the local parameter

position = {x: 3, y: 12}
mark(position)
print(position.done)  # true
```

Every invocation has independent parameters and locals. Every name assigned anywhere in a function is local throughout that function (reads before initialization fail). Other reads resolve to shared top-level variables. Parameters may shadow top-level variables/constants; local value names may shadow user-function names, but call syntax still resolves to the statically registered function. Built-ins cannot be shadowed. Functions are not values: no closures, nested definitions, dynamic function dispatch or global-write declaration. Return a value to publish it through a top-level shared assignment. `wait_for()` and `variable_has_changed()` preserve identity for both local bindings and shared globals; local versions/observations belong to each invocation.

Existing `CONST` remains compile-time, scalar-only and zero-cost. Lowercase `const name = expression` is an equivalent declaration spelling. Define compile-time constants outside functions; `const` in a parameter list is a different feature and may qualify runtime values, including objects.

### Const parameters and aliases

`function inspect(const target):` prohibits rebinding `target` and mutation anywhere reachable through an object/array reference. References derived through fields, indexing, assignments, returned aliases, or nested calls remain protected during the invocation. A mutable reference can be passed to a const parameter. A const reference can be forwarded to another const parameter. A const **scalar** can be copied into a mutable parameter; a const **object/array** cannot.

The compiler rejects const/mutable arguments that may share the same object, including ancestor/child aliases, even if the function happens not to mutate that particular object. Caller-owned objects are not permanently frozen: after a const function returns, the caller may mutate its original reference.

```python
function range_squared(const observation):
    return observation.distance * observation.distance

observation = {distance: 20}
squared = range_squared(observation)
observation.distance = 30  # Valid after the call
```

Compile-time safety is deliberately conservative. Allocation-site points-to sets are merged across assignments, branches, loops, calls and recursion. Ambiguous dynamic fields, unknown scalar-versus-reference types, and rebinding/mixed call patterns may be rejected even when a particular execution would be safe. A function used with many different object layouts may need separation into more specific helpers. Uncalled functions are validated too; unknown parameters are not assumed to be scalars. With multiple declared threads, a const reference that may alias shared top-level storage is rejected because another thread could mutate it while the call waits. Independent function-local storage and shared scalar copies remain usable. This is a compile-time rejection policy, not a promise to allow every safe dynamic program.

There is no existing public `clone()` API or collection mutation-method API in BW, so neither is added here. Creating a new object from proven scalar fields gives independent mutable storage; simply assigning an existing nested object preserves its alias. General cyclic deep copying is not provided.

### Stacks, scheduling and CPU cost

Each thread has its own resumable call stack. Calls can wait for scanners, clocks, shared variables or CPU credit while other threads and devices continue. Recursive calls have independent bindings. Functions use the same compiled instruction executor as top-level code.

The server setting `BWConfig.MaxCallDepthPerThread` defaults to **50**. Top-level execution does **not** count as a function frame. Total live function frames are bounded by `MaxCallDepthPerThread × installed computer thread capacity` (50/100/200/400/800 for Bunny/Dual/Quad/Octa/Hexadeca). A stack overflow reports the function/thread/line, fails that thread and cancels its device work; other threads can finish. Ordinary language/runtime errors retain the existing whole-program stop behavior. Stop, replacement, destruction and reset clear every suspended frame and active input.

| Executed operation | CPU ticks |
|---|---:|
| Function call / return | 0 |
| Const parameter initialization / read | 0 |
| Mutable parameter initialization | Existing write cost: 0.2 |
| Mutable parameter or local read | Existing read cost: 0.1 |
| Mutable binding/property write | Existing write cost: 0.2 |
| Property/index access | Existing access cost: 0.1, plus evaluated base/index reads |
| Arithmetic | Existing cost: 0.2 |
| Object/array literal allocation | Existing allocation cost: 0; contained expressions retain their costs |

These are current defaults from `BWChassis.Costs`, not a second set of tuning values. Calls do not duplicate argument charges. A compile-time constant argument costs zero to read, but initializing a **mutable** parameter still costs a write. Debug-only printing retains its existing cost waiver; a user function invoked inside print is gameplay work and pays its normal executed costs. Uncalled functions and unexecuted branches cost nothing. Free calls/returns still count against the bounded scheduler dispatch limit.

```python
function inefficient(distance):
    distance = distance + 10
    forward(distance)

function efficient(const distance):
    forward(distance + 10)
```

At current rates, `inefficient(5)` costs two reads, two writes, arithmetic and the forward submission: **1.8 ticks**. `efficient(5)` costs arithmetic and the same submission: **1.2 ticks**. Both remain subject to normal device availability and queue limits. The IDE can log a nonintrusive tip when an inferred scalar parameter is never reassigned; it never rewrites the source.

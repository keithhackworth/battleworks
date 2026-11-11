-- Player-facing reference. Costs, hardware and limits come from runtime configuration.
local Hardware=require(script.Parent.BWChassis)
local Limits=require(script.Parent.BWConfig)
local Scanner=require(script.Parent.ScannerConfig)
local Tanks=require(script.Parent.TankDefinitions)
local Catalog=require(script.Parent.ComponentCatalog)
local Handbook={}
local function number(n) return string.format("%g",n) end
local function command(name,signature,category,inputs,behavior,returns,device)
 return {name=name,signature=signature,cost=Hardware.Costs[category],inputs=inputs,behavior=behavior,returns=returns,device=device}
end
function Handbook.commands()
 local commands={}
 local function add(...) table.insert(commands,command(...)) end
 local accepted='A standard result: {status: "success", reason: null, commandId: number}. Success means accepted, not finished. Failure: {status: "fail", reason: code}. Inspect command_status(commandId) later.'
 for _,name in {"forward","back"} do
  add(name,name.."(studs, best_effort=true)\n"..name.."()",name,
   "Optional studs: finite number from 0 to "..number(Limits.MaxDistance).."; expressions are allowed. Omit studs for continuous driving.",
   (if name=="forward" then "Drive forward" else "Reverse").." for the actual requested distance. Installed mobility honors persistent steering; finite arcs count signed forward travel along the changing heading, excluding lateral drift and wheel spin. Real recoil along the commanded direction counts. Without a distance, drive continuously until replaced/stopped or lifecycle timeout. Both forms return immediately after submission. Walls can prevent completion. No teleporting.",accepted,"drivetrain")
 end
 for _,name in {"steer_left","steer_right"} do
  add(name,name.."(degrees, best_effort=true)",name,
   "degrees: finite number 0..180, clamped to the installed mobility steering limit (tracks use a 45-degree control range; wheels approximately "..number(math.deg(Catalog["mobility.wheels"].Properties.MaxSteer)).." degrees). No to= argument.",
   "Set an absolute steering target "..(if name=="steer_left" then "left" else "right").." of center, persisting until changed. Repeated calls do not accumulate. Immediate updates bypass queues. Wheeled mobility positions front wheels through existing smoothing; tracked mobility changes relative tread intent while driving. steer_right(20) sets steering; turn_right(20) changes heading. Unsupported only when installed mobility lacks steering: fail / unsupportedDrivetrain. High-level turns temporarily own actual steering, then the saved target resumes.",
   'Standard result with commandId and steeringDegrees (positive left, negative right). The setpoint command completes immediately, not when wheels physically finish moving. Positive is left and negative is right for both mobility types.',"drivetrain")
 end
 add("steer_center","steer_center()","steer_center","No arguments. Installed mobility must support steering.",
  "Set the persistent steering target to straight ahead without interrupting movement. Wheels use existing smoothing; tracks return to equal tread intent. Installed mobility without steering returns unsupportedDrivetrain.",
  'Standard result with commandId and steeringDegrees: 0; status success means the wheel target was accepted.',"drivetrain")
 add("stop","stop()","stop","No arguments. Both drivetrain types.",
  "Cancel active and queued drivetrain work and release throttle immediately. Preserve steering target, actual velocity and recoil; normal coasting/braking handles physical stopping. Other devices continue. Stop is accepted at zero drive allocation for safety, but requires an installed drivetrain.",
  'Standard result with commandId. Stop command completes immediately; cancelled movement commands report commandCancelled.',"drivetrain")
 for _,name in {"turn_left","turn_right","turret_left","turret_right"} do
  local turret=name:sub(1,6)=="turret"
  local left=name:find("left",1,true)~=nil
  add(name,name.."(degrees, best_effort=true)\n"..name.."(to=heading, best_effort=true)",name,
   "Choose ONE: relative degrees from 0 to "..number(Limits.MaxRelativeAngle)..", OR to=world heading from -"..number(Limits.MaxAbsoluteAngle).." to "..number(Limits.MaxAbsoluteAngle).." (normalized modulo 360). Finite numbers/expressions only.",
   "Rotate "..(if turret then "the turret" else "the chassis")..(if left then " counterclockwise (left)." else " clockwise (right).").." Relative rotation starts from the actual heading when this device begins the command, including full revolutions and crossing north. Absolute turns honor the chosen direction even when it takes the longer path. to=360 is north; use a relative 360 for a full revolution. World headings: 0 north, 90 east, 180 south, 270 west; independent of camera"..(if turret then " and chassis orientation. Recoil affects actual barrel aim." else ". Boomer can pivot; Rattler must drive a curved car-style path to turn, and cannot steer in the air."),accepted,if turret then "turret" else "drivetrain")
 end
 add("fire","fire(best_effort=true)\nfire(seconds, best_effort=true)","fire",
  "No duration: one logical weapon activation. Or seconds: finite number from 0 to "..number(Limits.MaxFireSeconds)..". fire(0) fires nothing.",
  "Submit a weapon operation. A timed command holds the normal trigger for that duration, respecting reload, preparation, heat and cooldown. It does not guarantee a hit or bypass restrictions. CPU cost is paid once per submission, not per bullet. The thread continues while the weapon works.",accepted,"weapon")
 add("Scanner","Scanner(angle, best_effort=true)\nScanner(position=index, best_effort=true)","Scanner",
  "Choose ONE input: angle in degrees (0, 45, 90, 135, 180, 225, 270 or 315, normalized modulo 360), OR position=index with an integer 0..7. Positions map 0->0 degrees, 1->45, 2->90, 3->135, 4->180, 5->225, 6->270, 7->315. Scanner(position=4) equals Scanner(180). Expressions are allowed. Do not provide both angle and position. 0 degrees is chassis-forward, 90 right, 180 back, 270 left.",
  "Submit to that physical sensor, then suspend ONLY this thread until it acquires a snapshot. Other threads and devices continue. Queue rejection returns immediately. Finds all visible tanks/walls in the cone, nearest first; cannot see through walls or tanks. Each sensor has its own queue and cooldown. Every completed sensor retains its own light event, so simultaneous scans cannot overwrite other lenses.",
  'Success: {status: "success", reason: null, sensor, timestamp, range, count, detections}. detections is an immutable zero-indexed array of immutable dictionaries. Empty space is success with count=0 and an empty list. Failure: {status: "fail", reason: code, sensor}. See Radar tab for every field.',"sensor0 ... sensor315")
 add("print","print(value)","print",
  "One value: number, string, boolean, null, array or dictionary; expressions are allowed. No best_effort argument.",
  "Write a readable value to this tank's private IDE history, with source line, simulation timestamp and thread. Printing and automatic logs cost ZERO ticks, including debug-only variable/property reads and arithmetic used to display a value. An expression containing a real call such as Scanner(), forward(), command_status() or a wait executes normally and retains its full expression cost, so print cannot bypass gameplay costs. Saving a print result in a variable still pays the assignment cost. Generic formatting is bounded at "..number(Limits.MaxOutputBytes).." bytes; automatic scanner diagnostics list every detection separately. Log history rolls instead of ending the program. Excess output is rate-limited with an explicit notice, not a fatal error.",
  '{status: "success", reason: null}. Explicit print(scan) is an additional entry after the automatic scan diagnostic.',"none")
 add("get_facing_direction","get_facing_direction()","get_facing_direction","No arguments.",
  "Read the current authoritative CHASSIS compass heading: 0 north, 90 east, 180 south, 270 west, normalized to [0,360). This is the tank body's actual heading, not turret aim, requested turn target or camera orientation. Returns immediately without operating a device.",
  '{status: "success", reason: null, world_direction: number}. Use facing.world_direction for the number; the result itself is a dictionary. Each scan hit also includes world_direction for direct use with turn_right(to=...) or turret_right(to=...).',"none")
 add("get_clock","get_clock()","get_clock","No arguments.",
  "Read authoritative ARENA simulation time in seconds. It can already be greater than zero when a program starts. It is independent of rendering frame rate and CPU throughput.",
  '{status: "success", reason: null, time: number}. Use get_clock().time or save the result and read clock.time; the result is not a bare number.',"none")
 add("wait_for_clock","wait_for_clock(targetTime)","sync",
  "targetTime: finite absolute arena simulation time in seconds, usually clock.time + delay.",
  "Suspend only this thread until the first CPU cycle at/after targetTime. A time already reached returns immediately. Other streams and devices keep operating. Waiting spends no repeated CPU ticks.",
  '{status: "success", reason: null}; invalid computed arguments return fail / invalidArgument.',"none")
 add("wait_for","wait_for(variable)","sync",
  "An actual variable NAME, not a literal/value/expression. It may not have been assigned yet.",
  "Wait for that shared variable to contain a ready value: anything except missing, false or null. Zero, an empty string and dictionaries ARE ready. An already-ready value returns immediately. This waits for readiness, not the next assignment. It also observes the variable's current version for this thread.",
  '{status: "success", reason: null, value: the shared value, version: assignment version}. Missing values wait rather than raise an undefined-variable error.',"none")
 add("variable_has_changed","variable_has_changed(variable)","sync",
  "An actual variable NAME. Each thread keeps its own last-observed version, initially zero.",
  "Check whether this variable has been assigned since THIS thread last checked/observed it. Every assignment increments its version, even assigning the same value. This call updates the thread's observed version. Property writes increment the named root variable's version; aliases do not create extra version notifications.",
  '{status: "success", reason: null, changed: boolean, version: number}. Test result.changed, not the dictionary itself. This does not wait.',"none")
 add("clear_queue","clear_queue(device)","queue",
  'device: string such as "drivetrain", "turret", "weapon" or "sensor45".',
  "Cancel all PENDING commands for this device without interrupting its active operation. Any thread may manage any installed device. A cancelled pending scan wakes its waiting thread with commandCancelled.",
  '{status: "success", reason: null}, or fail / deviceUnavailable for an unknown/uninstalled device.',"named device")
 add("abort_command","abort_command(device)","queue",
  'device: string such as "drivetrain", "turret", "weapon" or "sensor45".',
  "Cancel the ACTIVE command only. Pending commands remain; the oldest can begin at the next device update in the fixed simulation. Aborting a weapon cancels an unreleased preparation, not an already launched projectile. Physical momentum remains. To cancel all work, clear_queue(device) and then abort_command(device).",
  '{status: "success", reason: null}, or fail / deviceUnavailable. Aborting an idle installed device succeeds.',"named device")
 add("command_status","command_status(commandId)","queue",
  "commandId: number returned by a successful movement, turn or fire submission. IDs belong to this program run.",
  "Inspect accepted work without waiting. A successful QUERY does not mean the physical command succeeded. Check result.state and result.completionReason.",
  '{status: "success", reason: null, commandId, device, state, completionReason}. States: accepted, queued, running, completed, failed, cancelled. completionReason is null while pending/running and after normal completion; failed/cancelled commands carry a reason such as stuck or commandTimedOut. Unknown or expired ID: fail / invalidArgument. The most recent completed/failed/cancelled commands are retained in a rolling history; active and queued work is never evicted.',"none")
 return commands
end
local function renderCommands(commands,names)
 local blocks={}
 for _,name in names do
  for _,entry in commands do if entry.name==name then
   table.insert(blocks,"COMMAND: "..entry.name.."\n"..entry.signature.."\nBase CPU cost: "..number(entry.cost).." ticks • Device: "..entry.device.."\n\nINPUT\n"..entry.inputs.."\n\nHOW IT WORKS\n"..entry.behavior.."\n\nRETURNS\n"..entry.returns)
  end end
 end
 return table.concat(blocks,"\n\n────────────────────────────\n\n")
end
function Handbook.sections()
 local commands=Handbook.commands()
 local sections={}
 local function add(id,label,title,body) table.insert(sections,{id=id,label=label,title=title,body=body}) end
 local tiers={}
 for _,name in {"Bunny","Dual","Quad","Octa","Hexadeca"} do
  local t=Hardware.Tiers[name]
  table.insert(tiers,string.format("%s: %d bus/thread%s, %g ticks/cycle/thread, %d pending/device",name,t.threads,if t.threads==1 then "" else "s",t.ticks,t.queue))
 end
 add("cpu","CPU & ticks","Start here: cycles, ticks and time",string.format([[BW is a small language for controlling your existing tank. Commands are case-sensitive; write one statement per line and indent blocks with four spaces. This reference stays open independently of execution: reading it does NOT pause a running program.

A SIMULATION SECOND measures arena time. The server simulates tanks at its fixed physics step, not the rendering frame rate.

A CPU CYCLE replenishes each thread's instruction budget. Currently there are %g cycles per simulation second: one every %g seconds.

A CPU TICK is a gameplay cost, not a fixed duration or real processor MHz. Commands and expression operations spend ticks from the calling thread's budget. Several commands can run in the SAME cycle. If the next instruction cannot fit, it waits for sufficient credit; it is not partially replayed. Unused credit normally carries up to %d cycles. Large instructions can reserve bounded extra credit, up to %g ticks. Actual charges follow only the operations that execute.

%s

Example: Bunny gets %g ticks × %g cycles = %g ticks/second. This is throughput, not a fixed number of seconds per command.

Threads receive SEPARATE CPU budgets. One busy/waiting thread cannot spend another thread's ticks. Source instructions execute in ascending thread order in each cycle, so conflicting shared writes are deterministic; later writes win. Ordinary assignments are atomic. A physical observation or explicit wait may suspend expression evaluation, then resume without repeating prior side effects.

CPU TIME is different from DEVICE TIME. forward(100) costs %g tick to SUBMIT, then the drivetrain moves independently without spending ticks every step. Waiting in a queue also does not spend repeated CPU ticks. Reading the clock, printing values and automatic logging cost zero. Storing a result or executing real device/query/wait calls inside print still pays its normal cost.

Safety still applies: at most %d source operations/thread/cycle, %g simulated seconds/program, %d source statements and %d lines. Zero-cost operations cannot hang the server.]],
 Hardware.CyclesPerSecond,1/Hardware.CyclesPerSecond,Hardware.CreditCycles,Hardware.MaxInstructionCredit,table.concat(tiers,"\n"),Hardware.Tiers.Bunny.ticks,Hardware.CyclesPerSecond,Hardware.Tiers.Bunny.ticks*Hardware.CyclesPerSecond,
 Hardware.Costs.forward,Hardware.MaxOperationsPerCycle,Limits.MaxProgramSeconds,Limits.MaxInstructions,Limits.MaxLines))
 add("buses","Buses & busy","Buses, device performance, queues and physical time",[[Each chassis bus has TWO independent roles:
1. Run one BW instruction thread with its own CPU budget.
2. Supply reserved performance allocations to its installed devices.

A device belongs to exactly one bus. A bus can host several devices, but their configured allocation percentages must total no more than 100%. Idle devices do not donate their reserved allocation. Multiple devices on one bus CAN operate at the same time; they do not take turns using the bus. ANY thread can issue a command to ANY device, including one on a different bus.

Effective performance = 1 - (1 - allocation/100)^2
25% allocation -> 43.75% performance
50% -> 75%; 75% -> 93.75%; 100% -> 100%
0% -> deviceDisabled; the device cannot operate.

The drivetrain's speed cap, turret rotation rate and weapon preparation/recharge timing depend on performance. Acceleration, recoil, steering geometry, collisions, projectile speed and damage remain normal tank physics. Lower performance makes weapon intervals/preparation LONGER. Radar RANGE currently stays at 150 studs at 100% distance effectiveness, independently of bus allocation; acquisition time still depends on performance. Future equipment configuration can change radar hardware range.

Edit reservations in Hardware / threads while the program is stopped. First line is chassis name; following lines are: device bus allocationPercent. The server validates configuration too. Each tank starts with its configured chassis profile (listed below); the development hardware editor can override it. Shared allocations affect physical device performance as well as acquisition/preparation times.

WHAT DOES BUSY MEAN?
A device is busy while it has an active command. A drive remains busy while covering its distance/turn or waiting for genuine progress. A weapon may be busy during preparation, reload, held fire or waiting for its committed shot to release. A scanner is busy during acquisition/cooldown scheduling. Being busy is not a CPU charge every frame.

Every device has ONE active command plus a bounded FIFO pending queue. Queue depth comes from chassis tier and excludes the active command. Finite drivetrain forward/back/chassis turns share one pipeline; continuous forward()/back() replaces active/queued drive work. Finite navigation replaces an active continuous drive. stop() cancels all drive work. Steering setpoints bypass the queue, retain one last-written target and cost 1 tick per issue. All new movement/steering/stop commands cost 1 tick, with no repeated operating ticks. Continuous drive keeps BW running after threads finish, until stopped/cancelled or the normal program timeout. Ascending thread order gives deterministic last-submission wins for replacements; finite-versus-finite work remains FIFO. Drivetrain allocation and immobilization still apply; turret and weapon have separate pipelines. Each physical sensor has its OWN pipeline and cooldown.

Idle device: accepted command starts.
Busy device with room: command joins the queue.
Busy device with a full queue: fail / deviceQueueFull, immediately. Existing work is not overwritten and the thread does not wait for space. A full-queue rejection still spends the command submission ticks.

Device commands capture their starting pose when they BEGIN, not while waiting in the queue. Different devices work concurrently. A successful submission is NOT proof the physical operation will finish: it can later fail due to a wall, timeout, cancellation or destruction.

There is no fixed seconds-per-movement-command: distance, heading, terrain, acceleration, recoil and allocation affect actual completion time. Inspect command_status(id). There is no blocking command-completion wait; a while loop can inspect command_status and use clock waits between polls.

A thread finishing does not stop other threads or devices. The whole program completes after all threads finish and accepted device work drains. Stop/destruction/reset cancel operations and release inputs, preserving real inertia and already released projectiles.]])
 add("movement","Movement","Drivetrain commands",renderCommands(commands,{"forward","back","steer_left","steer_right","steer_center","stop","turn_left","turn_right"})..[[

RATTLER: CONTINUOUS CIRCLE
steer_right(20)
forward()

CHANGE CURVATURE WITHOUT STOPPING
clock = get_clock()
wait_for_clock(clock.time + 3)
steer_left(20)

STRAIGHTEN, THEN STOP
steer_center()
clock = get_clock()
wait_for_clock(clock.time + 3)
stop()

steer_right(20) sets steering: wheel angle for wheels, relative tread intent for tracks. turn_right(20) changes chassis heading. Capabilities come from installed components, not the model name. forward(50) travels a finite distance; forward() drives until replaced/stopped or lifecycle timeout. An issuing thread can finish while its continuous drive remains active. The same physics, collision, coasting, bus performance, airborne restrictions and damage filters still apply.]])
 add("turret","Turret","Turret commands",renderCommands(commands,{"turret_left","turret_right"}))
 add("weapon","Weapons","Firing and weapon timing",renderCommands(commands,{"fire"})..string.format([[

CURRENT FULL-PERFORMANCE TIMING
Cannon (currently Rattler): %g seconds cannon preparation and %g seconds firing interval. Lower allocation divides these durations by effective performance. It still swells, recoils and releases a shell along the actual barrel direction.

Gatling (currently Boomer): %g seconds firing interval, at most %g seconds continuous fire, then %g seconds mandatory overheat cooldown. Lower allocation lengthens the shot interval; it does not increase projectile speed or bypass heat. Releasing and tapping does not reset accumulated heat.

fire(2) holds the trigger for 2 simulated seconds; it does not mean two shots. Preparation/cooldown can delay activation, and active commands have bounded safety timeouts. Neither tank's recoil, movement or weapon mechanics is replaced by BW.]],Catalog["weapon.cannon"].Properties.FireWindup,Catalog["weapon.cannon"].Properties.Cooldown,Catalog["weapon.gatling"].Properties.Cooldown,Catalog["weapon.gatling"].Properties.MaxBurst,Catalog["weapon.gatling"].Properties.OverheatCooldown))
 add("radar","Radar","Scanner input, timing and all returned fields",renderCommands(commands,{"Scanner"})..string.format([[

PHYSICAL TIME (separate from CPU cost)
Default acquisition: %g seconds / effective device performance.
Each sensor cooldown: %g seconds. Queued acquisition honors that sensor's cooldown; a cooling sensor does not block a different sensor. There is also a separate shared query-work safety budget; scannerBusy means that budget/geometry guard, not a shared sensor cooldown. Acquisition priority rotates deterministically to avoid repeatedly favoring the same sensors. Acquisition occurs on a fixed simulation step; the issuing thread resumes on a CPU cycle, so delivery can be later than the recorded timestamp.
Default cone: %g degrees total (±%g). Fixed mounts are 45 degrees apart, leaving angular gaps between narrow cones; a nearby object outside every cone can produce zero detections. Scan activity lights do not guarantee a detected object.
Default distance: %g studs at %g%% distance effectiveness. Hardware range/distancePercent can be configured later; bus sharing currently does not shorten the range.

SNAPSHOT FIELDS
status: "success" or "fail".
reason: null on success; stable failure code otherwise.
sensor: physical mounting angle in DEGREES, even when called with position=index. Scanner(position=4) reports sensor=180.
timestamp: actual server simulation time of acquisition, NOT submission or the moment you print it.
range: effective distance of this radar, in studs.
count: number of visible detections.
detections: immutable nearest-first array. Access its first entry with detections[0], not [1].

EACH DETECTION
.type: "tank" or "wall" (solid obstacle).
.distance: 3D studs from scanner origin to visible surface.
.relative_direction: precise chassis-relative bearing to the observed surface, not necessarily the requested angle.
.world_direction: world compass bearing to that SAME observed surface: 0 north, 90 east, 180 south, 270 west. Use directly in to= heading commands. Both bearings are captured at acquisition, even while the chassis is turning.
.player: unique owner.tank#id identity for tanks; null for walls. Unowned tanks use a stable AI/tank ID.
.relation: "enemy" or "teammate" for tanks; null for walls.
.point: immutable {x, y, z} in WORLD coordinates of the visible hit surface, not necessarily the target center.

All entries belong to the same acquisition. The origin is tank position + %g studs world Y. The nearest entry is also exposed through top-level type, distance, relative_direction, world_direction, player, relation and point for existing programs. If nothing is visible, those convenience fields are null and count=0.

Walls/tanks occlude objects behind them. Smoke, cosmetic parts, your own tank and projectiles are ignored. A partially visible physical body can be detected inside the cone. The bounded geometry safety budget may return scannerBusy; it never silently reports a partial successful list. No velocity, prediction or automatic aiming is supplied.

USAGE
scan = Scanner(0)
if scan.status == "success" and scan.count > 0:
    first = scan.detections[0]
    print(first.player)
    print(first.distance)
    print(first.relative_direction)
    print(first.world_direction)
    turret_right(to=first.world_direction)

Check status before count/detections: failure dictionaries do not contain a successful snapshot. Do not mutate a scan, its detections list or hit points. Use relative_direction for the chassis-relative bearing and world_direction for absolute aiming. The old direction key has been renamed; it is no longer returned. get_facing_direction().world_direction gives your own chassis heading.]],Hardware.AcquisitionSeconds,Scanner.SensorCooldown,Scanner.ConeWidth,Scanner.ConeWidth/2,Scanner.MaxRange,Scanner.DistancePercent,Scanner.OriginHeight))
 add("clock","Facing / clock","Facing, time, shared readiness and assignment versions",renderCommands(commands,{"get_facing_direction","get_clock","wait_for_clock","wait_for","variable_has_changed"}))
 add("queues","Queues & results","Results, status inspection and cancellation",[[ALL CALLS RETURN A DICTIONARY
Success always includes status="success" and reason=null.
Failure includes status="fail" and a stable reason code.
Dictionary properties use result.status or result["status"].

Movement, turret and weapon success means ACCEPTED. Save commandId to inspect its later lifecycle. A scanner waits for the observation instead. A clock call returns .time; a change check returns .changed. These are dictionaries, not bare numbers/booleans.

NORMAL OPERATIONAL FAILURE DOES NOT STOP THE THREAD
Examples: deviceQueueFull, deviceDisabled (0% allocation), deviceUnavailable (not installed), invalidSensor, invalidArgument, sensorCooldown, scannerBusy. An accepted device command can later be stuck, commandTimedOut, executionFailed or commandCancelled. tankDestroyed cancels lifecycle work. deviceDamaged is reserved for future device-specific damage.

You may inspect or ignore a failed submission. Legacy best_effort=true/false is accepted on movement/turn/fire/Scanner, but it does not make asynchronous operational failures fatal. Undefined variables, invalid operand types, immutable-value mutation and other genuine runtime/syntax errors still stop safely with source lines. Stop/reset cannot be bypassed.

]]..renderCommands(commands,{"command_status","clear_queue","abort_command"}))
 local costs={}
 for _,entry in {{"Variable read","read"},{"Assignment / dictionary property write","write"},{"Arithmetic operation","arithmetic"},{"Comparison","comparison"},{"Logical operation","logical"},{"Dictionary / array access","access"},{"if / elif decision","branch"},{"switch dispatch (all cases together)","switch"},{"while condition test (each evaluation)","loop"}} do table.insert(costs,entry[1]..": "..number(Hardware.Costs[entry[2]]).." ticks") end
 add("loops","While loops","while: repeat while a value is truthy",string.format([[SYNTAX
while condition:
    # four-space indented statements
    print("body")

CPU COST
%g tick per condition test, PLUS normal condition-expression costs. The final false test also pays this cost. The backward jump adds no tick charge. Each body statement keeps its normal cost; printing remains free.

HOW IT WORKS
Evaluate condition before the first iteration and again after every body execution. Skip the body if the value is falsey. Otherwise run the body in order and return to the condition. A variable condition is re-read each time; another thread can change it. Nested while, if and switch blocks are supported. An asynchronous Scanner condition waits for one acquisition for that test, without repeating it while waiting.

FALSEY VALUES
false, null, numeric 0, the empty string "", an empty array [] and an empty dictionary {}.
Every other supported value is truthy, including -1, "0", a whitespace string, [false] and a nonempty dictionary. An undefined variable is still an error, not an implicit null. This truthiness rule belongs to while; existing if conditions and and/or/not operators still require booleans. Use comparisons when combining non-boolean values with logical operators. wait_for retains its separate readiness contract.

EXAMPLE: COUNT DOWN
remaining = 3
while remaining:
    print(remaining)
    remaining = remaining - 1
print("finished")

EXAMPLE: SCAN BY SENSOR POSITION
position = 4
remaining = 2
while remaining:
    observation = Scanner(position=position)
    print(observation)
    remaining = remaining - 1

The scanner still returns sensor in degrees and charges its usual submission ticks. A computed invalid position returns invalidSensor; invalid literal positions are rejected before the tank acts. position must be an integer 0..7; it does not wrap like an angle.

PHYSICAL DEVICES AND SAFETY
Submitting forward/fire/turn inside a loop does NOT wait for physical completion: it still submits to bounded device queues, which can become full. Use command_status and wait_for_clock when coordinating physical work. Loops do not block the server: they yield for CPU budget, asynchronous observations or explicit waits. Other threads/devices continue.

Stop, destruction, respawn and reset cancel loops and clear inputs/queued work. The usual %g-second program timeout and hard per-cycle operation cap still apply. Scanner snapshots, logs and completed command histories roll over rather than stopping a busy loop; output is rate-limited with visible omission notices, even for while true. Reading a handbook does not pause the loop. No break, continue, for or while-else syntax is implemented.

RETURNS
while is a statement, not a callable: it returns no result dictionary. When false, execution continues after the indented block.]],Hardware.Costs.loop,Limits.MaxProgramSeconds))
 add("language","Language","Variables, CONST, expressions, branches, threads and costs",[[CONST move = 10
CONST double_move = move * 2
forward(double_move)

CONST declares an immutable number, string, boolean or null during compilation. Its declaration and references cost ZERO runtime ticks and produce no runtime assignment, read or storage. Initializer operators/parentheses and previously declared constants are evaluated at compile time. Commands still pay their usual submission cost; forward(double_move) has exactly the cost of forward(20). Ordinary variables keep their read/write costs; arithmetic outside a CONST initializer still costs ticks.

Names are case-sensitive and program-wide, visible after declaration in textual source order across threads. Prefer declarations at the top. Declarations inside a branch/thread are compile-time, not conditional. No reassignment, duplicate names, mutable-name conflicts, collections, indexing, function calls, runtime dependencies, self/forward/circular references or synchronization variable references are allowed. Compiler errors identify the source line. Built-in and keyword names cannot be constants.

EDITOR
Enter retains indentation and adds four spaces after a block-header colon. Backspace in leading indentation removes one level. Tab/Shift+Tab indent/outdent the current line or selected lines. Shift+Delete removes the entire caret line, including its line break, as one undo step. Undo/Redo buttons and Ctrl/Cmd+Z, Ctrl/Cmd+Y or Ctrl/Cmd+Shift+Z use separate history for each tank.

Paste: align is the default: prepare the insertion indentation, then paste the AI code. Common outer indentation is removed and internal nesting is aligned to your insertion point; existing obsolete code stays in place for you to remove. A multiline paste is one undo operation. Inline whitespace/strings and line endings stay intact. Use Paste: exact when every received whitespace byte must remain unchanged. Run never normalizes source. The compiler still expects four-space indentation; the editor does not fix missing internal nesting or strip Markdown fences.

One statement per line. Names are case-sensitive. Command parameters named studs/degrees/seconds/value in this reference are positional placeholders; use named to=, position= or best_effort= only where shown. # starts a comment outside strings. Blocks use four spaces, not tabs. Variables belong to one tank's program and are shared by all its threads; they do not leak between tanks/runs/resets.

VALUES AND EXPRESSIONS
Numbers (including decimals), quoted strings, true, false, null, arrays and dictionaries. Zero-based arrays: items[0]. String dictionary keys: result.status or result["status"]. Missing dictionary keys return null; invalid array indices are errors. Programmer arrays and dictionaries are mutable references; scanner/result snapshots are immutable. Dictionary equality compares identity; compare fields to compare observations.

Use = for assignment and == for comparison. Arithmetic: + - * / and unary -. Comparisons: == != < <= > >=. Logical: and or not. Parentheses group expressions. Arithmetic has conventional precedence; comparisons bind before not, then and, then or. Conditions/logical operators require booleans; there is no implicit number/string coercion. and/or short-circuit, skipping unused calls and their costs. Division by zero and undefined reads are errors.

DECISIONS
if condition:
    forward(10)
elif other_condition:
    back(5)
else:
    print("neither")

switch value:
    case "tank":
        print("tank")
    case "wall":
        print("wall")
    default:
        print("other")

One matching branch executes. switch evaluates its value once, has no fallthrough and needs no break. Case labels are constant scalars/simple constant expressions. Nested blocks work. while loops are supported (see While loops tab). User functions are supported (Functions tab). for loops, break/continue and automatic targeting are not available yet.

THREADS
with thread(1):
    ready = true
with thread(2):
    wait_for(ready)
    print(ready)

Each block is an independent entry point, not a function. Thread IDs must be literal integers within the selected chassis capacity; Bunny cannot run thread 2. Top-level legacy statements map to thread 1. No extra CPU charge is assigned merely for entering a thread block. A waiting thread does not prevent others from running.

EXPRESSION COSTS (additional to base command cost)
]]..table.concat(costs,"\n")..string.format([[

Literal values and control-flow jumps have no extra charge. Construction of an array/dictionary adds the costs of its evaluated elements, not a separate construction fee. switch has no hidden per-case comparison charges. A single if is cheaper; switch becomes preferable for several alternatives.

EXACT SMALL EXAMPLES UNDER CURRENT COSTS
distance = 10 + 5
  %g arithmetic + %g assignment = %g ticks
forward(distance)
  %g submission + %g variable read = %g ticks
result = forward(10)
  %g submission + %g assignment = %g ticks
if distance < 30:
  %g decision + %g read + %g comparison = %g ticks

Command reference costs are BASE costs. Argument expressions, property reads and assignment normally cost extra. Exception: print/debug output and its pure display expressions are free. Expressions containing real device/query/wait calls inside print keep their full normal costs; assigning the returned success dictionary still pays a write cost. Waiting/operating device time is not charged repeatedly.]],Hardware.Costs.arithmetic,Hardware.Costs.write,Hardware.Costs.arithmetic+Hardware.Costs.write,Hardware.Costs.forward,Hardware.Costs.read,Hardware.Costs.forward+Hardware.Costs.read,Hardware.Costs.forward,Hardware.Costs.write,Hardware.Costs.forward+Hardware.Costs.write,Hardware.Costs.branch,Hardware.Costs.read,Hardware.Costs.comparison,Hardware.Costs.branch+Hardware.Costs.read+Hardware.Costs.comparison))
 add("examples","Output & examples","Output, practical programs and execution logs",renderCommands(commands,{"print"}).."\n\n"..[[MOVE WHILE SCANNING (even on Bunny)
move = forward(20)
turn = turn_right(90)
scan = Scanner(0)
print(scan)

Drive starts; the turn queues behind it; the scanner acquires while the drivetrain works. The tank may still be accelerating when observed. A scan only blocks its issuing thread for the observation, not the device work already submitted.

DELAY AND INSPECT COMPLETION
move = forward(10)
clock = get_clock()
wait_for_clock(clock.time + 2)
state = command_status(move.commandId)
if state.status == "success":
    print(state.state)

Two seconds is an explicit delay, not a guarantee of movement completion. Check the state. Use while for repeated polling, preferably with a small clock wait between polls. There is no wait_for_command operation.

SHARED SCAN (Dual or higher, sensor0 installed)
with thread(1):
    target = Scanner(0)
with thread(2):
    wait_for(target)
    if target.status == "success":
        print(target.detections)

QUEUE MANAGEMENT
clear_queue("drivetrain")
abort_command("drivetrain")

COST OF A WAIT
clock = get_clock()
wait_for_clock(clock.time + 1)

The initiating calls/expressions cost ticks once. The one-second wait does not continuously spend instruction ticks; the turret, drive or weapon can keep operating during it.

READING THE EXECUTION LOG
Command • L3 • t=5.833 • T1 • forward -> ...
Command = general submission/result.
L3 = source line 3.
t = authoritative simulation seconds for that event.
T1 = thread 1.
Scanner(0) = an actual sensor observation; its time is acquisition time.
print = explicit programmer output.
Indexed [0], [1], ... lines below a scan are detections in that same snapshot, nearest first.

Open Hardware / threads for thread state/current line/tick totals, device allocation, active command, FIFO queue and recent failures. "waiting" may mean CPU budget, clock, variable readiness or scan acquisition; it does not automatically mean a broken tank. Each sensor row also shows successful/failed acquisition totals and its latest object count or failure code/time. Your conditional print only runs on successful nonempty scans; use these rows (or print the scan outside that guard) to distinguish empty space from scannerBusy.

The execution log is selectable and read-only. Long retained history is split into bounded pages; Older opens earlier entries and Latest follows new output. The log header shows server prints executed, print events received by this client and the current page. Each thread row also shows loop-test and print counts, so you can distinguish a waiting scan from skipped print code or a display/transport issue. Click it and use Ctrl+A / Ctrl+C (or platform equivalents) to copy. Updates pause only while text is actually selected, so merely clicking/focusing the log does not freeze it. Clear the selection or click away to catch up. Output history retains the latest 256 entries; older entries roll out. Scan history retains 128 recent snapshots, and terminal command history retains 512 records plus all active/queued work. Excess logging is rate-limited per CPU cycle with an explicit notice; it never makes a valid loop fail. Programs continue running while you read this handbook.

Run closes the IDE and hands control of this tank to BW. Stop cancels its program/devices and returns manual control. You can switch to the other tank and play while this tank's program continues.]])
 add("functions","Functions","Functions, const references, stacks and ticks",string.format([[FUNCTION SYNTAX
function advance(const distance):
    return forward(distance)

function double(const value):
    return value * 2

move = advance(double(10))
print(move.status)

Functions take positional arguments, may be defined after calls, and support recursive/mutually recursive calls. Definitions run only when called. return expression exits immediately; return alone or fallthrough returns null. Calls work in expressions, conditions and arguments. Four spaces per block; definitions must be top-level. Built-in names cannot be replaced; identifiers stay case-sensitive. No function values, nested definitions or closures.

COPY OR REFERENCE?
Scalars (number, string, boolean, null) are copied. Mutable parameters are local bindings and may be reassigned. Arrays and objects keep identity: obj.x = 2 or items[0] = 2 changes caller storage, but obj = {x: 2} only rebinds the parameter. Direct object/array literal arguments are valid. Array writes must be in bounds. Assignments anywhere in a function declare function-local names. Other reads resolve shared top-level variables. Return a value to publish it via a top-level assignment.

CONST PARAMETERS
function inspect(const target):
    return target.distance

No reassignment to target, no mutation through fields, indexing or aliases. Const object references may only be forwarded to const parameters; const scalars may be copied into mutable parameters. Independent mutable objects may be passed alongside protected references, but potential aliases between const/mutable arguments are rejected. Const does not permanently freeze the original caller object after return.

Validation is conservative and compile-time: aliases merge across branches/rebindings/call sites. Unknown object-versus-scalar flows can be rejected. Multithread programs cannot pass potentially shared top-level objects as const references: another thread could modify them during a wait. Prefer function-local storage or scalar observations. Existing BW has no public clone() or append() API; neither is introduced. New objects built from proven scalar fields have independent mutable storage.

STACKS AND SCHEDULING
Each thread has independent call frames, locals and return destinations. Scanner/clock/variable/CPU waits suspend only the calling thread; other devices and threads continue. Default maximum is %d live function frames per thread, excluding top-level execution. Aggregate limit is %d times installed computer thread capacity. The server can configure this depth. Overflow names the function/thread/line, cancels that thread's commands, and lets other threads finish; the final program reports an error. Stop/destruction/reset/replacement clear all frames.

CPU COST
Function calls and returns: 0 ticks.
Const parameter initialization and reads: 0 ticks.
Mutable parameter initialization: normal write cost.
Mutable parameter/local reads and writes: normal variable costs.
Property/index traversal, arithmetic and device submissions retain their usual costs. Collection literal allocation keeps its existing zero cost; element expressions still cost ticks. Current read/write defaults are %g/%g, not 1 tick each. Calls never duplicate argument evaluation. Uncalled functions and unexecuted branches cost nothing. Optional compiler tips suggest const for unmodified scalar parameters without changing code.

function costly(distance):
    distance = distance + 10
    forward(distance)

function efficient(const distance):
    forward(distance + 10)

At current costs, costly(5) is %g ticks; efficient(5) is %g. Both submit asynchronously and preserve normal device queues. A function returning forward(10) returns acceptance, not physical arrival. Use command_status and an explicit clock wait to wait for completion. Infinite/free code is still bounded by scheduler dispatch and program safety limits. Hardware diagnostics show each thread's function, source line and call depth.]],Limits.MaxCallDepthPerThread,Limits.MaxCallDepthPerThread,Hardware.Costs.read,Hardware.Costs.write,2*Hardware.Costs.read+2*Hardware.Costs.write+Hardware.Costs.arithmetic+Hardware.Costs.forward,Hardware.Costs.arithmetic+Hardware.Costs.forward))
 add("physics","Physics","Momentum, traction and command completion",[[BW and manual controls use the same authoritative movement simulation. Drivetrain ratings and bus allocation limit propulsion; they do not cap world velocity from recoil or supplied environmental forces.

On low-grip surfaces, braking/turning take longer. A chassis can rotate while sliding sideways. Off-center collisions or supplied impulses can create yaw momentum. Ground traction does not act in the air; existing recoil hops, gravity and landing behavior remain.

stop() releases driving input and follows ordinary coast/resistance; it does not anchor the tank or erase momentum. Existing partial/reverse throttle can brake. Steering changes still position wheels or request differential tread steering rather than teleporting the chassis to a heading.

Finite forward/back measures signed actual horizontal travel along the requested direction; curved motion follows the changing heading tangent. Sideways/vertical drift and collision penetration corrections do not count. Backward displacement subtracts progress; external forward displacement can help. Turns count actual signed yaw, so an external spin can help or oppose them.

Completion means the requested travel/rotation was achieved, not that the tank is stationary or holding its final position. Residual sliding/spinning may continue. Timeouts, stuck detection, bounded immobilization pauses, best_effort, queues, command results and CPU tick costs retain their existing meaning. A program cannot bypass traction or teleport a tank to finish a command.

The debug speed HUD shows measured world speed against the allocation-limited drive target, rated engine speed, yaw rate and sliding/contact state. Physical surface regions can be configured independently from visible map terrain. The test arena now defaults to IceWind: parked tanks gently drift eastward (about1 stud/sec), with visibly icy ground. Powered grip exceeds the test wind, so driving/reversing can pull away from downwind walls. Uniform wind eases its push as downwind drift builds; it does not clamp faster movement. Rivers, buoyancy and general prop physics remain deferred. The internal force/impulse API is server-only and is not a new BW command.]])
 -- Each command has exactly one detailed home, plus a visible index at the
 -- top of that topic. Registry-only coverage is not enough: render every entry.
 local membership={movement={"forward","back","steer_left","steer_right","steer_center","stop","turn_left","turn_right"},turret={"turret_left","turret_right"},weapon={"fire"},radar={"Scanner"},
  clock={"get_facing_direction","get_clock","wait_for_clock","wait_for","variable_has_changed"},queues={"command_status","clear_queue","abort_command"},examples={"print"}}
 local byName={}; for _,entry in commands do byName[entry.name]=entry end
 local directory={"COMMAND DIRECTORY (choose a topic tab)"}
 for _,section in sections do
  if section.id=="buses" then
   local profiles={"DEFAULT TANK HARDWARE"}
   for _,kind in {"Boomer","Rattler"} do
    local config=Hardware.forTank(kind); local spec=Hardware.Tiers[config.tier]
    table.insert(profiles,string.format("%s: %s • %d cores/buses • %g ticks/cycle/thread • %d pending/device",kind,config.tier,spec.threads,spec.ticks,spec.queue))
   end
   table.insert(profiles,"Boomer's devices share its single bus. Rattler reserves dedicated drivetrain, turret and weapon buses; scanners share its remaining five buses. Radar range stays 150 studs at full distance effectiveness.")
   section.body=table.concat(profiles,"\n").."\n\n"..section.body
  end
  section.commands=membership[section.id] or {}
  if #section.commands>0 then
   local index={"COMMANDS IN THIS SECTION"}
   for _,name in section.commands do
    local entry=byName[name]
    table.insert(index,entry.signature.."\n  Base CPU cost: "..number(entry.cost).." ticks")
   end
   section.body=table.concat(index,"\n\n").."\n\nDETAILED REFERENCE\n────────────────────────────\n\n"..section.body
   table.insert(directory,section.label..": "..table.concat(section.commands,", "))
  end
 end
 sections[1].body=table.concat(directory,"\n").."\n\nCPU CYCLES AND TICKS\n\n"..sections[1].body
 return sections
end
return table.freeze(Handbook)

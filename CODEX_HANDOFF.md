# BattleWorks game and Codex handoff

Last reviewed: 2026-11-04. This document records the implemented prototype, user requirements, development workflow, and unresolved questions for future sessions. Read [README.md](README.md) for player setup and the detailed Android test checklist. Source code is the authority if either document becomes stale.

## Start here in a future session

1. Read this file, the README, `default.project.json`, and any applicable `AGENTS.md` instructions present in that session.
2. Inspect the current source and `git status` before editing. At this handoff, the project files are **untracked** in Git; that does not mean they are disposable. No commit, remote repository, publication, or deployment has been established by this work.
3. Preserve desktop controls, the shared input contract, server-authoritative gameplay, and the separation between simulation, input, and rendering.
4. Keep compatibility with **Rojo 7.7.1**, pinned in `rokit.toml`.
5. **Do not implement the BW language or interpreter unless the user changes the scope.** It has been explicitly deferred in both development requests. There is no language specification to reconstruct from this prototype.
6. Do not claim Studio or Android play testing has passed. The checks so far are builds, compilation, and mocked tests, not Roblox runtime execution.
7. After gameplay changes, run the checks below, rebuild both place formats, and update the relevant documentation. The current request that produced this document was documentation-only.

## What this game is

BattleWorks is currently a Roblox Luau tank-combat prototype: one controllable tank per connected player in a flat practice arena. It supports solo target practice and the code paths for multiple player-owned tanks. It is not yet a complete competitive game.

The first requested milestone was one working controllable tank with a chassis, two tracks, rotating turret, and cannon. The second added Android touch controls, runtime input preferences, gamepad support, and an input relay/debug display. Future BW autonomous programs motivated the input abstraction, but no autonomous controller or BW execution exists yet.

There are no rounds, teams, matchmaking, score, progression, inventory, account saves, custom assets, sounds, or monetization systems. There is no known published Roblox experience ID or external backend in this project. The game uses Roblox networking and primitive parts; the place needs no external runtime packages.

## Gameplay and arena

- Each player owns one server state and an invisible anchored hitbox. Normal character spawning is disabled using `Players.CharacterAutoLoads = false`.
- Tanks move on the XZ plane at Y = 0, turn in place, reverse, and aim independently of chassis direction.
- Firing is hitscan. There are no simulated shells, gravity/drop, ammo limits, or reload magazines. Holding FIRE repeats shots at the cooldown.
- Tanks and targets have 100 health; a hit deals 25 damage. Four successful hits destroy a full-health target/tank.
- Destroyed tanks appear translucent and respawn at their assigned initial position after three seconds, with fresh state and a neutral command.
- Five orange targets stand at X = -36, -18, 0, 18, 36 and Z = -65. Their size is 7 × 7 × 5 studs, centered at Y = 3.5.
- Targets reset three seconds after destruction. Their `Health` attribute is updated; destroyed targets become mostly transparent and stop participating in ray queries.
- Four anchored boundary walls are centered at X or Z = ±118, with height 6 and thickness 4. The baseplate top is at Y = 0.
- Player spawn positions use eight columns spaced 13 studs apart and four repeating rows starting at Z = 35. They are assigned by join order, not player choice.
- On player departure, the server removes their hitbox/state; subsequent snapshots remove their visual tank on other clients.
- The HUD shows health and Ready/Reloading/Respawning status. The camera follows from an offset of `(0, 68, 48)`, looking at the smoothed local tank position.

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
| Raycast range | 320 studs |
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
| `src/client/init.client.luau` | Network reception/send loop, renderer lifecycle, camera, HUD, controller setup |
| `src/client/InputController.luau` | Preferences, provider activation/reset, settings button, suspension and stock-control coordination |
| `src/client/KeyboardMouseInput.luau` | Existing desktop adapter |
| `src/client/TouchInput.luau` | Touch UI, independent capture ownership, analog sampling, relay display |
| `src/client/GamepadInput.luau` | Gamepad1 adapter |
| `src/client/Analog.luau` | Radial dead-zone remap and circular clamping shared by touch/gamepad |
| `src/client/TankRenderer.luau` | Local tank geometry, smoothing, track animation, recoil/wobble, tracer/flash effects |
| `scripts/check.mjs` | Node development runner: compile sources, bundle modules with mock services, execute tests |
| `tests/RobloxMock.luau` | Minimal Roblox stand-ins for deterministic tests |
| `tests/Input.spec.luau` | Shared contract, simulation, adapters, transition/release and layout math tests |
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

Tracers are short-lived Neon parts (0.07 seconds); muzzle flashes are Neon balls (0.06 seconds), cleaned up by Debris. There is no complex suspension physics, constraints, mesh rig, animation asset, or imported model.

## Collision and implementation caveats

These are code-review observations and prototype limitations, not newly verified runtime bugs:

- Movement is direct kinematic state integration with instant speed changes. Terrain, slopes, gravity, traction, acceleration, and realistic tank-track steering are absent.
- Arena clamping, expanded XZ target boxes, and tank-to-tank radius checks provide simple movement blocking. A blocked move reverts position; yaw/speed are not rolled back. Collision is conservative and differs from the rotated rectangular shot hitbox.
- Tank-to-tank collision checks iterate other tanks regardless of health. Dead tanks can therefore still block driving until they respawn, even though shots can pass through their disabled query hitboxes.
- Destroyed targets are ignored by movement collision and ray queries, but their Part `CanCollide` value is not switched off. Tanks use custom movement, so physical collision flags do not define their movement.
- Spawn allocation repeats after 32 slots and does not resolve overlap with existing tanks on respawn. Do not assume support for a large player population.
- Server tank collision and damage lookup involve nested iteration. Snapshot broadcasts include all states for all clients. No scalability/load testing has been performed.
- The shot hitbox primarily represents the hull; elevated shots may visibly pass through turret/cannon geometry without hitting it. Revisit hit volumes if expanding combat fidelity.
- Snapshot smoothing can visibly lag or slide across a respawn. No explicit teleport/death animation reset protocol exists.
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
- Syntax compilation of all **11** source Luau files.
- **94** test assertions using mock Roblox services and vector stand-ins.
- Source map generation.
- Inspection of the generated XML for the expected nine ModuleScripts, LandscapeSensor enum value, and exclusion of tests from the place.
- Source whitespace inspection and `git diff --check`. Note that Git diff alone does not inspect untracked files.

Tests exercise malicious/invalid command values and clamping, old desktop contract compatibility, pitch bounds and shot direction, neutral turret hold, cooldown/death firing gates, dead-zone remapping, diagonal clamping, simultaneous stick/FIRE capture, cancellation, release/recentering, touch stealing prevention, resize cleanup, Auto/explicit preferences, default-control restore behavior, menu/focus/text suspension, gamepad disconnect, desktop input, relay formatting, and small-screen layout formulas.

The mocked layout dimensions checked are 480×200, 568×240, 640×280, and 960×480 safe-area sizes. These checks prove arithmetic spacing, not actual rendered legibility or touch hit testing.

The runner compiles the server/client entrypoints but does not execute the complete server loop or a real Roblox world. There is no automated engine-level multiplayer, raycast, respawn, networking, live GUI, or Android hardware test. Updating module names or require topology may also require changes in the mock loader and mock module tables.

## Runtime validation still needed

See the full checklist in the README. Priority checks for the next session with Roblox access:

1. Solo Studio Play: tank assembly, camera/HUD, desktop movement/aim/fire, walls/targets, four-hit destruction and three-second reset/respawn.
2. Two-client server: ownership, movement and turret pitch replication, collision, damage, fire pacing, respawn, departure cleanup, client/server Output.
3. Small/notched Android landscape screens and tablets: safe-area layout, stick/FIRE separation, debug readability, settings accessibility, both landscape rotations.
4. Physical three-finger use: independent turret/drive/FIRE, release outside widgets, cancel, app switching/lock, menu/text focus, no stale presses after resume.
5. Runtime preference transitions and Auto behavior with Bluetooth mouse/keyboard/gamepad and a touchscreen laptop; default controls restored when leaving Touch.
6. Gamepad sticks/trigger/disconnect and settings selection; artificial latency if available. Local relay values must not be mistaken for server acceptance.

## Where future changes belong

| Change | Primary location |
| --- | --- |
| Speed, health, damage, pitch limits, cooldown | `TankConfig.luau` and relevant server timing constants |
| New input device or remapping | Adapter plus `InputController`; preserve shared command semantics |
| New authoritative intent field | `InputCommand`, simulation/server consumer, every affected adapter, tests/docs |
| Better mobile layout/debug | `TouchInput`; retain per-touch ownership and safe-area behavior |
| Better visuals/recoil/wobble | `TankRenderer`; keep gameplay state unaffected |
| New arena/targets, collision, respawn rules | Server entrypoint; keep authority on server |
| Persistent settings | Explicit design first: session/account/device scope, then client/server storage integration |
| BW autonomous programs | Deferred until requested; reuse intent/simulation boundary when authorized |

Keep gameplay claims tied to evidence: build success is not runtime success, a mock assertion is not a physical Android test, and local intent is not authoritative telemetry. Update this handoff when architecture, requirements, or validation status changes.

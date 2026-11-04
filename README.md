# Battleworks tank prototype

One controllable tank per player in a flat practice arena. Built from Roblox parts: chassis, two animated tracks, independently rotating turret, and cannon. No external assets or packages required. BW language and interpreter are intentionally deferred.

For detailed implementation notes, known limitations, and future-session context, read [the Codex handoff](CODEX_HANDOFF.md).

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
- **A / D:** rotate chassis left / right, including while stationary.
- **Mouse:** aim the turret at the cursor's intersection with cannon height; rotation has a server-enforced speed limit.
- **Left click (hold):** fire repeatedly at the server-enforced 0.65 second cooldown.

The camera follows from above. The HUD shows health and reload state. Five orange practice targets each take four hits and reset three seconds after destruction. Tanks also take four hits and respawn after three seconds. The arena walls, targets, and other tanks block movement. Controls clear when the window loses focus or a text field gains focus. Server commands expire after 0.35 seconds without a valid update.

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

## Architecture

| Module | Responsibility |
| --- | --- |
| `src/shared/InputCommand.luau` | Shared intent contract and server validation. World-position aiming for desktop; normalized turret-rate axes for touch/gamepad. Steer is positive left. |
| `src/shared/TankSimulation.luau` | Instance-free state transitions, movement, turret rotation, cooldown and firing eligibility. Only the server advances gameplay state. |
| `src/shared/TankConfig.luau` | Simulation and combat tuning. |
| `src/server/init.server.luau` | Player ownership, fixed 60 Hz simulation, arena collision, input validation/rate limiting, authoritative raycasts/damage, target resets, respawn, 20 Hz state snapshots. |
| `src/client/KeyboardMouseInput.luau` | Existing WASD/mouse adapter, gated by selected mode. |
| `src/client/TouchInput.luau` | Two independent virtual sticks, hold-to-fire, per-InputObject ownership/cancel cleanup, safe-area layout, input relay display. |
| `src/client/GamepadInput.luau` | Gamepad1 analog sticks and right-trigger adapter. |
| `src/client/Analog.luau` | Shared radial dead zone, normalized output and circular clamping. |
| `src/client/InputController.luau` | Auto/explicit mode selection, settings button, focus/menu release, temporary default movement suppression. |
| `src/client/TankRenderer.luau` | Anchored cosmetic geometry, state smoothing, scrolling track shoes, scripted chassis wobble and cannon recoil, short-lived tracers and muzzle flashes. |
| `src/client/init.client.luau` | Input transport at 30 Hz, snapshot reception, renderer lifecycle, camera and HUD. |

All adapters return the same command contract and send intent through the existing input RemoteEvent. A future BW program can generate commands on the server and feed them into the same simulation path. BW execution is not implemented.

The shared command includes `throttle`, `steer`, `fire`, and `aimMode`. `World` uses `aim` (XZ world position) and preserves horizontal desktop aiming. `Rate` uses `turretX` (positive right) and `turretY` (positive up), both in [-1, +1]. Rate release holds the last turret orientation. The server integrates turret yaw/pitch, limits pitch to -12°…+30°, and applies pitch to authoritative shot direction. The renderer consumes the resulting state; adapters contain no movement or weapon simulation. Missing `aimMode` still accepts the original world-aim contract. Neutral/expired commands now hold the turret instead of aiming at a fixed world point.

Clients submit intent only: they cannot choose tank IDs, positions, health, hit results, damage, or cooldowns. The server validates finite values, clamps axes, enforces input rate and timeout, and uses its own turret direction for hitscan raycasts. Raycasts start at the turret center so nearby cover cannot be bypassed by a protruding barrel. Client visual parts have collision and ray queries disabled. Server hitboxes are anchored; no physics ownership or constraints are involved. Recoil and wobble affect visuals only.

This prototype supports a flat arena, simple conservative tank/target collision, and hitscan combat. It does not implement terrain traversal, projectile ballistics, client movement prediction, or BW execution.

## Verification

`rojo build -o battleworks.rbxl` and `rojo build -o battleworks.rbxlx` succeed with Rojo 7.7.1. A build validates the Rojo data model; it does not execute Luau. The development check compiles every source file using Luau Web and executes deterministic input/contract/simulation tests with mock Roblox services:

```bash
npm install --prefix /tmp/battleworks-luau-check luau-web@1.4.0 --no-audit --no-fund
node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js
```

The npm package is a development-only tool outside the place. Tests cover axis clamping and malicious values, legacy desktop aim, turret pitch limits and shot direction, cooldown, dead zones, three-finger input, cancellation, recentering, mode/focus/menu transitions, default-control restoration, gamepad disconnect and desktop input regression. Mock services do not verify actual GUI layout, Roblox event ordering, network timing, or hardware behavior. Studio and Android play testing are still required.

In Studio:

1. Play solo; verify both tracks, chassis, turret and cannon appear, and the HUD is visible.
2. Drive and reverse, turn while stationary, and aim independently of the chassis. Confirm the tank stops at walls and targets.
3. Hold fire on an orange target: four hits destroy it; it returns after three seconds. Confirm reload pacing and visual recoil/wobble.
4. Release keys, focus a text field, and switch windows; confirm driving/firing stops.
5. Use Studio's **Server & Clients** test with two players. Confirm independent controls, replicated movement/shots, tank collision, damage and three-second respawn. Stop a client and confirm its tank disappears.
6. Watch client and server Output for runtime errors throughout these checks.

Roblox references: [remote events](https://create.roblox.com/docs/scripting/events/remote), [server boundary validation](https://create.roblox.com/docs/scripting/security/client-server-boundary), and [raycasting](https://create.roblox.com/docs/workspace/raycasting).

## Android testing checklist (requires Roblox runtime)

1. Build/open the place as above. In Studio's device emulator, select a small Android phone in landscape; also check a notched phone and tablet. Start **Play**, confirm Auto resolves to Touch (or select Touch manually if the emulator reports keyboard input). Confirm both sticks, FIRE, debug panel, settings, and Roblox top bar fit without overlap; no default movement/jump controls should be visible.
2. Drag the left joystick right/up and then left/down. Verify yaw/pitch direction, pitch limits, and that release holds orientation. With the right stick, test throttle, reverse, stationary steering, dead zone, diagonal full travel and dragging far outside its circle. Confirm the released stick recenters and its relay axes return to zero.
3. On a real Android device, hold **three fingers simultaneously**: turret, drive and FIRE. Move each independently; release/repress one while holding the other two. The other controls must stay active. Four level shots should destroy a target; elevated/depressed shots should follow the cannon. A single mouse pointer in Studio cannot prove multi-touch.
4. Slide the FIRE finger off the button and release outside it; firing must stop. Switch apps/lock the screen while holding controls, open/close the Roblox menu, rotate to the other landscape orientation, and resume. Verify no stuck throttle/steering/turret/FIRE; fresh touches must work. Cancellation event delivery needs actual device testing.
5. While holding controls, cycle all four preferences. Check release, correct resolved mode, Touch-only UI, and default movement-control restoration. Test Auto with Bluetooth keyboard/mouse and controller; verify `PreferredInput` changes select the corresponding adapter. On a touchscreen laptop, mouse/keyboard use must not show the touch overlay just because touch hardware exists.
6. Re-test desktop WASD, mouse aiming, held left click, chat focus, and focus loss. In Gamepad mode test both sticks/trigger together, disconnect/reconnect, menu navigation and explicit mode selection.
7. Use a two-client Studio server to check replicated turret pitch, fire pacing, damage/respawn and ownership. Watch client/server Output for errors. Add network latency if available: the relay is local intent and the server remains authoritative, so visual/gameplay response may lag.
8. Publish privately through Studio for testing in the Roblox Android app on physical hardware. Rejoin and confirm preference resets to Auto. Publication is not performed by this repository's build/check commands.

API references: [PreferredInput and cross-platform input](https://create.roblox.com/docs/input), [mobile orientation](https://create.roblox.com/docs/input/mobile), [safe-area UI containers](https://create.roblox.com/docs/ui/in-experience-containers).

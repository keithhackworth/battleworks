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

The fixed 50°/45° map camera uses a strict central 20% dead zone and a wider default view; small readable maps remain fully framed. The HUD shows health and reload state. Five orange practice targets each take four hits and reset five seconds after destruction when their space is clear. Tanks also take four hits and respawn after three seconds. The arena walls, targets, and other tanks block movement. Controls clear when the window loses focus or a text field gains focus. Server commands expire after 0.35 seconds without a valid update.

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
| `src/client/TankRenderer.luau` | Anchored cosmetic geometry, state smoothing, scrolling track shoes, scripted chassis wobble, cannon recoil and muzzle flashes. |
| `src/client/init.client.luau` | Input transport at 30 Hz, snapshot reception, renderer lifecycle, camera and HUD. |

All adapters return the same command contract and send intent through the existing input RemoteEvent. A future BW program can generate commands on the server and feed them into the same simulation path. BW execution is not implemented.

The shared command includes `throttle`, `steer`, `fire`, and `aimMode`. `World` uses `aim` (XZ world position) and preserves horizontal desktop aiming. `Rate` uses `turretX` (positive right) and `turretY` (positive up), both in [-1, +1]. Rate release holds the last turret orientation. The server integrates turret yaw/pitch, limits pitch to -12°…+30°, and applies pitch to authoritative shot direction. The renderer consumes the resulting state; adapters contain no movement or weapon simulation. Missing `aimMode` still accepts the original world-aim contract. Neutral/expired commands now hold the turret instead of aiming at a fixed world point.

Clients submit intent only: they cannot choose tank IDs, positions, health, hit results, damage, or cooldowns. The server validates finite values, clamps axes, enforces input rate and timeout, and uses its own turret direction for slow server-authoritative projectile sweeps. Shells launch from the cannon tip after a server obstruction check from turret to muzzle. Client visual parts have collision and ray queries disabled. Server hitboxes are anchored; no physics ownership or constraints are involved. Recoil and wobble affect visuals only.

This prototype supports a flat arena, simple conservative tank/target collision, and slow straight-flight projectile combat. It does not implement terrain traversal, projectile ballistics, client movement prediction, or BW execution.

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
3. Hold fire on an orange target: four hits destroy it; it returns after at least five seconds when unoccupied. Confirm reload pacing and visual recoil/wobble.
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

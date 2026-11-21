# Three-dimensional aiming and mouse controls

## Architecture inspected before implementation

KeyboardMouseInput currently projects the cursor onto the fixed Y=3.6 plane. InputCommand validates World/Rate commands but flattens World target Y to zero. TouchInput and GamepadInput already supply independent normalized yaw/pitch Rate axes through InputController. TankSimulation owns rate-limited yaw and pitch, but World mode resets pitch; pitch uses the separate PitchSpeed property. BWController derives turretPerformance from the existing turret device's allocation through BWChassis.performance. Both axes already use that performance multiplier.

TankSimulation.shotPose composes turret angles and chassis pitch/roll. The server releases cannon shots after existing windup and Gatling shots after existing heat timing; ProjectileSimulation sweeps the barrel and subsequent shell motion and LocalBattle applies server-derived damage. Existing airborne Gatling shotPose overrides elevation with a descending launch angle, and its trajectory can flatten an upward shot. TankRenderer already renders barrel elevation but smooths network state; BattleClient currently substitutes the smoothed local muzzle direction into shot effects.

BW commands use BWCommands contracts, BWExecution device routing, BWDevices queues and BWRuntime physical execution through BWTankAdapter. Existing turret_left/right are horizontal heading commands. Playground occupancy/epochs and Classic owned collections authorize the same Input/BW/hardware server handlers. Their session and respawn machinery does not need replacement.

## Proposed implementation

Keep the World/Rate protocol and server protections. Preserve finite World XYZ; solve target yaw/pitch in the tilted chassis frame about the existing turret pivot. Rate-limit both axes independently by TraverseSpeed × turretPerformance, respecting effective mount-relative limits (cannon −12°..30°, Gatling −15°..30°). Retain PitchSpeed only as a derived compatibility alias, never a separately tunable elevation speed.

Separate ray target selection, pure mouse-mode math, provider lifecycle and compact HUD. Mouse Points casts against authoritative arena geometry/tank hitboxes, excluding own tank, decorations and effects. A ground hit may promote to the first eligible solid vertical object directly above its XZ; an empty ray has a fixed-distance fallback. Mouse Direct consumes relative deltas into bounded angle intent; Mouse Joystick uses radial dead-zone rate intent around a stable viewport center. All ultimately use the existing mechanically bounded turret implementation. Keep the mouse preference in the persistent InputController across tank leases/respawns. Temporarily release cursor lock for GUI interaction and suspend/reset intent on focus/menu/BW/control changes.

Release shots using actual barrel orientation, without target redirection or forced airborne descent. Preserve existing Gatling descending-then-level flight only when fired downward while airborne, with a continuous initial tangent; upward/horizontal shots stay in their actual direction. Existing barrel obstruction, cooldown, range, damage, heat, bus and hit authority remain. Use server shot geometry for muzzle effects. Extend BW with queued turret_up/down commands on the existing turret device, using the same rate, limits and authorization; retain horizontal commands unchanged.

Implementation details, verification and native acceptance are appended below as work completes.


## Implemented controls and limits

Click the controller icon beside the input selector or press **C** while driving to open the mouse aiming options. C frees the cursor in Mouse Direct while the options are open. Choose Mouse Points (default), Mouse Direct, or Mouse Joystick, or press C again to close the panel. The selected option is marked. Mouse-specific UI is hidden for touch/gamepad. The existing touch sticks and gamepad axes remain on Rate input and share the upgraded mechanical speed.

- **Mouse Points:** raycast authoritative arena geometry and Terrain, excluding own hitbox, local art, effects and non-solid scenery. On a walkable top, search upward at the same XZ for the first eligible object. Empty rays use a 1,500-stud ray fallback. Desired yaw/pitch is solved about the existing pivot; the straight barrel's muzzle is collinear with that vector. A target out of range or outside mechanical travel does not gain an assisted hit.
- **Mouse Direct:** relative mouse deltas become bounded Rate input; the turret holds when movement stops. The cursor locks to center. **Hold Alt** to use UI, then release to resume. No offscreen cursor accumulation or delayed unlimited turn target. Deltas are sampled at the existing 30 Hz packet cadence so intermediate render frames do not discard mouse movement.
- **Mouse Joystick:** 55-pixel radial dead zone, proportional speed up to a 170-pixel radius, with a subtle neutral circle and cursor marker. Return to the circle to stop. **Shift+C** makes the current cursor location the new neutral point. After mode/focus/control transitions, move into the neutral circle (or press Shift+C) to arm; moving out of a menu cannot immediately spin a tank.

The preference lives in the persistent input provider for this client session, surviving tank switches, occupancy changes, death/respawn and BW handoffs. It is not yet stored across leaving/rejoining Roblox. Focus loss, text entry, Roblox menus, BW, and leaving a tank release intent/cursor state. Mode changes send a neutral release through the existing authorization path.

**All angles are relative to the weapon mount, not the world horizon.** Chassis pitch/roll is removed before solving target angles and reapplied to the actual release direction. A downhill tank can point farther below the horizon without exceeding its mount-relative depression. The standard mount permits −15°..30°; weapon.cannon limits depression to −12°, weapon.gatling to −15°. Optional weapon MinPitch/MaxPitch intersect mount travel in VehicleComponents.resolve. Future weapons can specify greater depression when their installed mount supports it; a weapon cannot bypass a stricter mount. No existing assembly IDs or world formats changed.

Both axes are bounded independently by the same TraverseSpeed × turretPerformance × dt. Legacy resolved PitchSpeed and TankConfig.TurretPitchSpeed are derived aliases; there is no independently configurable elevation speed. Bus allocations are still calculated by BWController/BWChassis. Mechanical limits apply to human input, BW, recoil-adjusted barrel orientation and server firing in both game modes.

Actual server shot origin/direction drive release effects and swept collision. Cannon windup still uses the barrel pose at release, not at click time. Gatling heat, cooldown, recoil and damage remain intact. Forced airborne downward barrel override is removed. Only a physically downward airborne shot acquires descending/leveling flight; upward/horizontal rounds preserve their direction, and the curve preserves its initial tangent even near a platform. Existing legacy trajectory helpers remain tested through explicit descending fixtures. No target/hit/damage claims were added to networking.

## BW elevation

`turret_up(degrees)` and `turret_down(degrees)` accept relative 0..180 degrees. Both support `to=pitch` (−90..90 degrees, positive up) and best_effort, with targets clamped to the installed weapon/mount travel. Absolute commands choose the direction needed regardless of their up/down name. They cost one submission tick and use the existing turret device FIFO, authorization, bus allocation, timeout, cancellation and result dictionaries. `turret_left/right` retain their heading and full-revolution semantics and preserve the current elevation. The in-game handbook and BW_LANGUAGE document these commands.

## Native acceptance still required

1. Start two clients in The Playground. Enter different public tanks. Park one above the other on the overlook/ramp and use Mouse Points to watch bounded yaw/elevation, then fire cannon and Gatling. Confirm hitboxes, visible barrel, tracer/release effects and damage agree.
2. Shoot downhill, across the ravine, and from bridge/raised custom platforms to lower land. Try a target beyond depression/elevation travel: the barrel must stop, and firing must not manufacture a hit.
3. Tilt a tank uphill/downhill and roll it on uneven ground. Confirm the cannon's −12° and Gatling's −15° stops are relative to the mount. The downhill world angle should differ by the chassis tilt. Repeat with a swapped weapon assembly.
4. Fire before alignment, during cannon preparation, while targets move vertically/horizontally and while Gatling recoil lifts the tank. Confirm actual release orientation, normal heat/cooldown, barrel cover obstruction and platform-relative downward leveling.
5. Switch all three modes while driving/firing. In Direct, use Alt for HUD, menus, editor and exit. In Joystick, test dead zone, sustained displacement, Shift+C recenter and rearming after menus. Test low/high frame rate and network latency.
6. Switch tanks, die/respawn, run/stop BW, lose focus, open text entry/CoreGui and return to Main Menu. Preference must persist without stuck fire, cursor lock, duplicate UI/listeners or abandoned tank control. Repeat with touch/gamepad; mouse UI should hide and existing controls should work.
7. Run turret_up/down and existing horizontal BW scripts with reduced/zero turret allocation. Both axes must share speed scaling and remain authorized only for current occupancy/selection. Repeat in Classic and an imported custom world, including buildings/bridges in vertical cursor columns.

Native ray/GUI input ordering, platform surface selection, cursor-lock behavior and smoothed network presentation require Roblox Studio/device testing. Automated stand-ins do not establish native gameplay acceptance. The existing −12°/−15° depression and 30° elevation intentionally leave some nearby height differences unreachable.

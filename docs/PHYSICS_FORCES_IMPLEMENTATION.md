# Flat-ground momentum and traction implementation

Branch: `feature/physics-forces`. Approved scope: shared world linear/yaw velocity, grounded traction, static/kinetic friction, forces/impulses, stable contacts, existing controls/BW/recoil. No rivers, wind generators, buoyancy or general prop simulation in this release.

## Stages and acceptance
- [x] 1. Generic motion/impulse primitives and deterministic independent surface-region contracts; focused unit tests; commit.
- [x] 2. Unify tank motion and migrate drive/recoil to the shared authority; preserve ordinary-ground tuning, airborne flight/landing, propulsion-only caps; focused regression tests; commit.
- [x] 3. Deterministic multi-contact collision response and server integration; penetration correction excluded from BW progress; focused tests; commit.
- [x] 4. BW braking/progress, debug/documentation, full regressions, both Rojo builds; commit.
- [ ] Native Studio acceptance: manual/touch/BW, ice braking/skidding/spinning, recoil landings, tight contacts, reset/switch, renderer and camera.

## Approved compatibility contract
World linear velocity and yaw angular velocity own motion; speed and legacy recoil velocity fields are derived compatibility views. Pitch/roll remain existing suspension/recoil behavior. The generic impulse API projects torque onto yaw for now, using a Vector3 angular representation reserved for later 3D support. Mass units are normalized gameplay units. Controls generate traction-limited requests. No contact traction in air. Speed ratings and bus allocations constrain propulsion, never erase externally acquired velocity. Recoil launch/gravity/ceiling/seeding remain existing policy, with one shared velocity authority. Surface fields compose independently from visual terrain; region priorities and boundary blending are deterministic.

Ordinary ground is calibrated for current feel; ice and explicit impulses reveal momentum. Immediate drivetrains gain a high but finite response. Command completion measures actual signed horizontal travel or unwrapped yaw; lateral/vertical drift and contact position corrections do not count, backward travel subtracts, completion does not erase momentum. No BW syntax/CPU/bus changes.

## Verification notes
Results and intentional differences will be recorded per stage below. Native Studio checks remain pending regardless of mocked server tests or successful builds. No merge to master or push is authorized by this task.

Stage 1: generic mass/inertia/force/impulse math and prepared surface fields pass 12 focused assertions, including one-shot consumption, off-center yaw, priority and transition/insertion-order independence. Surface fields use deterministic priority layers, weighted equal-priority blending, and maximum boundary coverage within each layer. No gameplay integration yet.

Stage 2: one horizontal motion path for all components; force/impulse state shared with flight, yaw momentum, four-point surface sampling and no airborne traction. Component Mass defaults1 and YawInertia derives from mass/footprint; mobility owns grip and finite yaw response. Classic propulsion gets high finite acceleration2880/braking2880/coast1440 to reproduce ordinary one-step response. Car tuning unchanged. Contact uses a shared longitudinal/lateral/twist impulse budget; static adhesion holds small disturbances, kinetic slip uses its separate lower limit. Ice has lower passive rolling resistance. Strong lateral grip replaces the former unconditional exponential lateral-velocity decay. Overspeed coasts rather than being engine-clamped; the weapon cap now limits added recoil only. Vertical flight retains the original seeded/ballistic equations and tank lift safety envelope; vertical impulses still follow that envelope in this phase.

Verified: motion/traction142 assertions, recoil6015, trajectory1855, speed11, steering57, components90, combat/projectile/terrain/tank suites pass. Recoil fixtures now set authoritative velocity through VehicleMotion rather than editing derived aliases after initialization; assertions retained. Native driving feel remains unverified. Pose support on existing rocks/logs remains; no new slope-force model.

Stage 3: VehicleContacts adds oriented-box support features/manifolds, accumulated sequential impulses, bounded friction, split position correction, continuous translational SAT and angular speculative contacts. Stable IDs order dynamic pairs and static contacts; simultaneous contacts use 10 fixed solver iterations, bounded event/substep counts and a no-advance fallback on event exhaustion. Tank envelopes initially derive from 2×legacyRadius (10×10), retaining old cardinal clearance; damage hitboxes remain unchanged. Chassis CollisionWidth/CollisionLength can override the envelope. Collision restitution is zero. Vertical intervals exclude non-overlapping airborne bodies. Tree/arena geometry is cached per environment generation; targets preserve their active/health blocking rule. Server prediction now completes for all tanks before one contact phase and all hitbox commits, replacing table-order-dependent rollback/velocity erasure. Obsolete recoil resolveBlocked removed.

Verified: contact coverage154 total assertions, production server4776, live loadout/server1518. Existing recoil boundary fixtures now isolate their pose/omega from earlier collision stress, use authoritative velocity setters, check actual contact surface with 0.001 numerical tolerance, and retain the flight envelope assertions. Ordinary-ground friction and pair collisions are dissipative; tight impossible spaces remain bounded but are not promised physically satisfiable. Angular CCD is conservatively subdivided/speculative; it is not a general mesh rigid-body engine.

Collision regression follow-up: initial full suite exposed the old invalid-position recovery case (spawn at10000 outside a tiny map). Arena boundaries are now infinite half-space contacts rather than finite boxes, with exact inward depenetration; normal contacts still use skin/slop and split correction. Input94/camera13132 plus all349 new physics assertions pass. Tree fixture now checks true contact surface instead of rollback to the previous tick. Two-point normal block solving prevents artificial yaw from centered impacts on narrow pillars without increasing the iteration budget.

Resolved-flight follow-up: the server defers vertical flight and suspension finalization until after horizontal contact resolution, so a predicted location behind cover cannot create a phantom landing/ground snap. The existing flight equations run once against the actual resolved support. New checks compare standalone/two-phase flight for120 steps and verify a falling tank blocked in front of a raised rock does not land on that unreachable rock. Core/contact/surface/flight286 assertions and BW/control195 pass (481 new total); server4876 and live loadout1518 pass.

## Configuration and server API

Three focused modules were added: VehicleMotion (body math), SurfacePhysics (prepared map contact fields) and VehicleContacts (planar contacts). Ground traction stays with the existing RattlerDrive module; flight policy stays with RattlerRecoil. There is no second control/physics engine or general prop simulator.

### Body state and components

- `linearVelocity: Vector3` is authoritative, world studs/sec.
- `angularVelocity: Vector3` reserves full 3D representation; only `.Y` is simulated in radians/sec. X/Z torques are deliberately not integrated.
- `speed` is signed forward projection. `velocityX`, `velocityZ`, `verticalSpeed` are derived views; code must use VehicleMotion setters after initialization.
- `motionMass` and `yawInertia` come from resolved chassis configuration. Mass defaults1 normalized gameplay unit, inertia defaults mass×(Hitbox.X²+Hitbox.Z²)/12.
- Chassis CollisionWidth/CollisionLength default2×Radius; damage/query hitboxes are unchanged.
- Mobility adds LongitudinalGrip/LateralGrip (both1), YawAcceleration120. These are contact response factors, not speed multipliers.
- `motionCorrection` is a cumulative split-position-correction ledger, excluded from BW travel and speed telemetry. It is not a velocity authority.

Generic internal APIs accept a body record with position/yaw and configured mass/inertia, not a tank identity:

```lua
local Motion = require(Shared.VehicleMotion)
Motion.configure(body, mass, yawInertia)
Motion.force(body, worldForce, optionalWorldPoint)
Motion.torque(body, yawTorque)
Motion.impulse(body, worldImpulse, optionalWorldPoint)
Motion.angularImpulse(body, Vector3.new(0, yawImpulse, 0))
```

Force units are normalized mass×studs/sec²; impulse units mass×studs/sec. Re-submit continuous forces once per authoritative physics step; beginStep consumes their sum once. Impulses apply immediately, once per call, without a timestep multiplier. Horizontal weapon kick values are physical normalized impulses; heavier chassis receive less horizontal velocity from the same gun. The existing vertical weapon launch remains a prescribed cartoon peak, explicitly retained for compatibility rather than converted to a new energy/reload balance. A world point produces yaw torque/angular impulse from its X/Z lever arm. Producers must run in stable server order. Weapon releases retain their established phase after movement/contact resolution; new recoil affects subsequent integration. This API does not expose new BW calls or trust client force results. Generic prop integration/full 3D physics is NOT implemented.

The existing flight solver applies gravity once. Do not submit the existing gravity a second time as an external force. While supported, upward forces below weight reduce the normal load without launching the tank; an actual launch impulse or force exceeding weight permits takeoff. No grounded propulsion, braking, slip correction or yaw control is applied while airborne. Landing and suspension finalize against resolved support, not a rejected predicted position.

### Invisible surface regions

Map construction can configure surface regions without changing visual terrain. For example, immediately after `Environment.create(mapSize)` in the server:

```lua
local Surface = require(Shared.SurfacePhysics)
Environment.setPhysicsSurfaces(environment, {
    {
        id = "ice-practice",
        shape = "box", -- or "ellipse"
        x = -mapSize.X * 0.25,
        z = mapSize.Y * 0.30,
        rx = mapSize.X * 0.15,
        rz = mapSize.Y * 0.12,
        priority = 10,
        transition = 3,
        surface = Surface.Profiles.Ice,
    },
})
```

The default map is not changed by this example: it remains opt-in configuration. Existing visual Water/Mud speed multipliers and rock/log height sampling remain intact. Surface contact defaults to Normal independently of visual `kind`.

A prepared region has a stable unique ID, box/ellipse bounds, priority and nonnegative transition width. Lower priority layers resolve first; higher layers overlay them. At equal priority, fields are weight-averaged and layer coverage is the maximum boundary weight, so overlaps never multiply friction. Sorting by priority/ID fixes evaluation order. Full coverage replaces the lower layer; smoothstep boundary coverage blends back to it. Zero transition is an explicit hard boundary. Ellipse transition distance is a normalized radial approximation scaled by its smaller radius; box edge distance is exact. Four chassis contact sample points average the resulting coefficients. Fields are copied/frozen at preparation, not sorted or validated each physics tick. `staticFriction >= kineticFriction >= 0` and resistance>=0 are enforced. Force zones, competing flow channels, wind/current generators and buoyancy are deferred; force/torque producers already compose additively through the body API.

## Intentional behavioral differences

- Ordinary-ground engine ratings, acceleration/reverse/braking, wheelbase, steer lock and weapon tuning are retained. Classic's formerly instantaneous response is approximated by high finite response; normal high grip preserves familiar pivot/curve behavior. This is calibrated by regression tests, not yet by native driving feel.
- Low grip limits combined longitudinal/lateral/angular response. A chassis may point away from its travel direction, skid, or spin. Neutral/stop uses coast/rolling resistance; partial/reverse throttle can brake. No stop path anchors or clears world velocity.
- Engine/bus limits constrain propulsion, not world velocity. Full-throttle overspeed coasts; reducing/reversing the requested throttle can brake it. Recoil's cap limits the newly added increment without reducing existing overspeed. Existing jump timing/height/landing/airborne-control rules remain.
- Arena/tree/target/tank contacts now resolve at their surfaces, not by rolling back an entire tick. The initial oriented envelope preserves prior cardinal radius clearance; corner clearance necessarily changes with yaw. Normal impulse blocks penetration, tangential friction allows sliding and contact offsets generate spin. Restitution defaults0. Stationary contact is not given artificial separation velocity.
- Penetration corrections can reposition an initially invalid/overlapping body, but do not create energy, BW progress or a fake speed boost. Tank pairs resolve once in stable ID order. Wreck tank colliders retain existing blocking participation; detached debris is still cosmetic, not a new prop simulation.
- Finite BW distance measures signed actual horizontal travel; backwards drift subtracts, sideways/vertical drift and solver correction do not count. Turns measure actual signed unwrapped yaw, including external angular motion. Completion need not mean resting/holding a final pose. Existing timeouts, immobilization pauses, cancellation, best-effort and command result contracts are unchanged.
- Debug HUD shows rated versus allocation-limited drive speed, measured speed/boost, yaw rate and grounded/sliding state. Moving with zero allocation avoids division by zero.

## Limits and follow-up work

This is planar rigid contact plus the retained tank flight/suspension solver, not full Roblox rigid-body dynamics. Surface load uses the existing support-height sampler and four-point grip samples, not a full per-wheel 3D suspension/contact model. Rivers, wind generation, slopes/gravity-field overrides, buoyancy, full 3D angular dynamics and general prop simulation remain deferred.

Contacts use oriented boxes/arena half-spaces, continuous translational SAT, conservative angular speculative contacts and bounded substeps/events. They are not arbitrary mesh CCD. Resting/multi-contact normal forces use a two-point block solve; split correction avoids energy injection. Overconstrained spaces converge to a bounded residual rather than promising an impossible fit. Pathological event exhaustion records `motionContactLimited` and conservatively leaves remaining motion unadvanced instead of tunneling; extreme angular/mesh cases require further work before general prop/pinball simulation.

Terrain obstacle caching is per environment generation; reconstruct/invalidate its `motionObstacles` cache when changing tree geometry in place. The current redraw path creates a new environment automatically. No new upgrade/map UI is introduced.

Final numeric checks: contact skin is1e-4 studs for native Vector3 precision at supported map sizes; correction ledgers record actual applied displacement, not requested correction. Empty contact sets skip unnecessary solver iterations. Horizontal gun impulse now scales with chassis mass while default mass1 preserves baseline weapon behavior.

BW integration refinement: physical forward-travel and unwrapped-yaw odometry are accumulated only during resolved integration (prediction is rewound before contact replay). Forward travel integrates the changing-heading projection analytically per constant-velocity segment, so a full spin cannot bank false forward distance. Chassis turn progress can count more than one revolution in an update; legacy wrapped-state/turret fallbacks remain. Depenetration is never odometry. Focused BW6094, best-effort104, steering57, damage61 and scanners193 pass. New suites total488 assertions (body/contact/flight290 + BW/control198).


## Final verified results

- Syntax compilation:72 Luau source files.
- Full checker:all19 groups pass, including every existing input/camera/combat/terrain/render/BW/compiler/device/thread/function/vehicle/server regression.
- New physics suites:488 assertions (290 motion/surface/contact/flight/mass;198 BW/control/telemetry/odometry).
- Existing server4876, live assembly integration1518, recoil6015, trajectory1855, BW movement6094, persistent steering57, vehicle components90, handbook399, editor175 pass.
- Runtime documentation:14 examples on each tank simulation in both legacy-loadout and live-loadout checks.
- `rojo build -o battleworks.rbxl`:passed.
- `rojo build -o battleworks.rbxlx`:passed.
- `git diff --check`:passed.
- Work remains on feature/physics-forces in logically separated commits; no master merge or push.

Only native Studio acceptance remains unchecked. Run from this worktree/build, restart Play, and verify ordinary driving, reverse/stop/curves on both installed mobility systems, an opt-in Ice region, moderate off-center impulses, centered/glancing/multiple contacts, airborne recoil/landing, camera/touch controls, BW completion/cancellation, reset and tank switching. Unit mocks/builds do not establish those native results. Deferred generators/3D/prop work listed above is outside this phase, not silently implemented.

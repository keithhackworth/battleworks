# Flat-ground momentum and traction implementation

Branch: `feature/physics-forces`. Approved scope: shared world linear/yaw velocity, grounded traction, static/kinetic friction, forces/impulses, stable contacts, existing controls/BW/recoil. No rivers, wind generators, buoyancy or general prop simulation in this release.

## Stages and acceptance
- [x] 1. Generic motion/impulse primitives and deterministic independent surface-region contracts; focused unit tests; commit.
- [ ] 2. Unify tank motion and migrate drive/recoil to the shared authority; preserve ordinary-ground tuning, airborne flight/landing, propulsion-only caps; focused regression tests; commit.
- [ ] 3. Deterministic multi-contact collision response and server integration; penetration correction excluded from BW progress; focused tests; commit.
- [ ] 4. BW braking/progress, debug/documentation, full regressions, both Rojo builds; commit.
- [ ] Native Studio acceptance: manual/touch/BW, ice braking/skidding/spinning, recoil landings, tight contacts, reset/switch, renderer and camera.

## Approved compatibility contract
World linear velocity and yaw angular velocity own motion; speed and legacy recoil velocity fields are derived compatibility views. Pitch/roll remain existing suspension/recoil behavior. The generic impulse API projects torque onto yaw for now, using a Vector3 angular representation reserved for later 3D support. Mass units are normalized gameplay units. Controls generate traction-limited requests. No contact traction in air. Speed ratings and bus allocations constrain propulsion, never erase externally acquired velocity. Recoil launch/gravity/ceiling/seeding remain existing policy, with one shared velocity authority. Surface fields compose independently from visual terrain; region priorities and boundary blending are deterministic.

Ordinary ground is calibrated for current feel; ice and explicit impulses reveal momentum. Immediate drivetrains gain a high but finite response. Command completion measures actual signed horizontal travel or unwrapped yaw; lateral/vertical drift and contact position corrections do not count, backward travel subtracts, completion does not erase momentum. No BW syntax/CPU/bus changes.

## Verification notes
Results and intentional differences will be recorded per stage below. Native Studio checks remain pending regardless of mocked server tests or successful builds. No merge to master or push is authorized by this task.

Stage 1: generic mass/inertia/force/impulse math and prepared surface fields pass 12 focused assertions, including one-shot consumption, off-center yaw, priority and transition/insertion-order independence. Surface fields use deterministic priority layers, weighted equal-priority blending, and maximum boundary coverage within each layer. No gameplay integration yet.

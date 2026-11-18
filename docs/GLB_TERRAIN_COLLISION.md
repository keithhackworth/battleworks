# GLB terrain collision: Forest/rocks-ramp

Forest/rocks-ramp now has an explicit `faces` collision profile in `worlds/asset-collision-profiles.json`, pointing to `GLBs/forest/rocks-ramp.glb`. Keep Solid enabled on placements that should support/block tanks. Rojo sync and restart Play so the new server catalog is loaded; existing saved-world asset IDs and transforms do not change.

## What is generated

`node tools/build-editor-catalog.js` reads the original GLB binary vertex/index buffers, applies scene-node transforms and normalizes upward triangles into the source mesh bounds. The actual asset has 107 upward faces, of which 51 satisfy the existing 45-degree walkable limit. Horizontal terraces preserve their individual heights. This produces trusted catalog metadata only: it never converts or rewrites the imported Roblox Model, its textures, geometry or native bundle. It does not build a place.

The offline reader supports static uncompressed GLB v2 triangle primitives, float VEC3 positions, unsigned indices, interleaved accessors and scene-node matrix/TRS transforms. It rejects unsupported compression, sparse accessors, skins, morphs, invalid buffers and excessive face counts. Binary/accessor conventions follow the [Khronos glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html).

## Runtime

- EditorAssetCatalog retains the native render model and publishes the face profile. Native/GLB dimension ratios must match within 1%; incompatible models are not silently fitted to unrelated geometry.
- Authoring JSON still contains asset references, transforms and Solid/destructibility flags. No faces are saved in player objects. PlayerWorldDocument rejects client-supplied collision geometry and resolves profiles from the server catalog. Compiled Studio catalogs carry ColliderFaces as trusted metadata.
- WorldObjectGeometry transforms each normalized triangle using the placed model's measured frame/size. A terrain prism extends from that top triangle down to the source model base. Its actual convex footprint is passed into VehicleContacts; the old enclosing square is not an obstacle.
- VehicleContacts adds a fixed convex-polygon path to its existing SAT/manifold/continuous collision solver. Existing rectangular tank, platform, ramp, pushing and boundary paths remain in use. Sloped top faces use the existing traversal/step limits; cliffs remain obstacles.
- FootprintSupport clips triangle tops against the entire chassis footprint, combining adjacent triangles and terraces. Point support and airborne projectile leveling use the same triangle-limited support faces, not an extrapolated rectangle.
- Native visible mesh parts provide projectile/scanner query hits for this profile; they share one object's health/damage receipts. Their native CanCollide remains false. Destruction/reset disables/restores all corresponding movement, support and hit queries. Native query accuracy still depends on Roblox MeshPart collision fidelity; tank support and blocking use the extracted GLB profile.

## Deliberate limits

This is an opt-in upright rock/terrain profile, not a general watertight triangle-mesh physics engine. It fills columns beneath upward faces, so it is unsuitable for bridges, arches, caves, tunnels, overhang clearance or upside-down terrain. Empty areas with no overlying terrain face remain clear. Yaw, uniform scale, placement height and ordinary terrain tilt transform the profile with the native asset; rotating it onto a side is not a substitute for extracting a different terrain orientation.

There is no increase to the tank's climbing ability. A tall real step remains too high: at the default scale 45, a source height difference of 0.1 is 4.5 studs, above the existing 1.5-stud step allowance. Use a reachable slope/access ramp or a smaller asset scale if access to that level is required. Do not turn Solid off to make terrain driveable.

The profile is limited to 512 upward triangles and is currently enabled only for rocks-ramp. Builtin ramps/platforms, imported buildings/bridges, registered tree fractions and the sampled `mesh` profiles for other rocks are unchanged. Spawn reservation checks remain conservative around triangular prism bounds.

## Validation

Automated tests decode the real source GLB, verify its terraces and source dimensions, exercise native placement-frame rotation/scale, reject forged client faces, and run production support/contact/damage/reset logic. They also drive both tank types over reachable triangulated terraces and check diagonal clearance, high-speed deflection and steep-face rejection. Existing elevation and footprint suites retain narrow seams, multilevel bridges and intentional cliff falls.

After Rojo sync, validate in Studio:

1. Restart Play, load a world containing Forest/rocks-ramp and keep Solid enabled. Approach visible empty corners: tanks should not hit the old overall square.
2. Reach several terraces via a builtin access ramp or by positioning a test spawn on them. Park, drive across triangulation joins and verify support matches the visible rock heights. Try a smaller scale to test naturally reachable low steps.
3. Confirm high cliffs block rather than lifting tanks. Drive off exposed edges and confirm ordinary falls.
4. Repeat at yaw 37/90 degrees, another scale and a raised placement. Check collider alignment visually with the native mesh, including its pivot.
5. Use two players to shoot a destructible copy. Confirm damage is shared, destruction removes support immediately, and reset restores it without extra geometry.
6. Check native projectile/scanner hit fidelity and profile cost with multiple copies on target hardware. No native Roblox Studio run is claimed by the Node/Luau numeric harness.

## Bulk processing update

The current catalog now processes every imported asset automatically. The original opt-in terrain implementation above is retained as historical/legacy behavior; the enabled bulk pass also pairs undersides and retains wall faces. See [Bulk asset collision](BULK_ASSET_COLLISION.md) for current coverage, fallbacks and clearance limits.

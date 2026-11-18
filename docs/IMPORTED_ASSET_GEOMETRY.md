# Imported asset bounds, snapping and tank collision

## Investigation

The native `assets/roblox/assets.rbxm` was inspected with Rojo's native model reader (temporary RBXMX model conversion, not a place build). Sampled Forest rocks-high, rocks-low, rocks-ramp, stones, bridge and building-platform, and Surburban/building-type-a contain a visible MeshPart inside the asset Model's primitive-group hierarchy. These samples had no invisible padding Parts. Their MeshPart Size matches the source GLB position extents; e.g. rocks-high is 1×1×1 and rocks-low is 1×0.52277×1. Source offsets and bottom-oriented pivots are recentered by ModelPlacement. There is no evidence of a universal GLB scale/pivot error.

The actual runtime mismatch was the generated collider: WorldObjects used one full-model rectangular proxy for every unregistered imported object. Native visual Parts have CanCollide=false. VehicleContacts performs BattleWorks' authoritative rectangle SAT/continuous collision, not Roblox native MeshPart contact physics. A rock's valid outer bounds therefore blocked tanks through empty corners. Registry trunk fractions remain intentional for registered trees.

The snap raycast did include imported objects. However, WorldEditorSnap accepted only the upper rectangle of the overall bounds. A rock surface, building side or roof below that top face was rejected. Separately, requesting Stretch on a MeshPart rejected the entire snap gesture. These are related uses of outer bounds, not one metadata registration failure.

## Pipeline and separation

- Binary bundle discovery, hierarchical asset IDs and native model resolution are unchanged. No model geometry is rewritten or duplicated in source assets.
- AssetGeometry measures visible BasePart bounds in the model bounding frame. Invisible helpers, generated WorldObstacleHitbox parts and parts marked BattleWorksIgnoreBounds are excluded. These bounds control grounding, selection and rotate pivots. MeshPart Size is still an outer bound, not a mesh-vertex scan.
- EditorAssetCatalog publishes measured bounds and trusted collision metadata. Imported snap targets use the native ray hit position/normal; bounding corners/edges are retained only when a short query confirms an actual surface there. Builtin face/edge/corner and multilevel fitting behavior is retained. Imported assets automatically use Scale if Stretch cannot represent their geometry.
- Authoring/export JSON still stores hierarchical asset references, visual bounds and transforms. Collision cells are not added to saved world objects. Existing IDs, scales, namespaces and documents remain compatible.
- PlayerWorldDocument recomputes dimensions and profiles from server templates. Client-supplied hit/collider claims are not accepted. The offline compiler retains profile selection in ColliderFit; compiled Studio worlds fit source templates before placement.
- Sampled `mesh` profiles in worlds/asset-collision-profiles.json cover Forest/rocks-high, rocks-low and stones. MeshCollisionFit samples native query geometry once per template in a temporary isolated WorldModel, then destroys it. It uses an 8×8 horizontal grid with nine samples per cell and upper/lower rays, producing at most 64 normalized boxes. Cells follow placement rotation/scale and feed the existing contact, projectile, support, health, destruction and reset systems. Compound cells share one damage receipt/health record.
- Buildings, bridges, ramps, builtins and registered trunk fractions keep their existing support geometry. No blanket shrink rule is applied. Spawn checks use fitted cells when authoritative sampled metadata is available; offline tools without native samples conservatively use the full rectangle.

## Limits and native Studio validation

This is a bounded sampled approximation, not triangle collision. It depends on the imported MeshPart's Roblox query geometry/CollisionFidelity. Thin features between samples and vertical overhangs/voids within a sampled column are not represented exactly. A failed or empty native query logs the asset name and reason and retains the full collider; it never silently removes collision. Failed fits are cached for that template's lifetime. Templates are not mutated. Changing native collision fidelity/import geometry requires a fresh server to resample.

After Rojo sync, start a fresh Studio Play session (no place recompilation required):

1. Place each profiled Forest rock and enable Solid. Verify a tank can pass empty corners but cannot cross visible rock volume. Repeat with yaw 37/90 degrees, scale changes, elevation and tilt. Inspect WorldObstacleHitbox children if native query fidelity differs from visible geometry; watch for the fitting fallback warning.
2. Snap a builtin bridge piece onto a rock surface and imported building wall/roof below its bounding-box top. The contact marker should stay on the actual surface. Check imported source assets can start Snap while Stretch is selected; the editor switches to Scale. Confirm four side handles, pinned contacts, undo/redo and optional grid behavior remain usable.
3. Select an object with an invisible helper far outside its mesh. Selection, grounding and rotation pivot should exclude the helper. Confirm legitimate visible multipart buildings retain their complete visual bounds.
4. Drive over builtin ramps and raised bridges, beneath elevated decks and along imported building/platform edges. Verify support is not lost; fire airborne Gatling shots above a bridge and confirm leveling uses that bridge surface.
5. Export/reload a world with rotated/scaled rocks and buildings. Join with two clients and verify matching scenery, blocking, damage/destruction and reset. Test several dozen rocks to assess native startup sampling and contact cost on target hardware.

Automated tests exercise numeric transforms, analytic irregular mesh query hits, the actual fitting adapter/cache cleanup, production scene/controller snap routing and the existing contact/support/projectile systems. They cannot validate Roblox's native mesh decomposition or rendered pixels. Roblox documents WorldModel spatial queries separately from simulation: https://create.roblox.com/docs/reference/engine/classes/WorldModel.

Structural tank support now intersects complete chassis footprints with these compound cells instead of relying on center/cross samples. See [Footprint support](FOOTPRINT_SUPPORT.md) for seam, cliff and uneven-surface behavior and validation.

Forest/rocks-ramp now uses an opt-in source GLB terrain face profile instead of a full box. See [GLB terrain collision](GLB_TERRAIN_COLLISION.md) for real terraces, climbing limits and Studio checks.

The enabled [bulk collision generator](BULK_ASSET_COLLISION.md) now supersedes those per-asset mesh profiles for imported models with supported source GLBs, including buildings, bridges and fences. Existing builtin colliders are retained.

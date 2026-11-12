# Tree and curved-fence Studio asset test

This milestone extends the existing Studio world selector, not a second world loader. It places the central tree and a curved ring of repeated fence panels, with uniform scale and degree rotation. Each clone is grounded independently. No GLB bytes are parsed by BattleWorks.

## Prepare the world (already generated in this checkout)

```sh
node tools/build-world.js worlds/tree-test.json --output build/worlds/tree-test.json
node tools/register-worlds.js build/worlds
rojo serve
```

The checked-in Rojo catalog contains `tree_test` / **Kenney Tree Test** with status `asset-dependent`. The default arena and Village Battle registrations are retained.

## One-time Studio import/export

No Studio session/import/upload tool is connected to this coding environment; the GLB has **not** been imported or uploaded automatically.

1. Open your BattleWorks place in **Edit mode** and sync Rojo.
2. Choose **File → Import** and select `GLBs/suburban/tree-large.glb`. Keep its sibling `Textures` directory available.
3. In the importer, keep **Import Only As Model** enabled, **Merge Meshes** disabled, and **Scale Unit = Studs**. Keep **Add to Workspace** enabled. For saved/published reuse, leave **Upload to Roblox** enabled and choose the experience's appropriate creator/owner. Check the preview and import messages, then click **Import**.
4. In Explorer, rename the imported top-level **Model** to exactly `tree-large`. Keep its complete nested meshes/materials. No PrimaryPart or manual pivot edit is needed. If you have a bare MeshPart instead, group it into a Model first.
5. **Move**, rather than copy, that Model into `ServerStorage → BattleWorksAssets`. Do not leave an extra tree in Workspace.
6. Before rebuilding, follow [the persistence workflow](ASSET_PERSISTENCE.md): save the Model once as `assets/roblox/tree-large.rbxm` (or `.rbxmx`), verify with `node tools/build-place.js --check`, and keep the original place as a backup until the reconstructed build is verified. The mounted source model is then included in every clean build. Saving only the Studio place is insufficient. If already imported, export that existing Model; do not reimport the GLB.

Reference: [Roblox Importer](https://create.roblox.com/docs/studio/importer). Materials, upload permissions and mesh appearance require manual confirmation.

## Select and play

Set `ServerStorage → BattleWorksStudio → SelectedWorld.Value` to **`tree_test`** in Edit mode, then press Play. Output should report **Active world: Kenney Tree Test [tree_test]**. Inspect `Workspace.Arena.WorldScenery.tree-large`: it is the central tree clone; its reusable template stays in ServerStorage. The fence panels are siblings in WorldScenery.

The test keeps the floor, boundaries, tanks, controls, networking and combat simulation. It omits generated rocks/logs/trees, terrain patches, wind/ice and practice targets. Reset Battle and map redraw do not duplicate the placed tree. Choose `default` to restore the complete existing test arena. A missing/unusable template reports the expected import path and uses that full default arena; no substitute model is created. Production ignores these Studio selections as before.

## Change placement, not the imported model

Edit `worlds/tree-test.json`, then rerun the two Node commands above and sync Rojo before the next Play:

```json
{
  "id": "tree-large",
  "ref": "tree_large",
  "position": [0, 0, 0],
  "rotation": [0, 45, 0],
  "scale": 4
}
```

`position` is the world **base anchor**, not the imported pivot/geometric center: X/Z center the rotated bounds, Y sets their bottom. Rotation is XYZ degrees using the existing compiler's order. Scale is uniform relative to the imported template (the multiplier is authored in `worlds/tree-test.json`), preserving original proportions. Native [Model scaling and bounding methods](https://create.roblox.com/docs/reference/engine/classes/Model) operate on the clone, leaving the source unchanged. Bounds grounding uses part bounding boxes, not mesh vertex/trunk analysis; verify visually with the actual import.

`ref: "tree_large"` is the logical asset identifier, defined independently in `worlds/definitions/kenney.json`. Its `asset` is the source path `GLBs/suburban/tree-large.glb`. The template binding is separate in `worlds/roblox-assets.json`; the binding resolver accepts either logical ID or source path. A model definition or instance asset override can reference that same source path directly. Imported geometry is never generated from the path string.

## Deliberate limits and verification

Up to 512 mapped model placements per world and uniform positive scale are supported. Shear/nonuniform scales and unmapped resources stay preview-only. Fixed trunk collision and weapon durability are now supported through the narrow [imported-object profile](IMPORTED_OBJECTS.md). The mesh remains cosmetic; a server-owned trunk proxy handles contacts, projectile hits and scanner occlusion. Pushing/tipping and general physics profiles are not implemented.

Automated coverage: source/logical asset resolution, one-object registration, transform extraction, bounds grounding with offset pivots/rotations, relative uniform scaling, template immutability, single-clone lifecycle, selector activation and missing/invalid asset fallback. Model operations are numerical doubles, not proof of native mesh rendering. **Still manual:** actual GLB import/materials, visual size/base contact, Edit-mode save/Play persistence and live tank controls in Studio.


## Curved fence and world asset scale

`worlds/tree-test.json` now sets `"assetScale": 45` once for all model assets.
The central tree and panels inherit that scale without per-object scale entries.
It is applied by the offline compiler at each model leaf, exactly once; positions,
path coordinates and spacing remain in world studs. Optional local `scale` still
multiplies this conversion (for example `scale: 0.5` becomes 22.5).

`worlds/definitions/kenney.json` defines `fence_section` using `fence.glb` and
`curvy_fence` as a closed cubic path. The current path yields nine tangent-aligned
panels around the tree, at 45-stud spacing. The panel's local X axis is assumed to
run along its length (`item.rotation` corrects it by 90 degrees for the path).
Adjust that rotation and spacing to your actual imported fence proportions; no
asset dimensions are guessed from GLB bytes. Fence panels are decorative for now;
the central tree retains its solid/destructible profile.

Import `fence.glb` once as a Model named `fence` in
`ServerStorage/BattleWorksAssets`, then export that model to
`assets/roblox/fence.rbxm` or `.rbxmx`, using the same persistence procedure as the
tree. The asset registry maps the symbolic file to this reusable native template.
No copying per panel is needed: the server clones it for all placements.

The existing selector reads the generated `Placements` folder; legacy single
`Placement` entries still work. Placement is staged before activating the world.
If either required model is missing or any placement fails, startup uses the
default arena with a diagnostic, rather than displaying a partial fence/world.
Validate the fence's scale, joins and orientation visually in Studio after import.

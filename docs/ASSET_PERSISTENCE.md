# Import once, keep Roblox models in the repository

## Import command

Use `tools/import-glb.js` for static scenery. It checks geometry before uploading, keeps the original GLB, verifies the uploaded Model's creator, and rebuilds the catalog with the Roblox asset ID. It refuses to replace an existing native asset.

Set `ROBLOX_API_KEY` in your local environment along with either `ROBLOX_GROUP_ID` or `ROBLOX_USER_ID` for the creator that owns the experience. The default workflow uses the Assets API for creation and metadata. Keep the key out of the repository. [Roblox Open Cloud Assets API](https://create.roblox.com/docs/cloud/guides/usage-assets)

```sh
# Source with embedded COLLISION_ nodes. Only the visual meshes go to Roblox.
node tools/import-glb.js Forest/new_bridge /path/to/new_bridge.glb

# Separate collision file. Export both from the same origin, units and orientation.
node tools/import-glb.js Forest/footbridge /path/to/visual.glb --collision /path/to/decks.glb

# Validate and write a visual-only GLB without credentials or a Roblox upload.
node tools/import-glb.js Forest/rope_bridge GLBs/forest/rope_bridge.glb --prepare-only /tmp/rope_bridge_visual.glb

# Package an existing Studio model export without uploading again.
node tools/import-glb.js Forest/rope_bridge GLBs/forest/rope_bridge.glb --native /path/to/rope_bridge.rbxm
```

For a cloud retry, reuse the original inputs with `--operation ID` or `--asset-id ID` from the command output. Both avoid a duplicate upload. `--download` opts in to packaging an RBXM/RBXMX through Asset Delivery and requires its separate `legacy-asset:manage` scope. [Roblox Asset Delivery authentication](https://devforum.roblox.com/t/creator-action-required-new-asset-delivery-api-endpoints-for-community-tools/3574403)

When the command reports **Registered**, sync Rojo and restart Play. The report shows `delivery: "roblox"` for an asset-ID reference. The server loads the model once per session under its catalog path, checks the experience owner and collision bounds, and strips non-visual instances before publishing it to the editor. The registered ID points at the current Roblox model version. Studio Output reports moderation, permission, or geometry failures if loading is rejected. Save the World Editor placement separately.

Native exports remain supported. If you save an RBXM directly in the repository, rebuild the catalog with `node tools/build-editor-catalog.js`. If live sync cannot apply the native mesh references, open a fresh Rojo build.

## Hide an asset from the object picker

```sh
node tools/delete-asset.js /Forest/Bridge
node tools/delete-asset.js /Forest/Bridge --apply
node tools/delete-asset.js "/Builtin/Shallow water" --apply
```

The command lists and counts repository worlds that reference the asset by world ID. It accepts built-in and imported assets, and allows case differences when the path is unambiguous. Use `--apply` to hide the asset. If any repository worlds use it, type `y` to confirm or press Enter to cancel.

Hiding preserves all asset files, collision data, and saved placements. Hosted worlds are outside the count and their placements are preserved too. Sync Rojo and restart Play to refresh the in-game picker. To make an asset visible again, remove its canonical path from the JSON list in the `Value` field of `assets/hidden-editor-assets.model.json`.

## Why the imports disappeared

Previously `ServerStorage/BattleWorksAssets` was only an empty Folder declaration in `default.project.json`. It had no filesystem `$path`. `$ignoreUnknownInstances=true` protected unknown Studio children during live synchronization; it did **not** export their data. `rojo build` reconstructs a place from project/files, not from a previously generated `.rbxl` or the open Studio session. Opening a fresh generated place therefore lost Studio-only imports. Additionally, the global `*.rbxm`/`*.rbxmx` ignore rules prevented source exports from being tracked.

The project now mounts **`assets/roblox`** directly at **`ServerStorage/BattleWorksAssets`**. Native `.rbxm` (binary, preferred) and `.rbxmx` (XML) are supported directly by [Rojo's native model support](https://rojo.space/docs/v7/sync-details/). No GLB parsing, mesh conversion, scripted property reconstruction, or runtime filesystem loading is involved. Git ignore exceptions allow these source files; generated places remain ignored.

## One-time export of existing imports — do this before discarding anything

**Bulk alternative:** individual exports are no longer required. Select one
enclosing Folder of imported Models, preserving its nested Folders, and save it
as `assets/roblox/assets.rbxm` (or `.rbxmx`). Run
`node tools/build-editor-catalog.js`, let Rojo sync and restart Play. This inspects
the binary with Rojo's sourcemap command and writes only catalog/path-index
metadata; it does not compile a game or reconstruct native geometry. Each Model
under a Folder becomes an independent asset; nested Models within that asset
stay together. The old individual-file workflow below remains supported.

1. Stop Play. Disconnect the Rojo Studio plugin while exporting/verifying. Keep the existing place/model intact and save a **separate backup place**, outside your generated build output. If your current generated place has already lost the tree, open a saved/recovered/published copy that still contains it.
2. Select **the imported Model itself** under `ServerStorage/BattleWorksAssets`. For the tree it must be named `tree-large`. Retain all its nested meshes, textures/materials, pivots, `PrimaryPart` and scale. Do not resize, regroup or flatten the hierarchy for this export.
3. In Explorer's context menu, choose **Save / Export → Save to File** (or **Save to File** in older Studio layouts). Save **`assets/roblox/tree-large.rbxm`** in the local repository Rojo uses. If choosing XML instead, save `tree-large.rbxmx`. This is a Roblox model save, **not** OBJ/glTF “Export Selection”. Export the Model, not its enclosing Folder.
4. For individual exports, save similarly named Model files under `assets/roblox`, retaining organizational subfolders. Alternatively, save all Models together in a Folder-root bundle. Keep **one format per export filename**, not both. Run the catalog builder after adding/replacing either kind of export.
5. Verify without touching the original Studio place:

   ```sh
   node tools/build-place.js --check
   git status --short --untracked-files=all assets/roblox
   ```

   All asset bindings must resolve to exported models. New source exports should appear as untracked/changed files rather than being ignored. Review/version-control them together with the project and binding changes using your normal Git workflow. Nothing stages or commits them automatically.
6. Build a **new** place path first:

   ```sh
   node tools/build-place.js --output build/battleworks.rbxl
   ```

   Open it separately in Studio. Check the template exists at `ServerStorage/BattleWorksAssets/tree-large`, compare its children, mesh/texture references, pivot and scale against the original, then select `tree_test` and Play. Verify materials, original proportions and grounding. **Keep the original place/imports until this comparison succeeds.** No tool in this workflow deletes the original Studio Model.

Export requires the real imported instance: no real RBXM/RBXMX export was present in the workspace when this fix was implemented. A read-only syncback inspection of the saved place here produced no model exports. Tests use synthetic native model data in temporary folders; no fake tree is shipped as a replacement.

## Normal rebuild workflow

Once native exports are in the repository, a clean checkout needs no GLB reimport or Studio asset recovery:

```sh
node tools/build-place.js --check
node tools/build-place.js --output build/battleworks.rbxl
# Optional XML place format:
node tools/build-place.js --output build/battleworks.rbxlx
```

The checked builder uses Rojo to validate native files and the resulting hierarchy before building to a temporary path and replacing the requested output. Missing bindings, corrupt exports, duplicate formats, wrong top-level types and empty/non-mesh models fail clearly. A failed check/build leaves an existing output untouched. Both native model formats are packaged directly; no export is rewritten.

Raw `rojo build` also packages the mounted files, but cannot warn that an unexported Studio-only model was expected. Prefer the checked command to prevent accidentally opening another empty-asset build. For intentional default-arena-only development/CI before exports exist:

```sh
node tools/build-place.js --check --allow-missing-assets
node tools/build-place.js --output /tmp/battleworks-default-only.rbxl --allow-missing-assets
```

This prints **ASSET NOT PACKAGED** for each missing export. It refuses to replace an existing output while exports are missing. The runtime's normal missing-model fallback remains intact; this option never fabricates substitute scenery.

`$ignoreUnknownInstances=true` remains on the asset folder to protect still-unexported Studio imports during migration. Source-backed names can be updated by Rojo once their files exist, which is why export verification should happen with the plugin disconnected. Live sync is not the archival step. In particular Rojo documents live-sync limitations for `MeshPart.MeshId`; use a new native place build as the reliable path for new/changed mesh exports. Opening a fresh build is now safe **after** those source exports exist.

## Asset definitions and references

- `GLBs/...`: original source art; not loaded at runtime and not converted by builds.
- `assets/roblox/tree-large.rbxm` **or** `.rbxmx`: persistent native template/hierarchy.
- `worlds/roblox-assets.json`: logical/source-path binding to template name `tree-large`.
- `worlds/definitions/kenney.json`: reusable tree definition.
- `worlds/tree-test.json`: placement, degree rotation and uniform scale; independent from the template.

For placement changes, compile/re-register the world as before, then build/open a new place. For model edits, edit a copy in Studio and export/verify the updated model file once. Rebuilds never require reimporting the original GLB. Filename/template names must agree with the binding, including case.

A freshly generated place starts with its default Studio world selection; set `SelectedWorld` to `tree_test` to display the tree. The persistent template is already packaged in ServerStorage, so this does not require reimporting it.

Native files preserve resource references and model properties; they do not make Roblox-hosted mesh/image bytes an offline archive or grant asset permissions. Confirm the mesh/texture resources are uploaded and accessible to the intended experience/creator. Appearance and cloud permissions still require Studio verification. Do not flatten native exports into JSON or manually reassign MeshIds to work around sync restrictions.

## Verification and scope

`node --test tests/asset-persistence.test.js` checks both native formats through the real Rojo executable, rebuilds after deleting generated outputs, and verifies mesh/texture/material IDs, hierarchy, `PrimaryPart`, pivot offsets, part transforms/sizes and model scale in built XML. It also checks source bytes remain unchanged, Git tracking exceptions, missing/corrupt/duplicate exports and prevention of destructive output replacement. This is native serialization validation, not a substitute for rendering the real exported tree in Studio.

The existing loader and `tree_test` selection/placement remain unchanged. No runtime download/import system, physics profile, source GLB parser or replacement asset is added. The remaining one-time manual work is exporting the actual Studio models and visually verifying the first reconstructed build; after that normal builds are automated.

## Hierarchical assets and the visual editor

Native exports may now be nested. Keep the same relative folder path on disk and
under `ServerStorage/BattleWorksAssets`; for example export
`Buildings/Houses/Fence` to `assets/roblox/Buildings/Houses/Fence.rbxm`. Basenames
need not be globally unique. Build checks walk recursively and resolve the full
path; they never flatten or rename models. See [canonical paths](ASSET_PATHS.md).

The [World Builder](WORLD_BUILDER.md) handles save, registration and selection.
Its repository-backed selected/published settings persist across builds. The
older instructions above to edit SelectedWorld manually are only a legacy
fallback; the editor provides Select/Test buttons. First-time native export and
asset permission/render verification are still Studio steps.

For automatic collision during GLB registration, use `--auto-collision`.
See [generator and batch import instructions](IMPORTED_ASSET_GEOMETRY.md#automatic-glb-collision-generation).

# Import once, keep Roblox models in the repository

## Why the imports disappeared

Previously `ServerStorage/BattleWorksAssets` was only an empty Folder declaration in `default.project.json`. It had no filesystem `$path`. `$ignoreUnknownInstances=true` protected unknown Studio children during live synchronization; it did **not** export their data. `rojo build` reconstructs a place from project/files, not from a previously generated `.rbxl` or the open Studio session. Opening a fresh generated place therefore lost Studio-only imports. Additionally, the global `*.rbxm`/`*.rbxmx` ignore rules prevented source exports from being tracked.

The project now mounts **`assets/roblox`** directly at **`ServerStorage/BattleWorksAssets`**. Native `.rbxm` (binary, preferred) and `.rbxmx` (XML) are supported directly by [Rojo's native model support](https://rojo.space/docs/v7/sync-details/). No GLB parsing, mesh conversion, scripted property reconstruction, or runtime filesystem loading is involved. Git ignore exceptions allow these source files; generated places remain ignored.

## One-time export of existing imports — do this before discarding anything

1. Stop Play. Disconnect the Rojo Studio plugin while exporting/verifying. Keep the existing place/model intact and save a **separate backup place**, outside your generated build output. If your current generated place has already lost the tree, open a saved/recovered/published copy that still contains it.
2. Select **the imported Model itself** under `ServerStorage/BattleWorksAssets`. For the tree it must be named `tree-large`. Retain all its nested meshes, textures/materials, pivots, `PrimaryPart` and scale. Do not resize, regroup or flatten the hierarchy for this export.
3. In Explorer's context menu, choose **Save / Export → Save to File** (or **Save to File** in older Studio layouts). Save **`assets/roblox/tree-large.rbxm`** in the local repository Rojo uses. If choosing XML instead, save `tree-large.rbxmx`. This is a Roblox model save, **not** OBJ/glTF “Export Selection”. Export the Model, not its enclosing Folder.
4. For each other imported GLB, save one similarly named model file directly in `assets/roblox`. Keep **one format per name**, not both. Each file must contain one Model with mesh descendants. Extra folder nesting would change the runtime lookup path and is rejected by the checked build.
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

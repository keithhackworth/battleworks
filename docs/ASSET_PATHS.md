# Canonical asset paths

World `asset` fields identify a **logical Model path in the asset library**,
using exact case and forward slashes:

```json
{"type":"model","asset":"Structures/Fences/Fence"}
```

For individual exports this identifies
`ServerStorage/BattleWorksAssets/Structures/Fences/Fence`. For bulk Folder exports,
the generated `__BattleWorksAssetIndex` maps the same logical path to the Model
inside its native bundle mount (for example `assets/Structures/Fences/Fence`).
It is not a Linux filename or a generated Workspace instance name. Another
`Buildings/Houses/Fence` can coexist without being merged or renamed. Qualified
paths are traversed segment by segment; lookup never falls back to a basename
when a qualified path is missing.

The registry may attach source provenance and collider defaults:

```json
{
  "rope_fence": {
    "model": "Structures/Fences/Fence",
    "source": "GLBs/forest/fence.glb",
    "collider": {"widthFraction":1,"depthFraction":1,"heightFraction":1}
  }
}
```

Registry keys are metadata identifiers; **worlds use the model path**. The GLB
source is not read at runtime. Existing root models (`tree-large`, `rope-fence`)
remain root-relative one-segment paths; no assets are moved automatically.
An exact root-level Model path takes precedence over legacy basename lookup, so
adding a bundle cannot invalidate an existing standalone root reference.
Legacy registered GLB paths, logical aliases and other basenames resolve only when
unambiguous. Ambiguous names identify the conflicting complete paths instead of
choosing the first model. Invalid paths (absolute, backslashes, empty segments,
`.`, `..`, whitespace-only segments or control characters) are rejected.

Native export layout mirrors Studio:

```text
assets/roblox/Buildings/Houses/Fence.rbxm
assets/roblox/Structures/Fences/Fence.rbxmx
```

Both are packaged at their original relative locations. A file may alternatively
contain one Folder root holding many Models organized in nested Folders. Run
`node tools/build-editor-catalog.js` to inspect binary/XML hierarchy with Rojo and
refresh both catalog and path index. Bundle filenames are physical mount names,
not logical prefixes; filesystem folders above the file remain logical prefixes.
Rojo receives the original bundle once. The index contains paths only, no geometry.
`.rbxm` and `.rbxmx` files cannot both define the same logical path. Duplicate full
paths fail rather than resolving arbitrary geometry. A Model is an asset boundary;
nested Models within it retain their hierarchy and are not duplicate palette items.
Rojo requires one top-level instance; select the enclosing Folder when exporting.

The World Builder also recursively discovers Models in the actual Studio asset
hierarchy on Connect and measures their bounds. Its authoring/export JSON stores
the canonical path in each object's `asset` field. Paths survive save/load and
portable export/import; referenced native models remain separate assets.
Built-in editor templates use the reserved `Builtin/` subtree of the same root.

The standalone offline compiler validates path syntax and can preserve symbolic
legacy references without installed geometry, as before. Callers that provide
`options.assetBindings` get strict missing/ambiguous reference validation and
canonicalized manifest paths. The editor adapter uses that strict mode. World
registration checks mappings, and the server checks actual Model existence;
missing assets produce explicit diagnostics and default-arena fallback.

Tests cover duplicate-basename discovery, real Rojo native packaging in nested
folders, strict compiler lookup, exact Luau traversal, invalid paths, legacy
unambiguous aliases, ambiguity errors, and JSON round-trip identity.

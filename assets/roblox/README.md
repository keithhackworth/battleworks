# Persistent Roblox models

Save Studio-native exports here. Both formats support either one Model or one
Folder containing many Models in nested Folders:

- `tree-large.rbxm` (preferred), or
- `tree-large.rbxmx` (XML alternative).

For bulk export, organize your imported Models in Studio, select their enclosing
Folder, and use **Save to File** to create `assets.rbxm` here. Then run:

```sh
node tools/build-editor-catalog.js
```

Let Rojo sync and restart Play. `assets.rbxm` containing `Trees/Oak` and
`Buildings/House1` produces separate palette entries at those paths, not a single
`assets` item. Hundreds of Models can share this one native file. Export the
enclosing Folder, not a multi-selection with several top-level roots (unsupported
by Rojo). Use only one RBXM/RBXMX format per export filename.

Rojo's sourcemap inspector reads the binary/XML hierarchy without rewriting it.
The builder generates catalog metadata plus `assets/asset-index.model.json`;
Rojo mounts that small index alongside the original native bundle. The shared
runtime resolver maps logical paths to physical bundle paths before cloning.
No geometry is flattened, converted or copied into generated per-asset files.

Do not add a placeholder model: the real one-time Studio export is required.
See [the persistence workflow](../../docs/ASSET_PERSISTENCE.md) for safe export,
verification and rebuilding. Keep existing Studio imports/backups until verified.

Nested asset folders are supported and must match Studio's hierarchy. For example
`Structures/Fences/Fence.rbxm` becomes
`ServerStorage/BattleWorksAssets/Structures/Fences/Fence`. The same basename in a
different folder is a different asset. A Model's nested Models remain part of that
asset; use Folders to organize independent assets. Duplicate full paths are errors.
Renaming a bundle file leaves its logical asset paths/IDs unchanged after rebuilding
the index. Existing individual filenames and registered IDs remain compatible.
The `Builtin/`
namespace is reserved for generated editor templates. See
[canonical asset paths](../../docs/ASSET_PATHS.md).

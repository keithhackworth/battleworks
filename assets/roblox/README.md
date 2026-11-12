# Persistent Roblox models

Save Studio-imported **Model** instances here, one model per file:

- `tree-large.rbxm` (preferred), or
- `tree-large.rbxmx` (XML alternative).

Use only one format per model name. Export the Model itself, not the enclosing
BattleWorksAssets folder. Rojo packages the files directly under
`ServerStorage/BattleWorksAssets`; no GLB conversion or reimport occurs on builds.

Do not add a placeholder model: the real one-time Studio export is required.
See [the persistence workflow](../../docs/ASSET_PERSISTENCE.md) for safe export,
verification and rebuilding. Keep existing Studio imports/backups until verified.

Nested asset folders are supported and must match Studio's hierarchy. For example
`Structures/Fences/Fence.rbxm` becomes
`ServerStorage/BattleWorksAssets/Structures/Fences/Fence`. The same basename in a
different folder is a different asset. Do not flatten folders. The `Builtin/`
namespace is reserved for generated editor templates. See
[canonical asset paths](../../docs/ASSET_PATHS.md).

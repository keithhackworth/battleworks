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

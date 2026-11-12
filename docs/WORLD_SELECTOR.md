# Studio world selection

The selector chooses a server-wide world at **Studio startup only**. It adds no player UI/remotes and ignores the development setting outside Studio. It supports the existing built-in arena plus the narrow [single imported tree test](TREE_ASSET_TEST.md). Other compiled worlds remain **preview-only**; no placeholder models are created.

## Build, discover and sync

```sh
node tools/build-world.js worlds/example.json --output build/worlds/example.json
node tools/register-worlds.js build/worlds --output worlds/studio-worlds.model.json
rojo serve
```

The registrar discovers compiled `*.json` manifests, checks IDs/names and gathers resource/object counts. `worlds/roblox-assets.json` binds logical IDs/source paths to manually imported models. A supported single-model manifest embeds one placement configuration in the catalog; it becomes available only when the named model can actually be cloned. It writes a small Rojo JSON model catalog (not the scenery itself). Existing IDs must be unique; `default` is reserved. `worlds/studio-worlds.model.json` is checked in so a fresh Rojo build already lists the built-in arena, Village Battle and the asset-dependent Kenney Tree Test, even before regenerating outputs. Rebuild the catalog when adding/removing/changing manifests. Registry/CLI failures do not replace a valid catalog with partial results.

## Choose without changing Luau source

In Studio **Edit mode, before Play**:

1. Sync the Rojo project.
2. Open Explorer → **ServerStorage → BattleWorksStudio**.
3. Expand **WorldCatalog** to inspect available world IDs, display names, status/reason, manifest source and asset/object counts.
4. Select **SelectedWorld**, a StringValue, and edit its **Value** in Properties.
5. Use `default` or an empty value for **Default Test Arena**. Use `village_battle` to exercise the registered preview-only fallback.
6. Save the place, then Play. Stop before changing selection for the next session.

An alternative is the Studio **Edit-mode** Command Bar:

```lua
game.ServerStorage.BattleWorksStudio.SelectedWorld.Value = "default"
```

`SelectedWorld.Value` is deliberately not owned by a `$properties.Value` entry in the Rojo project. Your Edit-mode value remains in the place across Play/Stop and can be saved with it. Changes made inside a running simulation are disposable Roblox Play changes and do not select the next session. Rebuilding/opening a fresh place starts with the default empty selection. Native Studio persistence/Play tests remain necessary; unit mocks cannot verify Studio's edit/save lifecycle. Imported model data is different from this selection setting: save native exports in `assets/roblox` so fresh builds retain the models too; see [asset persistence](ASSET_PERSISTENCE.md).

## Diagnostics and boundaries

Startup logs list names/IDs and availability, then report the active name/ID. `Workspace.Arena` carries `WorldId`, `WorldName`, `RequestedWorldId`, `WorldSelectionStatus` and `WorldSelectionReason` in Studio. Every player uses this single server selection.

Choosing Village Battle logs its missing Roblox GLB mappings/loader and explicitly falls back to **Default Test Arena [default]**. An unknown ID, missing config or unavailable catalog entry also uses the existing arena. A catalog `ready` label cannot enable arbitrary scenery loading; only registered `asset-dependent` single-model placements are attempted. The requested Edit-mode value is retained, so diagnostics are repeatable next session rather than silently resetting your setting.

The existing environment builder creates the default arena. The opt-in tree test uses the same ground/boundaries with generated scenery/targets omitted and places one decorative imported clone. Tank spawning, battle reset, map resizing, networking, combat and server simulation remain unchanged. The per-player BW hardware panel is not used for global Edit-mode configuration. Production startup does not read Studio selection, log it or set development world attributes.

Files: `tools/register-worlds.js`, `tools/world/catalog.js`, generated `worlds/studio-worlds.model.json`, `default.project.json`, `src/server/StudioWorldSelector.luau`, `src/server/StudioAssetPlacement.luau`, and the Studio-only startup hook in `src/server/init.server.luau`. Tests cover offline discovery/registration and default, unavailable, malformed, unknown, repeated-session and production-ignore selection behavior. GLB import is manual; no full multi-object world loader is included. See TREE_ASSET_TEST.md for exact import and selection steps.

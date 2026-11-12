# BattleWorks world builder

## Architecture decision

The editor is a local Roblox Studio plugin, packaged using a separate Rojo project.
It edits a versioned **authoring document** (`schemaVersion: 2`) stored in
`worlds/builder/`. A Node built-in HTTP bridge bound to loopback writes documents,
compiles them through the existing v1 world compiler, regenerates the existing
Studio catalog, and persists the selection. No npm packages or new runtime
filesystem loader are required. A short-lived bridge token authorizes writes;
HTTP browser origins are rejected. Asset geometry remains in native Roblox
models, separate from world placement data.

The plugin uses the Studio viewport, Selection, Handles and ArcHandles. It owns
only a temporary preview folder and cleans it up before play. Studio remains
responsible for camera pan/orbit/zoom. Only the server selector loads gameplay
objects. The default arena and v1 compiler/definitions remain supported. Built-in
palette objects are native model templates, loaded through the same placement
helper as imports. Models are never synthesized from fictional GLB paths.

Authoring documents use catalog type IDs with per-instance transforms and
properties, plus explicit dimensions, ground appearance, and tank spawns. The
adapter resolves catalog entries into v1 definitions and instances; the v1
compiler still owns flattening, transforms and deterministic manifests. Every
save validates before touching source/generated files. Legacy registered worlds
can be flattened into editable instances; unsupported/unmapped worlds receive
specific errors rather than invented replacements.

## Boundaries

Initial runtime ground remains flat at Y=0, rectangular and 25–2000 studs per
side, matching the existing physics and camera. No fake drivable elevation,
terrain mesh generation, new weapons, or music is included. Ground appearance,
solid obstacles, imported models, spawns, and existing water/mud effects can be
configured. The document reserves a versioned gameplay metadata extension point;
unknown operational properties are rejected instead of silently applied.

Studio import/export of a **new mesh asset** remains a one-time native Studio
operation. The editor automatically discovers registered native assets and
built-in templates; no per-world asset copying is required. Publishing here means
registering and selecting a repository world for BattleWorks builds, not publishing
a Roblox place to a cloud experience without user approval.

## Implementation progress

See [the persistent checklist](WORLD_BUILDER_CHECKLIST.md). Native Studio actions
are not considered verified by CLI builds or mock tests.

## Setup and daily workflow

One-time setup (no npm installation):

1. Sync/open the existing BattleWorks place using Rojo. In Studio, open
   **Plugins → Plugins Folder** to find its local plugin directory.
2. Install directly into that folder:

   ```sh
   node tools/install-world-builder.js --plugins-dir "/path/shown/by/Studio"
   ```

   On Windows/macOS the installer also offers a default when run without
   arguments; the folder shown by Studio is authoritative. On Linux with Studio
   on another machine or Wine, use the mounted Studio plugin folder. Alternatively
   build `rojo build world-builder.project.json -o build/BattleWorksWorldBuilder.rbxm`,
   insert it into Studio once and use **Save as Local Plugin**. Reload local
   plugins/restart Studio after installation or updates.
3. Start the development session:

   ```sh
   node tools/world-builder.js --studio
   ```

   This regenerates built-in templates/world registrations, starts the local save
   bridge on `127.0.0.1:34873`, and launches `rojo serve`. If Rojo is already running,
   use `node tools/world-builder.js` without `--studio`. Leave the bridge running.
4. Open **BattleWorks → World Builder**, click **Connect**, and grant the plugin
   permission to access this loopback endpoint if Studio asks. The runtime game
   does not make HTTP requests. With Studio on a different host, forward this port
   to Studio's machine and keep the plugin URL as localhost; do not expose the
   bridge publicly. `BW_BUILDER_PORT` changes the port if necessary.

Daily editing:

- Open **Builder Demo** to try built-in objects immediately without GLB imports,
  or enter a new ID/name and click **New world**.
- Click a palette entry then click the viewport, or drag from the palette into
  the viewport. Escape cancels. Objects rest on the ground automatically.
- Select with click/Shift-click. Drag on the ground or choose Move, Rotate or
  Scale handles. Properties provide exact X/Z, yaw and scale, collision,
  destructibility and HP. Spawns are selectable markers with editable headings;
  they cannot be deleted accidentally. Grid snapping and undo/redo are editor
  controls. Keyboard shortcuts are implemented but need native Studio validation;
  the corresponding buttons are always available.
- **Frame world** sets an overhead view. Use Studio's standard mouse camera
  controls for pan, orbit and zoom.
- **Save + register** writes source, manifest and catalog. **Select this world**
  also persists the development selection. **Test World** saves/selects and calls
  StudioTestService to start Play. If that API is unavailable in your Studio
  version, the message explicitly tells you to press ordinary Play/F5; the world
  is already saved and selected.
- Stop normally in Studio. Editing is disabled during both Play and pause. The
  editor's document remains available and its preview is rebuilt on return to
  Edit mode. A local draft is also stored through plugin settings; use **Restore
  last unsaved draft** after a restart. Repository saves remain the source of truth.
- Change the world name and Save to rename it. To create an independent world,
  enter a new World ID/name and use **Duplicate world**. Existing IDs cannot be
  overwritten by duplication or import. Deletion requires typing the exact ID.
- **Export portable JSON** writes `build/world-exports/<id>.json`. **Import world
  JSON file** opens a native file dialog and registers the imported document.
  The file contains references, not native mesh bytes; recipients need the same
  asset hierarchy. Legacy v1 worlds are listed as **Import copy** and flattened
  into a new v2 document, preserving the original source.
- **Publish world for repository builds** explicitly sets the server-wide
  production choice. It refuses missing native exports. This does not upload a
  place to Roblox. Development selection and published selection are independent.
  With neither configured, the original arena remains the default.

The bridge and registration pipeline have automated tests. Installation, native
mouse/handle interaction and the actual StudioTestService Play/Stop lifecycle
still require the manual acceptance procedure below.

## Asset names: one canonical identity

An asset is identified by its **complete path relative to
`ServerStorage/BattleWorksAssets`**, with forward slashes and exact case:

```json
{
  "id": "fence_1",
  "type": "asset.example_catalog_id",
  "asset": "Structures/Fences/Fence",
  "position": [0, 0, -30],
  "rotation": [0, 90, 0],
  "scale": 45,
  "solid": true,
  "destructible": false,
  "hp": 100,
  "bounds": [1, 1, 0.1]
}
```

`asset` is the identity that survives export/import. `type` holds catalog defaults
and behavior; the adapter resolves old catalog IDs through the asset path when
possible and rejects conflicting references. The editor generates these fields;
users do not need to type them. The palette and property panel show the full path.
`bounds` is measured from the unscaled native template, used for offline placement
validation; runtime spawn checks use the actual loaded collision boxes too.

`Buildings/Houses/Fence` and `Structures/Fences/Fence` are distinct, supported
assets. Their identical basenames are never merged. Paths are traversed folder by
folder; a missing qualified path does not trigger a global basename search.
Legacy bare names and registered GLB source aliases remain supported only when
unambiguous. Ambiguous references list valid complete paths. Empty segments, `.`,
`..`, absolute paths, backslashes and control characters are rejected.

Native exports are discovered recursively under `assets/roblox`. For example:

```text
assets/roblox/Buildings/Houses/Fence.rbxm
assets/roblox/Structures/Fences/Fence.rbxm
```

Rojo preserves these folders under BattleWorksAssets. The exported Model itself
is the file root; do not export a flattened combined asset folder. Mesh references,
textures, pivots and hierarchy remain native Roblox serialization. The plugin's
Connect action also discovers the actual Studio hierarchy and records template
paths/bounds automatically. Built-in shapes live in the reserved `Builtin/`
namespace under the same root.

A newly imported GLB still needs a one-time native export to its corresponding
repository path. This implementation uses Studio's file-selection/read APIs and does not reconstruct
RBXM/XML or mesh bytes. Native model export remains a one-time Studio operation. Once exported, builds and per-world
placement require no copying/reimport. Existing Studio imports are never deleted
or overwritten by this tool. See [asset persistence](ASSET_PERSISTENCE.md).

## Format, validation and limits

Sources: `worlds/builder/<world-id>.json` (`schemaVersion: 2`). Fields:
`id`, `name`, `description`, `settings`, `objects`, `spawns`, and reserved `gameplay`.
Settings contain width/depth in studs, boundary=true, and ground material/RGB.
Exactly one Boomer and one Rattler spawn are required. Headings use world compass
degrees; object yaw uses the existing Roblox Euler convention. Models have
per-instance uniform scale (not an additional implicit global multiplier in v2).
When importing v1, resolved global/local scales are retained.

Saves reject malformed fields, duplicate IDs, unknown assets, nonfinite values,
unsupported elevation/tilt, out-of-bounds footprints, invalid ground, overlapping
spawns, and spawns intersecting solid obstacle bounds. Validation does not silently
move authored objects to make a bad layout valid. The server independently checks
spawn safety using loaded colliders. Additional local player pairs receive
separate nearby spawn rows. Reset restores authored poses and destructible objects.

The first release caps worlds at **512 objects**, bridge requests at 2MB and Studio
catalog discovery at 2048 models. Undo history is capped at 100 operations; palette
previews at 24 live thumbnails. The editor updates selected objects during dragging,
not the entire scene each frame. Static runtime collision still uses the existing
contact solver; large-world native performance must be measured in Studio before
raising limits. This is not yet a thousands-of-objects release.

Ground is flat and boundaries rectangular because the current tank physics relies
on that contract. Bridge/road objects in the palette are flat decorative surfaces;
they do not create elevated drivable decks. Water/mud patches use the existing
slowdown/ripple/splash system. Ground material alone changes appearance, not
traction or gravity. Appearance customization currently covers ground and catalog
model defaults; arbitrary mesh recoloring and per-object material overrides are
not implemented. No mesh sculpting, arbitrary hazards, new physics or music.

## Exact manual Studio acceptance test (not yet executed here)

1. Install/reload the plugin, connect Rojo and the bridge, then Connect in Edit mode.
2. Open Builder Demo; verify all three built-in objects and two spawn markers.
3. Create another world. Place a block, tree/crate and water patch. Drag them,
   rotate/scale with handles and properties. Check snapping on/off and Shift-select.
4. Duplicate/delete multiple objects, then undo/redo and cancel a drag with Escape.
5. Move spawns into an obstacle; Save must identify the unsafe spawn. Move them
   clear, set dimensions and ground appearance, Save and reopen the saved world.
6. Export it, import under a new unique ID, and verify transforms and asset paths.
   Confirm duplicate IDs do not overwrite an existing saved world.
7. Select/Test it. Verify the chosen map dimensions, ground, spawns, normal manual
   and BW controls, solid objects, tree/crate damage, scanner object detection and
   Reset Battle. Stop; verify the edit document/preview survives.
8. Restart Studio/bridge and reopen the saved world. Verify repository persistence
   and optional local draft restoration independently.
9. Add two imported models named Fence in different folders. Connect again; both
   must appear separately. Save/export/reimport both, test exact lookup, then try
   ambiguous bare `Fence` in a legacy fixture and expect a clear error.
10. Export native meshes once; build both place formats, reopen without the bridge,
    and verify geometry/textures/pivots. Publish a built-in world and test a server
    without Studio development selection. Test with multiple players; all must
    receive the same world, with separate safe spawn rows.


API references used: [Studio file import](https://create.roblox.com/docs/reference/engine/classes/StudioService),
[plugin widgets](https://create.roblox.com/docs/reference/engine/classes/Plugin),
[Studio playtest API](https://create.roblox.com/docs/reference/engine/classes/StudioTestService),
and [RunService edit/play state](https://create.roblox.com/docs/reference/engine/classes/RunService).

# BattleWorks World Editor

Open **Main Menu → World Editor**. No Studio plugin or loopback bridge is needed
for authoring. **← Main Menu** returns home; the draft and undo history stay in
this client session. The existing Studio plugin is retained for compatibility.

The editor starts with a 230 × 230 world and a flat base floor. It uses the
existing catalog, authoring-v2 JSON document, native model placement math, and
compiler/export pipeline. It never edits the running arena.

## Mouse and keyboard workflow

1. Browse the **Object Library** in the bottom dock. Click directory tiles to
   drill into the actual asset hierarchy, and **↑** to go up. Leaf tiles show
   native 3D thumbnails. Search finds names and complete paths across folders. **Recent** shows the last 12 placed asset types;
   Next pages through up to 24 entries at a time.
2. Drag an asset tile onto the terrain and release. A translucent green preview
   follows the cursor. Red means the placement is invalid. Alternatively click
   a tile to arm it, then click the ground. Each successful placement creates a
   separate instance and selects it. **Repeat** leaves the asset armed for more placements. Escape cancels an armed placement.
3. Click an object to select it. In **Move**, drag its body freely on the ground
   or use the red X / blue Z anchors. The green **Y** anchor raises/lowers it.
   In **Rotate**, choose **Tilt X**, **Yaw Y** or **Tilt Z** on the left and drag
   that colored ring. In
   **Scale**, drag the green diagonal anchor to resize uniformly. The wire box
   shows selection; invalid live transforms turn red and roll back on release.
   Handles have a small pixel hit margin and take priority over object bodies.
4. Use **Duplicate**, **Delete**, **Undo** and **Redo** in the UI. Exact X/Y/Z, pitch/yaw/roll,
   uniform scale and HP are editable in the right-side property inspector.
   Collision, destructibility, canonical asset identity, collider fractions and
   catalog water/mud slowdown properties are shown there too.
5. Grid snapping starts **OFF**. Toggle it and choose 0.1–50 studs when useful.
   Rotation snaps to 15° when grid snapping is enabled. The visual grid shows
   bounded major lines on fine grids; snapping still uses the exact entered size.
6. Right-drag orbits down to eye level. Middle-drag or Shift+right-drag pans.
   WASD moves across the scene, Q/E lowers/raises the camera, and Shift increases travel speed.
   Scroll over the viewport to zoom toward the cursor. **F** focuses the selection,
   **Home** frames the entire world, and the inspector controls mouse sensitivity.
   Use **Tools**, **Inspector**, and **Object Library** to make more space for the viewport.

Shortcuts: **1** Move, **2** Rotate, **3** Scale;
**Ctrl/Cmd+D** duplicate; **Delete/Backspace** delete; **Ctrl/Cmd+Z** undo;
**Ctrl/Cmd+Y** or **Ctrl/Cmd+Shift+Z** redo; **G** toggle snapping.
Shortcuts yield to focused text fields. Roblox's own Escape menu is preserved.
Opening CoreGui or losing window focus cancels
an active gesture. Every complete drag is one undo action, not one action per frame.

The inspector shows local dimensions for all placed assets and allows axis resizing
for stretchable native blocks. Imported assemblies retain uniform scaling.
The editor remembers the last edited scale for each asset during the session.
**Copy scale** and **Apply copied scale** transfer the uniform multiplier between assets.

**Open**, **Save**, **Save As**, and **Save & Play Test** use the existing server
world service. **New World** is undoable, and opening a world puts the
previous draft one Undo away. Change width or depth in **World Settings**.
The editor rejects a reduction that would cut through an object or starting area.

The document and compiler still use rectangular bounds. Terrain brushes edit elevation within
those bounds. Boundary shapes and editable river paths are separate milestones.

## Sculpt and play-test terrain

1. Open **Main Menu → World Editor** and choose **New World**. Set width and depth before sculpting.
2. Choose **Terrain → Raise Terrain**. Move the orange footprint over the ground and drag to form a hill.
3. Choose **Lower Terrain** and drag beside the hill. **Smooth Terrain** blends nearby heights. **Flatten Terrain** brings the brush area toward the inspector’s chosen elevation.
4. Set **Radius**, **Strength**, and **Falloff** in the brush inspector. A falloff of zero gives an even brush. Higher values soften the edge. Each drag is one Undo or Redo action. Escape cancels a stroke.
5. **Save**, then **Open** the saved world to restore the terrain. Place five start zones on relatively level ground before selecting **Save & Play Test**.
6. In Studio, run the playtest in **Classic** using **ServerStorage → BattleWorksStudio → GameMode**, then drive up the hill and into the depression. Published private playtests use the existing saved-world travel flow.

Terrain is an optional height grid in the existing world document. Each axis uses 4–36 cells and heights are stored in eighth-stud increments between −96 and +96 studs. The editor updates only changed chunks during a drag. The playtest uses the same triangulated surface for tank height and slope, with native queryable ground parts for character collision, scanners, and projectiles. Legacy worlds without terrain retain their flat floor. The grid supports one elevation per horizontal point. Vertical caves, overhangs, and river tools are outside this milestone.

### Terrain Traversability

Turn on **Terrain Traversability** in the Terrain inspector. The overlay uses the same uphill grip calculation as the simulation. Green means both drivetrains have a useful uphill reserve, yellow means tracks have the reserve, and red means neither can reliably climb. It reads the ground material and covers sculpted terrain and solid single-block ramps. Multipart and irregular assets may have no overlay. The colors estimate uphill performance with an operational drive and leave local footprint support, crest clearance, momentum, steering, and bus power to the simulation.

On an incline, the drivetrain spends grip countering downhill gravity before it can accelerate, brake, or turn. Tracks retain useful grip through steeper grades. On level ground the existing propulsion and grip budgets still apply. The provisional dry-grass tuning gives both drivetrains useful grip at 15°, favors tracks at 32°, and causes both to slide back at 44°. The 55° support ceiling on constructed faces is a geometric safeguard. Heightfield movement also rejects abrupt or wall-like rises while allowing downhill movement and falls.

For a live Studio check, make slopes near 15°, 32°, and 44° using both sculpted grass and placed ramps. With comparable drivetrain allocations, drive both tank types uphill, coast and brake downhill, stop halfway up, and turn across the incline. Check seams, raised-deck clearance, and falling at a gap. Reload the same save, then profile a session with 30 tanks to check the server accumulator and contact timings.

## Ramps and raised bridges

- Browse **Builtin → BW_bridge** (**Bridge / ramp deck**). New deck placements
  default to SOLID; existing saved decorations keep their old collision setting.
- Choose **Move** and drag the green vertical handle, or enter **Height Y** in
  the properties panel. This is the height of the object's lowest visual point,
  so Y=0 rests it on the floor even when tilted. Negative heights can bury part
  of an object; the full object must stay between -2000 and 2000 studs vertically.
- Choose **Tilt X** or **Tilt Z** to slant it. For an easy first ramp, use a bridge
  deck with **Tilt X = 15°**, **Yaw = 0°**, **Tilt Z = 0°**, and **Height Y = 0**.
  A second level deck raised to about **6.2** studs can meet its upper end.
  Align the ends in X/Z, then duplicate/reverse a ramp for the other side.
- Numeric rotation fields and saved documents retain the existing Rx × Ry × Rz
  Euler format. Handles rotate around the object’s actual local X/Y/Z axes,
  composing the orientation before writing equivalent Euler angles. At 90° yaw,
  multiple numeric fields may change together even though only one local axis
  is being turned; the handles remain distinct and follow the object. Snapping
  remains optional and rounds rotation to 15°. If a ring is edge-on to the
  camera, orbit slightly or enter its numeric angle.
- **Collision: SOLID** is required for tank support; NONE stays decorative.
  Save & Play uses the same server simulation. Structurally reachable upper faces can
  support tanks, with a maximum 1.5-stud step. Tall ends/sides remain obstacles.
  Tanks can drive underneath a raised deck if their hull has enough clearance.
  Destructible decks lose support on destruction; normal reset restores it.
- Native asset registry boxes remain the collision/support approximation. Complex
  meshes, arches and irregular undersides do not gain triangle-mesh physics.
  Tilted obstacles use conservative planar bounds for side contacts. Keep ramps
  wide enough for the tank, join ends closely, and validate crossings in Studio.
  Water/mud region assets must remain level at Y=0; their ground-zone behavior is
  preserved. Spawn markers remain on the base floor.

Height and tilt survive selection, dragging, duplication, undo/redo, Save/Open,
Save & Play and JSON export. Existing Y=0, yaw-only worlds remain compatible.


## Save and play without commands

Choose **Save & Play Test** on the editor toolbar.

1. Enter a world name and a World ID (letters first, then letters/numbers/underscores/hyphens).
2. **Save** stores the current layout privately. **Save & Play** saves, validates,
   then launches it through the existing simulator.
3. Use **Open** on a saved row to restore it for editing. Undo can restore the previous draft.
   Open an existing save before updating
   it; change World ID to create a separate slot. Refresh lists your saved worlds.
4. Return with the battle HUD's **Main Menu**, then open World Editor to continue
   your draft. In a private battle server, Play BattleWorks re-enters that world.

The default provider stores up to **10 private worlds per player** in the
BattleWorks HTTP service at `https://groupboard.app/api/battleworks/v1`, hosted
by the existing GroupBoard API. Studio and live worlds have separate durable
namespaces. See [HTTP setup and backup transfer](HTTP_WORLD_STORAGE.md). Each world is limited to 512 objects and
260 KB of JSON; all slots together are limited to 3 MB. Successful saves receive
revision numbers. Stale saves cannot silently overwrite another session's changes.
Storage/launch failures appear in the panel; failed saves are never called durable.
Saves happen when requested, not automatically on exit. No Linux server commands,
repository changes or plugin installation are required from players.

Published Play creates a fresh reserved server of the same place. The destination
loads the saved owner/revision from server storage, validates again, installs the
world, then acknowledges normal battle admission. Teleport data contains references,
never geometry, code or damage claims. The public server's battlefield stays intact.
Names/documents are private; this does not publish a world to a public catalog or
add invites, matchmaking or collaborative authoring.

**Studio now saves durably through HTTP**, after one-time Allow HTTP Requests
and Local Secret setup. Save & Play still tests locally only when every client
has left combat; otherwise it explains that the battlefield is occupied. Live
servers use a separate secret/namespace and load their saved world through the
same service. Missing credentials or outages leave the draft intact and report
an error, never silent temporary storage. Explicit Session/DataStore providers
remain available for old fixtures and existing Roblox saves.

For shared cloud **Team Test**, enable the explicit server configuration under
`ServerStorage/BattleWorksStudio`: `TeamTestMode=true`. For user-owned experiences,
`TeamTestHostUserId="0"` chooses the experience owner; for group-owned experiences,
set it to the hosting person's numeric Roblox user ID. The provider must be Http.
Configure **BattleWorksStudioWorlds** in Creator Dashboard Secrets using the same
Studio key as Local Secrets, scoped to **groupboard.app**. Local Secrets alone are
not available on the cloud test server. Ensure the current code/configuration is
published/committed to the shared test, then restart Team Test. Local Rojo sync
alone does not update a running cloud server.

Both players initially stay at the main menu. The host's My Worlds library shows
**TEAM TEST • Your Studio saves**. The host opens a save and uses Save & Play to
install it into that shared server. Collaborators then use Play BattleWorks.
Only the host can access saved-world RPCs; collaborators can join the installed
battle without access to the host's private save library. The mode is disabled
by default, refuses public servers, and must be disabled for ordinary published
play. Ordinary reserved saved-world launches retain owner-only admission.

Save diagnostics appear in server Output as **[BattleWorks worlds]**. Startup
records raw IsStudio, the runtime TeamTestMode flag, private-server presence,
selected mode/provider, expected namespace, secret **name**, and secret-store
location. No secret value, Secret object, authorization header, request body or
response body is logged. Restart the server after syncing to get current startup
inputs; the Rojo file's values alone do not establish the deployed server's values.

`secret_missing` / `secret_lookup_failed` identify GetSecret failures and preserve
the Roblox exception. `secret_header_failed` is an AddPrefix failure after lookup
succeeded. These happen before any HTTP request. `http_disabled` is separate.
`http_transport` preserves the RequestAsync exception; `http_authorization` records
401/403 after successful secret retrieval. Backend errors record HTTP status,
backend code and returned message; invalid JSON/response contracts are distinct.
The client keeps these diagnostic codes instead of collapsing them to a setup
warning. Check these logs before changing secrets or switching namespaces.

Before the first world operation, the selected HTTP credential makes a read-only
`GET /health` call. Its server-reported namespace must match the configured mode;
otherwise `namespace_mismatch` blocks the world request. A missing/invalid health
namespace also blocks access. Successful verification is cached for that store.
There is no live/Studio fallback, save migration, credential rotation or save
deletion during this check.

**Before stopping an existing temporary Play session**, export and keep its JSON.
After source sync/setup/restart, paste it into the JSON box and click **Import JSON
(replaces draft)**, then Save. Invalid imports preserve the current draft. No
new game build or player-side server command is needed.

## Optional developer JSON export using the existing format

Choose **Export JSON**, enter a valid world ID/name, then **Generate / Select JSON**.
Copy with Ctrl/Cmd+C (or Ctrl/Cmd+A then C in the export box). The copy box may be
edited for convenience; this does not edit the layout until Import JSON is clicked. Generate restores the
validated layout JSON.

Save that text to `worlds/builder/<id>.json`, then run the existing build flow:

```sh
node tools/world-builder.js --build
```

This is the same version-2 authoring document consumed by
`tools/world-builder/document.js`, which adapts it through the unchanged v1 world
compiler. Objects retain their `id`, catalog `type`, full `asset` path, position,
yaw, uniform `scale`, `bounds`, `solid`, `destructible` and `hp`. Existing defaults
supply ground, boundaries and the two tank spawns. Water/mud catalog entries still
compile into the existing surface zones.

A representative object remains:

```json
{
  "id": "object_1",
  "type": "asset.oak",
  "asset": "Trees/Oak",
  "position": [12.25, 0, -40],
  "rotation": [0, 37, 0],
  "scale": 1.25,
  "solid": true,
  "destructible": true,
  "hp": 225,
  "bounds": [4, 12, 4]
}
```

`Trees/Oak` and `Decorations/Oak` remain distinct. Asset paths never acquire the
runtime replica prefix. The offline adapter remains the compiler for repository worlds. The online server
validates player worlds against measured native geometry; the client rejects invalid footprints, reserved-spawn intersections,
unsupported transforms, invalid numbers and conflicting identities before export.
After registration, select/test/publish through the existing world-selection
workflow. Exporting never changes a live battle's selected world.

## Catalog and native assets

`tools/build-editor-catalog.js` packages metadata from the existing
`tools/world-builder/catalog.js` into `assets/editor-catalog.model.json`, mounted
in ServerStorage. `node tools/world-builder.js --build` also refreshes it.
For new exports/registry edits, regenerate metadata and restart Play:

```sh
node tools/build-editor-catalog.js
```

Static thumbnails use folders in ViewportFrames; they allocate no physics worlds.

Bulk exports are supported by the same command. Organize independent asset Models
with nested Folders in Studio, select the enclosing Folder, and Save to File as
`assets/roblox/assets.rbxm` (or `.rbxmx`). Rojo 7 on PATH inspects the native binary
through `sourcemap --include-non-scripts`; Node never parses it as XML/JSON or
reconstructs geometry. The command updates both `assets/editor-catalog.model.json`
and `assets/asset-index.model.json`. The latter is mounted as the server-only
`BattleWorksAssets/__BattleWorksAssetIndex` StringValue. It maps logical paths such
as `Trees/Oak` to the native bundle mount `assets/Trees/Oak`.

The shared AssetPaths resolver follows this index for source lookup, runtime
placement and server validation. EditorAssetCatalog clones each individual asset
into its sanitized library using its logical path. Bundle containers are never
placeable. A Model's nested Models are retained within that asset; use Folders
to organize separate assets. Different full paths can share a basename. Duplicate
full logical or native paths fail before metadata is replaced. Rojo requires one
top-level instance per export, so export one containing Folder, not a multi-select
with several root Models. A corrupt export keeps the previous generated metadata.

Individual exports and registered IDs/paths stay compatible. Unique registered
bare names can resolve to bundled Models without rewriting saved references;
their palettePath follows the bundle's folders. Existing explicit root paths beat
legacy basename search. Bundled copies of the generated Builtin models are ignored
by the catalog; the original Builtin mount remains authoritative. No geometry is
unpacked into duplicate model files, no models are renamed, and renaming a bundle
file only changes the generated physical paths. Native mesh/texture permissions
and Rojo's existing MeshPart live-sync limitations still need Studio validation.

The server publishes a sanitized template library once at startup under
`ReplicatedStorage/BattleWorksEditorAssets`. It mirrors canonical folder paths,
measures real native bounds, removes executable/active effects, and disables
physical/query participation. ServerStorage source models are unchanged.
Missing models remain visible as unavailable entries; no substitute mesh is invented.
Built-ins work in this checkout. External GLBs still require the existing one-time
native import/export, valid mesh permissions and correct collider registration.
There is no new asset conversion pipeline.

## Architecture and multiplayer isolation

- `ShellWorldEditor` is a screen adapter to `WorldEditorController`. Entry requires
  menu/session state; the editor does not request battle admission.
- `WorldEditorView` owns the palette, thumbnails, toolbar, properties and export UI.
- `WorldEditorScene` owns a private ViewportFrame/WorldModel, ground, spawns, grid,
  native clones, placement ghost, selection wire geometry and 3D anchors. All
  editor queries go to that WorldModel or its analytic ground plane.
- `WorldEditorController` handles mouse gestures, camera navigation, keyboard
  shortcuts, validation/rollback, transactions and lifecycle cleanup.
- `WorldEditorState` is the existing plugin state/history implementation moved
  into Shared, with a thin compatibility wrapper in the plugin.
- `ModelPlacement` is the existing native placement implementation moved into
  Shared, with a reusable pose helper and the same server compatibility API.
  Gameplay and editor use identical grounding and relative uniform scaling.
- `WorldEditorDocument` covers the authoring contract and hierarchical browsing;
  `WorldEditorMath` handles private viewport rays, axis-plane drags and gesture transforms.
- `WorldObjectGeometry` shares oriented bounds, projected spawn clearance and
  upper-face support math. `WorldObjects` retains the normal damage registry and
  supplies live structure heights to existing Environment sampling. The existing
  planar solver skips step-accessible upper faces; standard suspension/gravity,
  movement, snapshots and hits retain server authority.
- `EditorAssetCatalog` publishes sanitized native templates.
- `WorldLibrary` owns the private save/open UI and ignores late responses after exit. JSON import reuses
  document validation and rebuilds its private scene before committing a replacement.
- `PlayerWorldDocument` validates the authoring schema on the server, replaces
  claimed bounds with native measurements, and adapts to existing placement specs,
  interaction fractions and water/mud zones. No compiler or gameplay rewrite.
- `PlayerWorldStore` retains per-user legacy DataStore slots;
  `HttpWorldStore` implements the same interface for authenticated HTTP persistence,
  and `PlayerWorldStorage` selects the explicit provider;
  `PlayerWorldService` validates/rate-limits List/Load/Save/Play/Bootstrap requests.
  The server derives ownership from the authenticated Player, never a payload.
- `installPlayerWorld` stages native scenery with ModelPlacement and WorldObjects,
  checks spawn clearance, and installs only into an empty battle. Published
  launches use server-generated reserved-server IDs. Admission remains explicit;
  existing movement, health, damage, controls and multiple tanks per player remain.
- Production camera framing now reads authoritative map dimensions; development
  resizing and client map overrides remain Studio-only.

No editor model enters Workspace, the server's object registry, collisions,
projectile queries or scanner allowlists. Live multiplayer keeps simulating with
its original authority, damage, collision and destructibility implementations.
The editor uses a separate camera and never changes Workspace.CurrentCamera.
Exit cancels gestures, disconnects all runtime listeners and destroys scene
geometry. Screen-local state stays available when returning to the editor.

## Proof-of-concept boundaries

- No public-world catalog, sharing/invites, collaborative editing, arbitrary JSON
  import or direct filesystem writes. Unsaved drafts remain client-session-only.
  There is no delete-save UI yet: reuse an existing World ID to update a slot.
- Single-object selection, XYZ position and rotation, uniform scale, at most
  512 objects and 100 undo steps. No terrain sculpting or movable/pushable props.
- Base-floor/dimensions/spawn editing is deferred. Visible spawn markers reserve
  their existing default areas; they cannot be accidentally selected/deleted.
- Collision and destructibility are editable export properties, not a second
  physics or damage simulation in the editor. Mesh shape/permissions and exact
  runtime interactions still come from the existing loaders.
- Desktop layout/interactions first. Touch/gamepad editor authoring and small
  screen layout are not complete; existing battle controls remain supported.
- Catalog templates are replicated once as a library. Very large catalogs may
  need a later on-demand strategy; thumbnails are paged and scenes are local.

## Automated verification

Verified: 80 Node tests, all 33 Luau groups, syntax compilation of 106 source
files, both Rojo place formats, the retained plugin build and whitespace checks.
Player-world suites cover 37 validator/storage/isolation assertions, 151 production
Studio integration assertions and 61 published-server integration assertions.
The editor runtime suite now has 55 assertions including save/open, launch
acknowledgment and stale-response isolation. The elevation suite now has 447 checks covering oriented bounds, both tanks traversing
a ramp/bridge/descent, underneath clearance, tall-end blocking, destruction and reset.
Existing gameplay, BW, physics,
world loading, damage and multiplayer suites remain in the full run.

## Native Studio acceptance

CLI/mock verification does not establish native viewport rendering/input success.

1. Open/sync the place and Play. Main Menu → World Editor must show an empty
   private ground and the right-hand library. Builtin tiles must have real 3D
   previews. Drill down/up and search; check duplicate basenames in different
   directories remain distinguishable by path.
2. Drag a tile into the ground and release; click-arm another tile then place.
   Check transparent cursor preview, red invalid feedback and two unique copies.
   Repeat near palette edges, toolbar, CoreGui/chat and reserved tank spawns.
3. Click/select and ground-drag. Drag X/Z anchors, rotation ring and scale anchor.
   Raise/lower with the Y handle and field, tilt with both rings/fields, then
   select the raised object again. Check resize grounding, pointer alignment with Roblox safe-area/top-bar insets,
   snapping OFF and ON, and middle/right camera gestures without jitter.
4. Undo/redo each placement and full drag once. Duplicate/delete and undo them.
   Edit X/Z/yaw/scale/HP and collision/destructibility. Enter invalid values or
   drag past a boundary: edits must roll back without losing history.
5. Choose My Worlds, name a layout, Save, reopen it, edit and Save & Play.
   After HTTP/Local Secret setup, check that the panel says Saved to world service. Drive into solid cover,
   shoot destructible objects, reset, and check water/mud slowdown. Return to the
   menu and editor, then reopen the save. Optionally verify JSON export still works.
6. Return to Main Menu while placing, dragging and editing a field. Re-enter:
   the draft should remain, with no duplicate input listeners or leaked geometry.
   Enter battle and confirm normal manual/BW controls and camera behavior.
   Drive both tank types over connected ramps/decks and underneath a high deck;
   shoot a destructible deck with a tank on it and verify falling/reset behavior.
7. Start two clients; enter battle on one and edit on the other. Editing, deleting,
   exporting or leaving must not move, damage, create or remove the other client's
   battle objects. Then test both battle clients normally.
8. Repeat with real imported nested models, unusual pivots/native scales, asset
   permissions and a moderately large layout. Inspect frame rate, thumbnail
   loading, selection visibility and first-join library replication.

### Picking coordinate regression

The v4 picking fix converts fullscreen mouse locations into the same core-safe
GUI coordinate space as `AbsolutePosition` before either panel hit testing or
viewport ray construction. The same conversion is used for palette drag start,
drop, camera drag and wheel hit tests. Projection and ray math both use the
viewport's actual size and vertical field of view. Visible gizmos have a minimum
10-pixel hit radius and are picked before model geometry; selection updates its
anchors immediately instead of waiting for the next render frame.

The production-controller regression uses a 58-pixel top-bar inset, an offset
viewport, and a geometry-based ray query double. It proves the old unadjusted ray
misses, then exercises reselecting an existing object and starting move/rotate/
scale handle drags using projected positions. Native Studio should still confirm
alignment at the user's window size and display scaling.

### Published Roblox acceptance (required before release)

1. Publish the synced source, join through Roblox, save a world, leave the experience,
   rejoin and Open it. Confirm name, hierarchical assets, transforms and properties.
2. Save & Play; confirm private-server arrival, automatic battle admission, correct
   dimensions/spawns, normal mouse/touch/gamepad/BW controls and server damage.
   Return home and back to the editor without held keys, duplicate UI or cameras.
3. Keep a second account in the original public battle while the first launches
   a saved world. The second player's world, tanks and combat must be unchanged.
   Each account must see only its own saves.
4. Verify save conflicts across sessions, missing asset rejection, cloud failure
   messages and both synchronous/asynchronous teleport failure feedback. A failed
   launch must preserve the saved world and leave the editor usable for retry.
5. Native viewport input, visual layout, Windows stability, HTTP credentials/storage and
   teleport behavior cannot be proven by the CLI mocks. The main-menu native
   selection crash workaround is preserved; no non-nil native menu focus added.

Roblox references: [Data stores](https://create.roblox.com/docs/cloud-services/data-stores),
[reserved servers](https://create.roblox.com/docs/projects/teleport-private-servers),
and [teleport limitations](https://create.roblox.com/docs/projects/teleport).

### Ramp support regression (live Rojo sync)

The board-to-platform support fix keeps the initial 1.5-stud reachability check,
then samples track heights relative to the surface actually supporting the tank.
Uphill track points are no longer rejected solely for being above the chassis's
step limit. A real footprint contact can support the opposite track over a narrow
board edge or short joint; when every contact leaves or the object is destroyed,
the existing gravity path takes over. Platform side contacts account for the
supported hull incline, and a small normal tolerance preserves boundary ramps with
native CFrame precision. These changes preserve underneath clearance and tall-end
blocking and do not introduce a second physics engine.

Regression tests cover gentle narrow boards, 0.35-stud platform joins,
per-tick support/pitch checks, both tank types, X/Z approach directions, and floating-point support tolerance.

With the Rojo plugin connected, sync the source and **stop/restart Play** once
(ModuleScripts are cached during a running session). Re-test the reported board:
climb slowly, stop midway, cross onto the platform, reverse, and try both tanks.
Also drive beneath the platform and shoot a destructible board. No newly compiled
place file is needed; game builds are intentionally skipped per user preference.

### Gatling shots on platforms

Gatling downward/leveling assistance now applies only during physical flight
(lift or upward velocity), following the installed weapon rather than tank name.
Grounded shots keep normal turret/barrel aim, including on raised decks. Hopping
shots aim/level relative to the tank's sampled support height instead of the arena
floor. Before free flight, the server also checks the descending heading for the
first approaching live solid upper face within range and can choose its level.
The barrel sweep remains first; upper faces above the shot, destroyed/decorative
objects and steep faces do not qualify. The curve uses ordinary muzzle clearance
above the selected surface, freezes that height/heading for this shot, and never
teleports a projectile upward or homes toward a player. A lower floor does not
pull a bridge-relative shot down through its deck. Existing sphere sweeps, range,
speed, damage and ownership remain authoritative and unchanged.

Tests now include grounded and hopping bridge shots hitting a bridge opponent,
an airborne shot approaching another raised platform, first-face selection,
destroyed/non-solid/removed/overhead surfaces, range limits and blocking cover.
The trajectory group has 1873 assertions and renderer group 143; all 33 Luau
groups were run without Rojo builds. Native acceptance: after live Rojo sync,
restart Play, fire from a stationary bridge, hold Gatling fire through repeated
hops, and aim toward a tank on the same deck. Check barrel direction, leveling
above the deck and actual damage. Also shoot below an overhead platform, toward
another raised platform, and into nearby solid cover. CLI tests do not establish
native visuals or exact feel.

HTTP world persistence is documented in [HTTP_WORLD_STORAGE.md](HTTP_WORLD_STORAGE.md).
The new adapter has 55 assertions; the editor runtime has 59 including JSON backup
restoration and invalid-import preservation; all 34 Luau groups pass. The backend's
14 BattleWorks tests pass. Its wider 189-test run retains exactly the 12 existing
failures/errors from the 175-test pre-change baseline. Live TiDB/HTTPS tests also
verified save/load, retry idempotency, concurrent revisions and namespace isolation.
No Rojo builds were run for this change.

### Local rotation handles at 90° yaw

The ring axes now come from the entire object orientation. Local X/Y/Z remain
orthogonal after yaw or any combination of pitch/roll; they no longer use the
Euler-component axes that collapse together at yaw=90°. Drag planes and visible
rings use that same basis. A drag composes an axis rotation with the original
frame, then converts back to the unchanged XYZ Euler save format. Zero movement
leaves the original numeric values untouched; snapping quantizes the local turn
in 15° increments. Numeric inspector fields still edit explicit Euler components.
Switching axis buttons immediately updates ring positions before the next frame.

Regression coverage includes yaw 90°/270°, combined tilt, near-singular angles,
independent orientation comparisons, snapping, height/scale preservation, actual
UI ring picking/drags, undo/redo and export through the existing Node validator.
The document/math suite now has 121 assertions and the editor runtime suite 74.
All 34 Luau groups were run, with no Rojo builds. Native validation: after Rojo
sync and restarting Play, yaw a board to 90°, alternate Tilt X / Tilt Z / Yaw Y,
and verify each ring follows the object and rotates about its own axis. Test
snapping, undo/redo and Save/Open afterward.

### Editor camera input and eye-level inspection

The editor now captures right/middle mouse input only over its viewport, through
a scoped high-priority camera action with viewport-local input delivery. It uses
relative MouseMovement deltas while the cursor is locked, so orbiting does not
freeze when GetMouseLocation stays constant. Starting orbit/pan no longer needs
a successful ground-ray hit; neither does picking a visible raised object.

Controls: RMB orbit, Shift+RMB or middle drag screen-plane pan, WASD horizontal
movement, E/Q vertical movement while dragging, wheel zoom, F reset. Orbit can
reach eye level (camera floor clearance 1.5 studs), including at different zoom
levels; it can look upward at a raised focus. Panning uses the camera right/up
basis and viewport/FOV scale, so it remains useful at the horizon. Camera movement
can continue with an armed placement without placing or modifying an object.
The editor continues to own a private viewport camera, never Workspace.CurrentCamera.

Mouse behavior/icon are restored on release, input cancel, focus loss, Roblox
menu opening, text focus, editor exit and destruction. Panels/modals/text fields
do not start camera capture; wheel zoom yields to the Roblox menu and text input.
The scoped camera action is unbound on exit. No native GUI auto-focus was added.

Regression suites: document/math130, runtime104, covering locked-cursor movement,
processed viewport delivery, no ground hit, eye-level pitch, pan and vertical
navigation, all release paths, no stale callbacks and unchanged document/history
and gameplay camera. All 35 Luau groups are run without Rojo builds. After live
Rojo sync, restart Play and validate RMB/Shift+RMB/middle dragging on Windows,
low-angle object selection, zoom/F reset, Escape/CoreGui, alt-tab and returning to
battle. CLI mocks do not establish native input delivery or visual camera feel.

Roblox input references: [UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService),
[context action priorities](https://create.roblox.com/docs/reference/engine/enums/ContextActionPriority).

## Edge snapping and bridge fitting

Choose **Snap** alongside Move, Rotate and Scale (shortcut **4**). Only Snap
shows four colored handles, one at the middle of each top side edge. Move,
Rotate and Scale retain their own handles, without overlapping snap handles.
The left **Scale / Stretch** button selects how endpoint fitting changes size.

Grab any side handle and drag it onto a highlighted platform edge/corner, top
face or ground. The opposite side remains fixed while the object rotates and
fits to the grabbed side. Release to hold the fit. Any handle can be grabbed
again immediately; its opposite then becomes the pivot. Away from a surface,
the grabbed handle follows a screen-facing plane through its starting position.

**Scale** resizes all dimensions proportionally. **Stretch** changes only the
local horizontal dimension between the grabbed side and its opposite, preserving
thickness and the other dimension. Stretch supports a single aligned native block
Part without a mesh, including the bundled bridge deck. Other shapes and complex
models use Scale; the server checks the actual template before accepting stretch.
There is no mesh deformation, shear or new asset conversion pipeline.

Move always moves the whole piece and releases its contacts when a body/Move-axis
drag starts. Position fields do the same. Rotate/Scale retain a single contact as
the pivot and release its second contact. **Clear contacts** resets the pivot.
Escape or an invalid release restores the previous pose and contacts. Undo/redo
tracks actual document changes, with one transaction per completed drag. Selection,
no-op clicks and contact-only changes do not create history or clear redo. Undo/redo
keeps the current selection, removing only IDs that no longer exist; it never
restores a historical selection. Contacts accompany actual geometry changes. Duplicates
retain fitted geometry but start without contacts. Green feedback indicates a
valid fit; red indicates an existing scale, boundary, spawn-clearance or other
validation failure. Grid snapping remains optional and independent.

Authoring-v2 objects may now contain optional `stretch: [x,y,z]` factors, each in
[0.001,1000], defaulting to `[1,1,1]`. `bounds` remains the server-measured native
size, and `scale` remains the uniform multiplier. Stretch is applied to visual
native block dimensions and derived collision bounds, not accepted as client
supplied collider dimensions. HTTP saves retain these factors. Compiled v1 worlds
use the existing per-axis transform scale; the native placement adapter accepts
that only for explicitly stretch-capable catalog entries. Old unstretched worlds
continue to use their existing data and uniform placement path.

Contacts use oriented visual bounding boxes. Irregular meshes or assets with
smaller registered colliders may not make a seamless drivable bridge. Prefer solid
box boards with full-size colliders. Existing driving support handles slopes up
to 45 degrees; snapping does not guarantee steep fitted ramps are drivable.
Ground contacts align the top surface at Y=0, allowing the underside below ground.

Pins are temporary, world-space editor references, not runtime welds or linked
constraints. Moving/deleting a target does not move the fitted bridge. Saving,
exporting and reopening retain the final position/rotation/scale/stretch and full
hierarchical asset reference, but do not persist pin metadata. Editor geometry,
feedback and camera remain in the private WorldModel, isolated from active battles.

After Rojo sync, restart Play. Native Studio validation: place two uneven solid
platforms and a board; try all four side handles, switch between Scale and Stretch,
and alternate which side is dragged. In Stretch, check thickness stays fixed.
Check both contact markers
remain flush, undo/redo, Escape, invalid boundary/spawn fits, release, duplicate,
save/reopen, and drive across the saved bridge. Verify eye-level camera picking
and that exiting to menu/battle removes editor feedback. CLI tests validate math,
controller transactions and export through the existing compiler; native viewport
rendering, mouse delivery and tank traversal still require Studio. No Rojo builds
are needed for this change.

## Five player starting areas

New in-game editor drafts start with no starting areas. Use the gold **Place start
zone • N/5** button in the top toolbar beside Move/Rotate/Scale/Snap, then click
the ground to place the next missing number, 1–5. The
preview turns red if the area is outside the world, too near another start, or
blocked by solid scenery. These are starting areas for player battle slots,
independent of tank type and the number of tanks owned by a player.

Each caution-striped area is **36 × 16 studs**, with three 12-stud-wide bays for
the current 8 × 10 stud tank hitboxes. White geometry digits show the player
number and an arrow shows facing. The same non-colliding, non-queryable markings
remain visible in the playable world. The editor alone makes the base selectable.
Select an area to drag it on the ground or edit X/Z and yaw. Areas cannot be
raised, tilted, scaled, stretched or duplicated. Delete and undo/redo work;
replacing a deleted area reuses its number without renumbering other players.

Ground clearance is deliberately conservative: starting centers must be 40 studs
apart, at least 20 studs inside world edges, and clear of solid objects within a
20-stud horizontal margin. The server remeasures imported model bounds before
accepting a save. Drafts with 0–4 areas can be saved and reopened; both Studio Play
and reserved-server launch require exactly five unique slots 1–5. Save & Play
checks this before saving or sending a launch request. Incomplete worlds show
"World is not playable", the placed count, and the top-toolbar tool location;
the regular Save action remains available. Legacy two-point
worlds remain loadable, but the editor clears their tank-type starts in its draft
so the designer can deliberately place the five larger areas. Scenery and the
existing saved source are retained until the designer saves the updated draft.

Authoring `spawns` use `{id, slot, position, heading}` for numbered areas. The
server selects the area matching the player's battle slot, tries its three clear
bays for that player's owned tanks, then uses existing safe fallback spawning if
occupied. Disconnects release player battle slots through the existing lifecycle.
This does not add a third owned tank or change multiplayer admission/publication.

Studio acceptance: place all five areas, check the 1–5 digits and caution stripes
from both overhead and low camera angles, move/delete/undo a start, and save/reopen
an incomplete draft. Confirm Play reports missing starts until all five are valid.
Launch the saved world and check all markings remain visible, player 3 starts in
area 3, owned tanks use separate bays, and bullets/tanks ignore the markings.

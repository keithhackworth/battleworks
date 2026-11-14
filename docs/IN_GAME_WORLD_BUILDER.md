# In-game World Builder proof of concept

Open **Main Menu → World Editor**. No Studio plugin or loopback bridge is needed
for authoring. **← Main Menu** returns home; the draft and undo history stay in
this client session. The existing Studio plugin is retained for compatibility.

This is a desktop-first editor for a new 230 × 230 world with a flat base floor. It uses the
existing catalog, authoring-v2 JSON document, native model placement math, and
compiler/export pipeline. It never edits the running arena.

## Mouse and keyboard workflow

1. Browse the **Asset Library** in the top-right panel. Click directory tiles to
   drill into the actual asset hierarchy, and **↑** to go up. Leaf tiles show
   native 3D thumbnails. Search finds names and complete paths across folders;
   Next pages through up to 24 entries at a time.
2. Drag an asset tile onto the terrain and release. A translucent green preview
   follows the cursor. Red means the placement is invalid. Alternatively click
   a tile to arm it, then click the ground. Each successful placement creates a
   separate instance and selects it. Escape or Q cancels an armed placement.
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
6. Right-drag orbits, middle-drag pans, WASD pans, and the wheel zooms. **F** or
   Frame world resets the camera. Use a desktop window around 1280 × 720 or larger.

Shortcuts: **1** Move, **2** Rotate, **3** Scale;
**Ctrl/Cmd+D** duplicate; **Delete/Backspace** delete; **Ctrl/Cmd+Z** undo;
**Ctrl/Cmd+Y** or **Ctrl/Cmd+Shift+Z** redo; **G** toggle snapping.
Shortcuts yield to focused text fields. Roblox's own Escape menu is preserved;
Q is an alternative cancel key. Opening CoreGui or losing window focus cancels
an active gesture. Every complete drag is one undo action, not one action per frame.

The current format supports uniform scaling only. Stretch remains removed.

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
- All rotation fields follow the existing Rx × Ry × Rz Euler transform order;
  rings follow their corresponding axes on an already tilted object. Snapping
  remains optional and rounds rotation to 15°. If a ring is edge-on to the
  camera, orbit slightly or enter its numeric angle.
- **Collision: SOLID** is required for tank support; NONE stays decorative.
  Save & Play uses the same server simulation. Gentle upper faces up to 45° can
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

Choose **My Worlds / Save & Play** on the left of the editor.

1. Enter a world name and a World ID (letters first, then letters/numbers/underscores/hyphens).
2. **Save** stores the current layout privately. **Save & Play** saves, validates,
   then launches it through the existing simulator.
3. Use **Open** on a saved row to restore it for editing. Opening replaces the
   current draft and clears its undo history. Open an existing save before updating
   it; change World ID to create a separate slot. Refresh lists your saved worlds.
4. Return with the battle HUD's **Main Menu**, then open World Editor to continue
   your draft. In a private battle server, Play BattleWorks re-enters that world.

In the published Roblox experience, up to **10 private worlds per account** are
stored in `BattleWorksPlayerWorlds_v1`. Each world is limited to 512 objects and
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

**Studio intentionally uses temporary session-only saves**, labeled in the UI.
They are lost when the player disconnects or Play stops. Save & Play tests locally
only when every client has left combat; otherwise it explains that the battlefield
is occupied. This avoids Studio writing live player data or relying on unsupported
Studio teleports. To verify account persistence and travel, publish the updated
place and test in the Roblox app. Players require no API keys or commands.

## Optional developer JSON export using the existing format

Choose **Export JSON**, enter a valid world ID/name, then **Generate / Select JSON**.
Copy with Ctrl/Cmd+C (or Ctrl/Cmd+A then C in the export box). The copy box may be
edited for convenience; this does not edit the layout. Generate restores the
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
- `WorldLibrary` owns the private save/open UI and ignores late responses after exit.
- `PlayerWorldDocument` validates the authoring schema on the server, replaces
  claimed bounds with native measurements, and adapts to existing placement specs,
  interaction fractions and water/mud zones. No compiler or gameplay rewrite.
- `PlayerWorldStore` owns per-user DataStore slots with UpdateAsync revision checks;
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
   Check that the Studio session-only notice is visible. Drive into solid cover,
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

1. Publish this build, join through Roblox, save a world, leave the experience,
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
5. Native viewport input, visual layout, Windows stability, cloud services and
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
supported hull incline, and a small normal tolerance preserves 45° ramps with
native CFrame precision. These changes preserve underneath clearance and tall-end
blocking and do not introduce a second physics engine.

Regression tests cover 30°, 40° and 45° narrow boards, 0.35-stud platform joins,
per-tick support/pitch checks, both tank types, X/Z approach directions and native
45° float rounding. CLI tests do not establish native rendering or driving feel.

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

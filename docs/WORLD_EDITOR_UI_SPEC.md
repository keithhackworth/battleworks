# BattleWorks World Editor — UI Specification

## Authority and scope

This specification is a binding architectural contract, not a design suggestion. All World Editor UI development, including future features, bug fixes and refactoring, must conform to it.

New functionality must be assigned to the appropriate primary tool, contextual section and property ownership level before implementation. Do not introduce ad hoc buttons, panels, menus or duplicated properties.

If a requested change conflicts with this specification, report the conflict and obtain approval. Update this specification as part of any approved architectural change.

Passing automated tests does not, by itself, establish compliance with this specification.


Rebuild the workspace around a compact, GIMP-inspired editor while retaining the BattleWorks military visual identity and existing visual assets. This is a presentation and usability redesign, not a gameplay expansion.

Preserve existing functionality, defaults, validation, serialization, undo/redo, shortcuts, gestures, and saved-world compatibility. Do not add gravity or other gameplay features. Do not redesign Save/Load World dialogs or refactor persistence. Preserve camera behavior; keep sensitivity under View.

## Required pre-implementation audit

Inspect the view, presentation, controller, scene, state, document model, asset catalog, shared modules and tests. Map every existing control, property, operation, selector value, shortcut, gesture and dialog to this contract. Report omissions, conflicts, unsupported proposed controls and implementation risks. Obtain approval before implementation. Do not silently discard functionality.

## Workspace architecture

- Top: application menus.
- Left upper: persistent three-column primary icon grid.
- Left middle: active tool's contextual sub-tools.
- Left lower: active tool's additional operations.
- Center: dominant world viewport.
- Right upper: shared properties of the active primary tool.
- Right lower: selected item or operation properties.
- Persistent common command strip and contextual status feedback.

Collapse unused sections. Independently scroll overflowing sections. Use compact icons, tooltips, clear active/disabled states and existing military styling. Avoid nested menus, oversized controls and unrelated properties. Do not rebuild the entire workspace on ordinary property changes.

### Primary tool order

| Column 1 | Column 2 | Column 3 |
|---|---|---|
| Select / Navigate | Assets | Move |
| Rotate | Resize | Scale |
| Terrain | Audio | Motion |
| Physics | Start Zones | |

Select / Navigate is always first. Undo, Redo, Duplicate and Delete belong in a separate persistent command strip, with existing enablement and history semantics. Keep one fixed strip immediately beneath the three-column grid. Preserve keyboard shortcuts and avoid duplicate permanent toolbar controls.

## Property ownership and state

World properties belong exclusively in World Settings. Shared tool properties belong in the upper-right panel. Object, material, catalog item, tunnel, waypoint, audio trigger and operation-specific properties belong in the lower-right panel. Do not duplicate editable fields; read-only inherited defaults are acceptable.

Maintain independent primary tool, contextual sub-tool, operation, world object, catalog asset and contextual item selection state. Switching tools must not deselect the world object. Each tool retains its workspace preferences for the editor session, including sub-tool and operation choice, tool-specific settings, rotation axis, terrain material and operation, brush settings, catalog browsing and preview, and repeat placement preference. Restore those preferences on return while leaving the current world selection intact. Object properties reflect the current world selection.

The grid toggle and increment are shared across Move, Resize, Scale and Rotate. Edge-snap enablement is retained separately for Move, Resize and Scale. Snap contacts belong to the object. Resize and Scale use the same existing uniform-scale clipboard, so either tool can apply a value copied in the other. Per-tool workspace restoration must never overwrite the shared grid settings, object snap contacts, or clipboard.

Clicking another object while idle changes the selection and keeps the primary tool active. While drawing a waypoint path, placing an armed asset, picking an attachment target, or picking a second tunnel portal, viewport clicks belong to the active operation until it commits or is cancelled. Tool changes cancel only unfinished transactions using the existing cancellation semantics. Preserve committed edits, clear obsolete handles and previews, and create no history entry for the switch itself. Restoring preferences must not resume an unfinished transaction or rearm placement.

## Tool inventory

### Select / Navigate

Select and navigate without accidental modification. Preserve existing selection and navigation behavior. Show basic selected-object information and convenient access to Physics, Audio and Motion. Camera sensitivity stays under View.

### Move

Sub-tools/operations: existing movement axes and handles, grid snap, edge snap, Move to Snap, Pin A Here, Pin B Here, Clear Contacts. Upper right: grid enabled, grid increment, edge snap enabled and applicable fit preferences. Lower right: X, Y (existing lowest-point semantics), Z. Move snapping translates the entire object without resizing it.

### Rotate

Sub-tools: Tilt X, Yaw Y, Tilt Z. Lower right: pitch, yaw, roll. Preserve manual rotation handles. Automatic rotation belongs under Motion.

### Resize

Sub-tools/operations: existing per-axis resizing, grid snap, edge snap, Stretch to Snap, contact pins, Clear Contacts, Copy Scale, Apply Copied Scale. Upper right: applicable snap settings and resize axis preferences. Lower right: local width, height, length. Preserve asset-specific restrictions, axis-specific stretch and fixed opposite-side semantics.

### Scale

Sub-tools/operations: uniform scaling, grid snap, edge snap, Scale to Snap, contact pins, Clear Contacts, Copy Scale, Apply Copied Scale. Upper right: applicable scaling and snapping preferences. Lower right: existing scale values and applicable dimensions.

Snapping is not a primary tool. Move, Resize and Scale expose their applicable fit modes. Preserve authored and collision-derived snap boundaries, handles, contact pins, target feedback and fitting algorithms.

### Assets

Left contextual section: integrated scrollable expandable tree using actual catalog hierarchy, nested folders, asset selection and existing recent-assets functionality. Selecting a catalog item previews it without placing it. Left operations: Place Asset and existing drag-into-world placement. Upper right: Repeat Placement and existing shared placement settings. Lower right: existing 3D preview and available metadata/dimensions.

Returning to Assets must restore the exact expanded/collapsed folders, scroll position, selected catalog asset, preview and repeat placement preference. A user building a roller coaster or line of trees must not repeatedly drill into the same folder after switching to Move or Rotate. Catalog selection is independent of placed object selection. Tree navigation replaces Previous/Next/Parent Directory controls only where equivalent functionality is retained. Search results use separate state from catalog browsing. Clearing the search restores the previous folder expansion, catalog selection, preview and scroll position. Cancel or Escape disarms placement while preserving browsing state, search and Recent view. Repeat placement continues after successful placement while armed.

### Terrain

Terrain shows a full-width material strip above the status bar. The strip begins with **None** and **Clear**, followed by Grass, Mud, Ice, Snow, Pavement and Water. None makes the brush idle. Clear restores the underlying world surface within the brush by removing local material paint, water and traction overrides while preserving elevations and world defaults. Clear is undoable as a single stroke. The strip blocks viewport input over its controls while the viewport bounds stay stable. Left operations: Raise, Lower, Smooth, Flatten, Carve Ravine, Tunnel. Retain independent material and operation preferences where supported; do not change existing gesture semantics.

Upper right: Brush Size (existing radius, default 26 studs), Heaviness (strength, default 24), Steepness (0–1, default 0.65). Apply brush falloff as one minus Steepness so low values give a gentle slope and high values give a sharper edge. Preserve actual units and validation. These are shared terrain settings, not material properties.

Lower right: **Paint entire world** is available for Grass, Mud, Ice, Snow and Pavement. Check it and click terrain to apply the active material and its brush traction setting in one undoable edit. The checkbox disarms after the edit. Elevations and world defaults are preserved. Water retains its separate routing action. Show selected material traction only where applicable. Show inherited world default read-only, Use World Default and painted traction override when enabled. Grass, Mud, Snow and Ice support configurable traction; Pavement is the reference, Water has no unsupported traction control. Preserve per-cell traction overrides independently of world defaults. Changing a default must leave existing painted overrides intact.

Operation-specific properties: flatten elevation (existing default 0), water/ravine depth (existing default 4), where applicable. Do not put them in global brush settings. Reconcile simultaneous material and operation visibility without losing access to either.

Tunnel operations: Draw New Tunnel, Select Next Tunnel, Delete Selected Tunnel. Selected tunnel properties: inside diameter, traction, start elevation, end elevation. While preparing to draw, diameter and traction presets apply only to the next tunnel. Preserve traversability visualization and terrain visibility.

### Audio

First-class tool; supports independent sound creation and editing sound associated with the selected world object. Sound Blocks remain independently selectable. Switching to Audio with an ordinary object selected retains that selection and exposes its applicable audio attachment and trigger relationships and operations. Editable audio fields remain on the Sound Block or trail. Preserve existing sound block/trail and asset relationships; do not introduce a new audio data model.

Sub-tools: Sound Block, Paint Audio, Paint Bucket, existing attachment functionality. Operations: Choose Sound Effect, Preview Sound, Finish Painting, Repaint Sound Trail, Follow Collision, Select Trigger Assets, Snap & Lock to Asset. Preserve sound picker search, categories, selection and close workflows. Only expose applicable operations. Objects without audio expose existing creation/attachment actions where supported. Upper right contains only existing shared audio workspace settings; collapse if empty.

Lower-right audio properties:

| Property | Existing values/defaults |
|---|---|
| Sound effect | Existing catalog |
| Activation | Always Active, On Entry, On Exit, While Occupied |
| Playback | Once per activation, Loop while active, Repeat while active |
| RollOff | Inverse, Linear, LinearSquare, InverseTapered |
| Trigger Filter | Tanks, Moving Assets, Both, Specific Assets, Terrain |
| Sound Origin | Block, Trigger |
| Repeat interval | 3 sec; 0.1–3600 |
| Cooldown | 0.5 sec; 0–3600 |
| Volume | 0.6; 0–10 |
| Playback speed | 1; 0.1–4 |
| Minimum audible distance | 8; 0–1000 |
| Maximum audible distance | 100; 1–2000 |

Repeat interval only for Repeat playback. Specific Assets exposes trigger asset selection (up to 32). Preserve attachment relationships, painted trails, collision following and all existing validation including min/max distance ordering.

### Motion

First-class tool operating on current world selection. Sub-tools: Automatic Rotation, Motion Path, Waypoint Editing. Operations: Add/disable/remove Automatic Rotation as currently supported, Draw Motion Path, Preview/Stop Motion Preview, Remove Motion Path, Remove Selected Waypoint.

Automatic rotation properties: axis space Local/World; mode Continuous/Swing; axis X/Y/Z (-1 to 1); speed (1–360 degrees/sec); swing angle (1–360 degrees, only when applicable); pause (0–3600 sec).

Motion path properties: enabled, speed (1–60 studs/sec), endpoint pause (0–10 sec), Maintain Orientation/Face Movement. Waypoint properties: X/Y/Z. Preserve existing 2–32 waypoint limit, dragging, selection, visualization, closed-loop detection, open-path traversal and validation. Do not change motion algorithms.

### Physics

First-class tool operating on current world selection. Lower right: Collision Enabled, Destructible, Durability/HP, Regenerates, Regeneration Delay, Asset Traction, Physical Movability. Preserve conditional visibility and validation. Physical Movability remains read-only where currently fixed. Do not introduce new movability functionality.

### Start Zones

Operations: Place Start Zone, Delete Selected Start Zone. Tool information: existing count and maximum (currently five). Selection properties: X, Z, yaw. Preserve placement and validation.

## Menus and dialogs

- File includes New World, Open World (the existing My Worlds entry), Open Playground where applicable, Save, Save As, Import JSON, Export JSON, and Main Menu or Leave Editor where applicable. Keep Generate / Select, world name and ID, and JSON validation and replacement in the existing overlay. Keep the existing Save/Load dialogs, unsaved-changes confirmation (including Keep Editing and Leave), and draft and persistence behavior.
- World opens World Settings.
- View includes camera sensitivity, Frame World, Focus Selected where applicable, Show/Hide Terrain, Audio and Tank Scale, Terrain Traversability, inspector visibility and existing view options.
- Test invokes the existing Save & Play Test workflow, including validation, saving or reusing a revision, launch, status and errors, and supported return behavior.

Hide Advanced while it has no applicable operations.

### World Settings

World width and depth; existing world sizing controls; ground material and RGB color; default material traction for Grass, Mud, Snow and Ice. Pavement remains reference traction. Preserve defaults, validation and serialization. World size never belongs to object Resize or Scale. Local painted, asset and tunnel traction remain selection properties. No gravity or new simulation settings.

## Shortcuts and viewport

| Shortcut | Action |
|---|---|
| 1 / 2 / 3 | Move / Rotate / Scale |
| 4 | Toggle edge snap |
| G | Toggle grid snap |
| F | Focus selected |
| Home | Frame world |
| Ctrl+Z | Undo |
| Ctrl+Shift+Z / Ctrl+Y | Redo |
| Ctrl+D | Duplicate |
| Delete / Backspace | Delete selection |
| Escape | Cancel / close applicable operation |
| Enter | Finish applicable gesture |
| WASD | Camera movement |
| Q / E | Vertical camera movement |
| Shift | Accelerated camera movement |

Preserve existing mouse, touch, camera orbit/pan/zoom, handles, highlights, brush previews, snap indicators, placement previews, path visualization and status feedback. Sidebar input must not propagate into viewport. Preserve the input and gesture behavior recorded in the source reconciliation.

## Implementation architecture and acceptance

Define tools explicitly by identity/icon, sub-tools, operations, shared properties, selection properties, visibility and enablement predicates, workspace state and existing controller actions. Presentation must not become a second implementation of editor behavior.

Acceptance requires every existing capability accessible; three-column primary grid; correct contextual grouping and property ownership; independent selection and exact workspace restoration; applicable snapping in Move/Resize/Scale; unchanged shortcuts, gestures, save/load dialogs, gameplay and saved-world compatibility; passing existing tests plus UI regression tests for visibility, selection persistence and workspace restoration.

## Implementation approval

The source reconciliation and its decisions are approved for implementation. Follow the implementation sequence in verified, testable increments. If implementation reveals a discrepancy with this contract, stop the affected work, report the discrepancy and obtain approval before changing the contract or proceeding with that work.

### Snap fitting behavior

Move, Resize and Scale must each expose their corresponding snap fitting mode as a directly accessible contextual control.

- Move → Move to Snap.
- Resize → Stretch to Snap.
- Scale → Scale to Snap.

The active primary tool determines the applicable fitting behavior. The user must not need to navigate to a separate snapping tool or dropdown to activate it.

Grid snapping, edge snapping, contact pin management and applicable fitting controls must remain accessible within each of these three tool workspaces.

Preserve existing snap geometry, contact management, axis restrictions, anchoring, visual feedback and fitting algorithms.

Retain applicable snapping preferences when switching between primary tools. Do not inadvertently carry an incompatible fitting mode into another tool.


### Property editing and viewport stability

Allow direct numeric entry with the existing precision, units, ranges and validation. Update fields as objects are manipulated without rounding stored values, losing keyboard focus, or triggering viewport shortcuts during text entry.

Keep primary icons fixed and sidebar widths stable across tool changes. Use independent scroll regions and the existing inspector visibility command at narrow sizes. Long labels and asset names must fit within their panels. Opening a popup, switching tools, or changing contextual content must leave viewport bounds stable. A deliberate viewport resize may safely cancel an active resize drag under existing cancellation behavior.

### Resource lifecycle and regression scenarios

Switching tools must not accumulate event connections, preview models, rendering callbacks, or viewport handles. Inactive tools should release temporary resources and stop unnecessary processing.

| Scenario | Expected behavior |
|---|---|
| Build a roller coaster | Switch between Assets, Move, Resize and Rotate, and clear a catalog search without losing folder expansion, selection or scroll position. |
| Connect track pieces | Use Move to Snap, Stretch to Snap and Scale to Snap directly in their corresponding tools. Transfer clipboard values across Resize and Scale and verify grid settings and contacts survive tool changes. |
| Sculpt terrain | Retain brush settings across materials, and verify changing world traction defaults leaves painted overrides intact. |
| Configure a moving platform | Switch between Motion, Physics and Audio without losing object selection. Select another object while idle and stay in the active tool. |
| Paint audio along a track | Preserve painting, bucket fill and collision following. |
| Switch tools mid-gesture | Cancel the unfinished transaction under existing rules, preserve committed work and verify Undo still restores world state. |
| Save and reopen an existing world | Preserve world data and verify the existing Save & Play Test workflow. |
| Repeatedly switch tools and open popups | Keep viewport bounds stable and verify resources and performance remain stable. |

## Source reconciliation

This section records current behavior and maps it to the approved rebuild. “Target location” maps the working feature into the proposed workspace. It does not claim that the current editor already matches the target structure.

### Sources audited

- [View](../src/client/shell/WorldEditorView.luau), [presentation](../src/client/shell/WorldEditorPresentation.luau), [controller](../src/client/shell/WorldEditorController.luau), and [viewport scene](../src/client/shell/WorldEditorScene.luau) for control ownership, conditional visibility, picking, and editing gestures.
- [Authoring state](../src/shared/WorldEditorState.luau), [document rules and catalog](../src/shared/WorldEditorDocument.luau), [snap geometry](../src/shared/WorldEditorSnap.luau), [world settings](../src/shared/WorldSettings.luau), [heightfield](../src/shared/WorldHeightfield.luau), [tunnels](../src/shared/WorldTunnel.luau), [motion and spin](../src/shared/WorldMotion.luau), and [sound](../src/shared/WorldSound.luau) for values and invariants.
- [World Library](../src/client/shell/WorldLibrary.luau), [world service](../src/server/PlayerWorldService.luau), [BattleWorks shell](../src/client/UI/App.luau), [editor bridge](../src/client/UI/WorldEditorAccess.luau), and [editor asset catalog](../src/server/EditorAssetCatalog.luau), [asset paths](../src/shared/AssetPaths.luau), and [offline authoring validator](../tools/world-builder/document.js) for navigation, catalog identity, and persistence.
- [Editor runtime](../tests/InGameEditorRuntime.spec.luau), [snap](../tests/WorldEditorSnap.spec.luau), [terrain](../tests/TerrainEditorRuntime.spec.luau), [terrain resize](../tests/TerrainResize.spec.luau), [tunnel](../tests/TunnelEditor.spec.luau), [Battle Royale client](../tests/RoyaleClientIntegration.spec.luau), [world service](../tests/PlayerWorldServerIntegration.spec.luau), and [offline authoring](../tests/world-builder.test.js) tests for covered behavior and assumptions about the current layout.

### Reconciled capability map

| Area | Current behavior to preserve | Target location |
|---|---|---|
| App shell | Battle Royale opens the existing editor through the World Editor route. The app header remains visible. The menu chest and dog tags start parked. Opening the animated menu gives it the cursor and blocks editing beneath it. Confirming navigation retains the dirty draft for the session. Classic retains its existing Main Menu entry and return. | Existing BattleWorks header and menu, plus **File → Leave Editor** where applicable. Both exits use the same confirmation and cleanup path. |
| Saved worlds | New World starts an undoable blank draft with a unique ID. Open lists private worlds. The existing dialog has world name and ID, Save, Save & Play, Refresh saves, per-world Open and confirmed Delete, and Back to editing. Save As needs a different ID. Revision checks, temporary save labels, team-test host restrictions, and late-reply fencing remain. | **File → New World, Open World, Open Playground, Save, Save As**; retain the current Library dialog and its internal actions. **Open World** already opens My Worlds. |
| Playground and Test | Open Playground is a Battle Royale operation. It loads the preferred saved revision or generates the starter. Test validates five numbered starts, saves or reuses a revision, and launches through the existing service. Studio installation and reserved-server travel differ. Return from a local test can restore the edited revision. | **File → Open Playground** and **Test → Save & Play**. Preserve save errors, launch/teleport status, and draft recovery. The existing saved-Playground launch path remains where available outside the editor. |
| JSON | Export generates and selects JSON and exposes world name and ID. Import takes pasted JSON and replaces the draft only after validation succeeds. Generate / Select, Import, and Close share one overlay. Import preserves the current draft when invalid or when a referenced asset is unavailable. | One Import entry and one Export entry, opening the existing shared overlay in the appropriate mode. Both entries belong under **File**. |
| Select and immediate commands | Select / Navigate picks objects without transform drags. Duplicate uses current selection, is undoable, and duplicates in place for a Sound Block with Follow Collision enabled. Delete supports objects and start zones and reconciles affected references. Undo/Redo are enabled by available history. | **Select / Navigate**; the common command strip owns **Undo, Redo, Duplicate, Delete**. The selected-object actions menu can provide the same Delete command as a contextual shortcut. |
| Move, Rotate, Resize, Scale | Move supports free dragging and axis handles. Y means the lowest point. Rotate uses local X/Y/Z rings. Resize edits eligible local axes and keeps the opposite side fixed during handle drags. Scale edits uniform scale. Precise edits are validated against bounds and collider restrictions. Copy/apply transfers only the uniform scale. Successful scale edits are remembered by asset for later placement. | Existing transform handles, upper-right shared tool settings, and lower-right precise values. Copy/apply shares one clipboard across Resize and Scale. The catalog item remains independent of the placed object. |
| Grid and edge fitting | Grid is off by default, starts at 1 stud, and accepts 0.1–50 studs. It also snaps manual rotation. Fitting uses authored boundary geometry when available and collision-derived geometry otherwise, with existing fallback handles. Preserve source edge dots, target edges and surfaces, A–D handles, Pin A/B Here, Clear Contacts, valid/invalid preview, opposite-side anchoring for Resize/Scale, and translation-only Move. Invalid fits and cancellation roll back. A direct numeric transform clears relevant contacts. | **Move, Resize, Scale** each own Grid Snap, Edge Snap, their dedicated fit action, and contact commands. Right inspector shows increment, geometry source, contacts, and the selected tool’s precise fields. Grid settings are shared, edge-snap enablement is tool-specific, and contacts belong to the object. |
| Asset browsing | Live catalog paths and nested folders, name/path search, parent directory, Previous/Next pagination, recent placements, missing/unavailable diagnostics, native 3D thumbnail and bounds, and collision warnings. The modal currently stages a selected catalog entry, then **Select Asset** activates placement. Repeat stays armed after a successful placement. Native and cloud-backed assets retain the same identity and availability policy. | **Assets** tree and search/results, selected asset/preview in the right lower panel, Repeat in the right upper panel, Place Asset in operations. A tree replaces page and parent buttons only once their content remains reachable. |
| World-level appearance and dimensions | Width/depth are integer 25–2,000 studs. Resizing a terrain grid resamples elevation and carries paint, water and traction cells; existing objects and starts stay in place, and invalid resizes are rejected. Existing ground material selector and RGB field are editable. Boundaries are required. There is no independent global scale multiplier. | **World → World Settings**. Keep width, depth, ground material, RGB, required boundaries and editable fallback traction here. Do not add a world scale, gravity, or viewport perspective selector. |
| Terrain brush | Raise, Lower, Smooth, Flatten, Grass, Mud, Ice, Snow, Pavement, Water, Carve Ravine, and Tunnel. Radius defaults to 26 (2–160 studs), strength to 24 (0.5–96), and displayed Steepness to 0.65 (0–1). Brush falloff is one minus Steepness. Flatten elevation defaults to 0 and uses the heightfield range −96 to 500 studs. Water/ravine depth defaults to 4 and accepts 0.25–32 studs. Water is click-to-route; sculpt/material/ravine operations drag. Current controller has one active operation, so material paint and sculpting do not execute together. | Terrain material controls across the bottom and operation controls directly below the common command strip. Shared brush settings upper right. Flatten elevation and water/ravine depth lower right only when applicable. Remember the last material and sculpt operation without running both at once. |
| Terrain traction | Grass, Mud, Snow and Ice have a world fallback and optional per-cell overrides. Brush traction applies only to the touched cells, accepts 0–100%, and an empty brush value removes the overrides when repainted. Zero is explicit, not inherited. Old saves keep their fallbacks. Pavement is the reference; Water uses the existing wet-ground behavior. The overlay and simulation use the same local override. | World fallback is editable only in World Settings. Terrain shows a read-only inherited value plus **Use World Default** and the brush override. Switching the brush value alone changes no world data. |
| Tunnels | Two portal clicks create a straight tunnel, Next selects an existing tunnel, and Delete removes it. Before creating it, the existing diameter and traction controls set defaults for the next tunnel. After selection they edit that tunnel. Defaults are 18 studs and 100%; validation includes diameter 12–48, traction 0–100%, no more than eight, portal clearance, minimum length, grade, cover, and non-overlap. | Tunnel operations on the Terrain left; lower-right **New Tunnel** properties while preparing a tunnel, and **Selected Tunnel** properties afterward, including both portal elevations. Never treat tunnel traction as world/material traction. |
| Audio creation and placement | Sound Block and Paint Audio are catalog asset types with separate placement behavior. Paint Audio creates trails on queryable collision surfaces; bucket fills connected surfaces. Follow Collision is a Sound Block move preference, and affects duplication. Finish commits a non-empty trail; Escape restores the draft on cancel. Editor previews use the sound catalog and clear on exit or selection change. | Audio left sub-tools are alternate entry points to the same asset/paint handlers, with shared Follow Collision preference and context-dependent Finish, Repaint and Fill. Keep the catalog entries under Assets too. Audio data stays on Sound Blocks and painted trails. |
| Audio properties and selection | Effect picker supports category/search, assign, preview and close. The target picker adds/removes up to 32 eligible placed assets. The current defaults are empty effect, Always, Loop, InverseTapered, Tanks, Block. Repeat interval only appears for Repeat; specific target selection only for Specific. Preserve the documented numeric limits, min/max ordering, unavailable clip feedback and preview stop. Snap & Lock can use an existing snap target or request a viewport parent. Detach preserves the current pose. | **Audio → Sound Effect, Trigger Assets, Attachment**; editable fields in the Sound Block or trail inspector. Sound Blocks remain independently selectable. Switching to Audio with an ordinary object selected exposes its applicable attachment and trigger relationships and existing operations. Audio fields remain on the Sound Block or trail. |
| Motion | Add/remove spin (initial local +Y, 30°/s, zero pause; Swing starts at 90°). Continuous pause is after a turn. Swing pause is at each end. Motion Path uses Draw/Edit/Finish with preview/stop, remove path, enable, orientation, and waypoint add/select/drag/numeric edit/delete. While drawing, clicking the first waypoint can close an eligible path and dragging either end of a closed path keeps closure. Numeric waypoint fields are world coordinates, stored relative to the object. Preview can follow attached children or the selected sound object's moving parent. | **Motion → Automatic Rotation, Motion Path, Waypoints**. Keep visibility tied to supported selection and current draft state. Remove a spin rather than inventing a separate spin enable property. Path enable stays independent. |
| Physics | Collision and destructibility; HP 1–100,000; eligible collider-only traction 0–100 or blank to inherit; regeneration is destructible-only and can be disabled, with delay 0–3600 seconds (default 5). Zone movement effects and collider information are read-only. Sound Blocks and starts have no destructible/collision editing. Assets remain physically fixed. | Lower-right **Physics** inspector with applicable fields and **Physical movability: Fixed**. Keep zone and collider information read-only. |
| Start Zones | Start placement arms the next numbered area. Each holds three tanks; five are required to test. Place on clear supported ground; start centers must be 40 studs apart. Selected zones support ground drag, X/Z/yaw, and deletion. Opening a legacy two-spawn document leaves the stored source intact and requires placing numbered zones in the draft. | **Start Zones** operations and count; lower-right X, Z, yaw with validation feedback. Common Delete calls the same operation. |
| View and status | Camera sensitivity starts at 1 (0.2–3). Frame World, Focus Selected, hide/show Terrain, Audio and Tank Scale, traversal overlay, and inspector visibility. Preserve 3D selection wire, private viewport and camera, tank reference, collision/snap visuals, brush footprint, motion and audio markers, and state-dependent prompts. | **View** owns camera and visibility controls; Terrain can offer a shortcut to the same traversal command. Keep transient status for mode, object/catalog item, dimensions, snapping, save results and validation. |

### Pointer, keyboard and session details

- **Desktop:** left click selects; drag uses the active handle or operation. Right mouse drag orbits, middle mouse drag pans, wheel zooms, and WASD/Q/E fly with Shift acceleration. Camera capture only begins inside the viewport and releases on mouse-up, Escape, window blur, text focus, menu opening, or editor exit. Preserve the viewport-local camera binding for events Roblox marks as processed.
- **Placement and precision:** honor free placement when grid is off and retain position/scale/rotation validation. Escape clears placement previews and cancels armed placement. Selecting a catalog entry never replaces the selected object's properties. Starting a placement transaction may change selection through the existing controller path. Keep both click/tap placement and the supported drag-to-place workflow explicitly reachable.
- **Snap and drags:** target raycasts and edge dots must stay in the private viewport. Pin changes with no document edit do not create phantom undo entries. A failed fit restores original pose and contacts. A resize outside the viewport holds its last preview; release ends it, and a viewport size change cancels safely.
- **Audio and motion:** Enter or keypad Enter finishes an active audio stroke when applicable, also available from Finish Painting. Lifting the brush permits camera navigation without ending a multi-stroke trail. Waypoint add/drag/close and two-click tunnel placement retain their explicit transaction boundaries.
- **Touch and controller:** preserve touch selection and placement, modal activation, and supported waypoint pointer handling. Desktop orbit/pan/fly and sculpting must not be advertised as equivalent touch gestures unless implemented separately. Preserve controller B for leaving the legacy editor through the confirmation path. Ctrl shortcuts also accept Command/Meta; redo accepts Shift+Ctrl/Meta+Z or Ctrl/Meta+Y. Text focus and modal inputs suppress viewport shortcuts.
- **History and state:** existing history holds up to 100 document changes and carries snap pins with transform history. Draft cancel restores gesture snapshots. Workspace state is session-local; cache the values and selection keys rather than keeping all previews or listeners active. Preserve retained draft contents when temporarily leaving the editor, and keep draft state distinct from saved revision and active playtest state.

### Implementation sequence and release checks

Verify each increment before proceeding to the next. Automated tests must be supplemented by Studio verification of the visual layout, contextual behavior, workspace restoration, viewport stability, and representative editing workflows at desktop, short landscape, and portrait sizes.

1. Add tool and operation identities and a session workspace model while keeping the controller the sole owner of authoring mutations.
2. Map the command strip, headings, inspector groups and menus to the existing handlers. Keep Save/Load and JSON dialog logic unchanged. Move the fallback-traction control without changing its schema or validation.
3. Replace catalog pagination with the equivalent searchable tree, wire explicit placement and repeat, then migrate Audio, Motion, Terrain/tunnels and Start Zones. Verify selection independence and eligibility-driven controls before removing old entry points.
4. Run the existing editor, snap, terrain, tunnel, world storage, and offline authoring regressions. Add checks for tool-state restoration, inactive viewport input, pointer cancellation, no UI/connection growth, and stable layout at desktop, short landscape, and portrait sizes.
5. In Studio, verify both shell entry paths, intended desktop and supported touch inputs, saved-world and playtest round trips, and performance while navigating a representative large catalog and terrain. A hosted save containing per-cell traction requires the deployed GroupBoard validator to accept `tractionCells`. Test it explicitly rather than inferring deployment from the local validator test.

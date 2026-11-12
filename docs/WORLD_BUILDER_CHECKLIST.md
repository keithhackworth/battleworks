# World builder implementation checklist

Status vocabulary: TODO, IN PROGRESS, BLOCKED, COMPLETE. Completion requires
verification. **Native Studio acceptance remains BLOCKED: no connected Studio
session is available to this coding environment.** Source/build/automated results
below are distinct from native interaction claims. Resume with Phase 3/6 manual
checks in [WORLD_BUILDER.md](WORLD_BUILDER.md), fixing any observed native issues.

## Phase 1 — Architecture (COMPLETE)
- COMPLETE: Inspect v1 JSON/compiler, asset registry, catalog and native placement.
- COMPLETE: Inspect LocalBattle spawn/reset, environment/physics, camera/network,
  contact solver, project structure and test infrastructure.
- COMPLETE: Verify plugin widgets, native file-selection, handles, RunState and
  StudioTestService APIs against official references.
- COMPLETE: Document Studio plugin + loopback save bridge decision before code.
Acceptance: existing pipeline and persistence/security decisions documented.
Paths: docs/WORLD_BUILDER.md, tools/world/*, src/server/{LocalBattle,
StudioWorldSelector,StudioAssetPlacement,WorldObjects,init.server}.luau.

## Phase 2 — Data and persistence (COMPLETE; depends on 1)
- COMPLETE: Versioned v2 authoring document, reusable catalog and stable IDs.
- COMPLETE: Adapt to existing v1 compiler, deterministic manifests/serialization.
- COMPLETE: Validate fields/transforms/bounds, asset paths, HP, spawns and obstacles.
- COMPLETE: Legacy migration into an editable copy; reject unsupported geometry.
- COMPLETE: Save/load/list/rename/duplicate/import/export/delete with confirmation.
- COMPLETE: Atomic file updates, serialized concurrent writes, automatic registration.
- COMPLETE: Persist independent development selection and explicit published choice.
- COMPLETE: Loopback-only authenticated bridge, browser-origin rejection, bounded
  bodies, strict file IDs, no untrusted executable world data.
- COMPLETE: Save/load/round-trip/CRUD/validation/concurrency/bridge tests.
Acceptance: programmatic create→save→reopen→edit→select/delete round trip passes.
Paths: tools/world-builder/{document,catalog,store,server}.js,
worlds/builder/builder_demo.json, worlds/{selected-world,published-world}.model.json,
tests/{world-builder,asset-paths}.test.js.

## Phase 3 — Visual editor (IN PROGRESS; depends on 2)
- COMPLETE: Separate plugin package and direct installer command build with Rojo.
- COMPLETE: Pure editing state: placement, multi-selection, transforms, snapping,
  duplication/deletion, atomic undo/redo, bounded history and dirty state tests.
- IN PROGRESS: Categorized palette with up to 24 native previews and missing asset
  indicators implemented/compiled; native visual verification pending.
- IN PROGRESS: Click/place and drag/drop, ground dragging, Move/Rotate/Scale handles,
  spawn placement, properties and keyboard shortcuts wired; native input checks pending.
- IN PROGRESS: World list and CRUD/import/export forms wired to tested bridge;
  native file dialog and actual user interaction pending.
- IN PROGRESS: Ground/dimension/spawn editing and draft restore implemented;
  actual plugin settings persistence across Studio restarts pending.
- BLOCKED: Native installation and editor acceptance; requires Studio access.
Acceptance: perform documented editing steps without JSON edits; do not equate
syntax compilation/state tests with native UI validation.
Paths: studio/world-builder/{init.server,EditorState,Preview}.luau,
world-builder.project.json, tools/install-world-builder.js,
tests/WorldBuilderState.spec.luau.

## Phase 4 — Existing game integration (COMPLETE for automated behavior; depends on 2)
- COMPLETE: Reuse existing catalog/selector/placement, including empty worlds.
- COMPLETE: Generated native templates share BattleWorksAssets/Builtin with imports.
- COMPLETE: Dimensions, ground, boundaries and actual collider spawn validation.
- COMPLETE: Authored spawn/reset poses and separate additional-player spawn rows.
- COMPLETE: Preserve contact solver, weapons, recoil, BW, scanner object metadata,
  solid/indestructible fences and destructible objects; regression tests pass.
- COMPLETE: Production uses a world only after explicit repository publication;
  default arena remains the fallback and development selection stays independent.
- COMPLETE: Real compiler output feeds real server entrypoint in Studio/published
  integration scenarios; movement blocking, reset and multiplayer state tested.
- BLOCKED: Actual mesh rendering, native controls, Play/Stop and multiplayer Studio
  verification; exact steps documented.
Acceptance: compiled builder metadata loads through production server simulation.
Paths: src/shared/{AssetPaths,WorldSettings}.luau, src/server/{LocalBattle,
StudioWorldSelector,StudioAssetPlacement,init.server}.luau,
tests/{BuilderIntegrationSetup,BuilderServerIntegration,WorldSettings}.luau,
scripts/check.mjs groups 21–22.

## Phase 5 — Documentation/usability (COMPLETE for source/docs; depends on 3–4)
- COMPLETE: Status/errors, exact asset paths, camera/selection guidance implemented.
- COMPLETE: One-time installation, bridge/Rojo launcher and daily save/test workflow.
- COMPLETE: Portable export/import, safe deletion, publication and native asset steps.
- COMPLETE: Practical object/history/request/preview limits and extension boundaries.
- BLOCKED: Native usability assessment (palette drag behavior, keyboard shortcut
  precedence and camera interaction), to be measured in Studio.
Acceptance: automated pipeline removes per-world JSON/registration/config edits;
remaining one-time native steps and unverified actions are explicit.
Paths: docs/{WORLD_BUILDER,ASSET_PATHS,ASSET_PERSISTENCE,WORLD_COMPILER}.md,
README.md, assets/roblox/README.md.

## Phase 6 — Verification (IN PROGRESS; depends on all above)
- COMPLETE: All 75 Node tests pass, including real Rojo nested native asset builds.
- COMPLETE: Full Luau runner passes all 23 groups, with existing gameplay regressions.
- COMPLETE: Editor-state 19 assertions, world-settings 8, path traversal 12; generated
  Studio integration 268 assertions and published-server integration 264 pass.
- COMPLETE: Both .rbxl and .rbxlx place builds; separate plugin .rbxm build.
- COMPLETE: Final focused syntax/state/placement checks and git diff --check.
- BLOCKED: Native create→save→close/reopen→modify→select→Play test with two tanks.
- BLOCKED: Native drag/handles/multi-select/undo, file dialog, previews and restart.
- BLOCKED: Native missing asset/rendering/performance and multi-client verification.
Acceptance: automated results reported separately; manual procedure in WORLD_BUILDER.md
must be performed before declaring the complete Studio milestone validated.

## Added requirement — hierarchical asset identities (COMPLETE)
- COMPLETE: Canonical case-sensitive forward-slash paths relative to BattleWorksAssets.
- COMPLETE: Exact folder traversal; legacy basenames/GLB aliases only if unambiguous.
- COMPLETE: Recursive native export discovery and actual Studio inventory discovery.
- COMPLETE: Duplicate basenames remain separate, with no flattening/auto-renaming.
- COMPLETE: Canonical object `asset` field survives JSON save/export/import.
- COMPLETE: Compiler path validation and optional strict registry resolution.
- COMPLETE: Clear missing path/segment, invalid path and ambiguity diagnostics.
- COMPLETE: Tests for nested native packaging, compiler/loader lookup and round trips.
Acceptance: Buildings/Houses/Fence and Structures/Fences/Fence preserve identity;
ambiguous bare Fence fails. Existing root models were not moved or renamed.
Paths: tools/world/asset-path.js, src/shared/AssetPaths.luau,
tests/{asset-paths.test.js,AssetPaths.spec.luau,asset-persistence.test.js}.

## Decisions, limitations and next required action
- v2 is an authoring adapter; v1 source worlds remain supported and unchanged in layout.
- Initial limit is 512 objects, not thousands. Native performance is unmeasured.
- Flat Y=0 ground and rectangular boundaries reflect current physics. Elevation,
  elevated drivable bridges, nonrectangular bounds and arbitrary hazards are deferred.
- Ground appearance/catalog defaults supported; arbitrary mesh recoloring/material
  editing is not implemented. Existing water/mud behaviors are reused.
- One-time Studio mesh import/export remains necessary; model bytes are never
  reconstructed by the bridge. There are no real mesh exports in this checkout;
  tree/fence appearance needs the user's native assets. Built-in demo needs none.
- If StudioTestService is unavailable, Test saves/selects and explicitly asks for
  ordinary Play/F5; it never pretends a playtest was launched.
- Publication registers repository gameplay settings; no Roblox cloud upload occurs.
- No music work and no commits/pushes were performed.
- Next action: install plugin and execute the numbered native acceptance procedure.

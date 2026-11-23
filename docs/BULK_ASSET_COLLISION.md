# Automatic collision processing for imported assets

Run the existing command after importing/exporting models and adding their source GLBs:

```
node tools/build-editor-catalog.js
```

Rojo sync, then restart Play. The command regenerates collision profiles for **every imported catalog asset**, with no category exclusions and no per-model registration. Fences, roofs, trees, rocks, decorations, buildings and bridges all go through it. Solid remains an author-controlled property: a fence can support a tank if Solid is enabled and the tank can reach its actual top surface. Existing HP/destructibility, IDs, hierarchy, scaling and saved world references remain unchanged. Builtin procedural assets keep their existing colliders.

`worlds/asset-collision-generation.json` enables the bulk pass and maps native model folders to source directories. The existing native spelling `Surburban` explicitly maps to `GLBs/suburban`; it is not renamed. New matching files in those folders are processed on the next run. Registered aliases retain their identity and use their full palette/native path or existing GLB source reference. There is no cross-folder basename guessing. New source directories need a folder mapping once, not an entry for each asset. While enabled, this bulk pass replaces the legacy opt-in profiles/fractions; the legacy profile file remains available when bulk generation is disabled.

## Generated geometry

The GLB reader extracts top faces, searches downward-facing geometry for their undersides, and retains real vertical wall faces. Raised decks and rails therefore do not automatically become columns extending to ground. Upward faces become bounded convex prisms, and vertical faces become thin blocking polygons. The thin-wall thickness is ten times the solver's contact skin (0.001 stud total); it provides stable SAT/CCD contacts rather than a large enclosing box. Support still uses the actual top triangles and the existing footprint-aware ground solver. Walkable slopes and step height remain governed by the chassis physics.

Normalized profile coordinates are rounded to six decimals for bulk metadata, retaining full precision if rounding would collapse a triangle. Render models, source GLBs, model names and native bundles are never rewritten. Registered trunk fractions are replaced with the full generated surface geometry when bulk processing is enabled; solid tree canopies can consequently support tanks too.

This remains an approximation: underside sampling and each triangle's constant prism base can be conservative around complex curved/arched/internal geometry. Retained side faces preserve ordinary walls/posts. It is not a general closed-mesh Boolean decomposition or a new native mesh physics engine. Use Studio to check clearance, particularly intricate imported models.

## Coverage and diagnostics

`assets/collision-report.json` lists the selected source, face/wall counts, fallback reason and native model availability for each asset. The CLI prints a summary and fallback reasons.

Current native bundle: **60 imported models processed, 59 GLB face profiles and one native-sampling fallback**. Forest/character-archer is skinned and is unsupported by the static source reader, so it uses the existing native mesh sampler. The report also contains the old registered rope-fence reference whose native model is missing; this registration is preserved and remains unavailable. It is not silently rebound to a different fence.

Missing source files, unsupported encodings/skin data and profile budgets select native mesh sampling with an explicit report entry. If source/native dimensions disagree at runtime, publication logs the asset and reason and uses native sampling rather than hiding the model. Player-world validation still uses the authoritative published catalog and rejects client-supplied collision claims. A native sampler failure retains its existing conservative full-box fallback and warning.

## Catalog size

Bulk geometry exceeds Roblox's [200,000-character StringValue limit](https://create.roblox.com/docs/reference/engine/classes/StringValue). Catalogs now retain the existing StringValue root and use bounded numbered child strings when needed. Source packaging, server publication, server world validation and the client editor all use the same codec; small catalogs remain compatible. Chunks preserve Unicode boundaries, and clients wait briefly for missing replicated chunks rather than decoding a partial catalog. The current catalog uses 15 chunks. Collision data stays in catalog metadata, not player save documents.

## Validation

Automated checks cover whole-catalog coverage and source mapping, preserved author flags/IDs, fence and bridge underside geometry, vertical fence CCD, shared destruction/reset, catalog chunk limits/Unicode/missing replication, and the existing terrain/elevation/snapping systems.

In Studio, restart Play after sync and verify:

1. Forest and Surburban fences both appear; reachable Solid tops can support tanks, and side walls block them.
2. Forest bridge/raised platforms preserve travel below decks and support above. Check doorway and rail openings visually.
3. Buildings retain solid walls and roofs; trees use their actual generated surfaces.
4. Archer fallback remains selectable and queryable. Watch server warnings for source/native dimension or native sampling failures.
5. Save/reload an existing world and join with two clients. Check collision, damage, destruction and reset agree.
6. Assess startup/catalog replication and physics cost on the Windows laptop with representative numbers of Solid detailed models. Face profiles cost more than one bounding box; the generator does not auto-enable Solid on decorative placements.

No game/place build is needed; only metadata is regenerated.

## Authoring collision slabs in Blender

1. Keep the visible boards and ropes as ordinary mesh objects. Add simple, closed deck slabs with upward-facing top faces. Name each **object** `COLLISION_Deck_01`, `COLLISION_Deck_02`, and so on. The prefix is case-insensitive and applies to the exported glTF node name. A parent may carry transforms, but name each collider mesh individually. Unmarked children remain visual.
2. Export both visual and collision meshes together as the original GLB in the matching source folder. Keep the slabs inside the combined visual bounds. Align neighboring top faces where the tank should drive across them and leave physical gaps where it should lose support.
3. Generate a visual-only copy for Studio. For example, from the repository root:

   ```sh
   node tools/glb-collision.js GLBs/forest/rope-bridge.glb /tmp/rope-bridge-visual.glb
   ```

   Choose a new output file each time. The preparer strips the collider mesh references and preserves the visual hierarchy and transforms. Import the generated copy into Studio, then export the native model under the matching asset name in `assets/roblox`. Keep the original mixed GLB as the catalog's source.
4. Run `node tools/build-editor-catalog.js`, sync with Rojo, and restart Play. Enable **Solid** on the bridge placement. The collision report marks the profile with `explicitCollision: true`.

For these assets, tank movement and ground support use the explicit slabs. Decorative ropes remain available to the existing projectile and scanner queries. Each slab uses its own underside faces, and the profile keeps separate surface triangles and walls. Invalid explicit profiles fail catalog generation. A native export that still contains a `COLLISION_` node is rejected so the proxy cannot appear as scenery. GLBs without named collision meshes continue through the regular profile and fallback paths.

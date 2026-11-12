# Offline world compiler v1

Dependency-free Node.js 18+ tools. This is an offline placement compiler, not a renderer, physics engine, asset importer or world editor. It does not read GLB files.

## Files and commands

- `tools/build-world.js`: CLI.
- `tools/world/compiler.js`: registry resolution, overrides, validation, deterministic placement/manifest.
- `tools/world/path.js`: supported SVG parser, curve flattening, arc-length lookup and even-odd containment.
- `tools/world/transform.js`: transform math.
- `worlds/definitions/*.json`: reusable registries; each file is `{"definitions": {"unique_id": definition}}`.
- `worlds/*.json`: worlds containing explicit instances and registry-file references.
- `build/worlds/*.json`: generated manifests, ignored by Git.
- `tests/world-compiler.test.js`: standalone Node tests, also invoked by the existing full check runner.

```sh
node tools/build-world.js worlds/example.json --output build/worlds/example.json
node tools/build-world.js worlds/example.json --validate
node --test tests/world-compiler.test.js
```

`--validate` performs full resolution, placement and validation, but writes nothing. It cannot be combined with `--output`. Omitting output writes `build/worlds/<input basename>`. Failed validation does not write a partial manifest. Errors identify file, instance/definition and property. Builds summarize objects, definitions used and generated path segments. A segment may expand a whole group, so path segment count is not necessarily leaf object count.

The example produces **157 objects**, **18 definitions used**, **76 path placements**, with fictional resources. It combines two transformed villages, roads/fences, dry and wet rock regions, a train with five repeated cargo groups, supply repetition and a house with replaced children.

## World and registry shape

```json
{
  "version": 1,
  "id": "forest_arena",
  "name": "Forest Arena",
  "seed": "forest-v1",
  "definitionFiles": ["definitions/example-assets.json"],
  "definitions": {},
  "instances": [
    {"id": "west", "ref": "village", "position": [-60, 0, 0]},
    {"id": "east", "ref": "village", "position": [65, 0, 0], "rotation": [0, 90, 0]},
    {"id": "gate_fence", "ref": "wood_fence", "path": "M0 0 H24 V12", "spacing": 6}
  ]
}
```

Registry file paths are relative to the world file, independent of the shell working directory. Registries are merged by unique ID; duplicate IDs across files or inline definitions fail. World `id` and `name` are optional (file stem defaults; unsafe ID characters become underscores); explicit IDs are recommended for Studio registration. Seeds are strings or safe integers, default `0`. Local IDs use letters, digits, `_ . : -`, start with a letter/digit/underscore, and cannot include `/`. Root instances and each group child require explicit sibling-unique IDs. JSON property names `__proto__`, `prototype` and `constructor` are reserved. Definition types are fixed; an instance cannot switch its referenced type.

All registry entries, including unused entries and child overrides, are validated. Missing references and reference cycles fail with a chain such as `village -> house -> village`. Root definition inheritance uses `ref` too, e.g. `"weathered_house": {"ref":"house", "children":[...]}`. Recursive definition references are prohibited even if an override could terminate recursion.

## Types

A model references one symbolic asset or a candidate group:

```json
{
  "type": "model",
  "asset": {
    "selection": "weighted",
    "items": [
      {"path": "fictional/fence_straight.glb", "weight": 5},
      {"path": "fictional/fence_crooked.glb", "weight": 1, "rotation": [0, 180, 0], "scale": 0.95}
    ]
  },
  "influences": {"physical": {"mass": 70, "movable": true, "destructible": true, "hp": 90}}
}
```

`asset` also accepts a string ending `.glb`. `selection` is `single` (first candidate), `random` (uniform), or `weighted` (default weight 1, nonnegative weights, positive total). Every candidate may supply rotation/scale corrections, applied after the model's own transform. GLBs need not exist. Asset paths never trigger imports or conversion.

A group has `type: "group"` and `children: [{"id":"building","ref":"building"}, ...]`. Children can reference any supported type. Groups are logical hierarchy/transform containers, not welds or physical bodies. Only model leaves appear in the manifest.

A path has `type: "path"`, `path` (SVG string), `spacing` and `item: {"ref":"wood_fence_section"}`. Optional properties:

- `overlap`: studs subtracted from spacing; default 0, must be smaller than spacing.
- `orientToPath`: default true; aligns asset local **-Z** to the tangent.
- `positionJitter`: nonnegative XYZ half-widths, default `[0,0,0]`.
- `rotationJitter`: nonnegative XYZ Euler half-widths in degrees, default `[0,0,0]`.
- `curveSamples`: 4..512 straight samples per cubic, default 32.

Supported commands are `M m L l H h V v C c S s Z z`, including implicit repeated coordinates, relative commands and reflected smooth controls. Other commands fail validation. Each subpath restarts spacing at its own start; no placement crosses a moveto gap. Open paths include an endpoint only if it is on the spacing grid. Closed paths exclude duplicate endpoints. At an exact corner the incoming segment supplies the tangent. Cubics are flattened at fixed parameter steps, then sampled along the resulting polyline's cumulative lengths; spacing is approximately uniform in the original curve's arc length. Increase `curveSamples` for tighter curves.

A region has `type: "region"`, a closed `path`, fixed `count` and `item`. Every subpath must close with `Z`; use simple nonzero-area polygons/flattened curves. Even-odd fill supports holes/disjoint subpaths. Optional `minSeparation` defaults to 0, `randomRotation` adds a uniform yaw, `rotationJitter` adds Euler jitter, and `scaleRange: [minimum,maximum]` samples one uniform positive scale multiplier. `maxAttempts` defaults to `max(1,count*100)` **total candidate attempts**, maximum 1,000,000. Failure to place the full count is an error with the placed/requested count, never a silent partial world.

Region containment/separation concern **placement anchors in region-local XZ units**, not model dimensions, collision geometry or item-local position corrections. Parent scaling also scales this separation. No overlap tests are performed against buildings, other regions or model bounds.

A repeat definition has `type: "repeat"`, `count`, `offset: [x,y,z]`, and `item`. Any instance may also use:

```json
{"id":"cars", "ref":"cargo_car", "position":[0,0,-12], "repeat":{"count":5,"offset":[0,0,-12]}}
```

This applies the resolved instance transform once, then offsets copies in its local axes. Parent rotation/scale affect offsets. Copies receive `repeat_000`, `repeat_001`, etc.; paths use `segment_000`; regions use `scatter_000`. Zero repeats/counts are valid.

## Overrides, transforms and influences

Scalars/null replace inherited values. Arrays replace entire arrays. Objects merge recursively. Explicit instance properties override resolved definition defaults. `children` replaces the entire child array; there is no child-ID patching. Null does not delete a field: if null is invalid for that field, validation fails.

Coordinates are Roblox-compatible **XYZ, Y-up**, measured in authored studs; SVG `(x,y)` becomes local `(X,0,Z)`. Rotations are XYZ degree arrays. Position/rotation/scale are local. Positive scale may be a number or XYZ vector. Zero/negative scale is deliberately unsupported in v1.

Matrices use column vectors and column-major storage. Local transform is **T × Rx × Ry × Rz × S**: scale first, then Z, Y, X rotations, then translation. Child world matrix is `parentWorld × childLocal`. Generator placement transforms come before the referenced item's local transform; selected candidate corrections come last. Jitter is in generator-local axes/Euler components.

Output contains world `position`, column-length `scale` and the authoritative 16-number `transform` matrix. No lossy Euler decomposition is attempted. Nested nonuniform scales/rotations may introduce shear; the full matrix preserves it. A future Roblox loader must handle or explicitly reject unsupported shear rather than silently dropping it. Metadata vector fields (for example a future wind vector) are preserved as data, not automatically transformed.

Influences inherit from containers to leaves, merging objects recursively; a child's own definition/instance fields override inherited container fields. No group mass aggregation is implied. Known validation covers nonnegative physical `mass`, `friction`, `hp`, booleans `movable`, `destructible`/`indestructible`, movement `traversable`, nonnegative `tractionMultiplier`/`speedMultiplier` and a nonempty `collision` category. Prefer one explicit destruction flag; if both exist they must agree. **HP=0 never implies indestructibility.** Unknown influence categories/fields remain finite JSON metadata, allowing future wind/water/damage extensions. None is simulated here.

## Determinism and manifest contract

Random streams use SHA-256 of `[worldSeed, hierarchicalInstanceID, purpose]`, followed by a deterministic 32-bit PRNG. Asset selection, position, rotation and scale use independent streams. IDs are explicit, not based on sibling array positions; adding/reordering unrelated instances/definitions does not reshuffle existing choices. Renaming/moving a logical instance ID changes its random identity. Generator indexes are stable while that generator's geometry/order is unchanged. Changing a region's boundary/separation naturally changes its own accepted placements.

The manifest is versioned, includes world ID/name/seed, coordinate conventions, stats and ID-sorted objects. Keys serialize in canonical order with no timestamps or machine-specific source paths. Each leaf has `id`, `source` (nearest referenced definition), `asset`, `position`, `scale`, full `transform`, `influences` and optional provenance (reference chain, candidate and generator details). A loader needs neither SVG parsing nor definition resolution. Programmatic `compileWorld(world, registry, {provenance:false})` disables provenance; CLI retains provenance.

Safety bounds: 64 levels of reference/JSON nesting, 100,000 output objects, 200,000 expanded/validation nodes, counts up to 10,000, 100,000 characters per SVG and 200,000 flattened curve samples. Extremely dense/impossible requests fail. This targets modest authored worlds; scattering is a simple bounded rejection algorithm, not optimized packing.

To add real assets later, replace symbolic paths with your resource catalog paths and retain sensible pivots, units, forward axis and corrections. Compilation still will not open or import those resources. A separate integration milestone should map paths to approved Roblox assets and implement a small server-authoritative manifest loader. The compiler itself implements no editor, runtime world loading, collision/pushing/damage calculations, GLB conversion, terrain meshes, train motion or animation. The separate Studio-only single-model smoke test is documented in TREE_ASSET_TEST.md.

See [WORLD_SELECTOR.md](WORLD_SELECTOR.md) for the Studio-only catalog/selection milestone.


## World-wide asset units

Optional world-level `"assetScale": 45` converts model assets to the game's stud
scale. It defaults to 1 and must be finite and positive. It multiplies every
model's resolved scale once, including models inside groups, repeats, regions
and paths. It does **not** multiply world positions, group offsets, SVG geometry,
spacing or separation distances. Local definition/instance and candidate scales
remain additional multipliers. This allows Kenney assets to share one conversion
without multiplying the entire arena layout or manually scaling every panel.
The manifest already contains the final transform; loaders must not scale again.

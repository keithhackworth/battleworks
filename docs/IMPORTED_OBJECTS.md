# Imported tree collision and durability

The existing Studio imported-model placement path now accepts fixed, solid,
weapon-destructible objects. No GLB importer or separate physics engine is added.
The imported template stays unchanged; the placed clone owns its gameplay state.

Example world instance (already configured in `worlds/tree-test.json`):

```json
{
  "id": "tree-large",
  "ref": "tree_large",
  "position": [0, 0, 0],
  "rotation": [0, 0, 0],
  "scale": 45,
  "influences": {
    "physical": {"movable": false, "destructible": true, "hp": 150},
    "movement": {"collision": "solid", "traversable": false}
  }
}
```

Recompile and register after changing a world:

```sh
node tools/build-world.js worlds/tree-test.json --output build/worlds/tree-test.json
node tools/register-worlds.js
```

Sync/build with the exported native model included, select `tree_test` through
`ServerStorage/BattleWorksStudio/SelectedWorld`, then start a new Play session.
See [asset persistence](ASSET_PERSISTENCE.md) and [tree import](TREE_ASSET_TEST.md).

## Runtime behavior

- A small invisible trunk proxy receives server projectile hits and participates
  in the existing swept tank contact solver. The canopy remains cosmetic.
- Normal weapon damage reduces tree HP once per projectile. Both manual and BW
  driving use the same obstacle solver. Solid proxies also block scanner queries.
- At zero HP, the clone disappears with a brief wood-chip effect; its blocker and
  projectile/scanner query proxy are removed from operation immediately. There is
  no fallen tree or tipping simulation.
- Reset Battle (or map redraw) restores the tree's HP, original visibility and
  blocker, and clears transient chips. Scenery is shared: any player's battle
  reset restores it for the entire server.
- Model attributes expose `WorldObjectId`, `Health`, `MaxHealth`, `Destructible`,
  `Destroyed` and `Solid`. These are server state, not client damage requests.

## Supported profile and tuning

`physical.movable` must be false or omitted. `destructible` explicitly enables
weapon damage; `indestructible` is its inverse if used. HP defaults to 100 and
must be nonnegative. HP=0 never means indestructible. A destructible object with
zero initial HP starts destroyed. Omitted destruction flags mean no destruction.
`movement.collision` supports `solid` and `none`; `traversable: false` also enables
blocking. Contradictory flags are rejected. With neither blocking nor destruction,
the model remains decorative.

`worlds/roblox-assets.json` keeps the reusable tree's collider proportions separate
from world placement. `widthFraction`, `depthFraction` and `heightFraction` must
be in (0,1]. Currently they are 0.18, 0.18 and 0.45. The proxy uses those fractions
of the placed bounding dimensions, is centered horizontally and starts at ground
height. This is an approximate trunk, not mesh collision. Verify alignment and
scale with the actual imported tree in Studio; tune the fractions if needed.

Interactive models must remain upright (yaw rotation only) with positive uniform
scale. Up to 512 mapped placements are supported per world. Pushing, tipping,
mass/friction/traction effects and other influence categories are unsupported in
this placement path: registration reports the specific unsupported property and
keeps that world preview-only. The offline compiler still preserves richer
metadata for future loaders.

## Verification boundaries

Automated tests exercise registration, flag validation, the real contact solver,
projectile overlap/damage, stuck detection, destruction and reset using numeric
model doubles. They do not validate native imported mesh rendering, materials,
trunk alignment, or the live Studio controls. Those require a Play test with the
exported `tree-large` model present.

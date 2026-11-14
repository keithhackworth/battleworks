# Multiplayer Milestone 1

A second battle participant entering from Play BattleWorks promotes the running
solo test to a shared battle. Players at Main Menu do not participate; see
[application shell](APPLICATION_SHELL.md).
Existing tanks, selections, programs and positions survive that transition.
Ownership remains `battles[userId].tanks[tankId]`; a player can own multiple tanks.
The current starter loadout remains the persistent Boomer/Rattler pair. Selecting
one changes manual control, not ownership or the other tank's lifecycle. This
milestone adds no team system or new loadout management.

## Existing architecture reused

- `init.server.luau` owns fixed-step movement, contacts, weapon timing, shell
  sweeps, snapshots and remote validation. Clients send intent only.
- `InputCommand` validates finite values, modes and types. The existing 60 Hz
  server packet limit, 30 Hz client send cadence and 0.35-second stale-input
  timeout remain. Keyboard/mouse, touch and gamepad providers are unchanged.
- Ownership lookup scopes manual input, BW Run/Stop and hardware requests to
  the sender's collection. Manual input additionally requires selection.
- Snapshots broadcast every tank's authoritative position, body/turret angles,
  firing, health, injury effects and generation. Existing Shot/PrepareShot
  broadcasts and replicated server shell/impact parts provide firing effects.
- `TankRenderers` already handles late join, removal and generation changes.
  Camera and editor remain bound to the player's selected owned tank.

## Added lifecycle and combat behavior

Cross-owner projectile hits now use the same `LocalBattle.damage` and injury
system as the solo pair. Damage values come from server weapon definitions;
there is no client damage or hit remote. Self hits remain rejected. Each tank
has an independent three-second respawn deadline. Respawn uses the existing
reset path, increments generation, restores health, clears weapon/input/BW and
injury state, and re-enables its authoritative hitbox.

Spawn assignment checks current tanks (including wrecks), practice targets,
authored solid objects and arena tree contacts. It preserves authored spawn
headings/rows when available, then searches a bounded grid inside the map.
Occupied respawns retry after one second. A joining tank without space has
`waitingForSpawn=true`, zero health and a disabled hitbox, and stays outside
movement/contact simulation until a safe spawn becomes available.

Disconnect destroys every tank in the owner's collection, its hitboxes and
in-flight shells, and stops its programs. Vacated player spawn indices can be
reused. A shared battle stays shared while any players remain; after everyone
leaves, a new first player gets the original solo lifecycle.

Solo reset/winner behavior remains. In shared play the private Reset Battle
request is ignored and its button is hidden so it cannot heal a collection, bypass the respawn timer or
restore shared destructible scenery. The existing HUD reports automatic
respawning. Studio-only map redraw remains a development tool.

`Workspace.SoloTankPairs=true` explicitly preserves isolated pair behavior for
historical Studio regression fixtures. Leave it absent for multiplayer tests;
published play always ignores this fixture override. World selection and the
world-builder plugin retain their existing startup and authoring paths.

## Automated verification

Run the full existing Node/Luau suite, including the new production-server
multiplayer integration group:

```sh
node scripts/check.mjs /path/to/luau-web/src/index.js
```

`tests/Multiplayer.spec.luau` covers multi-tank ownership, rejected foreign
input/BW/hardware actions, malformed and rate-limited commands, stale input,
ignored client hit/health claims, movement/turret replication, damage in both
directions through real projectile handling, destruction, delayed respawn,
occupied spawn retries, persistent selection, late join, renderer generation
replacement, disconnect cleanup (including live shells), rejoin and empty-server
cleanup. Existing suites retain solo, input-provider, physics, world selection,
world-builder and published-world coverage.

Build both place formats and the unchanged authoring plugin:

```sh
rojo build default.project.json -o /tmp/battleworks-multiplayer.rbxl
rojo build default.project.json -o /tmp/battleworks-multiplayer.rbxlx
rojo build world-builder.project.json -o /tmp/battleworks-world-builder.rbxm
```

Verified in this workspace: 75 Node tests, all 24 Luau groups (including 1,731
assertions in the multiplayer production harness), syntax compilation of 77
source files, both place builds, the plugin build and `git diff --check`.

## Studio acceptance still required

Mocks and builds do not verify native Roblox rendering or network delivery.

1. Start a server with two clients, with `SoloTankPairs` absent. Choose Play
   BattleWorks → Enter Battle on both. Check both owned
   tank collections have distinct positions. Move and aim on both clients;
   verify each sees the other's body and turret movement.
2. Use keyboard/mouse, touch emulation and gamepad separately. Confirm text focus,
   tank selection and BW ownership still release/resume the same input providers.
3. Fire both weapon types at the other player's tanks. Verify effects and health
   agree on both clients, wrecks stop accepting input/hits, and each destroyed
   tank respawns after three seconds with fresh health and controls.
4. Select another owned tank during combat. Verify its independent state and that
   neither player can take control of the other's collection.
5. Join a third client after combat starts; disconnect clients while moving,
   running BW and firing; reconnect. Check no ghost tanks, shell models or stale
   health/renderer generations remain.
6. Repeat in the default weather world and a world-builder authored/published
   world. Verify solid scenery and occupied spawn areas are respected. Check
   shared Reset Battle cannot reset scenery or bypass respawn.
7. Repeat with network latency/loss emulation, including a shot immediately around
   respawn and a late join during combat. Check snapshot recovery and camera pose.
8. Start a fresh single-client session and confirm the original pair selection,
   local duel, winner and Reset Battle behavior.

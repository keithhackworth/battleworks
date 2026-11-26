# Battle Royale Milestone 1

Battle Royale is the default startup mode. Players start on Home and select **Training Grounds** to join one continuous, server-authoritative battlefield on foot, approach an available public tank and use its proximity prompt to enter. Exit ejects the Roblox character just above the tank with an upward jump. There are no rounds, elimination, score, rewards or personal tank collections in this mode.

## Configuration and controls

In Edit mode, under **ServerStorage → BattleWorksStudio**:

| Setting | Default | Behavior |
| --- | --- | --- |
| GameMode | BattleRoyale | Use Classic for the existing lobby, owned collections and saved-world launch workflow. Restart Play after changing. |
| PublicTankCount | 15 | Integer 2–100. Pool slots retry when the world has no safe spawn. |
| PlaygroundBWEnabled | true | Set this BoolValue to false before Play to disable both built-in personality programs and BW Editor runs in Battle Royale. |
| PublicTankReplenishDelay | 5 | Seconds, 1–60, from destruction to retirement/replacement. |

Workspace attribute `BattleWorksGameMode` can explicitly override GameMode with `Classic` or `BattleRoyale` for development/tests. Historical test fixtures explicitly select Classic. Published places also default to BattleRoyale if configuration is absent. World selection, source assets and the existing loaded-world simulation are reused. The default arena uses Normal weather (grass, no wind). Set Workspace attribute `ArenaWeather=IceWind` explicitly to select the optional ice/wind preset.

- On foot: normal Roblox movement, jump and camera, including default mobile thumbstick and gamepad controls.
- Enter: approach within 12 studs and use **E**, **controller X**, or the native touch proximity button. Prompt hold is 0.2 seconds; availability is server-controlled and distance is independently validated.
- In tank: existing keyboard/mouse, touch and gamepad input providers, aiming, firing, HUD and battlefield camera.
- Exit: **F**, **controller B** outside text entry, or **Exit Tank** in the HUD. Text entry is protected from the keyboard/gamepad exit binding.
- BW Editor remains accessible while occupying a tank. Supported programs use the current Bunny CPU/bus limits; built-in personalities use their default balanced bus tuning. Main Menu → Garage saves a session setup for manual control. Computer upgrades are rejected in this mode.

The repeating pool variety is tracked/cannon, wheeled/Gatling, tracked/Gatling and wheeled/cannon. All use the existing standard chassis, installed drivetrain/mobility/weapon components and **Bunny computer**. No new weapon or physics model was added. Computer hardware/bus configuration resets on release; health, position, turret pose, heat and existing physical momentum are retained.

## Ownership, occupancy and authority

Public IDs are arena slot IDs (`public:1`, etc.). Their owner is the arena (`owner=0`/OwnerId=0), independent of temporary occupantUserId. Battle membership remains keyed by player. The existing battle record's tanks/selected fields expose only the currently controlled public tank in Royale, never a permanent owned collection. Classic mode retains multiple owned tanks per player unchanged.

BattleRoyale performs synchronous occupancy assignment before character presentation changes. One player can occupy one tank and one tank can have one occupant. A slot advances its controlEpoch at entry, release and replacement. All manual input, BW Run/Stop and hardware requests carry that epoch and are authorized against the sender's live character, current membership, current selected tank, occupant and tank health. Rate limiting, input validation, stale-input expiry and BW request ordering remain active. A previous lease cannot control a new occupant, a replenished tank or the same tank after rejoining.

The RoyaleControl remote accepts only bounded monotonic request IDs and Sync/Enter/Exit actions. Prompt instances are replaced on release so delayed interactions with an old prompt cannot reacquire a tank. Native prompts call the same entry path and also validate server distance, life and availability. Prompt Enabled/MaxActivationDistance are presentation, not trusted authorization. The client cannot set occupancy, spawn tanks, choose components, report damage/hits or modify health.

Control acknowledgments have a monotonic per-participation revision. Royale snapshots continue rendering the shared battlefield but cannot change client control selection. Older/duplicate occupancy messages and mismatched-epoch diagnostics/output cannot restore a previous control state. Sync recovers admission if the initial message preceded client startup.

## Lifecycle and combat

Public tanks are created through the extracted existing tank factory and Battle.resetTank, with the existing bounded spawn/world/obstacle validation. The same Heartbeat simulation, tank contacts, terrain support, cannon windup, Gatling heat/recoil/trajectory, turret code, projectile impact damage and snapshots remain authoritative. The existing renderer registry creates one local visual representation per authoritative public ID/generation for every client; there are no extra client-created gameplay tanks.

RoyaleCharacters hides, anchors and disables collision/query participation for the occupant's avatar, including late-loaded accessories. On release it restores saved properties and native movement. Voluntary Exit bypasses the spawn search: the avatar appears above the tank's current world position with a 25-stud/second upward velocity and inherited horizontal momentum. Shared BattleRoyaleConfig defines EjectClearance (4 studs above the hull/turret envelope) and EjectSpeed (25). Death/disconnect/character replacement retain the separate safe-spawn restoration path. Initial character loading starts after the arena is ready. Native CharacterAutoLoads handles death respawns; CharacterAdded/Died handlers are scoped to the current participant/character and disconnected on departure. Character entry and respawn search for safe positions. Voluntary ejection stays at the current tank, including raised platforms, rather than relocating to an arena spawn.

Native floor/boundary/environment contacts are enabled for characters in Royale. Imported-world authoritative collider parts also support character collisions; tank bodies/art remain non-collidable and continue using VehicleContacts. World collider destruction removes character support too. Classic geometry behavior stays unchanged.

Exit, disconnect and character death cancel BW, discard its runtime/variables, clear held input, pending shots and scanner control, release occupancy and restore the avatar. Tanks are not repaired or teleported. Already released arena projectiles continue normally. Disconnect removes participation and character subscriptions; arena tanks remain available rather than being deleted.

Destruction stops motion/input/AI, disables interaction and authoritative hit queries, and releases/kills the occupant's character for native respawn. The existing renderer receives the dead state and injury effects during the replacement delay. The wreck then retires and the same arena slot receives a new generation and lease epoch at a safe spawn. If no safe space exists, the slot retries once per second. The player stays on foot and can take another available tank at any time. Neither personal respawn nor Reset Battle can bypass this path. The pool remains arena-owned when the server has no participants.

## Modules

| File | Responsibility |
| --- | --- |
| shared/BattleRoyaleConfig | Startup selection, validated counts/delay and existing component combinations. |
| server/BattleRoyale | Pool slots, occupancy leases, prompt validation, membership, release and replenishment. |
| server/RoyaleCharacters | Native avatar property capture, hiding/query isolation and safe restoration. |
| server/init.server | Existing world/combat loop; shared tank factory, Royale composition and existing action authorization adapters. |
| client/RoyaleClient | On-foot hint, control acknowledgments, native exit binding and one persistent battle client. |
| client/BattleClient | Existing rendering/input/HUD/camera with a separate temporary driving state. |
| client/InputController | Existing input providers plus explicit native-character control handoff. |

The application shell, screen manager, private World Editor, Garage placeholders, BW interpreter and Classic sessions remain present. Use Main Menu to access the existing shell. Its first option, The Playground, returns to the same running server on foot. Main Menu works both on foot and in a tank; it releases occupancy, stops BW/manual commands, and parks the hidden avatar with movement and collision disabled. Abandoned tanks retain health and position, and other players keep fighting. Returning restores normal character controls at a safe entry point. Request IDs fence canceled or delayed joins; respawning while in the menu remains isolated.

Private World Editor editing/saving remains available. Launching saved layouts into the arena requires Classic mode: Royale rejects arena replacement even when every player is in the menu, preserving the public pool and saved data.

## Multiplayer chat

The lower-left Chat dock uses native TextChatService rendering and managed input for the server's global channel. It persists on foot/in tanks, yields gameplay input while typing, and hides in the menu/editor. See [chat behavior and native validation](PLAYGROUND_CHAT.md).

## Terrain and hazards

The default Playground includes a ravine, river, bridge and sloped overlook, with server-side environmental deaths and designated dry respawns. Unsafe voluntary exits are rejected with visible feedback; safe exits retain the jump-out at the current tank. See [terrain implementation and native acceptance](PLAYGROUND_TERRAIN.md). Explicitly authored worlds and Classic keep their existing layouts.

## Verification and known limits

Automated production-server tests cover admission, all hardware combinations, non-overlapping spawns, proximity, simultaneous entry, unauthorized/malformed actions, stale input/requests/leases, exit/switching, abandonment, actual cross-player projectile damage, destruction, blocked replenishment, character death/rejoin, disconnect while moving/firing/running BW and late join. Production-client tests cover on-foot rendering, character/tank camera handoff, keyboard, touch, gamepad, focus loss, stale messages and repeated transitions without duplicate widgets/renderers. Existing Classic, world/editor, contact, input, BW and multiplayer assertions remain intact.

Native Roblox character physics, proximity UI, avatar loading, actual cross-device network delivery and camera feel still require Studio/published acceptance. On-foot weapon/infantry damage and tank-versus-avatar impacts are not implemented; this milestone provides tank combat with native on-foot traversal. This is a continuous pool, not a Battle Royale match/elimination system. CPU upgrades and custom tanks remain absent; the later fifteen-personality follow-up adds unattended Auto as described in the proving-ground guide. No matchmaking/friend-server placement is added; testers must join the same actual server.

### Exact two-player acceptance

1. Sync current source and set GameMode=BattleRoyale, PublicTankCount=15, delay=5. Clear a conflicting Workspace mode override. Use **Test → Server & Clients → 2 clients**, or have Keith and Shane join the same published server. Neither should see a menu or automatically occupy a tank.
2. Confirm each has a visible normal avatar, native movement/jump/camera and fifteen visible public tanks. Walk/touch/gamepad to a tank. Verify the E/X/touch prompt appears and available weapon/mobility combinations match their art.
3. Enter separate tanks. Check avatars disappear, default character movement stops, tank controls/camera/HUD activate once and both clients see each other's body/turret movement. Try simultaneous entry into one tank: only one may win.
4. Fire cannon and Gatling across players; verify authoritative health and effects agree. Confirm hidden avatars do not create invisible projectile cover at their old entry spots.
5. Exit while driving/firing or while running BW. Verify held input and pending preparation stop, avatar jumps out above the tank and camera/default touch controls return, and the abandoned tank retains health/location. Walk to another tank and switch; the other tester can take the abandoned tank. Programs must not transfer.
6. Destroy an occupied tank. Verify wreck effects, disabled prompt, native avatar death/respawn on foot, and a fresh arena-owned tank after five seconds. Occupy another tank immediately after character respawn and repeat indefinitely. Reset Battle/owned selection must not affect Royale.
7. Reset a character while occupying a healthy tank. Verify occupancy releases and the healthy tank remains available. Disconnect/rejoin during manual firing and BW execution; check no stuck avatar anchors, programs, hidden collision parts or orphan memberships remain.
8. Repeat enter/exit rapidly with latency/loss emulation and alt-tab/CoreGui/text focus. Reconnect a late client. Check stale input/acknowledgments cannot take control and each device resumes neutral controls.
9. Repeat on a selected authored world with ramps/raised geometry. Check native foot traversal and validated exits as well as unchanged tank collision/support.
10. On foot and while driving/firing/running BW, click Main Menu. Confirm the other player continues, the tank becomes available, and the menu avatar cannot interact. Choose The Playground and verify normal on-foot entry, camera, touch/gamepad controls and no duplicate UI. Repeat rapid leave/rejoin and reset while in the menu.
11. Restart with GameMode=Classic and confirm Main Menu, personal collection selection, private World Editor Save & Play and original combat/BW behavior. Confirm no Royale pool appears in Classic.

Build artifacts under /tmp and mocked tests do not establish native acceptance.

### Commands and workspace results (2026-11-18)

```sh
node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js
node scripts/check.mjs /tmp/battleworks-luau-check/node_modules/luau-web/src/index.js --syntax
rojo build default.project.json -o /tmp/battleworks-battle-royale-m1.rbxl
rojo build default.project.json -o /tmp/battleworks-battle-royale-m1.rbxlx
rojo build world-builder.project.json -o /tmp/battleworks-battle-royale-world-builder.rbxm
git diff --check
```

The established full runner passed **101 Node tests**, **46 isolated Luau groups**, and syntax compilation of **120 source files** plus the plugin source checks. After final lifecycle hardening, focused production tests pass **2,611 Royale server assertions**, **63 Royale client assertions**, and **36 world-object assertions**. The prior large bulk-geometry fixture is split across two isolated groups because Luau Web has a fixed heap; all its existing assertions remain covered. Main binary/XML places and plugin model build into `/tmp`; no developer place is overwritten. Native Studio acceptance remains pending.

### Team Test startup and Server view

Studio clients may have IsStudio=true while cloud Team Test servers have IsStudio=false. BattleClient treats RedrawMap as an optional capability: it never waits for that Studio-only remote before registering snapshots/rendering. A late RedrawMap is discovered without blocking startup. Native prompts, combat and tank rendering do not depend on development tools.

Tank artwork is client-rendered from authoritative snapshots. Studio's Server view consequently shows invisible TankHitbox parts, not the rendered tanks. Check the player/client windows for visible tanks. If those remain empty after sync and a full test restart, inspect that client's Output for errors; the startup markers now include “initializing Battle Royale client” and “Battle Royale client ready.”

Regression groups46/47 cover a Studio client without RedrawMap, late optional tool discovery, and an empty non-Studio server followed by joining players. Existing published-client and Classic client integration checks remain covered.

Current autonomous pool/controls supersede the original fixed repeating loadouts and stopped-on-release behavior: [fifteen-tank follow-up](PLAYGROUND_PROVING_GROUND.md#follow-up-fifteen-autonomous-public-tanks). Native acceptance should include Auto/Manual switching, named personalities and equal-share Bunny buses.

# The Playground: ravine and river

The default Playground arena now has two broad combat banks, a western sloped overlook, a 42-stud-deep ravine, and an unguarded wooden bridge. The bridge is 44 studs long and 24 studs wide, allowing two tank lanes while leaving its edges dangerous. Land around either end of the ravine also connects the banks. Six public Bunny tanks and their existing weapons, occupancy, combat and five-second replenishment remain unchanged.

This layout applies only to BattleRoyale mode's default arena. Classic mode and explicitly selected authored worlds retain their existing terrain. There is no world format or asset pipeline change. Sync with Rojo and restart the server to install the layout.

## Implementation

- `shared/PlaygroundTerrain` describes land, slope and bridge planes, designated dry spawn anchors, and hazard volumes. `Environment.sample/pose` delegates only for this arena. Chassis footprint contacts determine support; there is no hidden support across the ravine or barrier at bridge edges.
- `server/PlaygroundBuilder` builds matching native character/query geometry and removes the continuous floor from collision and queries. The bridge has no protective rails. River streaks animate locally through `client/PlaygroundPresentation`; the water is cosmetic, with no fluid/current forces or extra server animation traffic.
- The existing movement, contacts and gravity remain authoritative. `RattlerRecoil` now treats sudden support drops as falls and avoids clamping descending tanks to the new floor's recoil ceiling. Normal recoil height limits remain in place.
- The explicit river volume spans X=-22..22, Z=-75..65 and starts at Y=-27, above the visible water at -30. It extends below the ravine bed. A terrain-relative buried-body check also catches bodies below bank surfaces, avoiding stranded tanks under land. Low Y alone outside these regions is not a river hit.
- `BattleRoyale.step` checks living public tanks and active on-foot characters. Server-only `LocalBattle.environmentDamage` shares the ordinary fatal damage/effect cleanup; Cannon's existing explosion presentation is reused. The retired guard and slot generation prevent duplicate deaths or replacements. Native humanoid death respawns occupants and infantry.
- Public tanks and avatar respawns use designated land anchors and existing obstacle/occupancy checks. Bridge, cliff margins and occupied anchors are excluded. A full arena retries tank spawning; an avatar without a safe anchor dies and retries through native respawn rather than remaining at an unsafe default position.
- Safe voluntary exits keep the existing jump-out above the current tank, with inherited horizontal motion. Ground and predicted landing clearance are checked first. At a dangerous edge or during a fall, exit is denied with a visible reason; move to safe ground and try again. Exit never relocates a healthy player to the map center. Death, menu departure and disconnect still release control and use safe land restoration.

## Native two-player acceptance

Automated tests exercise production math, contacts, server hazards, damage, occupancy, pool lifecycle and client feedback. Native Roblox physics, replication and presentation still require this checklist:

1. Start a fresh default Playground server with two clients. Verify six tanks, dry on-foot entry and the bridge/river/overlook. Confirm no old Studio Baseplate or unrelated Terrain has been added under the ravine.
2. Enter different tanks and cross the bridge simultaneously in opposite lanes. Check movement, turret replication, cannon/Gatling combat and the western slope. Steer off the side: a tank must fall naturally, explode at the river, release its occupant and be replaced once after the configured delay.
3. Drive off a bank cliff and repeat. Remain on foot and jump into the ravine: verify death and a dry respawn away from every public tank. Destroy an occupied tank with weapons and confirm the same safe respawn/replenishment behavior.
4. Exit on open ground and at the center of the bridge: verify the jump-out stays at the tank. Try exiting close to an edge, with outward momentum, and mid-fall: verify refusal and readable feedback. Repeated exit requests must never detach control incorrectly.
5. Disconnect during a fall and repeat with BW running. The released tank must still die and replenish once; no commands or programs transfer to its next occupant. Test late joining and repeated character resets.
6. Repeat menu departure/re-entry, rapid switching, simultaneous entry, keyboard/mouse, touch and controller controls. Other players must continue fighting while one player is in the menu.
7. Restart in Classic and verify the original ground, editor/loaded worlds, support on imported meshes, combat, and normal recoil hops.

Known limits: the layout is fixed for the default arena; no terrain editor features, swimming/current physics, infantry combat, match rules or new weapons are added. Automated tests do not establish native two-player acceptance.

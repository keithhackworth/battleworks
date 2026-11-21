# Phase 3 bus configuration

Open **Main Menu → Garage**, choose the exact chassis and weapon combination, and adjust the four master allocations. Scanner and weapon tradeoffs appear immediately under their master sliders. The thumb tooltip and readout show effective values as you drag. Lower one allocation before raising another if the shared budget is full. Save the setup, then enter battle or take manual control of the matching public tank.

The server validates the installed loadout, allocation total, and tuning positions and derives all device specifications from the component catalog. Garage saves are private to the player's server session. They survive returning to the menu, switching matching tanks, and respawns in that server. They expire on disconnect. Classic uses the configured setup when creating the owned tank and preserves its prior bus layout until a setup is saved. Public tanks use the player's preference in Manual. Built-in Auto and vacant tanks use the personality default. A player-written BW program on a tuned tank uses that tank's current setup.

Configuration zones are a follow-up. The current authority boundary is Main Menu, where players have released their tank leases. The server rejects Garage saves while the player is in battle. No separate in-world configuration or protection mechanism is installed.

## Performance formulas

A Garage setup has a single 100-point budget and four categories. The installed computer keeps its existing cores, CPU budgets, and queue limits. All eight scanner directions retain independent commands and cooldowns.

Let `p(a) = 1 - (1 - a/100)^2` for the standard bus and let `t` be the secondary slider from 0 at the left endpoint through .5 at center to 1 at the right. The provisional left and right weights are `1 - .25t` and `.75 + .25t`. Master power multiplies both weights.

| Device | Effective behavior and limits |
| --- | --- |
| Drivetrain | The existing curve gives about 15 forward studs/s at 5% before terrain, or the full rating if the rating is lower. Forward, reverse, and tracked turning use that fraction. Wheels retain their steering angle and geometry. Terrain, traction, water, and slopes still apply. |
| Turret | `catalog traverse speed × p(master)` for yaw and pitch, from zero to the installed rating. Mechanical angle stops remain in force. |
| Scanner array | For `N` installed lenses, each reserves `master/N`. Cone is `catalog cone × (.60 + .40 × p(master/N) × left weight)`. Range uses the same expression with the right weight, then applies catalog distance effectiveness. Standard powered bounds are **9–15°** and **90–150 studs**. All eight installed lenses can work concurrently using their own shares. BW acquisition is catalog acquisition divided by the lens curve. Manual radar waits for that acquisition and keeps its sweep interval and physical cooldown as minimums. |
| Cannon | Projectile speed is `catalog speed × (.65 + .35 × p(master) × left weight)`, bounded by **15.6–24 studs/s** for the standard cannon. Reload interval is `catalog interval / (p(master) × right weight)`, with a physical minimum of **0.65 s**. Windup is `catalog windup / max(p(master), .0001)`, with a physical minimum of **0.20 s**. The interval starts when preparation starts. |
| Gatling | Same speed formula, bounded by **55.25–85 studs/s** for the standard Gatling. Round interval is `catalog interval / max(p(master) × right weight, .0001)`, with a physical minimum of **0.10 s**. It has no windup. Heat accumulation, maximum burst, and the **2 s** overheat lockout are mechanical. |

The scanner and projectile lower bounds are positive-power limits. At zero power a device cannot actuate. BW reports disabled readiness, no usable scanner geometry, and zero projectile speed for a Garage-configured weapon. Catalog upper bounds apply before the shared bus split or secondary tradeoff. For example, even with 100% dedicated to eight standard lenses, each lens has 12.5% allocation, so maximum attainable range is about **104.1 studs** and maximum cone is about **10.4°**, at opposite endpoints. Higher allocation can shorten operating time until the existing timer floor or a mechanical limit is reached. Weapon damage, projectile flight model and maximum travel, and the scanner ray/terrain budgets are independent of the sliders.

## Migration and BW observability

Existing per-lens allocations are summed into the array category. Configurations whose individual buses reserved more than 100 points in total are normalized proportionally when loaded as a Garage draft. Both secondary sliders start centered. The 15 existing public personalities retain their original sources and the same default per-device bus shares. Their revised scanner and weapon capabilities follow the new balanced tuning.

BW retains the physical `sensor0` through `sensor315` device entries and unchanged scan directions and instruction fees. `get_bus_configuration()` exposes the shared master allocations and slider positions. `get_tank_state()` exposes the effective lens geometry, acquisition, muzzle speed, readiness, and motion ratings. Successful `Scanner` results include effective range and cone. Scanner indicators still report completed acquisitions and observed objects. The Garage and BW use the same component and timing calculations as the simulation.

## Play-test in Studio

1. Sync the repository and start Play. Choose Main Menu → Garage, cycle to a chassis/weapon combination, and verify the previews while dragging master and secondary sliders. Saving and reopening the Garage should retain the setup in that server.
2. Enter a matching public tank manually. Compare `get_bus_configuration()`, `get_tank_state()`, and `get_weapon_speed()` to the Garage readouts. A successful scan should return the same range and cone. Check scan targets near the new cone and range boundaries.
3. Try both weapon types. Time cannon preparation and intervals, Gatling round spacing and overheat, and compare projectile travel using fixed-distance targets. Switch the public tank to built-in Auto and check that it restores its default. Repeat fire and scans with the relevant master allocation at zero.
4. Verify input and tooltip placement with desktop and touch. Repeat with two clients and confirm the saved setup follows its owner within the server.

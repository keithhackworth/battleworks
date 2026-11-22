# Responsive equipment and progression

## Existing architecture

- `BWParser`, `BWFunctionAnalysis`, and `BWExecution` compile BW into bounded instruction streams and run them cooperatively at fixed CPU cycles. Functions and device waits already yield inside the VM. The chassis computer tier currently bundles 1, 2, 4, 8, or 16 thread slots with per-thread ticks and device queue capacity. Existing programs may depend on that legacy budget.
- `BWDevices` already arbitrates shared drivetrain, turret, weapon, and per-lens scanner commands. Steering setpoints and continuous drive use explicit replacement rules. Timed commands use bounded FIFO queues. One authoritative simulation step consumes the resulting command.
- `ComponentCatalog`, `VehicleAssemblies`, and `VehicleComponents` resolve installed and validated specifications. `BWChassis` supports legacy multi-bus reservations and a four-category Garage budget. Garage drafts are server-validated and session-local. Purchasing, inventory, and chassis rank restrictions need their own policies.
- `DirectionalScanner`, `ScannerScene`, and `ScannerTerrain` provide bounded detection, visibility, terrain observations, and scan budgets. `LocalBattle` applies damage. The server projectile launch path and weapon readiness APIs are existing sources for future sound and readiness events. Use these authority boundaries for equipment producers.
- `PlayerWorldStorage` and `PlayerWorldService` persist authored worlds. There is no progression profile in that schema. The Playground scoreboard is server-session data. World editor and startup world loading already support authored geometry and starts that lab and boss worlds can reuse.

## Dependency order

1. **BW event runtime.** Compile named handler registrations, accept trusted host events into a bounded FIFO, dispatch only to idle threads, and run event-enabled programs on one shared CPU budget. Preserve legacy programs' scheduling. Verify wait/resume, event and command ordering, saturation, concurrency, lifecycle, and backward compatibility.
2. **Equipment and hardware.** Separate CPU speed, dispatcher slots, device queue limits, bus capacity, and rank eligibility in the resolved fleet model. Integrate the nominal 25% responsive-device reserve with bus validation, then wire Black Widow to damage and Viper to bounded scanner/terrain processing. Verify that an uninstalled or unpowered device cannot emit events. Define sound, Echo reports, and readiness/death semantics before wiring those producers.
3. **Radio and team queries.** Define team identity, authorization, range, interception, and encryption before implementing message delivery. Debit responding CPUs through the scheduler before disclosing status or location. Verify range, privacy, costs, and deterministic delivery.
4. **Progression and inventory.** Add a separate versioned player profile for rank, XP, credits, purchases, and completed boss IDs. Keep kill attribution, reward grants, promotion criteria, and chassis derivation as separate services. Verify idempotent rewards and that both XP and required boss wins are necessary for promotion.
5. **Innovation Lab.** Reuse shell/world entry and the equipment catalog. Show owned/available equipment, next-rank previews, and CLASSIFIED placeholders. Validate that lab demonstration tanks are unclaimable and that preview equipment cannot enter a player loadout.
6. **Campaign and bosses.** Use authored worlds, normal simulation, and the same programmable equipment. Validate the maze's single loop as a graph property. Give each boss a deterministic scenario, a win condition, and regression tests for its recognizable behavior. Tune rewards only after these scenarios work.

## Decisions before later phases

- Whether the 25% reserve is a fixed reservation or a minimum operating allocation, and how event detection rate or range scales above it.
- Which chassis classes and ranks unlock CPU speed, independent buses, dispatcher slots (including 16), and each responsive device.
- Detection trigger semantics, including entry versus repeated detections, cooldowns, and whether damage data may identify an unseen attacker. Sound types, angle precision, and distance categories still need rules.
- Team membership, radio range, who may listen, and encryption/key authorization. Responder CPU costs and failure semantics need explicit values.
- Rank and reward tables, boss prerequisites, purchase prices, Robux credit packs, and whether a promotion preserves the previous loadout automatically.

## Phase 1 runtime contract

Register a named handler at compile time with `on_event("OnDamageTaken", handler)`. The handler accepts one `const` payload argument. This slice exposes a trusted host ingress and uses test producers. Equipment ownership and live damage emission are Phase 2 work.

Accepted events are FIFO per tank and dispatched at CPU-cycle boundaries to the lowest numbered idle slot. A slot remains busy during clock, device, and CPU waits. An event-enabled VM remains running while idle. At capacity it rejects the newest event. Existing device queue and setpoint rules arbitrate conflicting commands in scheduler execution order. Host producers must supply a stable emission order within a simulation step for deterministic replay.

All slots in an event-enabled program draw from one pool that receives the computer's tick grant once per CPU cycle. The first execution slot rotates each cycle. Expensive instructions can reserve that shared credit across cycles. Handler admission follows FIFO order. The handlers can start consuming CPU in a different order because the first execution slot rotates, and waits can cause handlers to finish out of order. Legacy sources without an event registration use their original per-thread grants.

The trusted ingress is `BWController.emitEvent(tank, name, fields)`. It accepts a bounded dictionary of copied, immutable scalar fields on a live tank's current invocation, outside configuration zones. The queue holds 32 pending events. Stopping or replacing an invocation discards its pending events. Handler-issued commands use the existing device APIs and keep their original ownership across thread slot reuse.

### Scheduler corner cases

| Case | Expected behavior |
| --- | --- |
| Conflicting movement | The existing device rules govern commands in scheduler execution order. A continuous move or stop replaces earlier drivetrain work. Timed moves normally enter the device FIFO. FIFO event admission does not fix subsequent handler execution order, since CPU priority rotates between slots. |
| Endless handler | It occupies one slot and shares the computer's credit. Runnable slots rotate priority. If a costly instruction reserves credit across cycles, priority advances past its slot after the reservation is served. A Bunny with one slot has no spare slot while its handler runs. The existing 180 simulated-second program limit still applies. |
| FIFO overflow | The 32 pending entries stay in order. New arrivals are rejected with `eventQueueFull` and the dropped counter increments. There is no coalescing or eviction. Active handlers are outside the queue count. |
| Follow-on events | BW source has no event-emission command. When a trusted producer queues a follow-on event during handler execution, the earliest dispatch is a later CPU cycle, subject to queue space and available slots. |
| Tank death | Stop clears queued events, active and queued device work, clock and device waits, call frames, and retained handler payloads. It returns neutral input and invokes the weapon cancellation hook when applicable. |
| Fleet load | The automated stress fixture creates 30 VMs and checks progress on all 480 busy slots and one CPU grant per tank per cycle. It reports idle and saturated timings separately. |

Run the corner cases with `node scripts/check.mjs /path/to/luau-web/src/index.js 68` and the 30-tank benchmark with group `69`. The benchmark uses 60 warm-up and 240 measured fixed steps. Its times include the BW VM and idle device stepping. Roblox physics, scanner queries, projectiles, and networking are outside the fixture. Treat these as offline timings and verify live frame headroom in the Studio MicroProfiler before using a 30-tank saturated configuration.

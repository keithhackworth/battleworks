# Playground retention and repeated-work audit

A report of steadily worsening performance prompted inspection of BW command/scanner histories, editor rendering, tanks, projectiles and effects. No claim is made that Roblox's collector is defective or that all native slowdown has been identified.

## Confirmed issues and fixes

Completed scanner commands retained full `result` and `observation` payloads in the512-command status history. This kept older terrain/detection graphs alive beyond the intended128-scan history. The objects were referenced, so garbage collection could not reclaim them. After a waiting BW thread consumes its scan, the command now retains only status metadata. Variables and the intended128-scan history still hold their valid observations. Physical command executors are released at completion. Stop releases the runtime's scan history/last-value references and remaining command payloads.

This was bounded retention, not a proven unbounded leak: with many tanks and terrain-rich observations it could still build a substantial live object graph as the histories filled. Neither the512-command nor128-scan limits were increased or deleted. `command_status` remains available because it exposes metadata, not the archived snapshot body.

Unoccupied public tanks also formatted scanner/print text that had no recipient. Lazy debug formatting now skips that work when output is not observable, preserving expression evaluation, CPU charges, counters, observations and gameplay. Occupied tanks still deliver the normal private output. Server scan presentation avoids formatting a full value before overwriting it with compact detection text.

The editor regenerated diagnostics and concatenated/paged growing log text every render frame even when unchanged. It now caches unchanged diagnostics/status/log content. Meaningful state/log updates, cursor changes, new source and tank/lease changes still refresh. Copy-selection pauses remain safe and refresh after the selection ends. No gameplay scheduler change, artificial garbage-collection call or reduced BW budget was introduced.

Other inspected paths already use bounded histories/weak registries or lifecycle cleanup: component/value type registries use weak keys; tank renderers destroy old generations; projectiles have finite range/lifetime and removal; most cosmetic effects use Debris. Inspection alone is not a soak-test guarantee.

## Automated evidence

`BWRetention.spec.luau` performs220 scans with24 terrain samples each through actual VM/device queues, both observed and unobserved. It checks consumed commands have no retained payload/executor, metadata status still works,128 scan history remains, script variables keep full values, Stop releases references, and output suppression preserves CPU fees/log-attempt counts (889 assertions). Editor tests verify100 unchanged snapshots do not repeatedly format logs and still refresh real changes. Existing execution, scanner and privacy tests remain required.

The test runner uses a fixed roughly17MB Luau Web heap, distinct from Roblox Studio. Memory-heavy fixtures load their actual production dependency graph instead of unrelated UI/server loaders; assertions and production limits are unchanged. A WASM fixture OOM is not evidence of a native Roblox leak.

## Native acceptance still needed

After Rojo sync, set **ServerStorage → BattleWorksStudio → PlaygroundBWEnabled → Value** to **false** in Edit mode and start a fresh Play session. Studio Output reports `Playground BW execution enabled: false`. The public tanks spawn idle and remain manually drivable. Arena, physics, manual driver radar and rendering still run. Repeat the same test with the value set to **true** and compare when frame time starts to climb. Keep the world, tank count and player actions consistent, and note that disabling BW also removes the movement and combat triggered by personality programs. The setting is read at server startup and applies to Battle Royale.

Run the same15-tank Playground for10–15 minutes. Record server/client Lua heap, instance count and script/frame time at startup, after histories fill, during heavy firing, and with the editor closed versus open. Exercise destruction/replenishment and enter/exit/switch cycles. Expected retained histories plateau; sawtooth heap growth with periodic collection is normal. Check whether instances, Lua heap or CPU time keep increasing after warm-up. Repeat with idle personalities disabled as a baseline if useful. Native scanner/physics/rendering load may remain even when retention is bounded; use Studio's profiler to distinguish it rather than forcing GC or changing CPU budgets without measurements.

## Capturing the slowdown around one minute

In Studio Edit mode, keep `ServerStorage → BattleWorksStudio → PlaygroundBWEnabled` on and set `PublicTankCount` to **15**. Start Play and use **BW Execution: ON/OFF** below **Main Menu** in the Playground. The button is available only in Studio Battle Royale. It starts ON each session and requests a global change from the server.

Use the button in the same session for **15 ON** and **15 OFF**, with the same camera and no occupied tanks. OFF parks autonomous inputs and cannon preparations, freezes BW clocks, and retains the tanks, their hardware, and active BW invocations. Physics can still move tanks and existing projectiles can still hit them. Players driving manually keep their controls. Switch back ON to resume. For **5 ON**, set `PublicTankCount` to **5** in Edit mode and start a separate Play session.

Studio server Output prints `[BattleWorks perf]` summaries with rolling average and maximum milliseconds **per fixed tick**. The window uses completed wall-clock seconds and defaults to five. Change `PlaygroundProfileWindowSeconds` in Edit mode to use 1–30 seconds. Wait a full window after a toggle so the report reflects the new mode. BW time excludes scanner processing, which is listed separately. The tick measurement covers the full fixed simulation step. Snapshot time has its own MicroProfiler scope because it runs outside the fixed step.

Capture a short server and client MicroProfiler window while the 15-tank run is still smooth, then capture again as the slowdown appears. Switch BW OFF in that session and capture again after the timing window refreshes. Save early and late server/client Lua heap readings from the Developer Console alongside the captures. [Roblox MicroProfiler](https://create.roblox.com/docs/performance-optimization/microprofiler)

| MicroProfiler scope | What it measures |
| --- | --- |
| `BattleWorks.ServerHeartbeat`, `BattleWorks.FixedStep` | Total BattleWorks heartbeat work and each 60 Hz simulation step. Multiple steps in one heartbeat indicate catch-up work. |
| `BattleWorks.BWRuntime`, `BattleWorks.Scan`, `BattleWorks.ScannerScene` | Interpreter and device work, scanner acquisition, and the static geometry cache rebuild. Scan time is included in BW runtime time when a program triggers it. |
| `BattleWorks.BWParse` | Source parsing at program starts, including automatic restarts. |
| `BattleWorks.TankSimulation`, `BattleWorks.Projectiles`, `BattleWorks.Snapshot` | Movement and contacts, projectile simulation and weapon effects, and snapshot preparation and sends. |
| `BattleWorks.ClientFrame`, `BattleWorks.ClientTankRendering`, `BattleWorks.ClientShotEffects` | Client frame work, tank visual updates, and effects initiated by shot messages. |

The scanner caches static arena membership and rebuilds the lists when queryable geometry changes. Each admitted scan still refreshes tank records, builds its query filters, and performs spatial queries and terrain sampling. A tank can retain up to 128 scan observations, so 15 scanning tanks could hold up to 1,920 observations as their histories fill. If scan time is high from startup but heap and GC time grow near the slowdown, compare heap snapshots before and during the drop. If scan time itself rises, check the nested cache rebuild scope against the rest of the scan. Rising projectile, snapshot, or client rendering costs would point to work generated by the running programs.

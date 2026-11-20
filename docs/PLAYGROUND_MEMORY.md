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

Run the same15-tank Playground for10–15 minutes. Record server/client Lua heap, instance count and script/frame time at startup, after histories fill, during heavy firing, and with the editor closed versus open. Exercise destruction/replenishment and enter/exit/switch cycles. Expected retained histories plateau; sawtooth heap growth with periodic collection is normal. Check whether instances, Lua heap or CPU time keep increasing after warm-up. Repeat with idle personalities disabled as a baseline if useful. Native scanner/physics/rendering load may remain even when retention is bounded; use Studio's profiler to distinguish it rather than forcing GC or changing CPU budgets without measurements.

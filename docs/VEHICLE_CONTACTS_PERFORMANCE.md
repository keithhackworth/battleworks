# Vehicle contact solver performance

The solver keeps its sorted tank and obstacle order. Each tank builds a list of static candidates from its current XZ center, linear sweep, existing orientation-independent reach, angular expansion, collision skin, and a two-stud correction reserve. Each phase verifies that its required bounds still fit before reusing the list. A correction that exceeds those bounds rebuilds the list immediately and continues from the last processed obstacle ID in sorted order. Tank-to-tank pairs still use the exhaustive order. The correction loop keeps its original limit and continues whenever a pass finds a constraint with depth above the existing skin and a positive combined inverse mass.

Box SAT reuses the trigonometric axes as scalars through all four projections. The impulse solver reuses each body's inverse mass and yaw inertia. The continuous SAT interval, positional correction, and impulse formulas remain the same.

## Reproduce the offline benchmark

Run from the repository root with the same Luau Web runtime used for the tests.

```sh
BW_CONTACTS_BENCHMARK=1 node scripts/check.mjs /path/to/luau-web/src/index.js 65
```

The runner reads the original solver from Git revision `ae8194090e7c8dc244e347196e5b3ccb9ab2d0e6`. A checkout without that object can supply the original source file through `BW_CONTACTS_BASELINE`. Timings use the original implementation and disable counters. Each version gets five warm-up solves and 80 timed solves per scenario, with equivalent fresh inputs prepared outside the timed call. Counter runs track broad-phase comparisons plus dispatched pair visits, SAT and plane tests, generated contact points, and positional correction passes. The fixture counts the five temporary axis tables allocated per original box SAT. That count measures one allocation source. Luau Web uses mocked vectors and a fixed WASM heap, so neither timings nor allocation counts measure full Roblox engine or garbage-collection behavior.

### Recorded offline result

| Scenario | Mean ms, old → new | P95 ms, old → new | Max ms, old → new | Pair checks, old → new | Narrow tests, old → new | Contact points | Correction passes, old → new |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 15 separated tanks, 63 statics | 7.509 → 1.432 | 8.269 → 1.579 | 10.397 → 1.831 | 3,150 → 1,260 | 0 → 0 | 0 | 0 → 0 |
| 15 clustered tanks, 63 statics | 43.655 → 23.018 | 56.033 → 25.018 | 69.043 → 28.607 | 24,150 → 4,272 | 1,574 → 1,574 | 46 | 20 → 20 |
| Rapid motion near obstacles | 118.216 → 23.020 | 152.816 → 28.033 | 170.604 → 33.294 | 110,250 → 13,824 | 1,725 → 1,650 | 16 | 80 → 75 |
| Rotating near walls and corners | 49.076 → 11.596 | 55.428 → 12.973 | 72.425 → 16.959 | 50,025 → 4,215 | 1,762 → 1,762 | 21 | 100 → 100 |
| Simultaneous contacts | 10.109 → 9.366 | 11.364 → 10.042 | 15.824 → 10.425 | 630 → 613 | 648 → 613 | 27 | 30 → 30 |
| High-speed CCD chain | 3.439 → 2.849 | 4.979 → 3.028 | 5.077 → 3.397 | 185 → 97 | 113 → 59 | 10 | 30 → 12 |
| Correction crosses cached bounds | 1.318 → 1.350 | 1.470 → 1.571 | 1.849 → 2.157 | 46 → 49 | 45 → 45 | 6 | 20 → 20 |
| Oblique polygon and grazing | 0.981 → 1.051 | 1.119 → 1.163 | 1.336 → 1.223 | 171 → 170 | 65 → 65 | 1 | 10 → 10 |

The clustered fixture removed 7,870 temporary axis tables per solve. The two smallest stress fixtures had slightly higher mean cost. Contact-point counts matched in every benchmark, and parity checks compared successive steps plus 28 seeded scenes at a tolerance of `1e-7`.

## Validate in Roblox Studio

1. Sync the repo and use a fresh Battle Royale Play session with `PublicTankCount=15` and BW execution ON. Keep the same map and player activity as in the original profile.
2. In server Output, record the `contacts` average and maximum under `[BattleWorks perf]`. It measures the solver only and is included in the broader `physics` measurement.
3. Record `[BattleWorks accumulator]` from the same window. It reports Heartbeat callbacks per second, average and maximum fixed steps per callback, peak buffered time before draining, peak time carried after draining, and elapsed time clipped by the existing 100 ms input cap.
4. Capture a server MicroProfiler window around the slowdown and inspect `BattleWorks.VehicleContacts` inside `BattleWorks.FixedStep`. Use comparable early and late windows and repeat the run to account for spawn and combat variation.

The reported baseline of 21.9 Heartbeats per second implies roughly 45.7 ms between callbacks. With a 16.67 ms fixed step and no clipping, that is about 2.74 steps per callback. At 11 ms per solve, the solver alone would account for roughly 30 ms of work per callback. This explains how catch-up can amplify a slow callback. The new counters can show whether that pattern persists after the optimization. The accumulator policy is unchanged. Reassess the need for an accumulator change after measuring the optimized Studio build.

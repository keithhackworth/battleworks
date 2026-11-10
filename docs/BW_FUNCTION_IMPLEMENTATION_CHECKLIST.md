# BW functions implementation checklist

## Architecture inspected
- [x] Parser emits flat per-thread instructions from block AST; expressions remain ASTs.
- [x] BWExecution cooperatively resumes expression coroutines; device waits suspend only the current virtual thread.
- [x] CPU accounting reserves worst-case statement cost; runtime charges actual operations.
- [x] Initial inspection: dictionaries were mutable references, arrays were frozen, scanner dictionaries were frozen snapshots.

## Design and acceptance
Extend the existing parser/compiler and instruction executor, not a second interpreter. Register function symbols before parsing bodies. Compile bodies with existing control-flow instructions. Each thread owns bounded frames and function-local bindings; top-level variables remain shared. Top-level execution does not count as a function frame. Calls/returns have no tick cost; mutable bindings retain configured read/write costs. Functions use the existing scheduler for device waits and CPU suspension.

Compile-time deep const analysis must conservatively reject unsafe/unknown object reference flows, including concurrent shared aliases. Unknown parameter types cannot simply be treated as scalar. Document conservative restrictions and prove accepted alias cases with actual runtime tests. No new clone API is planned.

- [x] Parse/register functions, parameters, returns, forward references and diagnostics. Files: BWParser, BWExpression, BWCommands.
- [x] Modular compile-time const/alias analysis; safe value/reference semantics. Files: BWFunctionAnalysis, BWValue.
- [x] Per-thread frames, local bindings, recursive calls, limits/cleanup and diagnostics. Files: BWExecution, BWConfig.
- [x] Exact cost accounting/reservations, bounded free-call execution and scheduler integration. Files: BWExecution, BWExpression.
- [x] Actual VM tests covering function behavior, aliases, const, stacks and costs. Files: tests/BWFunctions.spec.luau.
- [x] IDE handbook, language/runtime docs and limitations.
- [x] Full regression suites, both builds, whitespace validation.
- [ ] Studio runtime validation (Studio unavailable here; next action: run the function examples on both tanks, verify native line highlighting, scanner waits, Stop/switch/reset, and overflow diagnostics in Play).


## Verified phases
- Compiler/VM function suite: 381 assertions across 105 compiler/VM program checks; includes exact production CPU rates (read0.1/write0.2), depths50/51, independent aggregate guard, isolated thread overflow, real simulation/device/scanner integration and deterministic traces.
- Complete final regression run: all 18 groups pass; syntax compilation of 69 Luau source files passes. Final diagnostic formatting changes additionally rechecked with editor, function and live server integration groups.
- Alias policy: bounded flow-insensitive allocation-site analysis, rejecting unknown const/mutable alias flows and potentially shared const references in multithread programs. No clone/method API exists to reuse. Intentional conservative rejections documented in BW_LANGUAGE and BW_RUNTIME.
- Arrays created by BW expressions are now mutable references; scanner/result arrays remain frozen. Dictionaries retain existing reference semantics.

- Production server integration: 1518 assertions including function source submitted through BWRun, independent scanner-return/print ownership, private log replication, live function highlighting/depth diagnostics and Stop while suspended.
- Handbook UI/reference tests: 395 assertions. Runtime documentation now runs 14 example programs on both physical tank simulations.

## Final build and scope
- [x] `rojo build -o battleworks.rbxl`.
- [x] `rojo build -o battleworks.rbxlx`.
- [x] `git diff --check`.
- [x] No tank tuning, combat balance, bus allocation, scanner acquisition/refresh or vehicle physics changes in this task.
- [x] No commit or push.

Important files: `src/shared/BWParser.luau`, `BWCommands.luau`, `BWExpression.luau`, new `BWFunctionAnalysis.luau`, `BWExecution.luau`, `BWValue.luau`, `BWConfig.luau`, `BWDevices.luau`, legacy `BWRuntime.luau` delegation; `src/server/BWController.luau` and `src/client/BWIDE.luau` for highlighting/diagnostics; `BWHandbook.luau`; `tests/BWFunctions.spec.luau`, `SwappedWeapons.spec.luau`, mock/runner registration; language/runtime docs and generated build.

Only native Studio acceptance remains unchecked. Deliberately unsupported patterns: nested definitions, function values/closures, local compile-time constant declarations, new clone/mutating collection method APIs, and reference flows the conservative alias analysis cannot prove safe. Source-size/nesting/runtime limits remain enforced.

Final focused function checks also exercise truly zero-cost loops under the hard dispatch bound and function-name case sensitivity. All 381 assertions / 105 program checks pass. No remaining implementation item is knowingly pending beyond native Studio validation and the documented conservative-language restrictions.

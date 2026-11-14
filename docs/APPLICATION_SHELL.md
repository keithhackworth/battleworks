# BattleWorks application shell

Players arrive at the Main Menu. Play BattleWorks opens the lobby; Enter Battle
requests admission to the existing simulator. Main Menu in the battle HUD (or
Xbox B when no text field is focused) leaves the battle and returns home.

The main menu has exactly this order:

1. Play BattleWorks
2. Garage
3. Store
4. Separator
5. World Editor
6. Preferences
7. Manuals

Battle History is available from the lobby. Garage, Store, Battle History,
Preferences and Manuals currently have separate placeholder
modules with a return action. World Editor now hosts the [in-game builder](IN_GAME_WORLD_BUILDER.md) in its own private viewport scene. The existing Studio World Builder and the
in-battle BW editor/handbook are still available through their original paths.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `src/client/init.client.luau` | Compose the existing gameplay client, session and shell. |
| `src/client/BattleClientHost.luau` | Lazy, single-instance battle client activation; menu startup creates no battle UI or input. |
| `src/client/BattleClient.luau` | Existing simulator client wiring, HUD, renderer registry, input, BW UI and battle camera. Exposes `setActive(boolean)`. |
| `src/client/shell/ApplicationShell.luau` | Screen registration, composition, presentation visibility, keyboard and Xbox navigation. |
| `ScreenManager.luau` | Central lazy screen creation, transitions, instance reuse and destruction. |
| `ShellView.luau` | Responsive card, scrolling content, shared typography, buttons and selection lifecycle. |
| `GameplaySession.luau` | Client admission state and monotonic enter/leave request IDs. |
| `MenuBackground.luau` | Static, local viewport presentation of existing arena scenery. |
| `ShellMainMenu`, `ShellLobby`, `ShellBattle` | Main menu, working battle admission and gameplay lifecycle adapter. |
| `ShellGarage`, `ShellStore`, `ShellBattleHistory`, `ShellWorldEditor`, `ShellPreferences`, `ShellManuals` | Independent extension points for future features. |

All paths in the table after `BattleClient` are under `src/client/shell/`.

## Screen contract and extension

Each screen module exports `new(context)`. Its instance implements:

- `enter(params)`: reveal or activate the screen and establish initial focus.
- `exit()`: hide it, release focus and suspend screen-owned activity.
- `destroy()`: disconnect its listeners and destroy its owned UI/resources.

`ScreenManager` calls `exit` before the next screen's `enter`. Instances are
created lazily and reused. Screens do not own their own top-level navigation
stack or create additional copies on each visit.

Menu focus is local: arrows/D-pad choose an index and scroll/highlight its button;
Enter/controller A activates it. Shell buttons are excluded from native GUI
selection. The Windows Studio log stopped inside a `GuiService.SelectedObject`
assignment, so no menu entry or navigation path writes that property. See
[startup investigation](STUDIO_STARTUP_TROUBLESHOOTING.md).

`context.parent` is the UI container. `context.navigate(name, params)` routes
through the manager. `context.home()` returns to Main Menu and cancels pending
admission or leaves an active battle. `context.join()` requests battle entry;
it does not activate gameplay locally. `context.session` and `context.gameplay`
are used by the dedicated battle adapter.

A typical future screen can continue using the common view:

```lua
local View = require(script.Parent.ShellView)
local Garage = {}
function Garage.new(context)
    local screen = View.new(context, "Garage", "Your vehicle workshop.")
    -- Add garage-owned content here. Keep selection/data separate from UI.
    screen:back()
    return screen
end
return Garage
```

Replace the appropriate placeholder module while keeping its registration key.
If adding asynchronous data loading, cancel or ignore stale results after
`exit` and disconnect them in `destroy`. Screen work must not run battle
controls or mutate shared arena objects.

- **Garage:** add loadout presentation and validated persistence as a future
  feature; keep ownership as a collection of tanks per player.
- **Store:** add a separate future purchase/data service. No purchase flow exists
  in this shell.
- **Battle History:** add real history retrieval later. The current screen reads,
  records and saves no battle data.
- **World Editor:** extend the current in-experience authoring adapter (see the
  in-game builder guide). Preserve the existing compiler/world-selection pipeline.
- **Preferences:** introduce explicit settings state and persistence later.
  Existing in-battle Input mode selection remains unchanged.
- **Manuals:** supply content modules or reuse the existing BW handbook later;
  avoid duplicating interpreter rules in navigation code.

## Static background and future replacement

There is no working replay recording/playback implementation in this repository.
This milestone implements neither. `MenuBackground` takes a one-time static
copy of available Floor, Boundary, Environment, WorldScenery and CenterStick
geometry into a client-local ViewportFrame with static folders. It never copies tank
hitboxes, target actors, projectiles, scripts, sounds or emitters. Clones are
anchored, non-collidable and non-queryable; gameplay attributes are stripped.
The capture is bounded to 600 parts, cached across screens, and refreshed only
on a map revision. There is no background simulation or per-frame camera loop.

The viewport has its own fixed oblique camera, warm directional light and a dark
readability overlay. It does not change `Workspace.CurrentCamera`. Authored
terrain and available mesh parts come from the existing loaded arena, rather
than invented battle data.

`ApplicationShell.new(..., presenter)` accepts a presenter with `enter()`,
`exit()` and `destroy()`. A future replay presenter can implement that interface
and own its playback scheduling internally. Navigation will not need to know
about replay selection, storage or playback. Such services, most-recent replay
selection, demonstration replay fallback and looping are all deferred.

## Battle admission and isolation

The additive `TankNetwork.BattleSession` remote accepts only `Enter` or `Leave`
and a positive monotonic integer request ID. Replies are private acknowledgments:
`(requestId, inBattle, optionalMessage)`. Enter is rate limited to once per second
when creating a new participation. Leave is not rate limited, so cancellation is
always available. Older requests and acknowledgments cannot overtake newer ones.

`Players.PlayerAdded` now registers presence only. Admission calls the same
existing tank-spawn path. Ownership remains a per-player collection; no
exactly-one-tank assumption was introduced. Menu startup constructs no battle client UI/camera and does not wait for the optional editor library. Menu players have no tanks,
programs, projectiles or collision bodies and cannot affect multiplayer mode
selection. Returning to the menu uses the same collection cleanup as disconnect:
stop programs, destroy owned hitboxes/tanks/shells and remove battle membership.
Re-entry advances tank lifecycle generations so existing clients replace old
renderers, even across rapid leave/re-entry between snapshots.

The simulator's physics, BW interpreter, world loading, input contract, snapshot
format and gameplay remote paths are retained. Their existing owner checks
reject menu players because no owned battle collection exists.

The client suspends all input providers, hides every battle GUI (including BW
and Studio camera tools), clears renderer models, closes text focus and restores
camera pose, subject, type, field of view and field-of-view mode on exit. While
inactive it never sends gameplay intent, updates the battle camera or renders
battle shot effects. Snapshots may still arrive, but cannot activate gameplay.
Only an acknowledgment matching the current admission request can do so.
Held keyboard keys, touch captures and gamepad triggers are reset on transitions.
BW source buffers remain in the existing session-local editor; active server
programs are stopped when leaving.

## Verification and native acceptance

Run `node scripts/check.mjs /path/to/luau-web/src/index.js` for all existing
suites and the new shell groups:

- `ApplicationShell.spec.luau`: exact menu order/separator, screen lifecycle,
  lazy reuse, keyboard/Xbox routing, canceled/denied admission, presentation
  isolation and safe static scene capture.
- `ShellServerIntegration.spec.luau`: real production-server presence/admission,
  invalid/stale requests, rate limits, menu action rejection, multiplayer
  isolation, cleanup and lifecycle generations on re-entry.
- `ShellClientIntegration.spec.luau`: production client with real input/BW UI,
  hidden gameplay layers, camera restoration, ignored late effects/snapshots,
  keyboard/touch/gamepad paths and held-input cleanup.

Build without replacing a developer's existing place:

```sh
rojo build default.project.json -o /tmp/battleworks-shell.rbxl
rojo build default.project.json -o /tmp/battleworks-shell.rbxlx
rojo build world-builder.project.json -o /tmp/battleworks-shell-world-builder.rbxm
```

Verified in this workspace: 75 Node tests, all 27 Luau test groups, syntax
compilation of 92 source files, both place formats, the world-builder plugin
build and `git diff --check`. New shell suites passed 45 navigation/background,
120 server-isolation and 16 production-client assertions.

Native Roblox Studio still needs these checks:

1. Start two clients. Both must start at Main Menu, with readable static scenery
   and no tanks. Verify exact menu order and all placeholder return paths.
2. Enter only one client. Verify the other stays in the menu and cannot influence
   movement, targeting or the solo lifecycle. Enter the second client and verify
   the existing shared combat, BW execution, damage and respawn.
3. Return while driving, firing, entering BW text, or running a program. Verify
   tanks/shells disappear for the other client, every battle UI closes, the static
   view returns, and re-entry has fresh controls and renderer generations.
4. Cancel entry immediately; repeat enter/back with network latency emulation.
   Delayed acknowledgments must not reopen gameplay. A rate-limited retry should
   show the lobby message and permit retry or Back.
5. Check mouse/keyboard, touch emulation, device safe areas, short landscape
   windows, scroll reachability and Xbox D-pad/A/B navigation. Verify the return
   button is clear of touch sticks and B does not hijack focused text entry.
6. Repeat using an authored World Builder world. Inspect static mesh/texture
   rendering, camera composition and map-revision refresh; check Studio camera
   tools and BW editor panels never remain visible in menus.

Mock tests and Rojo builds do not verify native rendering, asset permissions,
selection/scroll behavior, CoreGui interactions or actual network delivery.

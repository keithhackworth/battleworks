# Studio closes immediately on Play

A complete Studio process exit needs a native Studio log to confirm the cause.
The local mock tests cannot reproduce or diagnose an engine/renderer crash. No
crash log from the affected machine was available when these changes were made.

Startup was reduced to the menu itself:

- `BattleClientHost` constructs the existing battle UI/input/camera only on the
  first admitted battle entry, then reuses it to preserve BW editor buffers.
  Canceling while a dependency loads leaves the completed client inactive.
- Static menu scenery and asset thumbnails use folders inside ViewportFrames,
  rather than allocating additional physics-enabled WorldModels. The interactive
  editor still creates its queryable WorldModel only when the editor opens.
- Main Menu no longer waits for the optional editor library. The editor resolves
  that library when opened and can retry on a later visit if unavailable.
- A Lua failure publishing the optional catalog warns instead of aborting the
  arena/server startup. This cannot catch a native process crash.

The supplied Windows Studio log reaches `arena and battle services ready` and
`initializing main menu`, then ends. It contains no BattleWorks script error in
that interval. This narrows the investigation to client menu initialization but
does not identify the precise native failure.

Startup isolation v2 now defaults to a plain background **in Studio**, creates no
menu ViewportFrame/camera/geometry unless explicitly opted in, defers initial GUI
selection, and logs the individual GUI/background/widgets/focus stages. Published
clients retain the normal static preview. For a later explicit preview test, set
`BattleWorksMenu3D=true` before Play; removing the attribute restores Studio's
plain-background default.

These are startup-risk reductions, not a confirmed identification of the crash.

## Retest and isolate

1. Open the new `battleworks-startup-isolation-v2.rbxl` test build or reconnect/sync Rojo and restart Play. Source changes do not update an old,
   unsynced place automatically. A source-only recovery build can be produced with
   `rojo build default.project.json -o /tmp/battleworks-startup-recovery.rbxl`.
2. If Studio still exits, disable menu 3D rendering before Play using Studio's
   Command Bar:

   ```lua
   workspace:SetAttribute("BattleWorksMenu3D", false)
   ```

   The menu will use a plain background and allocate no menu ViewportFrame,
   physics world or 3D camera. Navigation and gameplay remain available.
   Explicitly enable the static preview for an isolated test with:

   ```lua
   workspace:SetAttribute("BattleWorksMenu3D", true)
   ```

3. Collect the newest Studio log from the affected computer:
   - Windows: `%LOCALAPPDATA%\Roblox\logs`
   - macOS: `~/Library/Logs/Roblox`

   See [Roblox's debugging documentation](https://create.roblox.com/docs/studio/debugging).
   The final 40–80 lines, the Studio version, operating system and whether the
   main menu appeared help identify the failing startup phase.

## Startup markers

Studio-only log lines now include:

```text
[BattleWorks startup/server] server started
[BattleWorks startup/server] publishing editor asset library
[BattleWorks startup/server] editor asset library ready
[BattleWorks startup/server] arena and battle services ready
[BattleWorks startup/client] client started
[BattleWorks startup/client] initializing main menu
[BattleWorks startup/client] main menu ready
```

Server and client logs can interleave. `initializing battle client` and
`battle client ready` should appear only after Enter Battle, never on initial
Main Menu entry. The last recorded marker narrows the next investigation; it
does not by itself prove the cause of a native crash.

## Legacy plugin seen in the later Windows log

The later excerpt contains `user_BattleWorksWorldBuilder.rbxm` loading in
`dm=Edit`, followed by stack references to `Preview`, line 3, but no BattleWorks
Play startup markers. The legacy plugin required Shared modules before checking
whether the open place supplied them. Its source now checks dependencies first;
a blank-place bootstrap check passes and the plugin package builds. This repairs
a plugin startup defect, not a proven native crash cause.

The installed local plugin is separate from the downloaded game place and is
not replaced by downloading a newer `.rbxl`. For a controlled standalone-place
test, disable the old World Builder and Rojo plugins and restart Studio. The
in-game editor needs neither plugin. To identify the matching failed session in
Git Bash's log directory, list files by last modification time:

```sh
ls -lt *.log | head -10
```

Do not assume an Edit-session log with ongoing Rojo retries is the failed Play
instance's log. Match its timestamp and the startup-isolation-v2 marker.

## v3: native menu selection is the last recorded operation

The plugin-free v2 log reaches `main menu ready`, then ends immediately after
`assigning menu focus`; the `menu focus assigned` line after
`GuiService.SelectedObject = firstButton` never appears. This is substantially
narrower evidence than the earlier startup logs. The native exception itself is
still not available, so Studio must confirm the fix.

The v3 build removes this operation and the menu's native selection graph entirely:

- Menu entry schedules no native focus assignment.
- Menu buttons are excluded from native GUI selection.
- Arrows/D-pad update a local focus index and outline, with explicit scrolling.
- Enter/controller A invokes the corresponding action; mouse/touch clicks remain.
- The regression test rejects non-nil native `SelectedObject` assignments while
  exercising menu startup, screen changes and keyboard/controller navigation.

Use `/tmp/battleworks-focus-recovery-v3.rbxl` for the next native test. Its initial
client marker contains `focus recovery v3`, and the menu logs
`custom menu navigation ready; native auto-focus disabled`. Studio's plain
background default remains for this controlled test. The previous plugin removal
and 3D background changes were not by themselves sufficient to stop the crash.

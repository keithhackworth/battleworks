# Complete BW manual export

BW Handbook → **Download .txt** displays the entire reference in one selectable, read-only document. It includes all handbook topics plus the exact own-state API and terrain-scanner schemas. **Select address** selects the browser download address. Players can copy the text directly for an AI, or open the address in their browser and click **Download full manual (.txt)**.

Public page: https://groupboard.app/battleworks/manual.html

Plain text: https://groupboard.app/battleworks/BattleWorks-BW-Manual.txt

Roblox experiences cannot save arbitrary local files or launch an arbitrary external browser URL through a normal LocalScript. The UI does not claim to have saved a file or use executor clipboard/browser APIs. It uses the supported native selectable TextBox. Closing the handbook releases both text and address focus; downloading never runs/stops/configures a tank.

## Regeneration

```
node tools/build-bw-manual.mjs
node tools/build-bw-manual.mjs --check
```

The default development Luau Web path is `/tmp/battleworks-luau-check/node_modules/luau-web/src/index.js`; pass another runtime path as the first argument if needed. The tool executes the actual `BWHandbook.exportText()` with the repository's existing Roblox stand-ins and shared modules. It writes:

- `src/shared/BWManualAppendix.luau`: generated exact API/schema text for the in-game export.
- `docs/BW_MANUAL.txt`: full UTF-8 manual, generated from live handbook content plus that appendix.

Do not hand-edit either generated file. Update the handbook or referenced API/schema docs, then regenerate. Node tests verify parity. The current export is103,882 bytes; it does not include a player's private source, saved worlds, API keys or runtime logs.

## Hosting

`python3 tools/deploy-bw-manual.py` copies the generated manual and download page into Groupboard's existing `groupboard-app/static/battleworks` Nginx fallback. No frontend build or service restart is needed for that static publication. The HTML download uses the standard same-origin `download` attribute.

The same deployment also prepares a read-only attachment endpoint `/api/battleworks/v1/manual.txt` and its static artifact in the public API repository. That route is tested but the existing Flask process requires an administrator restart to load newly registered routes; normal and passwordless-sudo restarts were unavailable in this session. The game therefore uses the verified static download page, not the inactive API URL. Only the manual endpoint bypasses world-server authentication; all world operations and namespaces remain unchanged. Backend manual/world tests pass21 tests.

Public page/file returned HTTP200 and the fetched file's SHA-256 matched the generated artifact exactly. Native Roblox copy/select, touch keyboard and browser workflow still require Studio/device acceptance.

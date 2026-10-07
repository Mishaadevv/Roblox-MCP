# Roblox-MCP

**An MCP server that gives AI agents full control over Roblox Studio**: launch/close Studio, open projects, execute arbitrary Luau, view and build scenes, write scripts, create GUI, configure lighting/camera, insert Toolbox assets, run Play Solo / Run playtests and read Output. Everything is undoable (Ctrl+Z).

## How it works

```
AI agent (Claude / Cursor / any MCP client)
   │  MCP (stdio)
   ▼
roblox-mcp (Node.js) ── child_process ──► RobloxStudioBeta.exe (launch / open / close)
   │  HTTP localhost (127.0.0.1:8090)
   ▼
MCPBridge.luau plugin inside Roblox Studio (HttpService long-poll)
   └── executes commands through the regular Roblox API: Instance, Script.Source,
       Selection, RunService, InsertService (Toolbox), Lighting, Camera...
```

Why this shape: Studio plugins **cannot accept** inbound connections, but they **can** reach localhost via `HttpService`. So the plugin long-polls the bridge ("any commands?"), executes them, and posts results back via `POST /result`.

## Features (50 tools)

| Group | Tools |
|---|---|
| Studio | `studio_status`, `studio_launch`, `studio_open_place`, `studio_close`, `studio_list_places` |
| Bridge | `bridge_status` |
| Full access | `execute_luau` — any Luau in Studio context (a Command Bar on steroids) |
| Scene | `get_scene`, `get_children`, `get_instance`, `find_instances`, `create_instance`, `bulk_create`, `set_property`, `set_properties`, `delete_instance`, `rename_instance`, `reparent_instance`, `duplicate_instance`, `get_selection`, `set_selection` |
| Scripts | `list_scripts`, `read_script`, `write_script`, `create_script`, `delete_script`, `grep_scripts` |
| Playtesting | `play_solo` (F5), `run_game` (F8), `stop_playtest`, `get_play_state`, `playtest` (one-call run+output+stop), `get_output`, `clear_output`, `get_performance`, `teleport_player`, `respawn_player`, `kill_player` |
| Toolbox | `toolbox_search` (catalog search by keyword), `toolbox_info` (asset details), `insert_asset` (by assetId) |
| GUI / world | `create_gui`, `save_place`, `get_camera`, `set_camera`, `get_lighting`, `set_lighting`, `get_workspace_info`, `undo`, `redo` |

Property values support Roblox types via encoding:
`{"__type":"Vector3","value":[10,5,0]}`, `Color3` (RGB 0–255), `UDim2`, `CFrame` (12 numbers), `BrickColor` (`{"__type":"BrickColor","value":"Bright red"}`), Enums (`"Enum.Material.SmoothPlastic"`).

## Quick start

### 1. Requirements

- Windows 10/11 (macOS partially supported: Studio CLI differs, bridge + plugin work the same)
- Node.js 18+
- Roblox Studio installed
- Any MCP client: Claude Desktop, Cursor, VS Code (Copilot / Cline), Windsurf…

### 2. Install the server

```powershell
git clone https://github.com/<you>/Roblox-MCP.git
cd Roblox-MCP
npm install
npm run build
```

Smoke-test without Studio (the bridge should answer `ok:true`):

```powershell
node scripts/test-bridge.mjs
node scripts/mcp-check.mjs   # full MCP roundtrip over stdio
```

### 3. Install the Studio plugin

1. Copy `plugin/MCPBridge.luau` into the plugins folder:
   - Windows: `%LOCALAPPDATA%\Roblox\Plugins\MCPBridge.luau` (create the folder if missing)
   - macOS: `~/Documents/Roblox/Plugins/MCPBridge.luau`
2. Restart Roblox Studio and open any place.
3. On its first HTTP request Studio asks for localhost permission — allow it (or via Plugin Management → MCPBridge).
4. Output should show `[MCP] Connected to bridge at http://127.0.0.1:8090`.
5. (Optional, if `ROBLOX_MCP_API_KEY` is set) run in View → Command Bar:
   ```lua
   _G.MCP_SetApiKey("your-key-here")
   ```

### 4. Connect your AI client

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "roblox": {
      "command": "node",
      "args": ["C:/Users/<you>/Documents/Roblox-MCP/dist/index.js"],
      "env": { "ROBLOX_BRIDGE_PORT": "8090" }
    }
  }
}
```

**Cursor / VS Code (mcp.json)** — see `examples/mcp.json`.

Restart the client. The agent will see ~50 tools: `studio_*`, `execute_luau`, `get_scene`, …

## Example prompts for the agent

- "Launch Studio and open `C:\Games\MyObby.rbxl`"
- "Show the Workspace structure, 2 levels deep"
- "Build an obby: 10 stair-step platforms + SpawnLocation + a score script"
- "Make a main menu: ScreenGui with Play and Shop buttons"
- "Insert Toolbox asset 12345678 into Workspace"
- "Run Play Solo for 5 seconds, show me the Output, then stop"
- "Find all scripts containing `Damage` and show the first match"
- "Set ClockTime 14, Brightness 3, push the fog further out"

Ready-made scenarios live in `examples/`:
- `examples/obby.md` — generating an obby from scratch
- `examples/gui-menu.md` — a main menu
- `examples/debug-loop.md` — the "run → read Output → fix" loop

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `ROBLOX_BRIDGE_PORT` | bridge start port (probes +0…+9 on conflict) | `8090` |
| `ROBLOX_MCP_API_KEY` | key for `x-api-key` (plugin: `_G.MCP_SetApiKey`) | _(empty — no auth, localhost only)_ |
| `ROBLOX_TIMEOUT_MS` | plugin wait timeout | `30000` |
| `ROBLOX_STUDIO_PATH` | path to `RobloxStudioBeta.exe` if auto-detect fails | _(auto)_ |

No Studio exe yet (fresh install via the bootstrapper)? `studio_launch` starts `RobloxStudioInstaller.exe` automatically, waits for the real exe to appear, then opens your place.

## Debugging without MCP (curl)

```powershell
# bridge health
curl http://127.0.0.1:8090/health
# status (is the plugin connected?)
curl http://127.0.0.1:8090/status
# run one command synchronously (waits up to 30s for the plugin)
curl -X POST http://127.0.0.1:8090/command -H "Content-Type: application/json" -d '{"method":"get_workspace_info","params":{}}'
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Plugin timeout … Is Roblox Studio open…` | Open Studio with any place, check `bridge_status`: `pluginConnected` must be `true`. Look for `[MCP]` lines in Output |
| Plugin can't find the bridge | Start the MCP server first (`npm start`), then Studio. Check `curl …/health`. Ports 8090–8099 must be free |
| Studio asks for HTTP permission | Allow localhost for the plugin (Plugin Management). Without it the plugin can't reach the bridge |
| `studio_launch` → not found | Install Studio or set `ROBLOX_STUDIO_PATH` |
| `insert_asset` fails | Asset is private/off-sale or no access. Public free models insert fine |
| `save_place` → saved:false | This Studio version has no scriptable Save API — press Ctrl+S. Everything else works |

## Security

- The bridge listens on **`127.0.0.1` only**, nothing is exposed to the network.
- An optional API key locks the bridge even from other local processes.
- `execute_luau` runs **arbitrary** code in Studio — only connect trusted MCP clients.
- All mutations go through `ChangeHistoryService` — Ctrl+Z undoes agent actions.

## Repository layout

```
Roblox-MCP/
├── src/
│   ├── index.ts     # MCP stdio server
│   ├── bridge.ts    # HTTP bridge (long-poll) for the plugin
│   ├── studio.ts    # find/launch/close Studio, scan .rbxl files
│   └── tools.ts     # 50 MCP tools
├── plugin/
│   └── MCPBridge.luau  # Studio plugin (drop into the Plugins folder)
├── backrooms/       # example game: BACKROOMS Level 0 horror (Rojo project + built .rbxlx)
├── examples/        # mcp.json + prompt scenarios
├── scripts/         # smoke tests (bridge + full MCP roundtrip)
└── dist/            # build output (npm run build)
```

## Roadmap

- [ ] Viewport screenshots via the plugin, returned to the agent as images
- [ ] Rojo sync (edit `.lua` files directly)
- [ ] Team Create / Open Cloud publishing (`publish_place`)
- [ ] `.fbx`/`.obj` model and audio imports
- [ ] WebSocket instead of long-poll for lower latency
- [ ] macOS/Linux CI, signed plugin installer

PRs and issues welcome.

## License

MIT — see [LICENSE](LICENSE).

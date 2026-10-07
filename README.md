# Roblox-MCP

**MCP-сервер, дающий ИИ-агентам полный контроль над Roblox Studio**: запуск/закрытие Studio, открытие проектов, выполнение любого Luau-кода, просмотр и постройка сцены, скрипты, GUI, свет, камера, Toolbox (вставка ассетов по ID), Play Solo / Run для проверки игры, чтение Output-лога. Всё с поддержкой Ctrl+Z.

> 🇷🇺 Этот README на русском. Краткая версия на английском — ниже в разделе [English](#english-short-version).

## Как это работает

```
ИИ-агент (Claude / Cursor / любой MCP-клиент)
   │  MCP (stdio)
   ▼
roblox-mcp (Node.js) ── child_process ──► RobloxStudioBeta.exe (запуск/открытие/закрытие)
   │  HTTP localhost (127.0.0.1:8090)
   ▼
Плагин MCPBridge.luau внутри Roblox Studio (HttpService long-poll)
   └── исполняет команды через обычный Roblox API: Instance, Script.Source,
       Selection, RunService, InsertService (Toolbox), Lighting, камера...
```

Почему так: плагины Studio **не принимают** входящие соединения, но **могут сами** ходить в localhost через `HttpService`. Поэтому плагин раз в ~25 сек (long-poll) спрашивает у бриджа «есть команды?», выполняет их и возвращает результат через `POST /result`.

## Возможности (40 инструментов)

| Группа | Инструменты |
|---|---|
| Studio | `studio_status`, `studio_launch`, `studio_open_place`, `studio_close`, `studio_list_places` |
| Мост | `bridge_status` |
| Полный доступ | `execute_luau` — любой Luau-код в контексте Studio (Command Bar на стероидах) |
| Сцена | `get_scene`, `get_instance`, `create_instance`, `set_property`, `set_properties`, `delete_instance`, `rename_instance`, `reparent_instance`, `duplicate_instance`, `get_selection`, `set_selection` |
| Скрипты | `list_scripts`, `read_script`, `write_script`, `create_script`, `delete_script`, `grep_scripts` |
| Проверка игры | `play_solo` (F5), `run_game` (F8), `stop_playtest`, `get_play_state`, `get_output`, `clear_output` |
| GUI/мир | `create_gui`, `insert_asset` (Toolbox по assetId), `save_place`, `get_camera`, `set_camera`, `get_lighting`, `set_lighting`, `get_workspace_info`, `undo`, `redo` |

Значения свойств поддерживают типы Roblox через encoding:
`{"__type":"Vector3","value":[10,5,0]}`, `Color3` (RGB 0–255), `UDim2`, `CFrame` (12 чисел), `BrickColor` (`{"__type":"BrickColor","value":"Bright red"}`), Enum (`"Enum.Material.SmoothPlastic"`).

## Быстрый старт

### 1. Требования

- Windows 10/11 (macOS частично: запуск Studio через CLI отличается, бридж и плагин работают так же)
- Node.js 18+
- Установленный Roblox Studio
- Любой MCP-клиент: Claude Desktop, Cursor, VS Code (Copilot / Cline), Windsurf…

### 2. Установка сервера

```powershell
git clone https://github.com/<you>/Roblox-MCP.git
cd Roblox-MCP
npm install
npm run build
```

Проверка без Studio (бридж должен ответить `ok:true`):

```powershell
$env:ROBLOX_BRIDGE_PORT=8090
node scripts/test-bridge.mjs
```

### 3. Установка плагина в Studio

1. Скопируй `plugin/MCPBridge.luau` в папку плагинов:
   - Windows: `%LOCALAPPDATA%\Roblox\Plugins\MCPBridge.luau` (создай папку, если нет)
   - macOS: `~/Documents/Roblox/Plugins/MCPBridge.luau`
2. Перезапусти Roblox Studio, открой любой place.
3. При первом HTTP-запросе Studio спросит разрешение для localhost — разреши (или в Plugin Management → MCPBridge).
4. В Output должно появиться `[MCP] Connected to bridge at http://127.0.0.1:8090`.
5. (Опционально, если задан `ROBLOX_MCP_API_KEY`) в View → Command Bar выполни:
   ```lua
   _G.MCP_SetApiKey("твой-ключ")
   ```

### 4. Подключение к ИИ-клиенту

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "roblox": {
      "command": "node",
      "args": ["C:/Users/<ты>/Documents/Roblox-MCP/dist/index.js"],
      "env": { "ROBLOX_BRIDGE_PORT": "8090" }
    }
  }
}
```

**Cursor / VS Code (mcp.json)** — см. `examples/mcp.json`.

Перезапусти клиент. Агент увидит ~40 инструментов `studio_*`, `execute_luau`, `get_scene`, …

## Примеры запросов агенту

- «Запусти Studio и открой `C:\Games\MyObby.rbxl`»
- «Покажи структуру Workspace на 2 уровня»
- «Создай обби: 10 платформ лесенкой + SpawnLocation + скрипт выдачи очков»
- «Сделай главное меню: ScreenGui с кнопками Играть и Магазин»
- «Вставь ассет 12345678 из Toolbox в Workspace»
- «Запусти Play Solo на 5 секунд, покажи Output и останови»
- «Найди все скрипты со словом `Damage` и покажи первое совпадение»
- «Поставь ClockTime 14, Brightness 3, туман подальше»

Готовые диалоги — в `examples/`:
- `examples/obby.md` — генерация обби из нуля
- `examples/gui-menu.md` — главное меню
- `examples/debug-loop.md` — цикл «запустил → прочитал Output → починил»

## Переменные окружения

| Переменная | Назначение | По умолчанию |
|---|---|---|
| `ROBLOX_BRIDGE_PORT` | стартовый порт бриджа (пробует +0…+9) | `8090` |
| `ROBLOX_MCP_API_KEY` | ключ для `x-api-key` (плагин: `_G.MCP_SetApiKey`) | _(пусто — без авторизации, только localhost)_ |
| `ROBLOX_TIMEOUT_MS` | таймаут ожидания плагина | `30000` |
| `ROBLOX_STUDIO_PATH` | путь к `RobloxStudioBeta.exe`, если авто-поиск не нашёл | _(авто)_ |

## Отладка без MCP (curl)

```powershell
# здоровье бриджа
curl http://127.0.0.1:8090/health
# статус (подключён ли плагин)
curl http://127.0.0.1:8090/status
# выполнить команду синхронно (ждёт плагин до 30с)
curl -X POST http://127.0.0.1:8090/command -H "Content-Type: application/json" -d '{"method":"get_workspace_info","params":{}}'
```

## Troubleshooting

| Симптом | Что делать |
|---|---|
| `Plugin timeout … Is Roblox Studio open…` | Открой Studio с любым place, проверь `bridge_status`: `pluginConnected` должен быть `true`. Смотри Output → `[MCP]` строки |
| Плагин не находит бридж | Сначала запусти MCP-сервер (`npm start`), потом Studio. Проверь `curl …/health`. Порты 8090–8099 должны быть свободны |
| Studio просит HTTP-разрешение | Разреши localhost для плагина (Plugin Management). Без этого плагин не дотянется до бриджа |
| `studio_launch` → not found | Установи Studio или задай `ROBLOX_STUDIO_PATH` |
| `insert_asset` fails | Ассет приватный/снят с продажи, либо нет доступа. Публичные free-модели вставляются нормально |
| `save_place` → saved:false | В этой версии Studio нет скриптового Save API — нажми Ctrl+S. Всё остальное работает |

## Безопасность

- Бридж слушает **только** `127.0.0.1`, наружу ничего не торчит.
- Опциональный API-ключ закрывает бридж даже от других локальных процессов.
- `execute_luau` выполняет **любой** код в Studio — подключай к агенту только проверенные MCP-клиенты.
- Все мутации обёрнуты в `ChangeHistoryService` — Ctrl+Z откатывает действия агента.

## Структура репозитория

```
Roblox-MCP/
├── src/
│   ├── index.ts     # MCP stdio-сервер
│   ├── bridge.ts    # HTTP-бридж (long-poll) для плагина
│   ├── studio.ts    # запуск/поиск/закрытие Studio, поиск .rbxl
│   └── tools.ts     # 40 MCP-инструментов
├── plugin/
│   └── MCPBridge.luau  # плагин Studio (положить в папку Plugins)
├── examples/        # mcp.json + сценарии диалогов
├── scripts/
│   └── test-bridge.mjs # smoke-тест бриджа без Studio
└── dist/            # сборка (npm run build)
```

## Roadmap

- [ ] Скриншоты viewport через плагин и возврат картинки агенту
- [ ] Rojo-синхронизация (править `.lua` файлы напрямую)
- [ ] Team Create / Open Cloud publish (`publish_place`)
- [ ] Импорт моделей `.fbx/.obj` и аудио
- [ ] WebSocket вместо long-poll для меньшей задержки
- [ ] macOS/Linux CI, подписанный установщик плагина

PR и issue приветствуются.

## Лицензия

MIT — см. [LICENSE](LICENSE).

---

## English (short version)

**Roblox-MCP** — an MCP server giving AI agents full control over Roblox Studio: launch/close Studio, open places, run arbitrary Luau, inspect/build the scene, edit scripts, build GUI, lighting/camera, Toolbox inserts by asset ID, Play Solo/Run playtests, read Output. All edits are undoable (Ctrl+Z).

Architecture: MCP stdio server (Node.js) + local HTTP bridge (127.0.0.1:8090, long-poll) + Studio plugin (`plugin/MCPBridge.luau`, uses HttpService). The plugin polls the bridge because Studio plugins can't accept inbound connections.

Setup: `npm install && npm run build`, copy `plugin/MCPBridge.luau` to `%LOCALAPPDATA%\Roblox\Plugins\`, restart Studio, open any place, point your MCP client at `dist/index.js` (see `examples/mcp.json`). Full guide in Russian above; tool names are self-explanatory English.

License: MIT.

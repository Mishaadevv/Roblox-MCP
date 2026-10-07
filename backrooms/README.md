# BACKROOMS — Level 0

A realistic Backrooms horror game for Roblox: procedurally generated Level 0
(yellow wallpaper, moist carpet, buzzing fluorescents), a stalking Entity,
almond-water objective, and a full menu → HUD → death/win flow.

## Play it

1. Open `build/Backrooms.rbxlx` in Roblox Studio (double-click it).
2. Press **Play (F5)** — every run generates a **new maze**.
3. Menu → **ENTER** → find **5 almond waters** → reach the **EXIT** door.
   Don't let it touch you.

**Controls:** WASD move · SHIFT sprint (loud!) · F flashlight · mouse/touch buttons on mobile.

## How it works

```
Server (procedural, runs once per server start)
├── GameManager     round flow, lighting/atmosphere, flashlights, remotes
├── LevelGenerator  maze: pillars, wall runs, fixtures, waters, exit, spawn
├── LightManager    22 pooled PointLights follow players; strobe near Entity
├── EntityServer    the monster: stalk → hunt (sight + sound) → jumpscare kill
└── Pickups         almond water + exit door logic

Client
├── MainMenu        menu / how-to / death / win + orbiting menu camera
├── HUD             objective, stamina, flashlight/sprint buttons, dread FX
└── Effects         fullscreen jumpscare + camera shake

Shared
├── Config          all tuning in one place (maze, speeds, lights, sounds)
├── Util            pure helpers
├── LevelState      generated-level registry
├── EntityState     entity registry (for the light strobe)
└── Flashlights     headlamp registry (for flicker + toggle)
```

## Tuning without rebuilding

Edit `src/Shared/Config.lua`:
- `SEED = 0` → new maze every run; set a number for a fixed layout
- speeds, stamina, light count/range, entity sight and kill radius
- `JUMPSCARE_SOUND_ID` / `AMBIENT_HUM_SOUND_ID` — paste your audio asset IDs
  (e.g. `"rbxassetid://123456789"`) to enable custom audio; built-in UI
  click/pickup sounds work out of the box

## Rebuilding the place

Requires [Rojo](https://rojo.space/) 7.x:

```powershell
cd backrooms
rojo build default.project.json -o build/Backrooms.rbxlx
```

Sources are plain Luau (`*.server.lua` = Script, `*.client.lua` = LocalScript,
`*.lua` = ModuleScript). Luau syntax of every file is checked with stylua.

## Notes

- Single-player focused, multiplayer works (per-player waters, nearest-prey AI).
- `CharacterAutoLoads` is off: the menu owns the camera until you press ENTER.
- The Entity phases through walls — that's intentional, it's not bound by them.

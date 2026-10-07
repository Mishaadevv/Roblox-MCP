--!strict
-- BACKROOMS: Level 0 — shared tuning. Change gameplay feel here, no rebuild needed.

local Config = {}

-- ============ Level generation ============
Config.TILE = 8 -- studs per grid cell
Config.GRID_W = 26 -- cells (X)
Config.GRID_D = 26 -- cells (Z)
Config.WALL_H = 12 -- wall height in studs
Config.SEED = 0 -- 0 = new random maze every server start; set a number for a fixed layout
Config.PILLAR_EVERY = 3 -- pillar grid step in cells
Config.WALL_RUNS = 46 -- random wall segments to scatter
Config.SPAWN_CLEAR_RADIUS = 3 -- cells kept empty around spawn (in tiles)
Config.EXIT_CLEAR_RADIUS = 3 -- cells kept empty around the exit

-- ============ Look (Level 0 yellow) ============
Config.CARPET_COLOR = Color3.fromRGB(158, 133, 68)
Config.WALL_COLOR = Color3.fromRGB(178, 152, 74)
Config.PILLAR_COLOR = Color3.fromRGB(170, 144, 70)
Config.CEILING_COLOR = Color3.fromRGB(190, 178, 150)
Config.PANEL_COLOR = Color3.fromRGB(255, 244, 214) -- ceiling light panels
Config.DOOR_COLOR = Color3.fromRGB(200, 170, 60)
Config.WATER_COLOR = Color3.fromRGB(214, 186, 140) -- almond water
Config.LIGHT_COLOR = Color3.fromRGB(255, 226, 170)
Config.LIGHT_RANGE = 34
Config.LIGHT_BRIGHTNESS = 2
Config.ACTIVE_LIGHTS = 22 -- pooled real PointLights following players
Config.FIXTURE_STEP = 2 -- ceiling fixture grid step in cells

-- ============ Lighting / atmosphere ============
Config.AMBIENT = Color3.fromRGB(64, 58, 38)
Config.OUTDOOR_AMBIENT = Color3.fromRGB(50, 46, 30)
Config.ATMOSPHERE_DENSITY = 0.32
Config.ATMOSPHERE_COLOR = Color3.fromRGB(196, 170, 110)
Config.BLOOM_INTENSITY = 0.25
Config.BLOOM_THRESHOLD = 1.1
Config.SATURATION = 0.08 -- ColorCorrection: slightly washed out
Config.CONTRAST = 0.06
Config.TINT = Color3.fromRGB(255, 244, 220)

-- ============ Player ============
Config.WALK_SPEED = 14
Config.SPRINT_SPEED = 22
Config.STAMINA_MAX = 100
Config.STAMINA_DRAIN = 22 -- per second while sprinting
Config.STAMINA_REGEN = 14 -- per second while resting
Config.STAMINA_REGEN_DELAY = 0.8 -- seconds after sprint before regen starts
Config.SPAWN_HEIGHT = 4 -- studs above floor when teleporting to spawn

-- ============ Flashlight ============
Config.FLASHLIGHT_ANGLE = 55
Config.FLASHLIGHT_RANGE = 70
Config.FLASHLIGHT_BRIGHTNESS = 2.6
Config.FLASHLIGHT_COLOR = Color3.fromRGB(255, 240, 210)

-- ============ Objective ============
Config.WATERS_TO_COLLECT = 5
Config.WATERS_SPAWNED = 8
Config.WATER_MIN_SEPARATION = 5 -- cells between bottles

-- ============ Entity ============
Config.ENTITY_HEIGHT_SCALE = 1.6 -- ~11 studs tall
Config.ENTITY_WANDER_SPEED = 8
Config.ENTITY_HUNT_SPEED = 20
Config.ENTITY_STEP_TIME = 0.35 -- seconds between flicker-steps
Config.ENTITY_SIGHT_RANGE = 70 -- chase trigger while you sprint
Config.ENTITY_SIGHT_RANGE_QUIET = 45 -- chase trigger while walking
Config.ENTITY_HEAR_RADIUS = 25 -- always noticed this close (even behind)
Config.ENTITY_KILL_RADIUS = 7
Config.ENTITY_LOSE_RADIUS = 90 -- gives up beyond this
Config.ENTITY_COOLDOWN = 6 -- seconds of calm after a kill
Config.NEAR_EVENT_RADIUS = 70 -- EntityNear intensity falloff
Config.NEAR_EVENT_TICK = 0.25

-- ============ Audio (built-in only; drop your own IDs here) ============
-- UI click / pickup blip (built-in, always works)
Config.CLICK_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
Config.PICKUP_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
Config.PICKUP_PLAYBACK_SPEED = 1.6
-- Put a scream/hum asset ID here to enable it, e.g. "rbxassetid://123456789"
Config.JUMPSCARE_SOUND_ID = ""
Config.AMBIENT_HUM_SOUND_ID = ""

-- ============ RemoteEvents (created by GameManager) ============
Config.REMOTES_FOLDER = "BackroomsRemotes"
Config.REMOTE_START = "StartGame" -- client -> server
Config.REMOTE_OBJECTIVE = "Objective" -- server -> client {waters, needed}
Config.REMOTE_ENTITY_NEAR = "EntityNear" -- server -> client (intensity number 0..1)
Config.REMOTE_JUMPSCARE = "Jumpscare" -- server -> client (reason string)
Config.REMOTE_WIN = "Win" -- server -> client
Config.REMOTE_TOGGLE_FLASHLIGHT = "ToggleFlashlight" -- client -> server
Config.REMOTE_FLASHLIGHT_STATE = "FlashlightState" -- server -> client (bool)

return Config

--!strict
-- GameManager: builds remotes, atmosphere, level, flashlights, round flow.
--
-- Flow: PlayerAdded -> State=MENU (client shows menu, no character yet) ->
--   client fires StartGame -> LoadCharacter, teleport to spawn, State=PLAYING ->
--   death (State=DEAD) or exit (State=WON) -> StartGame again to retry.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LevelGenerator = require(script.Parent:WaitForChild("LevelGenerator"))
local LevelState = require(Shared:WaitForChild("LevelState"))
local Flashlights = require(Shared:WaitForChild("Flashlights"))

-- ================= remotes =================
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = Config.REMOTES_FOLDER
for _, name in
	{
		Config.REMOTE_START,
		Config.REMOTE_OBJECTIVE,
		Config.REMOTE_ENTITY_NEAR,
		Config.REMOTE_JUMPSCARE,
		Config.REMOTE_WIN,
		Config.REMOTE_TOGGLE_FLASHLIGHT,
		Config.REMOTE_FLASHLIGHT_STATE,
	}
do
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = remotesFolder
end
remotesFolder.Parent = ReplicatedStorage

local StartGameEvent = remotesFolder:WaitForChild(Config.REMOTE_START) :: RemoteEvent
local ObjectiveEvent = remotesFolder:WaitForChild(Config.REMOTE_OBJECTIVE) :: RemoteEvent
local ToggleFlashlightEvent = remotesFolder:WaitForChild(Config.REMOTE_TOGGLE_FLASHLIGHT) :: RemoteEvent
local FlashlightStateEvent = remotesFolder:WaitForChild(Config.REMOTE_FLASHLIGHT_STATE) :: RemoteEvent

-- ================= atmosphere =================
local function applyLighting()
	local okTech = pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	if not okTech then
		pcall(function()
			(Lighting :: any).Technology = Enum.Technology.ShadowMap
		end)
	end
	Lighting.Ambient = Config.AMBIENT
	Lighting.OutdoorAmbient = Config.OUTDOOR_AMBIENT
	Lighting.ColorShift_Top = Config.TINT
	Lighting.ColorShift_Bottom = Config.AMBIENT
	Lighting.GlobalShadows = true

	local atmo = Instance.new("Atmosphere")
	atmo.Density = Config.ATMOSPHERE_DENSITY
	atmo.Color = Config.ATMOSPHERE_COLOR
	atmo.Decay = Config.ATMOSPHERE_COLOR
	atmo.Glare = 0
	atmo.Haze = 2
	atmo.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = Config.BLOOM_INTENSITY
	bloom.Threshold = Config.BLOOM_THRESHOLD
	bloom.Size = 24
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0
	cc.Contrast = Config.CONTRAST
	cc.Saturation = Config.SATURATION
	cc.TintColor = Config.TINT
	cc.Parent = Lighting
end

-- ================= level =================
applyLighting()
local level = LevelGenerator.generate(Config.SEED, workspace)
LevelState.current = level
print(
	"[Backrooms] Level generated (seed "
		.. level.seed
		.. ", "
		.. #level.fixtures
		.. " fixtures, "
		.. #level.waters
		.. " waters)"
)

-- ================= flashlight =================
local function attachFlashlight(char: Model, plr: Player)
	local head = char:WaitForChild("Head", 5) :: BasePart?
	if not head then
		return
	end
	-- remove stale light (respawn safety)
	for _, d in head:GetChildren() do
		if d:IsA("SpotLight") and d.Name == "Headlamp" then
			d:Destroy()
		end
	end
	local spot = Instance.new("SpotLight")
	spot.Name = "Headlamp"
	spot.Angle = Config.FLASHLIGHT_ANGLE
	spot.Range = Config.FLASHLIGHT_RANGE
	spot.Brightness = Config.FLASHLIGHT_BRIGHTNESS
	spot.Color = Config.FLASHLIGHT_COLOR
	spot.Shadows = true
	spot.Face = Enum.NormalId.Front
	if Flashlights.baseOn[plr] == nil then
		Flashlights.baseOn[plr] = true
	end
	spot.Enabled = Flashlights.baseOn[plr] ~= false
	spot.Parent = head
	Flashlights.lights[plr] = spot
end

-- ================= round flow =================
local function pushObjective(plr: Player)
	ObjectiveEvent:FireClient(plr, {
		waters = plr:GetAttribute("Waters") or 0,
		needed = Config.WATERS_TO_COLLECT,
	})
end

local function startGameFor(plr: Player)
	plr:SetAttribute("Waters", 0)
	plr:SetAttribute("Sprinting", false)
	plr:SetAttribute("State", "PLAYING")
	pcall(function()
		plr:LoadCharacter()
	end)
	-- poll for the fresh live character (never hangs on a missed event)
	local char: Model? = nil
	for _ = 1, 50 do
		task.wait(0.1)
		local c = plr.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if c and h and (h :: Humanoid).Health > 0 then
			char = c
			break
		end
	end
	if not char then
		return
	end
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root then
		-- drop exactly on the spawn pad
		char:PivotTo(level.spawnCFrame)
		task.wait(0.1)
		char:PivotTo(level.spawnCFrame)
	end
	local hum = char:WaitForChildOfClass("Humanoid") :: Humanoid?
	if hum then
		hum.WalkSpeed = Config.WALK_SPEED
	end
	pushObjective(plr)
	FlashlightStateEvent:FireClient(plr, Flashlights.baseOn[plr] ~= false)
end

StartGameEvent.OnServerEvent:Connect(function(plr: Player)
	startGameFor(plr)
end)

ToggleFlashlightEvent.OnServerEvent:Connect(function(plr: Player)
	if plr:GetAttribute("State") ~= "PLAYING" then
		return
	end
	local cur = Flashlights.baseOn[plr] ~= false
	Flashlights.baseOn[plr] = not cur
	local light = Flashlights.lights[plr]
	if light then
		light.Enabled = not cur
	end
	FlashlightStateEvent:FireClient(plr, not cur)
end)

local function onPlayerAdded(plr: Player)
	plr:SetAttribute("State", "MENU")
	plr:SetAttribute("Waters", 0)
	plr:SetAttribute("Sprinting", false)
	Flashlights.baseOn[plr] = true
end

local function onCharacterAdded(plr: Player, char: Model)
	attachFlashlight(char, plr)
	local hum = char:WaitForChildOfClass("Humanoid") :: Humanoid?
	if hum then
		hum.Died:Connect(function()
			if plr:GetAttribute("State") == "PLAYING" then
				plr:SetAttribute("State", "DEAD")
			end
		end)
	end
end

Players.PlayerAdded:Connect(function(plr: Player)
	onPlayerAdded(plr)
	plr.CharacterAdded:Connect(function(char: Model)
		onCharacterAdded(plr, char)
	end)
end)
Players.PlayerRemoving:Connect(function(plr: Player)
	Flashlights.lights[plr] = nil
	Flashlights.baseOn[plr] = nil
end)
-- Play Solo (players already present when scripts run)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
	plr.CharacterAdded:Connect(function(char: Model)
		onCharacterAdded(plr, char)
	end)
	if plr.Character then
		onCharacterAdded(plr, plr.Character)
	end
end

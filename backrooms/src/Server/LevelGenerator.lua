--!strict
-- Procedural Level 0 generator: moist carpet, wallpaper walls, pillar grid,
-- scattered wall runs, flickering ceiling fixtures, almond water and an exit.
-- Runs once on the server at startup; every server start is a new maze
-- (unless Config.SEED is fixed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local LevelState = require(Shared:WaitForChild("LevelState"))

local LevelGenerator = {}

local function newPart(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Build the EXIT sign without any external assets (both faces: you can
-- approach the door from either side of the maze).
local function buildExitSign(door: Part)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(400, 200)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		label.TextColor3 = Color3.fromRGB(255, 220, 90)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = "EXIT"
		label.Parent = gui
		gui.Parent = door
	end
end

local function makeBottle(worldPos: Vector3): (Part, ProximityPrompt)
	local bottle = Instance.new("Part")
	bottle.Name = "AlmondWater"
	bottle.Size = Vector3.new(1, 2.2, 1)
	bottle.Position = worldPos + Vector3.new(0, 1.1, 0)
	bottle.Color = Config.WATER_COLOR
	bottle.Material = Enum.Material.Glass
	bottle.Anchored = true
	bottle.CanCollide = false
	bottle.CanQuery = false
	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Size = Vector3.new(0.8, 0.3, 0.8)
	cap.Position = bottle.Position + Vector3.new(0, 1.25, 0)
	cap.Color = Color3.fromRGB(245, 240, 225)
	cap.Material = Enum.Material.SmoothPlastic
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanQuery = false
	cap.Parent = bottle

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"
	prompt.ObjectText = "Almond Water"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = bottle
	return bottle, prompt
end

function LevelGenerator.generate(seed: number, parent: Instance): LevelState.Level
	local rng = if seed == 0 then Random.new() else Random.new(seed)
	local usedSeed = rng:NextInteger(1, 2_147_483_647)

	local tile = Config.TILE
	local gw, gd = Config.GRID_W, Config.GRID_D
	local wallH = Config.WALL_H
	local halfW = (gw * tile) / 2
	local halfD = (gd * tile) / 2

	local folder = Instance.new("Folder")
	folder.Name = "Level0"

	-- ---- floor & ceiling ----
	newPart({
		Name = "Floor",
		Size = Vector3.new(gw * tile + 2, 2, gd * tile + 2),
		Position = Vector3.new(0, -1, 0),
		Color = Config.CARPET_COLOR,
		Material = Enum.Material.Fabric,
	}, folder)
	newPart({
		Name = "Ceiling",
		Size = Vector3.new(gw * tile + 2, 1, gd * tile + 2),
		Position = Vector3.new(0, wallH + 0.5, 0),
		Color = Config.CEILING_COLOR,
		Material = Enum.Material.SmoothPlastic,
	}, folder)

	-- cell coords centered: cx in [-gw/2, gw/2)
	local function cellCenter(ix: number, iz: number): Vector3
		return Vector3.new((ix - gw / 2 + 0.5) * tile, 0, (iz - gd / 2 + 0.5) * tile)
	end

	local spawnCell = { x = 2, z = 2 }
	local exitCell = { x = gw - 3, z = gd - 3 }

	local function inClear(ix: number, iz: number): boolean
		return Util.gridDistance(ix, iz, spawnCell.x, spawnCell.z) <= Config.SPAWN_CLEAR_RADIUS
			or Util.gridDistance(ix, iz, exitCell.x, exitCell.z) <= Config.EXIT_CLEAR_RADIUS
	end

	-- ---- perimeter ----
	local wallT = 1
	newPart({
		Name = "WallNorth",
		Size = Vector3.new(gw * tile + 2, wallH, wallT),
		Position = Vector3.new(0, wallH / 2, -halfD - 0.5),
		Color = Config.WALL_COLOR,
		Material = Enum.Material.Fabric,
	}, folder)
	newPart({
		Name = "WallSouth",
		Size = Vector3.new(gw * tile + 2, wallH, wallT),
		Position = Vector3.new(0, wallH / 2, halfD + 0.5),
		Color = Config.WALL_COLOR,
		Material = Enum.Material.Fabric,
	}, folder)
	newPart({
		Name = "WallWest",
		Size = Vector3.new(wallT, wallH, gd * tile + 2),
		Position = Vector3.new(-halfW - 0.5, wallH / 2, 0),
		Color = Config.WALL_COLOR,
		Material = Enum.Material.Fabric,
	}, folder)
	newPart({
		Name = "WallEast",
		Size = Vector3.new(wallT, wallH, gd * tile + 2),
		Position = Vector3.new(halfW + 0.5, wallH / 2, 0),
		Color = Config.WALL_COLOR,
		Material = Enum.Material.Fabric,
	}, folder)

	-- ---- pillars ----
	local pillarFolder = Instance.new("Folder")
	pillarFolder.Name = "Pillars"
	pillarFolder.Parent = folder
	local pi = 0
	for ix = 0, gw - 1, Config.PILLAR_EVERY do
		for iz = 0, gd - 1, Config.PILLAR_EVERY do
			if not inClear(ix, iz) and rng:NextNumber() > 0.12 then
				pi += 1
				local c = cellCenter(ix, iz)
				newPart({
					Name = "Pillar" .. pi,
					Size = Vector3.new(2, wallH, 2),
					Position = Vector3.new(c.X, wallH / 2, c.Z),
					Color = Config.PILLAR_COLOR,
					Material = Enum.Material.Concrete,
				}, pillarFolder)
			end
		end
	end

	-- ---- scattered wall runs with door gaps ----
	local wallsFolder = Instance.new("Folder")
	wallsFolder.Name = "Walls"
	wallsFolder.Parent = folder
	local wi = 0
	for _ = 1, Config.WALL_RUNS do
		local horizontal = rng:NextInteger(0, 1) == 1
		local sx = rng:NextInteger(1, gw - 2)
		local sz = rng:NextInteger(1, gd - 2)
		local len = rng:NextInteger(2, 4)
		local gapAt = rng:NextInteger(1, len)
		for i = 1, len do
			if i ~= gapAt then
				local ix = if horizontal then sx + i - 1 else sx
				local iz = if horizontal then sz else sz + i - 1
				if ix >= 0 and ix < gw and iz >= 0 and iz < gd and not inClear(ix, iz) then
					wi += 1
					local c = cellCenter(ix, iz)
					local size = if horizontal then Vector3.new(tile, wallH, 1) else Vector3.new(1, wallH, tile)
					newPart({
						Name = "Wall" .. wi,
						Size = size,
						Position = Vector3.new(c.X, wallH / 2, c.Z),
						Color = Config.WALL_COLOR,
						Material = Enum.Material.Fabric,
					}, wallsFolder)
				end
			end
		end
	end

	-- ---- ceiling fixtures (emissive panels; real lights are pooled by LightManager) ----
	local fixtures: { Vector3 } = {}
	local fixFolder = Instance.new("Folder")
	fixFolder.Name = "Fixtures"
	fixFolder.Parent = folder
	for ix = 0, gw - 1, Config.FIXTURE_STEP do
		for iz = 0, gd - 1, Config.FIXTURE_STEP do
			local c = cellCenter(ix, iz)
			local pos = Vector3.new(c.X, wallH - 0.15, c.Z)
			local panel = newPart({
				Name = "Panel",
				Size = Vector3.new(5, 0.3, 5),
				Position = pos,
				Color = Config.PANEL_COLOR,
				Material = Enum.Material.Neon,
			}, fixFolder)
			panel.CanCollide = false
			panel.CanTouch = false
			panel.CastShadow = false
			table.insert(fixtures, pos)
		end
	end

	-- ---- almond water ----
	local waters: { Part } = {}
	local prompts: { ProximityPrompt } = {}
	local placed: { { x: number, z: number } } = {}
	local tries = 0
	while #waters < Config.WATERS_SPAWNED and tries < 400 do
		tries += 1
		local ix = rng:NextInteger(0, gw - 1)
		local iz = rng:NextInteger(0, gd - 1)
		if Util.gridDistance(ix, iz, spawnCell.x, spawnCell.z) < 6 then
			continue
		end
		local ok = true
		for _, p in placed do
			if Util.gridDistance(ix, iz, p.x, p.z) < Config.WATER_MIN_SEPARATION then
				ok = false
				break
			end
		end
		if not ok then
			continue
		end
		table.insert(placed, { x = ix, z = iz })
		local c = cellCenter(ix, iz)
		local bottle, prompt = makeBottle(c)
		bottle.Parent = folder
		table.insert(waters, bottle)
		table.insert(prompts, prompt)
	end

	-- ---- exit door ----
	local ec = cellCenter(exitCell.x, exitCell.z)
	local exitFolder = Instance.new("Folder")
	exitFolder.Name = "Exit"
	exitFolder.Parent = folder
	newPart({
		Name = "PostL",
		Size = Vector3.new(1, 9, 1),
		Position = ec + Vector3.new(-2.5, 4.5, 0),
		Color = Config.DOOR_COLOR,
		Material = Enum.Material.Wood,
	}, exitFolder)
	newPart({
		Name = "PostR",
		Size = Vector3.new(1, 9, 1),
		Position = ec + Vector3.new(2.5, 4.5, 0),
		Color = Config.DOOR_COLOR,
		Material = Enum.Material.Wood,
	}, exitFolder)
	newPart({
		Name = "Lintel",
		Size = Vector3.new(6, 1, 1),
		Position = ec + Vector3.new(0, 9, 0),
		Color = Config.DOOR_COLOR,
		Material = Enum.Material.Wood,
	}, exitFolder)
	local door = newPart({
		Name = "ExitDoor",
		Size = Vector3.new(4, 8, 0.6),
		Position = ec + Vector3.new(0, 4, 0),
		Color = Color3.fromRGB(216, 186, 74),
		Material = Enum.Material.SmoothPlastic,
	}, exitFolder)
	buildExitSign(door)
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.ActionText = "Escape"
	exitPrompt.ObjectText = "Locked — find Almond Water"
	exitPrompt.HoldDuration = 1.5
	exitPrompt.MaxActivationDistance = 12
	exitPrompt.RequiresLineOfSight = false
	exitPrompt.Parent = door

	-- ---- spawn pad (visual marker; teleport is authoritative) ----
	local sc = cellCenter(spawnCell.x, spawnCell.z)
	local pad = newPart({
		Name = "SpawnPad",
		Size = Vector3.new(5, 0.4, 5),
		Position = Vector3.new(sc.X, 0.2, sc.Z),
		Color = Color3.fromRGB(120, 110, 80),
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	pad.CanCollide = false
	pad.CanTouch = false

	folder.Parent = parent

	local level: LevelState.Level = {
		seed = usedSeed,
		folder = folder,
		spawnCFrame = CFrame.new(sc.X, Config.SPAWN_HEIGHT, sc.Z),
		exitPosition = ec,
		fixtures = fixtures,
		waters = waters,
		waterPrompts = prompts,
		exitPrompt = exitPrompt,
		tile = tile,
		gridW = gw,
		gridD = gd,
		wallH = wallH,
	}
	return level
end

-- Emergency flat arena used when procedural generation throws.
-- Guarantees the game is ALWAYS playable (spawn, 5+ waters, exit, lights).
function LevelGenerator.fallback(parent: Instance): LevelState.Level
	local folder = Instance.new("Folder")
	folder.Name = "Level0Fallback"
	local W, H = 120, 12
	newPart({
		Name = "Floor",
		Size = Vector3.new(W, 2, W),
		Position = Vector3.new(0, -1, 0),
		Color = Config.CARPET_COLOR,
		Material = Enum.Material.Fabric,
	}, folder)
	newPart({
		Name = "Ceiling",
		Size = Vector3.new(W, 1, W),
		Position = Vector3.new(0, H + 0.5, 0),
		Color = Config.CEILING_COLOR,
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	for _, w in
		{
			{ "N", Vector3.new(W, H, 1), Vector3.new(0, H / 2, -W / 2) },
			{ "S", Vector3.new(W, H, 1), Vector3.new(0, H / 2, W / 2) },
			{ "W", Vector3.new(1, H, W), Vector3.new(-W / 2, H / 2, 0) },
			{ "E", Vector3.new(1, H, W), Vector3.new(W / 2, H / 2, 0) },
		}
	do
		newPart({
			Name = "Wall" .. (w :: any)[1],
			Size = (w :: any)[2],
			Position = (w :: any)[3],
			Color = Config.WALL_COLOR,
			Material = Enum.Material.Fabric,
		}, folder)
	end
	local fixtures: { Vector3 } = {}
	for gx = -1, 1 do
		for gz = -1, 1 do
			local pos = Vector3.new(gx * 30, H - 0.15, gz * 30)
			local panel = newPart({
				Name = "Panel",
				Size = Vector3.new(5, 0.3, 5),
				Position = pos,
				Color = Config.PANEL_COLOR,
				Material = Enum.Material.Neon,
			}, folder)
			panel.CanCollide = false
			panel.CanTouch = false
			panel.CastShadow = false
			table.insert(fixtures, pos)
		end
	end
	local waters: { Part } = {}
	local prompts: { ProximityPrompt } = {}
	for i = 1, Config.WATERS_SPAWNED do
		local bottle, prompt = makeBottle(Vector3.new(-40 + i * 12, 0, 20))
		bottle.Parent = folder
		table.insert(waters, bottle)
		table.insert(prompts, prompt)
	end
	local door = newPart({
		Name = "ExitDoor",
		Size = Vector3.new(4, 8, 0.6),
		Position = Vector3.new(40, 4, -40),
		Color = Color3.fromRGB(216, 186, 74),
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	buildExitSign(door)
	local exitPrompt = Instance.new("ProximityPrompt")
	exitPrompt.ActionText = "Escape"
	exitPrompt.ObjectText = "Locked — find Almond Water"
	exitPrompt.HoldDuration = 1.5
	exitPrompt.MaxActivationDistance = 12
	exitPrompt.RequiresLineOfSight = false
	exitPrompt.Parent = door
	local pad = newPart({
		Name = "SpawnPad",
		Size = Vector3.new(5, 0.4, 5),
		Position = Vector3.new(-40, 0.2, -40),
		Color = Color3.fromRGB(120, 110, 80),
		Material = Enum.Material.SmoothPlastic,
	}, folder)
	pad.CanCollide = false
	pad.CanTouch = false
	folder.Parent = parent
	return {
		seed = -1,
		folder = folder,
		spawnCFrame = CFrame.new(-40, Config.SPAWN_HEIGHT, -40),
		exitPosition = Vector3.new(40, 0, -40),
		fixtures = fixtures,
		waters = waters,
		waterPrompts = prompts,
		exitPrompt = exitPrompt,
		tile = Config.TILE,
		gridW = 15,
		gridD = 15,
		wallH = H,
	}
end

return LevelGenerator

--!strict
-- Pooled ceiling lights: fixtures are everywhere (cheap emissive panels),
-- but only ACTIVE_LIGHTS real PointLights exist. They snap to the fixtures
-- nearest each player and strobe when the Entity is close. This keeps
-- Future lighting fast with hundreds of visible panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LevelState = require(Shared:WaitForChild("LevelState"))
local EntityState = require(Shared:WaitForChild("EntityState"))

local Players = game:GetService("Players")

local pool: { PointLight } = {}
local fixturePhase: { number } = {} -- per-fixture random flicker phase
local rng = Random.new()

local function nearestFixtures(pos: Vector3, level, count: number): { number }
	-- returns fixture indices sorted by distance (partial selection)
	local scored: { { d: number, i: number } } = {}
	for i, f in level.fixtures do
		local dx = f.X - pos.X
		local dz = f.Z - pos.Z
		table.insert(scored, { d = dx * dx + dz * dz, i = i })
	end
	table.sort(scored, function(a, b)
		return a.d < b.d
	end)
	local out: { number } = {}
	for k = 1, math.min(count, #scored) do
		table.insert(out, scored[k].i)
	end
	return out
end

local function buildPool(parent: Instance)
	for _ = 1, Config.ACTIVE_LIGHTS do
		local anchor = Instance.new("Part")
		anchor.Name = "LightAnchor"
		anchor.Size = Vector3.new(0.5, 0.5, 0.5)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		local light = Instance.new("PointLight")
		light.Color = Config.LIGHT_COLOR
		light.Range = Config.LIGHT_RANGE
		light.Brightness = Config.LIGHT_BRIGHTNESS
		light.Shadows = false
		light.Enabled = true
		light.Parent = anchor
		anchor.Parent = parent
		table.insert(pool, light)
	end
end

task.spawn(function()
	-- wait for the level
	while LevelState.current == nil do
		task.wait(0.2)
	end
	local level = LevelState.current :: LevelState.Level
	for _ in level.fixtures do
		table.insert(fixturePhase, rng:NextNumber() * math.pi * 2)
	end

	local holder = Instance.new("Folder")
	holder.Name = "LightPool"
	holder.Parent = workspace
	buildPool(holder)

	local t = 0
	while true do
		task.wait(0.4)
		t += 0.4
		level = LevelState.current :: LevelState.Level

		local targets: { Vector3 } = {}
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				table.insert(targets, root.Position)
			end
		end
		if #targets == 0 then
			-- nobody in game: park lights at spawn
			targets = { Vector3.new(level.spawnCFrame.X, 0, level.spawnCFrame.Z) }
		end

		local entityPos = if EntityState.root then EntityState.root.Position else nil
		local perTarget = math.max(1, math.floor(#pool / #targets))
		local li = 1
		for _, tp in targets do
			local idx = nearestFixtures(tp, level, perTarget)
			for _, fi in idx do
				if li > #pool then
					break
				end
				local light = pool[li]
				local anchor = light.Parent :: BasePart
				anchor.Position = level.fixtures[fi]
				li += 1
				-- ambient fluorescent flicker: rare dropouts
				local phase = fixturePhase[fi]
				local jitter = math.sin(t * 7 + phase) * 0.5 + math.sin(t * 23 + phase * 2) * 0.5
				local dropout = (math.sin(t * 1.7 + phase * 3) > 0.985)
				-- entity strobe: fixtures near the monster flash hard
				local strobe = false
				if entityPos then
					local d = (level.fixtures[fi] - entityPos).Magnitude
					if d < 30 then
						strobe = (math.floor(t * 9) % 2 == 0)
					end
				end
				if strobe then
					light.Enabled = (math.floor(t * 9) % 3 ~= 0)
					light.Brightness = Config.LIGHT_BRIGHTNESS * 1.4
				elseif dropout then
					light.Enabled = false
				else
					light.Enabled = true
					light.Brightness = Config.LIGHT_BRIGHTNESS * (0.92 + 0.08 * jitter)
				end
			end
		end
		-- park the rest far underground
		while li <= #pool do
			(pool[li].Parent :: BasePart).Position = Vector3.new(0, -100, 0)
			li += 1
		end
	end
end)

--!strict
-- THE ENTITY. A tall black humanoid that stalks Level 0.
-- It phases through walls (it is not bound by them), hunts by sight and
-- sound (sprinting is loud), flickers the lights and your flashlight,
-- and kills at close range with a jumpscare.
--
-- Net protocol (Remotes folder created by GameManager):
--   EntityNear (FireClient, number)  - 0..1 dread intensity
--   Jumpscare  (FireClient, string)  - play fullscreen scare, then you die

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LevelState = require(Shared:WaitForChild("LevelState"))
local EntityState = require(Shared:WaitForChild("EntityState"))
local Flashlights = require(Shared:WaitForChild("Flashlights"))

local Remotes = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER)
local EntityNearEvent = Remotes:WaitForChild(Config.REMOTE_ENTITY_NEAR) :: RemoteEvent
local JumpscareEvent = Remotes:WaitForChild(Config.REMOTE_JUMPSCARE) :: RemoteEvent

-- wait for level + remotes consumers
while LevelState.current == nil do
	task.wait(0.2)
end
local level = LevelState.current :: LevelState.Level

-- ================= model =================

local BODY = Color3.fromRGB(8, 8, 10)

local function limb(size: Vector3, offset: Vector3, model: Model): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = BODY
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	local torso = model.PrimaryPart :: BasePart
	p.CFrame = torso.CFrame * CFrame.new(offset)
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = p
	weld.Parent = torso
	return p
end

local model = Instance.new("Model")
model.Name = "Entity"

local s = Config.ENTITY_HEIGHT_SCALE
local torso = Instance.new("Part")
torso.Name = "Torso"
torso.Size = Vector3.new(2 * s, 3.4 * s, 1 * s)
torso.Color = BODY
torso.Material = Enum.Material.SmoothPlastic
torso.Anchored = true
torso.CanCollide = false
torso.CanTouch = false
torso.CanQuery = false
torso.CastShadow = false
local startPos = level.exitPosition + Vector3.new(0, 3 * s, 12)
torso.CFrame = CFrame.new(startPos)
torso.Parent = model
model.PrimaryPart = torso

limb(Vector3.new(1.5 * s, 1.5 * s, 1.2 * s), Vector3.new(0, 2.4 * s, 0), model).Name = "Head"
local eyeL = limb(Vector3.new(0.35 * s, 0.35 * s, 0.2), Vector3.new(-0.4 * s, 2.5 * s, 0.65 * s), model)
eyeL.Name = "EyeL"
eyeL.Color = Color3.fromRGB(255, 255, 255)
eyeL.Material = Enum.Material.Neon
local eyeR = limb(Vector3.new(0.35 * s, 0.35 * s, 0.2), Vector3.new(0.4 * s, 2.5 * s, 0.65 * s), model)
eyeR.Name = "EyeR"
eyeR.Color = Color3.fromRGB(255, 255, 255)
eyeR.Material = Enum.Material.Neon
limb(Vector3.new(0.8 * s, 3.6 * s, 0.8 * s), Vector3.new(-1.5 * s, 0, 0), model).Name = "ArmL"
limb(Vector3.new(0.8 * s, 3.6 * s, 0.8 * s), Vector3.new(1.5 * s, 0, 0), model).Name = "ArmR"
limb(Vector3.new(0.9 * s, 3.4 * s, 0.9 * s), Vector3.new(-0.6 * s, -3.4 * s, 0), model).Name = "LegL"
limb(Vector3.new(0.9 * s, 3.4 * s, 0.9 * s), Vector3.new(0.6 * s, -3.4 * s, 0), model).Name = "LegR"

model.Parent = workspace
EntityState.root = torso

-- ================= helpers =================

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { model }

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 1 then
		return true
	end
	local hit = workspace:Raycast(from, dir, rayParams)
	return hit == nil or hit.Distance >= dist - 1
end

local function playingPlayers(): { Player }
	local out: { Player } = {}
	for _, plr in Players:GetPlayers() do
		if plr:GetAttribute("State") == "PLAYING" and plr.Character then
			local root = plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				table.insert(out, plr)
			end
		end
	end
	return out
end

local function nearestPlayer(pos: Vector3): (Player?, number)
	local best: Player? = nil
	local bestD = math.huge
	for _, plr in playingPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				bestD = d
				best = plr
			end
		end
	end
	return best, bestD
end

local halfExtentX = (level.gridW * level.tile) / 2
local halfExtentZ = (level.gridD * level.tile) / 2

local function clampInside(p: Vector3): Vector3
	return Vector3.new(
		math.clamp(p.X, -halfExtentX + 4, halfExtentX - 4),
		torso.Size.Y / 2 + 0.5,
		math.clamp(p.Z, -halfExtentZ + 4, halfExtentZ - 4)
	)
end

local rng = Random.new()

-- flicker-step toward a point: snap closer in one glitchy jump
local function stepToward(target: Vector3, maxStep: number)
	local cur = torso.Position
	local dir = target - cur
	dir = Vector3.new(dir.X, 0, dir.Z)
	local dist = dir.Magnitude
	if dist < 0.5 then
		return
	end
	local step = math.min(dist, maxStep)
	local flat = dir.Unit
	local newPos = clampInside(cur + flat * step)
	-- glitch: brief transparency blink on the step frame
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "EyeL" and d.Name ~= "EyeR" then
			d.Transparency = 0.6
		end
	end
	-- eyes sit on +Z, so face +Z toward the target (lookAt faces -Z: aim behind)
	torso.CFrame = CFrame.new(newPos, newPos - flat)
	task.delay(0.12, function()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "EyeL" and d.Name ~= "EyeR" then
				d.Transparency = 0
			end
		end
	end)
end

local target: Player? = nil
local wanderPoint: Vector3? = nil
local cooldownUntil = 0

-- ================= main loop =================

local tick = 0
while true do
	task.wait(Config.ENTITY_STEP_TIME)
	tick += Config.ENTITY_STEP_TIME
	local now = os.clock()

	if now < cooldownUntil then
		EntityState.hunting = false
		continue
	end

	local me = torso.Position
	local candidate, dist = nearestPlayer(me)

	-- acquire / drop target
	if candidate and candidate.Character then
		local root = candidate.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		local head = candidate.Character:FindFirstChild("Head") :: BasePart?
		local sprinting = candidate:GetAttribute("Sprinting") == true
		local range = if sprinting then Config.ENTITY_SIGHT_RANGE else Config.ENTITY_SIGHT_RANGE_QUIET
		local seen = false
		if root and head then
			if dist <= Config.ENTITY_HEAR_RADIUS then
				seen = true -- too close: it hears your breathing
			elseif dist <= range and hasLineOfSight(me + Vector3.new(0, 3, 0), head.Position) then
				seen = true
			end
		end
		if seen then
			target = candidate
		elseif target == candidate and dist > Config.ENTITY_LOSE_RADIUS then
			target = nil -- lost you
		end
	else
		if target and dist > Config.ENTITY_LOSE_RADIUS then
			target = nil
		end
	end

	EntityState.hunting = target ~= nil
	EntityState.cooldownUntil = cooldownUntil

	if target and target.Character then
		local root = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			stepToward(root.Position, Config.ENTITY_HUNT_SPEED * Config.ENTITY_STEP_TIME)
			-- kill
			if (root.Position - torso.Position).Magnitude <= Config.ENTITY_KILL_RADIUS then
				JumpscareEvent:FireClient(target, "entity")
				cooldownUntil = now + Config.ENTITY_COOLDOWN
				target = nil
				EntityState.hunting = false
				task.delay(1.0, function()
					-- the scare plays first; then you die
					for _, plr in Players:GetPlayers() do
						-- only kill if still playing (didn't win/disconnect mid-scare)
						if plr:GetAttribute("State") == "PLAYING" and plr.Character then
							local hum = plr.Character:FindFirstChildOfClass("Humanoid")
							-- kill only the victim: closest to the entity
							local r = plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
							if
								hum
								and r
								and (r.Position - torso.Position).Magnitude <= Config.ENTITY_KILL_RADIUS + 4
							then
								hum.Health = 0
							end
						end
					end
				end)
			end
		end
	else
		-- stalk: drift between random points, closing in slowly
		if not wanderPoint or (wanderPoint - me).Magnitude < 6 then
			local a = rng:NextNumber() * math.pi * 2
			local d = rng:NextNumber(20, 44)
			wanderPoint = clampInside(me + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d))
		end
		-- lean toward the nearest living player from afar (it knows you're here)
		local prey, preyD = nearestPlayer(me)
		local goal = wanderPoint :: Vector3
		if prey and preyD < 60 and prey.Character then
			local r = prey.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				goal = (wanderPoint :: Vector3):Lerp(r.Position, 0.35)
			end
		end
		stepToward(goal, Config.ENTITY_WANDER_SPEED * Config.ENTITY_STEP_TIME)
	end

	-- idle bob (it hovers wrong)
	torso.CFrame += Vector3.new(0, math.sin(tick * 3) * 0.06, 0)
end

-- ================= dread + flashlight flicker tick =================

task.spawn(function()
	while true do
		task.wait(Config.NEAR_EVENT_TICK)
		local me = torso.Position
		for _, plr in Players:GetPlayers() do
			if plr:GetAttribute("State") ~= "PLAYING" or not plr.Character then
				continue
			end
			local root = plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end
			local dist = (root.Position - me).Magnitude
			local intensity = 1 - math.clamp(dist / Config.NEAR_EVENT_RADIUS, 0, 1)
			if not EntityState.hunting then
				intensity *= 0.45 -- background dread while it stalks
			end
			if cooldownUntil > os.clock() then
				intensity = 0
			end
			EntityNearEvent:FireClient(plr, intensity)
			-- its presence kills your flashlight
			local light = Flashlights.lights[plr]
			if light and light.Parent then
				if intensity > 0.55 and Flashlights.baseOn[plr] then
					light.Enabled = (math.floor(os.clock() * 11) % 3 ~= 0)
				else
					light.Enabled = Flashlights.baseOn[plr] ~= false
				end
			end
		end
	end
end)

--!strict
-- HUD: objective counter, stamina bar, flashlight + sprint buttons (mobile),
-- dread vignette + TV-static when the Entity is near.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER)
local ObjectiveEvent = Remotes:WaitForChild(Config.REMOTE_OBJECTIVE) :: RemoteEvent
local EntityNearEvent = Remotes:WaitForChild(Config.REMOTE_ENTITY_NEAR) :: RemoteEvent
local ToggleFlashlightEvent = Remotes:WaitForChild(Config.REMOTE_TOGGLE_FLASHLIGHT) :: RemoteEvent
local FlashlightStateEvent = Remotes:WaitForChild(Config.REMOTE_FLASHLIGHT_STATE) :: RemoteEvent

local YELLOW = Color3.fromRGB(216, 186, 74)

local gui = Instance.new("ScreenGui")
gui.Name = "BackroomsHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Enabled = false

-- objective
local obj = Instance.new("TextLabel")
obj.Name = "Objective"
obj.AnchorPoint = Vector2.new(0, 0)
obj.Position = UDim2.new(0, 20, 0, 16)
obj.Size = UDim2.new(0, 320, 0, 34)
obj.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
obj.BackgroundTransparency = 0.45
obj.BorderSizePixel = 0
obj.Font = Enum.Font.GothamBold
obj.TextSize = 20
obj.TextColor3 = YELLOW
obj.TextXAlignment = Enum.TextXAlignment.Left
local objPad = Instance.new("UIPadding")
objPad.PaddingLeft = UDim.new(0, 12)
objPad.Parent = obj
obj.Text = "ALMOND WATER 0/" .. Config.WATERS_TO_COLLECT
obj.Parent = gui

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0, 0)
hint.Position = UDim2.new(0, 20, 0, 54)
hint.Size = UDim2.new(0, 320, 0, 22)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 14
hint.TextColor3 = Color3.fromRGB(150, 140, 110)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "SHIFT sprint  •  F flashlight"
hint.Parent = gui

-- stamina
local stamBg = Instance.new("Frame")
stamBg.AnchorPoint = Vector2.new(0.5, 1)
stamBg.Position = UDim2.new(0.5, 0, 1, -28)
stamBg.Size = UDim2.new(0, 300, 0, 12)
stamBg.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
stamBg.BackgroundTransparency = 0.3
stamBg.BorderSizePixel = 0
stamBg.Parent = gui
local stamFill = Instance.new("Frame")
stamFill.Size = UDim2.fromScale(1, 1)
stamFill.BackgroundColor3 = Color3.fromRGB(120, 200, 120)
stamFill.BorderSizePixel = 0
stamFill.Parent = stamBg

-- flashlight button (touch-friendly, works with mouse too)
local lightBtn = Instance.new("TextButton")
lightBtn.AnchorPoint = Vector2.new(1, 1)
lightBtn.Position = UDim2.new(1, -20, 1, -52)
lightBtn.Size = UDim2.new(0, 120, 0, 48)
lightBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
lightBtn.BackgroundTransparency = 0.2
lightBtn.BorderSizePixel = 0
lightBtn.Font = Enum.Font.GothamBold
lightBtn.TextSize = 18
lightBtn.TextColor3 = YELLOW
lightBtn.Text = "LIGHT: ON"
lightBtn.Parent = gui

-- sprint button (mobile)
local sprintBtn = Instance.new("TextButton")
sprintBtn.AnchorPoint = Vector2.new(1, 1)
sprintBtn.Position = UDim2.new(1, -152, 1, -52)
sprintBtn.Size = UDim2.new(0, 120, 0, 48)
sprintBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
sprintBtn.BackgroundTransparency = 0.2
sprintBtn.BorderSizePixel = 0
sprintBtn.Font = Enum.Font.GothamBold
sprintBtn.TextSize = 18
sprintBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
sprintBtn.Text = "SPRINT"
sprintBtn.Visible = UserInputService.TouchEnabled
sprintBtn.Parent = gui

-- dread vignette (4 red edges)
local vigColor = Color3.fromRGB(120, 0, 0)
local edges: { Frame } = {}
local function edge(size: UDim2, pos: UDim2): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = vigColor
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	table.insert(edges, f)
	return f
end
edge(UDim2.new(1, 0, 0, 90), UDim2.new(0, 0, 0, 0))
edge(UDim2.new(1, 0, 0, 90), UDim2.new(0, 0, 1, -90))
edge(UDim2.new(0, 90, 1, 0), UDim2.new(0, 0, 0, 0))
edge(UDim2.new(0, 90, 1, 0), UDim2.new(1, -90, 0, 0))

-- TV static: recycled white dots
local staticDots: { Frame } = {}
for _ = 1, 110 do
	local d = Instance.new("Frame")
	d.Size = UDim2.fromOffset(2, 2)
	d.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	d.BackgroundTransparency = 1
	d.BorderSizePixel = 0
	d.Parent = gui
	table.insert(staticDots, d)
end

gui.Parent = playerGui

-- ================= state =================
local stamina = Config.STAMINA_MAX
local regenAt = 0
local sprintHeld = false
local sprinting = false
local dread = 0
local lastWaters = 0
local camSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)

local function character(): (Model?, Humanoid?)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return c, h
end

local function setSprinting(on: boolean)
	local _, hum = character()
	if on == sprinting then
		return
	end
	if on and stamina <= 5 then
		return
	end
	sprinting = on
	plr:SetAttribute("Sprinting", on)
	if hum then
		hum.WalkSpeed = if on then Config.SPRINT_SPEED else Config.WALK_SPEED
	end
end

-- ================= input =================
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not gui.Enabled then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprintHeld = true
		setSprinting(true)
	elseif input.KeyCode == Enum.KeyCode.F then
		ToggleFlashlightEvent:FireServer()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprintHeld = false
		setSprinting(false)
	end
end)
sprintBtn.MouseButton1Down:Connect(function()
	sprintHeld = true
	setSprinting(true)
end)
sprintBtn.MouseButton1Up:Connect(function()
	sprintHeld = false
	setSprinting(false)
end)
lightBtn.MouseButton1Click:Connect(function()
	ToggleFlashlightEvent:FireServer()
end)

-- ================= remotes =================
local function blip()
	if Config.PICKUP_SOUND_ID == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = Config.PICKUP_SOUND_ID
	s.PlaybackSpeed = Config.PICKUP_PLAYBACK_SPEED
	s.Volume = 0.7
	s.Parent = playerGui
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

ObjectiveEvent.OnClientEvent:Connect(function(data: { waters: number, needed: number })
	obj.Text = `ALMOND WATER {data.waters}/{data.needed}`
	if data.waters > lastWaters then
		blip()
	end
	lastWaters = data.waters
end)

EntityNearEvent.OnClientEvent:Connect(function(intensity: number)
	dread = math.clamp(intensity, 0, 1)
end)

FlashlightStateEvent.OnClientEvent:Connect(function(on: boolean)
	lightBtn.Text = if on then "LIGHT: ON" else "LIGHT: OFF"
end)

-- show HUD only while actually playing
local function refreshVisibility()
	local state = plr:GetAttribute("State")
	gui.Enabled = (state == "PLAYING")
end
plr:GetAttributeChangedSignal("State"):Connect(refreshVisibility)
refreshVisibility()

-- fresh spawn: reset sprint state (WalkSpeed is set by the server)
plr.CharacterAdded:Connect(function()
	sprinting = false
	sprintHeld = false
	stamina = Config.STAMINA_MAX
	plr:SetAttribute("Sprinting", false)
end)

-- ================= per-frame =================
local staticTick = 0
RunService.RenderStepped:Connect(function(dt: number)
	if not gui.Enabled then
		return
	end
	local _, hum = character()
	-- stamina
	if sprinting then
		local moving = hum and hum.MoveDirection.Magnitude > 0.1
		if moving then
			stamina -= Config.STAMINA_DRAIN * dt
			if stamina <= 0 then
				stamina = 0
				setSprinting(false)
			end
			regenAt = os.clock() + Config.STAMINA_REGEN_DELAY
		end
	else
		if os.clock() >= regenAt then
			stamina = math.min(Config.STAMINA_MAX, stamina + Config.STAMINA_REGEN * dt)
		end
		if sprintHeld and stamina > 5 then
			setSprinting(true)
		end
	end
	stamFill.Size = UDim2.fromScale(stamina / Config.STAMINA_MAX, 1)
	stamFill.BackgroundColor3 = if stamina > 40 then Color3.fromRGB(120, 200, 120) else Color3.fromRGB(200, 80, 60)

	-- viewport size can change (mobile rotate)
	local vs = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if vs then
		camSize = vs
	end

	-- dread drivers: vignette + static
	for _, e in edges do
		e.BackgroundTransparency = 1 - dread * 0.55
	end
	staticTick += dt
	if dread > 0.25 and staticTick > 0.08 then
		staticTick = 0
		for _, d in staticDots do
			if math.random() < dread then
				d.Position = UDim2.fromOffset(math.random(0, camSize.X), math.random(0, camSize.Y))
				d.BackgroundTransparency = 0.75 - dread * 0.4
			else
				d.BackgroundTransparency = 1
			end
		end
	elseif dread <= 0.25 then
		for _, d in staticDots do
			d.BackgroundTransparency = 1
		end
	end
	dread = math.max(0, dread - dt * 0.5) -- decay between server ticks
end)

--!strict
-- Main menu / death / win screens + menu camera orbit.
-- The player has no character until they press PLAY (CharacterAutoLoads=false).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER)
local StartGameEvent = Remotes:WaitForChild(Config.REMOTE_START) :: RemoteEvent
local WinEvent = Remotes:WaitForChild(Config.REMOTE_WIN) :: RemoteEvent

local YELLOW = Color3.fromRGB(216, 186, 74)
local DARK = Color3.fromRGB(8, 8, 10)

local function clickSound()
	if Config.CLICK_SOUND_ID == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = Config.CLICK_SOUND_ID
	s.Volume = 0.6
	s.Parent = playerGui
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

-- ================= gui =================
local gui = Instance.new("ScreenGui")
gui.Name = "BackroomsMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100

local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = DARK
bg.BorderSizePixel = 0
bg.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.34, 0)
title.Size = UDim2.new(0, 700, 0, 110)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = YELLOW
title.Text = "THE BACKROOMS"
title.Parent = bg

local subtitle = Instance.new("TextLabel")
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.Position = UDim2.new(0.5, 0, 0.44, 0)
subtitle.Size = UDim2.new(0, 500, 0, 36)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 22
subtitle.TextColor3 = Color3.fromRGB(150, 140, 110)
subtitle.Text = "LEVEL 0 — SURVIVE"
subtitle.Parent = bg

local function makeButton(name: string, text: string, y: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(0.5, 0, y, 0)
	b.Size = UDim2.new(0, 320, 0, 56)
	b.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 24
	b.TextColor3 = YELLOW
	b.Text = text
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = YELLOW
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = b
	b.Parent = bg
	return b
end

local playBtn = makeButton("Play", "▶  ENTER", 0.58)
local howBtn = makeButton("How", "?  HOW TO PLAY", 0.68)

local footer = Instance.new("TextLabel")
footer.AnchorPoint = Vector2.new(0.5, 1)
footer.Position = UDim2.new(0.5, 0, 1, -14)
footer.Size = UDim2.new(0, 600, 0, 24)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.Gotham
footer.TextSize = 14
footer.TextColor3 = Color3.fromRGB(90, 85, 70)
footer.Text = "headphones recommended  •  v1.0"
footer.Parent = bg

-- status line: loading progress / server errors (never leave the player guessing)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
statusLabel.Position = UDim2.new(0.5, 0, 0.78, 0)
statusLabel.Size = UDim2.new(0, 700, 0, 28)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 16
statusLabel.TextColor3 = Color3.fromRGB(200, 120, 60)
statusLabel.Text = ""
statusLabel.TextWrapped = true
statusLabel.Parent = bg

-- how-to panel
local howPanel = Instance.new("Frame")
howPanel.Name = "HowPanel"
howPanel.AnchorPoint = Vector2.new(0.5, 0.5)
howPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
howPanel.Size = UDim2.new(0, 460, 0, 360)
howPanel.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
howPanel.BorderSizePixel = 0
howPanel.Visible = false
howPanel.Parent = bg
local howCorner = Instance.new("UICorner")
howCorner.CornerRadius = UDim.new(0, 10)
howCorner.Parent = howPanel
local howStroke = Instance.new("UIStroke")
howStroke.Color = YELLOW
howStroke.Thickness = 1
howStroke.Transparency = 0.4
howStroke.Parent = howPanel
local howText = Instance.new("TextLabel")
howText.Size = UDim2.new(1, -40, 1, -80)
howText.Position = UDim2.new(0, 20, 0, 20)
howText.BackgroundTransparency = 1
howText.Font = Enum.Font.Gotham
howText.TextSize = 17
howText.TextXAlignment = Enum.TextXAlignment.Left
howText.TextYAlignment = Enum.TextYAlignment.Top
howText.TextColor3 = Color3.fromRGB(210, 200, 170)
howText.TextWrapped = true
howText.Text = "You no-clipped out of reality.\n\n"
	.. "• WASD — move, SHIFT — sprint (loud!), F — flashlight\n"
	.. "• Find 5 ALMOND WATER bottles (follow the prompts)\n"
	.. "• Reach the EXIT door and escape\n"
	.. "• IT hears sprinting. If the lights die — run.\n"
	.. "• Mobile: use the on-screen buttons"
howText.Parent = howPanel
local howClose = Instance.new("TextButton")
howClose.Size = UDim2.new(1, -40, 0, 40)
howClose.Position = UDim2.new(0, 20, 1, -60)
howClose.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
howClose.BorderSizePixel = 0
howClose.Font = Enum.Font.GothamBold
howClose.TextSize = 18
howClose.TextColor3 = YELLOW
howClose.Text = "CLOSE"
howClose.Parent = howPanel

-- fade frame (also used for transitions)
local fade = Instance.new("Frame")
fade.Name = "Fade"
fade.Size = UDim2.fromScale(1, 1)
fade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Parent = gui

-- death screen
local death = Instance.new("Frame")
death.Name = "Death"
death.Size = UDim2.fromScale(1, 1)
death.BackgroundColor3 = Color3.fromRGB(10, 0, 0)
death.BackgroundTransparency = 0.25
death.BorderSizePixel = 0
death.Visible = false
death.Parent = gui
local deathTitle = Instance.new("TextLabel")
deathTitle.AnchorPoint = Vector2.new(0.5, 0.5)
deathTitle.Position = UDim2.new(0.5, 0, 0.4, 0)
deathTitle.Size = UDim2.new(0, 600, 0, 100)
deathTitle.BackgroundTransparency = 1
deathTitle.Font = Enum.Font.GothamBlack
deathTitle.TextScaled = true
deathTitle.TextColor3 = Color3.fromRGB(170, 20, 20)
deathTitle.Text = "YOU DIED"
deathTitle.Parent = death
local deathSub = Instance.new("TextLabel")
deathSub.AnchorPoint = Vector2.new(0.5, 0.5)
deathSub.Position = UDim2.new(0.5, 0, 0.5, 0)
deathSub.Size = UDim2.new(0, 500, 0, 30)
deathSub.BackgroundTransparency = 1
deathSub.Font = Enum.Font.Gotham
deathSub.TextSize = 20
deathSub.TextColor3 = Color3.fromRGB(150, 140, 130)
deathSub.Text = "It found you."
deathSub.Parent = death
local retryBtn = makeButton("Retry", "↻  TRY AGAIN", 0.5)
retryBtn.Parent = death
retryBtn.Position = UDim2.new(0.5, 0, 0.62, 0)

-- win screen
local win = Instance.new("Frame")
win.Name = "Win"
win.Size = UDim2.fromScale(1, 1)
win.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
win.BackgroundTransparency = 0.3
win.BorderSizePixel = 0
win.Visible = false
win.Parent = gui
local winTitle = Instance.new("TextLabel")
winTitle.AnchorPoint = Vector2.new(0.5, 0.5)
winTitle.Position = UDim2.new(0.5, 0, 0.4, 0)
winTitle.Size = UDim2.new(0, 700, 0, 100)
winTitle.BackgroundTransparency = 1
winTitle.Font = Enum.Font.GothamBlack
winTitle.TextScaled = true
winTitle.TextColor3 = YELLOW
winTitle.Text = "YOU ESCAPED"
winTitle.Parent = win
local winSub = Instance.new("TextLabel")
winSub.AnchorPoint = Vector2.new(0.5, 0.5)
winSub.Position = UDim2.new(0.5, 0, 0.5, 0)
winSub.Size = UDim2.new(0, 500, 0, 30)
winSub.BackgroundTransparency = 1
winSub.Font = Enum.Font.Gotham
winSub.TextSize = 20
winSub.TextColor3 = Color3.fromRGB(180, 170, 140)
winSub.Text = "Level 0 is behind you. For now."
winSub.Parent = win
local againBtn = makeButton("Again", "↻  PLAY AGAIN", 0.5)
againBtn.Parent = win
againBtn.Position = UDim2.new(0.5, 0, 0.62, 0)

gui.Parent = playerGui

-- ================= menu behaviours =================

-- spooky title flicker
task.spawn(function()
	while true do
		task.wait(math.random() * 3 + 1.5)
		if not bg.Visible then
			continue
		end
		title.TextTransparency = 0.7
		task.wait(0.06)
		title.TextTransparency = 0
		task.wait(0.05)
		title.TextTransparency = 0.4
		task.wait(0.05)
		title.TextTransparency = 0
	end
end)

howBtn.MouseButton1Click:Connect(function()
	clickSound()
	howPanel.Visible = true
end)
howClose.MouseButton1Click:Connect(function()
	clickSound()
	howPanel.Visible = false
end)

-- slow menu camera drift around the maze (clipping = found-footage vibe)
local cam = workspace.CurrentCamera :: Camera
local menuCam = true
local angle = 0
task.spawn(function()
	cam.CameraType = Enum.CameraType.Scriptable
	while true do
		task.wait(0.03)
		if not menuCam then
			continue
		end
		angle += 0.0016
		local r = 34
		local pos = Vector3.new(math.cos(angle) * r, 8, math.sin(angle) * r)
		cam.CFrame = CFrame.new(pos, Vector3.new(pos.X * 2, 3, pos.Z * 2))
	end
end)

local function fadeTo(black: boolean, time: number)
	TweenService
		:Create(fade, TweenInfo.new(time, Enum.EasingStyle.Linear), { BackgroundTransparency = if black then 0 else 1 })
		:Play()
	task.wait(time + 0.05)
end

local playing = false
local function play()
	if playing then
		return
	end
	playing = true
	clickSound()
	statusLabel.Text = "LOADING LEVEL..."
	fadeTo(true, 0.6)
	bg.Visible = false
	death.Visible = false
	win.Visible = false
	StartGameEvent:FireServer()
	-- wait for a fresh LIVE character (the old corpse doesn't count on retry)
	local char: Model? = nil
	for _ = 1, 150 do -- up to ~15s: weak machines need time
		local c = plr.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if c and h and (h :: Humanoid).Health > 0 then
			char = c
			break
		end
		task.wait(0.1)
	end
	if not char then
		-- NEVER trap the player on a black screen: come back with a reason
		fadeTo(false, 0.4)
		bg.Visible = true
		statusLabel.Text = "SERVER DIDN'T SPAWN YOU (15s). Open View > Output, "
			.. "look for red [Backrooms] errors and send them to the dev."
		playing = false
		return
	end
	statusLabel.Text = ""
	local hum = char and char:WaitForChildOfClass("Humanoid") :: Humanoid?
	if hum then
		menuCam = false
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = hum
	end
	fadeTo(false, 0.6)
	gui.Enabled = false
	playing = false
end

playBtn.MouseButton1Click:Connect(play)
retryBtn.MouseButton1Click:Connect(function()
	death.Visible = false
	gui.Enabled = true
	bg.Visible = false
	play()
end)
againBtn.MouseButton1Click:Connect(function()
	win.Visible = false
	gui.Enabled = true
	bg.Visible = false
	play()
end)
-- keyboard: Enter starts
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.Return and gui.Enabled and bg.Visible and not howPanel.Visible then
		play()
	end
end)

-- death / win
local function watchCharacter(char: Model)
	local hum = char:WaitForChildOfClass("Humanoid") :: Humanoid?
	if not hum then
		return
	end
	hum.Died:Connect(function()
		task.wait(1.2) -- let the jumpscare finish
		gui.Enabled = true
		bg.Visible = false
		win.Visible = false
		death.Visible = true
	end)
end
plr.CharacterAdded:Connect(watchCharacter)
if plr.Character then
	watchCharacter(plr.Character)
end

WinEvent.OnClientEvent:Connect(function()
	gui.Enabled = true
	bg.Visible = false
	death.Visible = false
	win.Visible = true
	menuCam = false
end)

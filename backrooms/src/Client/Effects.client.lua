--!strict
-- Fullscreen effects: Entity jumpscare + camera shake.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER)
local JumpscareEvent = Remotes:WaitForChild(Config.REMOTE_JUMPSCARE) :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "BackroomsFX"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 150
gui.Enabled = false

local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
black.BorderSizePixel = 0
black.Parent = gui

-- the face: two white eyes + a dark screaming mouth
local function ellipse(x: number, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(x, 0, 0.38, 0)
	f.Size = UDim2.new(0, w, 0, h)
	f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	f.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	f.Visible = false
	f.Parent = gui
	return f
end
local eyeL = ellipse(0.36, 90, 130)
local eyeR = ellipse(0.64, 90, 130)

local mouth = Instance.new("Frame")
mouth.AnchorPoint = Vector2.new(0.5, 0.5)
mouth.Position = UDim2.new(0.5, 0, 0.68, 0)
mouth.Size = UDim2.new(0, 130, 0, 190)
mouth.BackgroundColor3 = Color3.fromRGB(60, 0, 0)
mouth.BorderSizePixel = 0
local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(1, 0)
mc.Parent = mouth
mouth.Visible = false
mouth.Parent = gui

local red = Instance.new("Frame")
red.Size = UDim2.fromScale(1, 1)
red.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
red.BackgroundTransparency = 1
red.BorderSizePixel = 0
red.Parent = gui

gui.Parent = playerGui

local shaking = 0

local function scream()
	if Config.JUMPSCARE_SOUND_ID == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = Config.JUMPSCARE_SOUND_ID
	s.Volume = 1
	s.Parent = playerGui
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

JumpscareEvent.OnClientEvent:Connect(function(_reason: string)
	gui.Enabled = true
	black.BackgroundTransparency = 0
	eyeL.Visible = true
	eyeR.Visible = true
	mouth.Visible = true
	red.BackgroundTransparency = 0.55
	shaking = 1.35
	scream()
	task.delay(1.35, function()
		gui.Enabled = false
		eyeL.Visible = false
		eyeR.Visible = false
		mouth.Visible = false
		red.BackgroundTransparency = 1
	end)
end)

-- violent handheld shake during the scare
RunService.RenderStepped:Connect(function(dt: number)
	if shaking <= 0 then
		return
	end
	shaking -= dt
	local cam = workspace.CurrentCamera
	if cam then
		local s = 0.09 * math.clamp(shaking, 0, 1)
		cam.CFrame *= CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0) * CFrame.Angles(
			(math.random() - 0.5) * s * 0.4,
			(math.random() - 0.5) * s * 0.4,
			0
		)
	end
end)

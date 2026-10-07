--!strict
-- Almond water pickups + the exit door.
-- Waters are per-player (attributes); the exit opens once YOU have enough.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LevelState = require(Shared:WaitForChild("LevelState"))

while LevelState.current == nil do
	task.wait(0.2)
end
local level = LevelState.current :: LevelState.Level

local Remotes = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER)
local ObjectiveEvent = Remotes:WaitForChild(Config.REMOTE_OBJECTIVE) :: RemoteEvent
local WinEvent = Remotes:WaitForChild(Config.REMOTE_WIN) :: RemoteEvent

local function pushObjective(plr: Player)
	local waters = plr:GetAttribute("Waters") or 0
	ObjectiveEvent:FireClient(plr, { waters = waters, needed = Config.WATERS_TO_COLLECT })
end

for _, prompt in level.waterPrompts do
	prompt.Triggered:Connect(function(plr: Player)
		if plr:GetAttribute("State") ~= "PLAYING" then
			return
		end
		local bottle = prompt.Parent
		if not bottle or not bottle.Parent then
			return -- already taken
		end
		bottle:Destroy() -- cap is a child of the bottle: goes with it
		local waters = (plr:GetAttribute("Waters") or 0) + 1
		plr:SetAttribute("Waters", waters)
		pushObjective(plr)
	end)
end

local hintLock = false
level.exitPrompt.Triggered:Connect(function(plr: Player)
	if plr:GetAttribute("State") ~= "PLAYING" then
		return
	end
	local waters = plr:GetAttribute("Waters") or 0
	if waters >= Config.WATERS_TO_COLLECT then
		plr:SetAttribute("State", "WON")
		WinEvent:FireClient(plr)
	else
		-- global cosmetic hint (co-op: everyone sees it briefly, that's fine)
		if not hintLock then
			hintLock = true
			local old = level.exitPrompt.ActionText
			level.exitPrompt.ActionText = `Need {Config.WATERS_TO_COLLECT - waters} more!`
			task.delay(2, function()
				level.exitPrompt.ActionText = old
				hintLock = false
			end)
		end
		pushObjective(plr)
	end
end)

-- keep late-join / respawn HUDs in sync
Players.PlayerAdded:Connect(function(plr: Player)
	plr:GetAttributeChangedSignal("Waters"):Connect(function()
		pushObjective(plr)
	end)
end)
for _, plr in Players:GetPlayers() do
	plr:GetAttributeChangedSignal("Waters"):Connect(function()
		pushObjective(plr)
	end)
end

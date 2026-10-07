# Example: generating an obby from scratch

An agent (Claude / Cursor) with `roblox-mcp` connected:

> You: Open Studio and build an obby of 10 stair-step platforms.
>
> Agent:
> 1. `studio_status` → Studio not running → `studio_launch`
> 2. `bridge_status` → waits for `pluginConnected: true`
> 3. `execute_luau`:
> ```lua
> local base = Vector3.new(0, 5, 0)
> for i = 1, 10 do
>   local p = Instance.new("Part")
>   p.Name = "Stage" .. i
>   p.Size = Vector3.new(8, 1, 8)
>   p.Position = base + Vector3.new(i * 10, i * 2, 0)
>   p.Anchored = true
>   p.Material = Enum.Material.SmoothPlastic
>   p.Color = Color3.fromHSV(i / 10, 0.8, 1)
>   p.Parent = workspace
> end
> local spawn = Instance.new("SpawnLocation")
> spawn.Size = Vector3.new(6, 1, 6)
> spawn.Position = Vector3.new(-10, 5, 0)
> spawn.Anchored = true
> spawn.Parent = workspace
> return "10 stages + spawn created"
> ```
> 4. `create_script` (Script in ServerScriptService, touch scoring):
> ```lua
> local Players = game:GetService("Players")
> local points = {}
> for _, p in workspace:GetChildren() do
>   if p.Name:match("^Stage") and p:IsA("BasePart") then
>     p.Touched:Connect(function(hit)
>       local plr = Players:GetPlayerFromCharacter(hit.Parent)
>       if plr then
>         points[plr.UserId] = (points[plr.UserId] or 0) + 1
>         print(plr.Name .. " stage touched, total=" .. points[plr.UserId])
>       end
>     end)
>   end
> end
> ```
> 5. `play_solo` → `get_output` → `stop_playtest`

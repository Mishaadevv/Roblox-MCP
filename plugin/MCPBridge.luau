--[[
	MCPBridge — Roblox Studio plugin: lets AI agents (via roblox-mcp) fully drive Studio.
	Companion of the `roblox-mcp` MCP server (Node.js).

	INSTALL:
		1. Copy THIS file into your Studio Plugins folder:
		   Windows: %LOCALAPPDATA%\Roblox\Plugins\MCPBridge.luau
		   (create the folder if missing; any .lua/.luau file there auto-loads as a plugin)
		   macOS: ~/Documents/Roblox/Plugins/MCPBridge.luau
		2. Restart Roblox Studio, open any place.
		3. Start the MCP server on this machine: `npm start` in roblox-mcp
		   (bridge defaults to http://127.0.0.1:8090).
		4. If you set ROBLOX_MCP_API_KEY for the server, run in View > Command Bar:
		      _G.MCP_SetApiKey("your-key-here")
		   Then the toolbar button turns on and Output shows [MCP] Connected.
		5. Allow the plugin's localhost HTTP permission when Studio prompts
		   (Plugin Management > MCPBridge > allow http://127.0.0.1 / localhost).

	PROTOCOL (HttpService, plugin -> bridge):
		GET  /health
		GET  /poll?timeoutMs=25000      -> { command = { id, method, params } | nil }
		POST /result { id, ok, output, error }

	All mutating commands are wrapped in ChangeHistoryService so Ctrl+Z undoes agent edits.
]]

local PLUGIN_NAME = "[MCP]"
local VERSION = "0.1.0"

local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")
local LogService = game:GetService("LogService")
local Lighting = game:GetService("Lighting")

-- ============================== settings ==============================

local PORTS =
	{ 8090, 8081, 8082, 8083, 8084, 8085, 8086, 8087, 8088, 8089, 8091, 8092, 8093, 8094, 8095, 8096, 8097, 8098, 8099 }
local serverUrl: string? = nil
local enabled = true
local apiKey = ""

pcall(function()
	apiKey = plugin:GetSetting("MCP_ApiKey") or ""
	if apiKey == nil then
		apiKey = ""
	end
end)

function _G.MCP_SetApiKey(key: string)
	apiKey = key or ""
	pcall(function()
		plugin:SetSetting("MCP_ApiKey", apiKey)
	end)
	print(PLUGIN_NAME .. " API key saved (" .. string.len(apiKey) .. " chars). Reconnecting...")
	serverUrl = nil
end

function _G.MCP_GetApiKey()
	if apiKey == "" then
		return "(no key set)"
	end
	return "(set, " .. string.len(apiKey) .. " chars, ..." .. string.sub(apiKey, -4) .. ")"
end

local function log(msg: string)
	print(PLUGIN_NAME .. " " .. msg)
end

-- ============================== output capture ==============================

local outputBuffer: { string } = {}
local MAX_OUTPUT = 500

local function pushOutput(text: string)
	table.insert(outputBuffer, text)
	if #outputBuffer > MAX_OUTPUT then
		table.remove(outputBuffer, 1)
	end
end

pcall(function()
	LogService.MessageOut:Connect(function(message: string, _messageType)
		pushOutput(message)
	end)
end)
pushOutput("MCPBridge v" .. VERSION .. " loaded.")

-- ============================== helpers ==============================

local function headers()
	if apiKey ~= "" then
		return { ["Content-Type"] = "application/json", ["x-api-key"] = apiKey }
	end
	return { ["Content-Type"] = "application/json" }
end

local function httpGet(url: string): (boolean, any)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = headers(),
		})
	end)
	if not ok then
		return false, res
	end
	if not res.Success then
		return false, res.StatusCode .. " " .. (res.StatusMessage or "")
	end
	local ok2, decoded = pcall(function()
		return HttpService:JSONDecode(res.Body)
	end)
	if not ok2 then
		return false, "bad JSON from bridge"
	end
	return true, decoded
end

local function httpPost(url: string, body: any): (boolean, any)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = headers(),
			Body = HttpService:JSONEncode(body),
		})
	end)
	if not ok then
		return false, res
	end
	if not res.Success then
		return false, res.StatusCode .. " " .. (res.StatusMessage or "")
	end
	local ok2, decoded = pcall(function()
		return HttpService:JSONDecode(res.Body)
	end)
	if not ok2 then
		return true, res.Body
	end
	return true, decoded
end

local function findServer(): string?
	for _, port in PORTS do
		local url = "http://127.0.0.1:" .. port
		local ok, data = httpGet(url .. "/health")
		if ok and type(data) == "table" and data.service == "roblox-mcp-bridge" then
			return url
		end
	end
	return nil
end

local function splitPath(pathStr: string): { string }
	local parts = {}
	for part in string.gmatch(pathStr, "[^%.]+") do
		table.insert(parts, part)
	end
	return parts
end

-- Dotted paths like "Workspace.SpawnLocation", "Lighting", "ServerScriptService.MyScript"
local function resolvePath(pathStr: string): Instance?
	if pathStr == "" or pathStr == "game" then
		return game
	end
	local parts = splitPath(pathStr)
	if #parts == 0 then
		return nil
	end
	local current: Instance? = nil
	local first = parts[1]
	-- top-level service or child of game
	local okSvc, svc = pcall(function()
		return game:GetService(first)
	end)
	if okSvc and svc then
		current = svc
	else
		current = game:FindFirstChild(first)
	end
	if not current then
		return nil
	end
	for i = 2, #parts do
		if not current then
			return nil
		end
		current = (current :: Instance):FindFirstChild(parts[i])
	end
	return current
end

local function fullPath(inst: Instance): string
	local parts = {}
	local cur: Instance? = inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

-- ---- value encode/decode (Roblox types <-> JSON) ----

local function encodeValue(v: any): any
	local t = typeof(v)
	if t == "Vector3" then
		return { __type = "Vector3", value = { v.X, v.Y, v.Z } }
	elseif t == "Vector2" then
		return { __type = "Vector2", value = { v.X, v.Y } }
	elseif t == "Color3" then
		return {
			__type = "Color3",
			value = { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) },
		}
	elseif t == "UDim" then
		return { __type = "UDim", value = { v.Scale, v.Offset } }
	elseif t == "UDim2" then
		return { __type = "UDim2", value = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	elseif t == "CFrame" then
		local c = { v:GetComponents() }
		return { __type = "CFrame", value = c }
	elseif t == "BrickColor" then
		return { __type = "BrickColor", value = v.Name }
	elseif t == "EnumItem" then
		return { __type = "Enum", value = tostring(v) }
	elseif t == "Instance" then
		return { __type = "Instance", value = fullPath(v) }
	elseif t == "table" then
		local out = {}
		for k, item in v do
			out[k] = encodeValue(item)
		end
		return out
	elseif t == "string" or t == "number" or t == "boolean" or t == "nil" then
		return v
	else
		-- userdata Roblox types without a portable encoding (Font, Ray, BrickColor already handled, etc.)
		-- stringify so HttpService:JSONEncode never chokes on handler results
		local okStr, s = pcall(function()
			return tostring(v)
		end)
		if okStr then
			return s
		end
		return "<unserializable " .. t .. ">"
	end
end

local function parseEnum(enumStr: string): EnumItem?
	-- "Enum.Material.SmoothPlastic"
	local parts = splitPath(enumStr)
	if #parts ~= 3 or parts[1] ~= "Enum" then
		return nil
	end
	local ok, item = pcall(function()
		return (Enum :: any)[parts[2]][parts[3]]
	end)
	if ok then
		return item
	end
	return nil
end

local function decodeValue(v: any): any
	if type(v) ~= "table" then
		-- convenience: "Enum.X.Y" strings
		if type(v) == "string" and string.sub(v, 1, 5) == "Enum." then
			return parseEnum(v)
		end
		return v
	end
	local tag = (v :: any).__type
	if type(tag) ~= "string" then
		local out = {}
		for k, item in v do
			out[k] = decodeValue(item)
		end
		return out
	end
	local val = (v :: any).value
	if tag == "Vector3" then
		return Vector3.new(val[1], val[2], val[3])
	elseif tag == "Vector2" then
		return Vector2.new(val[1], val[2])
	elseif tag == "Color3" then
		return Color3.fromRGB(val[1], val[2], val[3])
	elseif tag == "UDim" then
		return UDim.new(val[1], val[2])
	elseif tag == "UDim2" then
		return UDim2.new(val[1], val[2], val[3], val[4])
	elseif tag == "CFrame" then
		return CFrame.new(table.unpack(val))
	elseif tag == "BrickColor" then
		return BrickColor.new(val)
	elseif tag == "Enum" then
		return parseEnum(val) or val
	elseif tag == "Instance" then
		return resolvePath(val)
	end
	return v
end

local function setProp(inst: Instance, prop: string, raw: any)
	local value = decodeValue(raw)
	local ok, err = pcall(function()
		(inst :: any)[prop] = value
	end)
	if not ok then
		error(err)
	end
end

local function applyProperties(inst: Instance, props: { [string]: any })
	for prop, raw in props do
		local value = decodeValue(raw)
		local ok, err = pcall(function()
			(inst :: any)[prop] = value
		end)
		if not ok then
			error("Cannot set " .. inst.ClassName .. "." .. prop .. ": " .. tostring(err))
		end
	end
end

local function buildInstance(spec: any, parent: Instance): Instance
	local className = spec.className or spec.ClassName
	assert(type(className) == "string", "child spec needs className")
	local inst = Instance.new(className)
	if spec.name or spec.Name then
		inst.Name = spec.name or spec.Name
	end
	if spec.properties or spec.Properties then
		applyProperties(inst, spec.properties or spec.Properties)
	end
	inst.Parent = parent
	for _, childSpec in spec.children or spec.Children or {} do
		buildInstance(childSpec, inst)
	end
	return inst
end

-- ============================== command handlers ==============================

local handlers: { [string]: (params: any) -> any } = {}

handlers["execute_luau"] = function(params)
	local code = params.code
	assert(type(code) == "string" and code ~= "", "code (string) required")
	local fn, loadErr = loadstring(code)
	if not fn then
		error("Luau syntax error: " .. tostring(loadErr))
	end
	local printed: { string } = {}
	local oldPrint = print
	local function capturePrint(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring(select(i, ...)))
		end
		table.insert(printed, table.concat(parts, "  "))
	end
	print = capturePrint
	local results: { any } = {}
	local ok, err
	-- undo support for whatever the code does
	local recOk = pcall(function()
		ChangeHistoryService:TryBeginRecording("MCP execute_luau")
	end)
	ok, err = pcall(function()
		-- copy pack into a clean array (drop pack's `n` field so JSON stays an array)
		local packed = table.pack(fn())
		local clean = {}
		for i = 1, packed.n do
			clean[i] = packed[i]
		end
		results = clean
	end)
	print = oldPrint
	pcall(function()
		if recOk then
			ChangeHistoryService:FinishRecording("MCP execute_luau")
		end
	end)
	if not ok then
		error(tostring(err))
	end
	return {
		returned = encodeValue(results),
		printed = printed,
	}
end

handlers["get_scene"] = function(params)
	local rootPath = params.root or "game"
	local maxDepth = math.clamp(tonumber(params.maxDepth) or 3, 1, 10)
	local maxNodes = math.clamp(tonumber(params.maxNodes) or 300, 1, 2000)
	local includeProps = params.includeProperties == true
	local root: Instance
	if rootPath == "game" or rootPath == "" then
		root = game
	else
		root = resolvePath(rootPath) or error("Root not found: " .. tostring(rootPath))
	end
	local count = 0
	local truncated = false
	local KEY_PROPS = {
		"Anchored",
		"CanCollide",
		"Transparency",
		"Position",
		"Size",
		"CFrame",
		"Color",
		"Material",
		"Shape",
		"Enabled",
		"Visible",
		"Text",
		"Source",
	}
	local function node(inst: Instance, depth: number): any?
		if count >= maxNodes then
			truncated = true
			return nil
		end
		count += 1
		local entry: any = { Name = inst.Name, ClassName = inst.ClassName, Path = fullPath(inst) }
		if includeProps then
			local props = {}
			for _, p in KEY_PROPS do
				local ok, v = pcall(function()
					return (inst :: any)[p]
				end)
				if ok and v ~= nil and typeof(v) ~= "Instance" and typeof(v) ~= "function" then
					local ok2, enc = pcall(function()
						return encodeValue(v)
					end)
					if ok2 then
						if type(enc) == "string" and string.len(enc) > 500 then
							props[p] = string.sub(enc, 1, 500) .. "..."
						else
							props[p] = enc
						end
					end
				end
			end
			entry.Properties = props
		end
		if depth < maxDepth then
			local children = {}
			for _, child in inst:GetChildren() do
				if count >= maxNodes then
					truncated = true
					break
				end
				local n = node(child, depth + 1)
				if n then
					table.insert(children, n)
				end
			end
			table.sort(children, function(a, b)
				return a.Name < b.Name
			end)
			entry.Children = children
			entry.ChildCount = #inst:GetChildren()
		else
			entry.ChildCount = #inst:GetChildren()
		end
		return entry
	end
	-- "game" root: list services instead of the DataModel itself
	if root == game then
		local services = {}
		for _, child in game:GetChildren() do
			if count >= maxNodes then
				truncated = true
				break
			end
			-- services have all-caps-ish names; include everything, sorted
			local n = node(child, 1)
			if n then
				table.insert(services, n)
			end
		end
		table.sort(services, function(a, b)
			return a.Name < b.Name
		end)
		return { Root = "game", Services = services, nodeCount = count, truncated = truncated }
	end
	return { Root = fullPath(root), Tree = node(root, 0), nodeCount = count, truncated = truncated }
end

handlers["get_instance"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	local out: any = {
		Name = inst.Name,
		ClassName = inst.ClassName,
		Path = fullPath(inst),
		Parent = inst.Parent and fullPath(inst.Parent) or nil,
	}
	local props = {}
	for _, p in
		{
			"Anchored",
			"CanCollide",
			"CanQuery",
			"Transparency",
			"Reflectance",
			"Position",
			"Rotation",
			"Orientation",
			"Size",
			"CFrame",
			"Color",
			"Material",
			"MaterialVariant",
			"Shape",
			"TopSurface",
			"BottomSurface",
			"Enabled",
			"Visible",
			"Text",
			"BackgroundColor3",
			"TextColor3",
			"Font",
			"TextSize",
			"Value",
			"ClockTime",
			"Brightness",
			"Ambient",
			"OutdoorAmbient",
			"FogEnd",
			"FogStart",
			"GeographicLatitude",
		}
	do
		local ok, v = pcall(function()
			return (inst :: any)[p]
		end)
		if ok and v ~= nil and typeof(v) ~= "Instance" then
			local ok2, enc = pcall(function()
				return encodeValue(v)
			end)
			if ok2 then
				props[p] = enc
			end
		end
	end
	out.Properties = props
	out.Children = (function()
		local names = {}
		for _, c in inst:GetChildren() do
			table.insert(names, { Name = c.Name, ClassName = c.ClassName, Path = fullPath(c) })
		end
		table.sort(names, function(a, b)
			return a.Name < b.Name
		end)
		return names
	end)()
	return out
end

handlers["create_instance"] = function(params)
	local className = params.className or error("className required")
	local parentPath = params.parent or "Workspace"
	local parent = resolvePath(parentPath) or error("Parent not found: " .. tostring(parentPath))
	local inst = Instance.new(className)
	if params.name then
		inst.Name = params.name
	end
	if params.properties then
		applyProperties(inst, params.properties)
	end
	ChangeHistoryService:TryBeginRecording("MCP create " .. className)
	inst.Parent = parent
	ChangeHistoryService:FinishRecording("MCP create " .. className)
	return { Path = fullPath(inst), Name = inst.Name, ClassName = inst.ClassName }
end

handlers["set_property"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	assert(params.property, "property required")
	ChangeHistoryService:TryBeginRecording("MCP set_property")
	setProp(inst, params.property, params.value)
	ChangeHistoryService:FinishRecording("MCP set_property")
	return { Path = fullPath(inst), property = params.property, value = encodeValue((inst :: any)[params.property]) }
end

handlers["set_properties"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	assert(type(params.properties) == "table", "properties table required")
	ChangeHistoryService:TryBeginRecording("MCP set_properties")
	applyProperties(inst, params.properties)
	ChangeHistoryService:FinishRecording("MCP set_properties")
	return { Path = fullPath(inst), updated = params.properties }
end

handlers["delete_instance"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	local p = fullPath(inst)
	ChangeHistoryService:TryBeginRecording("MCP delete")
	inst:Destroy()
	ChangeHistoryService:FinishRecording("MCP delete")
	return { deleted = p }
end

handlers["rename_instance"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	assert(params.newName, "newName required")
	ChangeHistoryService:TryBeginRecording("MCP rename")
	inst.Name = params.newName
	ChangeHistoryService:FinishRecording("MCP rename")
	return { Path = fullPath(inst) }
end

handlers["reparent_instance"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	local newParent = resolvePath(params.newParent) or error("New parent not found: " .. tostring(params.newParent))
	ChangeHistoryService:TryBeginRecording("MCP reparent")
	inst.Parent = newParent
	ChangeHistoryService:FinishRecording("MCP reparent")
	return { Path = fullPath(inst) }
end

handlers["duplicate_instance"] = function(params)
	local inst = resolvePath(params.path) or error("Instance not found: " .. tostring(params.path))
	ChangeHistoryService:TryBeginRecording("MCP duplicate")
	local clone = inst:Clone()
	if params.newName then
		clone.Name = params.newName
	end
	clone.Parent = inst.Parent
	ChangeHistoryService:FinishRecording("MCP duplicate")
	return { Path = fullPath(clone), Name = clone.Name }
end

handlers["get_selection"] = function(_params)
	local out = {}
	for _, inst in Selection:Get() do
		table.insert(out, { Name = inst.Name, ClassName = inst.ClassName, Path = fullPath(inst) })
	end
	return out
end

handlers["set_selection"] = function(params)
	assert(type(params.paths) == "table", "paths array required")
	local insts = {}
	for _, p in params.paths do
		local inst = resolvePath(p)
		if inst then
			table.insert(insts, inst)
		end
	end
	Selection:Set(insts)
	return { selected = #insts }
end

-- ---------- scripts ----------

local function isScript(inst: Instance)
	return inst:IsA("LuaSourceContainer")
end

handlers["list_scripts"] = function(params)
	local root: Instance = game
	if params.root and params.root ~= "" and params.root ~= "game" then
		root = resolvePath(params.root) or error("Root not found: " .. tostring(params.root))
	end
	local out = {}
	local function walk(inst: Instance)
		if isScript(inst) then
			local ok, src = pcall(function()
				return (inst :: any).Source
			end)
			table.insert(out, {
				Path = fullPath(inst),
				Name = inst.Name,
				ClassName = inst.ClassName,
				Lines = ok and src and select(2, string.gsub(src, "\n", "")) + 1 or nil,
			})
		end
		for _, c in inst:GetChildren() do
			walk(c)
		end
	end
	if root == game then
		for _, svc in game:GetChildren() do
			walk(svc)
		end
	else
		walk(root)
	end
	table.sort(out, function(a, b)
		return a.Path < b.Path
	end)
	return out
end

handlers["read_script"] = function(params)
	local inst = resolvePath(params.path) or error("Script not found: " .. tostring(params.path))
	if not isScript(inst) then
		error("Not a script: " .. inst.ClassName)
	end
	return { Path = fullPath(inst), Name = inst.Name, ClassName = inst.ClassName, Source = (inst :: any).Source }
end

handlers["write_script"] = function(params)
	local inst = resolvePath(params.path) or error("Script not found: " .. tostring(params.path))
	if not isScript(inst) then
		error("Not a script: " .. inst.ClassName)
	end
	assert(type(params.source) == "string", "source required")
	ChangeHistoryService:TryBeginRecording("MCP write_script");
	(inst :: any).Source = params.source
	ChangeHistoryService:FinishRecording("MCP write_script")
	return { Path = fullPath(inst), bytes = string.len(params.source) }
end

handlers["create_script"] = function(params)
	assert(
		params.scriptType == "Script" or params.scriptType == "LocalScript" or params.scriptType == "ModuleScript",
		"scriptType must be Script|LocalScript|ModuleScript"
	)
	assert(params.name, "name required")
	assert(params.parent, "parent required")
	local parent = resolvePath(params.parent) or error("Parent not found: " .. tostring(params.parent))
	local inst = Instance.new(params.scriptType)
	inst.Name = params.name
	if params.source then
		(inst :: any).Source = params.source
	end
	ChangeHistoryService:TryBeginRecording("MCP create_script")
	inst.Parent = parent
	ChangeHistoryService:FinishRecording("MCP create_script")
	return { Path = fullPath(inst) }
end

handlers["delete_script"] = function(params)
	local inst = resolvePath(params.path) or error("Script not found: " .. tostring(params.path))
	if not isScript(inst) then
		error("Not a script: " .. inst.ClassName)
	end
	local p = fullPath(inst)
	ChangeHistoryService:TryBeginRecording("MCP delete_script")
	inst:Destroy()
	ChangeHistoryService:FinishRecording("MCP delete_script")
	return { deleted = p }
end

handlers["grep_scripts"] = function(params)
	assert(params.pattern, "pattern required")
	local root: Instance = game
	if params.root and params.root ~= "" and params.root ~= "game" then
		root = resolvePath(params.root) or error("Root not found")
	end
	local hits = {}
	local function walk(inst: Instance)
		if isScript(inst) then
			local ok, src = pcall(function()
				return (inst :: any).Source
			end)
			if ok and src and string.find(src, params.pattern) then
				-- first matching line
				local lineNo = 0
				local preview = ""
				for line in string.gmatch(src, "[^\n]*") do
					lineNo += 1
					if string.find(line, params.pattern) then
						preview = string.sub(line, 1, 200)
						break
					end
				end
				table.insert(hits, { Path = fullPath(inst), line = lineNo, preview = preview })
				if #hits >= 100 then
					return
				end
			end
		end
		for _, c in inst:GetChildren() do
			walk(c)
			if #hits >= 100 then
				return
			end
		end
	end
	if root == game then
		for _, svc in game:GetChildren() do
			walk(svc)
		end
	else
		walk(root)
	end
	return hits
end

-- ---------- output ----------

handlers["get_output"] = function(params)
	local limit = math.clamp(tonumber(params.limit) or 100, 1, 500)
	local start = math.max(1, #outputBuffer - limit + 1)
	local out = {}
	for i = start, #outputBuffer do
		table.insert(out, outputBuffer[i])
	end
	return { lines = out, total = #outputBuffer }
end

handlers["clear_output"] = function(_params)
	table.clear(outputBuffer)
	return { cleared = true }
end

-- ---------- playtest ----------

local function pressKey(key: Enum.KeyCode)
	local vim = game:GetService("VirtualInputManager")
	pcall(function()
		vim:SendKeyEvent(true, key, false, game)
		task.wait(0.05)
		vim:SendKeyEvent(false, key, false, game)
	end)
end

handlers["play_solo"] = function(_params)
	if RunService:IsRunning() then
		return { alreadyRunning = true }
	end
	pressKey(Enum.KeyCode.F5)
	task.wait(1)
	return { started = true, running = RunService:IsRunning() }
end

handlers["run_game"] = function(_params)
	if RunService:IsRunning() then
		return { alreadyRunning = true }
	end
	local ok2, runErr: any = pcall(function()
		RunService:Run()
	end)
	if not ok2 then
		pressKey(Enum.KeyCode.F8)
		task.wait(0.5)
	end
	local note: string? = nil
	if not ok2 then
		note = "fallback F8: " .. tostring(runErr)
	end
	return { started = true, running = RunService:IsRunning(), note = note }
end

handlers["stop_playtest"] = function(_params)
	if not RunService:IsRunning() then
		return { alreadyStopped = true }
	end
	pcall(function()
		RunService:Stop()
	end)
	task.wait(0.5)
	if RunService:IsRunning() then
		-- Shift+F5 fallback
		local vim = game:GetService("VirtualInputManager")
		pcall(function()
			vim:SendKeyEvent(true, Enum.KeyCode.F5, true, game)
			task.wait(0.05)
			vim:SendKeyEvent(false, Enum.KeyCode.F5, true, game)
		end)
		task.wait(0.5)
	end
	return { stopped = not RunService:IsRunning() }
end

handlers["get_play_state"] = function(_params)
	return {
		isRunning = RunService:IsRunning(),
		isRunMode = RunService:IsRunMode(),
		isServer = RunService:IsServer(),
		isClient = RunService:IsClient(),
		isStudio = RunService:IsStudio(),
	}
end

-- ---------- GUI / toolbox / world ----------

handlers["create_gui"] = function(params)
	assert(params.name, "name required")
	local parentPath = params.parent or "StarterGui"
	local parent = resolvePath(parentPath) or error("Parent not found: " .. tostring(parentPath))
	ChangeHistoryService:TryBeginRecording("MCP create_gui")
	local gui = Instance.new("ScreenGui")
	gui.Name = params.name
	if params.properties then
		applyProperties(gui, params.properties)
	end
	gui.Parent = parent
	for _, childSpec in params.children or {} do
		buildInstance(childSpec, gui)
	end
	ChangeHistoryService:FinishRecording("MCP create_gui")
	return { Path = fullPath(gui) }
end

handlers["insert_asset"] = function(params)
	local assetId = tonumber(params.assetId) or error("assetId (number) required")
	local parentPath = params.parent or "Workspace"
	local parent = resolvePath(parentPath) or error("Parent not found: " .. tostring(parentPath))
	ChangeHistoryService:TryBeginRecording("MCP insert_asset")
	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		pcall(function()
			ChangeHistoryService:FinishRecording("MCP insert_asset")
		end)
		error(
			"InsertService:LoadAsset failed (asset may be private/off-sale or Toolbox access denied): "
				.. tostring(model)
		)
	end
	(model :: Model).Parent = parent
	ChangeHistoryService:FinishRecording("MCP insert_asset")
	local children = {}
	for _, c in (model :: Model):GetChildren() do
		table.insert(children, { Name = c.Name, ClassName = c.ClassName, Path = fullPath(c) })
	end
	return { Path = fullPath(model), Children = children }
end

handlers["save_place"] = function(_params)
	-- Best-effort: Studio has no single public SavePlace API across versions,
	-- so try known entry points and report what happened.
	local tried: { string } = {}
	local ok = pcall(function()
		table.insert(tried, "StudioService:SavePlace");
		(game:GetService("StudioService") :: any):SavePlace()
	end)
	if ok then
		return { saved = true, via = tried }
	end
	local ok2, err2 = pcall(function()
		table.insert(tried, "game:SavePlace()");
		(game :: any):SavePlace()
	end)
	if ok2 then
		return { saved = true, via = tried }
	end
	return {
		saved = false,
		tried = tried,
		error = tostring(err2),
		hint = "No scriptable save API in this Studio version — press Ctrl+S in Studio. (execute_luau remains available for everything else.)",
	}
end

handlers["get_camera"] = function(_params)
	local cam = workspace.CurrentCamera or error("No CurrentCamera")
	return {
		CFrame = encodeValue(cam.CFrame),
		Focus = encodeValue(cam.Focus),
		FieldOfView = cam.FieldOfView,
		CameraType = tostring(cam.CameraType),
		CameraSubject = cam.CameraSubject and fullPath(cam.CameraSubject) or nil,
	}
end

handlers["set_camera"] = function(params)
	local cam = workspace.CurrentCamera or error("No CurrentCamera")
	if params.position then
		local pos = decodeValue(params.position)
		local focus = params.focus and decodeValue(params.focus) or cam.Focus.Position
		if typeof(pos) == "Vector3" and typeof(focus) == "Vector3" then
			cam.CFrame = CFrame.lookAt(pos, focus)
		elseif typeof(pos) == "CFrame" then
			cam.CFrame = pos
		else
			error("position must be Vector3 or CFrame encoding")
		end
	end
	if params.focus and not params.position then
		local focus = decodeValue(params.focus)
		if typeof(focus) == "Vector3" then
			cam.Focus = CFrame.new(focus)
		elseif typeof(focus) == "CFrame" then
			cam.Focus = focus
		end
	end
	if params.fov then
		cam.FieldOfView = params.fov
	end
	return { CFrame = encodeValue(cam.CFrame), FieldOfView = cam.FieldOfView }
end

handlers["get_lighting"] = function(_params)
	local out = {}
	for _, p in
		{
			"ClockTime",
			"Brightness",
			"Ambient",
			"OutdoorAmbient",
			"FogEnd",
			"FogStart",
			"FogColor",
			"GeographicLatitude",
			"GlobalShadows",
			"Technology",
			"EnvironmentDiffuseScale",
			"EnvironmentSpecularScale",
		}
	do
		local ok, v = pcall(function()
			return (Lighting :: any)[p]
		end)
		if ok and v ~= nil then
			local ok2, enc = pcall(function()
				return encodeValue(v)
			end)
			if ok2 then
				out[p] = enc
			end
		end
	end
	return out
end

handlers["set_lighting"] = function(params)
	assert(type(params.properties) == "table", "properties required")
	ChangeHistoryService:TryBeginRecording("MCP set_lighting")
	applyProperties(Lighting, params.properties)
	ChangeHistoryService:FinishRecording("MCP set_lighting")
	return { updated = params.properties }
end

handlers["get_workspace_info"] = function(_params)
	local descendants = workspace:GetDescendants()
	local parts, scripts, models = 0, 0, 0
	for _, d in descendants do
		if d:IsA("BasePart") then
			parts += 1
		end
		if d:IsA("LuaSourceContainer") then
			scripts += 1
		end
		if d:IsA("Model") then
			models += 1
		end
	end
	return {
		name = game.Name,
		placeId = game.PlaceId,
		jobId = game.JobId,
		workspaceChildCount = #workspace:GetChildren(),
		descendantCount = #descendants,
		partCount = parts,
		scriptCount = scripts,
		modelCount = models,
		gravity = workspace.Gravity,
		streamingEnabled = workspace.StreamingEnabled,
	}
end

handlers["undo"] = function(_params)
	pcall(function()
		ChangeHistoryService:Undo()
	end)
	return { undone = true }
end

handlers["redo"] = function(_params)
	pcall(function()
		ChangeHistoryService:Redo()
	end)
	return { redone = true }
end

-- ============================== dispatch ==============================

local function dispatch(cmd: any): (boolean, any)
	local method = cmd.method
	local params = cmd.params or {}
	local fn = handlers[method]
	if not fn then
		return false, "Unknown method: " .. tostring(method)
	end
	local ok, result = pcall(fn, params)
	if ok then
		return true, result
	else
		return false, tostring(result)
	end
end

-- ============================== toolbar ==============================

local toolbar = plugin:CreateToolbar("MCP Bridge")
-- NOTE: we intentionally never set toggleBtn.Enabled=false:
-- a disabled PluginToolbarButton stops firing Click, which would brick the toggle.
local toggleBtn = toolbar:CreateButton("MCPBridgeToggle", "MCP Bridge: click to enable/disable AI-agent bridge", "")
toggleBtn.Click:Connect(function()
	enabled = not enabled
	if enabled then
		log("enabled.")
	else
		log("disabled (polling paused).")
	end
	if enabled then
		serverUrl = nil
	end
end)

-- ============================== main loop ==============================

log("v" .. VERSION .. " starting. Looking for roblox-mcp bridge on 127.0.0.1 ...")

local backoff = 2

task.spawn(function()
	while true do
		if not enabled then
			task.wait(1)
			continue
		end
		if not serverUrl then
			serverUrl = findServer()
			if serverUrl then
				log("Connected to bridge at " .. serverUrl)
				backoff = 2
				pushOutput("MCP bridge connected: " .. serverUrl)
			else
				task.wait(backoff)
				backoff = math.min(backoff + 1, 10)
				continue
			end
		end

		local ok, data = httpGet(serverUrl .. "/poll?timeoutMs=25000")
		if not ok then
			log("poll failed (" .. tostring(data) .. ") — rediscovering...")
			serverUrl = nil
			pushOutput("MCP poll failed: " .. tostring(data))
			task.wait(backoff)
			backoff = math.min(backoff * 1.5, 10)
			continue
		end
		backoff = 2
		local cmd = (data :: any).command
		if cmd == nil then
			continue -- timeout, re-poll immediately
		end
		local cmdId = cmd.id
		local method = cmd.method
		log("exec " .. tostring(method) .. " (" .. tostring(cmdId) .. ")")
		pushOutput("MCP exec: " .. tostring(method))
		local success, output = dispatch(cmd)
		if not success then
			pushOutput("MCP error [" .. tostring(method) .. "]: " .. tostring(output))
		end
		local resultOutput: any = nil
		local resultError: string? = nil
		if success then
			resultOutput = output
		else
			resultError = tostring(output)
		end
		local okPost, postErr = httpPost(serverUrl .. "/result", {
			id = cmdId,
			ok = success,
			output = resultOutput,
			error = resultError,
		})
		if not okPost then
			log("result post failed: " .. tostring(postErr))
			serverUrl = nil
		end
	end
end)

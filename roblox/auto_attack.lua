-- Auto Attack — toggle via bind, box ESP on the current target.
-- ponytail: this game has no Humanoids (players are voxel `MCBody` models), so we can't
-- just touch Health. "Attack" = replay of the last outgoing MCRemotes packet it observes
-- you send. Swing once manually with auto-attack OFF to teach it the packet, then toggle on.

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------

local CONFIG = {
	BIND = Enum.KeyCode.F, -- toggle
	RANGE = 40, -- studs
	ATTACK_INTERVAL = 0.45, -- seconds between replayed attacks
	INCLUDE_BOTS = true, -- `MCBody Bot####` models are valid targets
	BOX_COLOR = Color3.fromRGB(255, 60, 60),
	BOX_THICKNESS = 2,
}

--------------------------------------------------------------------
-- Compat
--------------------------------------------------------------------

local warn_ = warn
local hookmetamethod = hookmetamethod or _G.hookmetamethod
local getnamecallmethod = getnamecallmethod or _G.getnamecallmethod
local getrawmetatable = getrawmetatable or _G.getrawmetatable
local setreadonly = setreadonly or _G.setreadonly

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
	warn_("[AutoAttack] Needs to run as a client local script.")
	return
end

--------------------------------------------------------------------
-- Target selection
--------------------------------------------------------------------

local SELF_NAME = "MCBody" -- your own avatar; everything else prefixed MCBody is a target
-- movement / telemetry / platform noise: never treat these as attacks
local IGNORE = {
	Lead = true,
	NetDiag = true,
	Metric = true,
	PlayerList = true,
	ClientReady = true,
	LoadDiag = true,
	MoveReport = true, -- the client's movement packet (fires constantly while walking)
	Chunks = true,
	Heartbeat = true,
	Changelog = true,
	Social = true,
	Profanity = true,
}
local HEARTBEAT_REMOTES = IGNORE -- alias kept for readability below
-- names that smell like an attack; preferred over whatever else was seen
local ATTACK_HINTS = { "Projectile", "Ability", "Sword", "Attack", "Hit", "Swing", "Combat", "Damage" }

local function hintScore(name)
	for _, h in ipairs(ATTACK_HINTS) do
		if name:find(h) then
			return true
		end
	end
	return false
end

local function isTargetBody(m)
	if m.ClassName ~= "Model" then
		return false
	end
	if m.Name == SELF_NAME or m.Name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if not CONFIG.INCLUDE_BOTS and m.Name:find("Bot") then
		return false
	end
	return true
end

local function headOf(model)
	return model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

local camera = Workspace.CurrentCamera

local function findNearest()
	local camPos = camera.CFrame.Position
	local best, bestDist, bestPos = nil, CONFIG.RANGE, nil
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			local head = headOf(m)
			if head then
				local d = (head.Position - camPos).Magnitude
				if d < bestDist then
					best, bestDist, bestPos = m, d, head.Position
				end
			end
		end
	end
	return best, bestDist, bestPos
end

--------------------------------------------------------------------
-- Attack learning: watch outgoing MCRemotes calls, remember the last non-heartbeat one
--------------------------------------------------------------------

local lastAttack = nil -- { remote, method, args }
local seen = {} -- remoteName -> { count = n, args = {...}, method = m, remote = inst }
local enabled = false

local function shortVal(v)
	local t = typeof(v)
	if t == "Instance" then
		return (v.Name or "?")
	elseif t == "string" then
		return '"' .. v:sub(1, 24) .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		return "table"
	end
	return tostring(v):sub(1, 32)
end

local function describeArgs(args)
	local parts = {}
	for i = 1, math.min(#args, 4) do
		local v = args[i]
		if typeof(v) == "table" then
			local kv, n = {}, 0
			for k, val in pairs(v) do
				n = n + 1
				if n > 6 then
					kv[#kv + 1] = "..."
					break
				end
				kv[#kv + 1] = tostring(k) .. "=" .. shortVal(val)
			end
			parts[#parts + 1] = "{" .. table.concat(kv, ",") .. "}"
		else
			parts[#parts + 1] = shortVal(v)
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function record(name, method, remote, a)
	local rec = seen[name]
	if rec then
		rec.count = rec.count + 1
		rec.args = a
	else
		seen[name] = { count = 1, args = a, method = method, remote = remote }
	end
	-- prefer hinted names; otherwise keep the freshest non-heartbeat packet
	if hintScore(name) or not (lastAttack and hintScore(lastAttack.remote.Name)) then
		lastAttack = { remote = remote, method = method, args = a }
	end
end

-- platform/stock folders whose traffic is never a game attack
local PLATFORM_FOLDERS = {
	RobloxReplicatedStorage = true,
	RobloxServerStorage = true,
	CorePackages = true,
	Chat = true,
	DefaultChatSystemChatEvents = true,
	PlayerScripts = true,
}

local function isMcRemote(inst)
	if typeof(inst) ~= "Instance" then
		return false
	end
	if IGNORE[inst.Name] then
		return false
	end
	-- walk up a few levels; skip anything inside the stock/platform folders
	local node, depth = inst.Parent, 0
	local underMc = false
	while node and depth < 4 do
		if PLATFORM_FOLDERS[node.Name] then
			return false
		end
		if node.Name == "MCRemotes" then
			underMc = true
		end
		node = node.Parent
		depth = depth + 1
	end
	-- a game remote under MCRemotes, or any remote whose name smells like an attack
	return underMc or hintScore(inst.Name)
end

if hookmetamethod and getnamecallmethod then
	local ok = pcall(function()
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and isMcRemote(self) then
				pcall(record, self.Name, method, self, { ... })
			end
			return oldNamecall(self, ...)
		end)
	end)
	if not ok then
		warn_("[AutoAttack] Could not hook __namecall — trying __index only.")
	end
end

-- sigma-spy-style: also catch dot-calls (remote.FireServer(remote, ...)) and cached method refs
local INDEX_METHODS = { FireServer = true, InvokeServer = true }
local rawMtRef, rawOldIndex
if getrawmetatable and setreadonly then
	pcall(function()
		local mt = getrawmetatable(game)
		rawMtRef, rawOldIndex = mt, mt.__index
		setreadonly(mt, false)
		mt.__index = function(s, k)
			local orig = rawOldIndex(s, k)
			if INDEX_METHODS[k] and type(orig) == "function" and isMcRemote(s) then
				return function(self, ...)
					pcall(record, self.Name, k, self, { ... })
					return orig(self, ...)
				end
			end
			return orig
		end
	end)
end

--------------------------------------------------------------------
-- Retargeting: replayed packets carry the position/target you used when
-- swinging; swap them for the current target so the hit lands on the box.
--------------------------------------------------------------------

local function isBodyModel(v)
	return typeof(v) == "Instance" and v:IsA("Model") and v.Name:sub(1, 6) == "MCBody"
end

local function retargetValue(v, target, targetPos, depth)
	local t = typeof(v)
	if t == "Instance" then
		if isBodyModel(v) and v ~= target then
			return target
		end
		return v
	elseif t == "Vector3" then
		return targetPos
	elseif t == "CFrame" then
		return CFrame.new(targetPos) * (v - v.Position)
	elseif t == "table" and (depth or 0) < 1 then
		local out = {}
		for k, val in pairs(v) do
			out[k] = retargetValue(val, target, targetPos, (depth or 0) + 1)
		end
		return out
	end
	return v
end

local function retarget(args, target, targetPos)
	local out = {}
	for i = 1, #args do
		out[i] = retargetValue(args[i], target, targetPos, 0)
	end
	return out
end

--------------------------------------------------------------------
-- Drawing (box + label)
--------------------------------------------------------------------

local box, label
if Drawing then
	box = Drawing.new("Square")
	box.Thickness = CONFIG.BOX_THICKNESS
	box.Filled = false
	box.Transparency = 0.35
	box.Color = CONFIG.BOX_COLOR
	box.Visible = false

	label = Drawing.new("Text")
	label.Size = 14
	label.Center = true
	label.Outline = true
	label.Color = CONFIG.BOX_COLOR
	label.Visible = false
else
	warn_("[AutoAttack] No Drawing library — box indicator unavailable.")
end

local target

local function hideBox()
	if box then
		box.Visible = false
	end
	if label then
		label.Visible = false
	end
end

--------------------------------------------------------------------
-- Loops
--------------------------------------------------------------------

local lastScan = 0
RunService.RenderStepped:Connect(function()
	local now = tick()
	if now - lastScan > 0.2 then
		lastScan = now
		target = findNearest()
	end

	if not target or not target.Parent then
		hideBox()
		return
	end

	local head = headOf(target)
	if not head then
		hideBox()
		return
	end

	local pos, onScreen = camera:WorldToViewportPoint(head.Position)
	if not onScreen then
		hideBox()
		return
	end

	local dist = (camera.CFrame.Position - head.Position).Magnitude
	if box then
		local size = math.clamp(900 / dist, 24, 260)
		box.Size = Vector2.new(size, size * 1.35)
		box.Position = Vector2.new(pos.X - size / 2, pos.Y - size * 0.68)
		box.Visible = true
	end
	if label then
		label.Position = Vector2.new(pos.X, pos.Y - (math.clamp(900 / dist, 24, 260) * 0.78) - 14)
		label.Text = target.Name .. "  [" .. math.floor(dist) .. "]"
		label.Visible = true
	end
end)

local fireCount = 0
task.spawn(function()
	while true do
		task.wait(CONFIG.ATTACK_INTERVAL)
		if enabled then
			if not target or not target.Parent then
				target = findNearest()
			end
			if target and target.Parent and lastAttack and lastAttack.remote and lastAttack.remote.Parent then
				local t = target
				local head = headOf(t)
				local tPos = head and head.Position or camera.CFrame.Position
				local remote, method = lastAttack.remote, lastAttack.method
				local args = retarget(lastAttack.args, t, tPos)
				task.spawn(function()
					local ok, err = pcall(function()
						remote[method](remote, table.unpack(args))
					end)
					fireCount = fireCount + 1
					if not ok then
						warn_("[AutoAttack] attack fire failed: " .. tostring(err))
					elseif fireCount % 5 == 1 then
						print("[AutoAttack] fired " .. remote.Name .. "." .. method .. " " .. describeArgs(args) .. " at " .. t.Name)
					end
				end)
			end
		end
	end
end)

--------------------------------------------------------------------
-- Bind
--------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.BIND then
		enabled = not enabled
		if not enabled then
			hideBox()
		end
		local summary = {}
		for name, rec in pairs(seen) do
			summary[#summary + 1] = name .. " x" .. rec.count
		end
		table.sort(summary)
		print("[AutoAttack] " .. (enabled and "ON" or "OFF") .. "  (fired " .. fireCount .. " times)")
		print("[AutoAttack] seen remotes: " .. (#summary > 0 and table.concat(summary, ", ") or "none"))
		if lastAttack then
			print("[AutoAttack] attacking with: " .. lastAttack.remote.Name .. "." .. lastAttack.method .. " " .. describeArgs(lastAttack.args))
		else
			print("[AutoAttack] no packet learned — swing/place/use an item first")
		end
	end
end)

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

task.spawn(function()
	task.wait(1)
	local found = 0
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			found = found + 1
		end
	end
	print("[AutoAttack][check] target bodies in workspace: " .. found)
	print("[AutoAttack][check] hook=" .. tostring(hookmetamethod ~= nil) .. " drawing=" .. tostring(Drawing ~= nil))
	print("[AutoAttack] Ready — press " .. CONFIG.BIND.Name .. " to toggle. Swing once (auto-attack off) so it can learn the attack packet.")
end)

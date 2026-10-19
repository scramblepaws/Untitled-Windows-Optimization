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
local HEARTBEAT_REMOTES = {
	Lead = true, -- tick/lead pings, not attacks
	NetDiag = true,
	Metric = true,
	PlayerList = true,
	ClientReady = true,
	LoadDiag = true,
}
-- names that smell like an attack; preferred over whatever else was seen
local ATTACK_HINTS = { "Projectile", "Ability", "Sword", "Attack", "Hit", "Swing", "Combat", "Block", "Damage" }

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

local function describeArgs(args)
	local parts = {}
	for i = 1, math.min(#args, 4) do
		local v = args[i]
		local t = typeof(v)
		if t == "Instance" then
			parts[#parts + 1] = (v.Name or "?")
		elseif t == "table" then
			parts[#parts + 1] = "table"
		else
			parts[#parts + 1] = tostring(v):sub(1, 40)
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

if hookmetamethod and getnamecallmethod then
	local ok = pcall(function()
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
				local parent = self.Parent
				local inMc = parent and (parent.Name == "MCRemotes" or (parent.Parent and parent.Parent.Name == "MCRemotes"))
				if inMc and not HEARTBEAT_REMOTES[self.Name] then
					local a = { ... }
					local rec = seen[self.Name]
					if rec then
						rec.count = rec.count + 1
						rec.args = a
					else
						seen[self.Name] = { count = 1, args = a, method = method, remote = self }
					end
					-- prefer hinted names; otherwise keep the freshest non-heartbeat packet
					local hinted = hintScore(self.Name)
					if hinted or not (lastAttack and hintScore(lastAttack.remote.Name)) then
						lastAttack = { remote = self, method = method, args = a }
					end
				end
			end
			return oldNamecall(self, ...)
		end)
	end)
	if not ok then
		warn_("[AutoAttack] Could not hook __namecall — attack replay disabled, ESP still works.")
	end
else
	warn_("[AutoAttack] Executor lacks hookmetamethod/getnamecallmethod — attack replay disabled, ESP still works.")
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

task.spawn(function()
	while true do
		task.wait(CONFIG.ATTACK_INTERVAL)
		if enabled then
			if not target or not target.Parent then
				target = select(1, findNearest())
			end
			if target and target.Parent and lastAttack and lastAttack.remote and lastAttack.remote.Parent then
				task.spawn(function()
					local ok, err = pcall(function()
						lastAttack.remote[lastAttack.method](lastAttack.remote, table.unpack(lastAttack.args))
					end)
					if not ok then
						warn_("[AutoAttack] attack fire failed: " .. tostring(err))
					end
				end)
			end
		end
		-- re-learn: if user manually attacks while enabled, keep the freshest packet
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
		print("[AutoAttack] " .. (enabled and "ON" or "OFF"))
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

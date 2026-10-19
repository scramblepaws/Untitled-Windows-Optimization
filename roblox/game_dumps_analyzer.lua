-- Game Dumps Analyzer — UNC/SUNC-compliant game analysis dump script (client-side, LocalScript-style)
-- Run once per session. Records remote traffic, hierarchy, and player state continuously,
-- writes JSON dumps + append log into <executor workspace>/game dumps/<GameName>/.
-- ponytail: fixed caps (500 remote events, 200 state samples, depth/desc caps) — raise if stars align.
-- Records BOTH directions: client->server via __namecall hook, server->client via OnClientEvent listeners.

--------------------------------------------------------------------
-- SECTION 0: Compat layer (UNC/SUNC API surface)
--------------------------------------------------------------------

-- ponytail: resolve via _G and the executor env table, since UNC functions live in one or the other
local env = (getgenv and getgenv()) or _G

local function need(name)
	local f = _G[name] or env[name]
	if type(f) ~= "function" then
		warn("[GameDumps] UNC check fail: missing function `" .. name .. "`, feature degraded")
		return nil
	end
	return f
end

local writefile = need("writefile")
local isfile = need("isfile")
local isfolder = need("isfolder")
local makefolder = need("makefolder")
local appendfile = need("appendfile")
local hookmetamethod = need("hookmetamethod")
local getnamecallmethod = need("getnamecallmethod")
local getrawmetatable = need("getrawmetatable")
local setreadonly = need("setreadonly")
local gethui = need("gethui")
local identifyexecutor = need("identifyexecutor")
-- optional, never abort on these:
local getconnections = need("getconnections")

--------------------------------------------------------------------
-- SECTION 1: Identity & paths
--------------------------------------------------------------------

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer
if not player then
	warn("[GameDumps] Must run as client local script (no LocalPlayer). Aborting.")
	return
end

local function cleanName(s)
	return (tostring(s):gsub("[^%w%-_]", "_"):sub(1, 64))
end

local GAME_NAME = cleanName(game.Name) .. "_" .. game.PlaceId
local EXECUTOR = identifyexecutor and identifyexecutor() or "unknown"

local BASE_DIR = "game dumps/" .. GAME_NAME

local function ensureDir(dir)
	if makefolder and isfolder then
		if not isfolder(dir) then
			local ok = pcall(makefolder, dir)
			return ok and isfolder(dir)
		end
		return true
	end
	return false -- degraded: writer will prefix filenames instead
end

local HAVE_DIR = ensureDir("game dumps") and ensureDir(BASE_DIR)

local function filePath(name)
	if HAVE_DIR then
		return BASE_DIR .. "/" .. name
	end
	return cleanName(GAME_NAME) .. "_" .. name -- degraded flat mode
end

--------------------------------------------------------------------
-- SECTION 2: Remote Spy (hooks with polling fallback)
--------------------------------------------------------------------

local remotes = {} -- ring buffer
local REMOTE_CAP = 500
local remotesDropped = 0
local s2c = 0 -- server->client event count

local function instancePath(inst)
	local ok, path = pcall(function()
		local cur, parts = inst, {}
		while cur and cur ~= game and #parts < 8 do
			table.insert(parts, 1, cur.Name)
			cur = cur.Parent
		end
		return "game/" .. table.concat(parts, "/")
	end)
	return ok and path or (tostring(inst.Name))
end

local function serializeArg(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if depth > 2 then
		return "..."
	end
	if t == "Instance" then
		return instancePath(v)
	elseif t == "string" then
		return (v:sub(1, 200))
	elseif t == "number" or t == "boolean" then
		return v
	elseif t == "EnumItem" then
		return tostring(v)
	elseif t == "CFrame" or t == "Vector3" or t == "Color3" then
		return tostring(v)
	elseif t == "table" then
		local out = {}
		local n = 0
		for k, val in pairs(v) do
			n = n + 1
			if n > 10 then
				out["..."] = true
				break
			end
			out[tostring(k):sub(1, 50)] = serializeArg(val, depth + 1)
		end
		return out
	else
		return t
	end
end

local function logRemote(method, remote, args)
	if #remotes >= REMOTE_CAP then
		remotesDropped = remotesDropped + 1
		return
	end
	local a = {}
	for i, v in ipairs(args) do
		if i > 10 then
			table.insert(a, "...")
			break
		end
		table.insert(a, serializeArg(v))
	end
	table.insert(remotes, {
		t = os.time(),
		m = method,
		r = instancePath(remote),
		a = a,
	})
end

local spyMode = "none"
local sessionActive = true
local sessionStart = tick()

if hookmetamethod and getnamecallmethod then
	local ok = pcall(function()
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if sessionActive and (method == "FireServer" or method == "InvokeServer") then
				pcall(logRemote, method, self, args)
			end
			return oldNamecall(self, ...)
		end)
	end)
	if ok then
		spyMode = "hook"
	end
end

-- Sigma-Spy-style fallback: raw __index hook catches dot-call style (remote.FireServer(remote, ...)),
-- which __namecall never sees. Kept always-on alongside the namecall hook (guarded, only these two keys).
local INDEX_METHODS = { FireServer = true, InvokeServer = true }
local rawMtRef, rawOldIndex -- hoisted so Stop can restore the metatable
if getrawmetatable and setreadonly then
	local okIndex = pcall(function()
		local mt = getrawmetatable(game)
		rawMtRef = mt
		rawOldIndex = mt.__index
		setreadonly(mt, false)
		mt.__index = function(s, k)
			local orig = rawOldIndex(s, k) -- resolve first, outside the guard, keeps stats reads cheap
			if sessionActive and INDEX_METHODS[k] and type(orig) == "function" then
				return function(self, ...)
					pcall(logRemote, k .. "(idx)", self, args)
					return orig(self, ...)
				end
			end
			return orig
		end -- ponytail: readonly restored only on session stop; cheap on one metatable
	end)
	if okIndex and spyMode == "hook" then
		spyMode = "hook+index"
	elseif okIndex then
		spyMode = "index"
	end
end

if spyMode ~= "hook" then
	-- Fallback: enumerate remotes and their client connections (existence + listener count fidelity)
	local seen = {} -- remote path -> logged once
	task.spawn(function()
		while sessionActive do
			if getconnections then
				local ok = pcall(function()
					for _, desc in ipairs(game:GetDescendants()) do
						if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
							local conns = getconnections(desc.OnClientEvent) or {}
							local n = #conns
							local path = instancePath(desc)
							if n > 0 and not seen[path] then
								seen[path] = true
								logRemote("listeners:" .. n, desc, {})
							end
						end
					end
				end)
			end
			task.wait(5)
		end
	end)
	spyMode = getconnections and "connections" or "none"
end

-- Server->client recording: plain OnClientEvent listeners (always on, hook or not).
-- Rescans every 30s to catch remotes created after startup. Cap 100 instrumented remotes.
local instrumented = 0
local instrumentedSet = {} -- instance -> true
task.spawn(function()
	while sessionActive do
		pcall(function()
			for _, desc in ipairs(game:GetDescendants()) do
				if instrumented >= 100 then
					break
				end
				if (desc:IsA("RemoteEvent")) and not instrumentedSet[desc] then
					instrumentedSet[desc] = true
					instrumented = instrumented + 1
					desc.OnClientEvent:Connect(function(...)
						s2c = s2c + 1
						logRemote("OnClientEvent", desc, { ... })
					end)
				end
			end
		end)
		task.wait(30)
	end
end)

--------------------------------------------------------------------
-- SECTION 3: Hierarchy dump (lazy, built on Export)
--------------------------------------------------------------------

local HIER_DEPTH_CAP = 6
local HIER_DESC_CAP = 2000

local function dumpNode(inst, depth, count)
	count = count or { 0 }
	if depth > HIER_DEPTH_CAP or count[1] > HIER_DESC_CAP then
		return nil
	end
	count[1] = count[1] + 1
	local node = { c = inst.ClassName, n = inst.Name, p = instancePath(inst) }
	local attrs = {}
	for _, attr in ipairs(inst:GetAttributes()) do
		attrs[attr] = serializeArg(inst:GetAttribute(attr))
	end
	if next(attrs) then
		node.attrs = attrs
	end
	if inst:IsA("BasePart") or inst:IsA("Model") then
		local ok, pos = pcall(function()
			return tostring(inst:IsA("Model") and inst:GetPivot().Position or inst.Position)
		end)
		if ok then
			node.pos = pos
		end
	end
	local kids = {}
	for _, child in ipairs(inst:GetChildren()) do
		local d = dumpNode(child, depth + 1, count)
		if d then
			table.insert(kids, d)
		end
	end
	if #kids > 0 then
		node.kids = kids
	end
	return node
end

local function buildHierarchy()
	local out = {}
	for _, rootInst in ipairs({ ReplicatedStorage, ReplicatedFirst, workspace }) do
		table.insert(out, dumpNode(rootInst, 0))
	end
	return out
end

--------------------------------------------------------------------
-- SECTION 4: Player state dump (5s polling)
--------------------------------------------------------------------

local states = {}
local STATE_CAP = 200

local function snapshotPlayer()
	local s = { t = os.time() }
	s.hasChar = player.Character ~= nil
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local stats = {}
		for _, v in ipairs(ls:GetChildren()) do
			local val
			pcall(function()
				val = v.Value
			end)
			stats[v.Name] = serializeArg(val) or v.ClassName
		end
		s.stats = stats
	end
	local tools = {}
	local function scanT(w)
		for _, v in ipairs(w:GetChildren()) do
			if v:IsA("Tool") then
				table.insert(tools, v.Name)
			end
		end
	end
	if player:FindFirstChild("Backpack") then
		scanT(player.Backpack)
	end
	if player.Character then
		scanT(player.Character)
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			s.hum = { hp = hum.Health, mhp = hum.MaxHealth, ws = hum.WalkSpeed, jp = hum.JumpPower }
		end
	end
	if #tools > 0 then
		s.tools = tools
	end
	return s
end

task.spawn(function()
	while sessionActive do
		if #states >= STATE_CAP then
			table.remove(states, 1)
		end
		table.insert(states, snapshotPlayer())
		task.wait(5)
	end
end)

--------------------------------------------------------------------
-- SECTION 5: Writer / autosave (30s while dirty)
--------------------------------------------------------------------

local function jsonEncode(tbl)
	local ok, out = pcall(HttpService.JSONEncode, HttpService, tbl)
	if not ok then
		return nil
	end
	return out
end

local wroteSinceRejoin = 0
local function writeFileSafe(name, data)
	if not writefile then
		return false
	end
	local ok = pcall(writefile, filePath(name), data)
	if ok then
		wroteSinceRejoin = wroteSinceRejoin + 1
	end
	return ok
end

local function appendLog(line)
	if appendfile then
		pcall(appendfile, filePath("events.log"), os.date("%Y-%m-%d %H:%M:%S ") .. line .. "\n")
	end
end

local function buildMeta(extra)
	return {
		game = game.Name,
		placeId = game.PlaceId,
		jobId = game.JobId,
		executor = EXECUTOR,
		player = player.Name,
		spyMode = spyMode,
		dropped = remotesDropped,
		exports = wroteSinceRejoin,
		t = os.time(),
		__extra = extra,
	}
end

local lastRemoteCount, lastStateCount = 0, 0

task.spawn(function()
	while sessionActive do
		task.wait(30)
		if #remotes > lastRemoteCount or #states > lastStateCount then
			lastRemoteCount = #remotes
			lastStateCount = #states
			writeFileSafe("remotes.json", jsonEncode({ meta = buildMeta(nil), events = remotes }) or '{"meta":{},"events":[]}')
			writeFileSafe("playerstate.json", jsonEncode({ meta = buildMeta(nil), samples = states }) or '{"samples":[]}')
			appendLog("autosave: " .. tostring(#remotes) .. " remotes, " .. tostring(#states) .. " state samples")
		end
	end
end)

-- Console controls (replaces removed GUI): call from executor console.
env.GameDumpsExport = function()
	writeFileSafe("remotes.json", jsonEncode({ meta = buildMeta(nil), events = remotes }) or "{}")
	writeFileSafe("playerstate.json", jsonEncode({ meta = buildMeta(nil), samples = states }) or "{}")
	writeFileSafe("hierarchy.json", jsonEncode({ meta = buildMeta(nil), roots = buildHierarchy() }) or "{}")
	appendLog("manual export")
	print("[GameDumps] Exported to " .. filePath("remotes.json"))
end
env.GameDumpsStop = function()
	sessionActive = false
	if rawMtRef and rawOldIndex and setreadonly then
		pcall(function()
			rawMtRef.__index = rawOldIndex
			setreadonly(rawMtRef, true)
		end)
	end
	print("[GameDumps] Stopped. Now run env.GameDumpsExport() for a final flush.")
end
env.GameDumpsStatus = function()
	print(("[GameDumps] up %ds | spy %s | out %d | in %d | instr %d | writes %d | dropped %d"):format(
		tick() - sessionStart, spyMode, #remotes - s2c, s2c, instrumented, wroteSinceRejoin, remotesDropped))
end

print("[GameDumps] Running. Output: game dumps/" .. GAME_NAME .. " (dir=" .. tostring(HAVE_DIR) .. ", spy=" .. spyMode .. ")")
print("[GameDumps] Controls were removed with the GUI. Functions available: env.GameDumpsExport() / env.GameDumpsStop() / env.GameDumpsStatus()")

--------------------------------------------------------------------
-- SELF CHECK (runnable check: env adequacy + JSON round-trip)
--------------------------------------------------------------------

task.spawn(function()
	local checks = {
		writefile = writefile ~= nil,
		isfolder = isfolder ~= nil,
		makefolder = makefolder ~= nil,
		appendfile = appendfile ~= nil,
		hookmetamethod = hookmetamethod ~= nil,
		write_dir = HAVE_DIR,
	}
	local testTable = { a = 1, b = { "x", "y" } }
	local enc = jsonEncode(testTable)
	checks.json_encode = enc ~= nil
	if enc then
		local back = HttpService:JSONDecode(enc)
		checks.json_roundtrip = back.a == 1 and back.b[2] == "y"
	end
	local fails = {}
	for k, v in pairs(checks) do
		print("[GameDumps][check] " .. k .. " = " .. tostring(v))
		if not v then
			table.insert(fails, k)
		end
	end
	if #fails > 0 then
		warn("[GameDumps] SELF CHECK FAILED: " .. table.concat(fails, ", "))
	else
		print("[GameDumps] SELF CHECK passed — environment adequate.")
	end
end)

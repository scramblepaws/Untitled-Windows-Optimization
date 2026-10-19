-- Remote Probe — list/log every remote the game actually calls, ONCE per remote name.
-- Purpose: find the attack packet. Load it, play a match (attack someone), paste the output.
-- Logs the FIRST call of each remote (name + method + args); later calls only bump a counter.
-- Channels: hookfunction on each remote's FireServer/InvokeServer (catches cached refs) + __namecall.

--------------------------------------------------------------------
-- Compat
--------------------------------------------------------------------

local hookfunction = hookfunction or _G.hookfunction or replaceclosure or _G.replaceclosure
local hookmetamethod = hookmetamethod or _G.hookmetamethod
local getnamecallmethod = getnamecallmethod or _G.getnamecallmethod

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------
-- Arg formatting
--------------------------------------------------------------------

local function shortVal(v)
	local t = typeof(v)
	if t == "Instance" then
		return (v.Name or "?")
	elseif t == "string" then
		return '"' .. v:sub(1, 32) .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		return "table"
	end
	return tostring(v):sub(1, 32)
end

local function describe(args)
	local parts = {}
	for i = 1, math.min(#args, 5) do
		local v = args[i]
		if typeof(v) == "table" then
			local kv, n = {}, 0
			for k, val in pairs(v) do
				n = n + 1
				if n > 8 then
					kv[#kv + 1] = ".."
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

--------------------------------------------------------------------
-- Logging: first call per remote name only
--------------------------------------------------------------------

local counts = {}
local firsts = 0
local function log(name, method, args)
	local c = counts[name]
	if c then
		counts[name] = c + 1
		return
	end
	counts[name] = 1
	firsts = firsts + 1
	print(string.format("[probe] %s:%s %s", name, method, describe(args)))
end

--------------------------------------------------------------------
-- Deep dump of MoveReport (the input stream) to find the attack variant.
--------------------------------------------------------------------

local WATCH = "MoveReport"
local DUMP_CAP = 120

local dumped = 0
local ALWAYS_FIRST = 12 -- always dump the first N, then only inside a click window
local clickUntil = 0 -- dump every WATCH call while tick() < this
local CLICK_WINDOW = 0.7

local function deep(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "table" then
		if depth >= 4 then
			return "{..}"
		end
		local parts, n = {}, 0
		for k, val in pairs(v) do
			n = n + 1
			if n > 16 then
				parts[#parts + 1] = ".."
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. deep(val, depth + 1)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "Instance" then
		return v.Name
	elseif t == "Vector3" or t == "CFrame" then
		return tostring(v):sub(1, 48)
	elseif t == "string" then
		return '"' .. v:sub(1, 40) .. '"'
	end
	return tostring(v):sub(1, 40)
end

local function deepArgs(args)
	local parts = {}
	for i = 1, math.min(#args, 6) do
		parts[#parts + 1] = deep(args[i], 0)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- MoveReport batches input: { e=<code>, t=<tick>, f=<flags>, n=<inputs> }.
-- Always dump the first few to learn the shape, then every call within a click
-- window (so we can see exactly what an attack adds).
local function maybeDump(name, a)
	if name ~= WATCH or dumped >= DUMP_CAP then
		return
	end
	local inWindow = tick() < clickUntil
	if not inWindow and dumped >= ALWAYS_FIRST then
		return
	end
	dumped = dumped + 1
	print(string.format("[probe] %s#%d %s", name, dumped, deepArgs(a)))
end

--------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------

local PATH_MAX_DEPTH = 6

local remotes = {}
local function collect(node, depth)
	if depth > PATH_MAX_DEPTH then
		return
	end
	for _, c in ipairs(node:GetChildren()) do
		if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") or c:IsA("UnreliableRemoteEvent") then
			remotes[#remotes + 1] = c
		end
		pcall(collect, c, depth + 1)
	end
end
pcall(collect, ReplicatedStorage, 0)

local hookedCount = 0
local function wrapMethod(remote, method)
	local orig = remote[method]
	if type(orig) ~= "function" then
		return
	end
	local rname = remote.Name
	local replacement = function(self, ...)
		local a = { ... }
		maybeDump(rname, a)
		pcall(log, rname, method, a)
		return orig(self, ...)
	end
	local ok = pcall(hookfunction, orig, replacement)
	if ok then
		hookedCount = hookedCount + 1
	end
end

local moveUnderRs = false
for _, r in ipairs(remotes) do
	if r.Name == WATCH then
		moveUnderRs = true
	end
	pcall(wrapMethod, r, "FireServer")
	if r:IsA("RemoteFunction") then
		pcall(wrapMethod, r, "InvokeServer")
	end
end

if hookmetamethod and getnamecallmethod then
	pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
				local a = { ... }
				maybeDump(self.Name, a)
				pcall(log, self.Name, method, a)
			end
			return old(self, ...)
		end)
	end)
end

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

print(string.format("[probe] remotes found: %d (hooked %d) — hookfunction=%s namecall=%s",
	#remotes, hookedCount, tostring(hookfunction ~= nil), tostring(hookmetamethod ~= nil)))
if not moveUnderRs then
	print("[probe] note: " .. WATCH .. " wasn't under ReplicatedStorage — hooked via namecall instead")
end
print(string.format("[probe] Now fight: attack a player. Distinct %s shapes print as #N. Press F for summary.", WATCH))

local UserInputService = game:GetService("UserInputService")
local inputLogs = 0
UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		clickUntil = tick() + CLICK_WINDOW
		dumped = 0
		print("[probe] CLICK -> dumping " .. WATCH .. " for " .. CLICK_WINDOW .. "s")
	end
	if inputLogs < 20 then
		inputLogs = inputLogs + 1
		print(string.format("[probe] input %s processed=%s", input.UserInputType.Name, tostring(processed)))
	end
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		local rows = {}
		for name, c in pairs(counts) do
			rows[#rows + 1] = name .. " x" .. c
		end
		table.sort(rows)
		print("[probe] summary: " .. table.concat(rows, ", "))
	end
end)

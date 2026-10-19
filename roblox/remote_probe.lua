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
	local replacement = function(self, ...)
		pcall(log, remote.Name, method, { ... })
		return orig(self, ...)
	end
	local ok = pcall(hookfunction, orig, replacement)
	if ok then
		hookedCount = hookedCount + 1
	end
end

for _, r in ipairs(remotes) do
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
				pcall(log, self.Name, method, { ... })
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
print("[probe] Now attack someone. Paste every [probe] line. Press F to dump the running summary.")

game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
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

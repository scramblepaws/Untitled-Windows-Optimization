-- Loadstring loader for the Game Dumps Analyzer.
-- Usage (paste into your executor):
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/scramblepaws/Untitled-Windows-Optimization/master/roblox/game_dumps_analyzer.lua"))()
-- Or run this file, which does the same thing with error handling.

local url = "https://raw.githubusercontent.com/scramblepaws/Untitled-Windows-Optimization/master/roblox/game_dumps_analyzer.lua"

local src = game:HttpGet(url)
if not src or #src == 0 then
	warn("[GameDumps] Failed to download script from " .. url)
	return
end

local fn, err = loadstring(src)
if not fn then
	warn("[GameDumps] Loadstring error: " .. tostring(err))
	return
end

print("[GameDumps] Loaded analyzer, executing...")
fn()

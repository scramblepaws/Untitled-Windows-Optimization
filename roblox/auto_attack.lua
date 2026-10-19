-- Aim — rotate your own head (CFrame) to face the nearest other player, with a box on it.
-- ponytail: this game has no Humanoids and clicking fires no remote (probed), so hits are
-- resolved server-side from the pose you replicate. Aiming therefore = setting your head's
-- CFrame toward the target each frame. Same trick works for any part via AimPart(part, target).

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------

local CONFIG = {
	BIND = Enum.KeyCode.F, -- toggle aiming
	RANGE = 60, -- studs
	INCLUDE_BOTS = true, -- `MCBody Bot####` models are valid targets
	LOCAL_MODEL_NAME = "MCBody", -- your own avatar model (others are `MCBody <id>`)
	HEAD_RUN_PRIORITY = Enum.RenderPriority.Character.Value + 1, -- run after the game's character step so ours wins
	BOX_COLOR = Color3.fromRGB(255, 60, 60),
	BOX_THICKNESS = 2,
}

--------------------------------------------------------------------
-- Services
--------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
	warn("[Aim] Needs to run as a client local script.")
	return
end

--------------------------------------------------------------------
-- Finding your own model + head
--------------------------------------------------------------------

local function findHead(model)
	if not model then
		return nil
	end
	local named = model:FindFirstChild("Head")
	if named and named:IsA("BasePart") then
		return named
	end
	-- fall back to any part with "Head" in its name
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name:find("Head") then
			return p
		end
	end
	-- last resort: highest part (voxel heads sit on top)
	local best, bestY = nil, -math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Position.Y > bestY then
			best, bestY = p, p.Position.Y
		end
	end
	return best
end

local function localModel()
	return Workspace:FindFirstChild(CONFIG.LOCAL_MODEL_NAME)
end

--------------------------------------------------------------------
-- Target selection (other `MCBody*` models)
--------------------------------------------------------------------

local function isTargetBody(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("Model") then
		return false
	end
	if inst.Name == CONFIG.LOCAL_MODEL_NAME then
		return false
	end
	if inst.Name:sub(1, 6) ~= "MCBody" then
		return false
	end
	if not CONFIG.INCLUDE_BOTS and inst.Name:find("Bot") then
		return false
	end
	return true
end

local function findTarget()
	local model = localModel()
	local myHead = findHead(model)
	local myPos = myHead and myHead.Position or Vector3.zero
	local best, bestDist, bestHead
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			local h = findHead(m)
			if h and h.Parent then
				local d = (h.Position - myPos).Magnitude
				if d <= CONFIG.RANGE and d < (bestDist or math.huge) then
					best, bestDist, bestHead = m, d, h
				end
			end
		end
	end
	return best, bestDist, bestHead
end

--------------------------------------------------------------------
-- The aim function
--------------------------------------------------------------------

-- Rotate `part` (your head) so its front faces `targetHead`, keeping its position.
local function AimPart(part, targetHead)
	if not part or not part.Parent or not targetHead or not targetHead.Parent then
		return false
	end
	part.CFrame = CFrame.lookAt(part.Position, targetHead.Position)
	return true
end

-- Convenience: aim your head at a whole target model.
local function AimAt(target)
	return AimPart(findHead(localModel()), findHead(target))
end

-- exported for manual use
if getgenv then
	getgenv().Aim = { AimPart = AimPart, AimAt = AimAt, findTarget = findTarget, findHead = findHead }
end

--------------------------------------------------------------------
-- Box ESP
--------------------------------------------------------------------

local RENDER_NAME = "UntitledAim"
local box, label
do
	local ok = pcall(function()
		if not Drawing then
			error("no Drawing")
		end
		box = Drawing.new("Square")
		box.Thickness = CONFIG.BOX_THICKNESS
		box.Filled = false
		box.Color = CONFIG.BOX_COLOR
		box.Visible = false
		label = Drawing.new("Text")
		label.Size = 16
		label.Center = true
		label.Outline = true
		label.Color = CONFIG.BOX_COLOR
		label.Visible = false
	end)
	if not ok then
		warn("[Aim] Drawing API unavailable — aiming still works, no box.")
	end
end

--------------------------------------------------------------------
-- Per-frame loop
--------------------------------------------------------------------

local enabled = false
local target, targetHead, targetDist

local function step()
	local camera = Workspace.CurrentCamera
	target, targetDist, targetHead = findTarget()

	if enabled and targetHead then
		AimPart(findHead(localModel()), targetHead)
	end

	if not (box and label) then
		return
	end
	if not target or not targetHead or not camera then
		box.Visible = false
		label.Visible = false
		return
	end

	local pos, onScreen = camera:WorldToViewportPoint(targetHead.Position)
	if not onScreen then
		box.Visible = false
		label.Visible = false
		return
	end
	local dist = targetDist or 0
	local size = math.clamp(900 / math.max(dist, 1), 24, 260)
	box.Size = Vector2.new(size, size * 1.35)
	box.Position = Vector2.new(pos.X - size / 2, pos.Y - size * 0.68)
	box.Visible = true
	label.Position = Vector2.new(pos.X, pos.Y - size * 0.78 - 14)
	label.Text = target.Name .. "  [" .. math.floor(dist) .. "]"
	label.Visible = true
end

if RunService.BindToRenderStep then
	RunService:BindToRenderStep(RENDER_NAME, CONFIG.HEAD_RUN_PRIORITY, step)
else
	RunService.RenderStepped:Connect(step)
end

--------------------------------------------------------------------
-- Bind
--------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == CONFIG.BIND then
		enabled = not enabled
		print("[Aim] " .. (enabled and "ON" or "OFF")
			.. (target and (" — target " .. target.Name .. " @ " .. math.floor(targetDist or 0)) or " — no target in range"))
	end
end)

--------------------------------------------------------------------
-- SELF CHECK
--------------------------------------------------------------------

task.spawn(function()
	task.wait(1)
	-- core math check: the aim CFrame's LookVector must point from part to target
	local a, b = Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)
	local lv = CFrame.lookAt(a, b).LookVector
	assert((lv - (b - a).Unit).Magnitude < 1e-4, "[Aim] lookAt math broken")

	local model = localModel()
	local head = findHead(model)
	print("[Aim][check] own model: " .. (model and model.Name or "NOT FOUND")
		.. "  head: " .. (head and (head.Name .. " @" .. tostring(head.Position)) or "NOT FOUND"))
	local names = {}
	for _, m in ipairs(Workspace:GetChildren()) do
		if isTargetBody(m) then
			names[#names + 1] = m.Name
		end
	end
	print("[Aim][check] targets: " .. #names .. " (" .. table.concat(names, ", ") .. ")")
	print("[Aim] Ready — press " .. CONFIG.BIND.Name .. " to toggle head-aim.")
end)

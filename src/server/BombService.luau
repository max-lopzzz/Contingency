--[[
	The bomb objective: one bomb is revealed at a time, one survivor can work it,
	and progress is kept when the disarm is interrupted (hit, moved, or the key released).

	Bomb spots are BaseParts in Workspace.Map.BombSpots, ordered by their "Order"
	attribute (or name). Placeholder spots are generated if that folder is missing.
	Each spot exposes attributes for the client: Progress (0-1), WorkerId (UserId or 0).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local SurvivorService = require(script.Parent.SurvivorService)

local BombService = {
	AllDisarmed = Signal.new(),
}

local queue: { BasePart } = {}
local activeIndex = 0
local disarmSeconds = 0
local worker: Player? = nil
local workerStart: Vector3? = nil
local heartbeat: RBXScriptConnection? = nil

local function makePlaceholderSpots(): Folder
	warn("[BombService] Workspace.Map.BombSpots not found - generating placeholder bomb spots")
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local folder = Instance.new("Folder")
	folder.Name = "BombSpots"
	for i = 1, 7 do
		local angle = (i / 7) * math.pi * 2
		local part = Instance.new("Part")
		part.Name = "Bomb" .. i
		part.Size = Vector3.new(2, 2, 2)
		part.Anchored = true
		part.Position = Vector3.new(math.cos(angle) * 90, 1, math.sin(angle) * 90)
		part:SetAttribute("Order", i)
		part.Parent = folder
	end
	folder.Parent = map
	return folder
end

local function getSpots(): { BasePart }
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("BombSpots") or makePlaceholderSpots()
	local spots = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spots, child)
		end
	end
	table.sort(spots, function(a, b)
		local oa, ob = a:GetAttribute("Order"), b:GetAttribute("Order")
		if oa and ob and oa ~= ob then
			return oa < ob
		end
		return a.Name < b.Name
	end)
	return spots
end

-- Puts the bomb model on a spot once. The spot part stays as the invisible anchor
-- for the prompt and attributes; the model and its status light are the visuals.
local function dressSpot(spot: BasePart)
	if spot:FindFirstChild("BombModel") then
		return
	end
	local assets = ServerStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("FearGasBomb")
	if not (template and template:IsA("Model")) then
		return
	end

	local model = template:Clone()
	model.Name = "BombModel"
	local _, size = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * Config.Bombs.ModelSize / math.max(size.X, size.Y, size.Z))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local floorY = spot.Position.Y - spot.Size.Y / 2
	local offset = Vector3.new(spot.Position.X, floorY + boxSize.Y / 2, spot.Position.Z) - boxCFrame.Position
	model:PivotTo(model:GetPivot() + offset)

	local status = Instance.new("Part")
	status.Name = "StatusLight"
	status.Shape = Enum.PartType.Ball
	status.Size = Vector3.new(0.6, 0.6, 0.6)
	status.Material = Enum.Material.Neon
	status.Anchored = true
	status.CanCollide = false
	status.CastShadow = false
	status.Position = Vector3.new(spot.Position.X, floorY + boxSize.Y + 0.4, spot.Position.Z)
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 2
	light.Parent = status
	status.Parent = model

	model.Parent = spot
	spot.Transparency = 1
	spot.CanCollide = false
end

local function setLook(spot: BasePart, state: "Idle" | "Active" | "Disarmed")
	local color = Config.Bombs.StatusColors[state]
	local model = spot:FindFirstChild("BombModel")
	local status = model and model:FindFirstChild("StatusLight")
	if not status then
		-- No model: tint the spot itself like before.
		spot.Color = if state == "Idle" then Color3.fromRGB(60, 60, 60) else color
		spot.Material = if state == "Idle" then Enum.Material.Metal else Enum.Material.Neon
		return
	end
	status.Color = color
	status.Transparency = 0
	status:SetAttribute("Blink", state == "Active")
	local light = status:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
		light.Enabled = state ~= "Idle"
	end
end

local function resetSpot(spot: BasePart)
	dressSpot(spot)
	setLook(spot, "Idle")
	spot:SetAttribute("Progress", 0)
	spot:SetAttribute("WorkerId", 0)
	for _, name in { "ActiveHighlight", "DisarmPrompt" } do
		local child = spot:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

local function stopWorking()
	local bomb = queue[activeIndex]
	if bomb then
		bomb:SetAttribute("WorkerId", 0)
	end
	worker = nil
	workerStart = nil
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character.PrimaryPart
	return root and root.Position
end

local function tryStart(player: Player)
	local bomb = queue[activeIndex]
	if not bomb then
		return
	end
	if worker or not SurvivorService.IsAlive(player) then
		return
	end
	if SurvivorService.IsInvincible(player) and not Config.Bombs.AllowDisarmWhileInvincible then
		return
	end
	local position = rootPosition(player)
	if not position or (position - bomb.Position).Magnitude > Config.Bombs.InteractRange then
		return
	end
	worker = player
	workerStart = position
	bomb:SetAttribute("WorkerId", player.UserId)
end

local activate

local function finishBomb(bomb: BasePart)
	stopWorking()
	resetSpot(bomb)
	bomb:SetAttribute("Progress", 1)
	setLook(bomb, "Disarmed")
	Net.State:SetAttribute("BombsDisarmed", activeIndex)

	if activeIndex >= #queue then
		Net.State.ActiveBomb.Value = nil
		BombService.AllDisarmed:Fire()
	else
		activate(activeIndex + 1)
	end
end

function activate(index: number)
	activeIndex = index
	local bomb = queue[index]
	Net.State.ActiveBomb.Value = bomb
	setLook(bomb, "Active")

	local highlight = Instance.new("Highlight")
	highlight.Name = "ActiveHighlight"
	highlight.Adornee = bomb:FindFirstChild("BombModel") or bomb -- the spot part is invisible when dressed
	highlight.FillColor = Color3.fromRGB(255, 170, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = bomb

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DisarmPrompt"
	prompt.ActionText = "Hold to disarm"
	prompt.ObjectText = "Fear Gas Bomb"
	-- The key is held for the whole disarm: pressing starts it, releasing stops it (progress is kept).
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Bombs.InteractRange
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(tryStart)
	prompt.TriggerEnded:Connect(function(player)
		if worker == player then
			stopWorking()
		end
	end)
	prompt.Parent = bomb
end

local function blink(bomb: BasePart)
	local model = bomb:FindFirstChild("BombModel")
	local status = model and model:FindFirstChild("StatusLight")
	if not (status and status:GetAttribute("Blink")) then
		return
	end
	local on = math.floor(os.clock() / Config.Bombs.BlinkSeconds) % 2 == 0
	status.Transparency = if on then 0 else 0.7
	local light = status:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = on
	end
end

local function step(dt: number)
	local bomb = queue[activeIndex]
	if bomb then
		blink(bomb)
	end
	if not (bomb and worker) then
		return
	end

	local position = rootPosition(worker)
	local valid = position ~= nil
		and worker.Parent == Players
		and SurvivorService.IsAlive(worker)
		and (position - workerStart).Magnitude <= Config.Bombs.MoveCancelDistance
		and (position - bomb.Position).Magnitude <= Config.Bombs.InteractRange
	if not valid then
		stopWorking()
		return
	end

	local progress = math.min(1, bomb:GetAttribute("Progress") + dt / disarmSeconds)
	bomb:SetAttribute("Progress", progress)
	if progress >= 1 then
		finishBomb(bomb)
	end
end

function BombService.Start(survivorCount: number)
	BombService.Stop()

	local row = Config.Bombs.BySurvivors[math.clamp(survivorCount, 2, 5)]
	disarmSeconds = row.DisarmSeconds

	local spots = getSpots()
	if Config.Bombs.RandomOrder then
		local rng = Random.new()
		for i = #spots, 2, -1 do
			local j = rng:NextInteger(1, i)
			spots[i], spots[j] = spots[j], spots[i]
		end
	end

	for _, spot in spots do
		resetSpot(spot)
	end
	for i = 1, math.min(row.Count, #spots) do
		queue[i] = spots[i]
	end
	if #queue < row.Count then
		warn(`[BombService] Need {row.Count} bomb spots but the map only has {#spots}`)
	end

	Net.State:SetAttribute("BombsTotal", #queue)
	Net.State:SetAttribute("BombsDisarmed", 0)
	heartbeat = RunService.Heartbeat:Connect(step)
	activate(1)
end

function BombService.Stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	stopWorking()
	for _, bomb in queue do
		resetSpot(bomb)
	end
	table.clear(queue)
	activeIndex = 0
	Net.State.ActiveBomb.Value = nil
end

function BombService.Init()
	-- Getting hit interrupts the disarm; progress stays where it was.
	SurvivorService.Damaged:Connect(function(player)
		if player == worker then
			stopWorking()
		end
	end)
end

return BombService

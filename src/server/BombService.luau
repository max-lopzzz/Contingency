--[[
	The bomb objective: one bomb is revealed at a time, one survivor can work it,
	and progress is kept when the disarm is interrupted (hit, moved, cancelled).

	Bomb spots are BaseParts in Workspace.Map.BombSpots, ordered by their "Order"
	attribute (or name). Placeholder spots are generated if that folder is missing.
	Each spot exposes attributes for the client: Progress (0-1), WorkerId (UserId or 0).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local function resetSpot(spot: BasePart)
	spot.Color = Color3.fromRGB(60, 60, 60)
	spot.Material = Enum.Material.Metal
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
	if worker == player then
		stopWorking() -- pressing again cancels
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
	bomb.Color = Color3.fromRGB(70, 200, 90)
	bomb.Material = Enum.Material.Neon
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
	bomb.Color = Color3.fromRGB(255, 170, 0)
	bomb.Material = Enum.Material.Neon

	local highlight = Instance.new("Highlight")
	highlight.Name = "ActiveHighlight"
	highlight.FillColor = Color3.fromRGB(255, 170, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = bomb

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DisarmPrompt"
	prompt.ActionText = "Disarm"
	prompt.ObjectText = "Fear Gas Bomb"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Bombs.InteractRange
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(tryStart)
	prompt.Parent = bomb
end

local function step(dt: number)
	local bomb = queue[activeIndex]
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

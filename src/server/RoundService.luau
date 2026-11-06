--[[
	The match loop: Intermission -> Briefing -> Match -> Debrief -> repeat.

	Map points (all optional, placeholders are used when missing):
	  Workspace.LobbySpawn               BasePart
	  Workspace.Map.ScarecrowSpawn       BasePart
	  Workspace.Map.SurvivorSpawns       Folder of BaseParts
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SurvivorService = require(script.Parent.SurvivorService)
local BombService = require(script.Parent.BombService)
local CombatService = require(script.Parent.CombatService)
local Weapons = require(script.Parent.Weapons)

local RoundService = {}

local PLACEHOLDER_LOBBY = Vector3.new(0, 4, 200)
local PLACEHOLDER_SCARECROW = Vector3.new(0, 4, -150)
local PLACEHOLDER_SURVIVORS = Vector3.new(0, 4, 0)

local scarecrow: Player? = nil
local survivors: { Player } = {}
local result: string? = nil -- "Survivors" | "Scarecrow" once the match is decided

local function setPhase(phase: string, seconds: number?)
	Net.State:SetAttribute("Phase", phase)
	Net.State:SetAttribute("PhaseEndsAt", if seconds then workspace:GetServerTimeNow() + seconds else 0)
end

local function minPlayers(): number
	return if RunService:IsStudio() then Config.Debug.StudioMinPlayers else Config.Round.MinPlayers
end

local function spawnAt(player: Player, position: Vector3)
	player:LoadCharacter()
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(position))
	end
end

local function survivorSpawn(index: number): Vector3
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("SurvivorSpawns")
	local points = folder and folder:GetChildren() or {}
	if #points > 0 then
		return points[(index - 1) % #points + 1].Position + Vector3.new(0, 3, 0)
	end
	return PLACEHOLDER_SURVIVORS + Vector3.new((index - 3) * 5, 0, 0)
end

local function pointOr(parent: Instance?, name: string, fallback: Vector3): Vector3
	local part = parent and parent:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part.Position + Vector3.new(0, 3, 0) else fallback
end

local function sendToLobby(player: Player)
	SurvivorService.Clear(player)
	spawnAt(player, pointOr(workspace, "LobbySpawn", PLACEHOLDER_LOBBY))
end

local function spawnScarecrow(player: Player)
	spawnAt(player, pointOr(workspace:FindFirstChild("Map"), "ScarecrowSpawn", PLACEHOLDER_SCARECROW))
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.Scarecrow.WalkSpeed
	end
	Weapons.EquipKit(player.Character, "Scarecrow")
end

local function setFrozen(frozen: boolean)
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character.PrimaryPart
		if root then
			root.Anchored = frozen
		end
	end
end

local function checkSurvivorsLeft()
	if result then
		return
	end
	for _, player in survivors do
		if player.Parent == Players and SurvivorService.IsAlive(player) then
			return
		end
	end
	-- Nobody left standing (downed players can't revive each other).
	result = "Scarecrow"
end

local function intermission()
	setPhase("Intermission")
	for _, player in Players:GetPlayers() do
		sendToLobby(player)
	end

	while true do
		local missing = minPlayers() - #Players:GetPlayers()
		Net.State:SetAttribute("PlayersNeeded", math.max(0, missing))
		if missing <= 0 then
			setPhase("Intermission", Config.Round.IntermissionSeconds)
			local endsAt = Net.State:GetAttribute("PhaseEndsAt")
			while workspace:GetServerTimeNow() < endsAt and #Players:GetPlayers() >= minPlayers() do
				task.wait(0.25)
			end
			if #Players:GetPlayers() >= minPlayers() then
				return
			end
			setPhase("Intermission")
		end
		task.wait(1)
	end
end

local function assignRoles()
	local pool = Players:GetPlayers()
	local rng = Random.new()
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	-- OPEN (Q7): Scarecrow is picked at random. A solo Studio tester plays survivor.
	scarecrow = if #pool >= 2 then table.remove(pool, 1) else nil
	survivors = {}
	for i = 1, math.min(#pool, Config.Round.MaxSurvivors) do
		survivors[i] = pool[i]
	end

	if scarecrow then
		scarecrow:SetAttribute("Role", "Scarecrow")
		scarecrow:SetAttribute("Kit", "Scarecrow")
		spawnScarecrow(scarecrow)
	end
	for i, player in survivors do
		spawnAt(player, survivorSpawn(i))
		SurvivorService.Setup(player, Config.SurvivorKit)
		Weapons.EquipKit(player.Character, Config.SurvivorKit)
	end
end

local function briefing()
	local roster = {}
	for _, player in survivors do
		table.insert(roster, { Name = player.DisplayName, Kit = player:GetAttribute("Kit") })
	end
	Net.Remotes.MissionBriefing:FireAllClients({
		Killer = "Scarecrow",
		KillerPlayer = scarecrow and scarecrow.DisplayName or "-",
		Survivors = roster,
	})
	setPhase("Briefing", Config.Round.BriefingSeconds)
	setFrozen(true)
	task.wait(Config.Round.BriefingSeconds)
	setFrozen(false)
end

local function match()
	result = nil
	setPhase("Match", Config.Round.MatchSeconds)
	BombService.Start(#survivors)

	local endsAt = Net.State:GetAttribute("PhaseEndsAt")
	while not result do
		if workspace:GetServerTimeNow() >= endsAt then
			result = "Scarecrow" -- the bombs went off
		elseif scarecrow and scarecrow.Parent ~= Players then
			result = "Survivors" -- the Scarecrow left
		else
			checkSurvivorsLeft()
		end
		task.wait(0.1)
	end
	BombService.Stop()
	CombatService.Reset()
end

local function debrief()
	setPhase("Debrief", Config.Round.DebriefSeconds)
	Net.Remotes.MissionDebrief:FireAllClients(result)
	task.wait(Config.Round.DebriefSeconds)
	scarecrow = nil
	survivors = {}
end

function RoundService.Init()
	Players.CharacterAutoLoads = false

	BombService.AllDisarmed:Connect(function()
		result = result or "Survivors"
	end)
	SurvivorService.ConditionChanged:Connect(checkSurvivorsLeft)

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				-- Survivors are benched by SurvivorService; everyone else respawns where they belong.
				task.wait(2)
				if player.Parent ~= Players or player.Character ~= character then
					return
				end
				if player:GetAttribute("Role") == "Scarecrow" then
					spawnScarecrow(player)
				elseif not player:GetAttribute("Role") then
					sendToLobby(player)
				end
			end)
		end)
		-- Late joiners wait in the lobby until the next round.
		if not player.Character then
			sendToLobby(player)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function RoundService.Run()
	while true do
		intermission()
		assignRoles()
		briefing()
		match()
		debrief()
	end
end

return RoundService

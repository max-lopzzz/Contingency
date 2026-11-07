--[[
	Survivor health, downed state, revives and benching.

	State lives in Player attributes so clients can read it directly:
	  Role            "Survivor" | "Scarecrow" | nil (lobby)
	  Kit             e.g. "Damian"
	  HP, MaxHP
	  Condition       "Alive" | "Downed" | "Benched"
	  HasBeenDowned   true after the first down; the next 0 HP benches them
	  InvincibleUntil workspace:GetServerTimeNow() timestamp
	  Stamina         0..Config.Sprint.MaxStamina
	  Sprinting       true while running (the client asks with Remotes.Sprint; the server decides)

	Survivors never use Humanoid.Health; Scarecrow damage goes through Damage().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)

local SurvivorService = {
	Damaged = Signal.new(), -- (player, amount)
	ConditionChanged = Signal.new(), -- (player, condition)
}

local function now()
	return workspace:GetServerTimeNow()
end

local rooted: { [Player]: true } = {}

-- Sprint state per survivor; Stamina/Sprinting attributes mirror it for the HUD.
type Run = { Held: boolean, Stamina: number, LastRun: number, Exhausted: boolean }
local runs: { [Player]: Run } = {}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function setDownedTag(player: Player, visible: boolean)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild("DownedTag")
	if not visible then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = "DownedTag"
	tag.Size = UDim2.fromOffset(120, 30)
	tag.StudsOffset = Vector3.new(0, 2.5, 0)
	tag.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0.3
	label.Text = "DOWNED"
	label.Parent = tag
	tag.Parent = head
end

-- Walk speed follows from condition, sprinting and any root (e.g. caught in Panic Rush).
function SurvivorService.RefreshMovement(player: Player)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	local canMove = player:GetAttribute("Condition") == "Alive" and not rooted[player]
	local speed = if player:GetAttribute("Sprinting") then Config.Sprint.Speed else Config.Survivor.WalkSpeed
	humanoid.WalkSpeed = if canMove then speed else 0
	humanoid.JumpPower = if canMove then StarterPlayer.CharacterJumpPower else 0
	humanoid.JumpHeight = if canMove then StarterPlayer.CharacterJumpHeight else 0
end

-- Drains stamina while running, refills it after a pause. Running out locks sprint until the
-- bar is back to MinToStart, so it can't be feathered at zero.
local function updateSprint(dt: number)
	local sprint = Config.Sprint
	local clock = os.clock()
	for player, run in runs do
		local running = run.Held
			and not run.Exhausted
			and run.Stamina > 0
			and player:GetAttribute("Condition") == "Alive"
			and not rooted[player]
		if running then
			run.Stamina = math.max(0, run.Stamina - sprint.DrainPerSecond * dt)
			run.LastRun = clock
			if run.Stamina <= 0 then
				run.Exhausted = true
			end
		elseif clock - run.LastRun >= sprint.RegenDelay then
			run.Stamina = math.min(sprint.MaxStamina, run.Stamina + sprint.RegenPerSecond * dt)
		end
		if run.Exhausted and run.Stamina >= sprint.MinToStart then
			run.Exhausted = false
		end

		-- Only publish visible changes so the attribute isn't replicated every frame.
		local shown = math.floor(run.Stamina + 0.5)
		if player:GetAttribute("Stamina") ~= shown then
			player:SetAttribute("Stamina", shown)
		end
		local sprinting = running and run.Stamina > 0
		if player:GetAttribute("Sprinting") ~= sprinting then
			player:SetAttribute("Sprinting", sprinting)
			SurvivorService.RefreshMovement(player)
		end
	end
end

function SurvivorService.SetRooted(player: Player, isRooted: boolean)
	rooted[player] = if isRooted then true else nil
	SurvivorService.RefreshMovement(player)
end

local function setCondition(player: Player, condition: string)
	player:SetAttribute("Condition", condition)
	SurvivorService.RefreshMovement(player)
	SurvivorService.ConditionChanged:Fire(player, condition)
end

function SurvivorService.IsSurvivor(player: Player): boolean
	return player:GetAttribute("Role") == "Survivor"
end

function SurvivorService.IsAlive(player: Player): boolean
	return SurvivorService.IsSurvivor(player) and player:GetAttribute("Condition") == "Alive"
end

function SurvivorService.IsInvincible(player: Player): boolean
	return (player:GetAttribute("InvincibleUntil") or 0) > now()
end

-- Damian's heal can't target anyone who has already been downed once.
function SurvivorService.CanBeHealed(player: Player): boolean
	return SurvivorService.IsAlive(player) and not player:GetAttribute("HasBeenDowned")
end

function SurvivorService.Setup(player: Player, kitName: string)
	local kit = Config.Kits[kitName]
	player:SetAttribute("Role", "Survivor")
	player:SetAttribute("Kit", kitName)
	player:SetAttribute("MaxHP", kit.MaxHP)
	player:SetAttribute("HP", kit.MaxHP)
	player:SetAttribute("HasBeenDowned", false)
	player:SetAttribute("InvincibleUntil", 0)
	player:SetAttribute("Condition", "Alive")
	runs[player] = { Held = false, Stamina = Config.Sprint.MaxStamina, LastRun = 0, Exhausted = false }
	player:SetAttribute("Stamina", Config.Sprint.MaxStamina)
	player:SetAttribute("Sprinting", false)
	SurvivorService.RefreshMovement(player)

	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.Died:Connect(function()
			-- Falling out of the map etc. counts as being taken out for good.
			if SurvivorService.IsSurvivor(player) and player:GetAttribute("Condition") ~= "Benched" then
				SurvivorService.Bench(player)
			end
		end)
	end
end

function SurvivorService.Damage(player: Player, amount: number)
	if not SurvivorService.IsAlive(player) or SurvivorService.IsInvincible(player) then
		return
	end

	local hp = math.max(0, player:GetAttribute("HP") - amount)
	player:SetAttribute("HP", hp)
	SurvivorService.Damaged:Fire(player, amount)

	if hp > 0 then
		return
	end
	if player:GetAttribute("HasBeenDowned") then
		SurvivorService.Bench(player)
	else
		SurvivorService.Down(player)
	end
end

function SurvivorService.Down(player: Player)
	player:SetAttribute("HasBeenDowned", true)
	setDownedTag(player, true)
	setCondition(player, "Downed")
end

function SurvivorService.Revive(reviver: Player, target: Player): boolean
	if not SurvivorService.IsAlive(reviver) or target == reviver then
		return false
	end
	if not SurvivorService.IsSurvivor(target) or target:GetAttribute("Condition") ~= "Downed" then
		return false
	end
	local a = reviver.Character and reviver.Character.PrimaryPart
	local b = target.Character and target.Character.PrimaryPart
	if not (a and b) or (a.Position - b.Position).Magnitude > Config.Survivor.ReviveRange then
		return false
	end

	target:SetAttribute("HP", Config.Survivor.ReviveHP)
	target:SetAttribute("InvincibleUntil", now() + Config.Survivor.ReviveInvincibleSeconds)
	setDownedTag(target, false)
	setCondition(target, "Alive")
	return true
end

function SurvivorService.Heal(player: Player, amount: number): boolean
	if not SurvivorService.CanBeHealed(player) then
		return false
	end
	local hp, maxHP = player:GetAttribute("HP"), player:GetAttribute("MaxHP")
	if hp >= maxHP then
		return false
	end
	player:SetAttribute("HP", math.min(maxHP, hp + amount))
	return true
end

-- Taken out for the rest of the match; the client switches to spectating.
function SurvivorService.Bench(player: Player)
	player:SetAttribute("HP", 0)
	setCondition(player, "Benched")
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
end

-- Wipes every round attribute (role, HP, cooldowns, status effects).
function SurvivorService.Clear(player: Player)
	rooted[player] = nil
	runs[player] = nil
	for name in player:GetAttributes() do
		player:SetAttribute(name, nil)
	end
end

function SurvivorService.Init()
	Players.PlayerRemoving:Connect(function(player)
		rooted[player] = nil
		runs[player] = nil
	end)

	Net.Remotes.Sprint.OnServerEvent:Connect(function(player, held)
		local run = runs[player]
		if run then
			run.Held = held == true
		end
	end)
	RunService.Heartbeat:Connect(updateSprint)

	Net.Remotes.RequestRevive.OnServerEvent:Connect(function(player, target)
		if typeof(target) == "Instance" and target:IsA("Player") and target.Parent == Players then
			SurvivorService.Revive(player, target)
		end
	end)

	if RunService:IsStudio() then
		Net.Remotes.DebugDamage.OnServerEvent:Connect(function(player)
			SurvivorService.Damage(player, Config.Debug.SelfDamageAmount)
		end)
	end
end

return SurvivorService

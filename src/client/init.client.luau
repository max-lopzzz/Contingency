local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Batcomputer = require(script.Batcomputer)
require(script.Abilities)
require(script.Hallucination)
require(script.Lobby)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local state = Net.State

-- HUD ---------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "Hud"
hud.ResetOnSpawn = false
hud.Parent = player:WaitForChild("PlayerGui")

local function label(props): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	for key, value in props do
		l[key] = value
	end
	l.Parent = hud
	return l
end

local timerLabel = label({ Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(400, 44), TextSize = 36 })
local bombLabel = label({ Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(400, 24), TextSize = 20 })
local statusLabel = label({ Position = UDim2.new(0.5, 0, 1, -140), Size = UDim2.fromOffset(600, 30), TextSize = 24 })
local hpLabel = label({ Position = UDim2.new(0, 110, 1, -60), Size = UDim2.fromOffset(200, 30), TextSize = 24 })

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 0, 84)
barBack.Size = UDim2.fromOffset(260, 10)
barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
barBack.BorderSizePixel = 0
barBack.Parent = hud
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local beep = Instance.new("Sound")
beep.SoundId = "rbxasset://sounds/electronicpingshort.wav"
beep.Volume = 1
beep.Parent = SoundService
local lastBeep = -1

-- Helpers -----------------------------------------------------------------

local function secondsLeft(): number
	local endsAt = state:GetAttribute("PhaseEndsAt") or 0
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

local function rootOf(p: Player): BasePart?
	return p.Character and p.Character.PrimaryPart
end

local function nearestDownedTeammate(): Player?
	local myRoot = rootOf(player)
	if not myRoot then
		return nil
	end
	local best, bestDistance = nil, Config.Survivor.ReviveRange
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if other ~= player and root and other:GetAttribute("Condition") == "Downed" then
			local distance = (root.Position - myRoot.Position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function spectateTarget(): Humanoid?
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Role") == "Survivor" and other:GetAttribute("Condition") ~= "Benched" then
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return humanoid
			end
		end
	end
	return nil
end

-- Per-frame HUD update ----------------------------------------------------

RunService.RenderStepped:Connect(function()
	local phase = state:GetAttribute("Phase")
	local left = secondsLeft()
	local isSurvivor = player:GetAttribute("Role") == "Survivor"
	local condition = player:GetAttribute("Condition")

	-- Timer
	timerLabel.TextColor3 = Color3.new(1, 1, 1)
	if phase == "Intermission" then
		local needed = state:GetAttribute("PlayersNeeded") or 0
		timerLabel.Text = if needed > 0
			then `Waiting for {needed} more player{if needed == 1 then "" else "s"}`
			else `Next mission in {math.ceil(left)}`
	elseif phase == "Match" then
		local whole = math.ceil(left)
		timerLabel.Text = string.format("%d:%02d", whole // 60, whole % 60)
		if whole <= Config.Round.FinalCountdownSeconds then
			timerLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
			if whole ~= lastBeep and whole > 0 then
				lastBeep = whole
				beep:Play()
			end
		end
	else
		timerLabel.Text = ""
	end

	-- Bombs
	local bomb = state.ActiveBomb.Value
	if phase == "Match" then
		bombLabel.Text = `Bombs disarmed {state:GetAttribute("BombsDisarmed") or 0}/{state:GetAttribute("BombsTotal") or 0}`
		barBack.Visible = bomb ~= nil
		if bomb then
			barFill.Size = UDim2.fromScale(bomb:GetAttribute("Progress") or 0, 1)
		end
	else
		bombLabel.Text = ""
		barBack.Visible = false
	end

	-- Scarecrow can't use the disarm prompt (local-only change).
	local prompt = bomb and bomb:FindFirstChild("DisarmPrompt")
	if prompt then
		prompt.Enabled = isSurvivor and condition == "Alive"
	end

	-- Own status
	-- (MaxHP is only set once the survivor has spawned with a character.)
	hpLabel.Text = if isSurvivor and condition ~= "Benched" and player:GetAttribute("MaxHP")
		then `HP {math.ceil(player:GetAttribute("HP") or 0)}/{player:GetAttribute("MaxHP")}`
		else ""
	local status = ""
	if isSurvivor and phase == "Match" then
		if condition == "Downed" then
			status = "DOWNED - a teammate can revive you"
		elseif condition == "Benched" then
			status = "BENCHED - spectating"
		elseif (player:GetAttribute("InvincibleUntil") or 0) > workspace:GetServerTimeNow() then
			status = "Invincible"
		elseif bomb and bomb:GetAttribute("WorkerId") == player.UserId then
			status = "Disarming... move to cancel"
		else
			local downed = nearestDownedTeammate()
			if downed then
				status = `Press R to revive {downed.DisplayName}`
			end
		end
	end
	statusLabel.Text = status

	-- Spectate while benched
	if condition == "Benched" and phase == "Match" then
		local target = spectateTarget()
		if target and camera.CameraSubject ~= target then
			camera.CameraSubject = target
		end
	end
end)

-- Input -------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R and player:GetAttribute("Condition") == "Alive" then
		local downed = nearestDownedTeammate()
		if downed then
			Net.Remotes.RequestRevive:FireServer(downed)
		end
	elseif input.KeyCode == Config.Debug.SelfDamageKey and RunService:IsStudio() then
		Net.Remotes.DebugDamage:FireServer()
	end
end)

-- Batcomputer screens -----------------------------------------------------

Net.Remotes.MissionBriefing.OnClientEvent:Connect(Batcomputer.ShowBriefing)
Net.Remotes.MissionDebrief.OnClientEvent:Connect(Batcomputer.ShowDebrief)

state:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = state:GetAttribute("Phase")
	lastBeep = -1
	if phase == "Match" or phase == "Intermission" then
		Batcomputer.Hide()
	end
end)

player.CharacterAdded:Connect(function(character)
	camera.CameraSubject = character:WaitForChild("Humanoid")
end)

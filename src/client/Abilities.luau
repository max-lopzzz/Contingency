--[[
	Ability input and the cooldown bar for whichever kit the local player has.
	The server validates everything; this only picks the aim and draws cooldowns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local DISPLAY_NAMES = {
	SickleSlash = "Sickle Slash",
	FearGas = "Fear Gas",
	Hallucination = "Hallucination",
	PanicRush = "Panic Rush",
	Parry = "Parry",
	Heal = "Heal",
}

local gui = Instance.new("ScreenGui")
gui.Name = "Abilities"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -20)
bar.Size = UDim2.fromOffset(0, 70)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local stunLabel = Instance.new("TextLabel")
stunLabel.AnchorPoint = Vector2.new(0.5, 1)
stunLabel.Position = UDim2.new(0.5, 0, 1, -100)
stunLabel.Size = UDim2.fromOffset(300, 30)
stunLabel.BackgroundTransparency = 1
stunLabel.Font = Enum.Font.GothamBold
stunLabel.TextSize = 26
stunLabel.TextColor3 = Color3.fromRGB(255, 240, 120)
stunLabel.TextStrokeTransparency = 0.4
stunLabel.Text = ""
stunLabel.Parent = gui

local tiles = {} -- ability -> { Frame, Cooldown TextLabel }

local function keyName(key: EnumItem): string
	if key == Enum.UserInputType.MouseButton1 then
		return "LMB"
	end
	return key.Name
end

local function buildBar()
	for _, tile in tiles do
		tile.Frame:Destroy()
	end
	table.clear(tiles)

	local kit = Config.Kits[player:GetAttribute("Kit")]
	if not kit or not kit.Abilities then
		return
	end
	for i, ability in kit.Abilities do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = i
		frame.Size = UDim2.fromOffset(110, 70)
		frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		frame.BackgroundTransparency = 0.2
		frame.BorderSizePixel = 0
		Instance.new("UICorner").Parent = frame

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0, 22)
		name.Position = UDim2.fromOffset(0, 26)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 14
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Text = DISPLAY_NAMES[ability] or ability
		name.Parent = frame

		local key = Instance.new("TextLabel")
		key.Size = UDim2.new(1, 0, 0, 22)
		key.Position = UDim2.fromOffset(0, 4)
		key.BackgroundTransparency = 1
		key.Font = Enum.Font.GothamBlack
		key.TextSize = 16
		key.TextColor3 = Color3.fromRGB(255, 200, 80)
		key.Text = keyName(kit[ability].Key)
		key.Parent = frame

		local cooldown = Instance.new("TextLabel")
		cooldown.Size = UDim2.fromScale(1, 1)
		cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
		cooldown.BackgroundTransparency = 0.35
		cooldown.Font = Enum.Font.GothamBlack
		cooldown.TextSize = 24
		cooldown.TextColor3 = Color3.new(1, 1, 1)
		cooldown.Visible = false
		Instance.new("UICorner").Parent = cooldown
		cooldown.Parent = frame

		frame.Parent = bar
		tiles[ability] = { Frame = frame, Cooldown = cooldown }
	end
end

-- Aim -----------------------------------------------------------------------

local function aimDirection(): Vector3
	return camera.CFrame.LookVector
end

local function aimPoint(range: number): Vector3
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then
		return hit.Position
	end
	local root = player.Character and player.Character.PrimaryPart
	local origin = if root then root.Position else camera.CFrame.Position
	return origin + aimDirection() * range
end

local function healTarget(range: number): Player?
	local myRoot = player.Character and player.Character.PrimaryPart
	if not myRoot then
		return nil
	end
	local best, bestDistance = nil, range
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character.PrimaryPart
		local hurt = (other:GetAttribute("HP") or 0) < (other:GetAttribute("MaxHP") or 0)
		if
			other ~= player
			and root
			and hurt
			and other:GetAttribute("Condition") == "Alive"
			and not other:GetAttribute("HasBeenDowned")
		then
			local distance = (root.Position - myRoot.Position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function aimFor(ability: string, def): any
	if ability == "Hallucination" then
		return aimPoint(def.ThrowRange)
	elseif ability == "Heal" then
		return healTarget(def.Range)
	end
	return aimDirection()
end

-- Input ---------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or Net.State:GetAttribute("Phase") ~= "Match" then
		return
	end
	local kit = Config.Kits[player:GetAttribute("Kit")]
	if not kit or not kit.Abilities then
		return
	end
	for _, ability in kit.Abilities do
		local def = kit[ability]
		if input.KeyCode == def.Key or input.UserInputType == def.Key then
			local aim = aimFor(ability, def)
			if ability ~= "Heal" or aim then
				Net.Remotes.UseAbility:FireServer(ability, aim)
			end
			return
		end
	end
end)

RunService.RenderStepped:Connect(function()
	local inMatch = Net.State:GetAttribute("Phase") == "Match"
	bar.Visible = inMatch and player:GetAttribute("Condition") ~= "Benched"
	local serverNow = workspace:GetServerTimeNow()
	for ability, tile in tiles do
		local left = (player:GetAttribute("Ready_" .. ability) or 0) - serverNow
		tile.Cooldown.Visible = left > 0
		tile.Cooldown.Text = if left > 0 then tostring(math.ceil(left)) else ""
	end
	local stunned = (player:GetAttribute("StunnedUntil") or 0) - serverNow
	stunLabel.Text = if inMatch and stunned > 0 then "PARRIED - STUNNED" else ""
end)

player:GetAttributeChangedSignal("Kit"):Connect(buildBar)
buildBar()

return {}

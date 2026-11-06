--[[
	Full-screen Batcomputer report shown at the start (mission briefing)
	and end (Mission Completed / Mission Lost) of every round.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local GREEN = Color3.fromRGB(80, 255, 140)
local RED = Color3.fromRGB(255, 80, 80)

local Batcomputer = {}

local gui = Instance.new("ScreenGui")
gui.Name = "Batcomputer"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(5, 10, 8)
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local body = Instance.new("TextLabel")
body.AnchorPoint = Vector2.new(0.5, 0.5)
body.Position = UDim2.fromScale(0.5, 0.5)
body.Size = UDim2.fromScale(0.7, 0.7)
body.BackgroundTransparency = 1
body.Font = Enum.Font.Code
body.TextSize = 26
body.TextColor3 = GREEN
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Center
body.TextWrapped = true
body.Parent = backdrop

local typing = 0

local function show(text: string, color: Color3)
	typing += 1
	local token = typing
	gui.Enabled = true
	backdrop.BackgroundTransparency = 1
	TweenService:Create(backdrop, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
	body.TextColor3 = color
	body.Text = text
	body.MaxVisibleGraphemes = 0
	task.delay(0.6, function()
		local length = utf8.len(text) or #text
		for i = 1, length do
			if typing ~= token then
				return
			end
			body.MaxVisibleGraphemes = i
			task.wait(0.015)
		end
		body.MaxVisibleGraphemes = -1
	end)
end

function Batcomputer.ShowBriefing(data)
	local lines = {
		"BATCOMPUTER // MISSION REPORT",
		"",
		`MISSION: STOP {string.upper(data.Killer)}'S FEAR GAS BOMBS`,
		`THREAT: {string.upper(data.Killer)} [{data.KillerPlayer}]`,
		"",
		"SELECTED OPERATIVES:",
	}
	for _, survivor in data.Survivors do
		table.insert(lines, `  > {survivor.Name} - {string.upper(survivor.Kit)}`)
	end
	show(table.concat(lines, "\n"), GREEN)
end

function Batcomputer.ShowDebrief(winner: string)
	local won = winner == "Survivors"
	local lines = {
		"BATCOMPUTER // MISSION REPORT",
		"",
		if won then "MISSION COMPLETED" else "MISSION LOST",
		"",
		if won then "ALL FEAR GAS BOMBS DISARMED." else "GOTHAM HAS FALLEN TO FEAR.",
	}
	show(table.concat(lines, "\n"), if won then GREEN else RED)
end

function Batcomputer.Hide()
	typing += 1
	local tween = TweenService:Create(backdrop, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	tween:Play()
	body.Text = ""
	tween.Completed:Once(function()
		if body.Text == "" then
			gui.Enabled = false
		end
	end)
end

return Batcomputer

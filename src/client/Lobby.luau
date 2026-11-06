--[[
	Lobby screens, in the Batcomputer style:
	  Killer vote       bottom panel during Intermission; everyone votes for the next killer (and its map)
	  Character select  full screen during Select; survivors pick, everyone else sees who is choosing
	Votes and picks are Player attributes set by the server (server/SelectionService.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local state = Net.State

local GREEN = Color3.fromRGB(80, 255, 140)
local DIM = Color3.fromRGB(110, 130, 120)
local PANEL = Color3.fromRGB(5, 12, 9)
local CARD = Color3.fromRGB(14, 24, 19)

local gui = Instance.new("ScreenGui")
gui.Name = "Lobby"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className: string, props, parent: Instance?)
	local object = Instance.new(className)
	for key, value in props do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function text(props, parent: Instance)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextColor3 = GREEN,
		TextScaled = true,
		TextWrapped = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("TextLabel", defaults, parent)
end

local function stroke(parent: Instance): UIStroke
	return make("UIStroke", { Color = DIM, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

-- One selectable card: colour stripe, two lines of text, a status line and a lock overlay.
type Card = { Button: TextButton, Title: TextLabel, Sub: TextLabel, Status: TextLabel, Stroke: UIStroke, Lock: TextLabel }
local function card(parent: Instance, entry, order: number, onClick: () -> ()): Card
	local button = make("TextButton", {
		Name = entry.Kit,
		LayoutOrder = order,
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
	}, parent)
	make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = entry.Color, BorderSizePixel = 0 }, button)
	local title = text({ Position = UDim2.new(0, 8, 0, 14), Size = UDim2.new(1, -16, 0.32, 0), Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1) }, button)
	local sub = text({ Position = UDim2.new(0, 8, 0.45, 0), Size = UDim2.new(1, -16, 0.18, 0), TextColor3 = DIM }, button)
	local status = text({ Position = UDim2.new(0, 8, 0.72, 0), Size = UDim2.new(1, -16, 0.18, 0) }, button)
	local lock = text({
		Position = UDim2.new(0, 0, 0.55, 0),
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Text = "COMING SOON",
		TextColor3 = DIM,
		ZIndex = 2,
		Visible = false,
	}, button)
	make("UIPadding", { PaddingLeft = UDim.new(0.1, 0), PaddingRight = UDim.new(0.1, 0), PaddingTop = UDim.new(0.25, 0), PaddingBottom = UDim.new(0.25, 0) }, lock)
	button.Activated:Connect(onClick)
	return { Button = button, Title = title, Sub = sub, Status = status, Stroke = stroke(button), Lock = lock }
end

-- Unplayable cards keep their name but hide everything else behind "COMING SOON".
local function setLocked(c: Card, locked: boolean)
	c.Lock.Visible = locked
	c.Sub.Visible = not locked
	c.Status.Visible = not locked
	c.Button.AutoButtonColor = not locked
end

local function highlight(c: Card, on: boolean)
	c.Stroke.Color = if on then GREEN else DIM
	c.Stroke.Thickness = if on then 3 else 1
end

-- Killer vote panel ------------------------------------------------------------

local votePanel = make("Frame", {
	Name = "KillerVote",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(1, -32, 0, 200), -- capped at 640 wide below, so it also fits phones
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UISizeConstraint", { MaxSize = Vector2.new(640, 200) }, votePanel)
make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12) }, votePanel)
stroke(votePanel)
text({ Size = UDim2.new(1, 0, 0, 24), Text = "BATCOMPUTER // VOTE FOR THE NEXT THREAT" }, votePanel)
local voteRow = make("Frame", { Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1 }, votePanel)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, voteRow)

local voteCards: { [string]: Card } = {}
local killerCount = #Config.Roster.Killers
for i, entry in Config.Roster.Killers do
	local c = card(voteRow, entry, i, function()
		if Config.IsPlayable(entry.Kit) then
			Net.Remotes.VoteKiller:FireServer(entry.Kit)
		end
	end)
	c.Button.Size = UDim2.new(1 / killerCount, -10 * (killerCount - 1) / killerCount, 1, 0)
	c.Title.Text = string.upper(entry.Name)
	c.Sub.Text = `Map: {entry.Map}`
	voteCards[entry.Kit] = c
end

local function refreshVote()
	local counts = {}
	for _, other in Players:GetPlayers() do
		local vote = other:GetAttribute("KillerVote")
		if vote then
			counts[vote] = (counts[vote] or 0) + 1
		end
	end
	local mine = player:GetAttribute("KillerVote")
	for kit, c in voteCards do
		local playable = Config.IsPlayable(kit)
		local n = counts[kit] or 0
		setLocked(c, not playable)
		c.Status.Text = if kit == mine then `YOUR VOTE · {n}` else `{n} vote{if n == 1 then "" else "s"}`
		highlight(c, kit == mine)
	end
end

-- Character select screen ------------------------------------------------------

local selectScreen = make("Frame", {
	Name = "CharacterSelect",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
}, gui)
make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 16) }, selectScreen)
local selectTitle = text({ Size = UDim2.new(1, 0, 0, 36), Text = "BATCOMPUTER // CHOOSE YOUR OPERATIVE" }, selectScreen)
local selectInfo = text({ Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 24), TextColor3 = DIM }, selectScreen)
local grid = make("ScrollingFrame", {
	Position = UDim2.new(0, 0, 0, 80),
	Size = UDim2.new(1, 0, 1, -80),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, selectScreen)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(170, 200),
	CellPadding = UDim2.fromOffset(12, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, grid)

local pickCards: { [string]: Card } = {}
for i, entry in Config.Roster.Survivors do
	local c = card(grid, entry, i, function()
		if player:GetAttribute("Role") == "Survivor" and Config.IsPlayable(entry.Kit) then
			Net.Remotes.PickSurvivor:FireServer(entry.Kit)
		end
	end)
	c.Title.Text = string.upper(entry.Alias)
	c.Sub.Text = entry.Name
	pickCards[entry.Kit] = c
end

local function killerName(): string
	local kit = state:GetAttribute("Killer")
	for _, entry in Config.Roster.Killers do
		if entry.Kit == kit then
			return entry.Name
		end
	end
	return kit or "?"
end

local function refreshSelect()
	local takenBy = {}
	for _, other in Players:GetPlayers() do
		local pick = other:GetAttribute("Role") == "Survivor" and other:GetAttribute("Pick")
		if pick then
			takenBy[pick] = other
		end
	end
	local role = player:GetAttribute("Role")
	local mine = player:GetAttribute("Pick")
	local left = math.ceil(math.max(0, (state:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()))
	selectTitle.Text = if role == "Survivor"
		then "BATCOMPUTER // CHOOSE YOUR OPERATIVE"
		else "BATCOMPUTER // OPERATIVES ASSEMBLING"
	selectInfo.Text = if role == "Survivor"
		then `Threat: {string.upper(killerName())} · {left}s · no pick = random operative`
		elseif role then `You are {string.upper(killerName())}. Survivors are choosing · {left}s`
		else `Survivors are choosing their operatives · {left}s`

	for kit, c in pickCards do
		local owner = takenBy[kit]
		setLocked(c, not Config.IsPlayable(kit))
		c.Status.Text = if owner == player then "SELECTED"
			elseif owner then `Taken: {owner.DisplayName}`
			else "Available"
		c.Status.TextColor3 = if owner and owner ~= player then DIM else GREEN
		highlight(c, kit == mine)
	end
end

-- Visibility -----------------------------------------------------------------

task.spawn(function()
	while true do
		local phase = state:GetAttribute("Phase")
		votePanel.Visible = phase == "Intermission"
		selectScreen.Visible = phase == "Select"
		if votePanel.Visible then
			refreshVote()
		end
		if selectScreen.Visible then
			refreshSelect()
		end
		task.wait(0.2)
	end
end)

return {}

--[[
	Local-only Hallucination effects for the victim:
	  - distorted colours, blur and a wobbling field of view
	  - fake teammates wandering nearby (purely visual)
	  - fake Scarecrows, positioned by the server (they can really hit you)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Kit = Config.Kits.Scarecrow.Hallucination

local colour = Instance.new("ColorCorrectionEffect")
colour.Enabled = false
colour.Saturation = -0.4
colour.Contrast = 0.3
colour.TintColor = Color3.fromRGB(200, 170, 255)
colour.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Enabled = false
blur.Size = 0
blur.Parent = Lighting

local baseFov = camera.FieldOfView
local active = false
local fakeTeammates = {} -- { Model, Target }
local fakeScarecrows = {} -- marker -> Model

-- Static, non-colliding copy of a character to use as an illusion.
local function illusionOf(character: Model?): Model
	local model
	if character then
		local wasArchivable = character.Archivable
		character.Archivable = true
		model = character:Clone()
		character.Archivable = wasArchivable
	end
	if not model then
		model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "HumanoidRootPart"
		body.Size = Vector3.new(2, 5, 1)
		body.Color = Color3.fromRGB(40, 30, 20)
		body.Parent = model
		model.PrimaryPart = body
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BaseScript") or item:IsA("BillboardGui") or item:IsA("Highlight") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		elseif item:IsA("Humanoid") then
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	model.Name = "Illusion"
	model.Parent = workspace
	return model
end

local function findCharacter(role: string, exclude: Player?): Model?
	local candidates = {}
	for _, other in Players:GetPlayers() do
		if other ~= exclude and other:GetAttribute("Role") == role and other.Character then
			table.insert(candidates, other.Character)
		end
	end
	return candidates[math.random(1, math.max(1, #candidates))]
end

local function randomPointNear(origin: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	return origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius * (0.5 + math.random() * 0.5))
end

local function start()
	active = true
	colour.Enabled = true
	blur.Enabled = true
	baseFov = camera.FieldOfView
	local root = player.Character and player.Character.PrimaryPart
	if not root then
		return
	end
	for _ = 1, Kit.FakeTeammates do
		local model = illusionOf(findCharacter("Survivor", player) or player.Character)
		model:PivotTo(CFrame.new(randomPointNear(root.Position, 20)))
		table.insert(fakeTeammates, { Model = model, Target = randomPointNear(root.Position, 25) })
	end
end

local function stop()
	active = false
	colour.Enabled = false
	blur.Enabled = false
	camera.FieldOfView = baseFov
	for _, fake in fakeTeammates do
		fake.Model:Destroy()
	end
	table.clear(fakeTeammates)
end

local function addFakeScarecrow(marker: Instance)
	if marker:GetAttribute("VictimId") ~= player.UserId then
		return
	end
	local model = illusionOf(findCharacter("Scarecrow"))
	model:PivotTo(CFrame.new(marker:GetAttribute("Position")))
	fakeScarecrows[marker] = model
end

Net.Hallucinations.ChildAdded:Connect(addFakeScarecrow)
Net.Hallucinations.ChildRemoved:Connect(function(marker)
	local model = fakeScarecrows[marker]
	if model then
		model:Destroy()
		fakeScarecrows[marker] = nil
	end
end)
for _, marker in Net.Hallucinations:GetChildren() do
	addFakeScarecrow(marker)
end

RunService.RenderStepped:Connect(function(dt)
	local hallucinating = (player:GetAttribute("HallucinatingUntil") or 0) > workspace:GetServerTimeNow()
		and player:GetAttribute("Condition") == "Alive"
	if hallucinating and not active then
		start()
	elseif not hallucinating and active then
		stop()
	end

	local root = player.Character and player.Character.PrimaryPart

	if active then
		local t = os.clock()
		blur.Size = 6 + math.sin(t * 3) * 4
		camera.FieldOfView = baseFov + math.sin(t * 2.3) * 8
		for _, fake in fakeTeammates do
			local pivot = fake.Model:GetPivot()
			local offset = fake.Target - pivot.Position
			if offset.Magnitude < 1 and root then
				fake.Target = randomPointNear(root.Position, 25)
			else
				local step = offset.Unit * math.min(offset.Magnitude, 12 * dt)
				fake.Model:PivotTo(CFrame.lookAt(pivot.Position + step, fake.Target))
			end
		end
	end

	-- Fake Scarecrows glide toward the server position and face the victim.
	for marker, model in fakeScarecrows do
		local target = marker:GetAttribute("Position")
		local current = model:GetPivot().Position
		local position = current:Lerp(target, math.min(1, dt * 10))
		local lookAt = if root then Vector3.new(root.Position.X, position.Y, root.Position.Z) else position + Vector3.zAxis
		if (lookAt - position).Magnitude > 0.1 then
			model:PivotTo(CFrame.lookAt(position, lookAt))
		end
	end
end)

return {}

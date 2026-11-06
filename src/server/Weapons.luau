--[[
	Weapon models held by characters (visual only; hits are resolved by the kits).

	Templates live in ServerStorage.Assets.Weapons.<Name> (Creator Store models saved in
	the place, scripts removed). Config.Weapons says which part is the handle and how it
	sits in the hand / on the back. A missing template just means no weapon is shown.

	The weapon is a Model named "Weapon" in the character, every part welded to the
	handle, and the handle held by a Weld named "WeaponMount":
	  Hand  RightHand (R15) or Right Arm (R6), at RightGripAttachment
	  Back  UpperTorso (R15) or Torso (R6), at BodyBackAttachment
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Weapons = {}

local MOUNT_POINTS = {
	Hand = { Parts = { "RightHand", "Right Arm" }, Attachment = "RightGripAttachment", Grip = "Grip" },
	Back = { Parts = { "UpperTorso", "Torso" }, Attachment = "BodyBackAttachment", Grip = "BackGrip" },
}

local function template(name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weapons")
	return folder and folder:FindFirstChild(name)
end

-- Clone the template into a plain Model with everything welded to the handle.
local function build(name: string): (Model?, BasePart?)
	local def = Config.Weapons[name]
	local source = template(name)
	if not (def and source) then
		return nil, nil
	end

	local model = Instance.new("Model")
	model.Name = "Weapon"
	model:SetAttribute("WeaponName", name)
	local copy = source:Clone()
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	local handle = copy:FindFirstChild(def.Handle, true)
	if not (handle and handle:IsA("BasePart")) then
		warn(`[Weapons] {name}: handle part "{def.Handle}" not found`)
		return nil, nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.CastShadow = false
			if d ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
	-- Tools (at any depth) would get equipped by the engine, so only their contents are kept.
	for _, d in copy:GetDescendants() do
		if d:IsA("Tool") then
			for _, child in d:GetChildren() do
				child.Parent = d.Parent
			end
			d:Destroy()
		end
	end
	for _, child in copy:GetChildren() do
		child.Parent = model
	end
	copy:Destroy()
	if def.Scale and def.Scale ~= 1 then
		model:ScaleTo(def.Scale)
	end
	return model, handle
end

local function mountPart(character: Model, mount: string): (BasePart?, Attachment?)
	local point = MOUNT_POINTS[mount]
	for _, partName in point.Parts do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part, part:FindFirstChild(point.Attachment) :: Attachment?
		end
	end
	return nil, nil
end

-- Move an equipped weapon between hand and back.
function Weapons.SetMount(character: Model, mount: "Hand" | "Back")
	local model = character:FindFirstChild("Weapon")
	local weld = model and model:FindFirstChild("WeaponMount", true)
	local def = model and Config.Weapons[model:GetAttribute("WeaponName")]
	if not (weld and weld:IsA("Weld") and def) then
		return
	end
	local part, attachment = mountPart(character, mount)
	if not part then
		return
	end
	weld.Part0 = part
	weld.C0 = if attachment then attachment.CFrame else CFrame.identity
	-- Grips are written for the unscaled model, so their offset scales with it.
	local grip = def[MOUNT_POINTS[mount].Grip] or CFrame.identity
	weld.C1 = grip.Rotation + grip.Position * (def.Scale or 1)
	model:SetAttribute("Mount", mount)
end

-- Gives the character its weapon, replacing any old one.
function Weapons.Equip(character: Model?, name: string, mount: "Hand" | "Back")
	if not character then
		return
	end
	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	local model, handle = build(name)
	if not (model and handle) then
		return
	end
	local weld = Instance.new("Weld")
	weld.Name = "WeaponMount"
	weld.Part1 = handle
	weld.Parent = handle
	model:SetAttribute("RestMount", mount)
	model.Parent = character
	Weapons.SetMount(character, mount)
end

-- Equips whatever Config.Kits[kitName].Weapon says, if anything.
function Weapons.EquipKit(character: Model?, kitName: string?)
	local kit = kitName and Config.Kits[kitName]
	local weapon = kit and kit.Weapon
	if weapon then
		Weapons.Equip(character, weapon.Name, weapon.Rest)
	end
end

-- Briefly holds the weapon in hand (e.g. Damian drawing his katana to parry), then puts it back.
function Weapons.Draw(character: Model?, seconds: number)
	local model = character and character:FindFirstChild("Weapon")
	if not model then
		return
	end
	local rest = model:GetAttribute("RestMount")
	Weapons.SetMount(character :: Model, "Hand")
	local sound = model:FindFirstChild("Unsheath", true)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
	local token = (model:GetAttribute("DrawToken") or 0) + 1
	model:SetAttribute("DrawToken", token)
	task.delay(seconds, function()
		if model.Parent == character and model:GetAttribute("DrawToken") == token and rest then
			Weapons.SetMount(character :: Model, rest)
		end
	end)
end

return Weapons

--[[
	Kit outfits: turns a Config.Kits[kit].Outfit table into a HumanoidDescription, so a
	character can be loaded already dressed (Player:LoadCharacterWithHumanoidDescription).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Outfits = {}

local BODY_COLORS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }

-- The kit's outfit as a HumanoidDescription, or nil when the kit has none.
function Outfits.Describe(kitName: string?): HumanoidDescription?
	local kit = kitName and Config.Kits[kitName]
	local outfit = kit and kit.Outfit
	if not outfit then
		return nil
	end
	local description = Instance.new("HumanoidDescription")
	for field, value in outfit do
		if field == "SkinColor" then
			local color = Color3.fromHex(value)
			for _, part in BODY_COLORS do
				(description :: any)[part] = color
			end
		elseif type(value) == "table" then
			(description :: any)[field] = table.concat(value, ",")
		else
			(description :: any)[field] = value
		end
	end
	return description
end

return Outfits

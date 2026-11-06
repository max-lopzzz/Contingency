--[[
	Damian (survivor, support):
	  Parry  draws his katana for a short window; a Sickle Slash landing in it stuns
	         Scarecrow (resolved in Kits/Scarecrow). Missing it has no extra penalty.
	  Heal   instantly heals an adjacent ally. Never himself, never anyone already downed once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SurvivorService = require(script.Parent.Parent.SurvivorService)
local Fx = require(script.Parent.Parent.Fx)

local Kit = Config.Kits.Damian

local Damian = { Use = {} }

function Damian.Use.Parry(player: Player): boolean
	player:SetAttribute("ParryUntil", workspace:GetServerTimeNow() + Kit.Parry.Window)
	Fx.Flash(player.Character, Color3.new(1, 1, 1), Kit.Parry.Window)
	return true
end

function Damian.Use.Heal(player: Player, target: unknown): boolean
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == player or target.Parent ~= Players then
		return false
	end
	local a = player.Character and player.Character.PrimaryPart
	local b = target.Character and target.Character.PrimaryPart
	if not (a and b) or (a.Position - b.Position).Magnitude > Kit.Heal.Range then
		return false
	end
	if not SurvivorService.Heal(target, Kit.Heal.Amount) then
		return false
	end
	Fx.Flash(target.Character, Color3.fromRGB(90, 255, 120), 0.5)
	return true
end

return Damian

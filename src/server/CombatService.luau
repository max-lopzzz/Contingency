--[[
	Entry point for every ability. Checks phase, role, condition, stun and
	cooldown, then hands off to the player's kit in server/Kits.

	Cooldowns are Player attributes "Ready_<Ability>" holding the server time
	the ability is usable again, so the client HUD can draw them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SurvivorService = require(script.Parent.SurvivorService)

local CombatService = {}

local kits = {}

local function now()
	return workspace:GetServerTimeNow()
end

function CombatService.IsReady(player: Player, ability: string): boolean
	return (player:GetAttribute("Ready_" .. ability) or 0) <= now()
end

function CombatService.StartCooldown(player: Player, ability: string)
	local kit = Config.Kits[player:GetAttribute("Kit")]
	local def = kit and kit[ability]
	if def then
		player:SetAttribute("Ready_" .. ability, now() + def.Cooldown)
	end
end

-- Put every ability in a player's kit on full cooldown (Fear Gas).
function CombatService.StartAllCooldowns(player: Player)
	local kit = Config.Kits[player:GetAttribute("Kit")]
	for _, ability in (kit and kit.Abilities or {}) do
		CombatService.StartCooldown(player, ability)
	end
end

function CombatService.IsStunned(player: Player): boolean
	return (player:GetAttribute("StunnedUntil") or 0) > now()
end

local function onUseAbility(player: Player, ability: unknown, aim: unknown)
	if Net.State:GetAttribute("Phase") ~= "Match" or typeof(ability) ~= "string" then
		return
	end
	local kitName = player:GetAttribute("Kit")
	local kit = kits[kitName]
	local def = Config.Kits[kitName]
	if not (kit and def and table.find(def.Abilities, ability) and kit.Use[ability]) then
		return
	end
	if player:GetAttribute("Role") == "Survivor" and not SurvivorService.IsAlive(player) then
		return
	end
	if CombatService.IsStunned(player) or not CombatService.IsReady(player, ability) then
		return
	end
	if kit.CanAct and not kit.CanAct(player) then
		return
	end

	-- Kits return true when the ability actually went off (e.g. heal had a valid target).
	if kit.Use[ability](player, aim) then
		CombatService.StartCooldown(player, ability)
	end
end

-- Called when a match ends to clear lingering effects (hallucinations, lunges).
function CombatService.Reset()
	for _, kit in kits do
		if kit.Reset then
			kit.Reset()
		end
	end
end

function CombatService.Init()
	kits.Damian = require(script.Parent.Kits.Damian)
	kits.Scarecrow = require(script.Parent.Kits.Scarecrow)
	for _, kit in kits do
		if kit.Init then
			kit.Init()
		end
	end
	Net.Remotes.UseAbility.OnServerEvent:Connect(onUseAbility)
end

return CombatService

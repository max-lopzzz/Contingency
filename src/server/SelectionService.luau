--[[
	Killer vote (lobby, during Intermission) and survivor character select (Select phase).

	Player attributes, readable by every client for the screens:
	  KillerVote   killer kit this player voted for
	  Pick         survivor kit this player picked (unique per match while free ones remain)
	Both are cleared with the rest of the round attributes when players go back to the lobby.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local SelectionService = {}

local rng = Random.new()

local function inRoster(list, kit: any): boolean
	for _, entry in list do
		if entry.Kit == kit then
			return true
		end
	end
	return false
end

local function playable(list): { string }
	local kits = {}
	for _, entry in list do
		if Config.IsPlayable(entry.Kit) then
			table.insert(kits, entry.Kit)
		end
	end
	return kits
end

local function pickedBy(kit: string, except: Player?): Player?
	for _, other in Players:GetPlayers() do
		if other ~= except and other:GetAttribute("Role") == "Survivor" and other:GetAttribute("Pick") == kit then
			return other
		end
	end
	return nil
end

-- The most-voted playable killer; ties and no votes are settled at random.
function SelectionService.ChooseKiller(): string
	local counts = {}
	for _, player in Players:GetPlayers() do
		local vote = player:GetAttribute("KillerVote")
		if vote and Config.IsPlayable(vote) then
			counts[vote] = (counts[vote] or 0) + 1
		end
	end
	local best, top = {}, 0
	for kit, count in counts do
		if count > top then
			best, top = { kit }, count
		elseif count == top then
			table.insert(best, kit)
		end
	end
	if #best == 0 then
		best = playable(Config.Roster.Killers)
	end
	return best[rng:NextInteger(1, #best)]
end

function SelectionService.AllPicked(survivors: { Player }): boolean
	for _, player in survivors do
		if player.Parent == Players and not player:GetAttribute("Pick") then
			return false
		end
	end
	return true
end

-- Gives everyone who didn't pick a random free character. When every playable character is
-- taken (few kits exist yet), duplicates are allowed so nobody is left without one.
function SelectionService.FillPicks(survivors: { Player })
	for _, player in survivors do
		if not player:GetAttribute("Pick") then
			local options = {}
			for _, kit in playable(Config.Roster.Survivors) do
				if not pickedBy(kit) then
					table.insert(options, kit)
				end
			end
			if #options == 0 then
				options = playable(Config.Roster.Survivors)
			end
			player:SetAttribute("Pick", options[rng:NextInteger(1, #options)])
		end
	end
end

function SelectionService.Init()
	Net.Remotes.VoteKiller.OnServerEvent:Connect(function(player, kit)
		if Net.State:GetAttribute("Phase") == "Intermission" and inRoster(Config.Roster.Killers, kit) and Config.IsPlayable(kit) then
			player:SetAttribute("KillerVote", kit)
		end
	end)

	Net.Remotes.PickSurvivor.OnServerEvent:Connect(function(player, kit)
		if
			Net.State:GetAttribute("Phase") == "Select"
			and player:GetAttribute("Role") == "Survivor"
			and inRoster(Config.Roster.Survivors, kit)
			and Config.IsPlayable(kit)
			and not pickedBy(kit, player)
		then
			player:SetAttribute("Pick", kit)
		end
	end)
end

return SelectionService

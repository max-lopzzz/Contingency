--[[
	Shared networking objects. The server creates them; clients wait for them.

	Net.Remotes.<Name>  RemoteEvents
	Net.State           Folder whose attributes mirror the round state:
	                      Phase         "Intermission" | "Briefing" | "Match" | "Debrief"
	                      PhaseEndsAt   workspace:GetServerTimeNow() when the phase ends (0 = waiting)
	                      PlayersNeeded players still missing before intermission can count down
	                      BombsTotal, BombsDisarmed
	                    and an ObjectValue child "ActiveBomb" pointing at the bomb being worked on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"MissionBriefing", -- server -> client: { Killer, KillerPlayer, Survivors = { { Name, Kit } } }
	"MissionDebrief", -- server -> client: "Survivors" | "Scarecrow"
	"RequestRevive", -- client -> server: target Player
	"DebugDamage", -- client -> server (Studio only)
}

local Net = { Remotes = {} }

if RunService:IsServer() then
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	for _, name in REMOTE_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		Net.Remotes[name] = remote
	end
	remotes.Parent = ReplicatedStorage

	local state = Instance.new("Folder")
	state.Name = "GameState"
	local activeBomb = Instance.new("ObjectValue")
	activeBomb.Name = "ActiveBomb"
	activeBomb.Parent = state
	state.Parent = ReplicatedStorage
	Net.State = state
else
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in REMOTE_NAMES do
		Net.Remotes[name] = remotes:WaitForChild(name)
	end
	Net.State = ReplicatedStorage:WaitForChild("GameState")
	Net.State:WaitForChild("ActiveBomb")
end

return Net

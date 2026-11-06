--[[
	All tunable numbers for Contingency live here so balancing after playtests
	never means hunting through gameplay code.

	Values marked OPEN are placeholders for design questions not answered yet.
]]

local Config = {}

Config.Round = {
	MinPlayers = 3, -- 1 Scarecrow + 2 survivors
	MaxSurvivors = 5,
	IntermissionSeconds = 15,
	BriefingSeconds = 7, -- Batcomputer mission report before the match
	DebriefSeconds = 7, -- "Mission Completed / Mission Lost" screen
	MatchSeconds = 8 * 60,
	FinalCountdownSeconds = 10, -- audible beeps for the last N seconds
}

Config.Bombs = {
	-- Keyed by survivor count. Counts below 2 use the 2-survivor row.
	BySurvivors = {
		[2] = { Count = 4, DisarmSeconds = 8 },
		[3] = { Count = 5, DisarmSeconds = 10 },
		[4] = { Count = 6, DisarmSeconds = 12 },
		[5] = { Count = 7, DisarmSeconds = 14 },
	},
	InteractRange = 8, -- studs from the bomb to start disarming
	MoveCancelDistance = 1.5, -- moving this far from where the disarm started cancels it (progress is kept)
	RandomOrder = true, -- OPEN (Q6): shuffle which fixed spots are used and their reveal order
	AllowDisarmWhileInvincible = true, -- OPEN (Q9): can a just-revived survivor disarm?
}

Config.Survivor = {
	WalkSpeed = 16, -- OPEN (Q8)
	ReviveRange = 8,
	ReviveHP = 10,
	ReviveInvincibleSeconds = 10,
	-- A survivor can only be downed once. The next time they hit 0 HP they are benched (spectating).
}

Config.Scarecrow = {
	WalkSpeed = 18, -- OPEN (Q8)
}

-- Character kits. Only HP is used by the round loop; the rest is recorded for the abilities pass.
Config.Kits = {
	Damian = {
		MaxHP = 100,
		Heal = { Amount = 25, Range = 6, Cooldown = 30 }, -- allies only, never someone who was already downed
		Parry = { Window = 0.7, StunSeconds = 2, Cooldown = 25 }, -- only blocks Scarecrow's basic slash
	},
	Scarecrow = {
		SickleSlash = { Damage = 30, Cooldown = 1.5 },
		FearGas = { Radius = 14, DurationSeconds = 4, TotalDamage = 30, Cooldown = nil }, -- OPEN (Q2): cooldown, thrown vs. around him
		Hallucination = { ThrowRange = 40, Radius = 10, Cooldown = 25, FakeScarecrowDamageMultiplier = 0.6, DistortSeconds = nil }, -- OPEN (Q3): distortion duration
		PanicRush = { LungeSeconds = 2, Slashes = 4, DamagePerSlash = 10, ComboSeconds = 2, Cooldown = 30, LungeDistance = nil }, -- OPEN (Q4): lunge distance
	},
}

Config.SurvivorKit = "Damian" -- OPEN (Q7): only kit so far, so every survivor plays Damian

Config.Debug = {
	StudioMinPlayers = 1, -- in Studio a solo tester becomes a survivor with no Scarecrow
	SelfDamageKey = Enum.KeyCode.K, -- Studio only: damage yourself to test down / revive / bench
	SelfDamageAmount = 30,
}

return Config

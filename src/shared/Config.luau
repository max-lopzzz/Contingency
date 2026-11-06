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

-- Character kits. Abilities are listed in HUD order; Key is a KeyCode or a UserInputType (mouse).
Config.Kits = {
	Damian = {
		MaxHP = 100,
		Abilities = { "Parry", "Heal" },
		Parry = {
			Key = Enum.KeyCode.Q,
			Window = 0.7, -- katana drawn; a Sickle Slash landing in this window is parried
			StunSeconds = 2,
			Cooldown = 25,
		},
		Heal = {
			Key = Enum.KeyCode.F,
			Amount = 25, -- instant; allies only, never someone who was already downed
			Range = 6,
			Cooldown = 30,
		},
	},
	Scarecrow = {
		Abilities = { "SickleSlash", "FearGas", "Hallucination", "PanicRush" },
		SickleSlash = {
			Key = Enum.UserInputType.MouseButton1,
			Damage = 30,
			Cooldown = 1.5,
			Windup = 0.25, -- delay before the hit lands, so a parry can be read
			Range = 6,
			ArcDegrees = 100, -- hits the single closest survivor inside this cone
		},
		FearGas = {
			Key = Enum.KeyCode.Q,
			Radius = 14, -- released around Scarecrow; OPEN (Q2): thrown instead?
			DurationSeconds = 4,
			TotalDamage = 30, -- dealt over the duration, only to survivors caught in the initial burst
			Ticks = 4,
			PutsAbilitiesOnCooldown = true, -- caught survivors' abilities go on full cooldown
			Cooldown = 20, -- OPEN (Q2)
		},
		Hallucination = {
			Key = Enum.KeyCode.E,
			ThrowRange = 40,
			FlightSeconds = 0.6,
			Radius = 10,
			Cooldown = 25,
			DistortSeconds = 8, -- OPEN (Q3)
			FakeScarecrows = 2, -- can hit for a reduced amount
			FakeScarecrowDamageMultiplier = 0.6, -- of Sickle Slash damage
			FakeScarecrowSpeed = 14,
			FakeScarecrowHitCooldown = 1.5,
			FakeTeammates = 2, -- visual only
		},
		PanicRush = {
			Key = Enum.KeyCode.F,
			LungeSeconds = 2, -- max lunge time; ends early on a catch
			LungeSpeed = 32, -- OPEN (Q4): distance, currently up to 64 studs
			CatchRange = 4,
			Slashes = 4,
			DamagePerSlash = 10,
			ComboSeconds = 2,
			Cooldown = 30,
		},
	},
}

Config.SurvivorKit = "Damian" -- OPEN (Q7): only kit so far, so every survivor plays Damian

Config.Debug = {
	StudioMinPlayers = 1, -- in Studio a solo tester becomes a survivor with no Scarecrow
	SelfDamageKey = Enum.KeyCode.K, -- Studio only: damage yourself to test down / revive / bench
	SelfDamageAmount = 30,
}

return Config

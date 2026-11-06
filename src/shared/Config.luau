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
	-- Visual model cloned onto every spot: ServerStorage.Assets.FearGasBomb (Creator Store C4, 15590597168).
	-- Missing model falls back to the plain spot part.
	ModelSize = 4, -- studs; the model's longest side is scaled to this
	StatusColors = {
		Idle = Color3.fromRGB(90, 20, 20), -- not revealed yet: dim red, no light
		Active = Color3.fromRGB(255, 170, 0), -- the one to disarm: lit and blinking
		Disarmed = Color3.fromRGB(70, 200, 90),
	},
	BlinkSeconds = 0.5,
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

-- Held weapon models (server/Weapons.luau), templates in ServerStorage.Assets.Weapons.
-- Grip / BackGrip are the handle's offset from RightGripAttachment / BodyBackAttachment,
-- in the same convention as Tool.Grip.
local KATANA_GRIP = CFrame.fromMatrix(Vector3.new(0, 0, -1.7), Vector3.yAxis, Vector3.zAxis, Vector3.xAxis)
Config.Weapons = {
	Katana = { -- Creator Store 4591697150; blade along the handle's +Z, hilt at -Z
		Handle = "Handle",
		Scale = 0.6, -- the model is ~5 studs; sized down for standard avatars
		Grip = KATANA_GRIP, -- the Tool's own grip
		-- Sheathed: hilt over the right shoulder, blade down the back.
		BackGrip = (CFrame.new(0, 0, 0.35) * CFrame.Angles(0, 0, math.rad(35)) * CFrame.Angles(math.rad(90), 0, 0)):Inverse(),
	},
	Sickle = { -- Creator Store 17404338816; shaft along +Y with the blade at the top
		Handle = "Meshes/Sickle_Cube",
		Scale = 0.75,
		-- Held low on the shaft, standing up and tipped 15 degrees forward, blade curving forward.
		-- (Measured in Studio against an R15 RightGripAttachment.)
		Grip = CFrame.new(0, -1.4, 0) * CFrame.fromEulerAnglesXYZ(math.rad(-119.1), math.rad(-36), math.rad(-74.3)),
	},
}
Config.Kits.Damian.Weapon = { Name = "Katana", Rest = "Back" } -- drawn into the hand during Parry
Config.Kits.Scarecrow.Weapon = { Name = "Sickle", Rest = "Hand" }

-- Outfits (server/Outfits.luau): a kit with an Outfit spawns in it instead of the player's own avatar.
-- Fields are HumanoidDescription properties; accessory fields take a list of Marketplace IDs.
-- SkinColor is a hex code applied to every body part.
Config.Kits.Damian.Outfit = {
	HairAccessory = { 75950807831434, 18332618554 }, -- black emo anime hair, messy wavy hair
	HatAccessory = { 83432370589857 }, -- gold rune hood
	FaceAccessory = { 18928204157 }, -- Blood Son's mask
	NeckAccessory = { 11810592188 }, -- Stargazer's Crest
	ShouldersAccessory = { 110530850781464 }, -- right shoulder bandage wraps
	-- The Steel Katana accessory (12508410858) is left out: Weapons.luau already puts his katana on his back.
	BackAccessory = { 12785830450 }, -- black cape
	WaistAccessory = { 17168048610 }, -- utility belt
	Shirt = 567486574,
	Pants = 567486933,
	SkinColor = "8c604b",
}

Config.SurvivorKit = "Damian" -- OPEN (Q7): only kit so far, so every survivor plays Damian

Config.Debug = {
	StudioMinPlayers = 1, -- in Studio a solo tester becomes a survivor with no Scarecrow
	SelfDamageKey = Enum.KeyCode.K, -- Studio only: damage yourself to test down / revive / bench
	SelfDamageAmount = 30,
}

return Config

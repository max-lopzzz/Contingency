--[[
	Scarecrow (killer):
	  Sickle Slash   single-target melee hit; Damian can parry it
	  Fear Gas       burst around him; damage over time and puts survivor abilities on cooldown
	  Hallucination  thrown bottle; distorts vision, spawns fake teammates (visual) and
	                 fake Scarecrows that chase and hit for reduced damage
	  Panic Rush     straight lunge; on a catch, a multi-slash combo that can't be parried
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SurvivorService = require(script.Parent.Parent.SurvivorService)
local CombatService = require(script.Parent.Parent.CombatService)
local Fx = require(script.Parent.Parent.Fx)

local Kit = Config.Kits.Scarecrow
local GAS_COLOR = Color3.fromRGB(120, 200, 60)
local HALLUCINATION_COLOR = Color3.fromRGB(150, 80, 220)

local Scarecrow = { Use = {} }

local busy: { [Player]: true } = {} -- mid lunge / combo
local fakes = {} -- { Instance, Victim, Position, NextHitAt, EndsAt }

local function now()
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character.PrimaryPart
end

local function flatDirection(aim: unknown, root: BasePart): Vector3
	if typeof(aim) == "Vector3" then
		local flat = Vector3.new(aim.X, 0, aim.Z)
		if flat.Magnitude > 0.01 then
			return flat.Unit
		end
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- Closest alive survivor within range and inside the cone around direction.
local function findTarget(origin: Vector3, direction: Vector3, range: number, arcDegrees: number): Player?
	local minDot = math.cos(math.rad(arcDegrees / 2))
	local best, bestDistance = nil, range
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and SurvivorService.IsAlive(player) then
			local offset = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
			local distance = offset.Magnitude
			local inArc = distance < 0.5 or direction:Dot(offset.Unit) >= minDot
			if distance <= bestDistance and inArc then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function survivorsWithin(position: Vector3, radius: number): { Player }
	local caught = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and SurvivorService.IsAlive(player) and (root.Position - position).Magnitude <= radius then
			table.insert(caught, player)
		end
	end
	return caught
end

function Scarecrow.RefreshMovement(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local frozen = busy[player] or CombatService.IsStunned(player)
		humanoid.WalkSpeed = if frozen then 0 else Config.Scarecrow.WalkSpeed
	end
end

function Scarecrow.Stun(player: Player, seconds: number)
	player:SetAttribute("StunnedUntil", now() + seconds)
	Scarecrow.RefreshMovement(player)
	Fx.Flash(player.Character, Color3.fromRGB(255, 255, 120), seconds)
	task.delay(seconds, Scarecrow.RefreshMovement, player)
end

function Scarecrow.CanAct(player: Player): boolean
	return not busy[player]
end

-- Sickle Slash ------------------------------------------------------------

function Scarecrow.Use.SickleSlash(player: Player, aim: unknown): boolean
	local def = Kit.SickleSlash
	local root = rootOf(player)
	if not root then
		return false
	end
	local direction = flatDirection(aim, root)

	task.delay(def.Windup, function()
		if not root.Parent or CombatService.IsStunned(player) then
			return
		end
		Fx.Slash(root.Position, direction, def.Range)
		local target = findTarget(root.Position, direction, def.Range, def.ArcDegrees)
		if not target then
			return
		end

		-- Parry: the hit landed while the survivor's katana was drawn.
		if (target:GetAttribute("ParryUntil") or 0) > now() then
			target:SetAttribute("ParryUntil", 0)
			local parry = Config.Kits[target:GetAttribute("Kit")].Parry
			Scarecrow.Stun(player, parry.StunSeconds)
			return
		end
		SurvivorService.Damage(target, def.Damage)
	end)
	return true
end

-- Fear Gas ----------------------------------------------------------------

function Scarecrow.Use.FearGas(player: Player): boolean
	local def = Kit.FearGas
	local root = rootOf(player)
	if not root then
		return false
	end
	Fx.Burst(root.Position, def.Radius, GAS_COLOR, 0.8)

	-- Only survivors in the initial burst are affected; nothing lingers.
	for _, target in survivorsWithin(root.Position, def.Radius) do
		if def.PutsAbilitiesOnCooldown then
			CombatService.StartAllCooldowns(target)
		end
		Fx.Flash(target.Character, GAS_COLOR, def.DurationSeconds)
		task.spawn(function()
			for _ = 1, def.Ticks do
				task.wait(def.DurationSeconds / def.Ticks)
				SurvivorService.Damage(target, def.TotalDamage / def.Ticks)
			end
		end)
	end
	return true
end

-- Hallucination -----------------------------------------------------------

local function spawnFakeScarecrow(victim: Player, around: Vector3, endsAt: number)
	local angle = math.random() * math.pi * 2
	local position = around + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 18

	local marker = Instance.new("Folder")
	marker.Name = "FakeScarecrow"
	marker:SetAttribute("VictimId", victim.UserId)
	marker:SetAttribute("Position", position)
	marker.Parent = Net.Hallucinations

	table.insert(fakes, {
		Instance = marker,
		Victim = victim,
		Position = position,
		NextHitAt = 0,
		EndsAt = endsAt,
	})
end

local function hallucinate(victim: Player)
	local def = Kit.Hallucination
	local root = rootOf(victim)
	if not root then
		return
	end
	local endsAt = now() + def.DistortSeconds
	victim:SetAttribute("HallucinatingUntil", math.max(endsAt, victim:GetAttribute("HallucinatingUntil") or 0))
	for _ = 1, def.FakeScarecrows do
		spawnFakeScarecrow(victim, root.Position, endsAt)
	end
end

function Scarecrow.Use.Hallucination(player: Player, aim: unknown): boolean
	local def = Kit.Hallucination
	local root = rootOf(player)
	if not root or typeof(aim) ~= "Vector3" then
		return false
	end

	local offset = aim - root.Position
	local landing = if offset.Magnitude > def.ThrowRange then root.Position + offset.Unit * def.ThrowRange else aim
	task.spawn(function()
		Fx.Throw(root.Position + Vector3.new(0, 2, 0), landing, def.FlightSeconds, HALLUCINATION_COLOR)
		Fx.Burst(landing, def.Radius, HALLUCINATION_COLOR, 1)
		for _, target in survivorsWithin(landing, def.Radius) do
			hallucinate(target)
		end
	end)
	return true
end

local replicateAccumulator = 0

local function stepFakes(dt: number)
	local def = Kit.Hallucination
	local hitRange = Kit.SickleSlash.Range * 0.8
	replicateAccumulator += dt
	local replicate = replicateAccumulator >= 0.1
	if replicate then
		replicateAccumulator = 0
	end

	for i = #fakes, 1, -1 do
		local fake = fakes[i]
		local root = rootOf(fake.Victim)
		if now() >= fake.EndsAt or not root or not SurvivorService.IsAlive(fake.Victim) then
			fake.Instance:Destroy()
			table.remove(fakes, i)
			continue
		end

		local offset = root.Position - fake.Position
		local distance = offset.Magnitude
		if distance > hitRange * 0.5 then
			fake.Position += offset.Unit * math.min(distance, def.FakeScarecrowSpeed * dt)
		end
		if distance <= hitRange and now() >= fake.NextHitAt then
			fake.NextHitAt = now() + def.FakeScarecrowHitCooldown
			SurvivorService.Damage(fake.Victim, Kit.SickleSlash.Damage * def.FakeScarecrowDamageMultiplier)
		end
		if replicate then
			fake.Instance:SetAttribute("Position", fake.Position)
		end
	end
end

-- Panic Rush --------------------------------------------------------------

function Scarecrow.Use.PanicRush(player: Player, aim: unknown): boolean
	local def = Kit.PanicRush
	local character = player.Character
	local root = rootOf(player)
	if not (character and root) then
		return false
	end
	local direction = flatDirection(aim, root)

	busy[player] = true
	Scarecrow.RefreshMovement(player)
	character:PivotTo(CFrame.lookAt(root.Position, root.Position + direction))

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * def.LungeSpeed
	velocity.MaxForce = 1e6
	velocity.Parent = root

	task.spawn(function()
		local started = os.clock()
		local victim = nil
		while os.clock() - started < def.LungeSeconds and root.Parent and not CombatService.IsStunned(player) do
			victim = findTarget(root.Position, direction, def.CatchRange, 180)
			if victim then
				break
			end
			RunService.Heartbeat:Wait()
		end
		velocity:Destroy()
		attachment:Destroy()

		if victim and root.Parent then
			SurvivorService.SetRooted(victim, true)
			for _ = 1, def.Slashes do
				if not root.Parent or not SurvivorService.IsAlive(victim) then
					break
				end
				Fx.Slash(root.Position, direction, Kit.SickleSlash.Range)
				SurvivorService.Damage(victim, def.DamagePerSlash)
				task.wait(def.ComboSeconds / def.Slashes)
			end
			SurvivorService.SetRooted(victim, false)
		end

		busy[player] = nil
		Scarecrow.RefreshMovement(player)
	end)
	return true
end

-- Lifecycle ---------------------------------------------------------------

function Scarecrow.Reset()
	for _, fake in fakes do
		fake.Instance:Destroy()
	end
	table.clear(fakes)
end

function Scarecrow.Init()
	RunService.Heartbeat:Connect(stepFakes)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return Scarecrow

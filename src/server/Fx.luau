-- Placeholder visual effects until real animations and particles exist.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Fx = {}

local function effectPart(props): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		part[key] = value
	end
	part.Parent = workspace
	return part
end

-- Quick arc in front of the attacker.
function Fx.Slash(origin: Vector3, direction: Vector3, range: number)
	local part = effectPart({
		Size = Vector3.new(range * 1.2, 0.2, 0.6),
		CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -range / 2),
		Color = Color3.fromRGB(220, 220, 220),
		Transparency = 0.3,
	})
	TweenService:Create(part, TweenInfo.new(0.15), { Transparency = 1 }):Play()
	Debris:AddItem(part, 0.2)
end

-- Expanding sphere, e.g. a gas cloud.
function Fx.Burst(position: Vector3, radius: number, color: Color3, seconds: number)
	local part = effectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one,
		Position = position,
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
	})
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, seconds + 0.1)
end

-- Lobbed projectile; yields until it lands.
function Fx.Throw(from: Vector3, to: Vector3, seconds: number, color: Color3)
	local part = effectPart({ Size = Vector3.new(0.6, 1, 0.6), Position = from, Color = color })
	local height = math.max(4, (to - from).Magnitude * 0.25)
	local started = os.clock()
	while true do
		local t = math.min(1, (os.clock() - started) / seconds)
		part.Position = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * height, 0)
		if t >= 1 then
			break
		end
		task.wait()
	end
	part:Destroy()
end

-- Tints a character for a moment (parry stance, heal, stun).
function Fx.Flash(character: Model?, color: Color3, seconds: number)
	if not character then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.5
	highlight.OutlineColor = color
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	Debris:AddItem(highlight, seconds)
end

return Fx

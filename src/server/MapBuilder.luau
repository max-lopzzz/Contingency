--[[
	Placeholder Gotham: a 3x3 grid of city blocks split by alleys, crossed by two
	closed-off streets each way, a central plaza with the Bat-Signal searchlight,
	and a lobby pad outside the playable area.

	Only built when Workspace.Map / Workspace.Lobby don't already exist, so a real
	map saved in the place file replaces this automatically. Builds:
	  Workspace.Map.Geometry          everything solid / decorative
	  Workspace.Map.BombSpots         7 parts in alleys, "Order" 1-7
	  Workspace.Map.SurvivorSpawns    5 parts
	  Workspace.Map.ScarecrowSpawn    part
	  Workspace.Lobby, Workspace.LobbySpawn

	Props come from ServerStorage.Assets (models saved in the place file, imported from
	the Creator Store with their scripts removed). Each one falls back to a plain block
	when its model is missing, so a fresh `rojo build` still produces a playable map:
	  Assets.Props.<Dumpster|TrashBags|FireEscape|SteamVent|Manhole|PoliceBarricade|RoadBlock|WreckedCar>
	  Assets.Graffiti                  Decals, one picked per alley wall
]]

local ServerStorage = game:GetService("ServerStorage")

local MapBuilder = {}

local GROUND = 0.2 -- top of the asphalt
local PAD_TOP = 1 -- top of sidewalks / block pads
local HALF = 160 -- playable area is -HALF..HALF on X and Z
local STREETS = { -55, 55 } -- street centre lines (both axes)
local STREET_WIDTH = 24
local ALLEY_WIDTH = 10
local BLOCK_RANGES = { { -160, -67 }, { -43, 43 }, { 67, 160 } }

local ASPHALT = Color3.fromRGB(28, 28, 32)
local CONCRETE = Color3.fromRGB(70, 70, 74)
local BUILDING_COLORS = {
	Color3.fromRGB(52, 44, 44),
	Color3.fromRGB(44, 46, 54),
	Color3.fromRGB(60, 54, 48),
	Color3.fromRGB(38, 38, 42),
}
local BUILDING_MATERIALS = { Enum.Material.Brick, Enum.Material.Concrete, Enum.Material.Slate }
local LAMP_COLOR = Color3.fromRGB(255, 200, 130)

local rng = Random.new(1939) -- fixed seed so the placeholder looks the same every run

local function part(parent: Instance, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

-- Box sitting on a surface: x/z centre, footprint, height.
local function box(parent: Instance, name: string, x: number, z: number, sx: number, sz: number, height: number, surface: number, props)
	local p = part(parent, { Name = name, Size = Vector3.new(sx, height, sz), Position = Vector3.new(x, surface + height / 2, z) })
	for key, value in props or {} do
		p[key] = value
	end
	return p
end

local function marker(parent: Instance, name: string, position: Vector3): Part
	return part(parent, {
		Name = name,
		Size = Vector3.new(4, 1, 4),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Imported models ---------------------------------------------------------

local function assetFolder(name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild(name)
end

-- Yaw that turns a model's -Z side (its back) to face `direction`.
local function backToward(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

type PropOptions = {
	Scale: number?,
	-- "Box" (default) centres the bounding box on `position`; "Main" centres the model's
	-- biggest part instead, for models whose loose debris would push the box off-centre.
	Anchor: ("Box" | "Main")?,
	Solid: boolean?, -- false: nothing in the model blocks movement
	-- true: keep the template's own collision even on thin parts (stair treads, ladder rungs).
	Climbable: boolean?,
}

-- Loose clutter never blocks movement, so it can't wall off a path: parts smaller than
-- DEBRIS_SIZE, and flat ones (litter sheets, decals on cards) thinner than FLAT_SIZE.
local DEBRIS_SIZE = 2
local FLAT_SIZE = 0.5

-- Clones Assets.Props[name] (templates are stored straightened, pivot unrotated at the
-- box centre), turns it by `yaw` and sits it on `position`. Returns nil when the model
-- isn't in the place so callers can fall back to a block.
local function prop(parent: Instance, name: string, position: Vector3, yaw: number, options: PropOptions?): Model?
	local props = assetFolder("Props")
	local template = props and props:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local opts = options or {}
	local model = template:Clone()
	if opts.Scale and opts.Scale ~= 1 then
		model:ScaleTo(model:GetScale() * opts.Scale)
	end
	local main, volume = nil, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			local size = d.Size
			local clutter = math.max(size.X, size.Y, size.Z) < DEBRIS_SIZE or math.min(size.X, size.Y, size.Z) < FLAT_SIZE
			if opts.Solid == false or (clutter and not opts.Climbable) then
				d.CanCollide = false
			end
			if size.X * size.Y * size.Z > volume then
				main, volume = d, size.X * size.Y * size.Z
			end
		end
	end
	model:PivotTo(CFrame.new(model:GetPivot().Position) * CFrame.Angles(0, yaw, 0))
	local box, size = model:GetBoundingBox()
	local centre = if opts.Anchor == "Main" and main then main.Position else box.Position
	local shift = Vector3.new(position.X - centre.X, position.Y + size.Y / 2 - box.Position.Y, position.Z - centre.Z)
	model:PivotTo(model:GetPivot() + shift)
	model.Parent = parent
	return model
end

-- Every building's footprint, so graffiti can check it has a wall behind it.
type Roof = { Centre: Vector3, Size: Vector2, HasTower: boolean }
local roofs: { Roof } = {} -- also used to place the Bat-Signal

local function insideBuilding(point: Vector3): boolean
	for _, roof in roofs do
		if math.abs(point.X - roof.Centre.X) <= roof.Size.X / 2 and math.abs(point.Z - roof.Centre.Z) <= roof.Size.Y / 2 then
			return true
		end
	end
	return false
end

-- A graffiti decal on a wall. `normal` is the axis-aligned direction the wall faces.
-- Slides along the wall until the whole canvas has building behind it (alley openings,
-- building ends and the sidewalk gap would leave it hanging in the air), else skips it.
local GRAFFITI_SLIDES = { 0, -3, 3, -6, 6, -9, 9 }
local function graffiti(parent: Instance, position: Vector3, normal: Vector3, along: Vector3)
	local decals = assetFolder("Graffiti")
	local choices = decals and decals:GetChildren() or {}
	if #choices == 0 then
		return
	end
	local width, height = 9, 6
	local placed = false
	for _, slide in GRAFFITI_SLIDES do
		local centre = position + along * slide
		local covered = true
		for s = -width / 2, width / 2, width / 6 do
			if not insideBuilding(centre + along * s - normal * 0.5) then
				covered = false
				break
			end
		end
		if covered then
			position = centre
			placed = true
			break
		end
	end
	if not placed then
		return
	end
	local axis = Vector3.new(math.abs(along.X), 0, math.abs(along.Z))
	local size = Vector3.new(0.05, height, 0.05) + axis * width
	local face = if normal.X > 0 then Enum.NormalId.Right
		elseif normal.X < 0 then Enum.NormalId.Left
		elseif normal.Z > 0 then Enum.NormalId.Back
		else Enum.NormalId.Front
	local canvas = part(parent, {
		Name = "Graffiti",
		Size = size,
		Position = position + normal * 0.05,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local decal = choices[rng:NextInteger(1, #choices)]:Clone()
	decal.Face = face
	decal.Parent = canvas
end

-- Props ---------------------------------------------------------------------

local function streetLamp(parent: Instance, x: number, z: number)
	local lamp = Instance.new("Model")
	lamp.Name = "StreetLamp"
	box(lamp, "Pole", x, z, 0.6, 0.6, 14, PAD_TOP, { Color = Color3.fromRGB(25, 25, 25), Material = Enum.Material.Metal })
	local head = box(lamp, "Head", x, z, 2, 2, 0.6, PAD_TOP + 14, { Color = LAMP_COLOR, Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = LAMP_COLOR
	light.Range = 45
	light.Brightness = 2
	light.Shadows = true
	light.Parent = head
	lamp.Parent = parent
end

-- `facing` is the axis-aligned direction the open front should face (away from the wall).
local function dumpster(parent: Instance, x: number, z: number, facing: Vector3)
	-- The template's front (lid side, trash spilling out) is its +X, so the body runs with the alley.
	local yaw = math.atan2(-facing.Z, facing.X)
	if prop(parent, "Dumpster", Vector3.new(x, PAD_TOP, z), yaw, { Scale = 0.7, Anchor = "Main" }) then
		return
	end
	local alongX = math.abs(facing.Z) > 0.5
	local sx, sz = if alongX then 6 else 3.5, if alongX then 3.5 else 6
	box(parent, "Dumpster", x, z, sx, sz, 4, PAD_TOP, { Color = Color3.fromRGB(30, 70, 40), Material = Enum.Material.Metal })
end

-- Small stack laid out along the alley.
local function crates(parent: Instance, x: number, z: number, alongX: boolean)
	local color = Color3.fromRGB(110, 80, 50)
	local step = if alongX then Vector3.new(3.2, 0, 0) else Vector3.new(0, 0, 3.2)
	for k, offset in { Vector3.zero, step, step / 2 } do
		local surface = if k == 3 then PAD_TOP + 3 else PAD_TOP
		box(parent, "Crate", x + offset.X, z + offset.Z, 3, 3, 3, surface, { Color = color, Material = Enum.Material.WoodPlanks })
	end
end

-- Police barricade across a street end. `alongX` = the street runs along X.
local function barricade(parent: Instance, x: number, z: number, alongX: boolean)
	local model = Instance.new("Model")
	model.Name = "Barricade"
	-- Road blocks and crowd barriers run lengthwise along Z in their own space.
	local acrossYaw = if alongX then 0 else math.rad(90)
	local inward = if alongX then Vector3.new(if x > 0 then -1 else 1, 0, 0) else Vector3.new(0, 0, if z > 0 then -1 else 1)
	for offset = -9, 9, 9 do
		local bx, bz = if alongX then x else x + offset, if alongX then z + offset else z
		if not prop(model, "RoadBlock", Vector3.new(bx, GROUND, bz), acrossYaw) then
			local sx, sz = if alongX then 2 else 7, if alongX then 7 else 2
			box(model, "JerseyBarrier", bx, bz, sx, sz, 3, GROUND, { Color = Color3.fromRGB(150, 150, 145), Material = Enum.Material.Concrete })
		end
	end
	-- Crowd barriers in front of the squad car, which sits on the inner side.
	local acrossDir = if alongX then Vector3.zAxis else Vector3.xAxis
	local front = Vector3.new(x, GROUND, z) + inward * 10
	for _, offset in { -6, 6 } do
		prop(model, "PoliceBarricade", front + acrossDir * offset, acrossYaw)
	end
	-- Squad car parked sideways across the street behind the barriers (model is long along Z).
	local back = if alongX then (if x > 0 then -6 else 6) else (if z > 0 then -6 else 6)
	local cx, cz = if alongX then x + back else x, if alongX then z else z + back
	local red, blue = Color3.fromRGB(255, 40, 40), Color3.fromRGB(50, 90, 255)
	local function glow(bar: BasePart, color: Color3)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 18
		light.Brightness = 1.5
		light.Parent = bar
	end
	local car = prop(model, "PoliceCar", Vector3.new(cx, GROUND, cz), if alongX then 0 else math.rad(90), { Scale = 0.6, Anchor = "Main" })
	if car then
		for _, side in { { "light_rack_red", red }, { "light_rack_blue", blue } } do
			local bar = car:FindFirstChild(side[1], true)
			if bar and bar:IsA("BasePart") then
				glow(bar, side[2])
			end
		end
	else
		local sx, sz = if alongX then 5 else 11, if alongX then 11 else 5
		box(model, "SquadCar", cx, cz, sx, sz, 3.5, GROUND, { Color = Color3.fromRGB(20, 30, 60), Material = Enum.Material.SmoothPlastic })
		local half = if alongX then Vector3.new(0, 0, 0.75) else Vector3.new(0.75, 0, 0)
		for _, side in { { "LightbarRed", red, -1 }, { "LightbarBlue", blue, 1 } } do
			local p = Vector3.new(cx, 0, cz) + half * side[3]
			glow(box(model, side[1], p.X, p.Z, if alongX then 1 else 0.75, if alongX then 0.75 else 1, 0.6, GROUND + 3.5, { Color = side[2], Material = Enum.Material.Neon }), side[2])
		end
	end
	model.Parent = parent
end

-- City blocks ---------------------------------------------------------------

local function building(parent: Instance, x0: number, z0: number, x1: number, z1: number)
	if x1 - x0 < 1 or z1 - z0 < 1 then
		return
	end
	local height = rng:NextInteger(40, 110)
	local roof: Roof = { Centre = Vector3.new((x0 + x1) / 2, PAD_TOP + height, (z0 + z1) / 2), Size = Vector2.new(x1 - x0, z1 - z0), HasTower = false }
	table.insert(roofs, roof)
	box(parent, "Building", (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, height, PAD_TOP, {
		Color = BUILDING_COLORS[rng:NextInteger(1, #BUILDING_COLORS)],
		Material = BUILDING_MATERIALS[rng:NextInteger(1, #BUILDING_MATERIALS)],
	})
	-- Occasional rooftop water tower for skyline variety.
	if rng:NextNumber() < 0.35 then
		roof.HasTower = true
		local tower = part(parent, {
			Name = "WaterTower",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(8, 7, 7),
			CFrame = CFrame.new((x0 + x1) / 2, PAD_TOP + height + 4, (z0 + z1) / 2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(80, 60, 45),
			Material = Enum.Material.WoodPlanks,
		})
		tower.CastShadow = false
	end
end

local function alleyLight(parent: Instance, position: Vector3, height: number, color: Color3, range: number, brightness: number)
	local fixture = box(parent, "AlleyLight", position.X, position.Z, 1, 1, 0.5, PAD_TOP + height, { Color = color, Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = fixture
end

local BOMB_LAMP = Color3.fromRGB(255, 150, 60)
local MOUTH_LAMP = Color3.fromRGB(170, 185, 255)

-- One straight stretch of alley: `mouth` is where it meets the street, `inner` its other end
-- (the far street, or the bend of an L). Clutter hugs the walls so at least half the width
-- stays open; `side` (+1/-1) picks which wall gets the dumpster.
local function dressLeg(geometry: Instance, mouth: Vector3, inner: Vector3, side: number)
	local along = (inner - mouth).Unit
	local across = Vector3.new(along.Z, 0, -along.X) * side
	local length = (inner - mouth).Magnitude
	local half = ALLEY_WIDTH / 2
	local function at(t: number, wall: number): Vector3
		return mouth + along * (length * t) + across * wall
	end

	local d = at(0.55, half - 2.2)
	dumpster(geometry, d.X, d.Z, -across)
	local c = at(0.25, -(half - 1.7))
	crates(geometry, c.X, c.Z, math.abs(along.X) > 0.5)
	local t = at(0.8, -(half - 2.4)) -- well clear of the dumpster on the opposite wall
	prop(geometry, "TrashBags", Vector3.new(t.X, PAD_TOP, t.Z), rng:NextNumber() * math.pi * 2, { Scale = 0.6, Anchor = "Main" })
	-- Fire escape: ladder up to the stairs. It hugs the wall, so the alley stays open beside it.
	local f = at(0.3, half - 1.75)
	prop(geometry, "FireEscape", Vector3.new(f.X, PAD_TOP, f.Z), backToward(across), { Scale = 0.7, Climbable = true })

	local wallY = Vector3.new(0, PAD_TOP + 4, 0)
	graffiti(geometry, at(0.7, -half) + wallY, across, along)
	graffiti(geometry, at(0.15, half) + wallY, -across, along)
	local m = at(0.08, -(half - 0.5))
	alleyLight(geometry, m, 9, MOUTH_LAMP, 20, 1.2)
end

-- Edge blocks: one straight alley from street to street. `alongX` = it runs along X.
-- Returns the bomb position (the alley's middle).
local function straightAlley(geometry: Instance, x0: number, x1: number, z0: number, z1: number, alongX: boolean): Vector3
	local inset = 3 -- sidewalk between street and buildings
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	box(geometry, "BlockPad", cx, cz, x1 - x0, z1 - z0, PAD_TOP - GROUND, GROUND, { Color = CONCRETE, Material = Enum.Material.Concrete })

	local a0, a1 = x0 + inset, x1 - inset
	local b0, b1 = z0 + inset, z1 - inset
	local half = ALLEY_WIDTH / 2
	if alongX then
		local mid = (a0 + a1) / 2 + rng:NextInteger(-10, 10)
		building(geometry, a0, b0, mid, cz - half)
		building(geometry, mid, b0, a1, cz - half)
		building(geometry, a0, cz + half, mid - 6, b1)
		building(geometry, mid - 6, cz + half, a1, b1)
	else
		local mid = (b0 + b1) / 2 + rng:NextInteger(-10, 10)
		building(geometry, a0, b0, cx - half, mid)
		building(geometry, a0, mid, cx - half, b1)
		building(geometry, cx + half, b0, a1, mid + 6)
		building(geometry, cx + half, mid + 6, a1, b1)
	end

	-- Each half is dressed as a leg from its street mouth to the bomb in the middle,
	-- leaving the centre clear around the bomb.
	local centre = Vector3.new(cx, 0, cz)
	local along = if alongX then Vector3.xAxis else Vector3.zAxis
	local reach = (if alongX then x1 - x0 else z1 - z0) / 2
	dressLeg(geometry, centre - along * reach, centre - along * 6, 1)
	dressLeg(geometry, centre + along * reach, centre + along * 6, -1)
	alleyLight(geometry, centre + Vector3.new(along.Z, 0, along.X) * (half - 0.5), 10, BOMB_LAMP, 22, 1.5)
	return Vector3.new(cx, PAD_TOP + 1, cz)
end

-- Corner blocks only touch two streets, at right angles, so a straight alley would dead-end
-- at the map edge. Instead an L: one leg from each street, meeting at the bomb in the middle.
-- `nearX`/`nearZ` are the block edges that face a street.
local function cornerAlley(geometry: Instance, x0: number, x1: number, z0: number, z1: number, nearX: number, nearZ: number): Vector3
	local inset = 3
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	box(geometry, "BlockPad", cx, cz, x1 - x0, z1 - z0, PAD_TOP - GROUND, GROUND, { Color = CONCRETE, Material = Enum.Material.Concrete })

	local half = ALLEY_WIDTH / 2
	local xs = { x0 + inset, cx - half, cx + half, x1 - inset }
	local zs = { z0 + inset, cz - half, cz + half, z1 - inset }
	-- 3x3 cells; the X leg is the middle row from the street side to the centre, the Z leg the
	-- middle column likewise. Everything else is buildings.
	local xLegCols = if nearX == x0 then { 1, 2 } else { 2, 3 }
	local zLegRows = if nearZ == z0 then { 1, 2 } else { 2, 3 }
	for col = 1, 3 do
		for row = 1, 3 do
			local open = (row == 2 and table.find(xLegCols, col) ~= nil) or (col == 2 and table.find(zLegRows, row) ~= nil)
			if not open then
				building(geometry, xs[col], zs[row], xs[col + 1], zs[row + 1])
			end
		end
	end

	local centre = Vector3.new(cx, 0, cz)
	dressLeg(geometry, Vector3.new(nearX, 0, cz), centre + Vector3.new(if nearX < cx then -6 else 6, 0, 0), 1)
	dressLeg(geometry, Vector3.new(cx, 0, nearZ), centre + Vector3.new(0, 0, if nearZ < cz then -6 else 6), -1)
	-- Lamp over the bomb, on the outside corner of the bend.
	local outer = Vector3.new(if nearX < cx then 1 else -1, 0, if nearZ < cz then 1 else -1)
	alleyLight(geometry, centre + outer * (half - 0.5), 10, BOMB_LAMP, 22, 1.5)
	return Vector3.new(cx, PAD_TOP + 1, cz)
end

local function plaza(geometry: Instance, x0: number, x1: number, z0: number, z1: number)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	box(geometry, "PlazaPad", cx, cz, x1 - x0, z1 - z0, PAD_TOP - GROUND, GROUND, { Color = Color3.fromRGB(95, 92, 88), Material = Enum.Material.Pavement })
	for _, offset in { Vector3.new(-25, 0, -25), Vector3.new(25, 0, -25), Vector3.new(-25, 0, 25), Vector3.new(25, 0, 25) } do
		box(geometry, "Planter", cx + offset.X, cz + offset.Z, 10, 10, 2.5, PAD_TOP, { Color = CONCRETE, Material = Enum.Material.Concrete })
		box(geometry, "Hedge", cx + offset.X, cz + offset.Z, 8.5, 8.5, 2, PAD_TOP + 2.5, { Color = Color3.fromRGB(30, 60, 30), Material = Enum.Material.Grass })
	end
	box(geometry, "Bench", cx, cz - 14, 8, 2, 1.5, PAD_TOP, { Color = Color3.fromRGB(60, 40, 25), Material = Enum.Material.Wood })
	box(geometry, "Bench", cx, cz + 14, 8, 2, 1.5, PAD_TOP, { Color = Color3.fromRGB(60, 40, 25), Material = Enum.Material.Wood })
	box(geometry, "Pedestal", cx, cz, 10, 10, 6, PAD_TOP, { Color = Color3.fromRGB(120, 115, 105), Material = Enum.Material.Marble })
end

-- Bat-Signal easter egg: a searchlight on the tallest rooftop near the plaza (like GCPD
-- headquarters) throwing a beam to a lit disc with a bat silhouette in the sky.
local function batSignal(geometry: Instance)
	local model = Instance.new("Model")
	model.Name = "BatSignal"
	local centre = CFrame.lookAt(Vector3.new(60, 190, -260), Vector3.zero)

	-- Tallest roof within reach of the plaza, avoiding ones with a water tower in the middle.
	local best: Roof? = nil
	for _, roof in roofs do
		local flat = Vector3.new(roof.Centre.X, 0, roof.Centre.Z)
		if flat.Magnitude < 110 and math.min(roof.Size.X, roof.Size.Y) >= 12 and not roof.HasTower then
			if not best or roof.Centre.Y > best.Centre.Y then
				best = roof
			end
		end
	end
	local base = if best then best.Centre else Vector3.new(0, PAD_TOP + 60, 0)
	box(model, "SearchlightBase", base.X, base.Z, 4, 4, 2, base.Y, { Color = Color3.fromRGB(45, 45, 48), Material = Enum.Material.Metal })
	local lampPos = base + Vector3.new(0, 4, 0)
	local searchlight = part(model, {
		Name = "Searchlight",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 5, 5),
		-- A cylinder's axis is its X, so face X at the disc.
		CFrame = CFrame.lookAt(lampPos, centre.Position) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(60, 60, 60),
		Material = Enum.Material.Metal,
	})
	local lens = Instance.new("SpotLight")
	lens.Face = Enum.NormalId.Left
	lens.Color = Color3.fromRGB(255, 235, 170)
	lens.Range = 25
	lens.Brightness = 3
	lens.Angle = 40
	lens.Parent = searchlight
	local disc = part(model, {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 70, 70),
		CFrame = centre * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(255, 230, 150),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		CastShadow = false,
	})
	local function silhouette(size: Vector3, offset: CFrame)
		part(model, {
			Name = "Bat",
			Size = size,
			CFrame = centre * CFrame.new(0, 0, -1) * offset,
			Color = Color3.new(0, 0, 0),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CastShadow = false,
		})
	end
	silhouette(Vector3.new(7, 14, 0.5), CFrame.new())
	silhouette(Vector3.new(20, 6, 0.5), CFrame.new(-12, 2, 0) * CFrame.Angles(0, 0, math.rad(-15)))
	silhouette(Vector3.new(20, 6, 0.5), CFrame.new(12, 2, 0) * CFrame.Angles(0, 0, math.rad(15)))
	silhouette(Vector3.new(1.5, 3, 0.5), CFrame.new(-2, 8, 0))
	silhouette(Vector3.new(1.5, 3, 0.5), CFrame.new(2, 8, 0))

	local from = Instance.new("Attachment")
	from.Parent = searchlight
	local to = Instance.new("Attachment")
	to.Parent = disc
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Width0 = 4
	beam.Width1 = 60
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 235, 170))
	beam.Transparency = NumberSequence.new(0.75, 0.9)
	beam.Parent = searchlight
	model.Parent = geometry
end

-- Map -----------------------------------------------------------------------

local function buildMap()
	local map = Instance.new("Folder")
	map.Name = "Map"
	local geometry = folder(map, "Geometry")
	local bombSpots = folder(map, "BombSpots")
	local survivorSpawns = folder(map, "SurvivorSpawns")

	box(geometry, "Asphalt", 0, 0, HALF * 2, HALF * 2, 1, GROUND - 1, { Color = ASPHALT, Material = Enum.Material.Asphalt })

	-- Road markings down the centre of each street.
	for _, s in STREETS do
		for t = -HALF + 6, HALF - 6, 14 do
			box(geometry, "LaneMark", s, t, 0.4, 6, 0.05, GROUND, { Color = Color3.fromRGB(200, 180, 60), CanCollide = false })
			box(geometry, "LaneMark", t, s, 6, 0.4, 0.05, GROUND, { Color = Color3.fromRGB(200, 180, 60), CanCollide = false })
		end
	end

	-- Blocks: centre is the plaza, the other 8 get alleys. Bombs go in 7 of them.
	-- Every bomb gets two ways in and out: edge blocks run their alley between the two
	-- streets they sit between, corner blocks get an L joining their two streets.
	table.clear(roofs)
	local alleys = {}
	for i, xr in BLOCK_RANGES do
		for j, zr in BLOCK_RANGES do
			local spot
			if i == 2 and j == 2 then
				plaza(geometry, xr[1], xr[2], zr[1], zr[2])
			elseif i == 2 or j == 2 then
				spot = straightAlley(geometry, xr[1], xr[2], zr[1], zr[2], i == 2)
			else
				local nearX = if i == 1 then xr[2] else xr[1]
				local nearZ = if j == 1 then zr[2] else zr[1]
				spot = cornerAlley(geometry, xr[1], xr[2], zr[1], zr[2], nearX, nearZ)
			end
			if spot then
				table.insert(alleys, { Position = spot, Skip = i == 3 and j == 3 })
			end
		end
	end
	local order = 0
	for _, alley in alleys do
		if not alley.Skip then
			order += 1
			local spot = part(bombSpots, { Name = "Bomb" .. order, Size = Vector3.new(2, 2, 2), Position = alley.Position })
			spot:SetAttribute("Order", order)
		end
	end

	-- Street lamps on the corners of every intersection.
	for _, sx in STREETS do
		for _, sz in STREETS do
			for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
				local offset = STREET_WIDTH / 2 + 1.5
				streetLamp(geometry, sx + corner.X * offset, sz + corner.Z * offset)
			end
		end
	end

	-- Street clutter: manholes on the centre line, steam vents on the sidewalk,
	-- wrecked cars as cover.
	local curb = STREET_WIDTH / 2 + 1.5 -- middle of the 3-stud sidewalk
	for k, s in STREETS do
		for n, t in { -110, 0, 110 } do
			prop(geometry, "Manhole", Vector3.new(s, GROUND, t), 0)
			prop(geometry, "Manhole", Vector3.new(t, GROUND, s), 0)
			local side = if (k + n) % 2 == 0 then 1 else -1
			prop(geometry, "SteamVent", Vector3.new(s + curb * side, PAD_TOP, t + 20), 0, { Scale = 0.4 })
			prop(geometry, "SteamVent", Vector3.new(t - 20, PAD_TOP, s - curb * side), 0, { Scale = 0.4 })
		end
	end
	-- Between intersections, clear of the manholes (at +-110) and the alley mouths.
	for _, spot in { Vector3.new(55, GROUND, -80), Vector3.new(-55, GROUND, 80), Vector3.new(80, GROUND, 55), Vector3.new(-80, GROUND, -55) } do
		prop(geometry, "WreckedCar", spot, rng:NextNumber() * math.pi * 2, { Scale = 0.8, Anchor = "Main" })
	end

	-- Streets are closed off where they leave the map.
	for _, s in STREETS do
		barricade(geometry, s, HALF - 4, false)
		barricade(geometry, s, -HALF + 4, false)
		barricade(geometry, HALF - 4, s, true)
		barricade(geometry, -HALF + 4, s, true)
	end

	-- Invisible boundary so nobody leaves the playable area.
	for _, side in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local size = if side.X ~= 0 then Vector3.new(2, 150, HALF * 2 + 4) else Vector3.new(HALF * 2 + 4, 150, 2)
		part(geometry, {
			Name = "Boundary",
			Size = size,
			Position = side * (HALF + 1) + Vector3.new(0, 75, 0),
			Transparency = 1,
			CastShadow = false,
		})
	end

	batSignal(geometry)

	-- Survivors start at one intersection, Scarecrow at the opposite one.
	for k = 1, 5 do
		marker(survivorSpawns, "SurvivorSpawn" .. k, Vector3.new(-55 + (k - 3) * 4, GROUND + 0.5, -55))
	end
	marker(map, "ScarecrowSpawn", Vector3.new(55, GROUND + 0.5, 55))

	map.Parent = workspace
end

local function buildLobby()
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local cz = 215
	box(lobby, "Floor", 0, cz, 120, 60, 1, GROUND, { Color = Color3.fromRGB(40, 40, 46), Material = Enum.Material.DiamondPlate })
	for _, wall in {
		{ 0, cz - 30, 120, 2 },
		{ 0, cz + 30, 120, 2 },
		{ -60, cz, 2, 60 },
		{ 60, cz, 2, 60 },
	} do
		box(lobby, "Wall", wall[1], wall[2], wall[3], wall[4], 14, GROUND + 1, { Color = Color3.fromRGB(25, 25, 30), Material = Enum.Material.Metal })
	end
	local light = box(lobby, "Light", 0, cz, 6, 6, 0.5, GROUND + 18, { Color = Color3.fromRGB(150, 200, 255), Material = Enum.Material.Neon })
	local point = Instance.new("PointLight")
	point.Range = 60
	point.Brightness = 2
	point.Color = Color3.fromRGB(150, 200, 255)
	point.Parent = light
	lobby.Parent = workspace

	marker(workspace, "LobbySpawn", Vector3.new(0, GROUND + 1.5, cz))
end

function MapBuilder.Build()
	if not workspace:FindFirstChild("Map") then
		buildMap()
	end
	if not workspace:FindFirstChild("Lobby") and not workspace:FindFirstChild("LobbySpawn") then
		buildLobby()
	end
end

return MapBuilder

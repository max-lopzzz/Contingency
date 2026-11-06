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
]]

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

local function dumpster(parent: Instance, x: number, z: number, alongX: boolean)
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
	for offset = -9, 9, 9 do
		local bx, bz = if alongX then x else x + offset, if alongX then z + offset else z
		local sx, sz = if alongX then 2 else 7, if alongX then 7 else 2
		box(model, "JerseyBarrier", bx, bz, sx, sz, 3, GROUND, { Color = Color3.fromRGB(150, 150, 145), Material = Enum.Material.Concrete })
	end
	-- Squad car parked behind the barriers.
	local back = if alongX then (if x > 0 then -6 else 6) else (if z > 0 then -6 else 6)
	local cx, cz = if alongX then x + back else x, if alongX then z else z + back
	local sx, sz = if alongX then 5 else 11, if alongX then 11 else 5
	box(model, "SquadCar", cx, cz, sx, sz, 3.5, GROUND, { Color = Color3.fromRGB(20, 30, 60), Material = Enum.Material.SmoothPlastic })
	box(model, "LightbarRed", cx, cz, if alongX then 1 else 1.5, if alongX then 1.5 else 1, 0.6, GROUND + 3.5, { Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon })
	model.Parent = parent
end

-- City blocks ---------------------------------------------------------------

local function building(parent: Instance, x0: number, z0: number, x1: number, z1: number)
	local height = rng:NextInteger(40, 110)
	box(parent, "Building", (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0, height, PAD_TOP, {
		Color = BUILDING_COLORS[rng:NextInteger(1, #BUILDING_COLORS)],
		Material = BUILDING_MATERIALS[rng:NextInteger(1, #BUILDING_MATERIALS)],
	})
	-- Occasional rooftop water tower for skyline variety.
	if rng:NextNumber() < 0.35 then
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

-- Returns the alley's centre point and whether it runs along X.
local function alleyBlock(geometry: Instance, x0: number, x1: number, z0: number, z1: number, alongX: boolean): (Vector3, boolean)
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

	-- Cover inside the alley.
	local along = if alongX then Vector3.xAxis else Vector3.zAxis
	local across = if alongX then Vector3.zAxis else Vector3.xAxis
	local centre = Vector3.new(cx, 0, cz)
	local d = centre + along * 22 + across * (half - 2)
	dumpster(geometry, d.X, d.Z, alongX)
	local c = centre - along * 24 - across * (half - 2.5)
	crates(geometry, c.X, c.Z, alongX)

	-- Dim light over the bomb spot.
	local lampPos = centre + across * (half - 0.5)
	local fixture = box(geometry, "AlleyLight", lampPos.X, lampPos.Z, 1, 1, 0.5, PAD_TOP + 10, { Color = Color3.fromRGB(255, 150, 60), Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 22
	light.Brightness = 1.5
	light.Parent = fixture

	return Vector3.new(cx, PAD_TOP + 1, cz), alongX
end

local function plaza(geometry: Instance, x0: number, x1: number, z0: number, z1: number): BasePart
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	box(geometry, "PlazaPad", cx, cz, x1 - x0, z1 - z0, PAD_TOP - GROUND, GROUND, { Color = Color3.fromRGB(95, 92, 88), Material = Enum.Material.Pavement })
	for _, offset in { Vector3.new(-25, 0, -25), Vector3.new(25, 0, -25), Vector3.new(-25, 0, 25), Vector3.new(25, 0, 25) } do
		box(geometry, "Planter", cx + offset.X, cz + offset.Z, 10, 10, 2.5, PAD_TOP, { Color = CONCRETE, Material = Enum.Material.Concrete })
		box(geometry, "Hedge", cx + offset.X, cz + offset.Z, 8.5, 8.5, 2, PAD_TOP + 2.5, { Color = Color3.fromRGB(30, 60, 30), Material = Enum.Material.Grass })
	end
	box(geometry, "Bench", cx, cz - 14, 8, 2, 1.5, PAD_TOP, { Color = Color3.fromRGB(60, 40, 25), Material = Enum.Material.Wood })
	box(geometry, "Bench", cx, cz + 14, 8, 2, 1.5, PAD_TOP, { Color = Color3.fromRGB(60, 40, 25), Material = Enum.Material.Wood })
	box(geometry, "Pedestal", cx, cz, 10, 10, 6, PAD_TOP, { Color = Color3.fromRGB(120, 115, 105), Material = Enum.Material.Marble })
	return part(geometry, {
		Name = "Searchlight",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 5, 5),
		CFrame = CFrame.new(cx, PAD_TOP + 8.5, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 60, 60),
		Material = Enum.Material.Metal,
	})
end

-- Bat-Signal easter egg: a lit disc in the sky with a bat silhouette, fed by a beam from the plaza.
local function batSignal(geometry: Instance, searchlight: BasePart)
	local model = Instance.new("Model")
	model.Name = "BatSignal"
	local centre = CFrame.lookAt(Vector3.new(60, 190, -260), Vector3.zero)
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
	local alleys = {}
	local searchlight
	for i, xr in BLOCK_RANGES do
		for j, zr in BLOCK_RANGES do
			if i == 2 and j == 2 then
				searchlight = plaza(geometry, xr[1], xr[2], zr[1], zr[2])
			else
				local spot = alleyBlock(geometry, xr[1], xr[2], zr[1], zr[2], (i + j) % 2 == 0)
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

	batSignal(geometry, searchlight)

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

--!strict
--[[
	RoomBuilder: convierte UNA sala del plano en geometria de verdad.

	DECISION DE LA FASE 3: las salas se construyen POR CODIGO, no clonando prefabs de
	`ServerStorage/RoomPrefabs`.

	El plan original pedia prefabs armados en Studio. Se eligio construirlas aqui por
	una razon concreta que el propio changelog de la Fase 0 dejo anotada como deuda:
	"un .rbxl reconstruible desde el repo queda pendiente". Con las salas en codigo, el
	piso entero sale de Git: el CI puede construir un place jugable sin que nadie tenga
	que acordarse de exportar un `.rbxmx`, y una sala no se puede "romper en el place"
	sin que se vea en un diff.

	Lo que se pierde: una sala hecha a mano tiene personalidad (columnas, recovecos,
	cobertura) que un generador no inventa solo. Por eso esto NO cierra la puerta:
	`DungeonGenerator` usa un prefab de `ServerStorage/RoomPrefabs` si existe uno para
	ese tipo de sala, y cae aca solo si no lo hay. Greybox jugable hoy, salas con
	carino cuando alguien las construya, sin cambiar una linea de los sistemas.

	Estructura de la sala que se produce (la misma que tendra un prefab hecho a mano,
	para que sean intercambiables):

		Room_<x>_<y>  (Model, tag Room, Attributes RoomType/GridX/GridY/...)
		  Floor       (BasePart, PrimaryPart)
		  Walls       (Folder)
		  Doors       (Folder, Parts con Attribute Side; CanCollide off = abierta)
		  SpawnPoints (Folder, Parts invisibles para los enemigos de la Fase 4)

	Cero scripts adentro (regla 4): quien la opera es RoomService, desde afuera.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local DungeonLayout = require(Shared.Logic.DungeonLayout)
local Tags = require(Shared.Tags)

local ROOM_SIZE = Constants.ROOM_SIZE_STUDS
local HALF_ROOM = ROOM_SIZE / 2
local WALL_HEIGHT = Constants.WALL_HEIGHT_STUDS
local WALL_THICKNESS = Constants.WALL_THICKNESS_STUDS
local DOOR_GAP = Constants.DOOR_GAP_STUDS
local SEGMENT_LENGTH = (ROOM_SIZE - DOOR_GAP) / 2
local SEGMENT_OFFSET = DOOR_GAP / 2 + SEGMENT_LENGTH / 2

local WALL_COLOR = Color3.fromRGB(104, 99, 120)
local DOOR_COLOR = Color3.fromRGB(214, 92, 74)

--[[
	El color del piso es la unica pista que tiene el jugador de en que tipo de sala esta
	antes de que pase nada. Paleta desaturada, coherente con la niebla.

	SUBIDOS EN LA FASE 4: eran del 23% de luminancia, y como el ambiente MULTIPLICA el
	color de la parte, un gris oscuro bajo una luz tenue no da un gris mas oscuro, da
	negro. Ahora rondan el 40%, que con el ambiente corregido se lee como piedra
	iluminada en vez de como un agujero.
]]
local FLOOR_COLORS: { [DungeonLayout.RoomKind]: Color3 } = {
	Start = Color3.fromRGB(108, 134, 112),
	Combat = Color3.fromRGB(96, 92, 102),
	Item = Color3.fromRGB(98, 114, 146),
	Portal = Color3.fromRGB(124, 100, 148),
	Boss = Color3.fromRGB(140, 88, 88),
}

local RoomBuilder = {}

export type BuiltRoom = {
	model: Model,
	floor: BasePart,
	doors: { BasePart },
	spawnPoints: { BasePart },
	center: Vector3,
}

--[[ Centro de una celda de la grilla, en studs. El eje Y de la grilla es el Z del mundo. ]]
function RoomBuilder.cellToWorld(x: number, y: number): Vector3
	local origin = Constants.DUNGEON_ORIGIN

	return Vector3.new(origin.x + x * ROOM_SIZE, origin.y, origin.z + y * ROOM_SIZE)
end

local function newPart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")

	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.Slate -- textura granulada barata que rompe el plano liso
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

--[[
	Datos de un lado: hacia donde esta y como se orienta la pared.
	`along` es el eje sobre el que se reparte la pared, `depth` el eje de su grosor.
]]
type SideGeometry = {
	side: DungeonLayout.Side,
	offset: Vector3, -- del centro de la sala al centro del lado
	along: Vector3, -- direccion en la que se reparten los segmentos
	wallSize: Vector3, -- tamano de un segmento completo (sin hueco)
	segmentSize: Vector3,
	doorSize: Vector3,
}

local function buildSideGeometry(): { SideGeometry }
	local edge = HALF_ROOM - WALL_THICKNESS / 2
	local horizontal = Vector3.new(ROOM_SIZE, WALL_HEIGHT, WALL_THICKNESS)
	local vertical = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, ROOM_SIZE)

	return {
		{
			side = "North",
			offset = Vector3.new(0, WALL_HEIGHT / 2, edge),
			along = Vector3.new(1, 0, 0),
			wallSize = horizontal,
			segmentSize = Vector3.new(SEGMENT_LENGTH, WALL_HEIGHT, WALL_THICKNESS),
			doorSize = Vector3.new(DOOR_GAP, WALL_HEIGHT, WALL_THICKNESS),
		},
		{
			side = "South",
			offset = Vector3.new(0, WALL_HEIGHT / 2, -edge),
			along = Vector3.new(1, 0, 0),
			wallSize = horizontal,
			segmentSize = Vector3.new(SEGMENT_LENGTH, WALL_HEIGHT, WALL_THICKNESS),
			doorSize = Vector3.new(DOOR_GAP, WALL_HEIGHT, WALL_THICKNESS),
		},
		{
			side = "East",
			offset = Vector3.new(edge, WALL_HEIGHT / 2, 0),
			along = Vector3.new(0, 0, 1),
			wallSize = vertical,
			segmentSize = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, SEGMENT_LENGTH),
			doorSize = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, DOOR_GAP),
		},
		{
			side = "West",
			offset = Vector3.new(-edge, WALL_HEIGHT / 2, 0),
			along = Vector3.new(0, 0, 1),
			wallSize = vertical,
			segmentSize = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, SEGMENT_LENGTH),
			doorSize = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, DOOR_GAP),
		},
	}
end

local SIDES = buildSideGeometry()

--[[
	Deja la puerta abierta o cerrada. Abierta = atravesable y transparente; cerrada =
	solida y opaca. `CanQuery` acompana a `CanCollide` para que las balas tampoco
	crucen una puerta cerrada: si no, encerrarse en una sala seria opcional para quien
	dispara desde afuera.

	Vive aca y no en RoomService porque es una propiedad de la GEOMETRIA. Quien decide
	CUANDO cerrarla es RoomService en la Fase 4.
]]
function RoomBuilder.setDoorClosed(door: BasePart, closed: boolean): ()
	door.CanCollide = closed
	door.CanQuery = closed
	door.Transparency = if closed then 0.15 else 1
	door:SetAttribute("Closed", closed)
end

local function buildSpawnPoints(parent: Folder, center: Vector3): { BasePart }
	local points: { BasePart } = {}
	local count = Constants.ENEMY_SPAWN_POINTS_PER_ROOM
	-- Anillo a media distancia del centro: lejos de las puertas (nadie aparece encima
	-- del jugador que entra) y lejos de las paredes (nadie aparece dentro de una).
	local radius = HALF_ROOM * 0.55

	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * radius, 3, math.sin(angle) * radius)

		local point = Instance.new("Part")
		point.Name = string.format("SpawnPoint%d", index)
		point.Size = Vector3.one
		point.Position = position
		point.Anchored = true
		point.CanCollide = false
		point.CanQuery = false
		point.CanTouch = false
		point.Transparency = 1
		point.Parent = parent

		table.insert(points, point)
	end

	return points
end

--[[ Construye la sala y la deja lista para que RoomService la adopte. ]]
function RoomBuilder.build(room: DungeonLayout.RoomNode, floorNumber: number, parent: Instance): BuiltRoom
	local center = RoomBuilder.cellToWorld(room.x, room.y)

	local model = Instance.new("Model")
	model.Name = string.format("Room_%d_%d", room.x, room.y)

	local floor = newPart(
		"Floor",
		Vector3.new(ROOM_SIZE, Constants.FLOOR_THICKNESS_STUDS, ROOM_SIZE),
		center - Vector3.new(0, Constants.FLOOR_THICKNESS_STUDS / 2, 0),
		FLOOR_COLORS[room.kind],
		model
	)

	model.PrimaryPart = floor

	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = model

	local doorsFolder = Instance.new("Folder")
	doorsFolder.Name = "Doors"
	doorsFolder.Parent = model

	local doors: { BasePart } = {}

	for _, geometry in SIDES do
		local state = room.sides[geometry.side]
		local sideCenter = center + geometry.offset

		if state == "SolidWall" then
			newPart(string.format("Wall_%s", geometry.side), geometry.wallSize, sideCenter, WALL_COLOR, walls)
			continue
		end

		-- Hay abertura: dos segmentos y un hueco de DOOR_GAP en el medio.
		newPart(
			string.format("Wall_%s_A", geometry.side),
			geometry.segmentSize,
			sideCenter + geometry.along * SEGMENT_OFFSET,
			WALL_COLOR,
			walls
		)
		newPart(
			string.format("Wall_%s_B", geometry.side),
			geometry.segmentSize,
			sideCenter - geometry.along * SEGMENT_OFFSET,
			WALL_COLOR,
			walls
		)

		if state == "Door" then
			local door = newPart(
				string.format("Door_%s", geometry.side),
				geometry.doorSize,
				sideCenter,
				DOOR_COLOR,
				doorsFolder
			)

			door.Material = Enum.Material.Neon
			door:SetAttribute("Side", geometry.side)
			RoomBuilder.setDoorClosed(door, false)

			table.insert(doors, door)
		end
	end

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "SpawnPoints"
	spawnFolder.Parent = model

	local spawnPoints = buildSpawnPoints(spawnFolder, center)

	-- Los Attributes son el contrato con RoomService y con cualquier prefab hecho a
	-- mano: una sala construida en Studio solo necesita estos mismos atributos.
	model:SetAttribute("RoomType", room.kind)
	model:SetAttribute("GridX", room.x)
	model:SetAttribute("GridY", room.y)
	model:SetAttribute("DistanceFromStart", room.distanceFromStart)
	model:SetAttribute("FloorNumber", floorNumber)

	model.Parent = parent
	CollectionService:AddTag(model, Tags.Room)

	return {
		model = model,
		floor = floor,
		doors = doors,
		spawnPoints = spawnPoints,
		center = center,
	}
end

return table.freeze(RoomBuilder)

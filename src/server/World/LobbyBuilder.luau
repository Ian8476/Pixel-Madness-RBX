--!strict
--[[
	LobbyBuilder: la sala del lobby, construida por codigo.

	Misma decision que `RoomBuilder` y que `LightingService`: si vive en el `.rbxl` no
	hay diff y el place deja de ser reconstruible desde el repo. Un lobby de verdad,
	con maniquies y tablero de records, es de la Fase 7; este es el greybox donde
	esperar, elegir personaje y decir listo.

	Es una sala CERRADA y sin puertas a proposito. Mientras esperas no hay nada que
	explorar, y una salida abierta invita a irse caminando a un vacio de 600 studs.

	Las tres plataformas de colores no son decoracion gratuita: son la unica pista
	dentro del mundo de que hay tres personajes. La eleccion sigue siendo por UI (el
	panel tiene stats y flavor, que una plataforma no puede mostrar), pero pararse
	sobre una y ver de que color es hace que el juego se explique solo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Data.Characters)
local Constants = require(Shared.Constants)

local CONTAINER_NAME = "Lobby"
local SIZE = Constants.LOBBY_SIZE_STUDS
local HALF = SIZE / 2
local WALL_HEIGHT = Constants.WALL_HEIGHT_STUDS
local WALL_THICKNESS = Constants.WALL_THICKNESS_STUDS

local FLOOR_COLOR = Color3.fromRGB(88, 84, 100)
local WALL_COLOR = Color3.fromRGB(104, 99, 120)
local PLATFORM_SIZE = Vector3.new(10, 1.5, 10)
local PLATFORM_SPACING = 16
local PLATFORM_OFFSET_Z = 18

local LobbyBuilder = {}

local container: Folder? = nil

local function origin(): Vector3
	local point = Constants.LOBBY_ORIGIN

	return Vector3.new(point.x, point.y, point.z)
end

--[[ Donde aparecen los jugadores: el centro, un poco elevado. ]]
function LobbyBuilder.getSpawnPosition(): Vector3
	return origin() + Vector3.new(0, 4, -8)
end

local function newPart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")

	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.Slate
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

--[[ Construye el lobby. Idempotente: reconstruirlo reemplaza al anterior. ]]
function LobbyBuilder.build(): Folder
	local existing = workspace:FindFirstChild(CONTAINER_NAME)

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = workspace

	container = folder

	local center = origin()

	newPart(
		"Floor",
		Vector3.new(SIZE, Constants.FLOOR_THICKNESS_STUDS, SIZE),
		center - Vector3.new(0, Constants.FLOOR_THICKNESS_STUDS / 2, 0),
		FLOOR_COLOR,
		folder
	)

	local edge = HALF - WALL_THICKNESS / 2
	local horizontal = Vector3.new(SIZE, WALL_HEIGHT, WALL_THICKNESS)
	local vertical = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, SIZE)

	newPart("Wall_North", horizontal, center + Vector3.new(0, WALL_HEIGHT / 2, edge), WALL_COLOR, folder)
	newPart("Wall_South", horizontal, center + Vector3.new(0, WALL_HEIGHT / 2, -edge), WALL_COLOR, folder)
	newPart("Wall_East", vertical, center + Vector3.new(edge, WALL_HEIGHT / 2, 0), WALL_COLOR, folder)
	newPart("Wall_West", vertical, center + Vector3.new(-edge, WALL_HEIGHT / 2, 0), WALL_COLOR, folder)

	--[[
		Una plataforma por personaje, con su color, en el mismo orden en que aparecen
		las tarjetas del panel de seleccion.

		EL EJE X SE RECORRE AL REVES A PROPOSITO. La camara top-down mira hacia +Z
		(su offset es z = -28), asi que en pantalla el +X queda a la IZQUIERDA. Sin
		invertir, las plataformas salian espejadas respecto de las tarjetas y el
		jugador veia un orden en el mundo y el contrario en la UI.
	]]
	local total = #Characters.all
	local firstX = -(total - 1) * PLATFORM_SPACING / 2

	for index, definition in Characters.all do
		local color = Color3.fromRGB(definition.greyboxColor.r, definition.greyboxColor.g, definition.greyboxColor.b)

		newPart(
			string.format("Platform_%s", definition.id),
			PLATFORM_SIZE,
			center + Vector3.new(firstX + (total - index) * PLATFORM_SPACING, PLATFORM_SIZE.Y / 2, PLATFORM_OFFSET_Z),
			color,
			folder
		)
	end

	return folder
end

function LobbyBuilder.clear(): ()
	if container then
		container:Destroy()
		container = nil
	end
end

return table.freeze(LobbyBuilder)

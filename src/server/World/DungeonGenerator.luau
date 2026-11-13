--!strict
--[[
	DungeonGenerator: convierte el plano de `DungeonLayout` en un piso jugable.

	Reparto de responsabilidades, que es lo unico interesante de este archivo:

	  DungeonLayout  decide QUE piso (puro, testeado en CI, sin Instances)
	  RoomBuilder    decide COMO se ve una sala (geometria)
	  DungeonGenerator  las conecta, siembra el contenido y limpia el piso anterior
	  RoomService    recuerda lo que quedo construido

	Nada de esto sabe de combate: la sala trae sus puntos de spawn y sus puertas, pero
	quien pone enemigos adentro y cuando se cierra es RoomService.

	Sobre la semilla: si no se pasa una, se sortea. La semilla se loguea SIEMPRE y se
	guarda como Attribute del piso, porque el dia que alguien reporte "me quede
	encerrado en el piso 2", el unico dato que reproduce el bug es ese numero.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Constants = require(Shared.Constants)
local DifficultyMath = require(Shared.Logic.DifficultyMath)
local DungeonLayout = require(Shared.Logic.DungeonLayout)
local Logger = require(Shared.Logger)
local Rng = require(Shared.Logic.Rng)
local Tags = require(Shared.Tags)
local Weapons = require(Shared.Data.Weapons)

local EnemySystem = require(script.Parent.Parent.Enemies.EnemySystem)
local LootService = require(script.Parent.LootService)
local PickupService = require(script.Parent.PickupService)
local RoomBuilder = require(script.Parent.RoomBuilder)
local RoomService = require(script.Parent.RoomService)

local CONTAINER_NAME = "Dungeon"
local SPAWN_HEIGHT_STUDS = 4
-- Cuidado con el orden de los ejes: en un Part cilindrico de Roblox, X es el EJE del
-- cilindro y las otras dos son el diametro. O sea que esto es un disco de 14 de
-- diametro y 1.5 de espesor, no una columna. Si Y y Z no son iguales, sale una elipse.
local PORTAL_SIZE = Vector3.new(1.5, 14, 14)
local PORTAL_COLOR = Color3.fromRGB(198, 120, 255)
-- Dos armas por sala de objetos: una sola vuelve la sala una loteria de "me salio la
-- que ya tenia"; dos convierten el desvio en una eleccion.
local WEAPONS_PER_ITEM_ROOM = 2

-- FASE 4: el jefe ya no lo planta el generador. La sala del Jefe spawnea a El Bonkaron
-- como un enemigo de verdad cuando el jugador entra (RoomService), igual que cualquier
-- sala de combate. El saco de golpes anclado de la Fase 3 se fue con su codigo.

export type GeneratedFloor = {
	floorNumber: number,
	seed: number,
	layout: DungeonLayout.Layout,
	startPosition: Vector3,
	portal: BasePart?,
	bossRoomCenter: Vector3?,
}

local log = Logger.new("DungeonGenerator")

local DungeonGenerator = {
	name = "DungeonGenerator",
}

local container: Folder? = nil
local seedSource = Random.new()

local function getContainer(): Folder
	if container and container.Parent then
		return container
	end

	local existing = workspace:FindFirstChild(CONTAINER_NAME)

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = workspace

	container = folder

	return folder
end

local function buildPortal(center: Vector3, parent: Instance): BasePart
	local portal = Instance.new("Part")

	portal.Name = "Portal"
	portal.Shape = Enum.PartType.Cylinder
	portal.Size = PORTAL_SIZE
	-- El cilindro de Roblox nace acostado sobre X: se para con una rotacion en Z.
	portal.CFrame = CFrame.new(center + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	portal.Color = PORTAL_COLOR
	portal.Material = Enum.Material.Neon
	portal.Anchored = true
	portal.CanCollide = false
	portal.CanQuery = false
	portal.CanTouch = false
	portal.Parent = parent

	CollisionGroups.applyToModel(portal, CollisionGroups.Names.Ghost)
	CollectionService:AddTag(portal, Tags.Portal)

	return portal
end

local function seedItemRoom(center: Vector3, rng: Rng.Rng): ()
	local ids = rng:shuffled(Weapons.ids)
	local count = math.min(WEAPONS_PER_ITEM_ROOM, #ids)
	local spacing = 8
	local firstX = -(count - 1) * spacing / 2

	for index = 1, count do
		PickupService.spawnWeaponPickup(ids[index], center + Vector3.new(firstX + (index - 1) * spacing, 2.5, 0))
	end
end

--[[
	Destruye el piso actual. Se llama antes de generar el siguiente y al terminar la
	run: dejar el piso viejo colgando es la forma mas facil de duplicar enemigos y de
	que el jugador vea dos portales.
]]
function DungeonGenerator.clear(): ()
	if container then
		container:Destroy()
		container = nil
	end

	RoomService.clear()

	-- Pickups, enemigos y monedas NO cuelgan de la carpeta del piso (viven en sus
	-- propios contenedores en workspace), asi que hay que borrarlos aparte. Sin esto,
	-- lo que quedo del piso 1 reaparece flotando dentro del piso 2: todos los pisos se
	-- construyen sobre el mismo origen.
	PickupService.clearAll()
	EnemySystem.despawnAll()
	LootService.clearAll()
end

--[[ Genera el piso `floorNumber`. Sin semilla, sortea una. ]]
function DungeonGenerator.generate(floorNumber: number, seed: number?): GeneratedFloor
	DungeonGenerator.clear()

	local resolvedSeed = seed or seedSource:NextInteger(1, 2 ^ 31 - 1)
	local rng = Rng.new(resolvedSeed)

	local layout = DungeonLayout.generate({
		floorNumber = floorNumber,
		roomCount = DifficultyMath.roomCountForFloor(floorNumber, Constants.BASE_ROOM_COUNT),
		isFinalFloor = floorNumber >= Constants.FLOORS_PER_RUN,
	}, function(minimum: number, maximum: number): number
		return rng:nextInteger(minimum, maximum)
	end)

	local parent = getContainer()

	parent:SetAttribute("Seed", resolvedSeed)
	parent:SetAttribute("FloorNumber", floorNumber)

	-- El seed viaja a RoomService para que la COMPOSICION de enemigos de cada sala sea
	-- tan reproducible como el plano: misma semilla, mismo piso y mismos bichos.
	RoomService.beginFloor(floorNumber, resolvedSeed)

	local startPosition = Vector3.zero
	local portal: BasePart? = nil
	local bossRoomCenter: Vector3? = nil

	for _, node in layout.rooms do
		local built = RoomBuilder.build(node, floorNumber, parent)

		RoomService.register(built, node)

		if node.kind == "Start" then
			startPosition = built.center + Vector3.new(0, SPAWN_HEIGHT_STUDS, 0)
		elseif node.kind == "Item" then
			seedItemRoom(built.center, rng)
		elseif node.kind == "Portal" then
			portal = buildPortal(built.center, built.model)
		elseif node.kind == "Boss" then
			bossRoomCenter = built.center
		end
	end

	log:info(
		"Piso %d generado. Semilla %d, %d salas (%s)",
		floorNumber,
		resolvedSeed,
		#layout.rooms,
		RoomService.describe()
	)

	return {
		floorNumber = floorNumber,
		seed = resolvedSeed,
		layout = layout,
		startPosition = startPosition,
		portal = portal,
		bossRoomCenter = bossRoomCenter,
	}
end

return DungeonGenerator

--!strict
--[[
	RoomService: el registro de las salas del piso Y el ciclo de vida de la sala de
	combate, que es el bucle de presion del juego: entrar, encerrarse, limpiar, avanzar.

	NO hay un Script por sala (reglas 3 y 7): hay una tabla y un servicio.

	--------------------------------------------------------------------------------
	EL CICLO
	--------------------------------------------------------------------------------

	  1. Cada 1/5 de segundo se mira en que sala esta cada jugador vivo.
	  2. Si alguno entro a una sala de Combate o de Jefe sin limpiar, la sala se ACTIVA:
	     se cierran las puertas PARA TODOS y se spawnean los enemigos escalados.
	  3. Cuando no queda ningun enemigo vivo de esa sala, se abre y se marca limpia.
	  4. Una sala limpia no vuelve a cerrarse nunca.

	El paso 4 no es un detalle: es la salvaguarda contra el bug clasico del genero, que
	es volver a entrar a una sala ya limpiada y quedar encerrado sin nada que matar. La
	guarda vive en `setLocked`, o sea en el UNICO lugar que cierra puertas, y no en cada
	llamador.

	Y hay una segunda salvaguarda para el otro caso feo, el que el plan pide cubrir
	explicitamente: un enemigo que se cae de la sala, que se destruye por otro camino o
	que nunca llego a existir. En cada tick, una sala cerrada SIN enemigos vivos se
	abre. Da igual por que desaparecieron: si no hay a quien matar, la puerta se abre.
	Preferimos abrir de mas que dejar a alguien encerrado.

	--------------------------------------------------------------------------------

	Deteccion por comparacion de caja y no por `Touched` ni `GetPartBoundsInBox`: las
	salas son una grilla regular, asi que saber en cual estas es aritmetica. Esto corre
	por jugador y por tick, y una consulta al motor de fisica costaria muchisimo mas
	que dos restas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local DifficultyMath = require(Shared.Logic.DifficultyMath)
local DungeonLayout = require(Shared.Logic.DungeonLayout)
local Enemies = require(Shared.Data.Enemies)
local Logger = require(Shared.Logger)
local Rng = require(Shared.Logic.Rng)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local EnemySystem = require(script.Parent.Parent.Enemies.EnemySystem)
local RoomBuilder = require(script.Parent.RoomBuilder)

local HALF_ROOM = Constants.ROOM_SIZE_STUDS / 2

export type Room = {
	key: string, -- "gridX:gridY"
	model: Model,
	kind: DungeonLayout.RoomKind,
	gridX: number,
	gridY: number,
	distanceFromStart: number,
	center: Vector3,
	doors: { BasePart },
	spawnPoints: { BasePart },
	isLocked: boolean,
	isCleared: boolean,
}

local log = Logger.new("RoomService")

local RoomService = {
	name = "RoomService",
}

local rooms: { Room } = {}
local roomsByKey: { [string]: Room } = {}
local floorNumber = 1
local floorSeed = 1
local heartbeatConnection: RBXScriptConnection? = nil
local accumulator = 0

local function makeKey(gridX: number, gridY: number): string
	return string.format("%d:%d", gridX, gridY)
end

--------------------------------------------------------------------------------
-- Registro
--------------------------------------------------------------------------------

--[[ Prepara el registro para un piso nuevo. Lo llama DungeonGenerator antes de construir. ]]
function RoomService.beginFloor(newFloorNumber: number, seed: number): ()
	table.clear(rooms)
	table.clear(roomsByKey)

	floorNumber = newFloorNumber
	floorSeed = seed
end

function RoomService.register(built: RoomBuilder.BuiltRoom, node: DungeonLayout.RoomNode): Room
	local room: Room = {
		key = makeKey(node.x, node.y),
		model = built.model,
		kind = node.kind,
		gridX = node.x,
		gridY = node.y,
		distanceFromStart = node.distanceFromStart,
		center = built.center,
		doors = built.doors,
		spawnPoints = built.spawnPoints,
		isLocked = false,
		isCleared = false,
	}

	table.insert(rooms, room)
	roomsByKey[room.key] = room

	return room
end

function RoomService.clear(): ()
	table.clear(rooms)
	table.clear(roomsByKey)
end

function RoomService.getAll(): { Room }
	return rooms
end

function RoomService.getFirstOfKind(kind: DungeonLayout.RoomKind): Room?
	for _, room in rooms do
		if room.kind == kind then
			return room
		end
	end

	return nil
end

function RoomService.getRoomContaining(position: Vector3): Room?
	for _, room in rooms do
		if
			math.abs(position.X - room.center.X) <= HALF_ROOM
			and math.abs(position.Z - room.center.Z) <= HALF_ROOM
		then
			return room
		end
	end

	return nil
end

--[[ Resumen del piso para el log del generador. ]]
function RoomService.describe(): string
	local counts: { [string]: number } = {}

	for _, room in rooms do
		counts[room.kind] = (counts[room.kind] or 0) + 1
	end

	local parts: { string } = {}

	for kind, count in counts do
		table.insert(parts, string.format("%s x%d", kind, count))
	end

	table.sort(parts)

	return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Puertas
--------------------------------------------------------------------------------

--[[
	Abre o cierra TODAS las puertas de la sala.

	Una sala ya limpiada NUNCA se vuelve a cerrar. El chequeo vive aca, en el unico
	lugar del proyecto que cierra puertas, y no repartido en cada llamador.
]]
function RoomService.setLocked(room: Room, locked: boolean): ()
	if locked and room.isCleared then
		return
	end

	if room.isLocked == locked then
		return
	end

	room.isLocked = locked

	for _, door in room.doors do
		RoomBuilder.setDoorClosed(door, locked)
	end
end

--[[ Marca la sala como limpiada y abre sus puertas. Irreversible a proposito. ]]
function RoomService.markCleared(room: Room): ()
	if room.isCleared then
		return
	end

	room.isCleared = true

	RoomService.setLocked(room, false)
end

--------------------------------------------------------------------------------
-- Activacion
--------------------------------------------------------------------------------

local function pickSpawnPositions(room: Room, count: number, rng: Rng.Rng): { Vector3 }
	local positions: { Vector3 } = {}

	if #room.spawnPoints == 0 then
		for _ = 1, count do
			table.insert(positions, room.center)
		end

		return positions
	end

	-- Se baraja para que dos salas con la misma cantidad de enemigos no los pongan
	-- siempre en el mismo orden de puntos; si hay mas enemigos que puntos, se da la
	-- vuelta y se reparte de nuevo.
	local shuffled = rng:shuffled(room.spawnPoints)

	for index = 1, count do
		local point = shuffled[(index - 1) % #shuffled + 1]

		table.insert(positions, point.Position)
	end

	return positions
end

--[[
	Enciende la sala: encierra y puebla.

	La composicion sale de un Rng sembrado con el seed del piso y las coordenadas de la
	sala, o sea que es REPRODUCIBLE: la misma semilla da el mismo piso Y los mismos
	bichos en las mismas salas. Sin eso, reproducir el reporte "el piso 2 era imposible"
	no serviria de nada.
]]
local function activate(room: Room): ()
	RoomService.setLocked(room, true)

	local playerCount = math.max(1, #Players:GetPlayers())

	if room.kind == "Boss" then
		local boss = Enemies.expect(Enemies.bossId)

		EnemySystem.spawn(boss, room.center, {
			floorNumber = floorNumber,
			playerCount = playerCount,
			roomKey = room.key,
		})

		log:info("Sala del jefe activada (piso %d, %d jugadores)", floorNumber, playerCount)

		return
	end

	local rng = Rng.new(floorSeed + room.gridX * 73856093 + room.gridY * 19349663)
	local count = DifficultyMath.enemyCountForRoom(Constants.BASE_ENEMIES_PER_COMBAT_ROOM, floorNumber, playerCount)
	local positions = pickSpawnPositions(room, count, rng)

	for index = 1, count do
		local definition = Enemies.expect(rng:pick(Enemies.combatPool))

		EnemySystem.spawn(definition, positions[index], {
			floorNumber = floorNumber,
			playerCount = playerCount,
			roomKey = room.key,
		})
	end

	log:info("Sala %s activada: %d enemigos (piso %d)", room.key, count, floorNumber)
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

local function shouldActivate(room: Room): boolean
	return not room.isCleared and not room.isLocked and (room.kind == "Combat" or room.kind == "Boss")
end

local function step(deltaTime: number): ()
	accumulator += deltaTime

	if accumulator < 1 / Constants.ROOM_CHECK_HZ then
		return
	end

	accumulator = 0

	if #rooms == 0 then
		return
	end

	-- 1. Activar las salas en las que entro alguien vivo.
	for _, player in Players:GetPlayers() do
		if not CharacterService.isAlive(player) then
			continue
		end

		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

		if not root or not root:IsA("BasePart") then
			continue
		end

		local room = RoomService.getRoomContaining(root.Position)

		if room and shouldActivate(room) then
			activate(room)
		end
	end

	-- 2. Abrir las que ya no tienen a quien matar.
	--    Da igual COMO desaparecieron los enemigos: si no queda ninguno vivo, la
	--    puerta se abre. Es la red que evita dejar a alguien encerrado para siempre.
	for _, room in rooms do
		if room.isLocked and EnemySystem.countAliveInRoom(room.key) == 0 then
			RoomService.markCleared(room)
			log:info("Sala %s limpiada", room.key)
		end
	end
end

function RoomService.start(): ()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(step)
end

return RoomService

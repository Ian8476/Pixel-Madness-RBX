--!strict
--[[
	DungeonLayout: el algoritmo de la mazmorra. Datos entran, datos salen.

	Este modulo NO crea una sola Instance. Recibe cuantas salas quiere el piso y una
	fuente de azar, y devuelve el plano: que celdas de la grilla estan ocupadas, que
	tipo es cada sala y como esta cada uno de sus cuatro lados. Quien lo convierte en
	paredes es `server/World/DungeonGenerator`.

	Esa separacion es el motivo por el que la Fase 3 del plan se puede testear en CI sin
	abrir Studio: aca vive TODA la logica que puede estar mal (salas encimadas, un piso
	sin salida, dos jefes, una sala inalcanzable) y ninguna de las cosas que solo se
	pueden mirar (que la pared se vea bien).

	El azar se INYECTA como funcion (`nextInteger`) igual que en SpreadMath, en vez de
	usar `Random` o de importar nuestro `Rng`: la regla de la carpeta prohibe `require`
	porque Lune y Roblox resuelven las rutas distinto. Quien llama arma el Rng con la
	semilla que quiera; con la misma semilla, este modulo devuelve siempre el mismo plano.

	--------------------------------------------------------------------------------
	EL ALGORITMO (heredado del prototipo Unity, traducido sin cambios de diseno)
	--------------------------------------------------------------------------------

	Caminata aleatoria sobre una grilla infinita empezando en (0, 0):

	  1. Se elige una direccion al azar desde la sala actual.
	  2. Si la celda vecina YA tiene sala, se camina hasta ella (no se crea nada).
	  3. Si esta vacia y tiene COMO MUCHO UN VECINO ocupado, se crea la sala ahi.
	  4. Si esta vacia pero tocaria dos o mas salas, se descarta y se salta a una sala
	     ya creada al azar para seguir desde otro lado.

	La regla 3 es la importante y merece su parrafo. Sin ella, la caminata rellena
	bloques de 2x2 y el piso queda como una mancha: salas pegadas por dos lados, sin
	pasillos y sin sensacion de recorrido. Con ella, cada sala nueva toca exactamente
	una sala vieja, y eso tiene una consecuencia geometrica gratis y muy util: el mapa
	resultante es un ARBOL. No hay ciclos, no hay dos caminos al mismo lugar, y por lo
	tanto "la sala mas lejana" esta bien definida y siempre hay callejones sin salida
	donde poner recompensas.

	Despues de la caminata:

	  - BFS desde la sala inicial para saber a que distancia esta cada sala.
	  - La MAS LEJANA es la salida: Portal en los pisos intermedios, Jefe en el ultimo.
	    (Asi la salida nunca cae al lado del spawn, que es el bug clasico de este tipo
	    de generador y convierte un piso entero en dos pasos.)
	  - De los callejones sin salida restantes, uno es la sala de objetos.
	  - Todo lo demas son salas de combate.

	Los lados se resuelven aca y no en el generador porque son una decision de DISENO,
	no de construccion: las salas que nunca encierran al jugador (Inicio y Objetos)
	llevan `OpenWall` donde las demas llevan `Door`.
]]

--------------------------------------------------------------------------------
-- Tipos (propios: la carpeta no puede importar Types.luau)
--------------------------------------------------------------------------------

export type RoomKind = "Start" | "Combat" | "Item" | "Portal" | "Boss"
export type Side = "North" | "South" | "East" | "West"
export type SideState = "SolidWall" | "OpenWall" | "Door"

export type RoomSides = {
	North: SideState,
	South: SideState,
	East: SideState,
	West: SideState,
}

export type RoomNode = {
	x: number, -- celda de la grilla, no studs
	y: number,
	kind: RoomKind,
	distanceFromStart: number,
	connections: number, -- 1 = callejon sin salida
	sides: RoomSides,
}

export type Layout = {
	floorNumber: number,
	roomCount: number,
	rooms: { RoomNode },
	startIndex: number,
	exitIndex: number, -- Portal o Boss, segun el piso
}

export type LayoutConfig = {
	floorNumber: number,
	roomCount: number,
	isFinalFloor: boolean, -- true = la salida es el Jefe en vez del Portal
}

type Direction = {
	side: Side,
	dx: number,
	dy: number,
}

--------------------------------------------------------------------------------

-- El orden importa: fija el recorrido del BFS y por lo tanto que sala gana un empate
-- de distancia. Cambiarlo cambia las mazmorras de todas las semillas existentes.
local DIRECTIONS: { Direction } = {
	{ side = "North", dx = 0, dy = 1 },
	{ side = "South", dx = 0, dy = -1 },
	{ side = "East", dx = 1, dy = 0 },
	{ side = "West", dx = -1, dy = 0 },
}

-- Presupuesto de intentos de la caminata. Con la regla anti-bloque, un intento de cada
-- dos o tres crea sala; 200 por sala es un margen absurdo a proposito, porque el error
-- que dispara es "el algoritmo se colgo", no "esta semilla tuvo mala suerte".
local ATTEMPTS_PER_ROOM = 200

local DungeonLayout = {}

local function cellKey(x: number, y: number): string
	return string.format("%d:%d", x, y)
end

local function assertPositiveInteger(value: number, label: string): ()
	if value ~= value or value < 1 or value % 1 ~= 0 then
		error(string.format("DungeonLayout: %s debe ser un entero >= 1, recibido %s", label, tostring(value)), 3)
	end
end

--------------------------------------------------------------------------------
-- Paso 1: caminata aleatoria
--------------------------------------------------------------------------------

type WorkingRoom = {
	x: number,
	y: number,
	kind: RoomKind,
	distanceFromStart: number,
	connections: number,
	sides: RoomSides,
}

local function walk(
	roomCount: number,
	nextInteger: (minimum: number, maximum: number) -> number
): ({ WorkingRoom }, { [string]: number })
	local rooms: { WorkingRoom } = {}
	local indexByCell: { [string]: number } = {}

	local function place(x: number, y: number): number
		local index = #rooms + 1

		rooms[index] = {
			x = x,
			y = y,
			kind = "Combat",
			distanceFromStart = 0,
			connections = 0,
			sides = { North = "SolidWall", South = "SolidWall", East = "SolidWall", West = "SolidWall" },
		}

		indexByCell[cellKey(x, y)] = index

		return index
	end

	local function occupiedNeighborCount(x: number, y: number): number
		local count = 0

		for _, direction in DIRECTIONS do
			if indexByCell[cellKey(x + direction.dx, y + direction.dy)] then
				count += 1
			end
		end

		return count
	end

	place(0, 0)

	local current = 1
	local attempts = 0
	local maxAttempts = roomCount * ATTEMPTS_PER_ROOM

	while #rooms < roomCount do
		attempts += 1

		if attempts > maxAttempts then
			error(
				string.format(
					"DungeonLayout: la caminata no logro colocar %d salas en %d intentos. Es un bug del algoritmo, no mala suerte.",
					roomCount,
					maxAttempts
				),
				0
			)
		end

		local direction = DIRECTIONS[nextInteger(1, #DIRECTIONS)]
		local room = rooms[current]
		local x, y = room.x + direction.dx, room.y + direction.dy
		local existing = indexByCell[cellKey(x, y)]

		if existing then
			-- Ya hay sala: se camina hasta ella y se sigue desde ahi.
			current = existing
		elseif occupiedNeighborCount(x, y) <= 1 then
			-- El unico vecino ocupado es la sala de la que venimos: regla anti-bloque.
			current = place(x, y)
		else
			-- Tocaria dos salas: se descarta y se reanuda desde otra sala cualquiera.
			-- Sin este salto, una caminata acorralada gira en el mismo rincon hasta
			-- agotar los intentos.
			current = nextInteger(1, #rooms)
		end
	end

	return rooms, indexByCell
end

--------------------------------------------------------------------------------
-- Paso 2: conexiones y distancias
--------------------------------------------------------------------------------

local function linkAndMeasure(rooms: { WorkingRoom }, indexByCell: { [string]: number }): ()
	for _, room in rooms do
		local connections = 0

		for _, direction in DIRECTIONS do
			if indexByCell[cellKey(room.x + direction.dx, room.y + direction.dy)] then
				connections += 1
			end
		end

		room.connections = connections
	end

	-- BFS desde la sala inicial. Como el mapa es un arbol, la distancia en saltos es
	-- tambien la longitud del unico camino que existe hasta cada sala.
	local queue = { 1 }
	local visited: { [number]: boolean } = { [1] = true }
	local head = 1

	while head <= #queue do
		local index = queue[head]
		head += 1

		local room = rooms[index]

		for _, direction in DIRECTIONS do
			local neighborIndex = indexByCell[cellKey(room.x + direction.dx, room.y + direction.dy)]

			if neighborIndex and not visited[neighborIndex] then
				visited[neighborIndex] = true
				rooms[neighborIndex].distanceFromStart = room.distanceFromStart + 1
				table.insert(queue, neighborIndex)
			end
		end
	end

	if #queue ~= #rooms then
		-- Imposible con la regla anti-bloque (cada sala nace pegada a otra), pero si
		-- alguien toca la caminata, este error aparece antes que un jugador atrapado.
		error(
			string.format("DungeonLayout: %d salas quedaron inalcanzables desde el inicio", #rooms - #queue),
			0
		)
	end
end

--------------------------------------------------------------------------------
-- Paso 3: repartir tipos de sala
--------------------------------------------------------------------------------

local function findExitIndex(rooms: { WorkingRoom }): number
	local exitIndex = 1
	local bestDistance = -1

	for index, room in rooms do
		-- Comparacion ESTRICTA: en un empate gana la sala colocada primero, y eso hace
		-- que el resultado dependa solo de la semilla y no del orden de iteracion.
		if room.distanceFromStart > bestDistance then
			bestDistance = room.distanceFromStart
			exitIndex = index
		end
	end

	return exitIndex
end

local function assignKinds(
	rooms: { WorkingRoom },
	exitIndex: number,
	isFinalFloor: boolean,
	nextInteger: (minimum: number, maximum: number) -> number
): ()
	rooms[1].kind = "Start"
	rooms[exitIndex].kind = if isFinalFloor then "Boss" else "Portal"

	local deadEnds: { number } = {}

	for index, room in rooms do
		if index ~= 1 and index ~= exitIndex and room.connections == 1 then
			table.insert(deadEnds, index)
		end
	end

	-- Una sala de objetos por piso, en un callejon sin salida: la recompensa se gana
	-- desviandose del camino, no tropezandose con ella.
	if #deadEnds > 0 then
		rooms[deadEnds[nextInteger(1, #deadEnds)]].kind = "Item"
	end
end

--------------------------------------------------------------------------------
-- Paso 4: lados
--------------------------------------------------------------------------------

local function resolveSides(rooms: { WorkingRoom }, indexByCell: { [string]: number }): ()
	for _, room in rooms do
		-- Inicio y Objetos NUNCA encierran al jugador (regla de diseno del documento
		-- de contexto), asi que sus aberturas no llevan puerta.
		local neverLocks = room.kind == "Start" or room.kind == "Item"
		local openState: SideState = if neverLocks then "OpenWall" else "Door"

		for _, direction in DIRECTIONS do
			if indexByCell[cellKey(room.x + direction.dx, room.y + direction.dy)] then
				room.sides[direction.side] = openState
			end
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--[[
	Genera el plano de un piso.

	`nextInteger(min, max)` es la unica fuente de azar: pasale
	`function(a, b) return rng:nextInteger(a, b) end` con un `Shared/Logic/Rng`
	sembrado, y la misma semilla dara siempre el mismo piso.
]]
function DungeonLayout.generate(
	config: LayoutConfig,
	nextInteger: (minimum: number, maximum: number) -> number
): Layout
	assertPositiveInteger(config.floorNumber, "floorNumber")
	assertPositiveInteger(config.roomCount, "roomCount")

	if config.roomCount < 2 then
		error("DungeonLayout: un piso necesita al menos 2 salas (inicio y salida)", 2)
	end

	local rooms, indexByCell = walk(config.roomCount, nextInteger)

	linkAndMeasure(rooms, indexByCell)

	local exitIndex = findExitIndex(rooms)

	assignKinds(rooms, exitIndex, config.isFinalFloor, nextInteger)
	resolveSides(rooms, indexByCell)

	local frozenRooms: { RoomNode } = table.create(#rooms)

	for _, room in rooms do
		room.sides = table.freeze(room.sides)
		table.insert(frozenRooms, table.freeze(room) :: RoomNode)
	end

	return table.freeze({
		floorNumber = config.floorNumber,
		roomCount = config.roomCount,
		rooms = table.freeze(frozenRooms),
		startIndex = 1,
		exitIndex = exitIndex,
	})
end

--[[ Sala en una celda concreta, o nil. Recorrido lineal: hay menos de 10 salas por piso. ]]
function DungeonLayout.findRoomAt(layout: Layout, x: number, y: number): RoomNode?
	for _, room in layout.rooms do
		if room.x == x and room.y == y then
			return room
		end
	end

	return nil
end

--[[ Cuantas salas de un tipo hay. Lo usan los tests y el log del generador. ]]
function DungeonLayout.countKind(layout: Layout, kind: RoomKind): number
	local count = 0

	for _, room in layout.rooms do
		if room.kind == kind then
			count += 1
		end
	end

	return count
end

return table.freeze(DungeonLayout)

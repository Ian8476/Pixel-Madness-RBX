--!strict
--[[
	Tests del generador de mazmorras. Este es el archivo que la Fase 3 del plan pide
	explicitamente ("los tests de layout pasan en CI") y el que evita el peor bug
	posible del juego: un piso del que no se puede salir.

	Estrategia: en vez de comprobar un piso concreto (que dependeria de la semilla y se
	romperia al tocar cualquier cosa), se comprueban INVARIANTES sobre muchas semillas.
	Si una sola de las 60 mazmorras generadas tiene dos jefes, una sala encimada o una
	celda inalcanzable, el CI lo dice y ademas dice con que semilla pasa.
]]

local DungeonLayout = require("../../src/shared/Logic/DungeonLayout")
local Rng = require("../../src/shared/Logic/Rng")

local SEEDS_UNDER_TEST = 60

local function makeRandom(seed: number): (minimum: number, maximum: number) -> number
	local rng = Rng.new(seed)

	return function(minimum: number, maximum: number): number
		return rng:nextInteger(minimum, maximum)
	end
end

local function generate(seed: number, roomCount: number, isFinalFloor: boolean): any
	return DungeonLayout.generate({
		floorNumber = if isFinalFloor then 3 else 1,
		roomCount = roomCount,
		isFinalFloor = isFinalFloor,
	}, makeRandom(seed))
end

--[[ Recorre muchas semillas y falla nombrando la que rompio. ]]
local function forEachSeed(roomCount: number, isFinalFloor: boolean, check: (layout: any, seed: number) -> string?): ()
	for seed = 1, SEEDS_UNDER_TEST do
		local layout = generate(seed, roomCount, isFinalFloor)
		local problem = check(layout, seed)

		if problem then
			error(string.format("semilla %d: %s", seed, problem), 0)
		end
	end
end

local DIRECTIONS = {
	{ side = "North", dx = 0, dy = 1 },
	{ side = "South", dx = 0, dy = -1 },
	{ side = "East", dx = 1, dy = 0 },
	{ side = "West", dx = -1, dy = 0 },
}

local function cellSet(layout: any): { [string]: boolean }
	local cells: { [string]: boolean } = {}

	for _, room in layout.rooms do
		cells[string.format("%d:%d", room.x, room.y)] = true
	end

	return cells
end

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("DungeonLayout: reproducibilidad", function()
		-- El motivo practico: cuando alguien reporte "el piso 2 me dejo encerrado",
		-- la semilla del log tiene que reproducir el bug exactamente.
		it("la misma semilla da el mismo piso", function()
			expect(generate(2024, 8, false)).toEqual(generate(2024, 8, false))
		end)

		it("semillas distintas dan pisos distintos", function()
			local a = generate(1, 8, false)
			local b = generate(2, 8, false)
			local identical = true

			for index, room in a.rooms do
				local other = b.rooms[index]

				if not other or other.x ~= room.x or other.y ~= room.y or other.kind ~= room.kind then
					identical = false
					break
				end
			end

			expect(identical).toBe(false)
		end)
	end)

	describe("DungeonLayout: forma del piso", function()
		it("crea exactamente las salas pedidas", function()
			for _, roomCount in { 2, 7, 8, 9, 15 } do
				forEachSeed(roomCount, false, function(layout)
					if #layout.rooms ~= roomCount then
						return string.format("esperaba %d salas, hay %d", roomCount, #layout.rooms)
					end

					return nil
				end)
			end
		end)

		it("nunca encima dos salas en la misma celda", function()
			forEachSeed(9, false, function(layout)
				local seen: { [string]: boolean } = {}

				for _, room in layout.rooms do
					local key = string.format("%d:%d", room.x, room.y)

					if seen[key] then
						return string.format("celda repetida %s", key)
					end

					seen[key] = true
				end

				return nil
			end)
		end)

		-- La regla anti-bloque (cada sala nueva toca como mucho una vieja) tiene una
		-- consecuencia geometrica exacta: el mapa es un ARBOL. Un arbol de N nodos tiene
		-- N-1 aristas. Si aparece una arista de mas, se formo un bloque 2x2 y el piso
		-- dejo de tener pasillos.
		it("respeta la regla anti-bloque: el mapa es un arbol", function()
			forEachSeed(9, false, function(layout)
				local cells = cellSet(layout)
				local adjacencies = 0

				for _, room in layout.rooms do
					for _, direction in DIRECTIONS do
						if cells[string.format("%d:%d", room.x + direction.dx, room.y + direction.dy)] then
							adjacencies += 1
						end
					end
				end

				-- Cada arista se cuenta dos veces, una por sala.
				local edges = adjacencies / 2

				if edges ~= #layout.rooms - 1 then
					return string.format("esperaba %d conexiones, hay %d", #layout.rooms - 1, edges)
				end

				return nil
			end)
		end)

		it("deja todas las salas alcanzables desde el inicio", function()
			forEachSeed(9, false, function(layout)
				for index, room in layout.rooms do
					if index ~= layout.startIndex and room.distanceFromStart <= 0 then
						return string.format("la sala %d quedo a distancia %d", index, room.distanceFromStart)
					end
				end

				if layout.rooms[layout.startIndex].distanceFromStart ~= 0 then
					return "la sala inicial no esta a distancia 0"
				end

				return nil
			end)
		end)
	end)

	describe("DungeonLayout: reparto de salas", function()
		it("hay exactamente una sala de inicio y esta en el origen", function()
			forEachSeed(8, false, function(layout)
				if DungeonLayout.countKind(layout, "Start") ~= 1 then
					return "no hay exactamente una sala de inicio"
				end

				local start = layout.rooms[layout.startIndex]

				if start.x ~= 0 or start.y ~= 0 or start.kind ~= "Start" then
					return "la sala inicial no es la del origen"
				end

				return nil
			end)
		end)

		it("los pisos intermedios tienen Portal y ningun Jefe", function()
			forEachSeed(8, false, function(layout)
				if DungeonLayout.countKind(layout, "Portal") ~= 1 then
					return "no hay exactamente un Portal"
				end

				if DungeonLayout.countKind(layout, "Boss") ~= 0 then
					return "un piso intermedio tiene Jefe"
				end

				return nil
			end)
		end)

		it("el piso final tiene Jefe y ningun Portal", function()
			forEachSeed(9, true, function(layout)
				if DungeonLayout.countKind(layout, "Boss") ~= 1 then
					return "no hay exactamente un Jefe"
				end

				if DungeonLayout.countKind(layout, "Portal") ~= 0 then
					return "el piso final tiene Portal"
				end

				return nil
			end)
		end)

		-- El bug clasico de este generador: la salida cae pegada al spawn y el piso
		-- entero se resuelve en dos pasos.
		it("la salida es siempre la sala mas lejana", function()
			forEachSeed(9, false, function(layout)
				local exit = layout.rooms[layout.exitIndex]

				for _, room in layout.rooms do
					if room.distanceFromStart > exit.distanceFromStart then
						return "hay una sala mas lejana que la salida"
					end
				end

				if exit.distanceFromStart < 2 then
					return string.format("la salida quedo a %d salas del inicio", exit.distanceFromStart)
				end

				return nil
			end)
		end)

		it("pone una sala de objetos cuando hay callejones disponibles", function()
			forEachSeed(9, false, function(layout)
				local availableDeadEnds = 0

				for index, room in layout.rooms do
					if index ~= layout.startIndex and index ~= layout.exitIndex and room.connections == 1 then
						availableDeadEnds += 1
					end
				end

				local itemCount = DungeonLayout.countKind(layout, "Item")

				if availableDeadEnds > 0 and itemCount ~= 1 then
					return string.format("habia %d callejones y %d salas de objetos", availableDeadEnds, itemCount)
				end

				if availableDeadEnds == 0 and itemCount ~= 0 then
					return "creo una sala de objetos sin callejones disponibles"
				end

				return nil
			end)
		end)

		it("la sala de objetos siempre es un callejon sin salida", function()
			forEachSeed(9, false, function(layout)
				for _, room in layout.rooms do
					if room.kind == "Item" and room.connections ~= 1 then
						return "la sala de objetos esta de paso, no en un callejon"
					end
				end

				return nil
			end)
		end)
	end)

	describe("DungeonLayout: lados", function()
		it("abre un lado si y solo si hay sala vecina", function()
			forEachSeed(9, false, function(layout)
				local cells = cellSet(layout)

				for _, room in layout.rooms do
					for _, direction in DIRECTIONS do
						local hasNeighbor = cells[string.format("%d:%d", room.x + direction.dx, room.y + direction.dy)]
						local isSolid = room.sides[direction.side] == "SolidWall"

						if hasNeighbor and isSolid then
							return string.format("lado %s tapiado con sala vecina", direction.side)
						end

						if not hasNeighbor and not isSolid then
							return string.format("lado %s abierto al vacio", direction.side)
						end
					end
				end

				return nil
			end)
		end)

		-- Regla de diseno del documento de contexto: Inicio y Objetos nunca encierran.
		it("Inicio y Objetos no llevan puertas; el resto si", function()
			forEachSeed(9, false, function(layout)
				for _, room in layout.rooms do
					local neverLocks = room.kind == "Start" or room.kind == "Item"

					for _, direction in DIRECTIONS do
						local state = room.sides[direction.side]

						if state == "SolidWall" then
							continue
						end

						if neverLocks and state ~= "OpenWall" then
							return string.format("%s tiene puerta y no deberia", room.kind)
						end

						if not neverLocks and state ~= "Door" then
							return string.format("%s tiene un hueco sin puerta", room.kind)
						end
					end
				end

				return nil
			end)
		end)

		it("cuenta bien las conexiones de cada sala", function()
			forEachSeed(9, false, function(layout)
				for _, room in layout.rooms do
					local open = 0

					for _, direction in DIRECTIONS do
						if room.sides[direction.side] ~= "SolidWall" then
							open += 1
						end
					end

					if open ~= room.connections then
						return string.format("declara %d conexiones y tiene %d lados abiertos", room.connections, open)
					end
				end

				return nil
			end)
		end)
	end)

	describe("DungeonLayout: entradas invalidas", function()
		it("rechaza pisos de menos de dos salas", function()
			expect(function()
				generate(1, 1, false)
			end).toThrow()
		end)

		it("rechaza conteos y pisos no enteros", function()
			expect(function()
				generate(1, 7.5, false)
			end).toThrow()

			expect(function()
				DungeonLayout.generate({ floorNumber = 0, roomCount = 7, isFinalFloor = false }, makeRandom(1))
			end).toThrow()
		end)
	end)

	describe("DungeonLayout.findRoomAt", function()
		it("encuentra la sala inicial en el origen y nada en una celda vacia", function()
			local layout = generate(3, 8, false)

			expect(DungeonLayout.findRoomAt(layout, 0, 0).kind).toBe("Start")
			expect(DungeonLayout.findRoomAt(layout, 999, 999)).toBe(nil)
		end)
	end)
end

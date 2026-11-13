--!strict
--[[
	DifficultyMath: matematica pura del escalado de dificultad.

	REGLA DURA de la carpeta Logic/: cero `require`, cero API de Roblox, cero Instances.
	Solo entra data y sale data. Eso lo hace ejecutable en Lune (CI) y en Roblox con el
	mismo archivo, y testeable sin abrir Studio.

	El tuning se inyecta como parametro opcional (DIP): produccion usa DEFAULT_TUNING,
	los tests usan tuning sintetico y el balanceo futuro puede venir de un modulo de datos
	sin tocar una sola linea de este archivo.

	Formulas base (documento de contexto, secciones 4 y 5):
		multiplicador de vida por piso      = 1 + 0.30 * (piso - 1)
		enemigos extra por piso             = piso - 1
		vida por jugador adicional          = +40%
		enemigos extra por jugador adicional= +1 por sala de combate
		vida del jefe por jugador adicional = +60%

	DECISION DE DISENO (revisar en playtest): los ejes "piso" y "jugadores" se componen
	de forma MULTIPLICATIVA, no aditiva. Con 4 jugadores en el piso 3 da 1.6 * 2.2 = 3.52x
	en lugar de 2.8x. Se elige multiplicativo porque cada eje es una presion independiente
	y compone correctamente al agregar un tercer eje (dificultad elegida, modo pesadilla).
	Si el playtest lo siente injusto, se baja enemyHealthPerExtraPlayer, no la formula.
]]

export type DifficultyTuning = {
	enemyHealthPerFloor: number,
	extraEnemiesPerFloor: number,
	enemyHealthPerExtraPlayer: number,
	extraEnemiesPerExtraPlayer: number,
	bossHealthPerExtraPlayer: number,
}

local DEFAULT_TUNING: DifficultyTuning = table.freeze({
	enemyHealthPerFloor = 0.30,
	extraEnemiesPerFloor = 1,
	enemyHealthPerExtraPlayer = 0.40,
	extraEnemiesPerExtraPlayer = 1,
	bossHealthPerExtraPlayer = 0.60,
})

local DifficultyMath = {}

DifficultyMath.DEFAULT_TUNING = DEFAULT_TUNING

--[[
	Falla ruidosamente ante entradas invalidas. Un piso 0 o un playerCount 0 producirian
	multiplicadores menores a 1 en silencio; ese es exactamente el tipo de bug que aparece
	tres semanas despues como "los enemigos del piso 1 son de papel".
]]
local function assertPositiveInteger(value: number, label: string): ()
	if value ~= value or value < 1 or value % 1 ~= 0 then
		error(string.format("DifficultyMath: %s debe ser un entero >= 1, recibido %s", label, tostring(value)), 3)
	end
end

--[[ Multiplicador de vida aplicable a cualquier enemigo comun. ]]
function DifficultyMath.enemyHealthMultiplier(
	floorNumber: number,
	playerCount: number,
	tuning: DifficultyTuning?
): number
	assertPositiveInteger(floorNumber, "floorNumber")
	assertPositiveInteger(playerCount, "playerCount")

	local config = tuning or DEFAULT_TUNING
	local floorFactor = 1 + config.enemyHealthPerFloor * (floorNumber - 1)
	local coopFactor = 1 + config.enemyHealthPerExtraPlayer * (playerCount - 1)

	return floorFactor * coopFactor
end

--[[ Multiplicador de vida del jefe. No escala por piso: el jefe siempre vive en el ultimo. ]]
function DifficultyMath.bossHealthMultiplier(playerCount: number, tuning: DifficultyTuning?): number
	assertPositiveInteger(playerCount, "playerCount")

	local config = tuning or DEFAULT_TUNING

	return 1 + config.bossHealthPerExtraPlayer * (playerCount - 1)
end

--[[ Enemigos adicionales por sala de combate, sobre el conteo base del prefab. ]]
function DifficultyMath.extraEnemiesPerRoom(floorNumber: number, playerCount: number, tuning: DifficultyTuning?): number
	assertPositiveInteger(floorNumber, "floorNumber")
	assertPositiveInteger(playerCount, "playerCount")

	local config = tuning or DEFAULT_TUNING
	local fromFloor = config.extraEnemiesPerFloor * (floorNumber - 1)
	local fromPlayers = config.extraEnemiesPerExtraPlayer * (playerCount - 1)

	return fromFloor + fromPlayers
end

--[[
	Vida final de un enemigo, redondeada a entero.
	Se expone como funcion propia para que ningun sistema tenga que acordarse de redondear:
	dos sistemas redondeando distinto es como nacen los "le pegue 3 veces y no murio".
]]
function DifficultyMath.scaledEnemyHealth(
	baseHealth: number,
	floorNumber: number,
	playerCount: number,
	tuning: DifficultyTuning?
): number
	if baseHealth <= 0 then
		error(string.format("DifficultyMath: baseHealth debe ser > 0, recibido %s", tostring(baseHealth)), 2)
	end

	local multiplier = DifficultyMath.enemyHealthMultiplier(floorNumber, playerCount, tuning)

	return math.max(1, math.round(baseHealth * multiplier))
end

--[[
	Cuantos enemigos spawnea una sala de combate: los del prefab mas los extra por piso
	y por jugador.

	Existe como funcion propia y no como una suma suelta en RoomService por el mismo
	motivo que `scaledEnemyHealth`: si el redondeo y el minimo viven en dos lugares,
	tarde o temprano dan distinto. El minimo de 1 es importante: una sala de combate
	que spawnea cero enemigos se auto-limpia al instante y el jugador la cruza sin
	entender que paso.
]]
function DifficultyMath.enemyCountForRoom(
	baseCount: number,
	floorNumber: number,
	playerCount: number,
	tuning: DifficultyTuning?
): number
	assertPositiveInteger(baseCount, "baseCount")

	local extra = DifficultyMath.extraEnemiesPerRoom(floorNumber, playerCount, tuning)

	return math.max(1, math.round(baseCount + extra))
end

--[[ Cantidad de salas del piso. Formula del documento: 7 + (piso - 1). ]]
function DifficultyMath.roomCountForFloor(floorNumber: number, baseRoomCount: number): number
	assertPositiveInteger(floorNumber, "floorNumber")
	assertPositiveInteger(baseRoomCount, "baseRoomCount")

	return baseRoomCount + (floorNumber - 1)
end

return table.freeze(DifficultyMath)

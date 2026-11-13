--!strict
--[[
	Rng: generador de numeros pseudoaleatorios propio, con semilla y reproducible.

	POR QUE NO `Random.new(seed)` DE ROBLOX:
	`Random` es un datatype de Roblox, y la regla dura de Shared/Logic/ es no tocar la
	API de Roblox para que el mismo archivo corra en Lune (CI) y en el juego. Sin esto,
	`DungeonLayout` no se podria testear sin abrir Studio, que es justo lo que la Fase 3
	del plan exige ("los tests de layout pasan en CI").

	Y hay un segundo motivo, mas importante a largo plazo: la implementacion de `Random`
	es de Roblox, no nuestra. Si algun dia cambian su algoritmo, la misma semilla deja
	de dar la misma mazmorra y se pierde la reproducibilidad de los reportes de bug
	("con la seed 12345 se generan dos salas Portal"). Con un generador propio, la seed
	significa lo mismo hoy, en el CI y dentro de dos anios.

	Algoritmo: xorshift32 (Marsaglia). Elegido porque son tres operaciones de bits, no
	tiene tablas de estado, y para repartir salas en una grilla su calidad estadistica
	sobra. No es criptografico y no pretende serlo: si algun dia hay que sortear loot
	con dinero real de por medio, eso se decide en el servidor con otra herramienta.
]]

-- Constante del numero aureo en 32 bits. Se usa como semilla de reemplazo porque
-- xorshift se queda clavado en 0 para siempre si el estado llega a valer 0.
local FALLBACK_SEED = 0x9E3779B9
local UINT32_COUNT = 4294967296 -- 2^32
local WARMUP_STEPS = 8

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

local function step(state: number): number
	state = bit32.bxor(state, bit32.lshift(state, 13))
	state = bit32.bxor(state, bit32.rshift(state, 17))
	state = bit32.bxor(state, bit32.lshift(state, 5))

	return state
end

--[[
	Crea un generador. Semillas distintas dan secuencias distintas; la MISMA semilla
	da siempre exactamente la misma secuencia, que es todo el punto.
]]
function Rng.new(seed: number): Rng
	if seed ~= seed then
		error("Rng: la semilla no puede ser NaN", 2)
	end

	local normalized = bit32.band(math.floor(math.abs(seed)), 0xFFFFFFFF)

	if normalized == 0 then
		normalized = FALLBACK_SEED
	end

	local self = setmetatable({ state = normalized }, Rng)

	-- Calentado: xorshift arranca con poca entropia si la semilla es chica (1, 2, 3...),
	-- y sin esto las primeras salas de las seeds 1 y 2 saldrian sospechosamente parecidas.
	for _ = 1, WARMUP_STEPS do
		self.state = step(self.state)
	end

	return self
end

--[[ Numero en [0, 1). ]]
function Rng.nextUnit(self: Rng): number
	self.state = step(self.state)

	return self.state / UINT32_COUNT
end

--[[ Entero en [minimum, maximum], ambos incluidos. ]]
function Rng.nextInteger(self: Rng, minimum: number, maximum: number): number
	if maximum < minimum then
		error(
			string.format("Rng: rango invalido [%s, %s]", tostring(minimum), tostring(maximum)),
			2
		)
	end

	local span = maximum - minimum + 1

	-- El math.min protege del caso extremo en que nextUnit devuelva algo que redondee
	-- justo al limite superior: un indice fuera de rango en una tabla es un nil que
	-- viaja lejos antes de explotar.
	return math.min(maximum, minimum + math.floor(self:nextUnit() * span))
end

--[[ Un elemento al azar de la lista. Revienta con lista vacia: elegir de la nada es un bug. ]]
function Rng.pick<T>(self: Rng, list: { T }): T
	if #list == 0 then
		error("Rng: no se puede elegir de una lista vacia", 2)
	end

	return list[self:nextInteger(1, #list)]
end

--[[
	Copia barajada (Fisher-Yates). Devuelve una tabla nueva a proposito: barajar in
	place una lista que vino de un modulo de datos congelado revienta, y barajar la
	lista del que llama es un efecto secundario que nadie espera.
]]
function Rng.shuffled<T>(self: Rng, list: { T }): { T }
	local copy = table.clone(list)

	for index = #copy, 2, -1 do
		local swapWith = self:nextInteger(1, index)
		copy[index], copy[swapWith] = copy[swapWith], copy[index]
	end

	return copy
end

return Rng

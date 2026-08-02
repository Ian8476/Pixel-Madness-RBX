--!strict
--[[
	HealthRegistry: el puente entre "una Part que toco un raycast" y "el Health que
	corresponde".

	Existe porque ProjectileSystem golpea Parts, no entidades. Sin este modulo, cada
	sistema que causa dano tendria que reimplementar "subi por el arbol hasta encontrar
	el Model duenno" y cada uno lo haria un poco distinto.

	Guarda las entradas con claves debiles (`__mode = "k"`): si un Model se destruye y
	nadie mas lo referencia, su entrada se va sola con el recolector. Aun asi
	`unregister` sigue siendo lo correcto al despawnear, para que el `onEntityDied`
	global no siga vivo mas de lo necesario.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Signal)

local Health = require(script.Parent.Health)

type HealthMap = { [Instance]: Health.Health }

local registry: HealthMap = setmetatable({} :: HealthMap, { __mode = "k" }) :: any

local HealthRegistry = {
	name = "HealthRegistry",
}

-- (entidad, Health, fuente del golpe final). Aqui se enchufa LootService en la Fase 4.
HealthRegistry.onEntityDied = Signal.new() :: Signal.Signal<Instance, Health.Health, Instance?>

--[[ Asocia un Health a una entidad y propaga su muerte al canal global. ]]
function HealthRegistry.register(entity: Instance, health: Health.Health): ()
	if registry[entity] then
		error(string.format("HealthRegistry: %s ya esta registrado", entity:GetFullName()), 2)
	end

	registry[entity] = health

	health.onDeath:connect(function(source: Instance?)
		HealthRegistry.onEntityDied:fire(entity, health, source)
	end)
end

function HealthRegistry.unregister(entity: Instance): ()
	local health = registry[entity]

	if not health then
		return
	end

	registry[entity] = nil
	health:destroy()
end

function HealthRegistry.get(entity: Instance): Health.Health?
	return registry[entity]
end

--[[
	Resuelve el Health a partir de una Part golpeada, subiendo por los ancestros.

	El limite de profundidad no es paranoia gratuita: sin el, una Part enterrada en
	una jerarquia profunda recorre todo el arbol hasta `game` en cada impacto, y esto
	corre una vez por bala por frame.
]]
local MAX_ANCESTOR_DEPTH = 4

function HealthRegistry.findFromPart(part: BasePart): (Health.Health?, Instance?)
	local current: Instance? = part
	local depth = 0

	while current and depth <= MAX_ANCESTOR_DEPTH do
		local health = registry[current]

		if health then
			return health, current
		end

		current = current.Parent
		depth += 1
	end

	return nil, nil
end

return HealthRegistry

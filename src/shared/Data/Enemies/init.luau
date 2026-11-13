--!strict
--[[
	Registro de enemigos. Mismas reglas que Data/Weapons y Data/Characters: lista
	explicita, validacion al cargarse, cero logica.

	`combatPool` es la lista de los que pueden aparecer en una sala de combate. El jefe
	NO esta ahi: sale una vez por run y lo coloca el generador en su sala, no el sorteo.
	Separarlo en una lista propia evita el bug de "me salieron dos Bonkarones en la
	sala 3" sin un solo `if` en el spawner.
]]

local Shared = script.Parent.Parent
local ContentSchema = require(Shared:WaitForChild("Logic"):WaitForChild("ContentSchema"))
local Types = require(Shared:WaitForChild("Types"))

local Chaser: Types.EnemyDef = require(script.Chaser)
local Shooter: Types.EnemyDef = require(script.Shooter)
local ElBonkaron: Types.EnemyDef = require(script.ElBonkaron)

local DEFINITIONS: { Types.EnemyDef } = {
	Chaser,
	Shooter,
	ElBonkaron,
}

local ok, problem = ContentSchema.validateCollection(DEFINITIONS, ContentSchema.validateEnemy)

if not ok then
	error(string.format("Data/Enemies: contenido invalido -> %s", tostring(problem)), 0)
end

local byId: { [Types.EnemyId]: Types.EnemyDef } = {}
local ids: { Types.EnemyId } = table.create(#DEFINITIONS)
local combatPool: { Types.EnemyId } = {}

for _, definition in DEFINITIONS do
	byId[definition.id] = definition
	table.insert(ids, definition.id)

	if not definition.isBoss then
		table.insert(combatPool, definition.id)
	end
end

local Enemies = {
	ids = table.freeze(ids),
	all = table.freeze(DEFINITIONS),
	-- Los que puede sortear una sala de combate. El jefe queda afuera a proposito.
	combatPool = table.freeze(combatPool),
	bossId = ElBonkaron.id,
}

function Enemies.getById(id: Types.EnemyId?): Types.EnemyDef?
	if type(id) ~= "string" then
		return nil
	end

	return byId[id]
end

function Enemies.expect(id: Types.EnemyId): Types.EnemyDef
	local definition = byId[id]

	if not definition then
		error(string.format("Data/Enemies: no existe el enemigo %q", tostring(id)), 2)
	end

	return definition
end

return table.freeze(Enemies)

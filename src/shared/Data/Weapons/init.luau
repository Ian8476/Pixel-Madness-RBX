--!strict
--[[
	Registro de armas: el unico lugar del juego que sabe que armas existen.

	Agregar un arma son DOS lineas: crear el archivo de datos y sumarlo a la lista de
	abajo. Cero logica, cero sistemas tocados. Esa es la regla 1 del proyecto en su
	forma mas literal, y el criterio de aceptacion de la Fase 2 ("agregar un arma
	nueva toma menos de 10 minutos").

	Por que la lista es explicita y no un recorrido de `script:GetChildren()`:
	el orden queda determinista (importa para la UI de la Fase 5) y un archivo mal
	nombrado se nota al instante en vez de dejar de existir en silencio. Es la misma
	decision que ya se tomo en `tests/run.luau` con las specs.

	Este modulo VALIDA el contenido al cargarse y revienta si algo esta mal. Un
	servidor que no levanta con un mensaje claro cuesta muchisimo menos que un arma
	con `damage = nil` descubierta a mitad de una run.
]]

-- Navegacion relativa (script -> Data -> Shared): este modulo vive DENTRO de Shared,
-- asi que no necesita buscarse desde ReplicatedStorage. Los `WaitForChild` son por el
-- cliente: un LocalScript puede arrancar antes de que termine de replicar todo
-- ReplicatedStorage, y en el servidor devuelven al instante.
local Shared = script.Parent.Parent
local ContentSchema = require(Shared:WaitForChild("Logic"):WaitForChild("ContentSchema"))
local Types = require(Shared:WaitForChild("Types"))

-- El tipo explicito es la segunda red: si un archivo de datos pierde un campo, el
-- analizador de Luau lo marca en el editor antes de llegar al CI.
local LaFiel: Types.WeaponDef = require(script.LaFiel)
local LaEscupechatarra: Types.WeaponDef = require(script.LaEscupechatarra)
local LaCotorra: Types.WeaponDef = require(script.LaCotorra)
local ElDedoDeDios: Types.WeaponDef = require(script.ElDedoDeDios)
local ElTridente: Types.WeaponDef = require(script.ElTridente)
local ElMeteoroQuesero: Types.WeaponDef = require(script.ElMeteoroQuesero)

-- Orden de presentacion: de la mas basica a la mas exotica.
local DEFINITIONS: { Types.WeaponDef } = {
	LaFiel,
	LaCotorra,
	ElTridente,
	LaEscupechatarra,
	ElDedoDeDios,
	ElMeteoroQuesero,
}

local ok, problem = ContentSchema.validateCollection(DEFINITIONS, ContentSchema.validateWeapon)

if not ok then
	error(string.format("Data/Weapons: contenido invalido -> %s", tostring(problem)), 0)
end

local byId: { [Types.WeaponId]: Types.WeaponDef } = {}
local ids: { Types.WeaponId } = table.create(#DEFINITIONS)

for _, definition in DEFINITIONS do
	byId[definition.id] = definition
	table.insert(ids, definition.id)
end

local Weapons = {
	-- Lista ordenada de ids. Congelada: es de lectura para todo el juego.
	ids = table.freeze(ids),
	all = table.freeze(DEFINITIONS),
}

--[[ Devuelve la definicion o nil. Para ids que vienen del cliente o de un Attribute. ]]
function Weapons.getById(id: Types.WeaponId?): Types.WeaponDef?
	if type(id) ~= "string" then
		return nil
	end

	return byId[id]
end

--[[
	Devuelve la definicion o revienta. Para ids que el CODIGO deberia garantizar
	(el arma inicial de un personaje, por ejemplo): si falta, es un bug nuestro y
	queremos enterarnos ya, no seguir con un arma nil.
]]
function Weapons.expect(id: Types.WeaponId): Types.WeaponDef
	local definition = byId[id]

	if not definition then
		error(string.format("Data/Weapons: no existe el arma %q", tostring(id)), 2)
	end

	return definition
end

--[[
	Un id al azar del pool completo. Lo usa PickupService para los pickups que no
	traen `WeaponId` en su Attribute (el `randomPool` del documento de contexto).
]]
function Weapons.randomId(random: Random): Types.WeaponId
	return ids[random:NextInteger(1, #ids)]
end

return table.freeze(Weapons)

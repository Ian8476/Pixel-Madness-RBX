--!strict
--[[
	Registro de personajes. Mismas reglas que Data/Weapons: lista explicita,
	validacion al cargar, cero logica.

	Ademas de validar el esquema, aca se comprueba una relacion que ningun archivo
	suelto puede comprobar solo: que el `startingWeaponId` de cada personaje exista
	de verdad en el registro de armas. Un typo ahi seria un jugador que aparece
	desarmado, y el sintoma ("no puedo disparar") no se parece en nada a la causa.
]]

-- Navegacion relativa (script -> Data -> Shared), igual que en Data/Weapons.
local Shared = script.Parent.Parent
local ContentSchema = require(Shared:WaitForChild("Logic"):WaitForChild("ContentSchema"))
local Types = require(Shared:WaitForChild("Types"))
local Weapons = require(script.Parent:WaitForChild("Weapons"))

local DonBonko: Types.CharacterDef = require(script.DonBonko)
local NinaLaRafaga: Types.CharacterDef = require(script.NinaLaRafaga)
local ElProfeVoltio: Types.CharacterDef = require(script.ElProfeVoltio)

-- Orden de la pantalla de seleccion (Fase 5). Bonko primero: es el gratuito.
local DEFINITIONS: { Types.CharacterDef } = {
	DonBonko,
	NinaLaRafaga,
	ElProfeVoltio,
}

local ok, problem = ContentSchema.validateCollection(DEFINITIONS, ContentSchema.validateCharacter)

if not ok then
	error(string.format("Data/Characters: contenido invalido -> %s", tostring(problem)), 0)
end

for _, definition in DEFINITIONS do
	if not Weapons.getById(definition.startingWeaponId) then
		error(
			string.format(
				"Data/Characters: %s empieza con el arma %q, que no existe en Data/Weapons",
				definition.id,
				tostring(definition.startingWeaponId)
			),
			0
		)
	end
end

local byId: { [Types.CharacterId]: Types.CharacterDef } = {}
local ids: { Types.CharacterId } = table.create(#DEFINITIONS)

for _, definition in DEFINITIONS do
	byId[definition.id] = definition
	table.insert(ids, definition.id)
end

local Characters = {
	ids = table.freeze(ids),
	all = table.freeze(DEFINITIONS),
	-- Personaje por defecto: el que juega quien todavia no eligio. Es el gratuito de
	-- la tienda de la Fase 7, asi que nadie puede jugarlo sin tenerlo.
	defaultId = DonBonko.id,
}

--[[ Devuelve la definicion o nil. Para ids que vienen del cliente (SelectCharacter). ]]
function Characters.getById(id: Types.CharacterId?): Types.CharacterDef?
	if type(id) ~= "string" then
		return nil
	end

	return byId[id]
end

--[[ Devuelve la definicion o revienta. Para ids que el codigo deberia garantizar. ]]
function Characters.expect(id: Types.CharacterId): Types.CharacterDef
	local definition = byId[id]

	if not definition then
		error(string.format("Data/Characters: no existe el personaje %q", tostring(id)), 2)
	end

	return definition
end

return table.freeze(Characters)

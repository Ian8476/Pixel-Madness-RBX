--!strict
--[[
	ContentSchema: valida que una definicion de contenido cumpla su esquema.

	Por que existe si ya tenemos tipos en Types.luau: los tipos de Luau se borran al
	compilar. Si alguien escribe `damage = "8"` en un arma, o se olvida de
	`projectileSpeed`, el analizador lo caza en su editor... si tiene el analizador
	prendido y si el archivo esta bien cableado. Este modulo lo caza en el CI, siempre,
	y con un mensaje que dice exactamente que campo esta mal.

	Es el guardian de la regla 1 del proyecto (contenido = datos): agregar un arma
	nueva no debe requerir tocar sistemas, pero SI debe ser imposible agregar un arma
	rota y enterarse en runtime, con cuatro jugadores mirando.

	Logica pura, sin `require` ni API de Roblox (regla de la carpeta Shared/Logic/):
	corre igual en Lune dentro del CI y en el servidor al arrancar. Por eso declara
	sus propios tipos en vez de importar Types.luau.

	Convencion de retorno: `(ok: boolean, problem: string?)`. Se devuelve el PRIMER
	problema y se corta. Un listado completo de errores suena mejor de lo que es:
	cuando falta un campo, la mitad de los errores siguientes son consecuencia del
	primero y solo agregan ruido.
]]

type Rgb = { r: number, g: number, b: number }

local VALID_ABILITY_KINDS: { [string]: boolean } = {
	Dash = true,
	DualWield = true,
	RapidFire = true,
}

local VALID_ENEMY_BRAINS: { [string]: boolean } = {
	Chaser = true,
	Shooter = true,
}

-- Campos que solo tienen sentido si el enemigo dispara. Declararlos en un Chaser no
-- rompe nada en runtime, y ese es justamente el problema: quien los escribio espera
-- que el bicho dispare y no va a disparar nunca.
local SHOOTER_ONLY_FIELDS = { "projectileDamage", "projectileSpeed", "fireRate", "preferredDistanceStuds" }

local ContentSchema = {}

--------------------------------------------------------------------------------
-- Chequeos elementales
--------------------------------------------------------------------------------

local function isNumber(value: any): boolean
	-- `value ~= value` es la comprobacion de NaN: un NaN colado en un dato se
	-- propaga en silencio hasta que una bala viaja a ninguna parte.
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function checkString(container: any, field: string, label: string): string?
	local value = container[field]

	if type(value) ~= "string" then
		return string.format("%s.%s debe ser string, es %s", label, field, typeof(value))
	end

	if #value == 0 then
		return string.format("%s.%s no puede estar vacio", label, field)
	end

	return nil
end

local function checkNumber(container: any, field: string, label: string, minimum: number?, maximum: number?): string?
	local value = container[field]

	if not isNumber(value) then
		return string.format("%s.%s debe ser un numero finito, es %s", label, field, tostring(value))
	end

	if minimum and value < minimum then
		return string.format("%s.%s debe ser >= %s, es %s", label, field, tostring(minimum), tostring(value))
	end

	if maximum and value > maximum then
		return string.format("%s.%s debe ser <= %s, es %s", label, field, tostring(maximum), tostring(value))
	end

	return nil
end

local function checkInteger(container: any, field: string, label: string, minimum: number): string?
	local problem = checkNumber(container, field, label, minimum)

	if problem then
		return problem
	end

	if container[field] % 1 ~= 0 then
		return string.format("%s.%s debe ser un entero, es %s", label, field, tostring(container[field]))
	end

	return nil
end

local function checkBoolean(container: any, field: string, label: string): string?
	if type(container[field]) ~= "boolean" then
		return string.format("%s.%s debe ser boolean, es %s", label, field, typeof(container[field]))
	end

	return nil
end

local function checkRgb(container: any, field: string, label: string): string?
	local value = container[field]

	if type(value) ~= "table" then
		return string.format("%s.%s debe ser una tabla {r, g, b}, es %s", label, field, typeof(value))
	end

	local color = value :: Rgb

	for _, channel in { "r", "g", "b" } do
		local problem = checkNumber(color, channel, string.format("%s.%s", label, field), 0, 255)

		if problem then
			return problem
		end
	end

	return nil
end

--[[ Corre una lista de chequeos y devuelve el primer problema. ]]
local function firstProblem(checks: { () -> string? }): string?
	for _, check in checks do
		local problem = check()

		if problem then
			return problem
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- Armas
--------------------------------------------------------------------------------

--[[ Valida un WeaponDef. Devuelve (true) o (false, que esta mal). ]]
function ContentSchema.validateWeapon(value: any): (boolean, string?)
	if type(value) ~= "table" then
		return false, string.format("un arma debe ser una tabla, es %s", typeof(value))
	end

	local label = if type(value.id) == "string" then string.format("arma %q", value.id) else "arma sin id"

	local problem = firstProblem({
		function()
			return checkString(value, "id", label)
		end,
		function()
			return checkString(value, "displayName", label)
		end,
		function()
			return checkString(value, "flavorText", label)
		end,
		-- fireRate > 0 y no solo >= 0: el intervalo entre disparos es 1/fireRate y un
		-- cero aca es una division por cero en el servidor, no un arma que no dispara.
		function()
			return checkNumber(value, "fireRate", label, 0.01)
		end,
		function()
			return checkInteger(value, "projectilesPerShot", label, 1)
		end,
		function()
			return checkNumber(value, "spreadDegrees", label, 0, 360)
		end,
		function()
			return checkNumber(value, "damage", label, 0)
		end,
		function()
			return checkNumber(value, "projectileSpeed", label, 1)
		end,
		function()
			return checkNumber(value, "energyCost", label, 0)
		end,
		function()
			return checkBoolean(value, "isAutomatic", label)
		end,
		function()
			return checkBoolean(value, "isPiercing", label)
		end,
		function()
			return checkNumber(value, "knockback", label, 0)
		end,
		function()
			return checkNumber(value, "projectileScale", label, 0.05)
		end,
		function()
			return checkRgb(value, "projectileColor", label)
		end,
	})

	if problem then
		return false, problem
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Habilidades
--------------------------------------------------------------------------------

--[[
	Valida un AbilityDef. La union se discrimina por `kind`, igual que el tipo de
	Luau: si aparece una habilidad nueva y nadie agrega su caso aca, esta funcion la
	rechaza en vez de dejarla pasar a medio validar.
]]
function ContentSchema.validateAbility(value: any, ownerLabel: string): (boolean, string?)
	if type(value) ~= "table" then
		return false, string.format("%s.ability debe ser una tabla, es %s", ownerLabel, typeof(value))
	end

	local kind = value.kind

	if type(kind) ~= "string" or not VALID_ABILITY_KINDS[kind] then
		return false, string.format("%s.ability.kind desconocido: %s", ownerLabel, tostring(kind))
	end

	local label = string.format("%s.ability", ownerLabel)

	local problem = firstProblem({
		function()
			return checkString(value, "displayName", label)
		end,
		function()
			return checkString(value, "flavorText", label)
		end,
		function()
			return checkNumber(value, "energyCost", label, 0)
		end,
		function()
			return checkNumber(value, "cooldownSeconds", label, 0)
		end,
	})

	if problem then
		return false, problem
	end

	if kind == "Dash" then
		problem = firstProblem({
			function()
				return checkNumber(value, "impulseSpeed", label, 1)
			end,
			function()
				return checkNumber(value, "invulnerabilitySeconds", label, 0)
			end,
		})
	elseif kind == "DualWield" then
		problem = checkNumber(value, "durationSeconds", label, 0.1)
	elseif kind == "RapidFire" then
		problem = firstProblem({
			function()
				return checkNumber(value, "durationSeconds", label, 0.1)
			end,
			function()
				return checkNumber(value, "fireRateMultiplier", label, 1)
			end,
		})
	end

	if problem then
		return false, problem
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Personajes
--------------------------------------------------------------------------------

--[[ Valida un CharacterDef, incluida su habilidad. ]]
function ContentSchema.validateCharacter(value: any): (boolean, string?)
	if type(value) ~= "table" then
		return false, string.format("un personaje debe ser una tabla, es %s", typeof(value))
	end

	local label = if type(value.id) == "string"
		then string.format("personaje %q", value.id)
		else "personaje sin id"

	local problem = firstProblem({
		function()
			return checkString(value, "id", label)
		end,
		function()
			return checkString(value, "displayName", label)
		end,
		function()
			return checkString(value, "flavorText", label)
		end,
		function()
			return checkRgb(value, "greyboxColor", label)
		end,
		function()
			return checkNumber(value, "maxHealth", label, 1)
		end,
		function()
			return checkNumber(value, "walkSpeed", label, 1)
		end,
		function()
			return checkNumber(value, "maxEnergy", label, 1)
		end,
		function()
			return checkNumber(value, "energyRegenPerSecond", label, 0)
		end,
		function()
			return checkString(value, "startingWeaponId", label)
		end,
	})

	if problem then
		return false, problem
	end

	local abilityOk, abilityProblem = ContentSchema.validateAbility(value.ability, label)

	if not abilityOk then
		return false, abilityProblem
	end

	-- Una habilidad que cuesta mas de lo que el personaje puede acumular es
	-- inusable, y el bug se descubre jugando en vez de en el CI.
	if value.ability.energyCost > value.maxEnergy then
		return false,
			string.format(
				"%s: la habilidad cuesta %s pero el personaje solo llega a %s de energia",
				label,
				tostring(value.ability.energyCost),
				tostring(value.maxEnergy)
			)
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Enemigos
--------------------------------------------------------------------------------

--[[
	Valida un EnemyDef. El `brain` decide que campos son obligatorios, igual que el
	`kind` en las habilidades.
]]
function ContentSchema.validateEnemy(value: any): (boolean, string?)
	if type(value) ~= "table" then
		return false, string.format("un enemigo debe ser una tabla, es %s", typeof(value))
	end

	local label = if type(value.id) == "string" then string.format("enemigo %q", value.id) else "enemigo sin id"

	local problem = firstProblem({
		function()
			return checkString(value, "id", label)
		end,
		function()
			return checkString(value, "displayName", label)
		end,
		function()
			return checkRgb(value, "greyboxColor", label)
		end,
		function()
			return checkNumber(value, "baseHealth", label, 1)
		end,
		function()
			return checkNumber(value, "walkSpeed", label, 0)
		end,
		function()
			return checkNumber(value, "contactDamage", label, 0)
		end,
		function()
			return checkNumber(value, "modelScale", label, 0.1)
		end,
		function()
			return checkInteger(value, "minCoinDrop", label, 0)
		end,
		function()
			return checkInteger(value, "maxCoinDrop", label, 0)
		end,
	})

	if problem then
		return false, problem
	end

	if type(value.brain) ~= "string" or not VALID_ENEMY_BRAINS[value.brain] then
		return false, string.format("%s.brain desconocido: %s", label, tostring(value.brain))
	end

	if value.maxCoinDrop < value.minCoinDrop then
		return false,
			string.format(
				"%s: maxCoinDrop (%s) es menor que minCoinDrop (%s)",
				label,
				tostring(value.maxCoinDrop),
				tostring(value.minCoinDrop)
			)
	end

	if value.isBoss ~= nil and type(value.isBoss) ~= "boolean" then
		return false, string.format("%s.isBoss debe ser boolean si esta presente", label)
	end

	if value.brain == "Shooter" then
		problem = firstProblem({
			function()
				return checkNumber(value, "projectileDamage", label, 0)
			end,
			function()
				return checkNumber(value, "projectileSpeed", label, 1)
			end,
			function()
				return checkNumber(value, "fireRate", label, 0.01)
			end,
			function()
				return checkNumber(value, "preferredDistanceStuds", label, 1)
			end,
		})

		if problem then
			return false, problem
		end
	else
		for _, field in SHOOTER_ONLY_FIELDS do
			if value[field] ~= nil then
				return false,
					string.format("%s declara %s pero su cerebro es %s y nunca dispara", label, field, value.brain)
			end
		end
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Colecciones
--------------------------------------------------------------------------------

--[[
	Valida una lista de definiciones con el validador dado y ademas exige que los
	`id` sean unicos. Dos armas con el mismo id no rompen nada visible: una
	simplemente deja de existir cuando el registro las indexa.
]]
function ContentSchema.validateCollection(
	definitions: { any },
	validate: (value: any) -> (boolean, string?)
): (boolean, string?)
	local seen: { [string]: boolean } = {}

	for index, definition in definitions do
		local ok, problem = validate(definition)

		if not ok then
			return false, string.format("definicion #%d: %s", index, tostring(problem))
		end

		local id = definition.id

		if seen[id] then
			return false, string.format("id duplicado: %q", id)
		end

		seen[id] = true
	end

	return true, nil
end

return table.freeze(ContentSchema)

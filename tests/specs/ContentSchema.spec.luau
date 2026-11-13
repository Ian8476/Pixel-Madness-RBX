--!strict
--[[
	Tests del validador de contenido. Aca se prueba el GUARDIAN; que el contenido real
	pase por el guardian se prueba en ContentData.spec.

	La forma de estos tests es "tomo una definicion valida, le rompo UN campo, espero
	que el validador la rechace". Eso obliga a que cada regla del esquema tenga su
	propio motivo de existir: si alguien borra un chequeo, exactamente un test cae y
	dice cual.
]]

local ContentSchema = require("../../src/shared/Logic/ContentSchema")

local function validWeapon(): any
	return {
		id = "arma_de_prueba",
		displayName = "Arma de Prueba",
		flavorText = "Existe solo en el CI.",
		fireRate = 2,
		projectilesPerShot = 1,
		spreadDegrees = 0,
		damage = 10,
		projectileSpeed = 60,
		energyCost = 3,
		isAutomatic = true,
		isPiercing = false,
		knockback = 10,
		projectileScale = 1,
		projectileColor = { r = 255, g = 255, b = 255 },
	}
end

local function validCharacter(): any
	return {
		id = "personaje_de_prueba",
		displayName = "Personaje de Prueba",
		flavorText = "Tampoco existe.",
		greyboxColor = { r = 10, g = 20, b = 30 },
		maxHealth = 100,
		walkSpeed = 16,
		maxEnergy = 100,
		energyRegenPerSecond = 5,
		ability = {
			kind = "Dash",
			displayName = "Prueba",
			flavorText = "Prueba.",
			energyCost = 20,
			cooldownSeconds = 1.5,
			impulseSpeed = 36,
			invulnerabilitySeconds = 0.35,
		},
		startingWeaponId = "arma_de_prueba",
	}
end

--[[ Rompe un campo de una copia y devuelve la copia. ]]
local function withField(base: any, field: string, value: any): any
	local copy = table.clone(base)
	copy[field] = value

	return copy
end

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("ContentSchema.validateWeapon", function()
		it("acepta un arma completa", function()
			local ok, problem = ContentSchema.validateWeapon(validWeapon())

			expect(ok).toBe(true)
			expect(problem).toBe(nil)
		end)

		it("rechaza campos faltantes", function()
			for _, field in { "id", "displayName", "damage", "projectileSpeed", "isPiercing", "projectileColor" } do
				local ok = ContentSchema.validateWeapon(withField(validWeapon(), field, nil))

				expect(ok).toBe(false)
			end
		end)

		it("rechaza numeros escritos como texto", function()
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "damage", "10"))).toBe(false)
		end)

		-- fireRate = 0 es una division por cero en el servidor (el intervalo entre
		-- disparos es 1/fireRate), no un arma que "no dispara".
		it("rechaza fireRate cero o negativo", function()
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "fireRate", 0))).toBe(false)
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "fireRate", -1))).toBe(false)
		end)

		it("rechaza un conteo de proyectiles no entero", function()
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "projectilesPerShot", 2.5))).toBe(false)
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "projectilesPerShot", 0))).toBe(false)
		end)

		it("rechaza un NaN colado en un numero", function()
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "damage", 0 / 0))).toBe(false)
		end)

		it("rechaza un color fuera de rango o mal formado", function()
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "projectileColor", { r = 300, g = 0, b = 0 }))).toBe(
				false
			)
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "projectileColor", { r = 0, g = 0 }))).toBe(false)
			expect(ContentSchema.validateWeapon(withField(validWeapon(), "projectileColor", "blanco"))).toBe(false)
		end)

		it("nombra el arma en el mensaje de error", function()
			local _, problem = ContentSchema.validateWeapon(withField(validWeapon(), "damage", nil))

			expect(typeof(problem)).toBe("string")
			expect(string.find(problem :: string, "arma_de_prueba") ~= nil).toBe(true)
		end)
	end)

	describe("ContentSchema.validateAbility", function()
		it("rechaza un kind desconocido", function()
			local ability = table.clone(validCharacter().ability)
			ability.kind = "Teletransporte"

			expect(ContentSchema.validateAbility(ability, "test")).toBe(false)
		end)

		it("exige los campos propios de cada kind", function()
			local dash = table.clone(validCharacter().ability)
			dash.impulseSpeed = nil

			expect(ContentSchema.validateAbility(dash, "test")).toBe(false)

			expect(ContentSchema.validateAbility({
				kind = "RapidFire",
				displayName = "X",
				flavorText = "X",
				energyCost = 10,
				cooldownSeconds = 1,
				durationSeconds = 4,
				-- falta fireRateMultiplier
			}, "test")).toBe(false)

			expect(ContentSchema.validateAbility({
				kind = "DualWield",
				displayName = "X",
				flavorText = "X",
				energyCost = 10,
				cooldownSeconds = 1,
				durationSeconds = 5,
			}, "test")).toBe(true)
		end)

		-- Un multiplicador menor a 1 seria una habilidad que EMPEORA el arma.
		it("rechaza un multiplicador de cadencia menor a 1", function()
			expect(ContentSchema.validateAbility({
				kind = "RapidFire",
				displayName = "X",
				flavorText = "X",
				energyCost = 10,
				cooldownSeconds = 1,
				durationSeconds = 4,
				fireRateMultiplier = 0.5,
			}, "test")).toBe(false)
		end)
	end)

	describe("ContentSchema.validateCharacter", function()
		it("acepta un personaje completo", function()
			expect(ContentSchema.validateCharacter(validCharacter())).toBe(true)
		end)

		it("rechaza vida o velocidad en cero", function()
			expect(ContentSchema.validateCharacter(withField(validCharacter(), "maxHealth", 0))).toBe(false)
			expect(ContentSchema.validateCharacter(withField(validCharacter(), "walkSpeed", 0))).toBe(false)
		end)

		-- Una habilidad que cuesta mas de lo que el personaje puede acumular es
		-- inusable, y el bug se descubre jugando en vez de en el CI.
		it("rechaza una habilidad mas cara que la energia maxima", function()
			expect(ContentSchema.validateCharacter(withField(validCharacter(), "maxEnergy", 10))).toBe(false)
		end)

		it("propaga el problema de la habilidad", function()
			local broken = table.clone(validCharacter())
			broken.ability = table.clone(broken.ability)
			broken.ability.cooldownSeconds = nil

			local ok, problem = ContentSchema.validateCharacter(broken)

			expect(ok).toBe(false)
			expect(string.find(problem :: string, "cooldownSeconds") ~= nil).toBe(true)
		end)
	end)

	describe("ContentSchema.validateEnemy", function()
		local function validEnemy(): any
			return {
				id = "bicho_de_prueba",
				displayName = "Bicho de Prueba",
				brain = "Chaser",
				greyboxColor = { r = 1, g = 2, b = 3 },
				baseHealth = 30,
				walkSpeed = 12,
				contactDamage = 10,
				modelScale = 1,
				minCoinDrop = 1,
				maxCoinDrop = 3,
			}
		end

		it("acepta un Chaser completo", function()
			expect(ContentSchema.validateEnemy(validEnemy())).toBe(true)
		end)

		it("rechaza un cerebro desconocido", function()
			expect(ContentSchema.validateEnemy(withField(validEnemy(), "brain", "Kamikaze"))).toBe(false)
		end)

		it("exige los campos de disparo cuando el cerebro es Shooter", function()
			local shooter = withField(validEnemy(), "brain", "Shooter")

			expect(ContentSchema.validateEnemy(shooter)).toBe(false)

			shooter.projectileDamage = 8
			shooter.projectileSpeed = 30
			shooter.fireRate = 0.8
			shooter.preferredDistanceStuds = 24

			expect(ContentSchema.validateEnemy(shooter)).toBe(true)
		end)

		-- Ponerle fireRate a un Chaser no rompe nada en runtime, y ese es el problema:
		-- quien lo escribio espera que dispare y no va a disparar nunca.
		it("rechaza campos de disparo en un enemigo que no dispara", function()
			local ok, problem = ContentSchema.validateEnemy(withField(validEnemy(), "fireRate", 2))

			expect(ok).toBe(false)
			expect(string.find(problem :: string, "fireRate") ~= nil).toBe(true)
		end)

		it("rechaza un rango de monedas invertido", function()
			local broken = withField(validEnemy(), "minCoinDrop", 5)

			expect(ContentSchema.validateEnemy(broken)).toBe(false)
		end)

		it("rechaza monedas fraccionarias", function()
			expect(ContentSchema.validateEnemy(withField(validEnemy(), "maxCoinDrop", 2.5))).toBe(false)
		end)

		it("acepta isBoss solo como boolean", function()
			expect(ContentSchema.validateEnemy(withField(validEnemy(), "isBoss", true))).toBe(true)
			expect(ContentSchema.validateEnemy(withField(validEnemy(), "isBoss", "si"))).toBe(false)
		end)
	end)

	describe("ContentSchema.validateCollection", function()
		it("rechaza ids duplicados", function()
			local ok, problem = ContentSchema.validateCollection(
				{ validWeapon(), validWeapon() },
				ContentSchema.validateWeapon
			)

			expect(ok).toBe(false)
			expect(string.find(problem :: string, "duplicado") ~= nil).toBe(true)
		end)

		it("dice cual definicion fallo", function()
			local ok, problem = ContentSchema.validateCollection(
				{ validWeapon(), withField(validWeapon(), "damage", nil) },
				ContentSchema.validateWeapon
			)

			expect(ok).toBe(false)
			expect(string.find(problem :: string, "#2") ~= nil).toBe(true)
		end)

		it("acepta una coleccion sana", function()
			local second = withField(validWeapon(), "id", "otra_arma")

			expect(ContentSchema.validateCollection({ validWeapon(), second }, ContentSchema.validateWeapon)).toBe(true)
		end)
	end)
end

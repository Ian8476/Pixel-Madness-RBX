--!strict
--[[
	El contenido REAL del juego, validado en el CI sin abrir Studio.

	Esta spec es la razon por la que los modulos de Shared/Data/ tienen prohibido
	hacer `require` y usar datatypes de Roblox: gracias a esa restriccion, aca se
	carga el MISMO archivo que carga el servidor, no una copia de fixtures que se
	desincroniza al primer cambio.

	Lo que no se puede cargar en Lune son los `init.luau` de los registros (usan
	`script` y `game`), asi que la lista de armas y personajes se repite aca. Para que
	esa repeticion no se convierta en un agujero silencioso ("agregue un arma y nadie
	la valida"), el ultimo bloque compara la lista contra los archivos que hay de
	verdad en el disco y falla si no coinciden.
]]

local fs = require("@lune/fs")

local ContentSchema = require("../../src/shared/Logic/ContentSchema")

local WEAPONS_DIRECTORY = "src/shared/Data/Weapons"
local CHARACTERS_DIRECTORY = "src/shared/Data/Characters"
local ENEMIES_DIRECTORY = "src/shared/Data/Enemies"

local WEAPON_FILES = {
	"LaFiel",
	"LaCotorra",
	"ElTridente",
	"LaEscupechatarra",
	"ElDedoDeDios",
	"ElMeteoroQuesero",
}

local CHARACTER_FILES = {
	"DonBonko",
	"NinaLaRafaga",
	"ElProfeVoltio",
}

local ENEMY_FILES = {
	"Chaser",
	"Shooter",
	"ElBonkaron",
}

local WEAPONS: { any } = {
	require("../../src/shared/Data/Weapons/LaFiel"),
	require("../../src/shared/Data/Weapons/LaCotorra"),
	require("../../src/shared/Data/Weapons/ElTridente"),
	require("../../src/shared/Data/Weapons/LaEscupechatarra"),
	require("../../src/shared/Data/Weapons/ElDedoDeDios"),
	require("../../src/shared/Data/Weapons/ElMeteoroQuesero"),
}

local CHARACTERS: { any } = {
	require("../../src/shared/Data/Characters/DonBonko"),
	require("../../src/shared/Data/Characters/NinaLaRafaga"),
	require("../../src/shared/Data/Characters/ElProfeVoltio"),
}

local ENEMIES: { any } = {
	require("../../src/shared/Data/Enemies/Chaser"),
	require("../../src/shared/Data/Enemies/Shooter"),
	require("../../src/shared/Data/Enemies/ElBonkaron"),
}

--[[ Nombres de modulo (sin extension) presentes en una carpeta de datos, sin el init. ]]
local function moduleNamesIn(directory: string): { string }
	local names = {}

	for _, entry in fs.readDir(directory) do
		local name = string.match(entry, "^(.+)%.luau$")

		if name and name ~= "init" then
			table.insert(names, name)
		end
	end

	table.sort(names)

	return names
end

local function sortedCopy(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)

	return copy
end

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("Contenido: armas", function()
		it("las 6 armas del diseno cumplen el esquema", function()
			local ok, problem = ContentSchema.validateCollection(WEAPONS, ContentSchema.validateWeapon)

			if not ok then
				error(problem, 0)
			end

			expect(#WEAPONS).toBe(6)
		end)

		-- La Fiel es la red de seguridad del juego: si algun dia cuesta energia, un
		-- jugador sin energia se queda sin poder disparar y el loop se rompe.
		it("La Fiel sigue siendo gratis", function()
			expect(WEAPONS[1].id).toBe("la_fiel")
			expect(WEAPONS[1].energyCost).toBe(0)
		end)

		it("hay exactamente un arma piercing y es la mas lenta", function()
			local piercing = {}
			local slowest = WEAPONS[1]

			for _, weapon in WEAPONS do
				if weapon.isPiercing then
					table.insert(piercing, weapon)
				end

				if weapon.projectileSpeed < slowest.projectileSpeed then
					slowest = weapon
				end
			end

			expect(#piercing).toBe(1)
			expect(piercing[1].id).toBe("el_meteoro_quesero")
			expect(slowest.id).toBe("el_meteoro_quesero")
		end)

		-- Las armas de un solo proyectil no deben abrir abanico: SpreadMath devuelve
		-- {0} para un proyectil, asi que un spread > 0 ahi seria un numero que miente.
		it("las armas de un proyectil no declaran spread", function()
			for _, weapon in WEAPONS do
				if weapon.projectilesPerShot == 1 and weapon.spreadDegrees > 0 then
					-- La Cotorra es la excepcion deliberada: su spread es imprecision
					-- de rafaga, no abanico, y se aplica como jitter.
					expect(weapon.id).toBe("la_cotorra")
				end
			end
		end)
	end)

	describe("Contenido: personajes", function()
		it("los 3 personajes del diseno cumplen el esquema", function()
			local ok, problem = ContentSchema.validateCollection(CHARACTERS, ContentSchema.validateCharacter)

			if not ok then
				error(problem, 0)
			end

			expect(#CHARACTERS).toBe(3)
		end)

		-- Un typo aca es un jugador que aparece desarmado, y el sintoma ("no puedo
		-- disparar") no se parece en nada a la causa.
		it("el arma inicial de cada personaje existe", function()
			local weaponIds: { [string]: boolean } = {}

			for _, weapon in WEAPONS do
				weaponIds[weapon.id] = true
			end

			for _, character in CHARACTERS do
				if not weaponIds[character.startingWeaponId] then
					error(
						string.format(
							"%s empieza con %q, que no existe en Data/Weapons",
							character.id,
							tostring(character.startingWeaponId)
						),
						0
					)
				end
			end
		end)

		it("las 3 habilidades del diseno estan cubiertas", function()
			local kinds: { [string]: boolean } = {}

			for _, character in CHARACTERS do
				kinds[character.ability.kind] = true
			end

			expect(kinds.Dash).toBe(true)
			expect(kinds.DualWield).toBe(true)
			expect(kinds.RapidFire).toBe(true)
		end)
	end)

	describe("Contenido: enemigos", function()
		it("los 3 enemigos del diseno cumplen el esquema", function()
			local ok, problem = ContentSchema.validateCollection(ENEMIES, ContentSchema.validateEnemy)

			if not ok then
				error(problem, 0)
			end

			expect(#ENEMIES).toBe(3)
		end)

		-- Dos jefes en una run seria un piso final con dos finales.
		it("hay exactamente un jefe", function()
			local bosses = 0

			for _, enemy in ENEMIES do
				if enemy.isBoss then
					bosses += 1
				end
			end

			expect(bosses).toBe(1)
		end)

		-- El jefe tiene que ser MAS lento que sus propios secuaces: un jefe que te
		-- alcanza no es un jefe, es un accidente.
		it("el jefe es el mas lento y el mas duro", function()
			local boss = ENEMIES[3]

			expect(boss.id).toBe("el_bonkaron")

			for _, enemy in ENEMIES do
				if enemy.isBoss then
					continue
				end

				expect(boss.walkSpeed < enemy.walkSpeed).toBe(true)
				expect(boss.baseHealth > enemy.baseHealth).toBe(true)
			end
		end)

		-- La bala del Shooter tiene que ser esquivable con 100 ms de latencia: por eso
		-- viaja mas lento que el personaje mas lento del juego (16 de Bonko).
		it("las balas del Shooter son mas lentas que las del jugador y esquivables", function()
			local shooter = ENEMIES[2]

			expect(shooter.id).toBe("shooter")
			expect(shooter.projectileSpeed <= 30).toBe(true)
		end)
	end)

	-- Sin este bloque, agregar contenido y olvidarse de sumarlo arriba significa que el
	-- contenido nuevo NO se valida y nadie se entera.
	describe("Contenido: cobertura", function()
		it("esta spec valida todos los archivos de Data/Weapons", function()
			expect(moduleNamesIn(WEAPONS_DIRECTORY)).toEqual(sortedCopy(WEAPON_FILES))
		end)

		it("esta spec valida todos los archivos de Data/Characters", function()
			expect(moduleNamesIn(CHARACTERS_DIRECTORY)).toEqual(sortedCopy(CHARACTER_FILES))
		end)

		it("esta spec valida todos los archivos de Data/Enemies", function()
			expect(moduleNamesIn(ENEMIES_DIRECTORY)).toEqual(sortedCopy(ENEMY_FILES))
		end)
	end)
end

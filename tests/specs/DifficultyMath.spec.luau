--!strict
--[[
	Tests del escalado de dificultad. Estos numeros son el contrato del balanceo:
	si alguien cambia una formula "para probar algo" y se olvida de revertirla,
	el CI se pone rojo en el PR y no tres semanas despues en un playtest.
]]

local DifficultyMath = require("../../src/shared/Logic/DifficultyMath")

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("DifficultyMath.enemyHealthMultiplier", function()
		it("no escala en el piso 1 con un solo jugador", function()
			expect(DifficultyMath.enemyHealthMultiplier(1, 1)).toBeCloseTo(1)
		end)

		it("aplica +30% por piso adicional", function()
			expect(DifficultyMath.enemyHealthMultiplier(2, 1)).toBeCloseTo(1.3)
			expect(DifficultyMath.enemyHealthMultiplier(3, 1)).toBeCloseTo(1.6)
		end)

		it("aplica +40% por jugador adicional", function()
			expect(DifficultyMath.enemyHealthMultiplier(1, 2)).toBeCloseTo(1.4)
			expect(DifficultyMath.enemyHealthMultiplier(1, 4)).toBeCloseTo(2.2)
		end)

		it("compone piso y jugadores de forma multiplicativa", function()
			-- Piso 3 con 4 jugadores: 1.6 * 2.2 = 3.52
			expect(DifficultyMath.enemyHealthMultiplier(3, 4)).toBeCloseTo(3.52)
		end)

		it("respeta el tuning inyectado en vez del default", function()
			local flatTuning = {
				enemyHealthPerFloor = 0,
				extraEnemiesPerFloor = 0,
				enemyHealthPerExtraPlayer = 0,
				extraEnemiesPerExtraPlayer = 0,
				bossHealthPerExtraPlayer = 0,
			}

			expect(DifficultyMath.enemyHealthMultiplier(3, 4, flatTuning)).toBeCloseTo(1)
		end)

		it("rechaza pisos y conteos invalidos en vez de devolver basura", function()
			expect(function()
				DifficultyMath.enemyHealthMultiplier(0, 1)
			end).toThrow()

			expect(function()
				DifficultyMath.enemyHealthMultiplier(1, 0)
			end).toThrow()

			expect(function()
				DifficultyMath.enemyHealthMultiplier(1.5, 1)
			end).toThrow()
		end)
	end)

	describe("DifficultyMath.bossHealthMultiplier", function()
		it("no escala en solitario", function()
			expect(DifficultyMath.bossHealthMultiplier(1)).toBeCloseTo(1)
		end)

		it("aplica +60% por jugador adicional", function()
			expect(DifficultyMath.bossHealthMultiplier(2)).toBeCloseTo(1.6)
			expect(DifficultyMath.bossHealthMultiplier(4)).toBeCloseTo(2.8)
		end)
	end)

	describe("DifficultyMath.extraEnemiesPerRoom", function()
		it("no agrega enemigos en el piso 1 en solitario", function()
			expect(DifficultyMath.extraEnemiesPerRoom(1, 1)).toBe(0)
		end)

		it("suma un enemigo por piso y otro por jugador adicional", function()
			expect(DifficultyMath.extraEnemiesPerRoom(3, 1)).toBe(2)
			expect(DifficultyMath.extraEnemiesPerRoom(1, 4)).toBe(3)
			expect(DifficultyMath.extraEnemiesPerRoom(3, 4)).toBe(5)
		end)
	end)

	describe("DifficultyMath.scaledEnemyHealth", function()
		it("redondea a entero", function()
			-- EnemyChaser base 30, piso 2, un jugador: 30 * 1.3 = 39
			expect(DifficultyMath.scaledEnemyHealth(30, 2, 1)).toBe(39)
		end)

		it("nunca deja un enemigo por debajo de 1 de vida", function()
			expect(DifficultyMath.scaledEnemyHealth(0.1, 1, 1)).toBe(1)
		end)

		it("rechaza vida base no positiva", function()
			expect(function()
				DifficultyMath.scaledEnemyHealth(0, 1, 1)
			end).toThrow()
		end)
	end)

	describe("DifficultyMath.roomCountForFloor", function()
		it("sigue la formula 7 + (piso - 1)", function()
			expect(DifficultyMath.roomCountForFloor(1, 7)).toBe(7)
			expect(DifficultyMath.roomCountForFloor(3, 7)).toBe(9)
		end)
	end)

	describe("DifficultyMath.enemyCountForRoom", function()
		it("en el piso 1 y en solitario spawnea la cantidad base", function()
			expect(DifficultyMath.enemyCountForRoom(3, 1, 1)).toBe(3)
		end)

		it("suma un enemigo por piso y otro por jugador adicional", function()
			expect(DifficultyMath.enemyCountForRoom(3, 3, 1)).toBe(5) -- 3 + 2 pisos
			expect(DifficultyMath.enemyCountForRoom(3, 1, 4)).toBe(6) -- 3 + 3 jugadores
			expect(DifficultyMath.enemyCountForRoom(3, 3, 4)).toBe(8) -- 3 + 2 + 3
		end)

		-- Una sala de combate con cero enemigos se auto-limpia al instante y el jugador
		-- la cruza sin entender que paso.
		it("nunca spawnea menos de un enemigo", function()
			expect(DifficultyMath.enemyCountForRoom(1, 1, 1)).toBe(1)
		end)

		it("rechaza una cantidad base invalida", function()
			expect(function()
				DifficultyMath.enemyCountForRoom(0, 1, 1)
			end).toThrow()
		end)
	end)
end

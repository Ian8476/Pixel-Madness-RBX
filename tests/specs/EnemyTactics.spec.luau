--!strict
--[[
	Tests de las decisiones de los enemigos.

	Lo que se protege aca es sobre todo el comportamiento del Shooter, que es el que
	tiene una forma facil de salir mal: sin banda muerta tiembla en el lugar, y sin
	conservar el rumbo termina orbitando al jugador. Las dos cosas se ven horribles y
	las dos son un numero mal puesto, no un bug evidente.
]]

local EnemyTactics = require("../../src/shared/Logic/EnemyTactics")

local function point(x: number, z: number): any
	return { x = x, z = z }
end

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("EnemyTactics.nearestTargetIndex", function()
		it("sin objetivos no elige ninguno", function()
			expect(EnemyTactics.nearestTargetIndex(0, 0, {})).toBe(nil)
		end)

		it("elige el mas cercano", function()
			local targets = { point(50, 0), point(3, 4), point(-20, -20) }

			expect(EnemyTactics.nearestTargetIndex(0, 0, targets)).toBe(2)
		end)

		it("mide en el plano y no le importa el orden de la lista", function()
			expect(EnemyTactics.nearestTargetIndex(10, 10, { point(10, 20), point(10, 12) })).toBe(2)
			expect(EnemyTactics.nearestTargetIndex(10, 10, { point(10, 12), point(10, 20) })).toBe(1)
		end)

		-- Sin desempate determinista, dos enemigos parados en el mismo lugar podrian
		-- elegir jugadores distintos y verse titubear.
		it("en un empate exacto gana siempre el primero", function()
			local targets = { point(5, 0), point(-5, 0) }

			expect(EnemyTactics.nearestTargetIndex(0, 0, targets)).toBe(1)
			expect(EnemyTactics.nearestTargetIndex(0, 0, targets)).toBe(1)
		end)
	end)

	describe("EnemyTactics.preferredStandPoint", function()
		it("dentro de la banda muerta no se mueve", function()
			-- Esta a 26 de un preferido de 24, con tolerancia 4: esta comodo.
			local x, z, shouldMove = EnemyTactics.preferredStandPoint(26, 0, 0, 0, 24, 4)

			expect(shouldMove).toBe(false)
			expect(x).toBe(26)
			expect(z).toBe(0)
		end)

		it("si esta lejos se acerca hasta la distancia exacta", function()
			local x, z, shouldMove = EnemyTactics.preferredStandPoint(60, 0, 0, 0, 24, 4)

			expect(shouldMove).toBe(true)
			expect(x).toBeCloseTo(24, 1e-6)
			expect(z).toBeCloseTo(0, 1e-6)
		end)

		it("si esta encima se aleja hasta la distancia exacta", function()
			local x, z, shouldMove = EnemyTactics.preferredStandPoint(5, 0, 0, 0, 24, 4)

			expect(shouldMove).toBe(true)
			expect(x).toBeCloseTo(24, 1e-6)
			expect(z).toBeCloseTo(0, 1e-6)
		end)

		-- Si no conservara el rumbo, el Shooter orbitaria al jugador en vez de
		-- plantarse, y en top-down con niebla eso es ilegible.
		it("conserva el rumbo: no rodea al objetivo", function()
			-- Enemigo en diagonal exacta respecto del objetivo.
			local x, z = EnemyTactics.preferredStandPoint(10, 10, 0, 0, 24, 1)
			local expected = 24 / math.sqrt(2)

			expect(x).toBeCloseTo(expected, 1e-6)
			expect(z).toBeCloseTo(expected, 1e-6)
		end)

		it("el punto elegido queda siempre a la distancia preferida", function()
			for _, start in { { 3, 71 }, { -40, 5 }, { 0, 9 }, { 100, -100 } } do
				local x, z = EnemyTactics.preferredStandPoint(start[1], start[2], 12, -7, 24, 0)

				expect(EnemyTactics.flatDistance(x, z, 12, -7)).toBeCloseTo(24, 1e-6)
			end
		end)

		-- Division por cero si no se cubre: el enemigo pisando exactamente al jugador.
		it("sobrevive a estar exactamente encima del objetivo", function()
			local x, z, shouldMove = EnemyTactics.preferredStandPoint(0, 0, 0, 0, 24, 4)

			expect(shouldMove).toBe(true)
			expect(x == x).toBe(true) -- no es NaN
			expect(z == z).toBe(true)
			expect(EnemyTactics.flatDistance(x, z, 0, 0)).toBeCloseTo(24, 1e-6)
		end)
	end)

	describe("EnemyTactics.directionTo", function()
		it("devuelve un vector unitario", function()
			local dx, dz = EnemyTactics.directionTo(0, 0, 3, 4)

			expect(dx).toBeCloseTo(0.6, 1e-6)
			expect(dz).toBeCloseTo(0.8, 1e-6)
		end)

		it("no inventa una direccion cuando los puntos coinciden", function()
			local dx, dz = EnemyTactics.directionTo(7, 7, 7, 7)

			expect(dx).toBe(nil)
			expect(dz).toBe(nil)
		end)
	end)

	describe("EnemyTactics.flatDistance", function()
		it("mide en el plano", function()
			expect(EnemyTactics.flatDistance(0, 0, 3, 4)).toBeCloseTo(5, 1e-6)
			expect(EnemyTactics.flatDistance(-2, -2, -2, -2)).toBe(0)
		end)
	end)
end

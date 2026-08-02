--!strict
--[[
	Tests del abanico de disparo. El caso de La Escupechatarra (6 proyectiles en 35
	grados) es el que define el contrato: si alguien "optimiza" el reparto y el arma
	deja de abrir 35 grados reales, este archivo lo caza.
]]

local SpreadMath = require("../../src/shared/Logic/SpreadMath")

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("SpreadMath.fanAngles", function()
		it("un solo proyectil va recto", function()
			expect(SpreadMath.fanAngles(1, 0)).toEqual({ 0 })
			expect(SpreadMath.fanAngles(1, 35)).toEqual({ 0 })
		end)

		it("reparte La Escupechatarra en 35 grados exactos", function()
			local angles = SpreadMath.fanAngles(6, 35)

			expect(#angles).toBe(6)
			expect(angles[1]).toBeCloseTo(-17.5, 1e-6)
			expect(angles[6]).toBeCloseTo(17.5, 1e-6)
			expect(angles[6] - angles[1]).toBeCloseTo(35, 1e-6)
		end)

		it("mantiene el abanico simetrico y uniforme", function()
			local angles = SpreadMath.fanAngles(3, 22)

			expect(angles[1]).toBeCloseTo(-11, 1e-6)
			expect(angles[2]).toBeCloseTo(0, 1e-6)
			expect(angles[3]).toBeCloseTo(11, 1e-6)
		end)

		it("con spread 0 todos los proyectiles van al mismo angulo", function()
			expect(SpreadMath.fanAngles(3, 0)).toEqual({ 0, 0, 0 })
		end)

		it("rechaza conteos invalidos", function()
			expect(function()
				SpreadMath.fanAngles(0, 10)
			end).toThrow()

			expect(function()
				SpreadMath.fanAngles(2.5, 10)
			end).toThrow()

			expect(function()
				SpreadMath.fanAngles(2, -1)
			end).toThrow()
		end)
	end)

	describe("SpreadMath.applyJitter", function()
		it("sin jitter devuelve una copia identica", function()
			local base = { -10, 0, 10 }

			expect(SpreadMath.applyJitter(base, 0, function()
				return 0.5
			end)).toEqual(base)
		end)

		it("desplaza el maximo posible con el random en los extremos", function()
			-- random = 1 -> +jitter completo; random = 0 -> -jitter completo
			expect(SpreadMath.applyJitter({ 0 }, 2, function()
				return 1
			end)[1]).toBeCloseTo(2, 1e-6)

			expect(SpreadMath.applyJitter({ 0 }, 2, function()
				return 0
			end)[1]).toBeCloseTo(-2, 1e-6)
		end)

		it("no muta la tabla original", function()
			local base = { 5 }

			SpreadMath.applyJitter(base, 2, function()
				return 1
			end)

			expect(base[1]).toBe(5)
		end)
	end)

	describe("SpreadMath.rotateHorizontal", function()
		it("rotar 0 grados no cambia nada", function()
			local x, z = SpreadMath.rotateHorizontal(0, 1, 0)

			expect(x).toBeCloseTo(0, 1e-6)
			expect(z).toBeCloseTo(1, 1e-6)
		end)

		it("rotar 90 grados cambia el eje", function()
			local x, z = SpreadMath.rotateHorizontal(0, 1, 90)

			expect(x).toBeCloseTo(-1, 1e-6)
			expect(z).toBeCloseTo(0, 1e-6)
		end)

		it("conserva la magnitud del vector", function()
			local x, z = SpreadMath.rotateHorizontal(0, 1, 37)

			expect(math.sqrt(x * x + z * z)).toBeCloseTo(1, 1e-6)
		end)
	end)
end

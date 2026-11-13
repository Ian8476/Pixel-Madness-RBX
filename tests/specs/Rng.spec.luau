--!strict
--[[
	Tests del generador pseudoaleatorio propio.

	Lo unico que este modulo tiene que garantizar de verdad es REPRODUCIBILIDAD: la
	misma semilla, la misma secuencia, siempre. Todo lo demas (que reparta parejo, que
	respete rangos) es higiene para que la mazmorra no salga deforme.
]]

local Rng = require("../../src/shared/Logic/Rng")

local function take(rng: any, count: number): { number }
	local values = {}

	for _ = 1, count do
		table.insert(values, rng:nextUnit())
	end

	return values
end

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("Rng: reproducibilidad", function()
		it("la misma semilla da la misma secuencia", function()
			expect(take(Rng.new(12345), 20)).toEqual(take(Rng.new(12345), 20))
		end)

		it("semillas distintas dan secuencias distintas", function()
			local a = take(Rng.new(1), 10)
			local b = take(Rng.new(2), 10)
			local identical = true

			for index, value in a do
				if value ~= b[index] then
					identical = false
					break
				end
			end

			expect(identical).toBe(false)
		end)

		-- xorshift se queda clavado en cero para siempre si el estado llega a valer 0.
		it("la semilla 0 no deja el generador muerto", function()
			local values = take(Rng.new(0), 5)

			for _, value in values do
				expect(value ~= 0).toBe(true)
			end
		end)

		-- Semillas chicas y consecutivas son el caso real: los pisos 1, 2 y 3 de una
		-- run suelen sembrarse a partir de un mismo numero.
		it("semillas consecutivas y chicas no se parecen", function()
			expect(Rng.new(1):nextUnit() ~= Rng.new(2):nextUnit()).toBe(true)
			expect(Rng.new(2):nextUnit() ~= Rng.new(3):nextUnit()).toBe(true)
		end)
	end)

	describe("Rng.nextUnit", function()
		it("siempre cae en [0, 1)", function()
			local rng = Rng.new(777)

			for _ = 1, 500 do
				local value = rng:nextUnit()

				expect(value >= 0 and value < 1).toBe(true)
			end
		end)
	end)

	describe("Rng.nextInteger", function()
		it("respeta el rango y cubre los extremos", function()
			local rng = Rng.new(42)
			local seenMin = false
			local seenMax = false

			for _ = 1, 500 do
				local value = rng:nextInteger(1, 4)

				expect(value >= 1 and value <= 4).toBe(true)
				expect(value % 1).toBe(0)

				if value == 1 then
					seenMin = true
				elseif value == 4 then
					seenMax = true
				end
			end

			expect(seenMin).toBe(true)
			expect(seenMax).toBe(true)
		end)

		it("un rango de un solo valor devuelve ese valor", function()
			local rng = Rng.new(9)

			expect(rng:nextInteger(5, 5)).toBe(5)
		end)

		it("rechaza rangos invertidos", function()
			local rng = Rng.new(9)

			expect(function()
				rng:nextInteger(10, 1)
			end).toThrow()
		end)
	end)

	describe("Rng.shuffled", function()
		it("no muta la lista original y conserva todos los elementos", function()
			local original = { "a", "b", "c", "d", "e" }
			local shuffled = Rng.new(5):shuffled(original)

			expect(original).toEqual({ "a", "b", "c", "d", "e" })
			expect(#shuffled).toBe(5)

			local seen: { [string]: boolean } = {}

			for _, value in shuffled do
				seen[value] = true
			end

			for _, value in original do
				expect(seen[value]).toBe(true)
			end
		end)

		it("es reproducible con la misma semilla", function()
			local list = { 1, 2, 3, 4, 5, 6, 7, 8 }

			expect(Rng.new(31):shuffled(list)).toEqual(Rng.new(31):shuffled(list))
		end)
	end)

	describe("Rng.pick", function()
		it("rechaza listas vacias", function()
			local rng = Rng.new(1)

			expect(function()
				rng:pick({})
			end).toThrow()
		end)
	end)
end

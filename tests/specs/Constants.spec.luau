--!strict
--[[
	Constants no se testea "por testear": se protege el invariante que hace que el
	resto del proyecto tenga sentido. La conversion 1 unidad Unity = 3 studs esta
	horneada en decenas de valores de diseno; si alguien la toca sin recalcular el
	resto, el juego queda descalibrado de forma silenciosa.

	Este archivo tambien es la prueba de que Constants sigue siendo Lune-compatible:
	el dia que alguien meta un Vector3 aqui, este test deja de poder cargarse.
]]

local Constants = require("../../src/shared/Constants")

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("Constants", function()
		it("mantiene la conversion de escala Unity -> Roblox", function()
			expect(Constants.STUDS_PER_UNITY_UNIT).toBe(3)
		end)

		it("deriva el tamano de sala de la conversion de escala (24 u * 3)", function()
			expect(Constants.ROOM_SIZE_STUDS).toBe(24 * Constants.STUDS_PER_UNITY_UNIT)
		end)

		it("deriva el iman de moneda de la conversion de escala (4 u * 3)", function()
			expect(Constants.COIN_MAGNET_RADIUS_STUDS).toBe(4 * Constants.STUDS_PER_UNITY_UNIT)
		end)

		it("deriva la distancia preferida del Shooter (8 u * 3)", function()
			expect(Constants.SHOOTER_PREFERRED_DISTANCE_STUDS).toBe(8 * Constants.STUDS_PER_UNITY_UNIT)
		end)

		it("es una tabla congelada: nadie muta constantes en runtime", function()
			expect(table.isfrozen(Constants)).toBe(true)
		end)
	end)
end

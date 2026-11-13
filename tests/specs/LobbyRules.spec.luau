--!strict
--[[
	Tests de las reglas de arranque del lobby.

	Son cuatro lineas de codigo y aun asi merecen tests, porque los dos fallos posibles
	son silenciosos: un servidor que arranca una run con cero jugadores deja una
	mazmorra girando sola, y uno que no arranca nunca deja a la gente mirando un boton
	que no hace nada. Ninguno de los dos tira un error.
]]

local LobbyRules = require("../../src/shared/Logic/LobbyRules")

return function(api)
	local describe, it, expect = api.describe, api.it, api.expect

	describe("LobbyRules.shouldCountdown", function()
		-- El caso que de verdad importa: un servidor vacio no puede empezar solo.
		it("un servidor sin jugadores nunca arranca", function()
			expect(LobbyRules.shouldCountdown(0, 0)).toBe(false)
		end)

		it("un jugador solo alcanza si esta listo", function()
			expect(LobbyRules.shouldCountdown(1, 0)).toBe(false)
			expect(LobbyRules.shouldCountdown(1, 1)).toBe(true)
		end)

		it("con varios, arranca cuando estan TODOS", function()
			expect(LobbyRules.shouldCountdown(4, 3)).toBe(false)
			expect(LobbyRules.shouldCountdown(4, 4)).toBe(true)
		end)

		-- Puede pasar de verdad: alguien se va justo despues de marcarse listo y por un
		-- instante hay mas "listos" registrados que jugadores conectados.
		it("aguanta mas listos que jugadores sin trabarse", function()
			expect(LobbyRules.shouldCountdown(2, 3)).toBe(true)
		end)
	end)

	describe("LobbyRules.remainingToStart", function()
		it("dice cuantos faltan", function()
			expect(LobbyRules.remainingToStart(4, 1)).toBe(3)
			expect(LobbyRules.remainingToStart(4, 4)).toBe(0)
		end)

		it("nunca devuelve negativos", function()
			expect(LobbyRules.remainingToStart(2, 5)).toBe(0)
			expect(LobbyRules.remainingToStart(0, 0)).toBe(0)
		end)
	end)
end

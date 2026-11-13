--!strict
--[[
	El Bonkaron: el jefe. Un Chaser escalado 2.5x, exactamente como lo definio el
	diseno original.

	Es lentisimo a proposito (6 de velocidad, la mitad que un Chaser comun): un jefe que
	te alcanza no es un jefe, es un accidente. A esta velocidad SIEMPRE se le puede
	sacar el cuerpo, y la pelea se trata de cuanto dano le podes meter mientras te
	moves, no de si te toca o no.

	Pega 25 de contacto, o sea que a Nina (80 de vida) la mata en cuatro toques y a
	Bonko (130) en seis. Esa diferencia es la que hace que el personaje fragil se
	sienta fragil justo cuando importa.

	PROVISIONAL: el Bonkaron de verdad, con fases y patrones de balas, es de la Fase 8.
	Este es el de la Fase 4 y su cerebro es literalmente el del Chaser.
]]

return table.freeze({
	id = "el_bonkaron",
	displayName = "El Bonkaron",
	brain = "Chaser",
	greyboxColor = { r = 214, g = 72, b = 72 },

	baseHealth = 400,
	walkSpeed = 6,
	contactDamage = 25,
	modelScale = 2.5,

	minCoinDrop = 15,
	maxCoinDrop = 25,

	isBoss = true,
})

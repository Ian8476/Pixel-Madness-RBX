--!strict
--[[
	El Chaser: el enemigo base. Corre hacia vos y te pega con el cuerpo.

	Es mas lento que Nina (12 contra 22) y mas rapido que Bonko (12 contra 16). Eso es
	deliberado: con el tanque no podes huir, tenes que pelear; con la rapida siempre
	podes salir. Es la primera decision tactica que el juego le propone al jugador y
	sale de estos dos numeros, no de codigo.

	REGLA DE LA CARPETA Shared/Data/: sin `require` y sin datatypes de Roblox (por eso
	el color es {r, g, b}), para que el test de esquema del CI cargue el contenido REAL.
]]

return table.freeze({
	id = "chaser",
	displayName = "Perseguidor",
	brain = "Chaser",
	greyboxColor = { r = 198, g = 62, b = 62 },

	baseHealth = 30,
	walkSpeed = 12,
	contactDamage = 10,
	modelScale = 1,

	minCoinDrop = 1,
	maxCoinDrop = 3,
})

--!strict
--[[
	El Shooter: mantiene distancia y dispara balas lentas y grandes.

	Los 30 studs/s de sus balas son el numero mas importante de este archivo y no es un
	numero de balance, es de NETCODE: a esa velocidad, una bala tarda casi un segundo en
	cruzar la distancia que la separa del jugador, asi que los 50-100 ms de latencia de
	replicacion no le quitan al jugador la posibilidad de esquivarla. "Leer las balas"
	solo funciona si las balas se pueden leer.

	Tiene dano por contacto bajo (6) en vez de cero: si no, el jugador podria pararsele
	encima y matarlo sin riesgo, que es justo la respuesta que no queremos premiar.
]]

return table.freeze({
	id = "shooter",
	displayName = "Escupidor",
	brain = "Shooter",
	greyboxColor = { r = 150, g = 82, b = 200 },

	baseHealth = 20,
	walkSpeed = 10,
	contactDamage = 6,
	modelScale = 1,

	minCoinDrop = 1,
	maxCoinDrop = 3,

	projectileDamage = 8,
	projectileSpeed = 30,
	fireRate = 0.8,
	preferredDistanceStuds = 24,
})

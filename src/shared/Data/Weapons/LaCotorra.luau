--!strict
--[[
	La Cotorra: cadencia de 10 disparos por segundo, el arma mas rapida del juego.

	Es la referencia para dimensionar el presupuesto del rate limiter de FireRequest
	y el arma que mas balas vivas genera: cualquier regresion de rendimiento en
	ProjectileSystem se nota primero con esta en la mano.
]]

return table.freeze({
	id = "la_cotorra",
	displayName = "La Cotorra",
	flavorText = "No se calla nunca.",

	fireRate = 10,
	projectilesPerShot = 1,
	spreadDegrees = 9,
	damage = 5,
	projectileSpeed = 66,
	energyCost = 1,

	isAutomatic = true,
	isPiercing = false,
	knockback = 4,
	projectileScale = 0.7,
	projectileColor = { r = 160, g = 255, b = 210 },
})

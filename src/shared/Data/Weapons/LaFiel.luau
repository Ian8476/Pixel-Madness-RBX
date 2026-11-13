--!strict
--[[
	La Fiel: la red de seguridad del juego. Energia 0, o sea que NUNCA te quedas sin
	poder disparar. Todo lo demas del arsenal se mide contra esta.

	REGLA DE LA CARPETA Shared/Data/: estos modulos no hacen `require` de nada y no
	usan datatypes de Roblox (por eso el color es {r, g, b} y no un Color3). Esa
	restriccion es lo que permite que el test de esquema del CI los cargue en Lune,
	sin Studio, y valide el contenido REAL y no una copia de fixtures.
]]

return table.freeze({
	id = "la_fiel",
	displayName = "La Fiel",
	flavorText = "Nunca te abandona. Nunca impresiona.",

	fireRate = 4,
	projectilesPerShot = 1,
	spreadDegrees = 0,
	damage = 8,
	projectileSpeed = 66,
	energyCost = 0,

	isAutomatic = true,
	isPiercing = false,
	knockback = 12,
	projectileScale = 1,
	projectileColor = { r = 255, g = 236, b = 140 },
})

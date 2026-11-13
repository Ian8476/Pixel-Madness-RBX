--!strict
--[[
	El Tridente: tres balas en abanico de 22 grados. El punto medio del arsenal:
	cubre area sin el costo de energia de la escopeta y sin su penalidad de cadencia.
]]

return table.freeze({
	id = "el_tridente",
	displayName = "El Tridente",
	flavorText = "Tres balas, cero explicaciones.",

	fireRate = 3,
	projectilesPerShot = 3,
	spreadDegrees = 22,
	damage = 9,
	projectileSpeed = 60,
	energyCost = 5,

	isAutomatic = true,
	isPiercing = false,
	knockback = 14,
	projectileScale = 1,
	projectileColor = { r = 120, g = 200, b = 255 },
})

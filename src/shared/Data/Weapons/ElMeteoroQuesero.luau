--!strict
--[[
	El Meteoro Quesero: la unica arma piercing del MVP. Bala gigante (escala 3) y
	lentisima (24 studs/s), o sea que la ves viajar y atravesar la fila entera.

	El piercing y la escala grande van juntos por diseno: una bala que atraviesa
	tiene que ser legible durante todo su recorrido, si no parece un bug.
]]

return table.freeze({
	id = "el_meteoro_quesero",
	displayName = "El Meteoro Quesero",
	flavorText = "Nadie sabe por que es de queso.",

	fireRate = 0.8,
	projectilesPerShot = 1,
	spreadDegrees = 0,
	damage = 30,
	projectileSpeed = 24,
	energyCost = 12,

	isAutomatic = false,
	isPiercing = true,
	knockback = 25,
	projectileScale = 3,
	projectileColor = { r = 255, g = 214, b = 64 },
})

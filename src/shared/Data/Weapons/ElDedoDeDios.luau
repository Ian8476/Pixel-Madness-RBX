--!strict
--[[
	El Dedo de Dios: francotirador. 45 de dano de un tiro, por encima del umbral de
	"dano grande" (Constants.BIG_DAMAGE_THRESHOLD = 30), asi que cada impacto pinta
	el popup naranja y agrandado. Eso es intencional: el arma se siente enorme.

	Knockback deliberadamente brutal: es el unico control de multitudes del arsenal.
]]

return table.freeze({
	id = "el_dedo_de_dios",
	displayName = "El Dedo de Dios",
	flavorText = "Un disparo, una anecdota.",

	fireRate = 0.9,
	projectilesPerShot = 1,
	spreadDegrees = 0,
	damage = 45,
	projectileSpeed = 135,
	energyCost = 10,

	isAutomatic = false,
	isPiercing = false,
	knockback = 60,
	projectileScale = 1.4,
	projectileColor = { r = 255, g = 255, b = 255 },
})

--!strict
--[[
	La Escupechatarra: escopeta. 6 perdigones en 35 grados de abanico.

	Es el arma que define el contrato de SpreadMath (ver tests/specs/SpreadMath.spec):
	si alguien "optimiza" el reparto del abanico y esto deja de abrir 35 grados
	reales, el CI lo caza.

	No es automatica a proposito: el ritmo de bombear el arma es parte de su caracter.
]]

return table.freeze({
	id = "la_escupechatarra",
	displayName = "La Escupechatarra",
	flavorText = "Legalmente, una escopeta.",

	fireRate = 1.3,
	projectilesPerShot = 6,
	spreadDegrees = 35,
	damage = 6,
	projectileSpeed = 54,
	energyCost = 6,

	isAutomatic = false,
	isPiercing = false,
	-- Knockback por perdigon: seis impactos casi simultaneos empujan mucho mas que
	-- el numero suelto que se lee aca.
	knockback = 8,
	projectileScale = 0.8,
	projectileColor = { r = 255, g = 180, b = 90 },
})

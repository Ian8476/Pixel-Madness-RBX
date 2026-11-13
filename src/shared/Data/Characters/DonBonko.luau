--!strict
--[[
	Don Bonko: el tanque. Mas vida que nadie, energia y regeneracion bajas.

	Su ulti (DualWield) NO VALE NADA sin una segunda arma. Eso es diseno, no un
	descuido: es el personaje que empuja al jugador a explorar y a recoger armas.
	Si algun dia se "arregla" dandole un arma extra gratis, se rompe su motivo de existir.

	Ver la regla de la carpeta en Shared/Data/Weapons/LaFiel.luau: sin requires y sin
	datatypes de Roblox, para que el CI valide el contenido real en Lune.
]]

return table.freeze({
	id = "don_bonko",
	displayName = "Don Bonko",
	flavorText = "Golpea primero. Pregunta jamas.",
	greyboxColor = { r = 235, g = 122, b = 40 },

	maxHealth = 130,
	walkSpeed = 16,
	maxEnergy = 100,
	energyRegenPerSecond = 4,

	ability = {
		kind = "DualWield",
		displayName = "Doble Bonk",
		flavorText = "Dos armas. Cero tecnica.",
		energyCost = 40,
		cooldownSeconds = 8,
		durationSeconds = 5,
	},

	startingWeaponId = "la_escupechatarra",
})

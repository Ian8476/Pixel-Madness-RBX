--!strict
--[[
	El Profe Voltio: el multiplicador. Mas energia y mas regeneracion que nadie, y una
	ulti que duplica la cadencia de LO QUE TENGA EN LA MANO.

	Por eso su arma inicial es La Cotorra: 10 disparos por segundo que durante 4
	segundos pasan a 20. Tambien es el personaje que hace jugable un arma mediocre,
	que es exactamente el rol que tenia en el diseno original.
]]

return table.freeze({
	id = "profe_voltio",
	displayName = "El Profe Voltio",
	flavorText = "La ciencia no es segura. Por eso funciona.",
	greyboxColor = { r = 154, g = 230, b = 60 },

	maxHealth = 100,
	walkSpeed = 18,
	maxEnergy = 120,
	energyRegenPerSecond = 7,

	ability = {
		kind = "RapidFire",
		displayName = "Sobrecarga",
		flavorText = "El manual decia que no.",
		energyCost = 35,
		cooldownSeconds = 6,
		durationSeconds = 4,
		fireRateMultiplier = 2,
	},

	startingWeaponId = "la_cotorra",
})

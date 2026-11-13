--!strict
--[[
	Nina "La Rafaga": riesgo y recompensa. La mas rapida y la mas fragil (80 de vida,
	dos golpes de un Chaser y medio).

	Su Dash cuesta poquisimo y enfria en 1.5 s: se usa TODO el tiempo. La ventana de
	invulnerabilidad es corta a proposito (0.35 s) para que sea una habilidad de
	timing y no un boton de "no me pasa nada".
]]

return table.freeze({
	id = "nina_rafaga",
	displayName = "Nina La Rafaga",
	flavorText = "Si me viste, ya era tarde.",
	greyboxColor = { r = 72, g = 219, b = 226 },

	maxHealth = 80,
	walkSpeed = 22,
	maxEnergy = 90,
	energyRegenPerSecond = 6,

	ability = {
		kind = "Dash",
		displayName = "Esfumarse",
		flavorText = "Tecnicamente sigue ahi.",
		energyCost = 20,
		cooldownSeconds = 1.5,
		impulseSpeed = 36,
		invulnerabilitySeconds = 0.35,
	},

	startingWeaponId = "la_fiel",
})

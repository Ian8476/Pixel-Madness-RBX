--!strict
--[[
	SoundLibrary: todos los sonidos del juego, en un solo lugar.

	Es DATO, no logica (regla "contenido = datos"): cambiar el sonido de la moneda es
	cambiar un numero aca, no tocar el sistema que la reproduce. No vive en
	`Shared/Data/` porque solo el cliente la usa y porque los ids de audio no se pueden
	validar en Lune (no hay forma de saber si un asset existe sin la red de Roblox).

	Todos los ids salen de la Creator Store (la "toolbox") y se verificaron en Studio
	con `ContentProvider:PreloadAsync`: cargan y son publicos. La mayoria son del set
	oficial de Roblox ("RBLX UI ...") o de catalogos con licencia de Roblox (APM,
	DistroKid). Si alguno deja de cargar, `SoundController` lo saltea en silencio: un
	sonido que falta nunca rompe el juego.

	Campos:
	  id           asset id de audio
	  volume       0..1, ya mezclado contra el resto (la musica va mucho mas baja)
	  pitch        velocidad base de reproduccion (1 = original)
	  pitchJitter  variacion aleatoria +-; evita el efecto "ametralladora de samples"
	               cuando el mismo sonido suena muchas veces seguidas
	  cooldown     segundos minimos entre dos reproducciones (escopetas, perdigones)
]]

export type SoundSpec = {
	id: number,
	volume: number,
	pitch: number?,
	pitchJitter: number?,
	cooldown: number?,
}

export type MusicSpec = {
	id: number,
	volume: number,
}

local SFX: { [string]: SoundSpec } = {
	-- Interfaz
	hover = { id = 10066936758, volume = 0.3, pitchJitter = 0.05, cooldown = 0.04 },
	click = { id = 10128760939, volume = 0.6 },
	back = { id = 10066914500, volume = 0.55 },
	panelOpen = { id = 10128766965, volume = 0.5 },
	ready = { id = 10066968815, volume = 0.65, pitch = 1.1 },
	unready = { id = 10066914500, volume = 0.5, pitch = 0.9 },
	countdown = { id = 139571940014575, volume = 0.6 },

	-- Momentos de la run
	runStart = { id = 3120909354, volume = 0.65 },
	floorUp = { id = 112485797063762, volume = 0.65 },
	roomLocked = { id = 117751546358455, volume = 0.45, pitch = 0.85 },
	roomCleared = { id = 10066947742, volume = 0.6 },
	bossAppear = { id = 117751546358455, volume = 0.6, pitch = 0.6 },
	victory = { id = 9067124098, volume = 0.75 },
	defeat = { id = 2390695935, volume = 0.7 },

	-- Combate
	shootPlayer = { id = 128598607431847, volume = 0.3, pitch = 1.15, pitchJitter = 0.08, cooldown = 0.05 },
	shootEnemy = { id = 128598607431847, volume = 0.4, pitch = 0.75, pitchJitter = 0.06, cooldown = 0.08 },
	hit = { id = 138148057831879, volume = 0.45, pitchJitter = 0.1, cooldown = 0.03 },
	hitConfirm = { id = 125235091454234, volume = 0.5, pitchJitter = 0.06, cooldown = 0.04 },
	hurt = { id = 4612384231, volume = 0.7, pitchJitter = 0.08, cooldown = 0.15 },
	enemyDown = { id = 140323850218372, volume = 0.65, pitchJitter = 0.15 },
	ability = { id = 2390691299, volume = 0.55 },
	abilityReady = { id = 6586979979, volume = 0.5, pitch = 1.3 },
	dash = { id = 12222200, volume = 0.8, pitchJitter = 0.05 },

	-- Botin
	coin = { id = 607665037, volume = 0.4, pitchJitter = 0.03 },
	weaponPickup = { id = 6586979979, volume = 0.6, pitch = 0.9 },
	weaponSwap = { id = 10066936758, volume = 0.55, pitch = 0.8 },
}

local MUSIC: { [string]: MusicSpec } = {
	lobby = { id = 1836039989, volume = 0.28 }, -- "Bouncy Way" (APM)
	run = { id = 1842054001, volume = 0.2 }, -- "Stay Out the Shed (b)" (APM)
	boss = { id = 81329998466828, volume = 0.26 }, -- "8 Bit Boss Battle"
}

return table.freeze({
	sfx = table.freeze(SFX),
	music = table.freeze(MUSIC),
})

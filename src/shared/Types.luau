--!strict
--[[
	Types: unica fuente de verdad de los contratos de datos del juego.

	Aqui viven los esquemas de contenido (regla 1: contenido = datos) y los payloads
	que cruzan la frontera cliente-servidor. Este modulo SI puede usar datatypes de
	Roblox (Color3, Vector3) porque no se ejecuta en Lune; los modulos puros de
	Shared/Logic/ declaran sus propios tipos y no dependen de este archivo.

	Nota sobre habilidades: AbilityDef es una union discriminada por el campo `kind`.
	Eso hace que `if ability.kind == "Dash" then` estreche el tipo automaticamente y
	que agregar una habilidad nueva rompa la compilacion en los lugares que hay que
	tocar, en vez de fallar en runtime.
]]

export type WeaponId = string
export type CharacterId = string
export type EnemyId = string

--[[
	Color como tripleta 0-255 en vez de Color3.

	Motivo (Fase 2): los modulos de Shared/Data/ no pueden usar datatypes de Roblox,
	porque la regla de esa carpeta es que el test de esquema del CI cargue el
	contenido REAL en Lune, sin Studio. El consumidor construye el Color3 con
	`Color3.fromRGB(c.r, c.g, c.b)`. Es el mismo precedente que `Constants.DUNGEON_ORIGIN`,
	que es una tripleta `{x, y, z}` y no un Vector3 por identica razon.
]]
export type Rgb = { r: number, g: number, b: number }

--------------------------------------------------------------------------------
-- Contenido: armas
--------------------------------------------------------------------------------

export type WeaponDef = {
	id: WeaponId,
	displayName: string,
	flavorText: string,

	fireRate: number, -- disparos por segundo
	projectilesPerShot: number,
	spreadDegrees: number, -- apertura total del abanico
	damage: number,
	projectileSpeed: number, -- studs/s
	energyCost: number, -- 0 = arma infinita

	isAutomatic: boolean,
	isPiercing: boolean,
	knockback: number, -- impulso aplicado al Humanoid golpeado
	projectileScale: number, -- 1 = tamano base
	-- Cada arma tiene su color de bala: en un top-down con niebla, leer las balas ES
	-- el juego, y el color es la forma mas barata de saber que te esta llegando.
	projectileColor: Rgb,

	modelName: string?, -- nombre de un Model en ReplicatedStorage/Assets
}

--------------------------------------------------------------------------------
-- Contenido: personajes y habilidades
--------------------------------------------------------------------------------

export type AbilityKind = "Dash" | "DualWield" | "RapidFire"

type AbilityBase = {
	displayName: string,
	flavorText: string,
	energyCost: number,
	cooldownSeconds: number,
}

export type DashAbility = AbilityBase & {
	kind: "Dash",
	impulseSpeed: number, -- studs/s
	invulnerabilitySeconds: number,
}

export type DualWieldAbility = AbilityBase & {
	kind: "DualWield",
	durationSeconds: number,
}

export type RapidFireAbility = AbilityBase & {
	kind: "RapidFire",
	durationSeconds: number,
	fireRateMultiplier: number,
}

export type AbilityDef = DashAbility | DualWieldAbility | RapidFireAbility

export type CharacterDef = {
	id: CharacterId,
	displayName: string,
	flavorText: string,
	greyboxColor: Rgb,

	maxHealth: number,
	walkSpeed: number,
	maxEnergy: number,
	energyRegenPerSecond: number,

	ability: AbilityDef,
	startingWeaponId: WeaponId,

	modelName: string?,
}

--------------------------------------------------------------------------------
-- Contenido: enemigos
--------------------------------------------------------------------------------

export type EnemyBrainKind = "Chaser" | "Shooter"

export type EnemyDef = {
	id: EnemyId,
	displayName: string,
	brain: EnemyBrainKind,
	greyboxColor: Rgb,

	baseHealth: number,
	walkSpeed: number,
	contactDamage: number,
	modelScale: number,

	minCoinDrop: number,
	maxCoinDrop: number,

	-- Solo Shooter
	projectileDamage: number?,
	projectileSpeed: number?,
	fireRate: number?,
	preferredDistanceStuds: number?, -- distancia que intenta mantener del objetivo

	-- Marca al jefe: escala su vida por jugador con la formula del jefe (no la comun),
	-- lleva el tag Boss y su muerte termina la run.
	isBoss: boolean?,
}

--------------------------------------------------------------------------------
-- Mundo
--------------------------------------------------------------------------------

export type RoomType = "Start" | "Combat" | "Item" | "Portal" | "Boss"
export type RoomSide = "North" | "South" | "East" | "West"
export type SideState = "SolidWall" | "OpenWall" | "Door"

--------------------------------------------------------------------------------
-- Estado de run (servidor es la unica fuente de verdad, regla 5)
--------------------------------------------------------------------------------

export type RunPhase = "Lobby" | "InRun" | "Victory" | "Defeat"

--[[
	Una fila de la lista del lobby. Lleva `userId` y no solo el nombre porque el nombre
	no es una clave: dos jugadores pueden tener el mismo DisplayName.
]]
export type LobbyMember = {
	userId: number,
	displayName: string,
	characterId: CharacterId?,
	isReady: boolean,
}

--[[
	`roster` y `countdownRemaining` viajan SOLO durante el lobby (nil en el resto de las
	fases). No es microoptimizacion: este snapshot tambien se emite cuando entran
	monedas, o sea varias veces por segundo en pleno combate, y no tiene sentido
	repetirle a cuatro clientes una lista que no cambia y que ninguno esta mirando.
]]
export type RunStateSnapshot = {
	phase: RunPhase,
	floorNumber: number,
	floorsPerRun: number,
	sharedCoins: number,
	playerCount: number,
	roster: { LobbyMember }?,
	countdownRemaining: number?,
}

--[[
	Todo lo que el dueno de un personaje necesita saber de si mismo, en un solo
	paquete. Va por `PlayerStatsChanged`, throttled a Constants.STATS_REPLICATION_HZ.

	`activeSlot` y `fireRateMultiplier` no son decoracion de HUD: el cliente los usa
	para decidir cada cuanto MANDA un FireRequest (cortesia de ancho de banda). La
	cadencia real la sigue imponiendo el servidor; esto solo evita mandar 60 mensajes
	por segundo para un arma que dispara 4 veces.
]]
export type PlayerStatsSnapshot = {
	health: number,
	maxHealth: number,
	energy: number,
	maxEnergy: number,
	characterId: CharacterId?,
	primaryWeaponId: WeaponId?,
	secondaryWeaponId: WeaponId?,
	activeSlot: number, -- 1 o 2
	fireRateMultiplier: number, -- 1 = normal; 2 mientras dura Sobrecarga
	isDualWielding: boolean,
	abilityCooldownRemaining: number,
}

--------------------------------------------------------------------------------
-- Payloads de remotes (contrato de Shared/Remotes.luau)
--------------------------------------------------------------------------------

export type FireRequestPayload = {
	aimDirection: Vector3, -- unitario y horizontal; el servidor lo revalida
}

export type PickupRequestPayload = {
	pickup: Instance,
}

export type SelectCharacterPayload = {
	characterId: CharacterId,
}

export type DamageDealtPayload = {
	position: Vector3,
	amount: number,
}

--[[
	Confirmacion de habilidad, del servidor al dueno. El servidor ya cobro la energia,
	arranco el cooldown y (si corresponde) concedio la invulnerabilidad: esto es un
	permiso para que el cliente PINTE la habilidad, no una orden de calcularla.

	Existe por el Dash: el impulso lo aplica el cliente porque es el dueno de red de
	su propio personaje, y esperar un round-trip para moverse arruina la habilidad
	que mas depende del timing del juego.
]]
export type AbilityActivatedPayload = {
	kind: AbilityKind,
	direction: Vector3?, -- solo Dash: hacia donde empujar
	impulseSpeed: number?, -- solo Dash: studs/s
	durationSeconds: number,
}

export type FXEventPayload = {
	effectId: string,
	position: Vector3,
}

return table.freeze({})

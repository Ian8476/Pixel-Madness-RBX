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
	greyboxColor: Color3,

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
	greyboxColor: Color3,

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

export type RunStateSnapshot = {
	phase: RunPhase,
	floorNumber: number,
	floorsPerRun: number,
	sharedCoins: number,
	playerCount: number,
}

export type PlayerStatsSnapshot = {
	health: number,
	maxHealth: number,
	energy: number,
	maxEnergy: number,
	characterId: CharacterId?,
	primaryWeaponId: WeaponId?,
	secondaryWeaponId: WeaponId?,
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

export type FXEventPayload = {
	effectId: string,
	position: Vector3,
}

return table.freeze({})

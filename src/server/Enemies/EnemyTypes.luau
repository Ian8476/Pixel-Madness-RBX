--!strict
--[[
	EnemyTypes: el tipo `Enemy` y el contexto que reciben los cerebros.

	Existe como archivo propio por una razon de dependencias, no de organizacion:
	`EnemySystem` necesita los cerebros y los cerebros necesitan el tipo `Enemy`. Si el
	tipo viviera en `EnemySystem`, cada cerebro tendria que requerirlo y el ciclo
	`EnemySystem -> Chaser -> EnemySystem` rompe el `require` de Roblox.

	Con el tipo afuera, la dependencia queda en una sola direccion:
	`EnemySystem -> cerebros -> EnemyTypes`, y ninguno de los dos lados sabe del otro.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)

local Health = require(script.Parent.Parent.Combat.Health)

export type Enemy = {
	definition: Types.EnemyDef,
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	health: Health.Health,

	-- Clave de la sala que lo spawneo. RoomService la usa para saber cuando quedo
	-- limpia; es una clave y no una referencia para no crear un ciclo entre servicios.
	roomKey: string?,

	-- Marcas de tiempo del ultimo repath / golpe / disparo. Viven en la entidad y no
	-- en el cerebro porque los cerebros son modulos SIN estado: un solo Chaser.update
	-- atiende a los treinta Chasers de la sala.
	nextRepathAt: number,
	nextContactAt: number,
	nextShotAt: number,
}

--[[
	Lo que un cerebro necesita saber del mundo para decidir. Se arma UNA vez por tick
	en EnemySystem y se reparte a todos los enemigos: sin esto, cada enemigo recorreria
	la lista de jugadores por su cuenta y el costo seria enemigos x jugadores por tick.
]]
export type Target = {
	player: Player,
	character: Model,
	root: BasePart,
	health: Health.Health,
	x: number,
	z: number,
}

export type BrainContext = {
	targets: { Target },
	now: number,
	deltaTime: number,
}

return {}

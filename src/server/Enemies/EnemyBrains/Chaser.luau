--!strict
--[[
	Cerebro Chaser: va hacia el jugador vivo mas cercano y pega por contacto.

	Este modulo NO tiene estado. Un solo `Chaser.update` atiende a los treinta Chasers
	de la sala; lo que cambia entre uno y otro vive en la entidad (`enemy.nextRepathAt`,
	`enemy.nextContactAt`). Es la misma regla que en el resto del proyecto: no hay un
	Script por entidad, hay una tabla y un bucle.

	Dos decisiones que valen la pena:

	1. `MoveTo` se re-emite cada 0.25 s y no cada frame. Cada llamada le da al Humanoid
	   un destino nuevo y reinicia su pathing interno; llamarlo 60 veces por segundo lo
	   deja recalculando en vez de caminando, y ademas es trafico de fisica al pedo.
	   0.25 s es suficiente para que persiga a un jugador que corre a 22 studs/s.

	2. El dano por contacto se resuelve por DISTANCIA, no con `Touched`. `Touched` en
	   Roblox se pierde eventos cuando las cosas se mueven rapido y dispara de mas
	   cuando se rozan; una comparacion de distancia es determinista y ademas nos deja
	   elegir el radio (mas generoso que la caja del modelo, a favor del enemigo, o mas
	   chico, a favor del jugador).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local EnemyTactics = require(Shared.Logic.EnemyTactics)

local EnemyTypes = require(script.Parent.Parent.EnemyTypes)

local Chaser = {}

--[[
	Aplica dano por contacto si el objetivo esta pegado y ya paso el enfriamiento.
	Devuelve true si conecto (lo usa el Shooter tambien: pega igual si lo acorralan).
]]
function Chaser.tryContactDamage(enemy: EnemyTypes.Enemy, target: EnemyTypes.Target, now: number): boolean
	if now < enemy.nextContactAt then
		return false
	end

	-- El alcance sale del CUERPO real del enemigo mas un margen fijo, no de multiplicar
	-- un radio por la escala: eso ultimo le daba al jefe un aura de dano de 11 studs.
	local radius = enemy.root.Size.X / 2 + Constants.ENEMY_CONTACT_GRACE_STUDS
	local distance = EnemyTactics.flatDistance(enemy.root.Position.X, enemy.root.Position.Z, target.x, target.z)

	if distance > radius then
		return false
	end

	local applied = target.health:damage(enemy.definition.contactDamage, enemy.model)

	-- El enfriamiento arranca aunque el golpe no entre (el jugador estaba invulnerable):
	-- si no, el enemigo reintentaria cada tick y pegaria en el instante exacto en que
	-- se le acaba la gracia al jugador, que es lo mismo que no tener gracia.
	enemy.nextContactAt = now + Constants.ENEMY_CONTACT_COOLDOWN_SECONDS

	return applied > 0
end

function Chaser.update(enemy: EnemyTypes.Enemy, context: EnemyTypes.BrainContext): ()
	local position = enemy.root.Position
	local index = EnemyTactics.nearestTargetIndex(position.X, position.Z, context.targets :: any)

	if not index then
		return
	end

	local target = context.targets[index]

	Chaser.tryContactDamage(enemy, target, context.now)

	if context.now < enemy.nextRepathAt then
		return
	end

	enemy.nextRepathAt = context.now + Constants.ENEMY_REPATH_INTERVAL_SECONDS
	enemy.humanoid:MoveTo(target.root.Position)
end

return table.freeze(Chaser)

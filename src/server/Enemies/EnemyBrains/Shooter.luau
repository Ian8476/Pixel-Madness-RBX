--!strict
--[[
	Cerebro Shooter: mantiene distancia y dispara balas lentas y grandes.

	La bala sale por el MISMO `ProjectileSystem` que las del jugador, con
	`team = "Enemy"`. Eso no es reutilizacion por ahorrar lineas: significa que las
	balas enemigas heredan gratis el raycast segmentado (nunca `Touched`), el
	`BulkMoveTo`, el filtrado por CollisionGroup y los popups de dano. Un segundo
	sistema de balas seria un segundo lugar donde se pierden impactos.

	La escala de la bala es 1.6: grande a proposito. Una bala que hay que esquivar
	tiene que verse desde la camara top-down y a traves de la niebla, y a 30 studs/s
	tiene tiempo de sobra para ser leida. "Leer las balas ES el juego".

	Si el jugador se le pega encima, el Shooter pega por contacto usando exactamente la
	misma funcion que el Chaser: acorralarlo tiene que costar algo, si no la respuesta
	optima contra el seria caminarle encima.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local EnemyTactics = require(Shared.Logic.EnemyTactics)

local ProjectileSystem = require(script.Parent.Parent.Parent.Combat.ProjectileSystem)
local EnemyTypes = require(script.Parent.Parent.EnemyTypes)
local Chaser = require(script.Parent.Chaser)

local BULLET_SCALE = 1.6
local BULLET_COLOR = Color3.fromRGB(255, 96, 72)

local Shooter = {}

function Shooter.update(enemy: EnemyTypes.Enemy, context: EnemyTypes.BrainContext): ()
	local position = enemy.root.Position
	local index = EnemyTactics.nearestTargetIndex(position.X, position.Z, context.targets :: any)

	if not index then
		return
	end

	local target = context.targets[index]
	local definition = enemy.definition

	Chaser.tryContactDamage(enemy, target, context.now)

	-- Colocarse
	if context.now >= enemy.nextRepathAt then
		enemy.nextRepathAt = context.now + Constants.ENEMY_REPATH_INTERVAL_SECONDS

		local preferred = definition.preferredDistanceStuds or Constants.SHOOTER_PREFERRED_DISTANCE_STUDS
		local standX, standZ, shouldMove = EnemyTactics.preferredStandPoint(
			position.X,
			position.Z,
			target.x,
			target.z,
			preferred,
			Constants.SHOOTER_DISTANCE_TOLERANCE_STUDS
		)

		if shouldMove then
			enemy.humanoid:MoveTo(Vector3.new(standX, position.Y, standZ))
		else
			-- Plantarse: sin esto, el Humanoid sigue caminando hacia el ultimo destino
			-- que le dieron y se pasa de largo la banda muerta.
			enemy.humanoid:MoveTo(position)
		end
	end

	-- Disparar
	if context.now < enemy.nextShotAt then
		return
	end

	local fireRate = definition.fireRate

	if not fireRate then
		return
	end

	enemy.nextShotAt = context.now + 1 / fireRate

	local directionX, directionZ = EnemyTactics.directionTo(position.X, position.Z, target.x, target.z)

	if not directionX or not directionZ then
		return
	end

	local direction = Vector3.new(directionX, 0, directionZ)

	ProjectileSystem.spawn({
		-- Nace en el centro del cuerpo por el mismo motivo que las del jugador (ver
		-- WeaponService): una bala que arranca adelante no puede golpear a algo que ya
		-- esta encima. EnemyBullet no colisiona con EnemyChar, asi que es seguro.
		origin = position,
		direction = direction,
		speed = definition.projectileSpeed or 30,
		damage = definition.projectileDamage or 0,
		knockback = 0, -- empujar al jugador le saca el control; eso no se hace
		isPiercing = false,
		scale = BULLET_SCALE,
		color = BULLET_COLOR,
		team = "Enemy",
		owner = nil,
	})
end

return table.freeze(Shooter)

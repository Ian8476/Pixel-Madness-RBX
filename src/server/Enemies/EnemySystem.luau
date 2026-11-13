--!strict
--[[
	EnemySystem: TODOS los enemigos vivos, en un solo Heartbeat.

	Misma regla que ProjectileSystem: no hay un Script por enemigo, hay una tabla y un
	bucle. Con 4 jugadores, +1 enemigo por jugador y +1 por piso, una sala del piso 3
	en co-op tiene mas de una decena de bichos; un Script por bicho serian decenas de
	corrutinas peleando por el mismo presupuesto de frame.

	DOS OPTIMIZACIONES QUE PARECEN DETALLES Y NO LO SON:

	1. La lista de objetivos se arma UNA vez por tick y se reparte a todos los cerebros.
	   Si cada enemigo recorriera la lista de jugadores por su cuenta, el costo seria
	   enemigos x jugadores; asi es enemigos + jugadores.

	2. El sistema NO corre a 60 Hz. Corre a `Constants.ENEMY_TICK_HZ` (20). Un enemigo
	   que decide 20 veces por segundo se comporta igual que uno que decide 60 veces
	   (el movimiento lo interpola el Humanoid, que si corre a full), y cuesta un tercio.

	La vida la lleva nuestro modulo `Health`, no `Humanoid.Health` (decision D2). El
	Humanoid es el actuador: cuando el Health logico llega a 0 se le pone la vida en 0
	para heredar gratis la animacion de muerte.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local DifficultyMath = require(Shared.Logic.DifficultyMath)
local Logger = require(Shared.Logger)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local Health = require(script.Parent.Parent.Combat.Health)
local HealthRegistry = require(script.Parent.Parent.Combat.HealthRegistry)
local EnemyFactory = require(script.Parent.EnemyFactory)
local EnemyTypes = require(script.Parent.EnemyTypes)
local Chaser = require(script.Parent.EnemyBrains.Chaser)
local Shooter = require(script.Parent.EnemyBrains.Shooter)

local CONTAINER_NAME = "Enemies"
local CORPSE_LIFETIME_SECONDS = 2.5

local log = Logger.new("EnemySystem")

local EnemySystem = {
	name = "EnemySystem",
}

-- (enemigo) al morir. Aqui se enganchan LootService (monedas), RoomService (saber si
-- la sala quedo limpia) y GameService (si era el jefe, la run termina).
EnemySystem.onEnemyDied = Signal.new() :: Signal.Signal<EnemyTypes.Enemy>

local enemies: { EnemyTypes.Enemy } = {}
local container: Folder? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local accumulator = 0

local BRAINS: { [Types.EnemyBrainKind]: (EnemyTypes.Enemy, EnemyTypes.BrainContext) -> () } = {
	Chaser = Chaser.update,
	Shooter = Shooter.update,
}

local function getContainer(): Folder
	if container and container.Parent then
		return container
	end

	local existing = workspace:FindFirstChild(CONTAINER_NAME)

	if existing and existing:IsA("Folder") then
		container = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = workspace

	container = folder

	return folder
end

--------------------------------------------------------------------------------
-- Spawn
--------------------------------------------------------------------------------

export type SpawnOptions = {
	floorNumber: number,
	playerCount: number,
	roomKey: string?,
}

--[[
	Crea un enemigo escalado y lo devuelve, o nil si el cuerpo no se pudo armar.

	El escalado de vida usa la formula del JEFE si el enemigo esta marcado como jefe, y
	la comun si no. Que la eleccion salga de los datos (`isBoss`) y no de un parametro
	del llamador evita el bug de spawnear al Bonkaron desde otro lugar y que salga con
	vida de bicho comun.
]]
function EnemySystem.spawn(definition: Types.EnemyDef, position: Vector3, options: SpawnOptions): EnemyTypes.Enemy?
	local rig = EnemyFactory.build(definition, position, getContainer())

	if not rig then
		return nil
	end

	local scaledHealth = if definition.isBoss
		then math.max(1, math.round(definition.baseHealth * DifficultyMath.bossHealthMultiplier(options.playerCount)))
		else DifficultyMath.scaledEnemyHealth(definition.baseHealth, options.floorNumber, options.playerCount)

	local health = Health.new({ maximum = scaledHealth })

	HealthRegistry.register(rig.model, health)

	local enemy: EnemyTypes.Enemy = {
		definition = definition,
		model = rig.model,
		root = rig.root,
		humanoid = rig.humanoid,
		health = health,
		roomKey = options.roomKey,
		nextRepathAt = 0,
		nextContactAt = 0,
		-- El primer disparo no sale instantaneo: si no, entrar a una sala de Shooters
		-- es recibir una salva antes de poder reaccionar.
		nextShotAt = os.clock() + 1,
	}

	if definition.isBoss then
		-- Solo el jefe replica su vida como Attribute: es lo que lee la barra grande
		-- del HUD. Hacerlo con todos seria replicar en cada impacto de cada bicho.
		rig.model:SetAttribute("MaxHealth", scaledHealth)
		rig.model:SetAttribute("Health", scaledHealth)
		rig.model:SetAttribute("DisplayName", string.upper(definition.displayName))

		health.onHealthChanged:connect(function(current: number)
			if rig.model.Parent then
				rig.model:SetAttribute("Health", current)
			end
		end)
	end

	health.onDeath:connect(function()
		rig.humanoid.Health = 0
	end)

	table.insert(enemies, enemy)

	return enemy
end

--------------------------------------------------------------------------------
-- Muerte y limpieza
--------------------------------------------------------------------------------

local function removeEnemy(enemy: EnemyTypes.Enemy, announce: boolean): ()
	HealthRegistry.unregister(enemy.model)

	if announce then
		EnemySystem.onEnemyDied:fire(enemy)
	end

	local model = enemy.model

	if model.Parent then
		-- El cadaver se queda un momento para que se vea la animacion de muerte, pero
		-- deja de estorbar en el acto: sin esto, una sala limpia sigue llena de cuerpos
		-- con colision contra los que el jugador choca.
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanQuery = false
			end
		end

		task.delay(CORPSE_LIFETIME_SECONDS, function()
			model:Destroy()
		end)
	end
end

--[[ Borra todos los enemigos sin anunciar muertes (cambio de piso, fin de run). ]]
function EnemySystem.despawnAll(): ()
	for _, enemy in enemies do
		HealthRegistry.unregister(enemy.model)
		enemy.model:Destroy()
	end

	table.clear(enemies)
end

function EnemySystem.getCount(): number
	return #enemies
end

--[[ Cuantos siguen vivos en una sala. Lo consulta RoomService para abrir las puertas. ]]
function EnemySystem.countAliveInRoom(roomKey: string): number
	local count = 0

	for _, enemy in enemies do
		if enemy.roomKey == roomKey and not enemy.health:isDead() then
			count += 1
		end
	end

	return count
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

--[[ Los jugadores a los que un enemigo puede ir. Se arma una vez por tick. ]]
local function collectTargets(): { EnemyTypes.Target }
	local targets: { EnemyTypes.Target } = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character

		if not character then
			continue
		end

		local health = CharacterService.getHealth(player)

		if not health or health:isDead() then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart")

		if not root or not root:IsA("BasePart") then
			continue
		end

		table.insert(targets, {
			player = player,
			character = character,
			root = root,
			health = health,
			x = root.Position.X,
			z = root.Position.Z,
		})
	end

	return targets
end

local function step(deltaTime: number): ()
	accumulator += deltaTime

	local interval = 1 / Constants.ENEMY_TICK_HZ

	if accumulator < interval then
		return
	end

	local elapsed = accumulator
	accumulator = 0

	if #enemies == 0 then
		return
	end

	local context: EnemyTypes.BrainContext = {
		targets = collectTargets(),
		now = os.clock(),
		deltaTime = elapsed,
	}

	local survivors: { EnemyTypes.Enemy } = table.create(#enemies)

	for _, enemy in enemies do
		-- Un enemigo puede haber muerto o haber sido destruido (piso despawneado) entre
		-- dos ticks. Se saca de la lista ANTES de que su cerebro toque una Part muerta.
		if enemy.health:isDead() or not enemy.model.Parent then
			removeEnemy(enemy, enemy.health:isDead())
			continue
		end

		table.insert(survivors, enemy)

		if #context.targets == 0 then
			continue
		end

		local brain = BRAINS[enemy.definition.brain]

		if brain then
			brain(enemy, context)
		end
	end

	enemies = survivors
end

function EnemySystem.start(): ()
	if heartbeatConnection then
		return
	end

	getContainer()
	heartbeatConnection = RunService.Heartbeat:Connect(step)

	log:info("Sistema de enemigos activo a %d Hz", Constants.ENEMY_TICK_HZ)
end

return EnemySystem

--!strict
--[[
	Bootstrap del servidor: el unico Script del contexto servidor.

	Todo lo demas son ModuleScripts. Un solo punto de entrada significa un solo lugar
	donde leer el orden real de arranque del juego, y cero sorpresas de "que corrio
	primero".

	Orden deliberado:
	  1. Infraestructura (grupos de colision, remotes). No son servicios: no tienen
	     ciclo de vida ni estado de juego, son condiciones previas.
	  2. Servicios, via ServiceLoader (init de todos, despues start de todos).

	El orden dentro de la lista importa porque son los `start` los que abren Heartbeats
	y escuchan remotes. Se lee de abajo hacia arriba en dependencias: los que producen
	antes que los que consumen.

	  Combate:  ProjectileSystem -> CharacterService -> EnergyService -> AbilityService
	            -> WeaponService -> PickupService
	  Mundo:    EnemySystem -> LootService -> RoomService
	  Run:      GameService -> PortalService
	  Espejo:   PlayerStatsReplicator

	`LobbyService` va JUSTO ANTES de `GameService` y no es casualidad: su `start`
	construye la sala del lobby, y el `start` de GameService pide los cuerpos. Si el
	orden fuera al reves, el primer jugador apareceria antes de que exista el piso
	sobre el que pararse.

	`GameService` va casi al final por lo mismo: su `start` reparte cuerpos y publica el
	estado. Todo lo que tenga que reaccionar a eso (las salas, los enemigos, el loot)
	tiene que estar escuchando ya.

	`PlayerStatsReplicator` va ultimo: es el unico que depende de todos los demas y del
	que no depende nadie.

	`DungeonGenerator`, `RoomBuilder`, `EnemyFactory`, `HealthRegistry` y los cerebros
	no estan en la lista a proposito: no tienen ciclo de vida propio, son herramientas.

	FASE 4: se borro `DevSpawnService`. El spawn de cuerpos lo controla `GameService`,
	que es lo que ese andamio venia anunciando desde la Fase 0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local ServiceLoader = require(Shared.ServiceLoader)

local AbilityService = require(script.Parent.Combat.AbilityService)
local CharacterService = require(script.Parent.Characters.CharacterService)
local EnemySystem = require(script.Parent.Enemies.EnemySystem)
local EnergyService = require(script.Parent.Combat.EnergyService)
local GameService = require(script.Parent.Core.GameService)
local LightingService = require(script.Parent.Core.LightingService)
local LobbyService = require(script.Parent.Core.LobbyService)
local LootService = require(script.Parent.World.LootService)
local PlayerStatsReplicator = require(script.Parent.Core.PlayerStatsReplicator)
local ProjectileSystem = require(script.Parent.Combat.ProjectileSystem)
local RateLimiter = require(script.Parent.Core.RateLimiter)
local WeaponService = require(script.Parent.Combat.WeaponService)
local BreakableService = require(script.Parent.World.BreakableService)
local PickupService = require(script.Parent.World.PickupService)
local PortalService = require(script.Parent.World.PortalService)
local RoomService = require(script.Parent.World.RoomService)

local log = Logger.new("Bootstrap")

log:info("Arrancando PixelMadness (servidor)")

CollisionGroups.registerAll()
Remotes.initServer()

ServiceLoader.bootstrap({
	LightingService,
	RateLimiter,
	ProjectileSystem,
	BreakableService,
	CharacterService,
	EnergyService,
	AbilityService,
	WeaponService,
	PickupService,
	EnemySystem,
	LootService,
	RoomService,
	LobbyService,
	GameService,
	PortalService,
	PlayerStatsReplicator,
})

log:info("Servidor listo")

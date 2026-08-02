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

	El orden dentro de la lista de servicios importa porque son los `start` los que
	abren Heartbeats y escuchan remotes. Se lee de abajo hacia arriba en dependencias:
	los que producen (ProjectileSystem, HealthRegistry) antes que los que consumen
	(WeaponService), y el spawn de desarrollo al final, cuando ya hay quien reciba
	al personaje que aparece.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local ServiceLoader = require(Shared.ServiceLoader)

local CharacterService = require(script.Parent.Characters.CharacterService)
local ProjectileSystem = require(script.Parent.Combat.ProjectileSystem)
local RateLimiter = require(script.Parent.Core.RateLimiter)
local WeaponService = require(script.Parent.Combat.WeaponService)
local BreakableService = require(script.Parent.World.BreakableService)

-- ANDAMIO: eliminar junto con la carpeta Dev/ en la Fase 4.
local DevSpawnService = require(script.Parent.Dev.DevSpawnService)

local log = Logger.new("Bootstrap")

log:info("Arrancando PixelMadness (servidor)")

CollisionGroups.registerAll()
Remotes.initServer()

ServiceLoader.bootstrap({
	RateLimiter,
	ProjectileSystem,
	BreakableService,
	CharacterService,
	WeaponService,
	DevSpawnService,
})

log:info("Servidor listo")

--!strict
--[[
	Constants: numeros globales del proyecto.

	REGLA DURA: este modulo no hace `require` de nada y no toca la API de Roblox.
	Esa restriccion es lo que permite ejecutarlo (y testearlo) en Lune dentro del CI
	sin abrir Studio. Si alguna vez necesitas un Vector3 aqui, construyelo en el
	modulo consumidor a partir de estos numeros: no metas datatypes de Roblox.

	Los valores vienen de la seccion 5 del documento de contexto
	(conversion adoptada: 1 unidad Unity ~= 3 studs).
]]

local Constants = {}

-- Conversion de escala heredada del prototipo Unity
Constants.STUDS_PER_UNITY_UNIT = 3

-- Mazmorra
Constants.ROOM_SIZE_STUDS = 72
Constants.DOOR_GAP_STUDS = 12
Constants.FLOORS_PER_RUN = 3
Constants.BASE_ROOM_COUNT = 7 -- roomCount = BASE_ROOM_COUNT + (piso - 1)

-- Camara top-down (offset relativo al personaje)
Constants.CAMERA_OFFSET = table.freeze({ x = 0, y = 45, z = -28 })
Constants.CAMERA_PITCH_DEGREES = -55
Constants.CAMERA_LERP_ALPHA = 0.15
Constants.CAMERA_LOOK_AHEAD_STUDS = 8

-- Combate
Constants.AIM_PLANE_HEIGHT_STUDS = 3 -- altura del pecho: plano contra el que se intersecta el rayo de mira
Constants.FIRE_RATE_TOLERANCE = 0.9 -- el servidor acepta 90% del intervalo (jitter de red)
Constants.PROJECTILE_SPREAD_JITTER_DEGREES = 2
Constants.PROJECTILE_MAX_LIFETIME_SECONDS = 4

-- Loot y pickups
Constants.COIN_MAGNET_RADIUS_STUDS = 12
Constants.COIN_LIFETIME_SECONDS = 30
Constants.PICKUP_RANGE_STUDS = 8

-- Enemigos
Constants.ENEMY_REPATH_INTERVAL_SECONDS = 0.25
Constants.SHOOTER_PREFERRED_DISTANCE_STUDS = 24

-- Presentacion
Constants.BIG_DAMAGE_THRESHOLD = 30 -- a partir de aqui el popup crece y se pone naranja
Constants.BIG_DAMAGE_POPUP_SCALE = 1.8

-- Replicacion
Constants.STATS_REPLICATION_HZ = 10 -- suficiente para una barra de vida/energia

return table.freeze(Constants)

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

-- Geometria del greybox de sala. La altura de pared es generosa a proposito: una pared
-- baja deja ver por encima el vacio de la sala de al lado. Con la camara de shooter la
-- que manda ya no es la altura de la camara sino su PITCH: mirando hacia arriba desde
-- 20 studs atras se sigue viendo por encima de una pared de 16.
Constants.WALL_HEIGHT_STUDS = 16
Constants.WALL_THICKNESS_STUDS = 2
Constants.FLOOR_THICKNESS_STUDS = 1
-- El piso se construye lejos del lobby y de la TestArena para que no se pisen.
Constants.DUNGEON_ORIGIN = table.freeze({ x = 0, y = 0, z = 1200 })
Constants.ENEMY_SPAWN_POINTS_PER_ROOM = 6
-- Radio dentro del cual un jugador cuenta como "parado en el portal".
Constants.PORTAL_ACTIVATION_RADIUS_STUDS = 10

--[[
	Iluminacion y niebla.

	LA NIEBLA SE MIDE DESDE LA CAMARA, NO DESDE EL PERSONAJE, y ese fue el bug que
	dejaba el juego en negro hasta la Fase 4: con el FogStart de 30 que traia el place y
	la vieja camara top-down (a sqrt(45^2 + 28^2) = 53 studs del jugador), el personaje
	nacia un 26% difuminado hacia el negro y la sala de al lado al 100%.

	Regla para tocar estos numeros: FOG_START tiene que ser MAYOR que la distancia de la
	camara mas media sala, o la sala en la que estas parado se empieza a borrar sola. La
	camara de shooter cambio esa cuenta: su distancia maxima es CAMERA_MAX_DISTANCE_STUDS
	(20), asi que el piso ahora es 20 + 36 = 56. FOG_START bajo de 95 a 60 por eso mismo:
	dejarlo en 95 con la camara pegada al personaje era arrancar la niebla tan lejos que
	el piso entero se veia plano.
]]
Constants.FOG_START_STUDS = 60
Constants.FOG_END_STUDS = 240 -- ~2 salas y media: se ve la de al lado, no el piso entero
Constants.FOG_COLOR = table.freeze({ r = 18, g = 16, b = 26 })

-- Sin sombras y con ambiente alto: plano y legible, que es el look que se busca.
-- El ambiente es un MULTIPLICADOR del color de la parte; con 0.23 (lo que habia), un
-- gris del 23% termina en un 5% de brillo, o sea negro.
Constants.AMBIENT_COLOR = table.freeze({ r = 96, g = 90, b = 112 })
Constants.OUTDOOR_AMBIENT_COLOR = table.freeze({ r = 128, g = 120, b = 148 })
Constants.LIGHTING_BRIGHTNESS = 2
Constants.CLOCK_TIME = 14.5 -- sol arriba: da definicion a las caras sin proyectar sombras
-- El contraste alto del grade aplastaba lo oscuro hacia el negro. Se baja y se deja que
-- el trabajo de "look sucio" lo haga la saturacion.
Constants.GRADE_CONTRAST = 0.12
Constants.GRADE_SATURATION = -0.2

--[[
	Camara de shooter en tercera persona.

	La camara orbita un pivote a la altura de los ojos y se corre al hombro para que el
	cuerpo del personaje no le tape la mira al jugador. La primera persona NO es una
	segunda camara: es esta misma con la distancia en cero, y por eso la rueda del mouse
	puede entrar y salir de ella sin pasar por ningun menu.

	MIN < distancia < MAX es el rango de tercera persona. Acercar por debajo de MIN es lo
	que dispara la primera persona; alejar desde ahi devuelve a MIN.
]]
Constants.CAMERA_EYE_HEIGHT_STUDS = 1.5 -- sobre el centro del HumanoidRootPart
Constants.CAMERA_SHOULDER_OFFSET_STUDS = 2.2
Constants.CAMERA_DEFAULT_DISTANCE_STUDS = 12
Constants.CAMERA_MIN_DISTANCE_STUDS = 6
Constants.CAMERA_MAX_DISTANCE_STUDS = 20
Constants.CAMERA_ZOOM_STEP_STUDS = 2 -- cuanto acerca o aleja un golpe de rueda
Constants.CAMERA_PITCH_MIN_DEGREES = -70
Constants.CAMERA_PITCH_MAX_DEGREES = 70
Constants.CAMERA_SENSITIVITY_DEGREES_PER_PIXEL = 0.3
-- Cuanto se despega la camara de la pared contra la que la empujaron. Sin margen, el
-- plano cercano de la camara queda DENTRO de la pared y se ve a traves de ella.
Constants.CAMERA_COLLISION_PADDING_STUDS = 0.8
Constants.CAMERA_FIELD_OF_VIEW = 70

-- Combate
-- Alcance del rayo de mira: mas alla de esto la direccion ya no cambia de forma visible.
Constants.AIM_RAY_LENGTH_STUDS = 500
-- Por debajo de esta distancia el punto de mira esta demasiado encima del jugador como
-- para sacar una direccion estable (mirando al piso, o con la nariz contra una pared).
Constants.AIM_MIN_CONVERGENCE_STUDS = 5
Constants.FIRE_RATE_TOLERANCE = 0.9 -- el servidor acepta 90% del intervalo (jitter de red)
Constants.PROJECTILE_SPREAD_JITTER_DEGREES = 2
Constants.PROJECTILE_MAX_LIFETIME_SECONDS = 4

-- Separacion entre las dos bocas de fuego mientras dura el Doble Bonk. Sin esto las
-- dos armas disparan desde el mismo punto y el jugador no ve que tiene dos.
Constants.DUAL_WIELD_MUZZLE_OFFSET_STUDS = 1.5

-- Loot y pickups
Constants.COIN_MAGNET_RADIUS_STUDS = 12
Constants.COIN_LIFETIME_SECONDS = 30
Constants.PICKUP_RANGE_STUDS = 8
Constants.WEAPON_DROP_FORWARD_STUDS = 4 -- a que distancia del jugador cae el arma que suelta
-- Un arma recien soltada no se puede volver a agarrar por un momento: sin esto, el
-- mismo E que intercambia el arma la recoge de nuevo en el frame siguiente.
Constants.PICKUP_ARM_DELAY_SECONDS = 0.8

-- Enemigos
Constants.ENEMY_REPATH_INTERVAL_SECONDS = 0.25
Constants.SHOOTER_PREFERRED_DISTANCE_STUDS = 24
-- Banda muerta alrededor de la distancia preferida. Sin ella el Shooter corrige, se
-- pasa, corrige de vuelta, y tiembla en el lugar en vez de plantarse a disparar.
Constants.SHOOTER_DISTANCE_TOLERANCE_STUDS = 4
--[[
	Margen de dano por contacto: cuanto MAS ALLA de su propio cuerpo alcanza a pegar un
	enemigo. El radio final es "medio ancho del cuerpo + este margen".

	No es el radio completo, y la diferencia importa. Antes esto era un radio de 4.5
	multiplicado por la escala del enemigo, lo que en el Bonkaron (escala 2.5) daba
	11.25 studs: pegaba a ocho studs de distancia de su propio cuerpo. En el playtest se
	veia como recibir dano de la nada. Con el margen fijo, un Chaser sigue alcanzando
	los mismos 4.5 de siempre (1.3 de medio cuerpo + 3.2) y el jefe alcanza 6.45, que es
	lo que se ve en pantalla.
]]
Constants.ENEMY_CONTACT_GRACE_STUDS = 3.2
-- Cadencia con la que UN enemigo puede pegarte. La ventana de invulnerabilidad del
-- jugador (0.35 s) ya frena a la horda entera; esto evita que uno solo te drene.
Constants.ENEMY_CONTACT_COOLDOWN_SECONDS = 1
Constants.BASE_ENEMIES_PER_COMBAT_ROOM = 3
Constants.ENEMY_TICK_HZ = 20 -- decisiones por segundo del EnemySystem

-- Salas
Constants.ROOM_CHECK_HZ = 5 -- con que frecuencia se mira en que sala esta cada jugador

-- Lobby. Lejos de la mazmorra (z = 1200) y de la TestArena (origen) para que nada se
-- pise: el lobby y el piso conviven en el mismo place y existen a la vez.
Constants.LOBBY_ORIGIN = table.freeze({ x = 0, y = 0, z = -600 })
Constants.LOBBY_SIZE_STUDS = 72
-- Margen entre que se marca el ultimo Listo y que arranca la run. Existe para poder
-- arrepentirse: sin el, tocar Listo sin querer te mete en una run.
Constants.LOBBY_COUNTDOWN_SECONDS = 5

-- Loot
Constants.COIN_VALUE = 1
Constants.COIN_SCATTER_RADIUS_STUDS = 5
Constants.LOOT_CHECK_HZ = 10
Constants.COIN_PICKUP_FLIGHT_SECONDS = 0.3 -- lo que tarda la moneda en llegar volando

-- Presentacion
Constants.BIG_DAMAGE_THRESHOLD = 30 -- a partir de aqui el popup crece y se pone naranja
Constants.BIG_DAMAGE_POPUP_SCALE = 1.8

-- Replicacion
Constants.STATS_REPLICATION_HZ = 10 -- suficiente para una barra de vida/energia

return table.freeze(Constants)

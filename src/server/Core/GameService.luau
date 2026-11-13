--!strict
--[[
	GameService: el estado de la run. En que piso estamos, si se gano o se perdio,
	cuando se genera el siguiente piso y cuando aparece un cuerpo.

	Es el heredero directo de `GameManager.cs` de la version Unity, con las dos
	traducciones que exigia Roblox:

	  - No hay escenas ni `DontDestroyOnLoad`. "Cambiar de piso" es destruir la
	    geometria vieja, generar la nueva y teletransportar al grupo. Un solo place.
	  - No hay `Time.timeScale`. Ganar o perder no puede pausar el juego: en
	    multijugador pausar el servidor es pausarle la partida a todos. La victoria y
	    la derrota son un ESTADO que se replica, y cada cliente decide que panel pinta.

	FASE 4: ademas del avance de pisos, ahora cierra el bucle completo. Se quedo con el
	spawn de personajes (antes lo hacia el andamio `DevSpawnService`, que se borro),
	declara la derrota cuando cae el ultimo jugador y la victoria cuando cae el jefe, y
	acepta que alguien pida volver a empezar.

	SOBRE MORIR: durante una run, un jugador muerto NO reaparece. Es un roguelite: la
	muerte tiene que costar la run. En solitario eso es la derrota inmediata; en co-op,
	los que quedan siguen y el caido espera (la Fase 6 le agrega el revivir). Esta
	regla es la razon por la que el respawn automatico de desarrollo tenia que morir.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local EnemySystem = require(script.Parent.Parent.Enemies.EnemySystem)
local DungeonGenerator = require(script.Parent.Parent.World.DungeonGenerator)
local HealthRegistry = require(script.Parent.Parent.Combat.HealthRegistry)
local LootService = require(script.Parent.Parent.World.LootService)
local RateLimiter = require(script.Parent.RateLimiter)
local WeaponService = require(script.Parent.Parent.Combat.WeaponService)

-- Las monedas llegan a rafagas (un enemigo suelta hasta 3, una sala suelta decenas).
-- Se acumulan y se replica como mucho cinco veces por segundo.
local COIN_PUBLISH_INTERVAL_SECONDS = 0.2

-- Reiniciar es un boton de menu, no de combate.
local RESTART_BURST_CAPACITY = 3
local RESTART_REFILL_PER_SECOND = 1

local log = Logger.new("GameService")

local GameService = {
	name = "GameService",
}

-- (snapshot) cada vez que cambia algo del estado de run.
GameService.onStateChanged = Signal.new() :: Signal.Signal<Types.RunStateSnapshot>

-- FASE 5: el servidor ya no arranca jugando. Arranca en el lobby, esperando.
local phase: Types.RunPhase = "Lobby"
local floorNumber = 1
local sharedCoins = 0
local currentFloor: DungeonGenerator.GeneratedFloor? = nil
local coinPublishScheduled = false

-- Estado del lobby. Vive aca porque es parte del snapshot, pero lo MANTIENE
-- LobbyService: este servicio solo lo guarda y lo replica (ver `setRoster`).
local roster: { Types.LobbyMember } = {}
local countdownRemaining: number? = nil

function GameService.getSnapshot(): Types.RunStateSnapshot
	local inLobby = phase == "Lobby"

	return {
		phase = phase,
		floorNumber = floorNumber,
		floorsPerRun = Constants.FLOORS_PER_RUN,
		sharedCoins = sharedCoins,
		playerCount = #Players:GetPlayers(),
		-- Fuera del lobby estos dos viajan como nil: el snapshot se emite tambien
		-- cuando entran monedas, y repetir una lista que nadie mira es trafico regalado.
		roster = if inLobby then roster else nil,
		countdownRemaining = if inLobby then countdownRemaining else nil,
	}
end

--[[ Replica el estado a todos. Se llama en cada cambio, no en un loop. ]]
local function publish(): ()
	local snapshot = GameService.getSnapshot()

	Remotes.event("RunStateChanged"):FireAllClients(snapshot)
	GameService.onStateChanged:fire(snapshot)
end

function GameService.getCurrentFloor(): DungeonGenerator.GeneratedFloor?
	return currentFloor
end

function GameService.getPhase(): Types.RunPhase
	return phase
end

--------------------------------------------------------------------------------
-- Cuerpos
--------------------------------------------------------------------------------

--[[
	Actualiza el estado del lobby. Lo llama LobbyService, que es su dueno.

	La dependencia va en esa direccion (LobbyService empuja, GameService guarda) para
	que GameService no tenga que conocer al lobby: si lo consultara, tendriamos el
	ciclo `LobbyService -> GameService -> LobbyService`.
]]
function GameService.setRoster(newRoster: { Types.LobbyMember }, newCountdown: number?): ()
	roster = newRoster
	countdownRemaining = newCountdown

	if phase == "Lobby" then
		publish()
	end
end

--[[ Deja al jugador en la sala de inicio del piso actual. ]]
function GameService.teleportToStart(player: Player): ()
	local floor = currentFloor
	local character = player.Character

	if not floor or not character then
		return
	end

	-- PivotTo y no `HumanoidRootPart.CFrame`: mueve el modelo entero de una, sin
	-- dejar partes del cuerpo atras.
	character:PivotTo(CFrame.new(floor.startPosition))
end

local function spawnEveryone(): ()
	for _, player in Players:GetPlayers() do
		WeaponService.resetLoadout(player)
		player:LoadCharacter()
	end
end

local function teleportEveryone(): ()
	for _, player in Players:GetPlayers() do
		GameService.teleportToStart(player)
	end
end

local function anyPlayerAlive(): boolean
	for _, player in Players:GetPlayers() do
		if CharacterService.isAlive(player) then
			return true
		end
	end

	return false
end

--------------------------------------------------------------------------------
-- Flujo de la run
--------------------------------------------------------------------------------

local function goToFloor(target: number, seed: number?): ()
	floorNumber = target
	currentFloor = DungeonGenerator.generate(target, seed)

	teleportEveryone()
	publish()
end

--[[ Arranca una run desde el piso 1. `seed` fija el piso 1 para reproducir bugs. ]]
function GameService.startRun(seed: number?): ()
	phase = "InRun"
	sharedCoins = 0

	goToFloor(1, seed)

	-- Los cuerpos van DESPUES de generar: `LoadCharacter` dispara `onCharacterReady`,
	-- que teletransporta a la sala de inicio, y esa sala tiene que existir ya.
	spawnEveryone()

	log:info("Run iniciada")
end

--[[
	Avanza de piso. Lo llama PortalService cuando el grupo esta en el portal.

	El ultimo piso no tiene portal (tiene jefe), asi que llegar aca en el ultimo piso
	seria un bug de otro sistema: se ignora en vez de generar un piso 4 fantasma.
]]
function GameService.nextFloor(): ()
	if phase ~= "InRun" then
		return
	end

	if floorNumber >= Constants.FLOORS_PER_RUN then
		log:warn("Se pidio avanzar de piso desde el ultimo. Ignorado.")
		return
	end

	goToFloor(floorNumber + 1)

	log:info("Piso %d de %d", floorNumber, Constants.FLOORS_PER_RUN)
end

local function endRun(newPhase: Types.RunPhase, reason: string): ()
	if phase ~= "InRun" then
		return
	end

	phase = newPhase

	-- Se limpia el piso para que la pantalla de final no tenga bichos disparandole a
	-- un cadaver de fondo. La geometria se queda: se ve donde termino la run.
	EnemySystem.despawnAll()

	publish()

	log:info("Run terminada: %s (%s)", newPhase, reason)
end

--[[ Fin feliz de la run. ]]
function GameService.bossDefeated(): ()
	endRun("Victory", "cayo El Bonkaron")
end

--[[
	Vuelve al lobby. Es el cierre del circulo que pedia la Fase 5: menu -> seleccion ->
	run -> victoria/derrota -> menu, todo sin recargar el servidor.

	Se desmonta el piso entero. Dejarlo puesto seria tener una mazmorra con enemigos
	corriendo mientras la gente elige personaje, y ademas el proximo `startRun` la
	regenera igual.
]]
function GameService.returnToLobby(): ()
	if phase == "Lobby" then
		return
	end

	phase = "Lobby"
	floorNumber = 1
	sharedCoins = 0
	currentFloor = nil

	DungeonGenerator.clear()

	-- Cuerpos nuevos para todos: el que murio vuelve entero, y el que llega vivo deja
	-- atras el arsenal de la run anterior.
	for _, player in Players:GetPlayers() do
		WeaponService.resetLoadout(player)
		player:LoadCharacter()
	end

	publish()

	log:info("De vuelta en el lobby")
end

--------------------------------------------------------------------------------
-- Monedas
--------------------------------------------------------------------------------

function GameService.getSharedCoins(): number
	return sharedCoins
end

local function addCoins(amount: number): ()
	if amount <= 0 then
		return
	end

	sharedCoins += amount

	if coinPublishScheduled then
		return
	end

	coinPublishScheduled = true

	task.delay(COIN_PUBLISH_INTERVAL_SECONDS, function()
		coinPublishScheduled = false
		publish()
	end)
end

--------------------------------------------------------------------------------

local function onRequestRestart(player: Player): ()
	if not RateLimiter.consume(player, "RequestRestart", RESTART_BURST_CAPACITY, RESTART_REFILL_PER_SECOND) then
		return
	end

	-- Solo con la run terminada: nadie puede mandar al grupo al lobby a mitad del piso 3.
	if phase == "InRun" then
		return
	end

	log:info("%s pidio volver al lobby", player.Name)

	GameService.returnToLobby()
end

function GameService.init(): ()
	-- Un cuerpo nuevo aparece en el SpawnLocation del place; hay que llevarlo a donde
	-- corresponda. En el lobby de eso se ocupa LobbyService, que sabe donde esta.
	CharacterService.onCharacterReady:connect(function(player: Player)
		if phase == "InRun" then
			GameService.teleportToStart(player)
		end
	end)

	-- El jefe es un enemigo como cualquier otro; lo que lo distingue es su dato.
	EnemySystem.onEnemyDied:connect(function(enemy)
		if enemy.definition.isBoss then
			GameService.bossDefeated()
		end
	end)

	LootService.onCoinsCollected:connect(function(amount: number)
		addCoins(amount)
	end)

	-- Derrota: cae el ultimo jugador vivo. Se comprueba al morir CUALQUIER entidad con
	-- Health que resulte ser el personaje de alguien, y se difiere un frame para que el
	-- estado del muerto ya este asentado cuando se cuenta.
	HealthRegistry.onEntityDied:connect(function(entity: Instance)
		if not entity:IsA("Model") or not Players:GetPlayerFromCharacter(entity) then
			return
		end

		task.defer(function()
			if phase == "InRun" and not anyPlayerAlive() then
				endRun("Defeat", "cayeron todos")
			end
		end)
	end)
end

function GameService.start(): ()
	Remotes.event("RequestRestart").OnServerEvent:Connect(onRequestRestart)

	Players.PlayerAdded:Connect(function(player: Player)
		-- Snapshot inmediato: el cliente no puede pintar el lobby ni el HUD sin saber
		-- en que estado esta la partida a la que se acaba de sumar.
		Remotes.event("RunStateChanged"):FireClient(player, GameService.getSnapshot())

		-- Un cuerpo siempre: en el lobby para esperar, o en el piso si entro a mitad
		-- de run. La Fase 6 cambia lo segundo por espectador hasta el proximo piso.
		player:LoadCharacter()
	end)

	Players.PlayerRemoving:Connect(function()
		-- El conteo de jugadores viaja en el snapshot, asi que irse tambien es un cambio.
		task.defer(publish)
	end)

	-- Cuerpos para quien ya estuviera conectado (recarga de Rojo en Studio).
	for _, player in Players:GetPlayers() do
		player:LoadCharacter()
	end

	publish()
end

return GameService

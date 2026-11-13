--!strict
--[[
	LobbyService: el estado Lobby. Donde se elige personaje, se dice "listo" y arranca
	la run.

	Es el reemplazo de la escena de menu de la version Unity. En Roblox no hay escenas:
	el lobby y la mazmorra existen a la vez, en el mismo place, separados en el espacio
	(`Constants.LOBBY_ORIGIN` esta a 600 studs del origen y la mazmorra a 1200 del otro
	lado). Cambiar de "escena" es teletransportar y cambiar una variable.

	--------------------------------------------------------------------------------
	POR QUE LOS REMOTES DEL LOBBY SE ESCUCHAN ACA Y NO EN CharacterService
	--------------------------------------------------------------------------------

	`SelectCharacter` tiene que validar "y la fase es Lobby". Si esa comprobacion
	viviera en CharacterService, CharacterService tendria que preguntarle la fase a
	GameService, y GameService ya depende de CharacterService: ciclo.

	La salida no es un truco de dependencias, es darse cuenta de que son dos
	responsabilidades distintas. CharacterService sabe QUE personaje jugas y como se
	arma tu cuerpo. LobbyService sabe QUE PODES HACER en el lobby. La validacion de
	fase pertenece al segundo. CharacterService quedo con un `select()` que es un
	setter puro y no escucha ningun remote.

	Con GameService pasa parecido y se resuelve al reves: este servicio LE EMPUJA la
	lista de jugadores (`GameService.setRoster`) en vez de que GameService se la pida.
	Asi la dependencia va en una sola direccion, LobbyService -> GameService, y el
	snapshot que ya existia no necesita conocer a nadie nuevo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Characters = require(Shared.Data.Characters)
local LobbyRules = require(Shared.Logic.LobbyRules)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local GameService = require(script.Parent.GameService)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local RateLimiter = require(script.Parent.RateLimiter)

-- Elegir personaje y marcarse listo son acciones de menu, no de combate.
local SELECT_BURST_CAPACITY = 6
local SELECT_REFILL_PER_SECOND = 2
local READY_BURST_CAPACITY = 6
local READY_REFILL_PER_SECOND = 2

local log = Logger.new("LobbyService")

local LobbyService = {
	name = "LobbyService",
}

local readyByPlayer: { [Player]: boolean } = {}
local countdownRemaining: number? = nil
local countdownToken = 0
-- Ultima fase VISTA. Existe para poder reaccionar a los cambios de fase y no a cada
-- snapshot; ver el comentario grande en `init`.
local lastSeenPhase: Types.RunPhase? = nil

--------------------------------------------------------------------------------
-- Estado
--------------------------------------------------------------------------------

local function buildRoster(): { Types.LobbyMember }
	local roster: { Types.LobbyMember } = {}

	for _, player in Players:GetPlayers() do
		table.insert(roster, {
			userId = player.UserId,
			displayName = player.DisplayName,
			characterId = CharacterService.getCharacterDef(player).id,
			isReady = readyByPlayer[player] == true,
		})
	end

	return roster
end

local function countReady(): number
	local count = 0

	for _, player in Players:GetPlayers() do
		if readyByPlayer[player] then
			count += 1
		end
	end

	return count
end

--[[ Empuja el estado del lobby a GameService, que es quien lo replica. ]]
local function publish(): ()
	GameService.setRoster(buildRoster(), countdownRemaining)
end

--------------------------------------------------------------------------------
-- Cuenta atras
--------------------------------------------------------------------------------

local function cancelCountdown(): ()
	if countdownRemaining == nil then
		return
	end

	-- El token invalida la corrutina que esta contando. Sin el, cancelar y volver a
	-- empezar dejaria dos cuentas corriendo y la run arrancaria antes de tiempo.
	countdownToken += 1
	countdownRemaining = nil

	log:info("Cuenta atras cancelada")
end

local function startCountdown(): ()
	if countdownRemaining ~= nil then
		return
	end

	countdownToken += 1

	local token = countdownToken
	countdownRemaining = Constants.LOBBY_COUNTDOWN_SECONDS

	publish()

	task.spawn(function()
		while countdownRemaining and countdownRemaining > 0 do
			task.wait(1)

			if token ~= countdownToken then
				return -- esta cuenta quedo obsoleta
			end

			countdownRemaining = (countdownRemaining :: number) - 1
			publish()
		end

		if token ~= countdownToken then
			return
		end

		countdownRemaining = nil

		if GameService.getPhase() == "Lobby" then
			GameService.startRun()
		end
	end)
end

--[[ Reevalua si hay que contar. Se llama en cada cambio que pueda alterar la decision. ]]
local function refresh(): ()
	if GameService.getPhase() ~= "Lobby" then
		return
	end

	local playerCount = #Players:GetPlayers()
	local readyCount = countReady()

	if LobbyRules.shouldCountdown(playerCount, readyCount) then
		startCountdown()
	else
		cancelCountdown()
	end

	publish()
end

--------------------------------------------------------------------------------
-- Intenciones del cliente
--------------------------------------------------------------------------------

local function onSelectCharacter(player: Player, payload: unknown): ()
	if not RateLimiter.consume(player, "SelectCharacter", SELECT_BURST_CAPACITY, SELECT_REFILL_PER_SECOND) then
		return
	end

	-- LA validacion que pedia el contrato de la Fase 5: solo se elige en el lobby.
	-- A mitad de run cambiar de personaje seria cambiar de vida maxima y de arma.
	if GameService.getPhase() ~= "Lobby" then
		return
	end

	if typeof(payload) ~= "table" then
		return
	end

	if not CharacterService.select(player, (payload :: any).characterId) then
		return
	end

	-- El cuerpo del lobby se rehace para que se vea el personaje elegido.
	player:LoadCharacter()

	refresh()
end

local function onSetReady(player: Player, payload: unknown): ()
	if not RateLimiter.consume(player, "SetReady", READY_BURST_CAPACITY, READY_REFILL_PER_SECOND) then
		return
	end

	if GameService.getPhase() ~= "Lobby" then
		return
	end

	if typeof(payload) ~= "table" then
		return
	end

	local ready = (payload :: any).ready

	if typeof(ready) ~= "boolean" then
		return
	end

	if readyByPlayer[player] == ready then
		return
	end

	readyByPlayer[player] = ready

	refresh()
end

--------------------------------------------------------------------------------

function LobbyService.init(): ()
	--[[
		Se escucha el cambio de fase en vez de que GameService nos llame: asi la
		dependencia sigue yendo en una sola direccion. Al ENTRAR al lobby se limpian los
		"listo", para que nadie arranque otra run arrastrado por el Listo que marco
		quince minutos antes.

		OJO CON LA CONDICION DE LA PRIMERA LINEA, que no es una optimizacion: se
		reacciona a los CAMBIOS de fase, no a cada snapshot. Reaccionar a cada snapshot
		producia una recursion infinita, y la encontro el playtest como un
		`C stack overflow` en el arranque:

		    publish() -> GameService.setRoster() -> GameService.publish()
		              -> onStateChanged -> este handler -> publish() -> ...

		Es la trampa clasica de dos servicios que se avisan cambios entre si. La salida
		no es cortar la signal, es preguntarse que se esta escuchando de verdad: aca
		interesa "se entro al lobby", que pasa una vez, y no "seguimos en el lobby",
		que pasa todo el tiempo.
	]]
	GameService.onStateChanged:connect(function(snapshot: Types.RunStateSnapshot)
		if snapshot.phase == lastSeenPhase then
			return
		end

		lastSeenPhase = snapshot.phase

		if snapshot.phase ~= "Lobby" then
			cancelCountdown()
			return
		end

		table.clear(readyByPlayer)
		publish()
	end)

	CharacterService.onCharacterReady:connect(function(player: Player)
		if GameService.getPhase() == "Lobby" then
			LobbyService.teleportToLobby(player)
		end
	end)
end

--[[ Deja al jugador en el lobby. Lo usa GameService al terminar una run. ]]
function LobbyService.teleportToLobby(player: Player): ()
	local character = player.Character

	if not character then
		return
	end

	character:PivotTo(CFrame.new(LobbyBuilder.getSpawnPosition()))
end

function LobbyService.start(): ()
	LobbyBuilder.build()

	Remotes.event("SelectCharacter").OnServerEvent:Connect(onSelectCharacter)
	Remotes.event("SetReady").OnServerEvent:Connect(onSetReady)

	Players.PlayerAdded:Connect(function()
		-- Un jugador nuevo hace que "todos listos" deje de ser cierto: si habia una
		-- cuenta atras corriendo, se cancela sola en el refresh.
		refresh()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		readyByPlayer[player] = nil
		task.defer(refresh)
	end)

	publish()

	log:info("Lobby listo. %d personajes para elegir.", #Characters.ids)
end

return LobbyService

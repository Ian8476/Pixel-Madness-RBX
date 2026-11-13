--!strict
--[[
	EnergyService: la energia de los jugadores. Solo servidor (regla 5).

	La energia es el recurso que hace interesantes a las armas caras y a las
	habilidades: sin ella, El Dedo de Dios seria simplemente el arma mejor. Por eso
	vive del lado autoritativo y el cliente nunca la calcula, solo la ve.

	Por que NO emite una signal por cada cambio (y si expone getters):
	la energia se regenera todos los frames. Una signal por tick serian 60 disparos
	por segundo por jugador para mover una barra que se replica a 10 Hz. Quien la
	necesita (PlayerStatsReplicator) la CONSULTA a su propio ritmo y compara con lo
	ultimo que envio. Rule 2 sigue valiendo para eventos discretos (murio, cambio de
	arma); un valor continuo se muestrea.

	Fuente de los numeros: el CharacterDef del personaje elegido (`maxEnergy`,
	`energyRegenPerSecond`). Cambiarlos es editar Shared/Data/Characters/.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Logger)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)

type EnergyState = {
	current: number,
	maximum: number,
	regenPerSecond: number,
}

local log = Logger.new("EnergyService")

local EnergyService = {
	name = "EnergyService",
}

local states: { [Player]: EnergyState } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local function configureFromCharacter(player: Player): ()
	local definition = CharacterService.getCharacterDef(player)

	-- Aparecer con la barra llena: la energia es un recurso de la pelea, no un
	-- castigo de entrada.
	states[player] = {
		current = definition.maxEnergy,
		maximum = definition.maxEnergy,
		regenPerSecond = definition.energyRegenPerSecond,
	}
end

local function step(deltaTime: number): ()
	for player, state in states do
		if state.current >= state.maximum then
			continue
		end

		-- Un muerto no regenera: si no, revivir con la barra llena vuelve gratis
		-- morirse, y en co-op (Fase 6) eso rompe el peso de caer.
		if not CharacterService.isAlive(player) then
			continue
		end

		state.current = math.min(state.maximum, state.current + state.regenPerSecond * deltaTime)
	end
end

function EnergyService.get(player: Player): number
	local state = states[player]

	return if state then state.current else 0
end

function EnergyService.getMaximum(player: Player): number
	local state = states[player]

	return if state then state.maximum else 0
end

--[[
	Intenta gastar energia. Devuelve false y NO gasta nada si no alcanza.

	Es todo-o-nada a proposito: un disparo a medias o una habilidad a medias no
	existen. Quien llama decide que hacer con el false (normalmente: descartar la
	intencion en silencio).
]]
function EnergyService.trySpend(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end

	local state = states[player]

	if not state or state.current < amount then
		return false
	end

	state.current -= amount

	return true
end

--[[ Devuelve energia (pickups y recompensas futuras). Nunca pasa del maximo. ]]
function EnergyService.grant(player: Player, amount: number): ()
	local state = states[player]

	if not state or amount <= 0 then
		return
	end

	state.current = math.min(state.maximum, state.current + amount)
end

function EnergyService.init(): ()
	-- Suscripcion en init (cableado), no en start: asi no importa el orden en que
	-- arrancan los servicios.
	CharacterService.onCharacterReady:connect(function(player: Player)
		configureFromCharacter(player)
	end)
end

function EnergyService.start(): ()
	if heartbeatConnection then
		return
	end

	for _, player in Players:GetPlayers() do
		if player.Character then
			configureFromCharacter(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	-- Un unico Heartbeat para todos los jugadores, no un loop por jugador.
	heartbeatConnection = RunService.Heartbeat:Connect(step)

	log:info("Regeneracion de energia activa")
end

return EnergyService

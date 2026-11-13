--!strict
--[[
	PlayerStatsReplicator: le manda a cada jugador SU estado, y solo el suyo.

	Por que un modulo aparte y no que cada servicio replique lo suyo (el plan de la
	Fase 2 pedia la replicacion "dentro de EnergyService"):
	vida, energia, loadout y cooldown se dibujan en el mismo HUD y cambian a la vez.
	Si cada servicio replicara por su cuenta serian tres remotes, tres throttles y tres
	oportunidades de que el HUD muestre una energia de este frame junto a una vida del
	anterior. Un solo snapshot por jugador (`PlayerStatsSnapshot`) llega coherente.

	Ademas mantiene la regla 3 intacta: EnergyService sabe de energia, WeaponService de
	armas, y NINGUNO sabe que existe una UI. Este modulo es el unico que conoce a los
	dos y al remote.

	Por que MUESTREA (10 Hz) en vez de escuchar signals: energia y cooldown son valores
	continuos, cambian todos los frames. Una signal por cambio serian 60 mensajes por
	segundo por jugador para mover una barra. Se muestrea al ritmo del HUD y se compara
	con lo ultimo enviado: parado y con la barra llena, no se manda nada.

	FASE 5: la UI se suscribe a esto. Hoy no hay nadie escuchando del lado del cliente
	salvo ClientState, que lo usa para saber cada cuanto mandar FireRequest.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local AbilityService = require(script.Parent.Parent.Combat.AbilityService)
local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local EnergyService = require(script.Parent.Parent.Combat.EnergyService)
local WeaponService = require(script.Parent.Parent.Combat.WeaponService)

-- Los valores continuos se comparan redondeados: sin esto, un flotante que cambia en
-- el decimo decimal marca el snapshot como distinto para siempre y el throttle no
-- ahorra nada.
local COMPARISON_PRECISION = 0.1

local log = Logger.new("PlayerStatsReplicator")

local PlayerStatsReplicator = {
	name = "PlayerStatsReplicator",
}

local lastSent: { [Player]: Types.PlayerStatsSnapshot } = {}
local heartbeatConnection: RBXScriptConnection? = nil
local accumulator = 0

local function quantize(value: number): number
	return math.floor(value / COMPARISON_PRECISION + 0.5) * COMPARISON_PRECISION
end

local function buildSnapshot(player: Player): Types.PlayerStatsSnapshot
	local definition = CharacterService.getCharacterDef(player)
	local health = CharacterService.getHealth(player)

	return {
		health = if health then quantize(health:getCurrent()) else 0,
		maxHealth = if health then health:getMaximum() else definition.maxHealth,
		energy = quantize(EnergyService.get(player)),
		maxEnergy = EnergyService.getMaximum(player),
		characterId = definition.id,
		primaryWeaponId = WeaponService.getWeaponIdInSlot(player, 1),
		secondaryWeaponId = WeaponService.getWeaponIdInSlot(player, 2),
		activeSlot = WeaponService.getActiveSlot(player),
		fireRateMultiplier = AbilityService.getFireRateMultiplier(player),
		isDualWielding = AbilityService.isDualWielding(player),
		abilityCooldownRemaining = quantize(AbilityService.getCooldownRemaining(player)),
	}
end

local function isSame(a: Types.PlayerStatsSnapshot, b: Types.PlayerStatsSnapshot): boolean
	return a.health == b.health
		and a.maxHealth == b.maxHealth
		and a.energy == b.energy
		and a.maxEnergy == b.maxEnergy
		and a.characterId == b.characterId
		and a.primaryWeaponId == b.primaryWeaponId
		and a.secondaryWeaponId == b.secondaryWeaponId
		and a.activeSlot == b.activeSlot
		and a.fireRateMultiplier == b.fireRateMultiplier
		and a.isDualWielding == b.isDualWielding
		and a.abilityCooldownRemaining == b.abilityCooldownRemaining
end

local function publish(player: Player, force: boolean): ()
	local snapshot = buildSnapshot(player)
	local previous = lastSent[player]

	if not force and previous and isSame(previous, snapshot) then
		return
	end

	lastSent[player] = snapshot
	Remotes.event("PlayerStatsChanged"):FireClient(player, snapshot)
end

local function step(deltaTime: number): ()
	accumulator += deltaTime

	local interval = 1 / Constants.STATS_REPLICATION_HZ

	if accumulator < interval then
		return
	end

	accumulator = 0

	for _, player in Players:GetPlayers() do
		publish(player, false)
	end
end

function PlayerStatsReplicator.init(): ()
	-- Snapshot inmediato al aparecer el cuerpo: asi el cliente no arranca con
	-- valores inventados esperando al proximo tick. Es el reemplazo del hack del
	-- `Invoke(0.05)` que tenia la version Unity.
	CharacterService.onCharacterReady:connect(function(player: Player)
		publish(player, true)
	end)
end

function PlayerStatsReplicator.start(): ()
	if heartbeatConnection then
		return
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastSent[player] = nil
	end)

	heartbeatConnection = RunService.Heartbeat:Connect(step)

	log:info("Replicando stats a %d Hz", Constants.STATS_REPLICATION_HZ)
end

return PlayerStatsReplicator

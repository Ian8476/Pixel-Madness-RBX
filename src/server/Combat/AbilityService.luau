--!strict
--[[
	AbilityService: las habilidades de los tres personajes, validadas en el servidor.

	Costo, cooldown y efecto salen del `AbilityDef` del personaje (union discriminada
	por `kind`, ver Types.luau). Agregar una habilidad nueva rompe la compilacion
	justo aca, en el `if` de abajo, en vez de fallar en runtime: eso es exactamente
	lo que queremos de una union discriminada.

	Reparto de responsabilidades entre servidor y cliente, habilidad por habilidad:

	- DualWield y RapidFire son FLAGS con vencimiento. Viven aca y los consulta
	  WeaponService al disparar. El cliente no participa: no tiene nada que hacer.
	- Dash es el caso interesante. La INVULNERABILIDAD la concede el servidor (es
	  estado de juego, regla 5) pero el IMPULSO lo aplica el cliente, porque el cliente
	  es el dueno de red de su propio personaje: un impulso escrito desde el servidor
	  sobre una assembly que posee el cliente se pisa en el siguiente paquete de
	  fisica. Y aunque funcionara, esperar un round-trip para moverse arruina la
	  habilidad que mas depende del timing del juego.

	  El anti-exploit no se resiente: lo que el cliente puede hacer con ese permiso es
	  moverse rapido durante un tercio de segundo. La energia ya se cobro, el cooldown
	  ya arranco y la invulnerabilidad la controla el servidor con duracion fija.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local EnergyService = require(script.Parent.EnergyService)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)

-- El cooldown mas corto del juego es el Dash de Nina (1.5 s). Un presupuesto de 5 en
-- rafaga y 2/s deja pasar cualquier uso legitimo y corta el spam de un cliente
-- modificado antes de que el servicio haga trabajo.
local ABILITY_BURST_CAPACITY = 5
local ABILITY_REFILL_PER_SECOND = 2

type AbilityState = {
	cooldownUntil: number,
	dualWieldUntil: number,
	rapidFireUntil: number,
	rapidFireMultiplier: number,
}

local log = Logger.new("AbilityService")

local AbilityService = {
	name = "AbilityService",
}

local states: { [Player]: AbilityState } = {}

local function newState(): AbilityState
	return {
		cooldownUntil = 0,
		dualWieldUntil = 0,
		rapidFireUntil = 0,
		rapidFireMultiplier = 1,
	}
end

local function getState(player: Player): AbilityState
	local state = states[player]

	if not state then
		state = newState()
		states[player] = state
	end

	return state
end

--[[ Direccion horizontal a la que mira el personaje. El cliente ya lo giro hacia el
	mouse y la rotacion se replica, asi que el servidor tiene una lectura fiel. ]]
local function getFacingDirection(character: Model): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return nil
	end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)

	if flat.Magnitude < 1e-3 then
		return nil
	end

	return flat.Unit
end

local function activate(player: Player, character: Model, ability: Types.AbilityDef, state: AbilityState): ()
	local now = os.clock()
	local payload: Types.AbilityActivatedPayload

	if ability.kind == "Dash" then
		local health = CharacterService.getHealth(player)

		if health then
			health:grantInvulnerability(ability.invulnerabilitySeconds)
		end

		payload = {
			kind = ability.kind,
			direction = getFacingDirection(character),
			impulseSpeed = ability.impulseSpeed,
			durationSeconds = ability.invulnerabilitySeconds,
		}
	elseif ability.kind == "DualWield" then
		state.dualWieldUntil = now + ability.durationSeconds

		payload = {
			kind = ability.kind,
			durationSeconds = ability.durationSeconds,
		}
	elseif ability.kind == "RapidFire" then
		state.rapidFireUntil = now + ability.durationSeconds
		state.rapidFireMultiplier = ability.fireRateMultiplier

		payload = {
			kind = ability.kind,
			durationSeconds = ability.durationSeconds,
		}
	else
		-- Inalcanzable con la union actual. Si algun dia se alcanza, es que alguien
		-- agrego un `kind` y no lo cableo: mejor un warn que una habilidad muda.
		log:warn("Habilidad sin caso implementado: %s", tostring((ability :: any).kind))
		return
	end

	Remotes.event("AbilityActivated"):FireClient(player, payload)
end

local function onUseAbility(player: Player): ()
	if not RateLimiter.consume(player, "UseAbility", ABILITY_BURST_CAPACITY, ABILITY_REFILL_PER_SECOND) then
		return
	end

	if not CharacterService.isAlive(player) then
		return
	end

	local character = player.Character

	if not character then
		return
	end

	local state = getState(player)

	if os.clock() < state.cooldownUntil then
		return
	end

	local ability = CharacterService.getCharacterDef(player).ability

	-- La energia se cobra ANTES de aplicar el efecto y despues del cooldown: si no
	-- alcanza, no se gasta nada y el cooldown no arranca.
	if not EnergyService.trySpend(player, ability.energyCost) then
		return
	end

	state.cooldownUntil = os.clock() + ability.cooldownSeconds

	activate(player, character, ability, state)
end

--[[ True mientras dure el Doble Bonk. Lo consulta WeaponService al disparar. ]]
function AbilityService.isDualWielding(player: Player): boolean
	local state = states[player]

	return state ~= nil and os.clock() < state.dualWieldUntil
end

--[[ Multiplicador de cadencia: 1 normal, 2 mientras dure la Sobrecarga de Voltio. ]]
function AbilityService.getFireRateMultiplier(player: Player): number
	local state = states[player]

	if not state or os.clock() >= state.rapidFireUntil then
		return 1
	end

	return state.rapidFireMultiplier
end

--[[ Segundos que faltan para poder volver a usar la habilidad. Para el HUD. ]]
function AbilityService.getCooldownRemaining(player: Player): number
	local state = states[player]

	if not state then
		return 0
	end

	return math.max(0, state.cooldownUntil - os.clock())
end

function AbilityService.init(): ()
	-- Cuerpo nuevo, estado limpio: ningun buff sobrevive a la muerte.
	CharacterService.onCharacterReady:connect(function(player: Player)
		states[player] = newState()
	end)
end

function AbilityService.start(): ()
	Remotes.event("UseAbility").OnServerEvent:Connect(onUseAbility)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	log:info("Escuchando UseAbility")
end

return AbilityService

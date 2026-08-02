--!strict
--[[
	WeaponService: convierte la INTENCION de disparar del cliente en balas reales.

	El cliente nunca crea una bala ni decide cuanto dano hace. Manda "quiero disparar
	en esta direccion" y el servidor decide si puede, cuando y con que (regla 5).

	Orden de validacion, del filtro mas barato al mas caro:
	  1. Rate limit del remote      -> frena el spam antes de gastar CPU
	  2. Forma del payload          -> tipos y estructura
	  3. Vector unitario horizontal -> nada de direcciones inventadas ni magnitudes raras
	  4. Jugador vivo con cuerpo    -> no se dispara desde la tumba
	  5. Cadencia del arma          -> el limite real de disparos por segundo

	Sobre la cadencia y el jitter de red: se acepta el 90% del intervalo
	(`Constants.FIRE_RATE_TOLERANCE`) porque los paquetes no llegan con reloj perfecto
	y castigar a un jugador con 120 ms de ping por adelantarse 5 ms seria injusto.
	Ese 10% no es una puerta: un cliente modificado que dispare al doble de cadencia
	sigue rebotando, y el rate limiter le corta la rafaga.

	ESTADO FASE 1: un arma hardcodeada (La Fiel). La Fase 2 reemplaza `getEquippedWeapon`
	por una consulta al inventario y a `Shared/Data/Weapons/`. Todo lo demas de este
	archivo queda igual: la costura esta puesta a proposito en un solo lugar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local ProjectileSystem = require(script.Parent.ProjectileSystem)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)

-- Presupuesto del remote: rafaga de 20 y 20/s sostenidos. Muy por encima de la
-- cadencia del arma mas rapida (La Cotorra, 10/s) y muy por debajo de lo que
-- necesitaria un exploiter para hacer dano.
local FIRE_BURST_CAPACITY = 20
local FIRE_REFILL_PER_SECOND = 20

local MUZZLE_FORWARD_OFFSET_STUDS = 2.5
local UNIT_VECTOR_TOLERANCE = 0.15
local PROJECTILE_COLOR = Color3.fromRGB(255, 236, 140)

-- TEMPORAL (Fase 2): sale de Shared/Data/Weapons/LaFiel.luau
local TEMP_WEAPON: Types.WeaponDef = table.freeze({
	id = "la_fiel",
	displayName = "La Fiel",
	flavorText = "Nunca te abandona. Nunca impresiona.",
	fireRate = 4,
	projectilesPerShot = 1,
	spreadDegrees = 0,
	damage = 8,
	projectileSpeed = 66,
	energyCost = 0,
	isAutomatic = true,
	isPiercing = false,
	knockback = 12,
	projectileScale = 1,
})

local log = Logger.new("WeaponService")

local WeaponService = {
	name = "WeaponService",
}

local lastFireClock: { [Player]: number } = {}
local random = Random.new()

local function nextUnitRandom(): number
	return random:NextNumber()
end

--[[ Costura de la Fase 2: aqui entra el inventario real. ]]
local function getEquippedWeapon(_player: Player): Types.WeaponDef
	return TEMP_WEAPON
end

--[[
	Valida el payload y devuelve la direccion saneada, o nil si hay que descartar.
	Se devuelve nil en silencio a proposito: no se le contesta nada al cliente que
	manda basura.
]]
local function sanitizeAimDirection(payload: unknown): Vector3?
	if typeof(payload) ~= "table" then
		return nil
	end

	local aimDirection = (payload :: any).aimDirection

	if typeof(aimDirection) ~= "Vector3" then
		return nil
	end

	local vector = aimDirection :: Vector3

	-- NaN o infinito: `vector ~= vector` es la comprobacion de NaN
	if vector ~= vector then
		return nil
	end

	local magnitude = vector.Magnitude

	if math.abs(magnitude - 1) > UNIT_VECTOR_TOLERANCE then
		return nil
	end

	local flat = Vector3.new(vector.X, 0, vector.Z)

	if flat.Magnitude < 1e-3 then
		return nil
	end

	return flat.Unit
end

local function onFireRequest(player: Player, payload: unknown): ()
	if not RateLimiter.consume(player, "FireRequest", FIRE_BURST_CAPACITY, FIRE_REFILL_PER_SECOND) then
		return
	end

	local direction = sanitizeAimDirection(payload)

	if not direction then
		return
	end

	if not CharacterService.isAlive(player) then
		return
	end

	local character = player.Character

	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local weapon = getEquippedWeapon(player)
	local interval = 1 / weapon.fireRate
	local now = os.clock()
	local last = lastFireClock[player]

	if last and now - last < interval * Constants.FIRE_RATE_TOLERANCE then
		return
	end

	lastFireClock[player] = now

	local origin = root.Position + direction * MUZZLE_FORWARD_OFFSET_STUDS

	ProjectileSystem.spawnVolley({
		origin = origin,
		direction = direction,
		speed = weapon.projectileSpeed,
		damage = weapon.damage,
		knockback = weapon.knockback,
		isPiercing = weapon.isPiercing,
		scale = weapon.projectileScale,
		color = PROJECTILE_COLOR,
		team = "Player",
		owner = player,
	}, weapon.projectilesPerShot, weapon.spreadDegrees, nextUnitRandom)
end

function WeaponService.start(): ()
	Remotes.event("FireRequest").OnServerEvent:Connect(onFireRequest)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastFireClock[player] = nil
	end)

	log:info("Escuchando FireRequest. Arma temporal: %s", TEMP_WEAPON.displayName)
end

return WeaponService

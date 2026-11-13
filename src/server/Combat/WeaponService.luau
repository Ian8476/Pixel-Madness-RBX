--!strict
--[[
	WeaponService: el inventario de armas y la conversion de la INTENCION de disparar
	del cliente en balas reales.

	El cliente nunca crea una bala ni decide cuanto dano hace. Manda "quiero disparar
	en esta direccion" y el servidor decide si puede, cuando y con que (regla 5).

	Orden de validacion de FireRequest, del filtro mas barato al mas caro:
	  1. Rate limit del remote      -> frena el spam antes de gastar CPU
	  2. Forma del payload          -> tipos y estructura
	  3. Vector unitario horizontal -> nada de direcciones inventadas ni magnitudes raras
	  4. Jugador vivo con cuerpo    -> no se dispara desde la tumba
	  5. Cadencia del arma          -> el limite real de disparos por segundo
	  6. Energia                    -> lo ultimo, porque es lo unico que CONSUME estado

	Sobre la cadencia y el jitter de red: se acepta el 90% del intervalo
	(`Constants.FIRE_RATE_TOLERANCE`) porque los paquetes no llegan con reloj perfecto
	y castigar a un jugador con 120 ms de ping por adelantarse 5 ms seria injusto.
	Ese 10% no es una puerta: un cliente modificado que dispare al doble de cadencia
	sigue rebotando, y el rate limiter le corta la rafaga.

	FASE 2: se fue el arma hardcodeada. Ahora hay dos ranuras por jugador, el arma
	sale de `Shared/Data/Weapons/`, la energia la cobra EnergyService y las habilidades
	de Voltio (cadencia x2) y Bonko (dos armas a la vez) se consultan a AbilityService.

	Nota sobre `isAutomatic`: NO se valida en el servidor. Que un arma sea semiautomatica
	es una decision de game feel que aplica el cliente (un click = un disparo); un
	cliente modificado que mantenga el fuego igual choca contra la cadencia del arma,
	que es el limite que si importa. Validar "clicks reales" seria inventar un estado
	imposible de verificar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Weapons = require(Shared.Data.Weapons)

local AbilityService = require(script.Parent.AbilityService)
local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local EnergyService = require(script.Parent.EnergyService)
local ProjectileSystem = require(script.Parent.ProjectileSystem)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)

-- Presupuesto del remote: rafaga de 20 y 20/s sostenidos. Por encima de la cadencia
-- del arma mas rapida con Sobrecarga (La Cotorra a 10/s x2) y muy por debajo de lo
-- que necesitaria un exploiter para hacer dano.
local FIRE_BURST_CAPACITY = 30
local FIRE_REFILL_PER_SECOND = 25

-- Alternar arma es una accion de un dedo, no de un script.
local SWAP_BURST_CAPACITY = 6
local SWAP_REFILL_PER_SECOND = 4

local UNIT_VECTOR_TOLERANCE = 0.15
local SLOT_COUNT = 2

type Loadout = {
	-- Mapa disperso: la ranura 2 puede no existir. `slots[2] == nil` ES la respuesta
	-- a "tiene segunda arma", sin un booleano paralelo que se pueda desincronizar.
	slots: { [number]: Types.WeaponId },
	activeSlot: number,
	lastFireClock: number,
}

local log = Logger.new("WeaponService")

local WeaponService = {
	name = "WeaponService",
}

local loadouts: { [Player]: Loadout } = {}
local random = Random.new()

local function nextUnitRandom(): number
	return random:NextNumber()
end

--[[ Loadout del jugador, creandolo con el arma inicial de su personaje si hace falta. ]]
local function getLoadout(player: Player): Loadout
	local loadout = loadouts[player]

	if not loadout then
		local startingWeaponId = CharacterService.getCharacterDef(player).startingWeaponId

		loadout = {
			slots = { [1] = startingWeaponId },
			activeSlot = 1,
			lastFireClock = 0,
		}

		loadouts[player] = loadout
	end

	return loadout
end

--------------------------------------------------------------------------------
-- Consultas publicas (las usan PickupService y PlayerStatsReplicator)
--------------------------------------------------------------------------------

function WeaponService.getWeaponIdInSlot(player: Player, slot: number): Types.WeaponId?
	return getLoadout(player).slots[slot]
end

function WeaponService.getActiveSlot(player: Player): number
	return getLoadout(player).activeSlot
end

function WeaponService.getActiveWeapon(player: Player): Types.WeaponDef?
	local loadout = getLoadout(player)

	return Weapons.getById(loadout.slots[loadout.activeSlot])
end

--[[
	Guarda un arma. Devuelve el id del arma DESPLAZADA, o nil si entro en una ranura
	libre. Quien llama (PickupService) decide que hacer con la desplazada: hoy, dejarla
	en el suelo como un pickup nuevo.

	Con una ranura libre el arma entra ahi Y pasa a ser la activa: recoger algo y
	tener que apretar Q para usarlo se siente roto.
]]
function WeaponService.equip(player: Player, weaponId: Types.WeaponId): (boolean, Types.WeaponId?)
	if not Weapons.getById(weaponId) then
		return false, nil
	end

	local loadout = getLoadout(player)

	for slot = 1, SLOT_COUNT do
		if not loadout.slots[slot] then
			loadout.slots[slot] = weaponId
			loadout.activeSlot = slot

			return true, nil
		end
	end

	local replaced = loadout.slots[loadout.activeSlot]
	loadout.slots[loadout.activeSlot] = weaponId

	return true, replaced
end

--[[
	Descarta el loadout: el proximo `getLoadout` lo reconstruye con el arma inicial del
	personaje. Lo llama GameService al empezar una run.

	Existe porque el loadout SOBREVIVE a la muerte a proposito (morir y reaparecer sin
	las armas que juntaste haria imposible probar nada), pero una run nueva tiene que
	empezar de cero: si no, la segunda run arrancaria con el arsenal de la primera.
]]
function WeaponService.resetLoadout(player: Player): ()
	loadouts[player] = nil
end

--------------------------------------------------------------------------------
-- Intenciones del cliente
--------------------------------------------------------------------------------

local function onSwapWeapon(player: Player): ()
	if not RateLimiter.consume(player, "SwapWeapon", SWAP_BURST_CAPACITY, SWAP_REFILL_PER_SECOND) then
		return
	end

	if not CharacterService.isAlive(player) then
		return
	end

	local loadout = getLoadout(player)

	-- Unica validacion del contrato: tiene que haber una segunda arma.
	if not loadout.slots[SLOT_COUNT] then
		return
	end

	loadout.activeSlot = if loadout.activeSlot == 1 then 2 else 1
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

--[[
	Armas que salen en este disparo. Normalmente una; dos mientras dure el Doble Bonk
	de Bonko, y solo si hay algo en la otra ranura (por eso su ulti no vale nada sin
	segunda arma: es diseno, no un bug).
]]
local function collectFiringWeapons(player: Player, loadout: Loadout): { Types.WeaponDef }
	local active = Weapons.getById(loadout.slots[loadout.activeSlot])

	if not active then
		return {}
	end

	if not AbilityService.isDualWielding(player) then
		return { active }
	end

	local otherSlot = if loadout.activeSlot == 1 then 2 else 1
	local other = Weapons.getById(loadout.slots[otherSlot])

	if not other then
		return { active }
	end

	return { active, other }
end

local function fireWeapon(weapon: Types.WeaponDef, origin: Vector3, direction: Vector3, player: Player): ()
	ProjectileSystem.spawnVolley({
		origin = origin,
		direction = direction,
		speed = weapon.projectileSpeed,
		damage = weapon.damage,
		knockback = weapon.knockback,
		isPiercing = weapon.isPiercing,
		scale = weapon.projectileScale,
		color = Color3.fromRGB(weapon.projectileColor.r, weapon.projectileColor.g, weapon.projectileColor.b),
		team = "Player",
		owner = player,
	}, weapon.projectilesPerShot, weapon.spreadDegrees, nextUnitRandom)
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

	local loadout = getLoadout(player)
	local firing = collectFiringWeapons(player, loadout)
	local active = firing[1]

	if not active then
		return
	end

	-- La cadencia la marca el arma ACTIVA aunque salgan dos: si la marcara la mas
	-- rapida, el Doble Bonk seria tambien un buff de cadencia encubierto.
	local interval = 1 / (active.fireRate * AbilityService.getFireRateMultiplier(player))
	local now = os.clock()

	if loadout.lastFireClock > 0 and now - loadout.lastFireClock < interval * Constants.FIRE_RATE_TOLERANCE then
		return
	end

	local energyCost = 0

	for _, weapon in firing do
		energyCost += weapon.energyCost
	end

	-- Todo o nada: con dos armas equipadas se paga por las dos o no dispara ninguna.
	if not EnergyService.trySpend(player, energyCost) then
		return
	end

	loadout.lastFireClock = now

	--[[
		LA BALA NACE EN EL CENTRO DEL CUERPO, NO ADELANTE. Encontrado en el playtest de
		la Fase 4 y no es cosmetico: era un bug que rompia el arma.

		Antes salia 2.5 studs adelante. Un raycast que EMPIEZA dentro de una parte no
		la detecta, asi que cuando un enemigo se te pegaba (su medio ancho es 1.3
		studs), la boca del arma quedaba dentro de su cuerpo y la escopeta no le hacia
		absolutamente nada. Medido: 3 impactos a 8 studs, 0 impactos a 3.5. O sea que
		el arma dejaba de funcionar justo en el momento en que mas la necesitas, que en
		un juego de perseguidores es todo el tiempo.

		Nacer en el centro es seguro por la matriz de colisiones: PlayerBullet no
		colisiona con PlayerChar, asi que la bala no puede pegarle a quien la disparo
		por mas que arranque adentro suyo. Y el raycast del primer frame ya cubre todo
		el camino desde el cuerpo hacia afuera.
	]]
	local muzzle = root.Position

	if #firing == 1 then
		fireWeapon(active, muzzle, direction, player)
		return
	end

	-- Dos bocas de fuego separadas: sin esto, las dos armas disparan desde el mismo
	-- punto y el jugador no ve que tiene dos.
	local sideways = Vector3.new(-direction.Z, 0, direction.X) * Constants.DUAL_WIELD_MUZZLE_OFFSET_STUDS

	fireWeapon(firing[1], muzzle - sideways, direction, player)
	fireWeapon(firing[2], muzzle + sideways, direction, player)
end

function WeaponService.init(): ()
	-- Cambiar de personaje cambia el arma inicial: se descarta el loadout viejo para
	-- que el proximo `getLoadout` lo reconstruya con el arma del personaje nuevo.
	CharacterService.onSelectionChanged:connect(function(player: Player)
		loadouts[player] = nil
	end)
end

function WeaponService.start(): ()
	Remotes.event("FireRequest").OnServerEvent:Connect(onFireRequest)
	Remotes.event("SwapWeapon").OnServerEvent:Connect(onSwapWeapon)

	Players.PlayerRemoving:Connect(function(player: Player)
		loadouts[player] = nil
	end)

	log:info("Escuchando FireRequest y SwapWeapon. Armas disponibles: %d", #Weapons.ids)
end

return WeaponService

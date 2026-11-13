--!strict
--[[
	PickupService: armas en el suelo.

	Funciona por TAGS, no por scripts adentro del objeto (regla 4). Cualquier cosa
	taggeada `WeaponPickup` queda adoptada por este servicio, venga de un prefab
	colocado a mano en Studio o de `spawnWeaponPickup`. Eso es lo que permite que las
	salas de la Fase 3 traigan armas colocadas sin una sola linea de codigo adentro.

	El Attribute `WeaponId` decide que arma es. Si viene vacio, el servidor elige una
	al azar del pool completo al adoptarlo: ese es el `randomPool` del documento de
	contexto, y es lo que hace que una sala de objetos sea distinta cada run.

	Validacion de PickupRequest (el cliente solo dice "quiero ese", regla 5):
	  1. Rate limit
	  2. Es una instancia con el tag (no cualquier cosa que mande el cliente)
	  3. No esta reclamada por otro jugador (co-op: dos E simultaneos)
	  4. Ya paso su tiempo de armado (no re-agarrar lo que acabas de soltar)
	  5. Jugador vivo y a <= Constants.PICKUP_RANGE_STUDS studs
	Recien despues se toca el inventario.

	Lo visual (flotar, girar, cartelito con el nombre) NO esta aca: lo hace el cliente
	en FX/PickupView. El servidor no gasta un frame de Heartbeat en animar decorado.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)
local Weapons = require(Shared.Data.Weapons)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local WeaponService = require(script.Parent.Parent.Combat.WeaponService)

local PICKUP_BURST_CAPACITY = 8
local PICKUP_REFILL_PER_SECOND = 4

local WEAPON_ID_ATTRIBUTE = "WeaponId"
local PICKUP_SIZE = Vector3.new(3.2, 0.8, 0.8)
local CONTAINER_NAME = "Pickups"

local log = Logger.new("PickupService")

local PickupService = {
	name = "PickupService",
}

-- Claves debiles: si el pickup se destruye, su entrada se va sola con el.
local armedAt: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local claimed: { [Instance]: true } = setmetatable({}, { __mode = "k" }) :: any

local container: Folder? = nil
local random = Random.new()

local function getContainer(): Folder
	if container then
		return container
	end

	local existing = workspace:FindFirstChild(CONTAINER_NAME)
	local folder: Folder

	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = CONTAINER_NAME
		folder.Parent = workspace
	end

	container = folder

	return folder
end

--[[ Posicion de un pickup, sea una Part suelta o un Model armado en Studio. ]]
local function resolvePosition(pickup: Instance): Vector3?
	if pickup:IsA("BasePart") then
		return pickup.Position
	end

	if pickup:IsA("Model") then
		local pivot = pickup:GetPivot()

		return pivot.Position
	end

	return nil
end

--[[
	Adopta un pickup: le resuelve el arma (al azar si no trae Attribute), lo deja sin
	fisica y le pone su color. Idempotente: adoptar dos veces no rompe nada.
]]
local function adopt(pickup: Instance): ()
	local weaponId = pickup:GetAttribute(WEAPON_ID_ATTRIBUTE)
	local definition = Weapons.getById(if type(weaponId) == "string" then weaponId else nil)

	if not definition then
		definition = Weapons.expect(Weapons.randomId(random))
		pickup:SetAttribute(WEAPON_ID_ATTRIBUTE, definition.id)
	end

	if armedAt[pickup] == nil then
		armedAt[pickup] = 0
	end

	CollisionGroups.applyToModel(pickup, CollisionGroups.Names.Ghost)

	if pickup:IsA("BasePart") then
		pickup.Anchored = true
		pickup.CanCollide = false
		pickup.CanQuery = false -- que las balas no lo golpeen
		pickup.CanTouch = false
		pickup.CastShadow = false
		pickup.Color = Color3.fromRGB(
			definition.projectileColor.r,
			definition.projectileColor.g,
			definition.projectileColor.b
		)
	end
end

--[[
	Deja un arma flotando en `position` (la posicion es exactamente donde queda: el
	balanceo lo simula el cliente alrededor de este punto).

	`armDelaySeconds` existe para las armas que un jugador acaba de soltar: sin esa
	ventana, el mismo E que intercambia el arma la vuelve a recoger en el frame
	siguiente.
]]
function PickupService.spawnWeaponPickup(weaponId: Types.WeaponId, position: Vector3, armDelaySeconds: number?): BasePart
	local definition = Weapons.expect(weaponId)

	local part = Instance.new("Part")
	part.Name = string.format("Pickup_%s", definition.id)
	part.Size = PICKUP_SIZE
	part.Material = Enum.Material.Neon
	part.Position = position
	part:SetAttribute(WEAPON_ID_ATTRIBUTE, definition.id)
	part.Parent = getContainer()

	adopt(part)
	armedAt[part] = os.clock() + (armDelaySeconds or 0)

	-- El tag va al final: cuando se agrega, el pickup ya esta completo para quien
	-- escuche (incluido el cliente que le pinta el cartelito).
	CollectionService:AddTag(part, Tags.WeaponPickup)

	return part
end

--[[
	Borra todas las armas del suelo. Lo llama DungeonGenerator al cambiar de piso.

	Es necesario y no una limpieza cosmetica: todos los pisos se construyen sobre el
	mismo origen, asi que un pickup del piso 1 que sobreviva reaparece flotando DENTRO
	del piso 2, en una sala que no lo puso ahi. Tambien es la regla de diseno correcta:
	lo que dejaste tirado en un piso, se queda en ese piso.
]]
function PickupService.clearAll(): ()
	for _, pickup in CollectionService:GetTagged(Tags.WeaponPickup) do
		pickup:Destroy()
	end
end

local function onPickupRequest(player: Player, payload: unknown): ()
	if not RateLimiter.consume(player, "PickupRequest", PICKUP_BURST_CAPACITY, PICKUP_REFILL_PER_SECOND) then
		return
	end

	if typeof(payload) ~= "table" then
		return
	end

	local pickup = (payload :: any).pickup

	if typeof(pickup) ~= "Instance" then
		return
	end

	-- El tag es la autorizacion: sin el, el cliente podria mandar cualquier Instance
	-- del datamodel y pedir que se la equipen.
	if not CollectionService:HasTag(pickup, Tags.WeaponPickup) then
		return
	end

	if claimed[pickup] then
		return
	end

	local armed = armedAt[pickup]

	if armed and os.clock() < armed then
		return
	end

	if not CharacterService.isAlive(player) then
		return
	end

	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if not root or not root:IsA("BasePart") then
		return
	end

	local pickupPosition = resolvePosition(pickup)

	if not pickupPosition then
		return
	end

	if (pickupPosition - root.Position).Magnitude > Constants.PICKUP_RANGE_STUDS then
		return
	end

	local weaponId = pickup:GetAttribute(WEAPON_ID_ATTRIBUTE)

	if type(weaponId) ~= "string" then
		return
	end

	local equipped, replaced = WeaponService.equip(player, weaponId)

	if not equipped then
		return
	end

	-- Se marca reclamado ANTES de destruir: en co-op, dos jugadores pueden pedir el
	-- mismo pickup en el mismo frame y el segundo tiene que rebotar aca.
	claimed[pickup] = true
	pickup:Destroy()

	if replaced then
		local look = root.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		-- Un LookVector vertical daria un vector degenerado al aplanarlo, y `.Unit`
		-- sobre magnitud 0 devuelve NaN: el arma terminaria en ninguna parte.
		local offset = if forward.Magnitude > 1e-3
			then forward.Unit * Constants.WEAPON_DROP_FORWARD_STUDS
			else Vector3.zero

		PickupService.spawnWeaponPickup(replaced, root.Position + offset, Constants.PICKUP_ARM_DELAY_SECONDS)
	end
end

function PickupService.start(): ()
	getContainer()

	for _, pickup in CollectionService:GetTagged(Tags.WeaponPickup) do
		adopt(pickup)
	end

	CollectionService:GetInstanceAddedSignal(Tags.WeaponPickup):Connect(adopt)

	Remotes.event("PickupRequest").OnServerEvent:Connect(onPickupRequest)

	-- No hay estado por jugador que limpiar en PlayerRemoving: lo que este servicio
	-- recuerda (armado, reclamado) vive contra el pickup, no contra el jugador, y se
	-- va solo con el objeto por las claves debiles.

	log:info("Pickups activos. Pool aleatorio: %d armas", #Weapons.ids)
end

return PickupService

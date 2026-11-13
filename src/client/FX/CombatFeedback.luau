--!strict
--[[
	CombatFeedback: traduce lo que pasa en el mundo a sonido y a avisos para la UI.

	El servidor no manda ningun remote nuevo para esto. Todo sale de cosas que YA se
	replican por otros motivos (regla 2, regla 5):

	  - Las balas son Parts en `workspace.Projectiles` con su `CollisionGroup`
	    (PlayerBullet / EnemyBullet): alcanza para saber quien disparo y desde donde.
	  - `DamageDealt` (unreliable) ya trae posicion y cantidad para los popups.
	  - Los enemigos llevan el tag `Enemy` y el Attribute `Health`.
	  - Las monedas llevan el Attribute `CollectedBy` cuando alguien las levanta.
	  - Las puertas de sala llevan el Attribute `Closed`.
	  - `PlayerStatsChanged` (via ClientState) trae vida y armas de MI personaje.

	Lo que expone para la UI son dos signals, nada mas:
	  - `hitConfirmed(amount)`: le pegaste a algo. El HUD dibuja el hitmarker.
	  - `roomLockChanged(locked)`: una sala se cerro (empieza la pelea) o se abrio.

	Sobre "le pegaste VOS": `DamageDealt` no dice quien disparo. Se infiere: si una bala
	de jugador nacio pegada a tu personaje hace menos de `HIT_CONFIRM_WINDOW` segundos,
	y el impacto no fue sobre vos mismo, cuenta como tuyo. En co-op puede fallar en un
	caso borde (un companero que dispara justo al lado tuyo), y el costo de ese error es
	un hitmarker de mas: no vale un remote nuevo.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollisionGroups = require(Shared:WaitForChild("CollisionGroups"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tags = require(Shared:WaitForChild("Tags"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.State.ClientState)
local SoundController = require(script.Parent.Parent.Audio.SoundController)

local PROJECTILES_FOLDER_NAME = "Projectiles"
local COLLECTED_BY_ATTRIBUTE = "CollectedBy"
local DOOR_CLOSED_ATTRIBUTE = "Closed"

local OWN_SHOT_RADIUS_STUDS = 4.5 -- las balas nacen en el centro del cuerpo del que dispara
local SELF_HIT_RADIUS_STUDS = 3.5
local HIT_CONFIRM_WINDOW = 1.5
local COIN_COMBO_WINDOW = 0.7
local COIN_COMBO_MAX = 12
local COIN_COMBO_PITCH_STEP = 0.045

local CombatFeedback = {
	name = "CombatFeedback",
}

-- (cantidad de dano) cuando un impacto propio conecta
CombatFeedback.hitConfirmed = Signal.new() :: Signal.Signal<number>
-- (cerrada) cuando una sala pasa de abierta a cerrada o al reves
CombatFeedback.roomLockChanged = Signal.new() :: Signal.Signal<boolean>

local player = Players.LocalPlayer
local lastOwnShotAt = -math.huge
local lastCoinAt = -math.huge
local coinCombo = 0
local trackedDoors: { [BasePart]: boolean } = {}
local anyRoomLocked = false
local previousStats: Types.PlayerStatsSnapshot? = nil

local function getRootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

--------------------------------------------------------------------------------
-- Disparos
--------------------------------------------------------------------------------

local function onProjectile(instance: Instance): ()
	if not instance:IsA("BasePart") then
		return
	end

	local position = instance.Position

	if instance.CollisionGroup == CollisionGroups.Names.EnemyBullet then
		SoundController.playAt("shootEnemy", position)
		return
	end

	local rootPosition = getRootPosition()

	if rootPosition and (rootPosition - position).Magnitude <= OWN_SHOT_RADIUS_STUDS then
		lastOwnShotAt = os.clock()
		-- El disparo propio va en 2D: es TU arma, tiene que sonar "en tus manos".
		SoundController.play("shootPlayer")
	else
		SoundController.playAt("shootPlayer", position)
	end
end

local function watchProjectiles(folder: Instance): ()
	folder.ChildAdded:Connect(onProjectile)
end

--------------------------------------------------------------------------------
-- Impactos y bajas
--------------------------------------------------------------------------------

local function onDamageDealt(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end

	local position = (payload :: any).position
	local amount = (payload :: any).amount

	if typeof(position) ~= "Vector3" or typeof(amount) ~= "number" then
		return
	end

	local rootPosition = getRootPosition()
	local hitMe = rootPosition ~= nil and (rootPosition - position).Magnitude <= SELF_HIT_RADIUS_STUDS

	-- El golpe que recibo lo cuenta el snapshot de vida (sonido "hurt"), no esto.
	if hitMe then
		return
	end

	if os.clock() - lastOwnShotAt <= HIT_CONFIRM_WINDOW then
		SoundController.play("hitConfirm")
		CombatFeedback.hitConfirmed:fire(amount)
	else
		SoundController.playAt("hit", position)
	end
end

local function onEnemyRemoved(instance: Instance): ()
	-- Solo cuenta como "baja" si murio. Al limpiar el piso tambien se borran enemigos
	-- vivos, y eso no deberia sonar a fiesta.
	local health = instance:GetAttribute("Health")

	if typeof(health) ~= "number" or health > 0 then
		return
	end

	local ok, pivot = pcall(function()
		return (instance :: any):GetPivot()
	end)

	if ok and typeof(pivot) == "CFrame" then
		SoundController.playAt("enemyDown", pivot.Position)
	else
		SoundController.play("enemyDown")
	end
end

--------------------------------------------------------------------------------
-- Monedas
--------------------------------------------------------------------------------

local function onCoinCollected(coin: Instance): ()
	if coin:GetAttribute(COLLECTED_BY_ATTRIBUTE) ~= player.UserId then
		return
	end

	local now = os.clock()

	-- Combo: cada moneda seguida suena un poco mas aguda. Es el truco mas viejo de los
	-- juegos de plataformas y convierte juntar plata en un pequeno instrumento.
	if now - lastCoinAt <= COIN_COMBO_WINDOW then
		coinCombo = math.min(coinCombo + 1, COIN_COMBO_MAX)
	else
		coinCombo = 0
	end

	lastCoinAt = now
	SoundController.play("coin", 1 + coinCombo * COIN_COMBO_PITCH_STEP)
end

local function trackCoin(coin: Instance): ()
	coin:GetAttributeChangedSignal(COLLECTED_BY_ATTRIBUTE):Connect(function()
		onCoinCollected(coin)
	end)
end

--------------------------------------------------------------------------------
-- Salas
--------------------------------------------------------------------------------

local function recomputeRoomLock(): ()
	local locked = false

	for door, _ in trackedDoors do
		if not door.Parent then
			trackedDoors[door] = nil
		elseif door:GetAttribute(DOOR_CLOSED_ATTRIBUTE) == true then
			locked = true
		end
	end

	if locked == anyRoomLocked then
		return
	end

	anyRoomLocked = locked

	SoundController.play(if locked then "roomLocked" else "roomCleared")
	CombatFeedback.roomLockChanged:fire(locked)
end

local function trackDoor(instance: Instance): ()
	if not instance:IsA("BasePart") or trackedDoors[instance] ~= nil then
		return
	end

	if instance:GetAttribute(DOOR_CLOSED_ATTRIBUTE) == nil then
		return
	end

	trackedDoors[instance] = true

	instance:GetAttributeChangedSignal(DOOR_CLOSED_ATTRIBUTE):Connect(recomputeRoomLock)
	instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(workspace) then
			recomputeRoomLock()
		end
	end)
end

local function trackRoom(room: Instance): ()
	for _, descendant in room:GetDescendants() do
		trackDoor(descendant)
	end

	-- Por si las puertas llegan por red despues que el tag del modelo.
	room.DescendantAdded:Connect(trackDoor)
end

--------------------------------------------------------------------------------
-- Mi personaje
--------------------------------------------------------------------------------

local function onStats(snapshot: Types.PlayerStatsSnapshot): ()
	local previous = previousStats
	previousStats = snapshot

	if not previous then
		return
	end

	if snapshot.health < previous.health and snapshot.health > 0 then
		SoundController.play("hurt")
	end

	-- Cambiar de personaje cambia las armas: eso ya sono como "click" en el panel.
	if snapshot.characterId ~= previous.characterId then
		return
	end

	local gotNewWeapon = (snapshot.primaryWeaponId ~= previous.primaryWeaponId and snapshot.primaryWeaponId ~= nil)
		or (snapshot.secondaryWeaponId ~= previous.secondaryWeaponId and snapshot.secondaryWeaponId ~= nil)

	if gotNewWeapon then
		SoundController.play("weaponPickup")
	elseif snapshot.activeSlot ~= previous.activeSlot then
		SoundController.play("weaponSwap")
	end
end

--------------------------------------------------------------------------------

function CombatFeedback.start(): ()
	local projectiles = workspace:FindFirstChild(PROJECTILES_FOLDER_NAME)

	if projectiles then
		watchProjectiles(projectiles)
	end

	-- El servidor crea la carpeta con el primer disparo de la sesion.
	workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == PROJECTILES_FOLDER_NAME and child:IsA("Folder") then
			watchProjectiles(child)
		end
	end)

	Remotes.unreliable("DamageDealt").OnClientEvent:Connect(onDamageDealt)

	CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(onEnemyRemoved)

	for _, coin in CollectionService:GetTagged(Tags.Coin) do
		trackCoin(coin)
	end

	CollectionService:GetInstanceAddedSignal(Tags.Coin):Connect(trackCoin)

	for _, room in CollectionService:GetTagged(Tags.Room) do
		trackRoom(room)
	end

	CollectionService:GetInstanceAddedSignal(Tags.Room):Connect(trackRoom)

	ClientState.changed:connect(onStats)

	Remotes.event("AbilityActivated").OnClientEvent:Connect(function(payload: Types.AbilityActivatedPayload)
		if typeof(payload) ~= "table" then
			return
		end

		SoundController.play(if payload.kind == "Dash" then "dash" else "ability")
	end)
end

return CombatFeedback

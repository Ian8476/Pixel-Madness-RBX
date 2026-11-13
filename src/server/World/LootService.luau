--!strict
--[[
	LootService: las monedas.

	Regla 5 en su forma mas literal: la moneda es CREDITO DEL SERVIDOR. El cliente no
	decide que recogio nada, no informa que la toco y no puede acreditarse una. El
	servidor mira distancias y suma; el cliente solo ve volar el objeto.

	Por que este servicio no conoce a GameService (que es quien lleva el bote comun):
	si LootService requiriera GameService tendriamos el ciclo
	`GameService -> DungeonGenerator -> LootService -> GameService`. Se invierte la
	dependencia con una signal: LootService anuncia "se recogieron N monedas" y quien
	quiera llevar la cuenta se suscribe. Ademas es la regla 2 bien aplicada: el que
	suelta el loot no sabe para que sirve.

	EL DOBLE CREDITO, que es el bug que el plan pide cubrir explicitamente:
	una moneda se marca como recogida ANTES de acreditarla y la marca es la condicion
	para entrar. En co-op, dos jugadores pueden estar dentro del radio en el mismo
	tick: el segundo rebota en esa guarda. Y como el bote es comun, ni siquiera importa
	cual de los dos la agarro; lo que importa es que se sume UNA vez.

	Las monedas no tienen fisica: son Parts ancladas en el grupo `Ghost`, que no
	colisiona con nada. Dispersarlas con impulso seria mas vistoso y traeria monedas
	cayendose por los huecos de las puertas; se dispersan con un desplazamiento
	aleatorio y listo. El brillo y el giro los pone el cliente.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Signal = require(Shared.Signal)
local Tags = require(Shared.Tags)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local EnemySystem = require(script.Parent.Parent.Enemies.EnemySystem)

local CONTAINER_NAME = "Coins"
local COIN_SIZE = Vector3.new(1.4, 1.4, 0.3)
local COIN_COLOR = Color3.fromRGB(255, 210, 63)
local COIN_HEIGHT_STUDS = 2
local VALUE_ATTRIBUTE = "Value"
local COLLECTED_BY_ATTRIBUTE = "CollectedBy"

local log = Logger.new("LootService")

local LootService = {
	name = "LootService",
}

-- (cantidad, quien la levanto). El bote comun lo lleva GameService, no este servicio.
LootService.onCoinsCollected = Signal.new() :: Signal.Signal<number, Player>

local coins: { BasePart } = {}
local collected: { [BasePart]: true } = {}
local container: Folder? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local accumulator = 0
local random = Random.new()

local function getContainer(): Folder
	if container and container.Parent then
		return container
	end

	local existing = workspace:FindFirstChild(CONTAINER_NAME)

	if existing and existing:IsA("Folder") then
		container = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = CONTAINER_NAME
	folder.Parent = workspace

	container = folder

	return folder
end

local function spawnCoin(position: Vector3, value: number): ()
	local coin = Instance.new("Part")

	coin.Name = "Coin"
	coin.Size = COIN_SIZE
	coin.Shape = Enum.PartType.Cylinder
	coin.Color = COIN_COLOR
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CanQuery = false
	coin.CanTouch = false
	coin.CastShadow = false
	coin.Position = position
	coin:SetAttribute(VALUE_ATTRIBUTE, value)
	coin.Parent = getContainer()

	CollisionGroups.applyToModel(coin, CollisionGroups.Names.Ghost)
	CollectionService:AddTag(coin, Tags.Coin)

	table.insert(coins, coin)

	-- Autodestruccion: una moneda olvidada en una sala del piso 1 no puede seguir
	-- ocupando memoria y ciclos de iman diez minutos despues.
	Debris:AddItem(coin, Constants.COIN_LIFETIME_SECONDS)
end

--[[ Suelta el loot de un enemigo. Se engancha a la muerte, no la provoca (regla 2). ]]
local function dropFor(definition: { minCoinDrop: number, maxCoinDrop: number }, position: Vector3): ()
	local amount = random:NextInteger(definition.minCoinDrop, definition.maxCoinDrop)

	for _ = 1, amount do
		local angle = random:NextNumber() * math.pi * 2
		local distance = random:NextNumber() * Constants.COIN_SCATTER_RADIUS_STUDS

		spawnCoin(
			position + Vector3.new(math.cos(angle) * distance, COIN_HEIGHT_STUDS, math.sin(angle) * distance),
			Constants.COIN_VALUE
		)
	end
end

--[[ Borra todas las monedas del piso. Lo llama DungeonGenerator al regenerar. ]]
function LootService.clearAll(): ()
	for _, coin in coins do
		if coin.Parent then
			coin:Destroy()
		end
	end

	table.clear(coins)
	table.clear(collected)
end

function LootService.getActiveCount(): number
	return #coins
end

--------------------------------------------------------------------------------
-- Iman
--------------------------------------------------------------------------------

local function collect(coin: BasePart, player: Player): ()
	-- La marca va PRIMERO: es lo que hace que dos jugadores en el mismo tick no
	-- acrediten la misma moneda dos veces.
	if collected[coin] then
		return
	end

	collected[coin] = true

	local value = coin:GetAttribute(VALUE_ATTRIBUTE)

	-- El Attribute es lo que le dice al cliente hacia quien tiene que volar la moneda.
	-- El objeto sobrevive lo que dura el vuelo y despues se destruye: el credito ya
	-- esta hecho, lo que queda es puro adorno.
	coin:SetAttribute(COLLECTED_BY_ATTRIBUTE, player.UserId)
	Debris:AddItem(coin, Constants.COIN_PICKUP_FLIGHT_SECONDS)

	LootService.onCoinsCollected:fire(if typeof(value) == "number" then value else Constants.COIN_VALUE, player)
end

local function step(deltaTime: number): ()
	accumulator += deltaTime

	if accumulator < 1 / Constants.LOOT_CHECK_HZ then
		return
	end

	accumulator = 0

	if #coins == 0 then
		return
	end

	local radius = Constants.COIN_MAGNET_RADIUS_STUDS
	local survivors: { BasePart } = table.create(#coins)

	for _, coin in coins do
		if not coin.Parent then
			collected[coin] = nil
			continue
		end

		if collected[coin] then
			table.insert(survivors, coin)
			continue
		end

		table.insert(survivors, coin)

		for _, player in Players:GetPlayers() do
			if not CharacterService.isAlive(player) then
				continue
			end

			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

			if not root or not root:IsA("BasePart") then
				continue
			end

			if (root.Position - coin.Position).Magnitude <= radius then
				collect(coin, player)
				break
			end
		end
	end

	coins = survivors
end

function LootService.init(): ()
	EnemySystem.onEnemyDied:connect(function(enemy)
		dropFor(enemy.definition, enemy.root.Position)
	end)
end

function LootService.start(): ()
	if heartbeatConnection then
		return
	end

	getContainer()
	heartbeatConnection = RunService.Heartbeat:Connect(step)

	log:info("Monedas activas. Iman de %d studs.", Constants.COIN_MAGNET_RADIUS_STUDS)
end

return LootService

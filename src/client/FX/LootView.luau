--!strict
--[[
	LootView: el giro de las monedas y su vuelo hacia el que las levanta.

	Todo esto es DECORADO y por eso vive en el cliente. El servidor ya decidio y ya
	acredito: cuando esta View se entera, la moneda YA es tuya. Que el vuelo se vea
	suave es un problema de presentacion, no de estado (regla 5).

	Como se entera: el servidor le pone a la moneda el Attribute `CollectedBy` con el
	UserId del que la levanto y recien la destruye 0.3 s despues. Ese margen es la
	ventana del vuelo. No hace falta un remote nuevo para algo que ya viaja como
	propiedad replicada del objeto.

	Un solo RenderStepped para TODAS las monedas, no un bucle por objeto: misma regla
	que las balas en el servidor y que los pickups en `PickupView`.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Tags = require(Shared:WaitForChild("Tags"))

local BIND_NAME = "PixelMadnessLootView"
local COLLECTED_BY_ATTRIBUTE = "CollectedBy"

local SPIN_DEGREES_PER_SECOND = 220
local HOVER_AMPLITUDE_STUDS = 0.25
local HOVER_CYCLES_PER_SECOND = 1.6

type Tracked = {
	part: BasePart,
	basePosition: Vector3,
	phase: number,
	-- Cuando arranco el vuelo, o nil si todavia esta en el suelo.
	flightStartedAt: number?,
	flightFrom: Vector3?,
	collector: Player?,
}

local LootView = {
	name = "LootView",
}

local tracked: { [Instance]: Tracked } = {}
local elapsed = 0

local function onCollected(entry: Tracked): ()
	local userId = entry.part:GetAttribute(COLLECTED_BY_ATTRIBUTE)

	if typeof(userId) ~= "number" or entry.flightStartedAt then
		return
	end

	entry.collector = Players:GetPlayerByUserId(userId)
	entry.flightStartedAt = elapsed
	entry.flightFrom = entry.part.Position
end

local function track(instance: Instance): ()
	if tracked[instance] or not instance:IsA("BasePart") then
		return
	end

	local entry: Tracked = {
		part = instance,
		basePosition = instance.Position,
		-- Desfase por moneda: sin esto, las tres que solto un enemigo laten al unisono
		-- y se ven como un solo objeto raro en vez de como tres monedas.
		phase = math.random() * math.pi * 2,
		flightStartedAt = nil,
		flightFrom = nil,
		collector = nil,
	}

	tracked[instance] = entry

	-- Puede venir ya marcada si el cliente la vio despues de que la levantaran.
	if instance:GetAttribute(COLLECTED_BY_ATTRIBUTE) ~= nil then
		onCollected(entry)
	end

	instance:GetAttributeChangedSignal(COLLECTED_BY_ATTRIBUTE):Connect(function()
		onCollected(entry)
	end)
end

local function untrack(instance: Instance): ()
	tracked[instance] = nil
end

local function targetPosition(entry: Tracked): Vector3?
	local player = entry.collector

	if not player then
		return nil
	end

	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	return if root and root:IsA("BasePart") then root.Position else nil
end

local function update(deltaTime: number): ()
	elapsed += deltaTime

	for instance, entry in tracked do
		if not entry.part.Parent then
			tracked[instance] = nil
			continue
		end

		local spin = CFrame.Angles(0, math.rad(elapsed * SPIN_DEGREES_PER_SECOND), math.rad(90))

		if entry.flightStartedAt and entry.flightFrom then
			local progress = (elapsed - entry.flightStartedAt) / Constants.COIN_PICKUP_FLIGHT_SECONDS
			local destination = targetPosition(entry)

			if destination then
				-- Acelerar hacia el final (progress^2) se lee como atraccion magnetica;
				-- una interpolacion lineal parece que la moneda flota sola.
				local eased = math.clamp(progress, 0, 1) ^ 2

				entry.part.CFrame = CFrame.new(entry.flightFrom:Lerp(destination, eased)) * spin
			end

			continue
		end

		local height = math.sin((elapsed * HOVER_CYCLES_PER_SECOND * math.pi * 2) + entry.phase)
			* HOVER_AMPLITUDE_STUDS

		entry.part.CFrame = CFrame.new(entry.basePosition + Vector3.new(0, height, 0)) * spin
	end
end

function LootView.start(): ()
	for _, coin in CollectionService:GetTagged(Tags.Coin) do
		track(coin)
	end

	CollectionService:GetInstanceAddedSignal(Tags.Coin):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.Coin):Connect(untrack)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, update)
end

return LootView

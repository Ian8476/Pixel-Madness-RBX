--!strict
--[[
	BreakableService: le da vida (Health) a todo lo taggeado `Breakable`.

	Es el ejemplo mas chico de la regla 4: el prefab no lleva scripts adentro. Se
	construye una caja en Studio, se le pone el tag, se le pone el Attribute
	`MaxHealth` si queres algo distinto del default, y el sistema la adopta desde
	afuera. Sirve igual para los muniecos de prueba de la Fase 1 que para los
	barriles rompibles de las salas reales.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Logger)
local Tags = require(Shared.Tags)

local Health = require(script.Parent.Parent.Combat.Health)
local HealthRegistry = require(script.Parent.Parent.Combat.HealthRegistry)

local DEFAULT_MAX_HEALTH = 100
local DEBRIS_LIFETIME_SECONDS = 1

local log = Logger.new("BreakableService")

local BreakableService = {
	name = "BreakableService",
}

local function findAnchorPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function onBreakableAdded(instance: Instance): ()
	if HealthRegistry.get(instance) then
		return
	end

	local anchor = findAnchorPart(instance)

	if not anchor then
		log:warn("%s tiene el tag Breakable pero no contiene ninguna BasePart", instance:GetFullName())
		return
	end

	local maximum = instance:GetAttribute("MaxHealth")
	local health = Health.new({
		maximum = if typeof(maximum) == "number" and maximum > 0 then maximum else DEFAULT_MAX_HEALTH,
	})

	HealthRegistry.register(instance, health)

	-- Se replica como Attribute de solo lectura para el cliente: sirve para pintar
	-- una barra o una grieta sin abrir un remote nuevo para algo puramente cosmetico.
	instance:SetAttribute("Health", health:getCurrent())

	health.onHealthChanged:connect(function(current: number)
		if instance.Parent then
			instance:SetAttribute("Health", current)
		end
	end)

	health.onDeath:connect(function()
		HealthRegistry.unregister(instance)

		if instance:IsA("BasePart") then
			instance.Anchored = false
			instance.CanCollide = false
		end

		Debris:AddItem(instance, DEBRIS_LIFETIME_SECONDS)
	end)
end

function BreakableService.start(): ()
	for _, instance in CollectionService:GetTagged(Tags.Breakable) do
		onBreakableAdded(instance)
	end

	CollectionService:GetInstanceAddedSignal(Tags.Breakable):Connect(onBreakableAdded)

	CollectionService:GetInstanceRemovedSignal(Tags.Breakable):Connect(function(instance: Instance)
		HealthRegistry.unregister(instance)
	end)
end

return BreakableService

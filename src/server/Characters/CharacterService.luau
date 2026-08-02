--!strict
--[[
	CharacterService: todo lo que le pasa al cuerpo del jugador cuando aparece.

	Responsabilidad unica: dejar el personaje en estado jugable y con Health propio.
	NO decide CUANDO spawnea (eso sera GameService en la Fase 4) ni que personaje se
	eligio (eso sera CharacterSelect en la Fase 5). Recibe un Model y lo prepara.

	Notas de por que cada ajuste esta aca:
	- `AutoRotate = false`: el personaje mira al mouse, no hacia donde camina. La
	  rotacion la hace el cliente porque el cliente es el dueno de red de su propio
	  personaje; hacerla en el servidor daria un giro con un round-trip de retraso.
	- Salto deshabilitado por dos vias (JumpPower/JumpHeight en 0 y el estado apagado):
	  solo bajar JumpPower deja al Humanoid entrando igual en estado Jumping.
	- El script `Health` nativo que Roblox inyecta en cada personaje se borra: regenera
	  vida por su cuenta y pelearia contra nuestro modulo (decision D2).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Logger = require(Shared.Logger)
local Signal = require(Shared.Signal)
local Tags = require(Shared.Tags)

local Health = require(script.Parent.Parent.Combat.Health)
local HealthRegistry = require(script.Parent.Parent.Combat.HealthRegistry)

-- TEMPORAL (Fase 2): estos valores salen de CharacterDef en cuanto exista la seleccion
-- de personaje. Por ahora todos juegan a Don Bonko.
local TEMP_MAX_HEALTH = 130
local TEMP_WALK_SPEED = 16
local TEMP_COLOR = Color3.fromRGB(235, 122, 40)
local INVULNERABILITY_AFTER_HIT_SECONDS = 0.35

local log = Logger.new("CharacterService")

local CharacterService = {
	name = "CharacterService",
}

-- (jugador, personaje) una vez configurado y con Health registrado
CharacterService.onCharacterReady = Signal.new() :: Signal.Signal<Player, Model>

local function removeNativeRegeneration(character: Model): ()
	local nativeScript = character:FindFirstChild("Health")

	if nativeScript and nativeScript:IsA("Script") then
		nativeScript:Destroy()
	end
end

local function applyGreybox(character: Model): ()
	local bodyColors = character:FindFirstChildOfClass("BodyColors")

	if bodyColors then
		bodyColors:Destroy()
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.Color = TEMP_COLOR
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("Decal") or descendant:IsA("Accessory") or descendant:IsA("Shirt") then
			descendant:Destroy()
		end
	end
end

local function configureHumanoid(humanoid: Humanoid): ()
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = TEMP_WALK_SPEED
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.UseJumpPower = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	-- El Humanoid queda inmortal a proposito: quien decide la muerte es nuestro Health.
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.BreakJointsOnDeath = false
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
end

local function onCharacterAdded(player: Player, character: Model): ()
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		log:warn("El personaje de %s no expuso un Humanoid", player.Name)
		return
	end

	removeNativeRegeneration(character)
	configureHumanoid(humanoid)
	applyGreybox(character)

	CollisionGroups.applyToModel(character, CollisionGroups.Names.PlayerChar)
	CollectionService:AddTag(character, Tags.Player)

	local health = Health.new({
		maximum = TEMP_MAX_HEALTH,
		invulnerabilitySecondsAfterHit = INVULNERABILITY_AFTER_HIT_SECONDS,
	})

	HealthRegistry.register(character, health)

	health.onDeath:connect(function()
		-- El Humanoid es el actuador: matarlo hereda gratis la animacion de muerte.
		humanoid.Health = 0
	end)

	character.Destroying:Once(function()
		HealthRegistry.unregister(character)
	end)

	CharacterService.onCharacterReady:fire(player, character)
end

function CharacterService.getHealth(player: Player): Health.Health?
	local character = player.Character

	if not character then
		return nil
	end

	return HealthRegistry.get(character)
end

function CharacterService.isAlive(player: Player): boolean
	local health = CharacterService.getHealth(player)

	return health ~= nil and not health:isDead()
end

function CharacterService.start(): ()
	local function bind(player: Player): ()
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end)

		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		bind(player)
	end

	Players.PlayerAdded:Connect(bind)
end

return CharacterService

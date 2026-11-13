--!strict
--[[
	CharacterService: todo lo que le pasa al cuerpo del jugador cuando aparece, y
	quien es ese jugador (que personaje eligio).

	Responsabilidad unica: dejar el personaje en estado jugable, con las stats de SU
	CharacterDef y con Health propio. NO decide CUANDO spawnea (eso sera GameService
	en la Fase 4).

	Cambio de la Fase 2: se acabaron los valores hardcodeados. Vida, velocidad y color
	salen de `Shared/Data/Characters/` (regla 1: contenido = datos). Cambiar la vida de
	Don Bonko es editar un numero en un archivo de datos, no tocar este servicio.

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
local Characters = require(Shared.Data.Characters)
local CollisionGroups = require(Shared.CollisionGroups)
local Logger = require(Shared.Logger)
local Signal = require(Shared.Signal)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)

local Health = require(script.Parent.Parent.Combat.Health)
local HealthRegistry = require(script.Parent.Parent.Combat.HealthRegistry)

local INVULNERABILITY_AFTER_HIT_SECONDS = 0.35

local log = Logger.new("CharacterService")

local CharacterService = {
	name = "CharacterService",
}

-- (jugador, personaje) una vez configurado y con Health registrado
CharacterService.onCharacterReady = Signal.new() :: Signal.Signal<Player, Model>
-- (jugador, definicion elegida)
CharacterService.onSelectionChanged = Signal.new() :: Signal.Signal<Player, Types.CharacterDef>

local selectedById: { [Player]: Types.CharacterId } = {}

local function removeNativeRegeneration(character: Model): ()
	local nativeScript = character:FindFirstChild("Health")

	if nativeScript and nativeScript:IsA("Script") then
		nativeScript:Destroy()
	end
end

local function applyGreybox(character: Model, definition: Types.CharacterDef): ()
	local bodyColors = character:FindFirstChildOfClass("BodyColors")

	if bodyColors then
		bodyColors:Destroy()
	end

	local color = Color3.fromRGB(definition.greyboxColor.r, definition.greyboxColor.g, definition.greyboxColor.b)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.Color = color
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("Decal") or descendant:IsA("Accessory") or descendant:IsA("Shirt") then
			descendant:Destroy()
		end
	end
end

local function configureHumanoid(humanoid: Humanoid, definition: Types.CharacterDef): ()
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = definition.walkSpeed
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

--[[ Personaje elegido por el jugador; Don Bonko si todavia no eligio. ]]
function CharacterService.getCharacterDef(player: Player): Types.CharacterDef
	return Characters.expect(selectedById[player] or Characters.defaultId)
end

local function onCharacterAdded(player: Player, character: Model): ()
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		log:warn("El personaje de %s no expuso un Humanoid", player.Name)
		return
	end

	local definition = CharacterService.getCharacterDef(player)

	removeNativeRegeneration(character)
	configureHumanoid(humanoid, definition)
	applyGreybox(character, definition)

	CollisionGroups.applyToModel(character, CollisionGroups.Names.PlayerChar)
	CollectionService:AddTag(character, Tags.Player)

	local health = Health.new({
		maximum = definition.maxHealth,
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

--[[
	Cambia el personaje elegido. Devuelve false si el id no existe.

	Es un SETTER, no un manejador de remotes. Quien escucha `SelectCharacter` y decide
	si se puede elegir ahora mismo es `LobbyService` (Fase 5): esa validacion es "que
	podes hacer en el lobby", no "quien sos", y ademas ponerla aca crearia el ciclo
	`CharacterService -> GameService -> CharacterService`.

	La Fase 7 le sumara "y lo tenes desbloqueado", tambien del lado de LobbyService.
]]
function CharacterService.select(player: Player, characterId: unknown): boolean
	if type(characterId) ~= "string" then
		return false
	end

	local definition = Characters.getById(characterId)

	if not definition then
		return false
	end

	if selectedById[player] == definition.id then
		return true
	end

	selectedById[player] = definition.id
	CharacterService.onSelectionChanged:fire(player, definition)

	return true
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

	Players.PlayerRemoving:Connect(function(player: Player)
		selectedById[player] = nil
	end)

	log:info("Personajes disponibles: %d (por defecto: %s)", #Characters.ids, Characters.defaultId)
end

return CharacterService

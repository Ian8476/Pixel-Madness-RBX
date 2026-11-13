--!strict
--[[
	HUDView: lo que el jugador mira sin darse cuenta de que lo esta mirando.

	Una View PINTA, no decide (patron UIController + ClientState + Views). Este archivo
	no calcula vida, no sabe cuanta energia cuesta un disparo y no le pregunta nada al
	servidor: recibe snapshots y los dibuja.

	--------------------------------------------------------------------------------
	QUE HAY EN PANTALLA Y POR QUE
	--------------------------------------------------------------------------------

	Abajo a la izquierda, la tarjeta del jugador: retrato redondo con el color del
	personaje, nombre, vida (con muescas por cuartos) y energia. Cada barra lleva su
	icono (corazon, rayo) para que se distingan sin leer.

	Abajo a la derecha, una fila: [habilidad] [arma 1] [arma 2]. La habilidad es un
	boton redondo que se "llena de sombra" mientras se enfria y brilla cuando vuelve.
	El arma activa se agranda y se pone dorada.

	Arriba al centro: el piso actual y tres pastillas de progreso. Debajo, la barra del
	jefe cuando hay uno vivo.

	Arriba a la derecha: las monedas del bote comun. Cuando suben, el contador rebota y
	sale flotando un "+N".

	En el centro exacto: la cruz, y el hitmarker (una X) cuando un disparo propio
	conecta. Sin el hitmarker, en una sala llena de enemigos no hay forma de saber cual
	de los veinte numeros flotantes es tuyo.

	Encima de todo: el destello rojo al recibir un golpe y la vineta roja que late con
	poca vida.

	--------------------------------------------------------------------------------
	DOS DETALLES DE IMPLEMENTACION QUE NO SON OBVIOS
	--------------------------------------------------------------------------------

	1. El enfriamiento de la habilidad se INTERPOLA localmente. El servidor manda
	   `abilityCooldownRemaining` diez veces por segundo; se guarda con su marca de
	   tiempo y se descuenta el tiempo transcurrido cada frame. La verdad sigue siendo
	   del servidor: esto es interpolacion visual entre dos verdades.

	2. Los rastros de las barras usan `1 - exp(-velocidad * dt)` y no un alpha fijo por
	   frame: con alpha fijo, el rastro se moveria mas rapido a 144 fps que a 60.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Tags = require(Shared:WaitForChild("Tags"))
local Types = require(Shared:WaitForChild("Types"))
local Weapons = require(Shared:WaitForChild("Data"):WaitForChild("Weapons"))
local Characters = require(Shared:WaitForChild("Data"):WaitForChild("Characters"))

local ClientState = require(script.Parent.Parent.Parent.State.ClientState)
local CombatFeedback = require(script.Parent.Parent.Parent.FX.CombatFeedback)
local SoundController = require(script.Parent.Parent.Parent.Audio.SoundController)
local Theme = require(script.Parent.Parent.Theme)

local BIND_NAME = "PixelMadnessHUD"

-- Muescas en cuartos: "cuartos" se lee igual con 80 de vida (Nina) que con 130 (Bonko).
local HEALTH_SEGMENTS = 4
local GHOST_CATCHUP_SPEED = 3.5
local LOW_HEALTH_RATIO = 0.3
local LOW_HEALTH_PULSES_PER_SECOND = 2.2
local DAMAGE_FLASH_TRANSPARENCY = 0.5
local DAMAGE_FLASH_SECONDS = 0.35
local READY_PULSES_PER_SECOND = 1.4

local CROSSHAIR_SIZE = 44
local CROSSHAIR_TICK_LENGTH = 9
local CROSSHAIR_TICK_THICKNESS = 3
local CROSSHAIR_GAP = 6
local HITMARKER_SECONDS = 0.22

local SLOT_SIZE = Vector2.new(132, 104)
local LONG_WEAPON_NAME = 12 -- caracteres a partir de los cuales el nombre se achica
local ABILITY_SIZE = 104
local MARGIN = 24

local HUDView = {}
HUDView.__index = HUDView

type Widgets = {
	root: Frame,

	portrait: Frame,
	portraitGradient: UIGradient,
	portraitInitial: TextLabel,
	characterName: TextLabel,
	healthBar: Theme.Bar,
	healthText: TextLabel,
	healthBadge: Frame,
	energyBar: Theme.Bar,
	energyText: TextLabel,

	slotFrames: { Frame },
	slotGradients: { UIGradient },
	slotStrokes: { UIStroke },
	slotNames: { TextLabel },
	slotIcons: { TextLabel },

	abilityButton: Frame,
	abilityGradient: UIGradient,
	abilityStroke: UIStroke,
	abilityIcon: TextLabel,
	abilityShade: Frame,
	abilityShadeGradient: UIGradient,
	abilityTimer: TextLabel,
	abilityName: TextLabel,
	abilityStatus: TextLabel,

	floorLabel: TextLabel,
	floorPips: { Frame },
	coinsPanel: Frame,
	coinsLabel: TextLabel,
	coinBadge: Frame,

	bossPanel: Frame,
	bossName: TextLabel,
	bossBar: Theme.Bar,

	crosshair: Frame,
	hitmarker: Frame,
	hitmarkerTicks: { Frame },

	damageFlash: Frame,
	lowHealthVignette: Frame,
}

export type HUDView = typeof(setmetatable(
	{} :: {
		widgets: Widgets,
		cooldownRemaining: number,
		cooldownStampedAt: number,
		cooldownTotal: number,
		wasAbilityReady: boolean,
		lastHealth: number,
		lastCoins: number,
		lastActiveSlot: number,
		healthGhostRatio: number,
		energyGhostRatio: number,
		bossGhostRatio: number,
		boss: Instance?,
		connections: { RBXScriptConnection },
	},
	HUDView
))

local function colorFromRgb(rgb: { r: number, g: number, b: number }): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function iconForAbility(kind: Types.AbilityKind): string
	if kind == "Dash" then
		return Theme.icons.dash
	elseif kind == "DualWield" then
		return Theme.icons.swords
	end

	return Theme.icons.bolt
end

--------------------------------------------------------------------------------
-- Construccion
--------------------------------------------------------------------------------

local function buildVignette(parent: Instance, name: string, color: Color3, zIndex: number): Frame
	local frame = Instance.new("Frame")

	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent

	-- Degradado desde los bordes, no tinte plano: tapar la pantalla entera esconde
	-- justo lo que el jugador necesita ver despues de recibir un golpe.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.7, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = frame

	return frame
end

local function buildPlayerPanel(parent: Instance, widgets: any): ()
	local colors = Theme.colors

	local panel = Theme.panel({
		name = "PlayerPanel",
		parent = parent,
		size = UDim2.fromOffset(392, 124),
		position = UDim2.new(0, MARGIN, 1, -MARGIN),
		anchorPoint = Vector2.new(0, 1),
		radius = 18,
		transparency = 0.08,
	})

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Size = UDim2.fromOffset(92, 92)
	portrait.Position = UDim2.fromOffset(14, 16)
	portrait.BorderSizePixel = 0
	portrait.Parent = panel
	Theme.circle(portrait)
	Theme.outline(portrait, 4)

	local portraitGradient = Theme.gradient(portrait, colors.grey, colors.greyDark)

	local initial = Theme.label({
		name = "Initial",
		parent = portrait,
		size = UDim2.fromScale(1, 1),
		text = "?",
		textSize = 54,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
		strokeThickness = 4,
	})

	local characterName = Theme.label({
		name = "CharacterName",
		parent = panel,
		size = UDim2.fromOffset(260, 26),
		position = UDim2.fromOffset(120, 10),
		text = "...",
		textSize = 24,
		font = Theme.titleFont,
	})

	local healthBar = Theme.bar({
		name = "HealthBar",
		parent = panel,
		size = UDim2.fromOffset(240, 30),
		position = UDim2.fromOffset(138, 44),
		fillTop = colors.health,
		fillBottom = colors.healthDark,
		ghostColor = colors.healthGhost,
		segments = HEALTH_SEGMENTS,
	})

	local healthText = Theme.label({
		name = "HealthText",
		parent = healthBar.container,
		size = UDim2.fromScale(1, 1),
		text = "",
		textSize = 19,
		alignment = Enum.TextXAlignment.Center,
	})
	healthText.ZIndex = 6

	-- La medalla va ENCIMA del extremo izquierdo de la barra: el icono "sostiene" la
	-- barra, el gesto clasico de los HUD de Roblox.
	local healthBadge = Theme.iconBadge({
		name = "HealthBadge",
		parent = panel,
		size = 38,
		position = UDim2.fromOffset(120, 40),
		icon = Theme.icons.heart,
		-- Fondo claro: un corazon rojo sobre una medalla roja no se ve.
		top = Color3.fromRGB(255, 240, 245),
		bottom = Color3.fromRGB(255, 176, 196),
	})
	healthBadge.ZIndex = 8
	;(healthBadge:FindFirstChild("Icon") :: TextLabel).ZIndex = 9

	local energyBar = Theme.bar({
		name = "EnergyBar",
		parent = panel,
		size = UDim2.fromOffset(240, 22),
		position = UDim2.fromOffset(138, 86),
		fillTop = colors.energy,
		fillBottom = colors.energyDark,
		ghostColor = colors.energyGhost,
	})

	local energyText = Theme.label({
		name = "EnergyText",
		parent = energyBar.container,
		size = UDim2.fromScale(1, 1),
		text = "",
		textSize = 15,
		alignment = Enum.TextXAlignment.Center,
	})
	energyText.ZIndex = 6

	local energyBadge = Theme.iconBadge({
		name = "EnergyBadge",
		parent = panel,
		size = 32,
		position = UDim2.fromOffset(122, 81),
		icon = Theme.icons.bolt,
		top = colors.energy,
		bottom = colors.energyDark,
	})
	energyBadge.ZIndex = 8
	;(energyBadge:FindFirstChild("Icon") :: TextLabel).ZIndex = 9

	widgets.portrait = portrait
	widgets.portraitGradient = portraitGradient
	widgets.portraitInitial = initial
	widgets.characterName = characterName
	widgets.healthBar = healthBar
	widgets.healthText = healthText
	widgets.healthBadge = healthBadge
	widgets.energyBar = energyBar
	widgets.energyText = energyText
end

local function buildWeaponSlots(parent: Instance, widgets: any): ()
	local colors = Theme.colors

	widgets.slotFrames = {}
	widgets.slotGradients = {}
	widgets.slotStrokes = {}
	widgets.slotNames = {}
	widgets.slotIcons = {}

	for slot = 1, 2 do
		-- La ranura 1 va a la izquierda de la 2: el mismo orden en que las lee el
		-- jugador cuando aprieta Q.
		local offsetX = if slot == 2 then -MARGIN else -(MARGIN + SLOT_SIZE.X + 14)

		local frame = Theme.panel({
			name = string.format("WeaponSlot%d", slot),
			parent = parent,
			size = UDim2.fromOffset(SLOT_SIZE.X, SLOT_SIZE.Y),
			position = UDim2.new(1, offsetX - SLOT_SIZE.X / 2, 1, -MARGIN - SLOT_SIZE.Y / 2),
			anchorPoint = Vector2.new(0.5, 0.5),
			radius = 16,
			strokeThickness = 4,
		})

		local icon = Theme.label({
			name = "Icon",
			parent = frame,
			size = UDim2.new(1, 0, 0, 50),
			position = UDim2.fromOffset(0, 8),
			text = Theme.icons.gun,
			textSize = 40,
			alignment = Enum.TextXAlignment.Center,
			strokeThickness = 0,
		})

		local name = Theme.label({
			name = "WeaponName",
			parent = frame,
			size = UDim2.new(1, -12, 0, 40),
			position = UDim2.fromOffset(6, 58),
			text = "-",
			textSize = 16,
			alignment = Enum.TextXAlignment.Center,
		})
		name.TextWrapped = true

		Theme.keyCap(frame, tostring(slot), UDim2.fromOffset(-8, -8))

		table.insert(widgets.slotFrames, frame)
		table.insert(widgets.slotGradients, frame:FindFirstChildOfClass("UIGradient"))
		table.insert(widgets.slotStrokes, frame:FindFirstChildOfClass("UIStroke"))
		table.insert(widgets.slotNames, name)
		table.insert(widgets.slotIcons, icon)
	end

	-- Ayuda de teclas encima de las ranuras.
	local hint = Instance.new("Frame")
	hint.Name = "SwapHint"
	hint.Size = UDim2.fromOffset(SLOT_SIZE.X * 2 + 14, 28)
	hint.Position = UDim2.new(1, -MARGIN, 1, -MARGIN - SLOT_SIZE.Y - 12)
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.BackgroundTransparency = 1
	hint.Parent = parent

	Theme.keyCap(hint, "Q", UDim2.fromOffset(0, 1))
	Theme.label({
		name = "SwapText",
		parent = hint,
		size = UDim2.fromOffset(90, 28),
		position = UDim2.fromOffset(34, 0),
		text = "CAMBIAR",
		textSize = 16,
		color = colors.textMuted,
	})
	Theme.keyCap(hint, "E", UDim2.fromOffset(140, 1))
	Theme.label({
		name = "PickupText",
		parent = hint,
		size = UDim2.fromOffset(90, 28),
		position = UDim2.fromOffset(174, 0),
		text = "RECOGER",
		textSize = 16,
		color = colors.textMuted,
	})
end

local function buildAbility(parent: Instance, widgets: any): ()
	local colors = Theme.colors
	local rightEdge = MARGIN + SLOT_SIZE.X * 2 + 14 + 22

	local button = Instance.new("Frame")
	button.Name = "Ability"
	button.Size = UDim2.fromOffset(ABILITY_SIZE, ABILITY_SIZE)
	button.Position = UDim2.new(1, -rightEdge - ABILITY_SIZE / 2, 1, -MARGIN - ABILITY_SIZE / 2)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BorderSizePixel = 0
	button.Parent = parent
	Theme.circle(button)

	local gradient = Theme.gradient(button, colors.purple, colors.purpleDark)
	local stroke = Theme.outline(button, 5)

	local icon = Theme.label({
		name = "Icon",
		parent = button,
		size = UDim2.fromScale(1, 1),
		text = Theme.icons.sparkles,
		textSize = 52,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 0,
	})
	icon.ZIndex = 2

	-- Sombra de enfriamiento: un circulo oscuro del mismo tamano cuyo degradado de
	-- transparencia "sube" desde abajo. Un Frame que crece no sirve aca porque no se
	-- puede recortar a un circulo; un degradado si respeta la forma.
	local shade = Instance.new("Frame")
	shade.Name = "CooldownShade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = colors.outline
	shade.BackgroundTransparency = 0.25
	shade.BorderSizePixel = 0
	shade.ZIndex = 3
	shade.Visible = false
	shade.Parent = button
	Theme.circle(shade)

	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Rotation = 90
	shadeGradient.Parent = shade

	local timer = Theme.label({
		name = "Timer",
		parent = button,
		size = UDim2.fromScale(1, 1),
		text = "",
		textSize = 34,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
		strokeThickness = 3,
	})
	timer.ZIndex = 4

	local key = Theme.keyCap(button, "ESPACIO", UDim2.new(0.5, 0, 1, 6), Vector2.new(0.5, 0.5))
	key.ZIndex = 5
	;(key:FindFirstChild("Key") :: TextLabel).ZIndex = 6

	local name = Theme.label({
		name = "AbilityName",
		parent = parent,
		size = UDim2.fromOffset(200, 24),
		position = UDim2.new(1, -rightEdge - ABILITY_SIZE / 2, 1, -MARGIN - ABILITY_SIZE - 16),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "-",
		textSize = 20,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
	})

	-- Estado de una habilidad activa ("DOBLE BONK!", "CADENCIA x2"), encima del nombre.
	local status = Theme.label({
		name = "AbilityStatus",
		parent = parent,
		size = UDim2.fromOffset(240, 26),
		position = UDim2.new(1, -rightEdge - ABILITY_SIZE / 2, 1, -MARGIN - ABILITY_SIZE - 42),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		textSize = 22,
		color = colors.gold,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
	})

	widgets.abilityButton = button
	widgets.abilityGradient = gradient
	widgets.abilityStroke = stroke
	widgets.abilityIcon = icon
	widgets.abilityShade = shade
	widgets.abilityShadeGradient = shadeGradient
	widgets.abilityTimer = timer
	widgets.abilityName = name
	widgets.abilityStatus = status
end

local function buildTopBars(parent: Instance, widgets: any): ()
	local colors = Theme.colors

	-- Piso
	local floorPanel = Theme.panel({
		name = "FloorPanel",
		parent = parent,
		size = UDim2.fromOffset(250, 52),
		position = UDim2.new(0.5, 0, 0, 16),
		anchorPoint = Vector2.new(0.5, 0),
		radius = 26,
	})

	Theme.label({
		name = "FloorIcon",
		parent = floorPanel,
		size = UDim2.fromOffset(44, 52),
		position = UDim2.fromOffset(12, 0),
		text = Theme.icons.castle,
		textSize = 30,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 0,
	})

	local floorLabel = Theme.title({
		name = "FloorLabel",
		parent = floorPanel,
		size = UDim2.new(1, -60, 1, 0),
		position = UDim2.fromOffset(52, 2),
		text = "PISO 1 / 3",
		textSize = 30,
		strokeThickness = 3,
		top = colors.text,
		bottom = colors.textMuted,
	})

	local pips: { Frame } = {}

	for index = 1, Constants.FLOORS_PER_RUN do
		local pip = Instance.new("Frame")
		pip.Name = string.format("Pip%d", index)
		pip.Size = UDim2.fromOffset(16, 16)
		pip.Position = UDim2.new(0.5, (index - 2) * 26, 0, 76)
		pip.AnchorPoint = Vector2.new(0.5, 0)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = colors.panelDeep
		pip.Parent = parent
		Theme.circle(pip)
		Theme.outline(pip, 2)

		table.insert(pips, pip)
	end

	-- Monedas
	local coinsPanel = Theme.panel({
		name = "CoinsPanel",
		parent = parent,
		size = UDim2.fromOffset(180, 54),
		position = UDim2.new(1, -MARGIN, 0, 16),
		anchorPoint = Vector2.new(1, 0),
		radius = 27,
	})

	local coinBadge = Theme.iconBadge({
		name = "CoinBadge",
		parent = coinsPanel,
		size = 58,
		position = UDim2.new(0, -14, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		icon = Theme.icons.coin,
		top = colors.gold,
		bottom = colors.goldDark,
		iconScale = 0.62,
	})
	coinBadge.ZIndex = 3
	;(coinBadge:FindFirstChild("Icon") :: TextLabel).ZIndex = 4

	local coinsLabel = Theme.title({
		name = "CoinsLabel",
		parent = coinsPanel,
		size = UDim2.new(1, -60, 1, 0),
		position = UDim2.fromOffset(50, 2),
		text = "0",
		textSize = 32,
		strokeThickness = 3,
		alignment = Enum.TextXAlignment.Center,
	})

	-- Jefe
	local bossPanel = Theme.panel({
		name = "BossPanel",
		parent = parent,
		size = UDim2.fromOffset(660, 80),
		position = UDim2.new(0.5, 0, 0, 104),
		anchorPoint = Vector2.new(0.5, 0),
		top = Color3.fromRGB(110, 36, 90),
		bottom = Color3.fromRGB(52, 16, 48),
		radius = 18,
		strokeThickness = 4,
	})

	bossPanel.Visible = false

	local skull = Theme.iconBadge({
		name = "SkullBadge",
		parent = bossPanel,
		size = 66,
		position = UDim2.new(0, -18, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		icon = Theme.icons.skull,
		top = colors.red,
		bottom = colors.purpleDark,
		iconScale = 0.6,
	})
	skull.ZIndex = 3
	;(skull:FindFirstChild("Icon") :: TextLabel).ZIndex = 4

	local bossName = Theme.title({
		name = "BossName",
		parent = bossPanel,
		size = UDim2.new(1, -80, 0, 30),
		position = UDim2.fromOffset(60, 6),
		text = "EL BONKARON",
		textSize = 28,
		strokeThickness = 3,
		top = colors.orange,
		bottom = colors.red,
	})

	local bossBar = Theme.bar({
		name = "BossBar",
		parent = bossPanel,
		size = UDim2.new(1, -84, 0, 26),
		position = UDim2.fromOffset(60, 42),
		fillTop = colors.red,
		fillBottom = colors.purpleDark,
		ghostColor = colors.healthGhost,
		segments = 10,
	})

	widgets.floorLabel = floorLabel
	widgets.floorPips = pips
	widgets.coinsPanel = coinsPanel
	widgets.coinsLabel = coinsLabel
	widgets.coinBadge = coinBadge
	widgets.bossPanel = bossPanel
	widgets.bossName = bossName
	widgets.bossBar = bossBar
end

--[[
	La cruz: cuatro marcas y un punto, con hueco en el medio (una cruz maciza tapa
	justo el pixel que el jugador mira). Encima, el hitmarker: cuatro marcas en X que
	aparecen un instante cuando un disparo propio conecta.
]]
local function buildCrosshair(parent: Instance, widgets: any): ()
	local container = Instance.new("Frame")

	container.Name = "Crosshair"
	container.Size = UDim2.fromOffset(CROSSHAIR_SIZE, CROSSHAIR_SIZE)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.ZIndex = 40
	container.Parent = parent

	local function tick(name: string, rotation: number, distance: number, color: Color3, holder: Frame): Frame
		local radians = math.rad(rotation)
		local mark = Instance.new("Frame")

		mark.Name = name
		mark.Size = UDim2.fromOffset(CROSSHAIR_TICK_THICKNESS, CROSSHAIR_TICK_LENGTH)
		mark.Position = UDim2.new(0.5, math.sin(radians) * distance, 0.5, -math.cos(radians) * distance)
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Rotation = rotation
		mark.BackgroundColor3 = color
		mark.BorderSizePixel = 0
		mark.ZIndex = 41
		mark.Parent = holder
		Theme.corner(mark, 2)
		Theme.outline(mark, 1.5)

		return mark
	end

	local tickDistance = CROSSHAIR_GAP + CROSSHAIR_TICK_LENGTH / 2

	for index, rotation in { 0, 90, 180, 270 } do
		tick(string.format("Tick%d", index), rotation, tickDistance, Theme.colors.text, container)
	end

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(5, 5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Theme.colors.gold
	dot.BorderSizePixel = 0
	dot.ZIndex = 41
	dot.Parent = container
	Theme.circle(dot)
	Theme.outline(dot, 1.5)

	local hitmarker = Instance.new("Frame")
	hitmarker.Name = "Hitmarker"
	hitmarker.Size = UDim2.fromScale(1, 1)
	hitmarker.BackgroundTransparency = 1
	hitmarker.Visible = false
	hitmarker.ZIndex = 42
	hitmarker.Parent = container

	local ticks: { Frame } = {}

	for index, rotation in { 45, 135, 225, 315 } do
		local mark = tick(string.format("Hit%d", index), rotation, tickDistance + 3, Theme.colors.text, hitmarker)
		mark.ZIndex = 43
		table.insert(ticks, mark)
	end

	widgets.crosshair = container
	widgets.hitmarker = hitmarker
	widgets.hitmarkerTicks = ticks
end

--------------------------------------------------------------------------------
-- Ciclo de vida
--------------------------------------------------------------------------------

function HUDView.new(parent: Instance): HUDView
	local root = Instance.new("Frame")
	root.Name = "HUD"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = parent

	local widgets: any = { root = root }

	widgets.lowHealthVignette = buildVignette(root, "LowHealth", Theme.colors.redDark, 1)

	buildPlayerPanel(root, widgets)
	buildWeaponSlots(root, widgets)
	buildAbility(root, widgets)
	buildTopBars(root, widgets)
	buildCrosshair(root, widgets)

	widgets.damageFlash = buildVignette(root, "DamageFlash", Theme.colors.health, 50)

	return setmetatable({
		widgets = widgets :: Widgets,
		cooldownRemaining = 0,
		cooldownStampedAt = os.clock(),
		cooldownTotal = 1,
		wasAbilityReady = true,
		lastHealth = -1,
		lastCoins = -1,
		lastActiveSlot = 0,
		healthGhostRatio = 1,
		energyGhostRatio = 1,
		bossGhostRatio = 1,
		boss = nil,
		connections = {},
	}, HUDView)
end

--------------------------------------------------------------------------------
-- Pintado
--------------------------------------------------------------------------------

local function ratio(current: number, maximum: number): number
	if maximum <= 0 then
		return 0
	end

	return math.clamp(current / maximum, 0, 1)
end

function HUDView.flashDamage(self: HUDView): ()
	local flash = self.widgets.damageFlash

	flash.BackgroundTransparency = DAMAGE_FLASH_TRANSPARENCY

	TweenService
		:Create(flash, TweenInfo.new(DAMAGE_FLASH_SECONDS, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
		:Play()

	Theme.bounce(self.widgets.healthBadge, 1.3)
end

function HUDView.showHitmarker(self: HUDView, amount: number): ()
	local widgets = self.widgets
	local isBig = amount >= Constants.BIG_DAMAGE_THRESHOLD
	local color = if isBig then Theme.colors.orange else Theme.colors.text

	widgets.hitmarker.Visible = true

	for _, mark in widgets.hitmarkerTicks do
		mark.BackgroundColor3 = color
		mark.BackgroundTransparency = 0

		TweenService:Create(mark, TweenInfo.new(HITMARKER_SECONDS, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		}):Play()
	end

	Theme.bounce(widgets.hitmarker, if isBig then 1.6 else 1.3)
end

--[[ Pinta una ranura de arma como activa (dorada y mas grande) o en reposo. ]]
local function paintSlot(widgets: Widgets, slot: number, isActive: boolean): ()
	local colors = Theme.colors

	if isActive then
		Theme.setGradient(widgets.slotGradients[slot], colors.gold, colors.orangeDark)
		widgets.slotStrokes[slot].Color = colors.text
		widgets.slotStrokes[slot].Thickness = 5
	else
		Theme.setGradient(widgets.slotGradients[slot], colors.panelTop, colors.panel)
		widgets.slotStrokes[slot].Color = colors.outline
		widgets.slotStrokes[slot].Thickness = 4
	end

	TweenService:Create(Theme.scaleOf(widgets.slotFrames[slot]), Theme.tweens.hover, {
		Scale = if isActive then 1.08 else 0.94,
	}):Play()
end

--[[ Redibuja todo lo que depende del snapshot del jugador. ]]
function HUDView.applyStats(self: HUDView, snapshot: Types.PlayerStatsSnapshot): ()
	local widgets = self.widgets
	local colors = Theme.colors

	local definition = Characters.getById(snapshot.characterId)

	if definition then
		local color = colorFromRgb(definition.greyboxColor)

		widgets.characterName.Text = string.upper(definition.displayName)
		widgets.characterName.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
		widgets.portraitInitial.Text = string.upper(string.sub(definition.displayName, 1, 1))
		Theme.setGradient(widgets.portraitGradient, color:Lerp(Color3.new(1, 1, 1), 0.25), darken(color, 0.35))

		widgets.abilityName.Text = string.upper(definition.ability.displayName)
		widgets.abilityIcon.Text = iconForAbility(definition.ability.kind)
		-- El cooldown TOTAL sale de los datos del personaje, no del snapshot: el
		-- servidor manda cuanto FALTA, y sin el total no se puede dibujar una fraccion.
		self.cooldownTotal = math.max(definition.ability.cooldownSeconds, 0.001)
	else
		widgets.characterName.Text = "..."
	end

	-- Vida
	local healthRatio = ratio(snapshot.health, snapshot.maxHealth)

	widgets.healthBar.fill.Size = UDim2.fromScale(healthRatio, 1)
	widgets.healthText.Text = string.format("%d / %d", math.ceil(snapshot.health), math.floor(snapshot.maxHealth))

	if self.lastHealth >= 0 and snapshot.health < self.lastHealth then
		self:flashDamage()
	end

	-- Aparecer o revivir reinicia el rastro: si no, la barra "cae" desde el valor del
	-- personaje anterior y parece que naciste recibiendo un golpe.
	if snapshot.health > self.lastHealth then
		self.healthGhostRatio = math.max(self.healthGhostRatio, healthRatio)
	end

	self.lastHealth = snapshot.health

	-- Energia
	local energyRatio = ratio(snapshot.energy, snapshot.maxEnergy)

	widgets.energyBar.fill.Size = UDim2.fromScale(energyRatio, 1)
	widgets.energyText.Text = string.format("%d", math.floor(snapshot.energy))

	-- Armas
	local weaponIds = { snapshot.primaryWeaponId, snapshot.secondaryWeaponId }

	for slot = 1, 2 do
		local weapon = Weapons.getById(weaponIds[slot])

		local weaponName = if weapon then string.upper(weapon.displayName) else "VACIA"

		widgets.slotNames[slot].Text = weaponName
		-- Los nombres largos ("LA ESCUPECHATARRA") bajan un punto en vez de cortarse.
		-- No se usa TextScaled: con el UIScale global, una palabra corta crece hasta
		-- llenar la caja y "VACIA" terminaba mas grande que el nombre de un arma.
		widgets.slotNames[slot].TextSize = if #weaponName > LONG_WEAPON_NAME then 13 else 16
		widgets.slotNames[slot].TextColor3 = if weapon then colors.text else colors.textMuted
		widgets.slotIcons[slot].Text = if weapon then Theme.icons.gun else ""
		widgets.slotIcons[slot].TextTransparency = if weapon then 0 else 1
	end

	if snapshot.activeSlot ~= self.lastActiveSlot then
		self.lastActiveSlot = snapshot.activeSlot

		for slot = 1, 2 do
			paintSlot(widgets, slot, snapshot.activeSlot == slot)
		end
	end

	-- Habilidad: se guarda con marca de tiempo para interpolarla entre snapshots.
	self.cooldownRemaining = snapshot.abilityCooldownRemaining
	self.cooldownStampedAt = os.clock()

	if snapshot.isDualWielding then
		widgets.abilityStatus.Text = Theme.icons.exclaim .. "DOBLE BONK!"
	elseif snapshot.fireRateMultiplier > 1 then
		widgets.abilityStatus.Text = string.format("CADENCIA x%d", math.floor(snapshot.fireRateMultiplier))
	else
		widgets.abilityStatus.Text = ""
	end
end

--[[ Redibuja lo que depende del estado de la run. ]]
function HUDView.applyRunState(self: HUDView, snapshot: Types.RunStateSnapshot): ()
	local widgets = self.widgets
	local colors = Theme.colors

	widgets.floorLabel.Text = string.format("PISO %d / %d", snapshot.floorNumber, snapshot.floorsPerRun)

	for index, pip in widgets.floorPips do
		local reached = index <= snapshot.floorNumber
		local isBossFloor = index == snapshot.floorsPerRun

		pip.BackgroundColor3 = if reached
			then (if isBossFloor then colors.red else colors.gold)
			else colors.panelDeep
		pip.Visible = index <= snapshot.floorsPerRun
	end

	local coins = snapshot.sharedCoins

	widgets.coinsLabel.Text = tostring(coins)

	if self.lastCoins >= 0 and coins > self.lastCoins then
		self:celebrateCoins(coins - self.lastCoins)
	end

	self.lastCoins = coins
end

--[[ El contador rebota y sale flotando un "+N" dorado. ]]
function HUDView.celebrateCoins(self: HUDView, gained: number): ()
	local widgets = self.widgets

	Theme.bounce(widgets.coinBadge, 1.35)
	Theme.bounce(widgets.coinsLabel, 1.2)

	local floater = Theme.title({
		name = "CoinFloater",
		parent = widgets.root,
		size = UDim2.fromOffset(120, 30),
		position = UDim2.new(1, -MARGIN - 70, 0, 78),
		anchorPoint = Vector2.new(0.5, 0),
		text = "+" .. tostring(gained),
		textSize = 28,
		strokeThickness = 3,
	})

	local stroke = floater:FindFirstChildOfClass("UIStroke") :: UIStroke
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(floater, info, {
		Position = floater.Position + UDim2.fromOffset(0, 34),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()

	task.delay(0.85, function()
		floater:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Jefe
--------------------------------------------------------------------------------

local function readNumberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)

	return if typeof(value) == "number" then value else nil
end

function HUDView.refreshBoss(self: HUDView, deltaTime: number): ()
	local widgets = self.widgets
	local boss = self.boss

	if not boss or not boss.Parent then
		self.boss = nil
		widgets.bossPanel.Visible = false
		return
	end

	local current = readNumberAttribute(boss, "Health")
	local maximum = readNumberAttribute(boss, "MaxHealth")

	if not current or not maximum then
		widgets.bossPanel.Visible = false
		return
	end

	local displayName = boss:GetAttribute("DisplayName")

	widgets.bossName.Text = if typeof(displayName) == "string" then displayName else string.upper(boss.Name)

	if not widgets.bossPanel.Visible then
		widgets.bossPanel.Visible = true
		self.bossGhostRatio = 1
		Theme.popIn(widgets.bossPanel)
	end

	local healthRatio = ratio(current, maximum)
	local alpha = 1 - math.exp(-GHOST_CATCHUP_SPEED * deltaTime)

	self.bossGhostRatio += (healthRatio - self.bossGhostRatio) * alpha

	widgets.bossBar.fill.Size = UDim2.fromScale(healthRatio, 1)
	widgets.bossBar.ghost.Size = UDim2.fromScale(math.max(self.bossGhostRatio, healthRatio), 1)
end

--------------------------------------------------------------------------------
-- Frame a frame
--------------------------------------------------------------------------------

--[[
	Sombra de enfriamiento: cubre la fraccion `covered` del circulo, desde abajo.
	Con Rotation = 90 el degradado va de arriba (0) a abajo (1).
]]
local function setShade(widgets: Widgets, covered: number): ()
	if covered <= 0.001 then
		widgets.abilityShade.Visible = false
		return
	end

	widgets.abilityShade.Visible = true

	local edge = math.clamp(1 - covered, 0.002, 0.998)

	widgets.abilityShadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(edge - 0.001, 1),
		NumberSequenceKeypoint.new(edge, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

function HUDView.update(self: HUDView, deltaTime: number): ()
	local widgets = self.widgets
	local colors = Theme.colors
	local now = os.clock()

	-- Rastro de las barras.
	local alpha = 1 - math.exp(-GHOST_CATCHUP_SPEED * deltaTime)

	self.healthGhostRatio += (widgets.healthBar.fill.Size.X.Scale - self.healthGhostRatio) * alpha
	self.energyGhostRatio += (widgets.energyBar.fill.Size.X.Scale - self.energyGhostRatio) * alpha

	widgets.healthBar.ghost.Size = UDim2.fromScale(self.healthGhostRatio, 1)
	widgets.energyBar.ghost.Size = UDim2.fromScale(self.energyGhostRatio, 1)

	-- Vida baja: la barra late y los bordes de la pantalla se tinen de rojo.
	local healthRatio = widgets.healthBar.fill.Size.X.Scale

	if healthRatio > 0 and healthRatio < LOW_HEALTH_RATIO then
		local pulse = (math.sin(now * LOW_HEALTH_PULSES_PER_SECOND * math.pi * 2) + 1) / 2

		Theme.setGradient(
			widgets.healthBar.fillGradient,
			colors.health:Lerp(colors.text, pulse * 0.5),
			colors.healthDark:Lerp(colors.health, pulse * 0.5)
		)
		widgets.lowHealthVignette.BackgroundTransparency = 0.55 + pulse * 0.3
	else
		Theme.setGradient(widgets.healthBar.fillGradient, colors.health, colors.healthDark)
		widgets.lowHealthVignette.BackgroundTransparency = 1
	end

	-- Enfriamiento interpolado entre snapshots.
	local remaining = math.max(0, self.cooldownRemaining - (now - self.cooldownStampedAt))
	local isReady = remaining <= 0

	if isReady then
		setShade(widgets, 0)
		widgets.abilityTimer.Text = ""
		widgets.abilityIcon.TextTransparency = 0

		-- Lista: el borde late en dorado. Se ve de reojo sin leer nada.
		local pulse = (math.sin(now * READY_PULSES_PER_SECOND * math.pi * 2) + 1) / 2

		widgets.abilityStroke.Color = colors.gold:Lerp(colors.text, pulse)
		widgets.abilityStroke.Thickness = 4 + pulse * 2
		widgets.abilityName.TextColor3 = colors.ready
	else
		setShade(widgets, math.clamp(remaining / self.cooldownTotal, 0, 1))
		widgets.abilityTimer.Text = if remaining >= 10
			then string.format("%d", math.ceil(remaining))
			else string.format("%.1f", remaining)
		widgets.abilityIcon.TextTransparency = 0.5
		widgets.abilityStroke.Color = colors.outline
		widgets.abilityStroke.Thickness = 5
		widgets.abilityName.TextColor3 = colors.textMuted
	end

	if isReady and not self.wasAbilityReady then
		SoundController.play("abilityReady")
		Theme.bounce(widgets.abilityButton, 1.2)
	end

	self.wasAbilityReady = isReady

	self:refreshBoss(deltaTime)
end

--------------------------------------------------------------------------------

function HUDView.start(self: HUDView): ()
	local function trackBoss(instance: Instance): ()
		self.boss = instance
	end

	for _, instance in CollectionService:GetTagged(Tags.Boss) do
		trackBoss(instance)
	end

	table.insert(self.connections, CollectionService:GetInstanceAddedSignal(Tags.Boss):Connect(trackBoss))
	table.insert(
		self.connections,
		CollectionService:GetInstanceRemovedSignal(Tags.Boss):Connect(function(instance: Instance)
			if self.boss == instance then
				self.boss = nil
			end
		end)
	)

	ClientState.changed:connect(function(snapshot: Types.PlayerStatsSnapshot)
		self:applyStats(snapshot)
	end)

	ClientState.runChanged:connect(function(snapshot: Types.RunStateSnapshot)
		self:applyRunState(snapshot)
	end)

	CombatFeedback.hitConfirmed:connect(function(amount: number)
		if self.widgets.root.Visible then
			self:showHitmarker(amount)
		end
	end)

	-- Puede haber llegado un snapshot antes de que esta View existiera.
	local stats = ClientState.get()

	if stats then
		self:applyStats(stats)
	end

	local run = ClientState.getRun()

	if run then
		self:applyRunState(run)
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function(deltaTime: number)
		self:update(deltaTime)
	end)
end

function HUDView.setVisible(self: HUDView, visible: boolean): ()
	self.widgets.root.Visible = visible
end

return HUDView

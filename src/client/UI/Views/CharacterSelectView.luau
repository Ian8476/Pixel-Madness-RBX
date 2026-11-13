--!strict
--[[
	CharacterSelectView: la pantalla de elegir personaje.

	Lo que esta pantalla NO hace, y es importante: no decide nada. Manda
	`SelectCharacter` con un id y se calla. El servidor valida que el id exista (y en la
	Fase 7, que este desbloqueado) y responde cambiando el personaje. Si el jugador
	edita su cliente para mandar un id inventado, el servidor lo descarta.

	Las barras de stats se normalizan contra el MAXIMO DE CADA STAT entre los
	personajes, no contra un tope absoluto. Comparar es el unico trabajo de esta
	pantalla: que Nina tenga la barra de velocidad llena significa "la mas rapida de
	los tres", que es lo que el jugador esta tratando de averiguar.

	Rediseno "estilo Roblox": cada tarjeta lleva el color de su personaje como
	cabecera, las barras de stats tienen cada una su color e icono, las tarjetas entran
	rebotando una detras de otra y la elegida lleva una cinta dorada.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Characters = require(Shared:WaitForChild("Data"):WaitForChild("Characters"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local Weapons = require(Shared:WaitForChild("Data"):WaitForChild("Weapons"))

local ClientState = require(script.Parent.Parent.Parent.State.ClientState)
local SoundController = require(script.Parent.Parent.Parent.Audio.SoundController)
local Theme = require(script.Parent.Parent.Theme)

local CARD_SIZE = Vector2.new(310, 470)
local CARD_GAP = 28
local HOVER_SCALE = 1.05
local CARD_STAGGER_SECONDS = 0.07

local CharacterSelectView = {}
CharacterSelectView.__index = CharacterSelectView

type Card = {
	button: TextButton,
	stroke: UIStroke,
	scale: UIScale,
	ribbon: Frame,
	characterId: Types.CharacterId,
	color: Color3,
}

export type CharacterSelectView = typeof(setmetatable(
	{} :: {
		root: Frame,
		dim: TextButton,
		cards: { Card },
		isOpen: boolean,
		-- (abierto) para que UIController esconda el HUD detras del panel sin que esta
		-- View tenga que conocerlo. Se emite tanto al apretar C como al elegir una
		-- tarjeta, que es justo el caso que se olvida si el que cierra es el llamador.
		openChanged: Signal.Signal<boolean>,
	},
	CharacterSelectView
))

--------------------------------------------------------------------------------

local function colorFromRgb(rgb: { r: number, g: number, b: number }): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

--[[ Techo de cada stat entre los personajes: la referencia para comparar. ]]
local function computeStatCeilings(): { health: number, speed: number, energy: number }
	local ceilings = { health = 1, speed = 1, energy = 1 }

	for _, definition in Characters.all do
		ceilings.health = math.max(ceilings.health, definition.maxHealth)
		ceilings.speed = math.max(ceilings.speed, definition.walkSpeed)
		ceilings.energy = math.max(ceilings.energy, definition.maxEnergy)
	end

	return ceilings
end

--[[ Una frase que explique la habilidad sin obligar a leer numeros. ]]
local function describeAbility(ability: Types.AbilityDef): string
	if ability.kind == "Dash" then
		return string.format("Impulso rapido e invulnerable %.2fs", ability.invulnerabilitySeconds)
	elseif ability.kind == "DualWield" then
		return string.format("Dispara las DOS armas %ds", ability.durationSeconds)
	end

	return string.format("Cadencia x%d durante %ds", ability.fireRateMultiplier, ability.durationSeconds)
end

local function buildStatRow(
	parent: Instance,
	y: number,
	icon: string,
	label: string,
	value: number,
	ceiling: number,
	top: Color3,
	bottom: Color3
): ()
	Theme.label({
		name = label .. "Icon",
		parent = parent,
		size = UDim2.fromOffset(24, 22),
		position = UDim2.fromOffset(16, y),
		text = icon,
		textSize = 18,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 0,
	})

	Theme.label({
		name = label,
		parent = parent,
		size = UDim2.fromOffset(96, 22),
		position = UDim2.fromOffset(44, y),
		text = label,
		textSize = 15,
		color = Theme.colors.textMuted,
	})

	local bar = Theme.bar({
		name = label .. "Bar",
		parent = parent,
		size = UDim2.fromOffset(CARD_SIZE.X - 160, 16),
		position = UDim2.fromOffset(142, y + 3),
		fillTop = top,
		fillBottom = bottom,
		ghostColor = top,
	})

	local fraction = math.clamp(value / ceiling, 0.05, 1)

	bar.fill.Size = UDim2.fromScale(fraction, 1)
	bar.ghost.Visible = false
end

local function buildCard(
	parent: Instance,
	definition: Types.CharacterDef,
	index: number,
	total: number,
	ceilings: { health: number, speed: number, energy: number }
): Card
	local colors = Theme.colors
	local icons = Theme.icons
	local totalWidth = total * CARD_SIZE.X + (total - 1) * CARD_GAP
	local offsetX = -totalWidth / 2 + (index - 1) * (CARD_SIZE.X + CARD_GAP)
	local color = colorFromRgb(definition.greyboxColor)

	local button = Instance.new("TextButton")
	button.Name = string.format("Card_%s", definition.id)
	button.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	button.Position = UDim2.new(0.5, offsetX + CARD_SIZE.X / 2, 0.5, 30)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent

	Theme.corner(button, 22)
	Theme.gradient(button, colors.panelTop, colors.panel)

	local stroke = Theme.outline(button, 5)
	local scale = Theme.scaleOf(button)

	-- Cabecera con el color del personaje: en una mazmorra con niebla el personaje se
	-- reconoce por color y silueta, no por su cara. La tarjeta muestra ese dato.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -20, 0, 150)
	header.Position = UDim2.fromOffset(10, 10)
	header.BorderSizePixel = 0
	header.Parent = button
	Theme.corner(header, 16)
	Theme.gradient(header, color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(Color3.new(0, 0, 0), 0.4))
	Theme.outline(header, 3)

	local avatar = Instance.new("Frame")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.fromOffset(104, 104)
	avatar.Position = UDim2.fromScale(0.5, 0.5)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.BackgroundColor3 = Color3.new(1, 1, 1)
	avatar.BackgroundTransparency = 0.75
	avatar.BorderSizePixel = 0
	avatar.Parent = header
	Theme.circle(avatar)
	Theme.outline(avatar, 4, Color3.new(1, 1, 1))

	Theme.label({
		name = "Initial",
		parent = avatar,
		size = UDim2.fromScale(1, 1),
		text = string.upper(string.sub(definition.displayName, 1, 1)),
		textSize = 72,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
		strokeThickness = 5,
	})

	Theme.title({
		name = "Name",
		parent = button,
		size = UDim2.new(1, -24, 0, 34),
		position = UDim2.fromOffset(12, 166),
		text = string.upper(definition.displayName),
		textSize = 30,
		strokeThickness = 4,
		top = color:Lerp(Color3.new(1, 1, 1), 0.45),
		bottom = color,
	})

	local flavor = Theme.label({
		name = "Flavor",
		parent = button,
		size = UDim2.new(1, -32, 0, 38),
		position = UDim2.fromOffset(16, 202),
		text = string.format('"%s"', definition.flavorText),
		textSize = 15,
		color = colors.textMuted,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 1.5,
	})
	flavor.TextWrapped = true

	buildStatRow(button, 246, icons.heart, "VIDA", definition.maxHealth, ceilings.health, colors.health, colors.healthDark)
	buildStatRow(button, 272, icons.runner, "VELOCIDAD", definition.walkSpeed, ceilings.speed, colors.green, colors.greenDark)
	buildStatRow(button, 298, icons.bolt, "ENERGIA", definition.maxEnergy, ceilings.energy, colors.energy, colors.energyDark)

	local abilityPanel = Theme.panel({
		name = "Ability",
		parent = button,
		size = UDim2.new(1, -28, 0, 96),
		position = UDim2.fromOffset(14, 328),
		top = colors.purple,
		bottom = colors.purpleDark,
		radius = 14,
	})

	Theme.label({
		name = "AbilityName",
		parent = abilityPanel,
		size = UDim2.new(1, -20, 0, 24),
		position = UDim2.fromOffset(10, 6),
		text = icons.sparkles .. " " .. string.upper(definition.ability.displayName),
		textSize = 20,
		font = Theme.titleFont,
		color = colors.gold,
	})

	local abilityText = Theme.label({
		name = "AbilityText",
		parent = abilityPanel,
		size = UDim2.new(1, -20, 0, 36),
		position = UDim2.fromOffset(10, 32),
		text = describeAbility(definition.ability),
		textSize = 15,
	})
	abilityText.TextWrapped = true
	abilityText.TextYAlignment = Enum.TextYAlignment.Top

	Theme.label({
		name = "AbilityCost",
		parent = abilityPanel,
		size = UDim2.new(1, -20, 0, 18),
		position = UDim2.fromOffset(10, 70),
		text = string.format(
			"%s %d energia   %s %ss",
			icons.bolt,
			definition.ability.energyCost,
			icons.hourglass,
			tostring(definition.ability.cooldownSeconds)
		),
		textSize = 14,
		color = colors.textMuted,
	})

	local startingWeapon = Weapons.getById(definition.startingWeaponId)

	local weaponPill = Theme.panel({
		name = "StartingWeapon",
		parent = button,
		size = UDim2.new(1, -28, 0, 30),
		position = UDim2.fromOffset(14, 430),
		top = colors.gold,
		bottom = colors.goldDark,
		radius = 15,
		strokeThickness = 3,
	})

	Theme.label({
		name = "Text",
		parent = weaponPill,
		size = UDim2.fromScale(1, 1),
		text = string.format(
			"%s %s",
			icons.gun,
			if startingWeapon then string.upper(startingWeapon.displayName) else "?"
		),
		textSize = 16,
		alignment = Enum.TextXAlignment.Center,
	})

	-- Cinta "ACTUAL" del personaje que se esta jugando.
	local ribbon = Theme.panel({
		name = "Ribbon",
		parent = button,
		size = UDim2.fromOffset(130, 34),
		position = UDim2.new(1, 14, 0, -10),
		anchorPoint = Vector2.new(1, 0),
		top = colors.gold,
		bottom = colors.orangeDark,
		radius = 10,
		strokeThickness = 3,
	})
	ribbon.Rotation = 8
	ribbon.ZIndex = 10
	ribbon.Visible = false

	local ribbonText = Theme.label({
		name = "Text",
		parent = ribbon,
		size = UDim2.fromScale(1, 1),
		text = icons.check .. " ACTUAL",
		textSize = 18,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
	})
	ribbonText.ZIndex = 11

	return {
		button = button,
		stroke = stroke,
		scale = scale,
		ribbon = ribbon,
		characterId = definition.id,
		color = color,
	}
end

--------------------------------------------------------------------------------

function CharacterSelectView.new(parent: Instance): CharacterSelectView
	local colors = Theme.colors

	local root = Instance.new("Frame")
	root.Name = "CharacterSelect"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 20
	root.Parent = parent

	-- Fondo oscurecido COMO BOTON: se come los clicks para que elegir personaje no
	-- dispare el arma que hay detras del panel. Clic afuera de las tarjetas = cerrar.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundTransparency = 0.2
	dim.BorderSizePixel = 0
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Parent = root
	Theme.gradient(dim, Color3.fromRGB(40, 20, 80), colors.screenDim)

	Theme.title({
		name = "Title",
		parent = root,
		size = UDim2.fromOffset(900, 70),
		position = UDim2.new(0.5, 0, 0.5, -310),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "ELIGE TU PERSONAJE",
		textSize = 64,
		strokeThickness = 6,
		top = colors.gold,
		bottom = colors.orangeDark,
	})

	Theme.label({
		name = "Subtitle",
		parent = root,
		size = UDim2.fromOffset(700, 26),
		position = UDim2.new(0.5, 0, 0.5, -262),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "Solo se puede elegir en el lobby  -  [C] abre y cierra",
		textSize = 18,
		color = colors.textMuted,
		alignment = Enum.TextXAlignment.Center,
	})

	local self = setmetatable({
		root = root,
		dim = dim,
		cards = {},
		isOpen = false,
		openChanged = Signal.new() :: Signal.Signal<boolean>,
	}, CharacterSelectView)

	local closeButton = Theme.button({
		name = "Close",
		parent = root,
		size = UDim2.fromOffset(56, 56),
		position = UDim2.new(0.5, (#Characters.all * (CARD_SIZE.X + CARD_GAP)) / 2 + 10, 0.5, -310),
		text = "X",
		textSize = 32,
		top = colors.red,
		bottom = colors.redDark,
		clickSound = "back",
	})

	closeButton.button.Activated:Connect(function()
		self:setOpen(false)
	end)

	dim.Activated:Connect(function()
		SoundController.play("back")
		self:setOpen(false)
	end)

	local ceilings = computeStatCeilings()
	local total = #Characters.all

	for index, definition in Characters.all do
		local card = buildCard(root, definition, index, total, ceilings)

		table.insert(self.cards, card)

		card.button.MouseEnter:Connect(function()
			SoundController.play("hover")
			TweenService:Create(card.scale, Theme.tweens.hover, { Scale = HOVER_SCALE }):Play()
			card.button.Rotation = if index % 2 == 0 then 1 else -1
		end)

		card.button.MouseLeave:Connect(function()
			TweenService:Create(card.scale, Theme.tweens.hover, { Scale = 1 }):Play()
			card.button.Rotation = 0
		end)

		card.button.Activated:Connect(function()
			SoundController.play("ready")
			Remotes.event("SelectCharacter"):FireServer({ characterId = card.characterId })
			self:setOpen(false)
		end)
	end

	return self
end

--[[ Marca cual es el personaje que se esta jugando ahora mismo. ]]
function CharacterSelectView.highlight(self: CharacterSelectView, characterId: Types.CharacterId?): ()
	for _, card in self.cards do
		local isCurrent = card.characterId == characterId

		card.stroke.Color = if isCurrent then Theme.colors.gold else Theme.colors.outline
		card.stroke.Thickness = if isCurrent then 6 else 5
		card.ribbon.Visible = isCurrent
	end
end

function CharacterSelectView.setOpen(self: CharacterSelectView, open: boolean): ()
	if self.isOpen == open then
		return
	end

	self.isOpen = open
	self.root.Visible = open

	if open then
		local stats = ClientState.get()

		self:highlight(if stats then stats.characterId else nil)
		SoundController.play("panelOpen")

		-- Las tarjetas entran rebotando una detras de otra.
		for index, card in self.cards do
			card.button.Rotation = 0
			Theme.popIn(card.button, (index - 1) * CARD_STAGGER_SECONDS)
		end

		self.dim.BackgroundTransparency = 1
		TweenService:Create(self.dim, Theme.tweens.fade, { BackgroundTransparency = 0.2 }):Play()
	end

	self.openChanged:fire(open)
end

function CharacterSelectView.toggle(self: CharacterSelectView): ()
	self:setOpen(not self.isOpen)
end

function CharacterSelectView.start(self: CharacterSelectView): ()
	ClientState.changed:connect(function(snapshot: Types.PlayerStatsSnapshot)
		if self.isOpen then
			self:highlight(snapshot.characterId)
		end
	end)
end

return CharacterSelectView

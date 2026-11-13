--!strict
--[[
	MenuView: la pantalla del lobby. Titulo, tu personaje, el boton de Listo y quien
	mas esta esperando.

	El menu no tapa el mundo, flota sobre el: estas parado en el lobby con tu personaje
	puesto mientras eliges, asi que el cambio de color se ve en el cuerpo y no solo en
	una tarjeta. Por eso los paneles viven en los bordes y dejan el centro libre.

	Rediseno "estilo Roblox": titulo enorme con degradado que se mece, tarjetas
	redondeadas, un boton de LISTO verde gigante que late hasta que lo apretas, y una
	tira de controles abajo para el que entra por primera vez.

	Como todas las Views: PINTA, no decide. El boton manda `SetReady` y se calla; que
	la run arranque lo decide el servidor cuando LobbyRules dice que si.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Characters = require(Shared:WaitForChild("Data"):WaitForChild("Characters"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Parent.State.ClientState)
local SoundController = require(script.Parent.Parent.Parent.Audio.SoundController)
local Theme = require(script.Parent.Parent.Theme)

local BIND_NAME = "PixelMadnessMenu"
local ROSTER_ROW_HEIGHT = 40
local MAX_ROSTER_ROWS = 4
local MARGIN = 32
local TITLE_SWAY_DEGREES = 2.5
local TITLE_BOB_PIXELS = 6
local READY_PULSE_SPEED = 3

local MenuView = {}
MenuView.__index = MenuView

type RosterRow = {
	row: Frame,
	dot: Frame,
	name: TextLabel,
	state: TextLabel,
}

export type MenuView = typeof(setmetatable(
	{} :: {
		root: Frame,
		title: TextLabel,
		titleBasePosition: UDim2,
		characterName: TextLabel,
		portraitGradient: UIGradient,
		portraitInitial: TextLabel,
		chooseButton: Theme.Button,
		cameraButton: Theme.Button,
		readyButton: Theme.Button,
		statusLabel: TextLabel,
		statusPanel: Frame,
		rosterRows: { RosterRow },
		isReady: boolean,
		isOpen: boolean,
		lastCountdown: number?,
		-- (nada) cuando el jugador pide abrir la seleccion de personaje. UIController
		-- la escucha; esta View no conoce al panel de seleccion.
		chooseRequested: Signal.Signal<>,
		-- (nada) cuando pide cambiar entre tercera y primera persona. Misma idea: esta
		-- View no conoce a la camara, solo pinta el modo que le cuentan.
		cameraToggleRequested: Signal.Signal<>,
	},
	MenuView
))

local function colorFromRgb(rgb: { r: number, g: number, b: number }): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

--[[ Tira de controles: cada tecla dibujada como tecla, con su accion al lado. ]]
local function buildControlsStrip(parent: Instance): ()
	local colors = Theme.colors
	local entries = {
		{ key = "WASD", text = "MOVER" },
		{ key = "CLICK", text = "DISPARAR" },
		{ key = "ESPACIO", text = "HABILIDAD" },
		{ key = "Q", text = "CAMBIAR ARMA" },
		{ key = "E", text = "RECOGER" },
	}

	local strip = Theme.panel({
		name = "Controls",
		parent = parent,
		size = UDim2.fromOffset(820, 46),
		position = UDim2.new(0.5, 0, 1, -MARGIN),
		anchorPoint = Vector2.new(0.5, 1),
		radius = 23,
		transparency = 0.15,
	})

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 18)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip

	for index, entry in entries do
		local item = Instance.new("Frame")
		item.Name = entry.text
		item.BackgroundTransparency = 1
		item.Size = UDim2.fromOffset(0, 30)
		item.AutomaticSize = Enum.AutomaticSize.X
		item.LayoutOrder = index
		item.Parent = strip

		local itemLayout = Instance.new("UIListLayout")
		itemLayout.FillDirection = Enum.FillDirection.Horizontal
		itemLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		itemLayout.Padding = UDim.new(0, 6)
		itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
		itemLayout.Parent = item

		local cap = Theme.keyCap(item, entry.key, UDim2.fromOffset(0, 0))
		cap.LayoutOrder = 1

		local label = Theme.label({
			name = "Action",
			parent = item,
			size = UDim2.fromOffset(0, 30),
			text = entry.text,
			textSize = 16,
			color = colors.textMuted,
		})
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = 2
	end
end

function MenuView.new(parent: Instance): MenuView
	local colors = Theme.colors
	local icons = Theme.icons

	local root = Instance.new("Frame")
	root.Name = "Menu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 15
	root.Parent = parent

	-- Titulo
	local titlePosition = UDim2.new(0.5, 0, 0, 40)

	local title = Theme.title({
		name = "Title",
		parent = root,
		size = UDim2.fromOffset(980, 104),
		position = titlePosition,
		anchorPoint = Vector2.new(0.5, 0),
		text = "PIXEL MADNESS",
		textSize = 100,
		strokeThickness = 7,
		top = colors.gold,
		bottom = colors.orangeDark,
	})

	local taglinePanel = Theme.panel({
		name = "Tagline",
		parent = root,
		size = UDim2.fromOffset(560, 40),
		position = UDim2.new(0.5, 0, 0, 150),
		anchorPoint = Vector2.new(0.5, 0),
		top = colors.pink,
		bottom = colors.pinkDark,
		radius = 20,
	})
	taglinePanel.Rotation = -2

	Theme.label({
		name = "Text",
		parent = taglinePanel,
		size = UDim2.fromScale(1, 1),
		text = "3 PISOS " .. icons.swords .. " 1 BONKARON " .. icons.skull .. " 0 PLANIFICACION",
		textSize = 20,
		alignment = Enum.TextXAlignment.Center,
	})

	-- Tarjeta del jugador, abajo a la izquierda
	local panel = Theme.panel({
		name = "PlayerPanel",
		parent = root,
		size = UDim2.fromOffset(400, 270),
		position = UDim2.new(0, MARGIN, 1, -MARGIN - 62),
		anchorPoint = Vector2.new(0, 1),
		radius = 20,
	})

	Theme.label({
		name = "PanelTitle",
		parent = panel,
		size = UDim2.fromOffset(360, 22),
		position = UDim2.fromOffset(20, 14),
		text = "TU PERSONAJE",
		textSize = 17,
		color = colors.textMuted,
	})

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Size = UDim2.fromOffset(72, 72)
	portrait.Position = UDim2.fromOffset(20, 42)
	portrait.BorderSizePixel = 0
	portrait.Parent = panel
	Theme.circle(portrait)
	Theme.outline(portrait, 4)

	local portraitGradient = Theme.gradient(portrait, colors.grey, colors.greyDark)

	local portraitInitial = Theme.label({
		name = "Initial",
		parent = portrait,
		size = UDim2.fromScale(1, 1),
		text = "?",
		textSize = 42,
		alignment = Enum.TextXAlignment.Center,
		font = Theme.titleFont,
		strokeThickness = 3,
	})

	local characterName = Theme.label({
		name = "CharacterName",
		parent = panel,
		size = UDim2.fromOffset(280, 72),
		position = UDim2.fromOffset(106, 42),
		text = "...",
		textSize = 30,
		font = Theme.titleFont,
	})
	characterName.TextWrapped = true

	local chooseButton = Theme.button({
		name = "Choose",
		parent = panel,
		size = UDim2.fromOffset(360, 54),
		position = UDim2.fromOffset(200, 156),
		text = icons.mask .. " ELEGIR PERSONAJE [C]",
		textSize = 22,
		top = colors.blue,
		bottom = colors.blueDark,
		clickSound = "panelOpen",
	})

	-- El toggle de camara vive aca y no en el HUD: durante la partida el cursor esta
	-- bloqueado girando la camara, asi que un boton en pleno combate no se puede
	-- apretar. Para eso esta la rueda del mouse, que hace lo mismo.
	local cameraButton = Theme.button({
		name = "CameraMode",
		parent = panel,
		size = UDim2.fromOffset(360, 48),
		position = UDim2.fromOffset(200, 220),
		text = icons.camera .. " CAMARA: 3RA PERSONA",
		textSize = 20,
		top = colors.purple,
		bottom = colors.purpleDark,
	})

	-- Boton de listo, abajo a la derecha y enorme: es LA accion de esta pantalla
	local readyButton = Theme.button({
		name = "Ready",
		parent = root,
		size = UDim2.fromOffset(340, 96),
		position = UDim2.new(1, -MARGIN - 170, 1, -MARGIN - 62 - 48),
		text = Theme.icons.exclaim .. "LISTO!",
		textSize = 48,
		top = colors.green,
		bottom = colors.greenDark,
		clickSound = "",
		shine = true,
	})

	local statusPanel = Theme.panel({
		name = "Status",
		parent = root,
		size = UDim2.fromOffset(340, 44),
		position = UDim2.new(1, -MARGIN, 1, -MARGIN - 62 - 112),
		anchorPoint = Vector2.new(1, 1),
		radius = 22,
		transparency = 0.1,
	})

	local statusLabel = Theme.label({
		name = "Text",
		parent = statusPanel,
		size = UDim2.fromScale(1, 1),
		text = "",
		textSize = 22,
		alignment = Enum.TextXAlignment.Center,
	})

	-- Lista de jugadores, arriba a la derecha
	local rosterPanel = Theme.panel({
		name = "Roster",
		parent = root,
		size = UDim2.fromOffset(330, 58 + ROSTER_ROW_HEIGHT * MAX_ROSTER_ROWS),
		position = UDim2.new(1, -MARGIN, 0, 210),
		anchorPoint = Vector2.new(1, 0),
		radius = 20,
	})

	Theme.label({
		name = "RosterTitle",
		parent = rosterPanel,
		size = UDim2.fromOffset(290, 24),
		position = UDim2.fromOffset(20, 14),
		text = icons.crown .. " EN LA SALA",
		textSize = 20,
		font = Theme.titleFont,
		color = colors.gold,
	})

	local rosterRows: { RosterRow } = {}

	for index = 1, MAX_ROSTER_ROWS do
		local row = Instance.new("Frame")
		row.Name = string.format("Row%d", index)
		row.Size = UDim2.fromOffset(298, ROSTER_ROW_HEIGHT - 6)
		row.Position = UDim2.fromOffset(16, 46 + (index - 1) * ROSTER_ROW_HEIGHT)
		row.BackgroundColor3 = colors.panelDeep
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Visible = false
		row.Parent = rosterPanel
		Theme.corner(row, 10)

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.Size = UDim2.fromOffset(20, 20)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = colors.grey
		dot.Parent = row
		Theme.circle(dot)
		Theme.outline(dot, 2)

		local name = Theme.label({
			name = "Name",
			parent = row,
			size = UDim2.fromOffset(170, ROSTER_ROW_HEIGHT - 6),
			position = UDim2.fromOffset(36, 0),
			text = "",
			textSize = 18,
		})
		name.TextTruncate = Enum.TextTruncate.AtEnd

		local state = Theme.label({
			name = "State",
			parent = row,
			size = UDim2.fromOffset(90, ROSTER_ROW_HEIGHT - 6),
			position = UDim2.fromOffset(200, 0),
			text = "",
			textSize = 17,
			alignment = Enum.TextXAlignment.Right,
		})

		table.insert(rosterRows, { row = row, dot = dot, name = name, state = state })
	end

	buildControlsStrip(root)

	local self = setmetatable({
		root = root,
		title = title,
		titleBasePosition = titlePosition,
		characterName = characterName,
		portraitGradient = portraitGradient,
		portraitInitial = portraitInitial,
		chooseButton = chooseButton,
		cameraButton = cameraButton,
		readyButton = readyButton,
		statusLabel = statusLabel,
		statusPanel = statusPanel,
		rosterRows = rosterRows,
		isReady = false,
		isOpen = false,
		lastCountdown = nil,
		chooseRequested = Signal.new() :: Signal.Signal<>,
		cameraToggleRequested = Signal.new() :: Signal.Signal<>,
	}, MenuView)

	chooseButton.button.Activated:Connect(function()
		self.chooseRequested:fire()
	end)

	cameraButton.button.Activated:Connect(function()
		self.cameraToggleRequested:fire()
	end)

	readyButton.button.Activated:Connect(function()
		-- El sonido depende de hacia donde va el toggle, por eso no lo pone el Theme.
		SoundController.play(if self.isReady then "unready" else "ready")

		-- Se manda lo CONTRARIO de lo que el cliente cree tener. Si el cliente y el
		-- servidor discrepan, el proximo snapshot corrige la pantalla: la verdad la
		-- tiene el servidor y esta View no lleva la cuenta por su lado.
		Remotes.event("SetReady"):FireServer({ ready = not self.isReady })
	end)

	return self
end

--------------------------------------------------------------------------------

--[[
	Redibuja el contenido. NO toca `root.Visible`: quien decide que se ve es
	`UIController.applyPhase`, y tenerlo en dos lugares ya dio un bug una vez.
]]
function MenuView.applyRunState(self: MenuView, snapshot: Types.RunStateSnapshot): ()
	local colors = Theme.colors
	local icons = Theme.icons

	self.isOpen = snapshot.phase == "Lobby"

	if not self.isOpen then
		return
	end

	local localUserId = Players.LocalPlayer.UserId
	local roster = snapshot.roster or {}

	-- Mi personaje
	local mine: Types.LobbyMember? = nil

	for _, member in roster do
		if member.userId == localUserId then
			mine = member
		end
	end

	if mine then
		self.isReady = mine.isReady

		local definition = Characters.getById(mine.characterId)

		if definition then
			local color = colorFromRgb(definition.greyboxColor)

			self.characterName.Text = string.upper(definition.displayName)
			self.characterName.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
			self.portraitInitial.Text = string.upper(string.sub(definition.displayName, 1, 1))
			Theme.setGradient(
				self.portraitGradient,
				color:Lerp(Color3.new(1, 1, 1), 0.25),
				color:Lerp(Color3.new(0, 0, 0), 0.35)
			)
		end
	end

	if self.isReady then
		self.readyButton.label.Text = icons.cross .. " CANCELAR"
		self.readyButton.label.TextSize = 36
		Theme.setButtonColors(self.readyButton, colors.orange, colors.orangeDark)
	else
		self.readyButton.label.Text = icons.exclaim .. "LISTO!"
		self.readyButton.label.TextSize = 48
		Theme.setButtonColors(self.readyButton, colors.green, colors.greenDark)
	end

	-- Estado: cuenta atras o a cuantos se espera
	local countdown = snapshot.countdownRemaining

	if countdown then
		local whole = math.max(0, math.ceil(countdown))

		self.statusLabel.Text = string.format("%s EMPIEZA EN %d...", icons.hourglass, whole)
		self.statusLabel.TextColor3 = colors.gold

		if whole ~= self.lastCountdown then
			Theme.bounce(self.statusPanel, 1.12)
		end

		self.lastCountdown = whole
	else
		local waiting = 0

		for _, member in roster do
			if not member.isReady then
				waiting += 1
			end
		end

		self.statusLabel.Text = if waiting == 0
			then icons.check .. " TODOS LISTOS"
			elseif waiting == 1 then "FALTA 1 JUGADOR"
			else string.format("FALTAN %d JUGADORES", waiting)
		self.statusLabel.TextColor3 = if waiting == 0 then colors.ready else colors.textMuted
		self.lastCountdown = nil
	end

	-- Lista
	for index, entry in self.rosterRows do
		local member = roster[index]

		if not member then
			entry.row.Visible = false
			continue
		end

		entry.row.Visible = true

		local definition = Characters.getById(member.characterId)
		local color = if definition then colorFromRgb(definition.greyboxColor) else colors.text

		entry.dot.BackgroundColor3 = color
		entry.name.Text = member.displayName
		entry.name.TextColor3 = if member.userId == localUserId then colors.gold else colors.text
		entry.state.Text = if member.isReady then icons.check .. " LISTO" else "..."
		entry.state.TextColor3 = if member.isReady then colors.ready else colors.textMuted
	end
end

--[[
	Pinta el modo de camara vigente. Lo llama UIController, que es quien habla con la
	camara: el modo tambien cambia con la rueda del mouse, asi que este boton no puede
	llevar la cuenta por su lado.
]]
function MenuView.setCameraMode(self: MenuView, isFirstPerson: boolean): ()
	self.cameraButton.label.Text = Theme.icons.camera
		.. (if isFirstPerson then " CAMARA: 1RA PERSONA" else " CAMARA: 3RA PERSONA")
end

--[[ Animaciones idle: el titulo se mece y el boton de Listo late mientras espera. ]]
function MenuView.animate(self: MenuView): ()
	if not self.root.Visible then
		return
	end

	local now = os.clock()

	self.title.Rotation = math.sin(now * 1.3) * TITLE_SWAY_DEGREES
	self.title.Position = self.titleBasePosition + UDim2.fromOffset(0, math.sin(now * 2.1) * TITLE_BOB_PIXELS)

	if not self.isReady then
		local pulse = (math.sin(now * READY_PULSE_SPEED) + 1) / 2

		self.readyButton.stroke.Color = Theme.colors.outline:Lerp(Theme.colors.text, pulse * 0.7)
	else
		self.readyButton.stroke.Color = Theme.colors.outline
	end
end

function MenuView.start(self: MenuView): ()
	ClientState.runChanged:connect(function(snapshot: Types.RunStateSnapshot)
		self:applyRunState(snapshot)
	end)

	local run = ClientState.getRun()

	if run then
		self:applyRunState(run)
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function()
		self:animate()
	end)
end

return MenuView

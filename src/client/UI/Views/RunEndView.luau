--!strict
--[[
	RunEndView: la pantalla de Victoria y la de Derrota.

	Son UNA sola View y no dos, porque son el mismo panel con distinto texto y distinto
	color. Dos archivos con el 90% del codigo repetido significan que el dia que se
	agregue "monedas depositadas al banco" (Fase 7) alguien se olvida de tocar uno.

	Lo que muestra sale entero del `RunStateSnapshot` que ya replica el servidor: hasta
	donde llegaste y cuanto juntaste. Esta View no cuenta nada por su cuenta.

	El boton manda `RequestRestart` y se calla. El servidor comprueba que la run este
	de verdad terminada antes de hacer nada.

	Rediseno "estilo Roblox": el panel entra rebotando, detras del titulo giran rayos
	de luz, en la victoria llueve confeti y cada final tiene su jingle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Parent.State.ClientState)
local SoundController = require(script.Parent.Parent.Parent.Audio.SoundController)
local Theme = require(script.Parent.Parent.Theme)

local BIND_NAME = "PixelMadnessRunEnd"
local PANEL_SIZE = Vector2.new(600, 400)
local FADE_SECONDS = 0.4
local RAY_COUNT = 12
local RAYS_DEGREES_PER_SECOND = 18
local CONFETTI_COUNT = 70
local CONFETTI_FALL_SPEED = Vector2.new(0.12, 0.32) -- fraccion de pantalla por segundo (min, max)

local RunEndView = {}
RunEndView.__index = RunEndView

type Confetti = {
	frame: Frame,
	velocity: number,
	sway: number,
	phase: number,
	spin: number,
	baseX: number,
}

export type RunEndView = typeof(setmetatable(
	{} :: {
		root: Frame,
		dim: TextButton,
		panel: Frame,
		panelGradient: UIGradient,
		rays: Frame,
		rayFrames: { Frame },
		title: TextLabel,
		titleGradient: UIGradient,
		subtitle: TextLabel,
		floorValue: TextLabel,
		coinsValue: TextLabel,
		button: Theme.Button,
		confettiLayer: Frame,
		confetti: { Confetti },
		isOpen: boolean,
		isVictory: boolean,
	},
	RunEndView
))

local function buildStatCard(parent: Instance, x: number, icon: string, caption: string): TextLabel
	local colors = Theme.colors

	local card = Theme.panel({
		name = caption,
		parent = parent,
		size = UDim2.fromOffset(220, 96),
		position = UDim2.new(0.5, x, 0, 186),
		anchorPoint = Vector2.new(0.5, 0),
		top = colors.panelLight,
		bottom = colors.panelDeep,
		radius = 16,
	})

	Theme.label({
		name = "Icon",
		parent = card,
		size = UDim2.fromOffset(60, 96),
		position = UDim2.fromOffset(8, 0),
		text = icon,
		textSize = 40,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 0,
	})

	Theme.label({
		name = "Caption",
		parent = card,
		size = UDim2.fromOffset(140, 22),
		position = UDim2.fromOffset(70, 14),
		text = caption,
		textSize = 16,
		color = colors.textMuted,
	})

	return Theme.title({
		name = "Value",
		parent = card,
		size = UDim2.fromOffset(140, 46),
		position = UDim2.fromOffset(70, 38),
		text = "",
		textSize = 40,
		strokeThickness = 3,
		alignment = Enum.TextXAlignment.Left,
	})
end

function RunEndView.new(parent: Instance): RunEndView
	local colors = Theme.colors
	local icons = Theme.icons

	local root = Instance.new("Frame")
	root.Name = "RunEnd"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 30
	root.Parent = parent

	-- Fondo como boton: se come los clicks para que celebrar la victoria no dispare el
	-- arma que quedo debajo del panel.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = colors.screenDim
	dim.BackgroundTransparency = 0.25
	dim.BorderSizePixel = 0
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Parent = root

	-- Rayos de luz: rectangulos finos rotados alrededor del centro, dentro de un
	-- contenedor que gira. Sin imagenes, sin assets.
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.Size = UDim2.fromOffset(1400, 1400)
	rays.Position = UDim2.new(0.5, 0, 0.5, -60)
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.BackgroundTransparency = 1
	rays.Parent = root

	local rayFrames: { Frame } = {}

	for index = 1, RAY_COUNT do
		local ray = Instance.new("Frame")
		ray.Name = string.format("Ray%d", index)
		ray.Size = UDim2.new(0, 110, 1, 0)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Rotation = (index - 1) * (180 / RAY_COUNT)
		ray.BackgroundColor3 = colors.gold
		ray.BorderSizePixel = 0
		ray.Parent = rays

		-- Cada rayo se desvanece hacia las puntas: luz que sale del centro.
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray

		table.insert(rayFrames, ray)
	end

	local confettiLayer = Instance.new("Frame")
	confettiLayer.Name = "Confetti"
	confettiLayer.Size = UDim2.fromScale(1, 1)
	confettiLayer.BackgroundTransparency = 1
	confettiLayer.ZIndex = 5
	confettiLayer.Parent = root

	local panel = Theme.panel({
		name = "Panel",
		parent = root,
		size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		radius = 28,
		strokeThickness = 5,
	})

	local panelGradient = panel:FindFirstChildOfClass("UIGradient") :: UIGradient

	local title = Theme.title({
		name = "Title",
		parent = panel,
		size = UDim2.new(1, -40, 0, 96),
		position = UDim2.new(0.5, 0, 0, -40),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		textSize = 92,
		strokeThickness = 7,
	})

	title.TextScaled = true

	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 92
	titleLimit.Parent = title

	local subtitle = Theme.label({
		name = "Subtitle",
		parent = panel,
		size = UDim2.new(1, -40, 0, 30),
		position = UDim2.fromOffset(20, 100),
		text = "",
		textSize = 22,
		alignment = Enum.TextXAlignment.Center,
	})
	subtitle.TextWrapped = true

	local floorValue = buildStatCard(panel, -120, icons.castle, "PISO")
	local coinsValue = buildStatCard(panel, 120, icons.coin, "MONEDAS")

	local button = Theme.button({
		name = "Restart",
		parent = panel,
		size = UDim2.fromOffset(380, 76),
		position = UDim2.new(0.5, 0, 1, -62),
		-- Va al LOBBY y no directo a otra run: ahi se puede cambiar de personaje antes
		-- de volver a entrar, que es la mitad de la gracia de haber perdido.
		text = icons.home .. " VOLVER AL LOBBY",
		textSize = 34,
		top = colors.green,
		bottom = colors.greenDark,
		shine = true,
	})

	local self = setmetatable({
		root = root,
		dim = dim,
		panel = panel,
		panelGradient = panelGradient,
		rays = rays,
		rayFrames = rayFrames,
		title = title,
		titleGradient = title:FindFirstChildOfClass("UIGradient") :: UIGradient,
		subtitle = subtitle,
		floorValue = floorValue,
		coinsValue = coinsValue,
		button = button,
		confettiLayer = confettiLayer,
		confetti = {},
		isOpen = false,
		isVictory = false,
	}, RunEndView)

	button.button.Activated:Connect(function()
		-- Se apaga en el acto para que nadie lo apriete tres veces mientras el servidor
		-- genera el lobby. El servidor igual descarta las repeticiones.
		button.label.Text = "..."
		Remotes.event("RequestRestart"):FireServer()
	end)

	return self
end

--------------------------------------------------------------------------------

local CONFETTI_COLORS = {
	Theme.colors.gold,
	Theme.colors.pink,
	Theme.colors.blue,
	Theme.colors.green,
	Theme.colors.purple,
	Theme.colors.orange,
}

function RunEndView.spawnConfetti(self: RunEndView): ()
	self:clearConfetti()

	for _ = 1, CONFETTI_COUNT do
		local frame = Instance.new("Frame")
		frame.Name = "Piece"
		frame.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22))
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		frame.BorderSizePixel = 0
		frame.ZIndex = 5
		frame.Parent = self.confettiLayer
		Theme.corner(frame, 3)

		local baseX = math.random()

		frame.Position = UDim2.fromScale(baseX, -math.random() * 1.2)

		table.insert(self.confetti, {
			frame = frame,
			velocity = CONFETTI_FALL_SPEED.X + math.random() * (CONFETTI_FALL_SPEED.Y - CONFETTI_FALL_SPEED.X),
			sway = 0.01 + math.random() * 0.03,
			phase = math.random() * math.pi * 2,
			spin = (math.random() * 2 - 1) * 360,
			baseX = baseX,
		})
	end
end

function RunEndView.clearConfetti(self: RunEndView): ()
	for _, piece in self.confetti do
		piece.frame:Destroy()
	end

	table.clear(self.confetti)
end

function RunEndView.update(self: RunEndView, deltaTime: number): ()
	if not self.isOpen then
		return
	end

	self.rays.Rotation = (self.rays.Rotation + RAYS_DEGREES_PER_SECOND * deltaTime) % 360

	local now = os.clock()

	for _, piece in self.confetti do
		local position = piece.frame.Position
		local y = position.Y.Scale + piece.velocity * deltaTime

		-- Al salir por abajo vuelve a entrar por arriba: lluvia continua mientras el
		-- panel este abierto, con un costo fijo de Frames.
		if y > 1.1 then
			y = -0.1
		end

		piece.frame.Position = UDim2.fromScale(piece.baseX + math.sin(now * 2 + piece.phase) * piece.sway, y)
		piece.frame.Rotation += piece.spin * deltaTime
	end
end

function RunEndView.applyRunState(self: RunEndView, snapshot: Types.RunStateSnapshot): ()
	local colors = Theme.colors
	local icons = Theme.icons
	local shouldOpen = snapshot.phase == "Victory" or snapshot.phase == "Defeat"

	if not shouldOpen then
		if self.isOpen then
			self.isOpen = false
			self.root.Visible = false
			self:clearConfetti()
		end

		return
	end

	local isVictory = snapshot.phase == "Victory"

	self.isVictory = isVictory

	if isVictory then
		self.title.Text = icons.trophy .. " VICTORIA " .. icons.trophy
		Theme.setGradient(self.titleGradient, colors.gold, colors.orangeDark)
		Theme.setGradient(self.panelGradient, Color3.fromRGB(96, 70, 170), Color3.fromRGB(44, 30, 92))
		self.subtitle.Text = "EL BONKARON NO VOLVERA A BONKEAR A NADIE"

		for _, ray in self.rayFrames do
			ray.BackgroundColor3 = colors.gold
		end
	else
		self.title.Text = icons.skull .. " DERROTA " .. icons.skull
		Theme.setGradient(self.titleGradient, colors.red, colors.redDark)
		Theme.setGradient(self.panelGradient, Color3.fromRGB(110, 40, 70), Color3.fromRGB(46, 16, 36))
		self.subtitle.Text = "LA MAZMORRA SIGUE INVICTA... POR AHORA"

		for _, ray in self.rayFrames do
			ray.BackgroundColor3 = colors.red
		end
	end

	self.floorValue.Text = string.format("%d / %d", snapshot.floorNumber, snapshot.floorsPerRun)
	self.coinsValue.Text = tostring(snapshot.sharedCoins)
	self.button.label.Text = icons.home .. " VOLVER AL LOBBY"

	if self.isOpen then
		return
	end

	self.isOpen = true
	self.root.Visible = true

	SoundController.play(if isVictory then "victory" else "defeat")

	-- Aparece con fundido y rebote en vez de de golpe: el corte seco compite con la
	-- muerte del personaje, que esta pasando en el mismo instante.
	self.dim.BackgroundTransparency = 1
	TweenService:Create(self.dim, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 0.25 }):Play()
	Theme.popIn(self.panel, 0.1)
	Theme.popIn(self.rays, 0.05)

	if isVictory then
		self:spawnConfetti()
	else
		self:clearConfetti()
	end
end

function RunEndView.start(self: RunEndView): ()
	ClientState.runChanged:connect(function(snapshot: Types.RunStateSnapshot)
		self:applyRunState(snapshot)
	end)

	local run = ClientState.getRun()

	if run then
		self:applyRunState(run)
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, function(deltaTime: number)
		self:update(deltaTime)
	end)
end

return RunEndView

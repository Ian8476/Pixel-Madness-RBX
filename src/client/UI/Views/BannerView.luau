--!strict
--[[
	BannerView: los anuncios grandes en el centro de la pantalla.

	"3, 2, 1", "A LA MAZMORRA", "PISO 2", "PELEA", "SALA DESPEJADA", "JEFE". Son el
	pulso de la run: cada uno marca una transicion que antes pasaba en silencio y el
	jugador solo notaba despues (las puertas ya estaban cerradas, el piso ya era otro).

	Como todas las Views: PINTA, no decide. Escucha transiciones de estado que ya
	existen (ClientState, CombatFeedback, el tag Boss) y las anuncia. Escucha
	TRANSICIONES y no estados por la misma razon documentada en LobbyService: un estado
	que se repite en dos snapshots seguidos no tiene que anunciarse dos veces.

	Un solo anuncio a la vez: uno nuevo pisa al anterior. Dos carteles apilados en el
	centro de la pantalla no se leen, y el mas nuevo siempre es el mas relevante.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared:WaitForChild("Tags"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.Parent.State.ClientState)
local CombatFeedback = require(script.Parent.Parent.Parent.FX.CombatFeedback)
local SoundController = require(script.Parent.Parent.Parent.Audio.SoundController)
local Theme = require(script.Parent.Parent.Theme)

local DEFAULT_DURATION_SECONDS = 1.6
local COUNTDOWN_DURATION_SECONDS = 0.85
local EXIT_SECONDS = 0.3

local BannerView = {}
BannerView.__index = BannerView

export type BannerView = typeof(setmetatable(
	{} :: {
		root: Frame,
		holder: Frame,
		title: TextLabel,
		titleGradient: UIGradient,
		titleStroke: UIStroke,
		subtitle: TextLabel,
		subtitleStroke: UIStroke,
		token: number,
		lastPhase: Types.RunPhase?,
		lastFloor: number,
		lastCountdown: number?,
	},
	BannerView
))

function BannerView.new(parent: Instance): BannerView
	local root = Instance.new("Frame")
	root.Name = "Banners"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = 25
	root.Parent = parent

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.Size = UDim2.fromOffset(900, 170)
	holder.Position = UDim2.fromScale(0.5, 0.34)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = root

	local title = Theme.title({
		name = "Title",
		parent = holder,
		size = UDim2.new(1, 0, 0, 110),
		text = "",
		textSize = 96,
		strokeThickness = 6,
	})

	-- Los textos largos ("SALA DESPEJADA") se achican solos en vez de salirse.
	title.TextScaled = true

	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 96
	sizeLimit.Parent = title

	local subtitle = Theme.label({
		name = "Subtitle",
		parent = holder,
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 112),
		text = "",
		textSize = 30,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 3,
	})

	return setmetatable({
		root = root,
		holder = holder,
		title = title,
		titleGradient = title:FindFirstChildOfClass("UIGradient") :: UIGradient,
		titleStroke = title:FindFirstChildOfClass("UIStroke") :: UIStroke,
		subtitle = subtitle,
		subtitleStroke = subtitle:FindFirstChildOfClass("UIStroke") :: UIStroke,
		token = 0,
		lastPhase = nil,
		lastFloor = 0,
		lastCountdown = nil,
	}, BannerView)
end

local function setTransparency(self: BannerView, value: number): ()
	self.title.TextTransparency = value
	self.titleStroke.Transparency = value
	self.subtitle.TextTransparency = value
	self.subtitleStroke.Transparency = value
end

--[[
	Muestra un anuncio. Entra con un rebote y un giro chico, se queda `duration`
	segundos y sale achicandose y desvaneciendose.
]]
function BannerView.show(
	self: BannerView,
	text: string,
	top: Color3,
	bottom: Color3,
	subtitle: string?,
	duration: number?
): ()
	self.token += 1

	local token = self.token
	local holder = self.holder
	local scale = Theme.scaleOf(holder)

	self.title.Text = text
	self.subtitle.Text = subtitle or ""
	Theme.setGradient(self.titleGradient, top, bottom)
	setTransparency(self, 0)

	holder.Visible = true
	holder.Rotation = -6
	scale.Scale = 0.2

	local enter = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	TweenService:Create(scale, enter, { Scale = 1 }):Play()
	TweenService:Create(holder, enter, { Rotation = 0 }):Play()

	task.delay(duration or DEFAULT_DURATION_SECONDS, function()
		if self.token ~= token then
			return
		end

		local exit = TweenInfo.new(EXIT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		TweenService:Create(scale, exit, { Scale = 1.25 }):Play()

		for _, target in { self.title, self.subtitle } do
			TweenService:Create(target, exit, { TextTransparency = 1 }):Play()
		end

		for _, stroke in { self.titleStroke, self.subtitleStroke } do
			TweenService:Create(stroke, exit, { Transparency = 1 }):Play()
		end

		task.delay(EXIT_SECONDS, function()
			if self.token == token then
				holder.Visible = false
			end
		end)
	end)
end

--------------------------------------------------------------------------------

function BannerView.applyRunState(self: BannerView, snapshot: Types.RunStateSnapshot): ()
	local colors = Theme.colors
	local icons = Theme.icons
	local previousPhase = self.lastPhase

	self.lastPhase = snapshot.phase

	-- Cuenta atras del lobby: un numero gigante por segundo.
	if snapshot.phase == "Lobby" then
		local countdown = snapshot.countdownRemaining
		local whole = if countdown then math.ceil(countdown) else nil

		if whole and whole > 0 and whole ~= self.lastCountdown then
			-- Cada segundo suena un poco mas agudo: la tension sube sola.
			SoundController.play("countdown", 1 + (5 - math.min(whole, 5)) * 0.08)
			self:show(tostring(whole), colors.gold, colors.goldDark, "PREPARATE", COUNTDOWN_DURATION_SECONDS)
		end

		self.lastCountdown = whole
		self.lastFloor = 0

		return
	end

	self.lastCountdown = nil

	if snapshot.phase ~= "InRun" then
		return
	end

	if previousPhase ~= "InRun" then
		SoundController.play("runStart")
		self:show(icons.exclaim .. "A LA MAZMORRA!", colors.orange, colors.redDark, "PISO 1", 2)
	elseif snapshot.floorNumber > self.lastFloor and self.lastFloor > 0 then
		SoundController.play("floorUp")
		self:show(
			string.format("PISO %d", snapshot.floorNumber),
			colors.purple,
			colors.purpleDark,
			if snapshot.floorNumber >= snapshot.floorsPerRun
				then icons.skull .. " EL JEFE TE ESPERA " .. icons.skull
				else "CADA VEZ MAS DIFICIL",
			2
		)
	end

	self.lastFloor = snapshot.floorNumber
end

function BannerView.start(self: BannerView): ()
	local colors = Theme.colors
	local icons = Theme.icons

	ClientState.runChanged:connect(function(snapshot: Types.RunStateSnapshot)
		self:applyRunState(snapshot)
	end)

	CombatFeedback.roomLockChanged:connect(function(locked: boolean)
		if self.lastPhase ~= "InRun" then
			return
		end

		if locked then
			self:show(icons.exclaim .. "PELEA!", colors.red, colors.redDark, icons.swords .. " ACABA CON TODOS " .. icons.swords, 1.3)
		else
			self:show(icons.exclaim .. "SALA DESPEJADA!", colors.green, colors.greenDark, "SEGUI EXPLORANDO", 1.4)
		end
	end)

	CollectionService:GetInstanceAddedSignal(Tags.Boss):Connect(function(boss: Instance)
		local displayName = boss:GetAttribute("DisplayName")

		SoundController.play("bossAppear")
		self:show(
			icons.warning .. " JEFE " .. icons.warning,
			colors.purple,
			colors.redDark,
			if typeof(displayName) == "string" then displayName else string.upper(boss.Name),
			2.2
		)
	end)

	local run = ClientState.getRun()

	if run then
		-- Sincroniza sin anunciar: entrar a mitad de una run no es "empezo la run".
		self.lastPhase = run.phase
		self.lastFloor = run.floorNumber
	end
end

return BannerView

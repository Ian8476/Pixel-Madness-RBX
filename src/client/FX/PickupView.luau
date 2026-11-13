--!strict
--[[
	PickupView: el cartelito y el flotar de las armas en el suelo.

	Todo esto es DECORADO y por eso vive en el cliente: el servidor no gasta un frame
	de Heartbeat en hacer girar un arma, y girarla en el servidor ademas la replicaria
	a todos los clientes 60 veces por segundo para nada.

	Que se puede mover una Part anclada que creo el servidor: si, localmente. El cambio
	no se replica (justamente lo que queremos) y el servidor sigue teniendo la posicion
	"real" del pickup para validar la distancia del PickupRequest. El giro es mentira
	visual, la posicion base no cambia.

	Un solo RenderStepped para TODOS los pickups, no un bucle por objeto: es la misma
	regla que en el servidor con las balas y los enemigos.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared:WaitForChild("Tags"))
local Weapons = require(Shared:WaitForChild("Data"):WaitForChild("Weapons"))

local BIND_NAME = "PixelMadnessPickupView"
local WEAPON_ID_ATTRIBUTE = "WeaponId"

local SPIN_DEGREES_PER_SECOND = 90
local HOVER_AMPLITUDE_STUDS = 0.35
local HOVER_CYCLES_PER_SECOND = 1.2
local LABEL_HEIGHT_STUDS = 2.6

type Tracked = {
	part: BasePart,
	basePosition: Vector3,
	label: TextLabel,
	phase: number, -- desfase para que no floten todos al unisono
}

local PickupView = {
	name = "PickupView",
}

local tracked: { [Instance]: Tracked } = {}
local elapsed = 0

local function createLabel(part: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PickupLabel"
	billboard.Size = UDim2.fromScale(8, 1.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT_STUDS, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60

	-- Pastilla dorada redondeada con texto gordo: el mismo idioma visual que la UI
	-- (ver Theme). No se usa Theme directamente porque esto es un BillboardGui en el
	-- mundo y se mide en escala, no en pixeles.
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.05
	pill.BorderSizePixel = 0
	pill.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 214, 51), Color3.fromRGB(255, 140, 0))
	gradient.Rotation = 90
	gradient.Parent = pill

	local border = Instance.new("UIStroke")
	border.Thickness = 3
	border.Color = Color3.fromRGB(18, 10, 36)
	border.Parent = pill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.04, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = ""
	label.Parent = pill

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2
	textStroke.Color = Color3.fromRGB(18, 10, 36)
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = label

	billboard.Parent = part

	return label
end

local function refreshLabel(entry: Tracked): ()
	local weapon = Weapons.getById(entry.part:GetAttribute(WEAPON_ID_ATTRIBUTE) :: any)

	entry.label.Text = if weapon then string.format("[E] %s", string.upper(weapon.displayName)) else "[E]"
end

local function track(pickup: Instance): ()
	if tracked[pickup] then
		return
	end

	if not pickup:IsA("BasePart") then
		-- Los pickups tipo Model llegan en la Fase 3 con los prefabs de sala; cuando
		-- existan, esto pasa a buscar su PrimaryPart.
		return
	end

	local entry: Tracked = {
		part = pickup,
		basePosition = pickup.Position,
		label = createLabel(pickup),
		phase = math.random() * math.pi * 2,
	}

	tracked[pickup] = entry

	refreshLabel(entry)

	-- El servidor puede resolver el arma al azar DESPUES de que el tag llegue al
	-- cliente: el atributo aparece un instante mas tarde y el cartel se corrige solo.
	pickup:GetAttributeChangedSignal(WEAPON_ID_ATTRIBUTE):Connect(function()
		refreshLabel(entry)
	end)
end

local function untrack(pickup: Instance): ()
	tracked[pickup] = nil
end

local function update(deltaTime: number): ()
	elapsed += deltaTime

	for instance, entry in tracked do
		if not entry.part.Parent then
			tracked[instance] = nil
			continue
		end

		local height = math.sin((elapsed * HOVER_CYCLES_PER_SECOND * math.pi * 2) + entry.phase)
			* HOVER_AMPLITUDE_STUDS

		entry.part.CFrame = CFrame.new(entry.basePosition + Vector3.new(0, height, 0))
			* CFrame.Angles(0, math.rad(elapsed * SPIN_DEGREES_PER_SECOND), 0)
	end
end

function PickupView.start(): ()
	for _, pickup in CollectionService:GetTagged(Tags.WeaponPickup) do
		track(pickup)
	end

	CollectionService:GetInstanceAddedSignal(Tags.WeaponPickup):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tags.WeaponPickup):Connect(untrack)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, update)
end

return PickupView

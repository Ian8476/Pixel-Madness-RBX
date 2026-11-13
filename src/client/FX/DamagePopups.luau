--!strict
--[[
	DamagePopups: los numerotes de dano. Marca de la casa del juego.

	El servidor no sabe que esto existe: emite `DamageDealt` (unreliable) con posicion
	y cantidad, y cada cliente decide como pintarlo (reglas 2 y 5). Que el remote sea
	unreliable es intencional: si se pierde un paquete se pierde un numero flotante,
	no un estado. A cambio no bloquea la cola ordenada de los remotes que si importan.

	Detalle de game feel heredado del prototipo Unity: a partir de 30 de dano el numero
	crece 1.8x y se pone naranja. Es informacion, no decoracion - te dice de un vistazo
	que el arma que acabas de recoger pega distinto.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local POPUP_LIFETIME_SECONDS = 0.7
local RISE_STUDS = 6
local HORIZONTAL_SCATTER_STUDS = 1.5
local POP_IN_SECONDS = 0.12
local POP_OVERSHOOT = 1.35
-- Degradados de los numeros (claro arriba, oscuro abajo), como los titulos de la UI.
local NORMAL_TOP = Color3.fromRGB(255, 255, 255)
local NORMAL_BOTTOM = Color3.fromRGB(255, 226, 120)
local BIG_TOP = Color3.fromRGB(255, 214, 51)
local BIG_BOTTOM = Color3.fromRGB(255, 70, 40)
local OUTLINE = Color3.fromRGB(18, 10, 36)

local DamagePopups = {
	name = "DamagePopups",
}

local container: Folder? = nil

local function getContainer(): Folder
	if container then
		return container
	end

	local folder = Instance.new("Folder")
	folder.Name = "DamagePopups"
	-- Solo existe en este cliente: nada de esto se replica ni molesta al servidor.
	folder.Parent = workspace

	container = folder

	return folder
end

local function spawnPopup(position: Vector3, amount: number): ()
	local isBig = amount >= Constants.BIG_DAMAGE_THRESHOLD
	local scale = if isBig then Constants.BIG_DAMAGE_POPUP_SCALE else 1

	-- Un ancla invisible es mas barato que un Attachment con adornee dinamico, y
	-- permite moverla con un Tween en vez de recalcular offsets cada frame.
	local anchor = Instance.new("Part")
	anchor.Name = "PopupAnchor"
	anchor.Size = Vector3.one * 0.1
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = position

	local finalSize = UDim2.fromScale(4 * scale, 2 * scale)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(0.1, 0.1)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy -- la fuente de titulos de la UI (ver Theme)
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = if isBig then tostring(math.round(amount)) .. "!" else tostring(math.round(amount))
	label.Rotation = if isBig then (math.random() * 2 - 1) * 12 else 0
	label.Parent = billboard

	local gradient = Instance.new("UIGradient")
	gradient.Color = if isBig
		then ColorSequence.new(BIG_TOP, BIG_BOTTOM)
		else ColorSequence.new(NORMAL_TOP, NORMAL_BOTTOM)
	gradient.Rotation = 90
	gradient.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = if isBig then 3 else 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label

	anchor.Parent = getContainer()

	-- Dispersion horizontal para que varias balas seguidas no apilen numeros ilegibles
	local scatter = Vector3.new(
		(math.random() - 0.5) * 2 * HORIZONTAL_SCATTER_STUDS,
		RISE_STUDS,
		(math.random() - 0.5) * 2 * HORIZONTAL_SCATTER_STUDS
	)

	local tweenInfo = TweenInfo.new(POPUP_LIFETIME_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Entrada con sobrepaso ("pop") y despues sube desvaneciendose.
	TweenService:Create(billboard, TweenInfo.new(POP_IN_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(finalSize.X.Scale * POP_OVERSHOOT, finalSize.Y.Scale * POP_OVERSHOOT),
	}):Play()

	task.delay(POP_IN_SECONDS, function()
		TweenService:Create(billboard, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Size = finalSize }):Play()
	end)

	TweenService:Create(anchor, tweenInfo, { Position = position + scatter }):Play()

	local fadeInfo = TweenInfo.new(
		POPUP_LIFETIME_SECONDS * 0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		POPUP_LIFETIME_SECONDS * 0.5
	)

	TweenService:Create(label, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fadeInfo, { Transparency = 1 }):Play()

	Debris:AddItem(anchor, POPUP_LIFETIME_SECONDS)
end

function DamagePopups.start(): ()
	Remotes.unreliable("DamageDealt").OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end

		local position = (payload :: any).position
		local amount = (payload :: any).amount

		if typeof(position) ~= "Vector3" or typeof(amount) ~= "number" then
			return
		end

		spawnPopup(position, amount)
	end)
end

return DamagePopups

--!strict
--[[
	Theme: la identidad visual del juego, en un solo archivo.

	Ninguna View escribe un color, un grosor de borde ni una fuente a mano. El motivo
	es el mismo por el que existe `Tags.luau`: cuando cada pantalla elige su propio
	rojo, tres meses despues hay cinco rojos parecidos y cambiar "el rojo del juego"
	es una caceria. Aca hay uno.

	--------------------------------------------------------------------------------
	EL LOOK (rediseno "estilo Roblox popular")
	--------------------------------------------------------------------------------

	La primera version era pixel-art sobria: sin esquinas redondeadas, fuente Arcade,
	paneles grises. Se leia bien pero no invitaba a jugar. Este rediseno copia el
	idioma visual que los jugadores de Roblox ya conocen de los juegos mas populares:

	1. ESQUINAS REDONDEADAS Y CONTORNO OSCURO GRUESO. El contorno sigue siendo la
	   regla que sostiene la lectura sobre una mazmorra oscura con niebla; ahora ademas
	   es "caricatura", no "retro".

	2. DEGRADADOS SATURADOS. Cada boton y cada barra es un degradado vertical de un
	   color claro a uno oscuro del mismo tono. Es lo que da volumen sin texturas.

	3. TEXTO GORDO CON CONTORNO. Fuentes redondas (Luckiest Guy para titulos, Fredoka
	   One para todo lo demas) con `UIStroke` oscuro: se lee sobre cualquier fondo.

	4. TODO REACCIONA. Los botones crecen al pasar el mouse, se aplastan al apretarlos
	   y suenan. Los numeros que cambian rebotan. Nada aparece "de golpe".

	5. LA UI SIGUE SIENDO INFORMACION. Mas color no significa mas cosas en pantalla:
	   el HUD muestra lo mismo que antes, solo que mas facil de leer de reojo.

	--------------------------------------------------------------------------------

	Sobre los iconos: son emoji (Roblox los dibuja a color con su fuente de respaldo)
	escritos con escapes `\u{...}` para que el codigo fuente siga siendo ASCII puro y
	ningun script de sincronizacion pueda romper el encoding.

	Sobre la escala: todo se mide en PIXELES (offset) y despues se multiplica por un
	`UIScale` global. `Theme.applyViewportScale` calcula ese factor.
]]

local TweenService = game:GetService("TweenService")

local SoundController = require(script.Parent.Parent.Audio.SoundController)

local COLORS = table.freeze({
	-- Fondos: violeta profundo, el color "de noche" de los juegos de Roblox
	panel = Color3.fromRGB(38, 30, 72),
	panelTop = Color3.fromRGB(76, 62, 140),
	panelLight = Color3.fromRGB(64, 52, 118),
	panelDeep = Color3.fromRGB(24, 18, 48),
	outline = Color3.fromRGB(18, 10, 36),
	screenDim = Color3.fromRGB(12, 6, 28),

	-- Texto
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(196, 186, 240),

	-- Recursos
	health = Color3.fromRGB(255, 82, 120),
	healthDark = Color3.fromRGB(196, 24, 72),
	healthGhost = Color3.fromRGB(255, 236, 160), -- el mordisco del golpe, en amarillo claro
	energy = Color3.fromRGB(84, 214, 255),
	energyDark = Color3.fromRGB(28, 112, 232),
	energyGhost = Color3.fromRGB(210, 245, 255),

	-- Acentos (siempre de a pares: claro arriba, oscuro abajo)
	gold = Color3.fromRGB(255, 214, 51),
	goldDark = Color3.fromRGB(255, 140, 0),
	green = Color3.fromRGB(110, 240, 90),
	greenDark = Color3.fromRGB(24, 170, 60),
	blue = Color3.fromRGB(80, 180, 255),
	blueDark = Color3.fromRGB(36, 92, 230),
	purple = Color3.fromRGB(200, 120, 255),
	purpleDark = Color3.fromRGB(116, 44, 220),
	red = Color3.fromRGB(255, 92, 92),
	redDark = Color3.fromRGB(200, 28, 52),
	orange = Color3.fromRGB(255, 170, 60),
	orangeDark = Color3.fromRGB(235, 90, 20),
	pink = Color3.fromRGB(255, 120, 200),
	pinkDark = Color3.fromRGB(210, 40, 140),
	grey = Color3.fromRGB(150, 146, 170),
	greyDark = Color3.fromRGB(88, 84, 110),

	-- Alias semanticos (las Views piden "danger", no "red")
	danger = Color3.fromRGB(255, 92, 92),
	ready = Color3.fromRGB(110, 240, 90),
	portal = Color3.fromRGB(200, 120, 255),
})

-- Emoji como escapes: ver la nota del encabezado.
local ICONS = table.freeze({
	heart = "\u{2764}\u{FE0F}",
	bolt = "\u{26A1}",
	coin = "\u{1F4B0}", -- bolsa de dinero: la moneda (U+1FA99) es muy nueva y Roblox no la dibuja
	skull = "\u{1F480}",
	gun = "\u{1F52B}",
	star = "\u{2B50}",
	sparkles = "\u{2728}",
	dash = "\u{1F4A8}",
	fire = "\u{1F525}",
	swords = "\u{2694}\u{FE0F}",
	castle = "\u{1F3F0}",
	trophy = "\u{1F3C6}",
	home = "\u{1F3E0}",
	camera = "\u{1F3A5}",
	mask = "\u{1F3AD}",
	check = "\u{2714}\u{FE0F}",
	cross = "\u{2716}\u{FE0F}",
	warning = "\u{26A0}\u{FE0F}",
	hourglass = "\u{23F3}",
	crown = "\u{1F451}",
	runner = "\u{1F3C3}",
	shield = "\u{1F6E1}\u{FE0F}",
	boom = "\u{1F4A5}",
	exclaim = "\u{A1}", -- signo de apertura de exclamacion
})

local Theme = {}

Theme.colors = COLORS
Theme.icons = ICONS
Theme.titleFont = Enum.Font.LuckiestGuy
Theme.font = Enum.Font.FredokaOne
Theme.outlineThickness = 3
Theme.cornerRadius = 12

-- Animaciones compartidas
Theme.tweens = table.freeze({
	hover = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fade = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
})

local HOVER_SCALE = 1.06
local PRESS_SCALE = 0.92
local SHINE_PERIOD_SECONDS = 3.2

--------------------------------------------------------------------------------
-- Piezas sueltas
--------------------------------------------------------------------------------

--[[ Esquinas redondeadas. `radius` en pixeles; `1` como escala da un circulo. ]]
function Theme.corner(instance: GuiObject, radius: number?): UICorner
	local corner = Instance.new("UICorner")

	corner.CornerRadius = UDim.new(0, radius or Theme.cornerRadius)
	corner.Parent = instance

	return corner
end

function Theme.circle(instance: GuiObject): UICorner
	local corner = Instance.new("UICorner")

	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = instance

	return corner
end

--[[ Contorno grueso del borde de un Frame o boton. ]]
function Theme.outline(instance: GuiObject, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")

	stroke.Thickness = thickness or Theme.outlineThickness
	stroke.Color = color or COLORS.outline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = instance

	return stroke
end

--[[ Contorno del TEXTO (no del recuadro). Es la marca registrada del look Roblox. ]]
function Theme.textOutline(label: TextLabel | TextButton, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")

	stroke.Thickness = thickness or 2.5
	stroke.Color = color or COLORS.outline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	return stroke
end

--[[
	Degradado vertical de `top` a `bottom`. Para que se vea el color real, el fondo de
	la instancia tiene que ser blanco: el degradado MULTIPLICA el color de fondo.
]]
function Theme.gradient(instance: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")

	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = instance

	-- En un TextLabel el degradado es para las LETRAS (titulos); el fondo no importa.
	if not instance:IsA("TextLabel") then
		instance.BackgroundColor3 = Color3.new(1, 1, 1)
	end

	return gradient
end

function Theme.setGradient(gradient: UIGradient, top: Color3, bottom: Color3): ()
	gradient.Color = ColorSequence.new(top, bottom)
end

--[[ El UIScale de una instancia, creandolo si no existe. Lo usan todas las animaciones. ]]
function Theme.scaleOf(instance: GuiObject): UIScale
	local existing = instance:FindFirstChildOfClass("UIScale")

	if existing then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Parent = instance

	return scale
end

--[[ Rebote: crece hasta `peak` y vuelve a 1. Para numeros que cambian e iconos. ]]
function Theme.bounce(instance: GuiObject, peak: number?): ()
	local scale = Theme.scaleOf(instance)

	scale.Scale = peak or 1.25
	TweenService:Create(scale, Theme.tweens.pop, { Scale = 1 }):Play()
end

--[[ Aparicion: de 0 a 1 con sobrepaso. Para paneles que se abren. ]]
function Theme.popIn(instance: GuiObject, delaySeconds: number?): ()
	local scale = Theme.scaleOf(instance)

	scale.Scale = 0

	local info = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delaySeconds or 0)

	TweenService:Create(scale, info, { Scale = 1 }):Play()
end

--[[
	Brillo que barre el elemento cada tantos segundos. Un detalle chico que hace que un
	boton importante "llame" sin parpadear ni molestar.
]]
function Theme.shine(instance: GuiObject): ()
	local sweep = Instance.new("Frame")

	sweep.Name = "Shine"
	sweep.Size = UDim2.fromScale(1, 1)
	sweep.BackgroundColor3 = Color3.new(1, 1, 1)
	sweep.BackgroundTransparency = 0
	sweep.BorderSizePixel = 0
	sweep.ZIndex = instance.ZIndex + 2
	sweep.Parent = instance

	local corner = instance:FindFirstChildOfClass("UICorner")

	if corner then
		Theme.corner(sweep, corner.CornerRadius.Offset)
	end

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = sweep

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, SHINE_PERIOD_SECONDS)

	TweenService:Create(gradient, info, { Offset = Vector2.new(1, 0) }):Play()
end

--------------------------------------------------------------------------------
-- Paneles y texto
--------------------------------------------------------------------------------

export type PanelConfig = {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	top: Color3?,
	bottom: Color3?,
	transparency: number?,
	radius: number?,
	outlined: boolean?,
	strokeThickness: number?,
}

--[[ Tarjeta redondeada con degradado y contorno. La pieza base de todos los paneles. ]]
function Theme.panel(config: PanelConfig): Frame
	local frame = Instance.new("Frame")

	frame.Name = config.name
	frame.Size = config.size
	frame.Position = config.position
	frame.AnchorPoint = config.anchorPoint or Vector2.zero
	frame.BackgroundTransparency = config.transparency or 0.05
	frame.BorderSizePixel = 0
	frame.Parent = config.parent

	Theme.corner(frame, config.radius)
	Theme.gradient(frame, config.top or COLORS.panelTop, config.bottom or COLORS.panel)

	if config.outlined ~= false then
		Theme.outline(frame, config.strokeThickness)
	end

	return frame
end

export type LabelConfig = {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
	text: string,
	textSize: number,
	color: Color3?,
	alignment: Enum.TextXAlignment?,
	font: Enum.Font?,
	strokeThickness: number?,
}

--[[ Texto gordo con contorno. Nunca se usa un TextLabel pelado. ]]
function Theme.label(config: LabelConfig): TextLabel
	local label = Instance.new("TextLabel")

	label.Name = config.name
	label.Size = config.size
	label.Position = config.position or UDim2.fromScale(0, 0)
	label.AnchorPoint = config.anchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.Font = config.font or Theme.font
	label.Text = config.text
	label.TextSize = config.textSize
	label.TextColor3 = config.color or COLORS.text
	label.TextXAlignment = config.alignment or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = config.parent

	if config.strokeThickness ~= 0 then
		Theme.textOutline(label, config.strokeThickness)
	end

	return label
end

--[[ Titulo grande con degradado en el TEXTO (el degradado de un TextLabel pinta las letras). ]]
function Theme.title(config: LabelConfig & { top: Color3?, bottom: Color3? }): TextLabel
	local label = Theme.label({
		name = config.name,
		parent = config.parent,
		size = config.size,
		position = config.position,
		anchorPoint = config.anchorPoint,
		text = config.text,
		textSize = config.textSize,
		color = Color3.new(1, 1, 1),
		alignment = config.alignment or Enum.TextXAlignment.Center,
		font = config.font or Theme.titleFont,
		strokeThickness = config.strokeThickness or 5,
	})

	Theme.gradient(label, config.top or COLORS.gold, config.bottom or COLORS.goldDark)

	return label
end

export type IconConfig = {
	name: string,
	parent: Instance,
	size: number,
	position: UDim2,
	anchorPoint: Vector2?,
	icon: string,
	top: Color3,
	bottom: Color3,
	iconScale: number?,
}

--[[ Medalla circular con un emoji adentro: corazon, rayo, moneda, calavera. ]]
function Theme.iconBadge(config: IconConfig): (Frame, TextLabel)
	local badge = Instance.new("Frame")

	badge.Name = config.name
	badge.Size = UDim2.fromOffset(config.size, config.size)
	badge.Position = config.position
	badge.AnchorPoint = config.anchorPoint or Vector2.zero
	badge.BorderSizePixel = 0
	badge.Parent = config.parent

	Theme.circle(badge)
	Theme.gradient(badge, config.top, config.bottom)
	Theme.outline(badge, 3)

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Font = Theme.font
	icon.Text = config.icon
	icon.TextSize = math.floor(config.size * (config.iconScale or 0.58))
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.ZIndex = badge.ZIndex + 1
	icon.Parent = badge

	return badge, icon
end

--[[ Pastilla de tecla: "[Q]" dibujado como una tecla de verdad. ]]
function Theme.keyCap(parent: Instance, key: string, position: UDim2, anchorPoint: Vector2?): Frame
	local width = math.max(28, 14 + #key * 11)

	local cap = Theme.panel({
		name = "Key_" .. key,
		parent = parent,
		size = UDim2.fromOffset(width, 26),
		position = position,
		anchorPoint = anchorPoint,
		top = Color3.fromRGB(255, 255, 255),
		bottom = Color3.fromRGB(200, 196, 220),
		radius = 7,
		strokeThickness = 2,
		transparency = 0,
	})

	local label = Theme.label({
		name = "Key",
		parent = cap,
		size = UDim2.fromScale(1, 1),
		text = key,
		textSize = 15,
		color = COLORS.outline,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = 0,
	})
	label.ZIndex = cap.ZIndex + 1

	return cap
end

--------------------------------------------------------------------------------
-- Botones
--------------------------------------------------------------------------------

export type ButtonConfig = {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	text: string,
	textSize: number,
	top: Color3,
	bottom: Color3,
	font: Enum.Font?,
	clickSound: string?, -- nombre en SoundLibrary; "" para que no suene
	shine: boolean?,
}

export type Button = {
	button: TextButton,
	label: TextLabel,
	gradient: UIGradient,
	stroke: UIStroke,
	scale: UIScale,
}

--[[
	Boton "gomita": degradado, contorno, crece al pasar el mouse, se aplasta al apretar,
	y suena en las dos cosas.

	El texto va en un TextLabel hijo y no en el `Text` del boton: el `UIStroke` del
	recuadro (modo Border) y el del texto (modo Contextual) no pueden convivir en la
	misma instancia.
]]
function Theme.button(config: ButtonConfig): Button
	local button = Instance.new("TextButton")

	button.Name = config.name
	button.Size = config.size
	button.Position = config.position
	button.AnchorPoint = config.anchorPoint or Vector2.new(0.5, 0.5)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = config.parent

	Theme.corner(button, 14)

	local gradient = Theme.gradient(button, config.top, config.bottom)
	local stroke = Theme.outline(button, 4)
	local scale = Theme.scaleOf(button)

	-- Brillo fijo en la mitad de arriba: el "caramelo" de los botones de Roblox.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, -10, 0.42, 0)
	gloss.Position = UDim2.fromOffset(5, 4)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.78
	gloss.BorderSizePixel = 0
	gloss.ZIndex = button.ZIndex + 1
	gloss.Parent = button
	Theme.corner(gloss, 10)

	local label = Theme.label({
		name = "Label",
		parent = button,
		size = UDim2.fromScale(1, 1),
		text = config.text,
		textSize = config.textSize,
		alignment = Enum.TextXAlignment.Center,
		font = config.font or Theme.titleFont,
		strokeThickness = 3,
	})
	label.ZIndex = button.ZIndex + 3

	if config.shine then
		Theme.shine(button)
	end

	local hovering = false

	button.MouseEnter:Connect(function()
		hovering = true
		SoundController.play("hover")
		TweenService:Create(scale, Theme.tweens.hover, { Scale = HOVER_SCALE }):Play()
	end)

	button.MouseLeave:Connect(function()
		hovering = false
		TweenService:Create(scale, Theme.tweens.hover, { Scale = 1 }):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, Theme.tweens.press, { Scale = PRESS_SCALE }):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, Theme.tweens.hover, { Scale = if hovering then HOVER_SCALE else 1 }):Play()
	end)

	local clickSound = config.clickSound or "click"

	button.Activated:Connect(function()
		if clickSound ~= "" then
			SoundController.play(clickSound)
		end
	end)

	return {
		button = button,
		label = label,
		gradient = gradient,
		stroke = stroke,
		scale = scale,
	}
end

function Theme.setButtonColors(handle: Button, top: Color3, bottom: Color3): ()
	Theme.setGradient(handle.gradient, top, bottom)
end

--------------------------------------------------------------------------------
-- Barras
--------------------------------------------------------------------------------

export type BarConfig = {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	fillTop: Color3,
	fillBottom: Color3,
	ghostColor: Color3,
	segments: number?,
}

export type Bar = {
	container: Frame,
	fill: Frame,
	fillGradient: UIGradient,
	ghost: Frame,
}

--[[
	Barra de recurso redondeada con RASTRO.

	El "ghost" es una barra detras que baja mas lento que la real: en un juego donde un
	escopetazo te saca 40 de vida en un frame, el rastro deja ver el mordisco.

	Las muescas (`segments`) convierten "mas o menos media barra" en "dos de cuatro".
]]
function Theme.bar(config: BarConfig): Bar
	local container = Instance.new("Frame")

	container.Name = config.name
	container.Size = config.size
	container.Position = config.position
	container.AnchorPoint = config.anchorPoint or Vector2.zero
	container.BackgroundColor3 = COLORS.panelDeep
	container.BackgroundTransparency = 0
	container.BorderSizePixel = 0
	container.Parent = config.parent

	Theme.corner(container, 999)
	Theme.outline(container, 3)

	local ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.Size = UDim2.fromScale(1, 1)
	ghost.BackgroundColor3 = config.ghostColor
	ghost.BorderSizePixel = 0
	ghost.ZIndex = 2
	ghost.Parent = container
	Theme.corner(ghost, 999)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Parent = container
	Theme.corner(fill, 999)

	local fillGradient = Theme.gradient(fill, config.fillTop, config.fillBottom)

	-- Reflejo superior: la franja clara que hace que la barra parezca un tubo.
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.new(1, -8, 0.32, 0)
	sheen.Position = UDim2.new(0, 4, 0.12, 0)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BackgroundTransparency = 0.6
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 4
	sheen.Parent = fill
	Theme.corner(sheen, 999)

	local segments = config.segments or 0

	if segments > 1 then
		for index = 1, segments - 1 do
			local notch = Instance.new("Frame")
			notch.Name = string.format("Notch%d", index)
			notch.Size = UDim2.new(0, 2, 0.6, 0)
			notch.Position = UDim2.fromScale(index / segments, 0.2)
			notch.AnchorPoint = Vector2.new(0.5, 0)
			notch.BackgroundColor3 = COLORS.outline
			notch.BackgroundTransparency = 0.55
			notch.BorderSizePixel = 0
			notch.ZIndex = 5
			notch.Parent = container
		end
	end

	return {
		container = container,
		fill = fill,
		fillGradient = fillGradient,
		ghost = ghost,
	}
end

--------------------------------------------------------------------------------
-- Escala
--------------------------------------------------------------------------------

-- El "lienzo" de diseno: todas las Views estan pensadas para 1200x900 como minimo.
local BASE_VIEWPORT_HEIGHT = 900
local BASE_VIEWPORT_WIDTH = 1200
local MIN_SCALE = 0.35
local MAX_SCALE = 1.6

--[[
	Ajusta el UIScale a la pantalla. Se llama al arrancar y cada vez que cambia el
	viewport (ventana redimensionada, rotacion de un telefono).

	Se toma el MENOR de los dos factores (alto y ancho): asi el lienzo de diseno
	siempre entra entero y ningun panel se pisa con otro, que es lo que pasaba en
	ventanas chicas (el viewport de Studio, un telefono) cuando solo contaba el alto.
]]
function Theme.applyViewportScale(scaleObject: UIScale, viewportSize: Vector2): ()
	local raw = math.min(viewportSize.Y / BASE_VIEWPORT_HEIGHT, viewportSize.X / BASE_VIEWPORT_WIDTH)

	scaleObject.Scale = math.clamp(raw, MIN_SCALE, MAX_SCALE)
end

return table.freeze(Theme)

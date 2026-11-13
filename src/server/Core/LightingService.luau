--!strict
--[[
	LightingService: la atmosfera del juego, aplicada desde codigo al arrancar.

	POR QUE ESTO NO VIVE EN EL PLACE (es la misma decision que ya se tomo con la matriz
	de CollisionGroups en la Fase 0, y por los mismos motivos):

	  - Si vive en el `.rbxl`, no hay diff. El dia que alguien mueva la niebla, no hay
	    PR, ni historial, ni forma de saber quien la rompio.
	  - El `.rbxl` no esta en Git. La configuracion del place venia siendo anotada a
	    mano en el CHANGELOG porque era la unica forma de recordarla; esto la vuelve
	    codigo y el changelog deja de ser su unico registro.
	  - Un colaborador nuevo que sincroniza el repo obtiene la atmosfera correcta sin
	    tener que copiar valores de un documento.

	POR QUE EXISTE ESTE ARCHIVO, ademas: hasta la Fase 4 el juego se veia NEGRO. La
	causa eran cuatro factores que se multiplicaban entre si, cada uno razonable por
	separado:

	  1. `ClockTime = 0` (medianoche) dejaba al sol bajo el horizonte, asi que la unica
	     luz era el ambiente.
	  2. El ambiente estaba en 0.23, y el ambiente MULTIPLICA el color de la parte.
	  3. Los grises del greybox eran del 23% de luminancia.
	  4. El ColorCorrection tenia +0.3 de contraste, que empuja lo oscuro hacia el negro.

	0.23 x 0.23 = 5% de brillo, y el contraste lo bajaba a ~3%. A eso se le sumaba una
	niebla calibrada para una camara que no es la nuestra (ver `Constants.FOG_START_STUDS`).

	Se conserva la intencion estetica del documento de estilo: sin sombras, saturacion
	baja y niebla densa que esconde el final del piso. Lo que se corrigio es que fuera
	tan densa y tan oscura que escondia tambien el propio piso.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)

local GRADE_NAME = "PixelMadnessGrade"

local log = Logger.new("LightingService")

local LightingService = {
	name = "LightingService",
}

local function toColor(rgb: { r: number, g: number, b: number }): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

--[[ Aplica la atmosfera. Idempotente: se puede llamar mil veces. ]]
function LightingService.apply(): ()
	Lighting.Ambient = toColor(Constants.AMBIENT_COLOR)
	Lighting.OutdoorAmbient = toColor(Constants.OUTDOOR_AMBIENT_COLOR)
	Lighting.Brightness = Constants.LIGHTING_BRIGHTNESS
	Lighting.ClockTime = Constants.CLOCK_TIME

	-- Sin sombras: es el 60% del look plano del documento de estetica, y ademas es lo
	-- que permite subir el ambiente sin que la escena se vea sucia.
	Lighting.GlobalShadows = false
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0

	Lighting.FogStart = Constants.FOG_START_STUDS
	Lighting.FogEnd = Constants.FOG_END_STUDS
	Lighting.FogColor = toColor(Constants.FOG_COLOR)

	local grade = Lighting:FindFirstChild(GRADE_NAME)

	if not grade or not grade:IsA("ColorCorrectionEffect") then
		if grade then
			grade:Destroy()
		end

		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = GRADE_NAME
		grade.Parent = Lighting
	end

	local correction = grade :: ColorCorrectionEffect
	correction.Contrast = Constants.GRADE_CONTRAST
	correction.Saturation = Constants.GRADE_SATURATION
	correction.Brightness = 0
	correction.Enabled = true
end

function LightingService.start(): ()
	LightingService.apply()

	log:info(
		"Atmosfera aplicada. Niebla %d-%d studs (camara a %d como mucho del jugador).",
		Constants.FOG_START_STUDS,
		Constants.FOG_END_STUDS,
		Constants.CAMERA_MAX_DISTANCE_STUDS
	)
end

return LightingService

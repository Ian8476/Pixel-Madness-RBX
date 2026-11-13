--!strict
--[[
	CharacterFacing: aplica la direccion de mira al cuerpo del personaje.

	Modulo separado de AimProvider a proposito: uno CALCULA hacia donde se apunta
	(logica de input), el otro lo PINTA (presentacion). Cuando en la Fase 8 el giro
	pase a interpolarse o a tener animacion de torso, se toca solo este archivo.

	Con la camara de shooter el cuerpo mira SIEMPRE hacia donde mira la camara, tambien
	cuando caminas de costado o hacia atras. Es lo contrario de lo que hace un personaje
	de aventura y es lo correcto para apuntar: la mira esta en el centro de la pantalla,
	y un cuerpo que se gira hacia donde camina dispararia a otro lado. El
	`AutoRotate = false` que pone CharacterService es lo que deja hacerlo sin pelea.

	Se escribe la CFrame directamente en vez de usar AlignOrientation porque el cliente
	es dueno de red de su propio personaje: el cambio es inmediato y se replica solo.
	Solo se toca la rotacion; la posicion la sigue mandando el Humanoid.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AimProvider = require(script.Parent.Parent.Input.AimProvider)

local BIND_NAME = "PixelMadnessFacing"

local CharacterFacing = {
	name = "CharacterFacing",
}

local localPlayer = Players.LocalPlayer

local function update(): ()
	local character = localPlayer.Character

	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local position = root.Position
	local direction = AimProvider.getAimDirection()

	root.CFrame = CFrame.lookAt(position, position + direction)
end

function CharacterFacing.start(): ()
	-- Justo despues de AimProvider, que a su vez corre despues de la camara.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, update)
end

return CharacterFacing

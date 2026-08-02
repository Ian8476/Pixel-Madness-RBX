--!strict
--[[
	CharacterFacing: aplica la direccion de mira al cuerpo del personaje.

	Modulo separado de AimProvider a proposito: uno CALCULA hacia donde se apunta
	(logica de input), el otro lo PINTA (presentacion). Cuando en la Fase 8 el giro
	pase a interpolarse o a tener animacion de torso, se toca solo este archivo.

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
	-- Justo despues de AimProvider y antes de la camara.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Input.Value + 1, update)
end

return CharacterFacing

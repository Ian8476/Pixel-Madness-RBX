--!strict
--[[
	TopDownCamera: camara top-down con seguimiento suave y look-ahead hacia la mira.

	El look-ahead es lo que hace que la camara se sienta "de shooter" y no "de
	plataformas": el encuadre se corre hacia donde apuntas, asi que ves mas del lado
	al que estas disparando. Es la traduccion directa del CameraFollow de Unity.

	Sobre el suavizado: se usa `1 - exp(-velocidad * dt)` en vez de un alpha fijo.
	Un alpha fijo por frame hace que la camara se mueva mas rapido a 144 fps que a
	60 fps, o sea que el game feel cambia segun el monitor del jugador. La forma
	exponencial es independiente del framerate.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local AimProvider = require(script.Parent.Parent.Input.AimProvider)

local BIND_NAME = "PixelMadnessCamera"
local FOLLOW_SPEED = 12

local TopDownCamera = {
	name = "TopDownCamera",
}

local localPlayer = Players.LocalPlayer
local offset = Vector3.new(Constants.CAMERA_OFFSET.x, Constants.CAMERA_OFFSET.y, Constants.CAMERA_OFFSET.z)

local function update(deltaTime: number): ()
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character

	if not camera or not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local focus = root.Position + AimProvider.getAimDirection() * Constants.CAMERA_LOOK_AHEAD_STUDS
	local target = CFrame.lookAt(focus + offset, focus)

	camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-FOLLOW_SPEED * deltaTime))
end

function TopDownCamera.start(): ()
	local camera = workspace.CurrentCamera

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 55
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value, update)
end

return TopDownCamera

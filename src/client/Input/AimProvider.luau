--!strict
--[[
	AimProvider: donde esta apuntando el jugador, en coordenadas del mundo.

	Metodo: interseccion analitica del rayo de camara con un plano horizontal a la
	altura del pecho del personaje. NO se usa un raycast fisico contra el suelo.

	Por que el plano y no el raycast (traduccion de la decision del documento):
	  - Es una division, no una consulta al motor de fisica: corre 60 veces por
	    segundo por cliente sin costo medible.
	  - No depende de que haya piso debajo del cursor. Con raycast, apuntar a un hueco
	    de puerta, a un pozo o al vacio devuelve nil y el personaje se queda mirando
	    al ultimo punto valido, que se siente roto.
	  - El plano esta a la altura del pecho, o sea a la altura a la que salen las
	    balas: lo que ves bajo el cursor es exactamente lo que va a recibir el disparo.

	Corre en prioridad Input, antes que la camara: la camara lee el aim de este frame
	para su look-ahead, no el del frame anterior.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BIND_NAME = "PixelMadnessAim"

local AimProvider = {
	name = "AimProvider",
}

local localPlayer = Players.LocalPlayer
local aimDirection = Vector3.new(0, 0, 1)
local aimPoint: Vector3? = nil

local function getRootPart(): BasePart?
	local character = localPlayer.Character

	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

--[[ Interseccion del rayo con el plano Y = planeHeight. nil si el rayo es paralelo o apunta al reves. ]]
local function intersectHorizontalPlane(origin: Vector3, direction: Vector3, planeHeight: number): Vector3?
	if math.abs(direction.Y) < 1e-4 then
		return nil
	end

	local distance = (planeHeight - origin.Y) / direction.Y

	if distance < 0 then
		return nil
	end

	return origin + direction * distance
end

local function update(): ()
	local camera = workspace.CurrentCamera
	local root = getRootPart()

	if not camera or not root then
		return
	end

	-- GetMouseLocation y ViewportPointToRay comparten el mismo espacio (sin el inset
	-- de la topbar). Mezclarlo con ScreenPointToRay desplaza la mira ~36 px hacia arriba.
	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local point = intersectHorizontalPlane(unitRay.Origin, unitRay.Direction, root.Position.Y)

	if not point then
		return
	end

	aimPoint = point

	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)

	-- Cuando el cursor cae encima del personaje la direccion es degenerada:
	-- se conserva la ultima valida en vez de dar un giro aleatorio.
	if flat.Magnitude > 1e-3 then
		aimDirection = flat.Unit
	end
end

function AimProvider.getAimDirection(): Vector3
	return aimDirection
end

function AimProvider.getAimPoint(): Vector3?
	return aimPoint
end

function AimProvider.start(): ()
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Input.Value, update)
end

return AimProvider

--!strict
--[[
	AimProvider: donde esta apuntando el jugador, en coordenadas del mundo.

	CAMBIO DE METODO (camara de shooter). Antes la mira era el cursor: se intersectaba
	el rayo del mouse con un plano horizontal a la altura del pecho. Con la camara en
	tercera persona el cursor ya no existe - esta bloqueado en el centro de la pantalla
	girando la camara -, asi que la mira pasa a ser lo que hay bajo el centro de la
	pantalla, que es donde vive la cruz del HUD.

	Metodo: un raycast desde la camara hacia adelante. El primer impacto es el punto de
	mira; si no hay nada, se toma un punto lejano en la misma direccion.

	POR QUE EL RAYCAST Y NO LA DIRECCION DE LA CAMARA A SECAS: la camara esta corrida al
	hombro. Disparar paralelo a ella tirarle a un par de studs al costado de lo que la
	cruz esta tapando, y a 20 studs eso es fallar un enemigo entero. Apuntando al PUNTO
	que la camara ve, la bala converge en la cruz, que es la unica promesa que el jugador
	le pide a una mira.

	La direccion se devuelve APLANADA (sin componente vertical) porque el
	ProjectileSystem dispara en horizontal y el servidor de todas formas la aplana al
	validarla: devolver una direccion inclinada seria prometer un disparo que el juego no
	tiene. Mirar hacia arriba o hacia abajo encuadra, no apunta.

	Corre despues de la camara y antes del giro del cuerpo: lee la camara de ESTE frame,
	no la del anterior.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local BIND_NAME = "PixelMadnessAim"

local AimProvider = {
	name = "AimProvider",
}

local localPlayer = Players.LocalPlayer
local aimDirection = Vector3.new(0, 0, 1)

-- El rayo ignora el cuerpo propio y nada mas: que un enemigo o un companero delante de
-- la cruz atraigan el punto de mira es justamente lo que se busca. Balas, monedas y
-- pickups no necesitan filtro porque nacen con `CanQuery = false`.
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function getRootPart(): BasePart?
	local character = localPlayer.Character

	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

local function flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)

	return if flat.Magnitude > 1e-3 then flat.Unit else nil
end

local function update(): ()
	local camera = workspace.CurrentCamera
	local root = getRootPart()

	if not camera or not root then
		return
	end

	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector

	local result = workspace:Raycast(origin, look * Constants.AIM_RAY_LENGTH_STUDS, aimParams)
	local point = if result then result.Position else origin + look * Constants.AIM_RAY_LENGTH_STUDS

	-- Un punto demasiado cerca del jugador (la pared contra la que esta pegado, el piso
	-- a sus pies) da una direccion que salta con cualquier movimiento: ahi manda la
	-- camara, que gira de forma estable.
	local converged = if (point - root.Position).Magnitude >= Constants.AIM_MIN_CONVERGENCE_STUDS
		then flatten(point - root.Position)
		else nil

	local direction = converged or flatten(look)

	-- Sin direccion valida se conserva la ultima: un giro aleatorio se ve como un tic.
	if direction then
		aimDirection = direction
	end
end

function AimProvider.getAimDirection(): Vector3
	return aimDirection
end

function AimProvider.start(): ()
	local function refreshFilter(): ()
		local character = localPlayer.Character

		aimParams.FilterDescendantsInstances = if character then { character } else {}
	end

	refreshFilter()
	localPlayer.CharacterAdded:Connect(refreshFilter)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

return AimProvider

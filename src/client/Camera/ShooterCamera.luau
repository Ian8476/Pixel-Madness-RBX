--!strict
--[[
	ShooterCamera: camara de shooter en tercera persona, con primera persona incluida.

	Reemplaza a la vieja TopDownCamera (offset fijo (0, 45, -28) y look-ahead hacia el
	cursor). El cambio de perspectiva arrastra tres consecuencias que estan resueltas
	aca y conviene tener presentes antes de tocar este archivo:

	  1. EL MOUSE PASA A SER LA CAMARA, no la mira. Con `MouseBehavior = LockCenter` el
	     cursor desaparece y el delta del mouse gira la camara. Como consecuencia, la
	     mira ya no se calcula intersectando el cursor con un plano: sale del centro de
	     la pantalla (ver AimProvider).

	  2. EL CURSOR TIENE QUE VOLVER cuando hay un panel abierto, o el jugador no puede
	     apretar LISTO. Esta camara NO sabe que es un panel: recibe `setInputEnabled` de
	     UIController, que es quien ya decide que se ve. La dependencia va en un solo
	     sentido a proposito (UIController -> camara); al reves seria un ciclo de
	     requires, que es exactamente la trampa que ya costo un `C stack overflow` entre
	     dos servicios del servidor.

	  3. HAY PAREDES ENTRE MEDIO. Una camara a 12 studs detras del jugador y a la altura
	     de los ojos se mete dentro de la pared de atras en la primera esquina. Por eso
	     el raycast de oclusion: si algo tapa, la camara se acerca hasta el impacto.

	--------------------------------------------------------------------------------
	PRIMERA PERSONA
	--------------------------------------------------------------------------------

	No es una segunda camara ni un modo aparte: es esta misma con la distancia en cero.
	Eso es lo que permite que la RUEDA DEL MOUSE entre y salga de ella sin abrir ningun
	menu (acercar por debajo de la distancia minima entra; alejar sale), y que el boton
	del menu sea un atajo a lo mismo y no otro camino.

	Dos ajustes acompanan el acercamiento para que la transicion no se vea rota:
	  - El offset de hombro se apaga proporcionalmente. A distancia cero, un hombro de
	    2.2 studs dejaria la camara flotando al costado de la cabeza.
	  - El cuerpo se vuelve invisible SOLO para su dueno (`LocalTransparencyModifier`).
	    Los demas te siguen viendo entero: es una propiedad local, no replica.

	--------------------------------------------------------------------------------

	Sobre el suavizado: la rotacion es 1:1 con el mouse, sin lerp. Suavizar el giro de
	un shooter es lo que se siente como "mando de tanque" y es la queja numero uno de
	las camaras caseras. Lo unico que se suaviza es la DISTANCIA (el zoom), donde el
	salto seco si se nota feo. La forma es `1 - exp(-velocidad * dt)` y no un alpha
	fijo, por el mismo motivo de siempre: un alpha fijo por frame va mas rapido a 144
	fps que a 60, o sea que el game feel dependeria del monitor.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Signal = require(Shared:WaitForChild("Signal"))
local Tags = require(Shared:WaitForChild("Tags"))

local BIND_NAME = "PixelMadnessCamera"
local ZOOM_SPEED = 14 -- suavizado exponencial de la distancia
-- Distancia por debajo de la cual el cuerpo propio estorba mas de lo que ubica. Cubre
-- la primera persona y tambien a la camara aplastada contra una pared.
local HIDE_BODY_DISTANCE_STUDS = 2.5

local ShooterCamera = {
	name = "ShooterCamera",
}

-- (esta en primera persona) La escucha MenuView para pintar su boton: la rueda del
-- mouse tambien cambia el modo, asi que el boton no puede llevar la cuenta por su lado.
ShooterCamera.firstPersonChanged = Signal.new() :: Signal.Signal<boolean>

local localPlayer = Players.LocalPlayer

local yawDegrees = 0
local pitchDegrees = -10 -- un pelin hacia abajo: es el encuadre natural de un shooter
local pendingDelta = Vector2.zero

local isFirstPerson = false
local targetDistance = Constants.CAMERA_DEFAULT_DISTANCE_STUDS
local currentDistance = Constants.CAMERA_DEFAULT_DISTANCE_STUDS
-- A donde volver al salir de primera persona por el boton del menu. La rueda no lo usa:
-- alejarse un paso desde la primera persona tiene que dejarte en la distancia MINIMA,
-- que es el paso inmediatamente anterior, y no de vuelta donde estabas hace un rato.
local lastThirdPersonDistance = Constants.CAMERA_DEFAULT_DISTANCE_STUDS

local inputEnabled = true
local isBodyHidden = false
local bodyParts: { BasePart } = {}
local bodyConnection: RBXScriptConnection? = nil

--[[
	Filtro del raycast de oclusion: se ignoran los cuerpos, se respeta el mundo.

	Un enemigo que te pasa por detras no tiene que arrastrarte la camara a la nuca. Y el
	propio personaje menos todavia: es lo primero que el rayo se encontraria siempre.
	Balas, monedas y pickups no hace falta listarlos porque nacen con `CanQuery = false`.
]]
local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
occlusionParams.IgnoreWater = true

--------------------------------------------------------------------------------
-- Estado del personaje
--------------------------------------------------------------------------------

local function refreshOcclusionFilter(): ()
	local ignored: { Instance } = {}

	-- El personaje propio se agrega a mano ademas de por tag: el tag lo pone el servidor
	-- y tarda un instante en replicar, y en ese instante la camara ya esta corriendo.
	local character = localPlayer.Character

	if character then
		table.insert(ignored, character)
	end

	for _, instance in CollectionService:GetTagged(Tags.Player) do
		table.insert(ignored, instance)
	end

	for _, instance in CollectionService:GetTagged(Tags.Enemy) do
		table.insert(ignored, instance)
	end

	occlusionParams.FilterDescendantsInstances = ignored
end

--[[
	Cachea las partes del cuerpo. Se recorre el personaje una vez por vida y no cada
	frame: en primera persona hay que reescribir la transparencia constantemente.
]]
local function refreshBodyParts(character: Model?): ()
	if bodyConnection then
		bodyConnection:Disconnect()
		bodyConnection = nil
	end

	table.clear(bodyParts)

	if not character then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(bodyParts, descendant)
		end
	end

	-- El motor arma el personaje en varios frames. Una parte que llega tarde se suma a
	-- la cache o en primera persona reaparece flotando un brazo suelto.
	bodyConnection = character.DescendantAdded:Connect(function(descendant: Instance)
		if not descendant:IsA("BasePart") then
			return
		end

		table.insert(bodyParts, descendant)

		if isBodyHidden then
			descendant.LocalTransparencyModifier = 1
		end
	end)
end

--[[
	`LocalTransparencyModifier` es lo que usa el propio Roblox para su primera persona:
	es una propiedad de cliente, no replica, y no pelea con el `Transparency` real de la
	parte (que es del servidor). Se reescribe cada frame mientras el cuerpo esta oculto
	porque el motor la resetea cuando la parte recibe una actualizacion.
]]
local function applyBodyVisibility(hidden: boolean): ()
	if not hidden and not isBodyHidden then
		return
	end

	for _, part in bodyParts do
		part.LocalTransparencyModifier = if hidden then 1 else 0
	end

	isBodyHidden = hidden
end

local function onCharacterAdded(character: Model): ()
	refreshBodyParts(character)
	refreshOcclusionFilter()

	isBodyHidden = false

	-- La camara arranca mirando hacia donde mira el cuerpo recien spawneado, en vez de
	-- conservar el angulo de la vida anterior y hacerte reaparecer mirando una pared.
	local root = character:FindFirstChild("HumanoidRootPart")

	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector

		yawDegrees = math.deg(math.atan2(-look.X, -look.Z))
	end
end

--------------------------------------------------------------------------------
-- Modo y zoom
--------------------------------------------------------------------------------

local function enterFirstPerson(): ()
	if isFirstPerson then
		return
	end

	lastThirdPersonDistance = targetDistance
	isFirstPerson = true
	targetDistance = 0

	ShooterCamera.firstPersonChanged:fire(true)
end

local function exitFirstPerson(distance: number): ()
	if not isFirstPerson then
		return
	end

	isFirstPerson = false
	targetDistance = math.clamp(distance, Constants.CAMERA_MIN_DISTANCE_STUDS, Constants.CAMERA_MAX_DISTANCE_STUDS)

	ShooterCamera.firstPersonChanged:fire(false)
end

--[[
	Un golpe de rueda. `steps` positivo acerca. Es el camino que entra y sale de primera
	persona sin abrir nada: por debajo de la distancia minima ya no hay tercera persona
	que valga, asi que en vez de frenar contra un tope se pasa a primera.
]]
local function zoom(steps: number): ()
	if isFirstPerson then
		if steps < 0 then
			exitFirstPerson(Constants.CAMERA_MIN_DISTANCE_STUDS)
		end

		return
	end

	local wanted = targetDistance - steps * Constants.CAMERA_ZOOM_STEP_STUDS

	if wanted < Constants.CAMERA_MIN_DISTANCE_STUDS then
		enterFirstPerson()
		return
	end

	targetDistance = math.min(wanted, Constants.CAMERA_MAX_DISTANCE_STUDS)
end

--------------------------------------------------------------------------------
-- Frame a frame
--------------------------------------------------------------------------------

local function applyMouseState(): ()
	UserInputService.MouseBehavior = if inputEnabled then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not inputEnabled
end

--[[ Distancia real a la que puede quedar la camara sin meterse dentro de una pared. ]]
local function resolveOcclusion(pivot: Vector3, offset: Vector3): Vector3
	local length = offset.Magnitude

	if length < 1e-3 then
		return offset
	end

	local result = workspace:Raycast(pivot, offset, occlusionParams)

	if not result then
		return offset
	end

	local allowed = (result.Position - pivot).Magnitude - Constants.CAMERA_COLLISION_PADDING_STUDS

	return offset * math.clamp(allowed / length, 0, 1)
end

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

	-- Reafirmar el tipo de camara cada frame no es paranoia: al respawnear, el
	-- PlayerModule de Roblox la devuelve a Custom y la camara se iria sola.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FIELD_OF_VIEW
	end

	if inputEnabled then
		-- Idem con el cursor: perder el foco de la ventana lo desbloquea.
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end

		local sensitivity = Constants.CAMERA_SENSITIVITY_DEGREES_PER_PIXEL

		yawDegrees = (yawDegrees - pendingDelta.X * sensitivity) % 360
		pitchDegrees = math.clamp(
			pitchDegrees - pendingDelta.Y * sensitivity,
			Constants.CAMERA_PITCH_MIN_DEGREES,
			Constants.CAMERA_PITCH_MAX_DEGREES
		)
	end

	pendingDelta = Vector2.zero

	-- YXZ aplica primero el giro horizontal y despues el vertical: es lo que evita que
	-- la camara se incline de costado al mirar hacia arriba mientras giras.
	local rotation = CFrame.fromEulerAnglesYXZ(math.rad(pitchDegrees), math.rad(yawDegrees), 0)
	local pivot = root.Position + Vector3.new(0, Constants.CAMERA_EYE_HEIGHT_STUDS, 0)

	currentDistance += (targetDistance - currentDistance) * (1 - math.exp(-ZOOM_SPEED * deltaTime))

	-- El hombro se apaga junto con la distancia: a medio camino de la primera persona,
	-- medio hombro.
	local shoulderRatio = math.clamp(currentDistance / Constants.CAMERA_MIN_DISTANCE_STUDS, 0, 1)
	local shoulder = Constants.CAMERA_SHOULDER_OFFSET_STUDS * shoulderRatio

	local offset = rotation.RightVector * shoulder - rotation.LookVector * currentDistance
	local resolved = resolveOcclusion(pivot, offset)

	camera.CFrame = CFrame.new(pivot + resolved) * rotation

	applyBodyVisibility(resolved.Magnitude < HIDE_BODY_DISTANCE_STUDS)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function ShooterCamera.isFirstPerson(): boolean
	return isFirstPerson
end

--[[ Lo llama UIController cuando el jugador toca el boton del menu. ]]
function ShooterCamera.setFirstPerson(value: boolean): ()
	if value then
		enterFirstPerson()
	else
		exitFirstPerson(lastThirdPersonDistance)
	end
end

--[[
	Enciende o apaga el control de camara. Apagado: vuelve el cursor y el mouse deja de
	girar la vista, que es lo que hace falta con un panel abierto. La camara sigue
	siguiendo al personaje: congelarla ademas haria que abrir el menu se viera como un
	tiron.
]]
function ShooterCamera.setInputEnabled(enabled: boolean): ()
	if inputEnabled == enabled then
		return
	end

	inputEnabled = enabled
	pendingDelta = Vector2.zero

	applyMouseState()
end

function ShooterCamera.start(): ()
	local camera = workspace.CurrentCamera

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = Constants.CAMERA_FIELD_OF_VIEW
	end

	-- UIController arranca ANTES que la camara y ya decidio si hay un panel abierto:
	-- aca se obedece esa decision en vez de asumir que se empieza jugando.
	applyMouseState()

	-- Sin `:Wait()`: el bootstrap del cliente corre en el lobby, donde el personaje
	-- puede no existir todavia, y bloquear aca dejaria sin arrancar a todo lo que va
	-- detras en la lista de servicios.
	local character = localPlayer.Character

	if character then
		onCharacterAdded(character)
	end

	localPlayer.CharacterAdded:Connect(onCharacterAdded)

	CollectionService:GetInstanceAddedSignal(Tags.Player):Connect(refreshOcclusionFilter)
	CollectionService:GetInstanceRemovedSignal(Tags.Player):Connect(refreshOcclusionFilter)
	CollectionService:GetInstanceAddedSignal(Tags.Enemy):Connect(refreshOcclusionFilter)
	CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(refreshOcclusionFilter)

	UserInputService.InputChanged:Connect(function(input: InputObject, processedByUi: boolean)
		if not inputEnabled then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Se acumula y se consume en el RenderStep: dos eventos de mouse en el mismo
			-- frame tienen que girar la camara una sola vez.
			pendingDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processedByUi then
			zoom(input.Position.Z)
		end
	end)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value, update)
end

return ShooterCamera

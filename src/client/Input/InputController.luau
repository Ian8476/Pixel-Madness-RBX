--!strict
--[[
	InputController: traduce teclas y clicks en INTENCIONES para el servidor.

	Este modulo no calcula dano, ni cadencia real, ni consume energia. Solo dice
	"quiero disparar hacia alla" (regla 5). El movimiento WASD no aparece por ningun
	lado porque lo resuelve el Humanoid: gratis, replicado y con prediccion nativa.

	Mapa de controles (documento de contexto, seccion 2):
	  Click izquierdo -> disparar        Q -> alternar arma
	  ESPACIO         -> habilidad       E -> recoger arma

	El mouse y la rueda no aparecen aca: giran y acercan la camara, y de eso se ocupa
	ShooterCamera. Este modulo solo lee la direccion de mira ya resuelta.

	ESPACIO ya no salta: el salto esta desactivado en CharacterService por dos vias.

	Sobre el ritmo de envio de FireRequest (cambio de la Fase 2): mientras el boton
	este apretado se manda una intencion al ritmo del ARMA EQUIPADA, no cada 100 ms
	fijos. NO es una medida de seguridad (la cadencia real la impone el servidor y el
	rate limiter corta al que mande de mas): es cortesia de ancho de banda. La Fiel
	dispara 4 veces por segundo y no tiene sentido mandarle 60 mensajes.

	`isAutomatic` tambien se aplica aca y no en el servidor: que El Dedo de Dios sea
	de un click por disparo es game feel, no seguridad. Un cliente modificado que
	mantenga el fuego choca igual contra la cadencia del arma, que es el limite que
	importa.

	La capa esta aislada a proposito: agregar gamepad o tactil (mando/joystick
	virtual) es agregar entradas aqui, sin tocar una linea de gameplay.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))

local AimProvider = require(script.Parent.AimProvider)
local ClientState = require(script.Parent.Parent.State.ClientState)
local UIController = require(script.Parent.Parent.UI.UIController)

local BIND_NAME = "PixelMadnessInput"

-- Sin snapshot todavia (los primeros frames de la partida) se usa un ritmo prudente.
local DEFAULT_SEND_INTERVAL_SECONDS = 0.1
-- Se manda un pelin antes del intervalo teorico para que el jitter de red no coma
-- disparos legitimos. Es el mismo 10% que tolera el servidor.
local SEND_INTERVAL_MARGIN = 0.9
local MIN_SEND_INTERVAL_SECONDS = 0.03

local ABILITY_KEY = Enum.KeyCode.Space
local SWAP_KEY = Enum.KeyCode.Q
local PICKUP_KEY = Enum.KeyCode.E

local InputController = {
	name = "InputController",
}

local player = Players.LocalPlayer
local isHoldingFire = false
local lastSendClock = 0

local function getSendInterval(): number
	local weapon = ClientState.getActiveWeapon()

	if not weapon then
		return DEFAULT_SEND_INTERVAL_SECONDS
	end

	local interval = 1 / (weapon.fireRate * ClientState.getFireRateMultiplier())

	return math.max(MIN_SEND_INTERVAL_SECONDS, interval * SEND_INTERVAL_MARGIN)
end

local function sendFireRequest(): ()
	lastSendClock = os.clock()

	Remotes.event("FireRequest"):FireServer({
		aimDirection = AimProvider.getAimDirection(),
	})
end

local function update(): ()
	if not isHoldingFire or UIController.isModalOpen() then
		return
	end

	local weapon = ClientState.getActiveWeapon()

	-- Semiautomatica: un click, un disparo. El primero ya salio en InputBegan.
	if weapon and not weapon.isAutomatic then
		return
	end

	if os.clock() - lastSendClock < getSendInterval() then
		return
	end

	sendFireRequest()
end

--[[
	Pickup mas cercano dentro del rango. El servidor REVALIDA la distancia: esto solo
	elige el candidato, porque el cliente es quien sabe donde esta el cursor del
	jugador y que tiene enfrente.
]]
local function findNearestPickup(): Instance?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if not root or not root:IsA("BasePart") then
		return nil
	end

	local nearest: Instance? = nil
	local nearestDistance = Constants.PICKUP_RANGE_STUDS

	for _, pickup in CollectionService:GetTagged(Tags.WeaponPickup) do
		local position: Vector3? = nil

		if pickup:IsA("BasePart") then
			position = pickup.Position
		elseif pickup:IsA("Model") then
			position = pickup:GetPivot().Position
		end

		if not position then
			continue
		end

		local distance = (position - root.Position).Magnitude

		if distance <= nearestDistance then
			nearest = pickup
			nearestDistance = distance
		end
	end

	return nearest
end

local function onKeyDown(keyCode: Enum.KeyCode): ()
	if keyCode == SWAP_KEY then
		Remotes.event("SwapWeapon"):FireServer()
	elseif keyCode == ABILITY_KEY then
		Remotes.event("UseAbility"):FireServer()
	elseif keyCode == PICKUP_KEY then
		local pickup = findNearestPickup()

		-- Sin candidato no se manda nada: no tiene sentido gastarle el presupuesto de
		-- rate limit al jugador que aprieta E en el aire.
		if pickup then
			Remotes.event("PickupRequest"):FireServer({ pickup = pickup })
		end
	end
end

function InputController.start(): ()
	UserInputService.InputBegan:Connect(function(input: InputObject, processedByUi: boolean)
		-- `processedByUi` cubre los clicks sobre botones, pero no las teclas: sin la
		-- segunda condicion, elegir personaje con el panel abierto tambien gastaria la
		-- habilidad y cambiaria de arma.
		if processedByUi or UIController.isModalOpen() then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isHoldingFire = true
			-- El primer click sale de inmediato: esperar al proximo tick se siente
			-- como un juego con lag aunque no lo tenga.
			sendFireRequest()
		elseif input.UserInputType == Enum.UserInputType.Keyboard then
			onKeyDown(input.KeyCode)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isHoldingFire = false
		end
	end)

	-- Soltar el boton fuera de la ventana deja el disparo trabado sin esto.
	UserInputService.WindowFocusReleased:Connect(function()
		isHoldingFire = false
	end)

	-- Ultimo de la cadena camara -> mira -> cuerpo -> intencion: la direccion que se le
	-- manda al servidor es la de este frame, no la del anterior.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 3, update)
end

return InputController

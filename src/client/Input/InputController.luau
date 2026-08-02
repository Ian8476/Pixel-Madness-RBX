--!strict
--[[
	InputController: traduce teclas y clicks en INTENCIONES para el servidor.

	Este modulo no calcula dano, ni cadencia real, ni consume energia. Solo dice
	"quiero disparar hacia alla" (regla 5). El movimiento WASD no aparece por ningun
	lado porque lo resuelve el Humanoid: gratis, replicado y con prediccion nativa.

	Sobre el throttle de envio: mientras el boton este apretado se manda un
	FireRequest cada 100 ms. NO es una medida de seguridad, es cortesia de ancho de
	banda: sin el se mandarian 60 mensajes por segundo para un arma que dispara 4
	veces. La cadencia real la impone el servidor, y el rate limiter corta al que
	mande de mas. Cuando la Fase 2 traiga los datos de armas al cliente, este
	intervalo pasara a derivarse del arma equipada.

	La capa esta aislada a proposito: agregar gamepad o tactil (mando/joystick
	virtual) es agregar entradas aqui, sin tocar una linea de gameplay.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local AimProvider = require(script.Parent.AimProvider)

local BIND_NAME = "PixelMadnessInput"
local FIRE_SEND_INTERVAL_SECONDS = 0.1

local InputController = {
	name = "InputController",
}

local isFiring = false
local lastSendClock = 0

local function update(): ()
	if not isFiring then
		return
	end

	local now = os.clock()

	if now - lastSendClock < FIRE_SEND_INTERVAL_SECONDS then
		return
	end

	lastSendClock = now

	Remotes.event("FireRequest"):FireServer({
		aimDirection = AimProvider.getAimDirection(),
	})
end

function InputController.start(): ()
	UserInputService.InputBegan:Connect(function(input: InputObject, processedByUi: boolean)
		if processedByUi then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isFiring = true
			-- Se dispara de inmediato en vez de esperar al proximo tick: el primer
			-- click tiene que sentirse instantaneo.
			lastSendClock = 0
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isFiring = false
		end
	end)

	-- Soltar el boton fuera de la ventana deja el disparo trabado sin esto.
	UserInputService.WindowFocusReleased:Connect(function()
		isFiring = false
	end)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Input.Value + 2, update)
end

return InputController

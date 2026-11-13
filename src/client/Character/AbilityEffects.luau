--!strict
--[[
	AbilityEffects: lo que el CLIENTE hace cuando el servidor confirma una habilidad.

	Hoy tiene un solo caso real, el Dash, y existe por un motivo tecnico concreto: el
	cliente es el dueno de red de su propio personaje. Un empujon escrito desde el
	servidor sobre una assembly que posee el cliente se pisa con el siguiente paquete
	de fisica del cliente; y aunque no se pisara, esperar un round-trip para moverse
	arruina justo la habilidad que mas depende del timing.

	Que NO se decide aca: si la habilidad se puede usar, cuanta energia cuesta, cuando
	vuelve a estar lista y si el jugador es invulnerable. Todo eso ya lo resolvio
	AbilityService en el servidor; cuando llega `AbilityActivated`, la habilidad YA
	ocurrio. Esto solo la pinta.

	Doble Bonk y Sobrecarga no hacen nada aca: son flags que vive el servidor y se
	notan al disparar. Reciben el evento igual para que la Fase 8 les cuelgue FX sin
	tocar el servidor.

	El Dash usa velocidad directa y no un impulso escalado por masa a proposito: un
	impulso se suma a la velocidad que ya llevabas, asi que dashear corriendo llegaria
	mas lejos que dashear parado y la habilidad no se podria calibrar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local AimProvider = require(script.Parent.Parent.Input.AimProvider)

local AbilityEffects = {
	name = "AbilityEffects",
}

local player = Players.LocalPlayer

local function getRoot(): BasePart?
	local character = player.Character

	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

local function applyDash(payload: Types.AbilityActivatedPayload): ()
	local root = getRoot()

	if not root then
		return
	end

	local speed = payload.impulseSpeed

	if not speed then
		return
	end

	-- Se prefiere la mira local a la direccion que mando el servidor: es la misma
	-- intencion pero sin el retraso de la replicacion de la rotacion. La direccion
	-- del dash no es una frontera de seguridad (el jugador ya controla su propia
	-- fisica); lo que si controla el servidor es que el dash se pueda usar y por
	-- cuanto tiempo sos invulnerable.
	local direction = AimProvider.getAimDirection()

	if direction.Magnitude < 1e-3 then
		direction = payload.direction or root.CFrame.LookVector
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)

	if flat.Magnitude < 1e-3 then
		return
	end

	local horizontal = flat.Unit * speed

	-- Se conserva la componente vertical: pisar el acelerador no debe cancelar la
	-- gravedad ni pegar al personaje contra el piso.
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, root.AssemblyLinearVelocity.Y, horizontal.Z)
end

function AbilityEffects.start(): ()
	Remotes.event("AbilityActivated").OnClientEvent:Connect(function(payload: Types.AbilityActivatedPayload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.kind == "Dash" then
			applyDash(payload)
		end
		-- DualWield y RapidFire: nada que pintar todavia (Fase 8).
	end)
end

return AbilityEffects

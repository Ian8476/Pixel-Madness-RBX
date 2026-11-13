--!strict
--[[
	PortalService: decide cuando el grupo baja al siguiente piso.

	Regla de diseno (documento de contexto): hace falta que TODOS los jugadores VIVOS
	esten parados en el portal. En solitario eso es trivialmente "vos"; en co-op evita
	el problema social real de que uno solo arrastre a los otros a mitad de pelea.

	Por que la condicion es "todos los vivos" y no "todos": un caido en la Fase 6 no
	puede caminar hasta el portal, y exigirselo dejaria al grupo encerrado en el piso.

	La deteccion es una consulta de DISTANCIA en un tick lento (5 Hz), no un `Touched`
	ni un bucle por frame: la posicion de cuatro jugadores contra un punto es
	aritmetica barata, y a 5 Hz el jugador no nota la diferencia contra 60.

	FASE 6 le agrega la variante por mayoria con countdown de 10 s, que el documento
	deja como alternativa. Se implementa la regla estricta primero porque es la que no
	necesita UI para entenderse.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)

local CharacterService = require(script.Parent.Parent.Characters.CharacterService)
local GameService = require(script.Parent.Parent.Core.GameService)

local CHECK_INTERVAL_SECONDS = 0.2
local RADIUS = Constants.PORTAL_ACTIVATION_RADIUS_STUDS

local log = Logger.new("PortalService")

local PortalService = {
	name = "PortalService",
}

local accumulator = 0
local heartbeatConnection: RBXScriptConnection? = nil
-- Evita que dos ticks seguidos disparen dos cambios de piso mientras el primero
-- todavia esta generando geometria.
local isTransitioning = false

local function distanceToPortal(player: Player, portalPosition: Vector3): number?
	local character = player.Character

	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return nil
	end

	return (root.Position - portalPosition).Magnitude
end

local function step(deltaTime: number): ()
	accumulator += deltaTime

	if accumulator < CHECK_INTERVAL_SECONDS then
		return
	end

	accumulator = 0

	if isTransitioning then
		return
	end

	local floor = GameService.getCurrentFloor()
	local portal = if floor then floor.portal else nil

	if not portal or GameService.getPhase() ~= "InRun" then
		return
	end

	local portalPosition = portal.Position
	local aliveCount = 0
	local readyCount = 0

	for _, player in Players:GetPlayers() do
		if not CharacterService.isAlive(player) then
			continue
		end

		aliveCount += 1

		local distance = distanceToPortal(player, portalPosition)

		if distance and distance <= RADIUS then
			readyCount += 1
		end
	end

	-- Sin nadie vivo no se avanza: eso lo resuelve la derrota (Fase 4), no el portal.
	if aliveCount == 0 or readyCount < aliveCount then
		return
	end

	isTransitioning = true

	log:info("Portal activado por %d jugador(es)", readyCount)

	GameService.nextFloor()

	-- La pausa cubre el hueco entre "se genero el piso" y "las posiciones de los
	-- personajes ya reflejan el teleport". Sin ella, un tick que leyera posiciones
	-- viejas podria contar a todos como listos otra vez.
	task.delay(1.5, function()
		isTransitioning = false
	end)
end

function PortalService.start(): ()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(step)
end

return PortalService

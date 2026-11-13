--!strict
--[[
	EnemyFactory: arma el cuerpo de un enemigo. Nada mas.

	Es un greybox construido en codigo, por el mismo motivo que las salas (ver
	`RoomBuilder`): el enemigo entero sale de Git y no de un `.rbxl` sin diff. Cuando
	haya modelos de verdad, esta funcion pasa a clonar un Model de
	`ReplicatedStorage/Assets/Enemies` y nadie mas se entera.

	EL RIG MINIMO Y POR QUE ES ASI:
	un Humanoid solo necesita una parte llamada `HumanoidRootPart` para caminar. No
	hace falta un R6 completo. Se le agrega una cabeza chica porque en top-down el
	enemigo se reconoce por SILUETA, y un cubo pelado y un cubo con cabeza se
	distinguen de un vistazo aunque tengan el mismo color.

	`RequiresNeck = false` es obligatorio en un rig sin cuello: sin eso, el Humanoid se
	mata solo a los pocos segundos buscando una articulacion que no existe.

	`SetNetworkOwner(nil)` va SIEMPRE y va al final (necesita la parte ya en el
	workspace y sin anclar). Es la trampa de Roblox documentada en el README: sin eso,
	el servidor le regala la simulacion al cliente mas cercano, y ademas de jitter, un
	exploiter podria mover los enemigos.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Logger = require(Shared.Logger)
local Tags = require(Shared.Tags)
local Types = require(Shared.Types)

local BODY_SIZE = Vector3.new(2.6, 3, 2.6)
local HEAD_SIZE = Vector3.new(1.4, 1.4, 1.4)
-- OJO CON ESTE NUMERO: `HipHeight` es la distancia entre la BASE del RootPart y el
-- piso, no la altura del personaje. Como en este rig el RootPart ES el cuerpo (no hay
-- piernas), tiene que ser casi cero: un valor proporcional al cuerpo dejaria al
-- Bonkaron (escala 2.5) flotando varios studs sobre el suelo.
local GROUND_CLEARANCE_STUDS = 0.2

local log = Logger.new("EnemyFactory")

local EnemyFactory = {}

export type Rig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
}

local function newPart(name: string, size: Vector3, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")

	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

--[[
	Construye el cuerpo en `position` y lo deja simulado por el servidor.
	Devuelve nil si algo falla, en vez de dejar un enemigo a medio armar suelto.
]]
function EnemyFactory.build(definition: Types.EnemyDef, position: Vector3, parent: Instance): Rig?
	local scale = definition.modelScale
	local color = Color3.fromRGB(definition.greyboxColor.r, definition.greyboxColor.g, definition.greyboxColor.b)

	local model = Instance.new("Model")
	model.Name = definition.id

	local bodySize = BODY_SIZE * scale

	-- El nombre NO es decorativo: el Humanoid busca literalmente "HumanoidRootPart".
	local root = newPart("HumanoidRootPart", bodySize, color, model)
	root.CanCollide = true

	local head = newPart("Head", HEAD_SIZE * scale, color:Lerp(Color3.new(0, 0, 0), 0.35), model)
	head.CFrame = root.CFrame * CFrame.new(0, bodySize.Y / 2 + HEAD_SIZE.Y * scale / 2, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	local clearance = GROUND_CLEARANCE_STUDS * scale

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = definition.walkSpeed
	humanoid.RequiresNeck = false
	humanoid.HipHeight = clearance
	humanoid.BreakJointsOnDeath = false
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	-- Inmortal: la vida de verdad la lleva nuestro modulo Health, y este Humanoid es
	-- solo el actuador que muere para heredar gratis la animacion (decision D2).
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.Parent = model

	model.PrimaryPart = root
	-- El pivote es el centro del cuerpo: se lo sube media altura mas el despeje para
	-- que nazca apoyado en el piso y no medio enterrado.
	model:PivotTo(CFrame.new(position + Vector3.new(0, bodySize.Y / 2 + clearance, 0)))
	model.Parent = parent

	CollisionGroups.applyToModel(model, CollisionGroups.Names.EnemyChar)
	CollectionService:AddTag(model, Tags.Enemy)

	if definition.isBoss then
		CollectionService:AddTag(model, Tags.Boss)
	end

	-- Al final y con pcall: si la parte se destruyo entre medio (sala despawneada en
	-- el mismo frame), esto tira error y no queremos que se lleve puesto al spawner.
	local ok, err = pcall(function()
		root:SetNetworkOwner(nil)
	end)

	if not ok then
		log:warn("No se pudo fijar el network owner de %s: %s", definition.id, tostring(err))
	end

	return {
		model = model,
		root = root,
		humanoid = humanoid,
	}
end

return table.freeze(EnemyFactory)

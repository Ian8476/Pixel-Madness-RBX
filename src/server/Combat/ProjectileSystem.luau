--!strict
--[[
	ProjectileSystem: TODAS las balas del juego, en un solo Heartbeat.

	Decisiones que definen este modulo:

	1. NO se usa `Touched`. A 66 studs/s una bala avanza mas de 1 stud por frame y
	   `Touched` se pierde impactos de forma no determinista. Se usa un raycast del
	   segmento recorrido en el frame (posicion anterior -> posicion nueva), que no
	   puede atravesar nada por rapido que vaya.

	2. NO hay un Script por bala. Hay una tabla y un bucle. Con 4 jugadores, La
	   Cotorra a 10 disparos/s y una sala llena de Shooters, un Script por bala son
	   cientos de corrutinas; una tabla son cientos de entradas.

	3. Las Parts van ancladas, con CanCollide y CanQuery en false, y se mueven con
	   `BulkMoveTo` en una sola llamada por frame. Son puramente visuales: la verdad
	   de donde esta la bala vive en la tabla, no en la Part.

	4. El filtrado de a quien puede golpear se delega a `RaycastParams.CollisionGroup`.
	   Como la matriz dice que PlayerBullet no colisiona con PlayerChar, el raycast de
	   una bala del jugador simplemente no ve a los jugadores. Cero `if` de bando.

	MVP: la Part la crea y replica el servidor (gratis). La migracion a balas visuales
	en cliente es la Fase 8 y SOLO si el profiler o el playtest lo piden (decision D3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.CollisionGroups)
local Constants = require(Shared.Constants)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)
local SpreadMath = require(Shared.Logic.SpreadMath)
local Tags = require(Shared.Tags)

local HealthRegistry = require(script.Parent.HealthRegistry)

local CollectionService = game:GetService("CollectionService")

local log = Logger.new("ProjectileSystem")

export type ProjectileTeam = "Player" | "Enemy"

export type ProjectileSpec = {
	origin: Vector3,
	direction: Vector3, -- se normaliza y se aplana internamente
	speed: number,
	damage: number,
	knockback: number,
	isPiercing: boolean,
	scale: number,
	color: Color3,
	team: ProjectileTeam,
	owner: Player?,
}

type Projectile = {
	part: BasePart,
	position: Vector3,
	direction: Vector3,
	speed: number,
	damage: number,
	knockback: number,
	isPiercing: boolean,
	team: ProjectileTeam,
	owner: Player?,
	expiresAt: number,
	-- Solo relevante en balas piercing: evita que la misma bala golpee al mismo
	-- enemigo dos veces si el raycast lo vuelve a encontrar en el frame siguiente.
	alreadyHit: { [Instance]: true },
}

local BASE_PROJECTILE_SIZE = Vector3.new(0.8, 0.8, 1.6)

local ProjectileSystem = {
	name = "ProjectileSystem",
}

local projectiles: { Projectile } = {}
local container: Folder? = nil
local heartbeatConnection: RBXScriptConnection? = nil

local function getContainer(): Folder
	if container then
		return container
	end

	local folder = Instance.new("Folder")
	folder.Name = "Projectiles"
	folder.Parent = workspace

	container = folder

	return folder
end

local function collisionGroupFor(team: ProjectileTeam): CollisionGroups.CollisionGroupName
	return if team == "Player" then CollisionGroups.Names.PlayerBullet else CollisionGroups.Names.EnemyBullet
end

local function createPart(spec: ProjectileSpec): BasePart
	local part = Instance.new("Part")

	part.Name = "Projectile"
	part.Size = BASE_PROJECTILE_SIZE * spec.scale
	part.Shape = Enum.PartType.Block
	part.Material = Enum.Material.Neon
	part.Color = spec.color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- que no se golpeen entre si ni aparezcan en otros raycasts
	part.CanTouch = false
	part.CastShadow = false
	part.CollisionGroup = collisionGroupFor(spec.team)
	part.CFrame = CFrame.lookAt(spec.origin, spec.origin + spec.direction)

	CollectionService:AddTag(part, Tags.Bullet)
	part.Parent = getContainer()

	return part
end

local function applyKnockback(entity: Instance, direction: Vector3, knockback: number): ()
	if knockback <= 0 then
		return
	end

	local model = entity :: any

	if not model:IsA("Model") then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") or root.Anchored then
		return
	end

	-- Impulso, no velocidad: se suma al movimiento del enemigo en vez de reemplazarlo,
	-- asi un enemigo pesado se mueve menos que uno liviano sin codigo extra.
	root:ApplyImpulse(direction * knockback * root.AssemblyMass)
end

--[[
	Resuelve un impacto. Devuelve true si la bala debe seguir viva (piercing sobre
	un enemigo), false si tiene que morir aqui.
]]
local function resolveHit(projectile: Projectile, result: RaycastResult): boolean
	local health, entity = HealthRegistry.findFromPart(result.Instance)

	if not health or not entity then
		-- Pared, piso o decorado: la bala muere donde golpeo.
		return false
	end

	if projectile.alreadyHit[entity] then
		return true
	end

	projectile.alreadyHit[entity] = true

	local applied = health:damage(projectile.damage, projectile.owner or projectile.part)

	if applied > 0 then
		applyKnockback(entity, projectile.direction, projectile.knockback)

		-- El popup lo pinta el cliente: el servidor no sabe que existe una UI (regla 2).
		Remotes.unreliable("DamageDealt"):FireAllClients({
			position = result.Position,
			amount = applied,
		})
	end

	return projectile.isPiercing
end

local function destroyProjectile(projectile: Projectile): ()
	projectile.part:Destroy()
end

local function step(deltaTime: number): ()
	if #projectiles == 0 then
		return
	end

	local now = os.clock()
	local survivors: { Projectile } = table.create(#projectiles)
	local partsToMove: { BasePart } = table.create(#projectiles)
	local cframesToApply: { CFrame } = table.create(#projectiles)

	for _, projectile in projectiles do
		if now >= projectile.expiresAt then
			destroyProjectile(projectile)
			continue
		end

		local travel = projectile.direction * projectile.speed * deltaTime
		local nextPosition = projectile.position + travel

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { getContainer() }
		params.CollisionGroup = collisionGroupFor(projectile.team)
		params.IgnoreWater = true

		local result = workspace:Raycast(projectile.position, travel, params)
		local alive = true

		if result then
			alive = resolveHit(projectile, result)

			if not alive then
				-- Morir EN el punto de impacto, no un frame mas adelante dentro de la pared.
				nextPosition = result.Position
			end
		end

		if not alive then
			projectile.part.CFrame = CFrame.lookAt(nextPosition, nextPosition + projectile.direction)
			destroyProjectile(projectile)
			continue
		end

		projectile.position = nextPosition

		table.insert(survivors, projectile)
		table.insert(partsToMove, projectile.part)
		table.insert(cframesToApply, CFrame.lookAt(nextPosition, nextPosition + projectile.direction))
	end

	projectiles = survivors

	if #partsToMove > 0 then
		-- Una sola llamada al motor para mover todas las balas del frame.
		workspace:BulkMoveTo(partsToMove, cframesToApply, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--[[ Lanza una bala. Normaliza y aplana la direccion: el juego es top-down. ]]
function ProjectileSystem.spawn(spec: ProjectileSpec): ()
	local flat = Vector3.new(spec.direction.X, 0, spec.direction.Z)

	if flat.Magnitude < 1e-4 then
		log:warn("Direccion de proyectil degenerada, disparo descartado")
		return
	end

	local normalized = flat.Unit
	local resolvedSpec = table.clone(spec)
	resolvedSpec.direction = normalized

	local projectile: Projectile = {
		part = createPart(resolvedSpec),
		position = spec.origin,
		direction = normalized,
		speed = spec.speed,
		damage = spec.damage,
		knockback = spec.knockback,
		isPiercing = spec.isPiercing,
		team = spec.team,
		owner = spec.owner,
		expiresAt = os.clock() + Constants.PROJECTILE_MAX_LIFETIME_SECONDS,
		alreadyHit = {},
	}

	table.insert(projectiles, projectile)
end

--[[
	Lanza una salva en abanico. El calculo del abanico vive en SpreadMath (puro y
	testeado); aqui solo se traduce cada angulo a una direccion.
]]
function ProjectileSystem.spawnVolley(
	spec: ProjectileSpec,
	projectileCount: number,
	spreadDegrees: number,
	nextUnitRandom: () -> number
): ()
	local baseAngles = SpreadMath.fanAngles(projectileCount, spreadDegrees)
	local angles = SpreadMath.applyJitter(baseAngles, Constants.PROJECTILE_SPREAD_JITTER_DEGREES, nextUnitRandom)

	for _, angle in angles do
		local x, z = SpreadMath.rotateHorizontal(spec.direction.X, spec.direction.Z, angle)
		local rotated = table.clone(spec)
		rotated.direction = Vector3.new(x, 0, z)

		ProjectileSystem.spawn(rotated)
	end
end

function ProjectileSystem.getActiveCount(): number
	return #projectiles
end

function ProjectileSystem.start(): ()
	if heartbeatConnection then
		return
	end

	getContainer()
	heartbeatConnection = RunService.Heartbeat:Connect(step)
end

return ProjectileSystem

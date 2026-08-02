--!strict
--[[
	CollisionGroups: nombres de grupos de colision + registro idempotente de la matriz.

	Por que registrar en codigo y no en el editor de Collision Groups de Studio:
	el place debe ser reconstruible desde el repo. Si la matriz vive en el .rbxl, el
	dia que alguien la toque no habra diff, ni PR, ni forma de saber quien la rompio.
	Aqui hay una sola fuente de verdad, versionada y revisable.

	Detalle importante de por que esto importa tanto en PixelMadness: las balas son
	Parts con CanCollide=false y CanQuery=false, o sea que la matriz NO se usa para
	fisica de balas. Se usa para el filtrado de RaycastParams.CollisionGroup: el
	raycast segmentado del ProjectileSystem hereda estas reglas, asi que "PlayerBullet
	no colisiona con PlayerChar" significa "la bala del jugador no puede impactar al
	jugador", que es exactamente el comportamiento que queremos y sale gratis.
]]

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local CollisionGroups = table.freeze({
	Default = "Default" :: "Default",
	PlayerChar = "PlayerChar" :: "PlayerChar",
	EnemyChar = "EnemyChar" :: "EnemyChar",
	PlayerBullet = "PlayerBullet" :: "PlayerBullet",
	EnemyBullet = "EnemyBullet" :: "EnemyBullet",
	Ghost = "Ghost" :: "Ghost", -- monedas y pickups: no chocan con nada, se detectan por consulta espacial
})

export type CollisionGroupName = "Default" | "PlayerChar" | "EnemyChar" | "PlayerBullet" | "EnemyBullet" | "Ghost"

-- Grupos que este proyecto registra (Default ya existe siempre, no se registra)
local MANAGED_GROUPS: { CollisionGroupName } = {
	CollisionGroups.PlayerChar,
	CollisionGroups.EnemyChar,
	CollisionGroups.PlayerBullet,
	CollisionGroups.EnemyBullet,
	CollisionGroups.Ghost,
}

type CollisionRule = {
	a: CollisionGroupName,
	b: CollisionGroupName,
	canCollide: boolean,
}

-- Solo se declaran las EXCEPCIONES: todo lo no listado colisiona (default de Roblox).
local RULES: { CollisionRule } = {
	-- Las balas del jugador no lastiman al jugador ni chocan entre si
	{ a = CollisionGroups.PlayerBullet, b = CollisionGroups.PlayerChar, canCollide = false },
	{ a = CollisionGroups.PlayerBullet, b = CollisionGroups.PlayerBullet, canCollide = false },

	-- Idem para el bando enemigo (fuego amigo entre enemigos rompe el ritmo del juego)
	{ a = CollisionGroups.EnemyBullet, b = CollisionGroups.EnemyChar, canCollide = false },
	{ a = CollisionGroups.EnemyBullet, b = CollisionGroups.EnemyBullet, canCollide = false },

	-- Las balas de bandos opuestos se atraviesan: en un bullet-hell top-down,
	-- balas que se anulan entre si son ilegibles para el jugador
	{ a = CollisionGroups.PlayerBullet, b = CollisionGroups.EnemyBullet, canCollide = false },

	-- Ghost (monedas, pickups) no colisiona con NADA, ni consigo mismo
	{ a = CollisionGroups.Ghost, b = CollisionGroups.Default, canCollide = false },
	{ a = CollisionGroups.Ghost, b = CollisionGroups.Ghost, canCollide = false },
	{ a = CollisionGroups.Ghost, b = CollisionGroups.PlayerChar, canCollide = false },
	{ a = CollisionGroups.Ghost, b = CollisionGroups.EnemyChar, canCollide = false },
	{ a = CollisionGroups.Ghost, b = CollisionGroups.PlayerBullet, canCollide = false },
	{ a = CollisionGroups.Ghost, b = CollisionGroups.EnemyBullet, canCollide = false },
}

local Registry = {}

local function buildRegisteredSet(): { [string]: true }
	local registered: { [string]: true } = {}

	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		registered[group.name] = true
	end

	return registered
end

--[[
	Registra grupos y aplica la matriz. Idempotente: se puede llamar mil veces.
	Solo servidor: PhysicsService es autoritativo y el cliente no debe tocar fisica global.
]]
function Registry.registerAll(): ()
	if not RunService:IsServer() then
		error("CollisionGroups.registerAll solo puede llamarse desde el servidor", 2)
	end

	local registered = buildRegisteredSet()

	for _, groupName in MANAGED_GROUPS do
		if not registered[groupName] then
			PhysicsService:RegisterCollisionGroup(groupName)
		end
	end

	for _, rule in RULES do
		PhysicsService:CollisionGroupSetCollidable(rule.a, rule.b, rule.canCollide)
	end
end

--[[
	Asigna un grupo a una Part y a todos sus descendientes BasePart.
	Utilidad chica pero repetida en todos los sistemas (personajes, enemigos, pickups).
]]
function Registry.applyToModel(root: Instance, groupName: CollisionGroupName): ()
	if root:IsA("BasePart") then
		root.CollisionGroup = groupName
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

Registry.Names = CollisionGroups

return table.freeze(Registry)

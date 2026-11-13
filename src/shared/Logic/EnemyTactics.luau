--!strict
--[[
	EnemyTactics: las decisiones de los enemigos, sin Instances de por medio.

	El cerebro de un enemigo son dos preguntas: a quien voy, y donde me paro. Las dos
	son geometria pura, asi que viven aca y se testean en CI. Lo que queda en el
	servidor (`EnemyBrains/`) es traducir la respuesta a `Humanoid:MoveTo`, que es lo
	unico que de verdad necesita a Roblox.

	REGLA DURA de la carpeta Logic/: cero `require`, cero API de Roblox. Por eso todo
	se pasa como numeros sueltos en vez de Vector3, y por eso el eje vertical no
	aparece: el juego es top-down y perseguir en Y no existe.
]]

export type Point = {
	x: number,
	z: number,
}

local EnemyTactics = {}

--[[
	Distancia al cuadrado. Se usa para COMPARAR sin pagar la raiz cuadrada: esto corre
	una vez por enemigo y por jugador en cada tick de decision, y con cuatro jugadores
	y una sala llena eso es varias decenas de veces por segundo.
]]
local function squaredDistance(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz

	return dx * dx + dz * dz
end

--[[
	Indice del objetivo mas cercano, o nil si no hay ninguno.

	Recibe ya filtrada la lista de objetivos VALIDOS (vivos, en la misma sala): decidir
	quien es valido es responsabilidad del servidor, que es el unico que sabe de vida y
	de salas. Aca solo se mide.

	En un empate exacto gana el primero de la lista. Es arbitrario pero DETERMINISTA, y
	eso importa: dos enemigos con la misma posicion deben elegir el mismo objetivo, si
	no se ven titubear entre dos jugadores.
]]
function EnemyTactics.nearestTargetIndex(originX: number, originZ: number, targets: { Point }): number?
	local bestIndex: number? = nil
	local bestDistance = math.huge

	for index, target in targets do
		local distance = squaredDistance(originX, originZ, target.x, target.z)

		if distance < bestDistance then
			bestDistance = distance
			bestIndex = index
		end
	end

	return bestIndex
end

--[[
	Donde quiere pararse un enemigo que mantiene distancia (el Shooter).

	Devuelve `(x, z, shouldMove)`. El punto ideal conserva el RUMBO actual respecto del
	objetivo y solo corrige la distancia: si el Shooter esta al norte del jugador, se
	queda al norte: no lo rodea. Rodear es una decision de diseno que hoy no queremos
	(un enemigo que orbita es dificil de leer en top-down con niebla).

	`tolerance` crea una banda muerta alrededor de la distancia preferida. Sin ella, el
	Shooter corrige un stud, se pasa, corrige de vuelta, y el resultado es un bicho
	temblando en el lugar en vez de uno plantado disparando.
]]
function EnemyTactics.preferredStandPoint(
	enemyX: number,
	enemyZ: number,
	targetX: number,
	targetZ: number,
	preferredDistance: number,
	tolerance: number
): (number, number, boolean)
	local dx = enemyX - targetX
	local dz = enemyZ - targetZ
	local distance = math.sqrt(dx * dx + dz * dz)

	-- Encima del objetivo: no hay rumbo que conservar. Se elige uno fijo en vez de
	-- dividir por cero; cual es no importa, que sea siempre el mismo si.
	if distance < 1e-4 then
		return targetX + preferredDistance, targetZ, true
	end

	if math.abs(distance - preferredDistance) <= tolerance then
		return enemyX, enemyZ, false
	end

	local scale = preferredDistance / distance

	return targetX + dx * scale, targetZ + dz * scale, true
end

--[[
	Direccion horizontal normalizada de un punto a otro, o nil si coinciden.
	La usan los Shooter para apuntar y el sistema de contacto para el knockback.
]]
function EnemyTactics.directionTo(fromX: number, fromZ: number, toX: number, toZ: number): (number?, number?)
	local dx = toX - fromX
	local dz = toZ - fromZ
	local length = math.sqrt(dx * dx + dz * dz)

	if length < 1e-4 then
		return nil, nil
	end

	return dx / length, dz / length
end

--[[ Distancia plana entre dos puntos. Ignora la altura: el juego es top-down. ]]
function EnemyTactics.flatDistance(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt(squaredDistance(ax, az, bx, bz))
end

return table.freeze(EnemyTactics)

--!strict
--[[
	RateLimiter: presupuesto de llamadas por jugador y por clave (token bucket).

	La estrategia anti-exploit del plan lo pide desde la Fase 1, y no se solapa con
	la validacion de cadencia del arma: esa dice "no podes disparar mas rapido que
	el arma", esta dice "no podes hacerme gastar CPU validando 5000 mensajes por
	segundo". Un cliente modificado que spamea un remote se frena aca, antes de que
	el servicio haga cualquier trabajo.

	Exceso = descarte silencioso. No se responde al cliente: contestarle le confirma
	al exploiter que encontro el limite y donde esta.
]]

local Players = game:GetService("Players")

type Bucket = {
	tokens: number,
	capacity: number,
	refillPerSecond: number,
	lastRefill: number,
}

type PlayerBuckets = { [string]: Bucket }

local buckets: { [Player]: PlayerBuckets } = {}

local RateLimiter = {
	name = "RateLimiter",
}

--[[
	Devuelve true si la llamada entra en presupuesto (y consume un token).

	`capacity` es cuantas llamadas se toleran en una rafaga; `refillPerSecond` es el
	ritmo sostenido. Para FireRequest, una capacidad algo mayor a la cadencia del arma
	mas rapida absorbe el jitter de red sin abrirle la puerta a nadie.
]]
function RateLimiter.consume(player: Player, key: string, capacity: number, refillPerSecond: number): boolean
	local playerBuckets = buckets[player]

	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local now = os.clock()
	local bucket = playerBuckets[key]

	if not bucket then
		bucket = {
			tokens = capacity,
			capacity = capacity,
			refillPerSecond = refillPerSecond,
			lastRefill = now,
		}
		playerBuckets[key] = bucket
	end

	bucket.tokens = math.min(bucket.capacity, bucket.tokens + (now - bucket.lastRefill) * bucket.refillPerSecond)
	bucket.lastRefill = now

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1

	return true
end

function RateLimiter.start(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
end

return RateLimiter

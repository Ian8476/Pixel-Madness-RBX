--!strict
--[[
	SpreadMath: abanico de disparo. Logica pura, sin `require` ni API de Roblox.

	Adelantado de la Fase 2 porque ProjectileSystem lo necesita ya: escribirlo despues
	habria significado reescribir el sistema de proyectiles al mes siguiente.

	El azar se INYECTA como funcion (`nextUnitRandom: () -> number` en [0, 1)) en vez
	de usar `Random.new()`. Dos motivos: `Random` es un datatype de Roblox y romperia
	la regla de la carpeta, y ademas permite testear el jitter con una secuencia fija
	en vez de rezarle a la estadistica.
]]

local SpreadMath = {}

--[[
	Angulos de un abanico uniforme, en grados, centrados en 0.

	1 proyectil  -> { 0 }
	6 en 35 grados -> { -17.5, -10.5, -3.5, 3.5, 10.5, 17.5 }  (La Escupechatarra)

	Nota de diseno: con N proyectiles los extremos caen EXACTAMENTE en +/- spread/2.
	La alternativa (repartir en N sectores y usar sus centros) deja el abanico mas
	angosto de lo que dice el numero del arma, y "35 grados" tiene que significar 35.
]]
function SpreadMath.fanAngles(projectileCount: number, totalSpreadDegrees: number): { number }
	if projectileCount < 1 or projectileCount % 1 ~= 0 then
		error(string.format("SpreadMath: projectileCount debe ser un entero >= 1, recibido %s", tostring(projectileCount)), 2)
	end

	if totalSpreadDegrees < 0 then
		error(string.format("SpreadMath: totalSpreadDegrees no puede ser negativo, recibido %s", tostring(totalSpreadDegrees)), 2)
	end

	if projectileCount == 1 then
		return { 0 }
	end

	local angles = table.create(projectileCount)
	local step = totalSpreadDegrees / (projectileCount - 1)
	local start = -totalSpreadDegrees / 2

	for index = 1, projectileCount do
		table.insert(angles, start + step * (index - 1))
	end

	return angles
end

--[[
	Aplica jitter simetrico a cada angulo. Devuelve una tabla nueva: el abanico base
	es determinista y se puede cachear por arma, el jitter es por disparo.
]]
function SpreadMath.applyJitter(angles: { number }, jitterDegrees: number, nextUnitRandom: () -> number): { number }
	if jitterDegrees <= 0 then
		return table.clone(angles)
	end

	local jittered = table.create(#angles)

	for _, angle in angles do
		local unit = nextUnitRandom()
		table.insert(jittered, angle + (unit * 2 - 1) * jitterDegrees)
	end

	return jittered
end

--[[
	Rota un vector director horizontal por un angulo en grados alrededor del eje Y.
	Trabaja sobre componentes x/z sueltas para no depender de Vector3 ni de CFrame.
]]
function SpreadMath.rotateHorizontal(x: number, z: number, angleDegrees: number): (number, number)
	local radians = math.rad(angleDegrees)
	local cosine = math.cos(radians)
	local sine = math.sin(radians)

	return x * cosine - z * sine, x * sine + z * cosine
end

return table.freeze(SpreadMath)

--!strict
--[[
	LobbyRules: cuando arranca una run.

	Es poco codigo y aun asi merece vivir aca y tener tests, porque las reglas de
	arranque son de las que se rompen en silencio y de la peor manera: un servidor que
	arranca una run con cero jugadores queda con una mazmorra girando sola, y uno que
	no arranca nunca deja a la gente mirando un boton que no hace nada. Ninguno de los
	dos tira un error.

	REGLA DURA de la carpeta Logic/: cero `require`, cero API de Roblox.
]]

local LobbyRules = {}

--[[
	True si la cuenta atras debe estar corriendo.

	Hoy la condicion es "todos los conectados listos". La alternativa que deja abierta
	el documento de contexto (mayoria + countdown largo) se decide en la fase de co-op,
	con gente de verdad esperandose: es una decision social, no tecnica, y no se puede
	tomar bien sin verla pasar.

	El caso de cero jugadores esta primero y es el importante: un servidor vacio NUNCA
	arranca una run. Sin esta guarda, `readyCount >= playerCount` da true con 0 y 0.
]]
function LobbyRules.shouldCountdown(playerCount: number, readyCount: number): boolean
	if playerCount < 1 then
		return false
	end

	return readyCount >= playerCount
end

--[[
	Cuantos faltan para arrancar. Se expone como funcion propia y no se calcula en la
	UI para que el texto del lobby y la decision de arrancar no puedan discrepar.
]]
function LobbyRules.remainingToStart(playerCount: number, readyCount: number): number
	if playerCount < 1 then
		return 0
	end

	return math.max(0, playerCount - readyCount)
end

return table.freeze(LobbyRules)

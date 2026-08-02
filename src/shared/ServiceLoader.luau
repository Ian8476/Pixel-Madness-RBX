--!strict
--[[
	ServiceLoader: arranque explicito y ordenado de servicios, en dos fases.

	Movido de server/Core/ a shared/ en la Fase 1: el cliente necesita exactamente
	el mismo mecanismo y duplicarlo habria sido peor que compartirlo.

	Por que dos fases (init y start) y no una:
	`init` es cableado - crear estado, suscribirse a signals de otros servicios.
	`start` es comportamiento - abrir Heartbeats, escuchar remotes, spawnear cosas.

	Con una sola fase, el servicio A que se suscribe a una signal del servicio B
	falla si A carga antes que B, y "arreglarlo" significa reordenar la lista a mano
	hasta que deje de romperse. Con dos fases, TODOS los init corren antes que
	cualquier start, asi que el cableado nunca depende del orden. Solo el orden de
	los `start` importa, y ese si es una decision explicita del bootstrap.

	Este modulo deliberadamente NO descubre servicios recorriendo carpetas. El orden
	de arranque es una decision de diseno que se lee en el bootstrap, no un efecto
	secundario del orden alfabetico de los archivos.
]]

local Logger = require(script.Parent.Logger)

export type Service = {
	name: string,
	init: (() -> ())?,
	start: (() -> ())?,
}

local log = Logger.new("ServiceLoader")

local ServiceLoader = {}

local function runPhase(service: Service, phaseName: string, phase: (() -> ())?): ()
	if not phase then
		return
	end

	local ok, err = xpcall(phase, debug.traceback)

	if not ok then
		-- Fallar ruidoso y temprano: un servicio a medio arrancar produce bugs
		-- mucho mas caros de diagnosticar que un servidor que no levanta.
		error(string.format("ServiceLoader: %s.%s() fallo\n%s", service.name, phaseName, tostring(err)), 0)
	end
end

--[[ Corre init() de todos y despues start() de todos, en el orden recibido. ]]
function ServiceLoader.bootstrap(services: { Service }): ()
	local startClock = os.clock()

	for _, service in services do
		runPhase(service, "init", service.init)
	end

	for _, service in services do
		runPhase(service, "start", service.start)
	end

	log:info("%d servicios arrancados en %.1f ms", #services, (os.clock() - startClock) * 1000)
end

return table.freeze(ServiceLoader)

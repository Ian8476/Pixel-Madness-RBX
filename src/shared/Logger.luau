--!strict
--[[
	Logger: salida con prefijo de modulo y contexto (SERVER/CLIENT).

	Existe por una razon muy concreta: en co-op vas a estar leyendo el Output con
	un servidor y hasta 4 clientes escupiendo lineas a la vez. Sin prefijo no se
	entiende nada. Con prefijo, "[SERVER][WeaponService]" te dice de inmediato
	quien hablo y desde donde.
]]

local RunService = game:GetService("RunService")

local CONTEXT = if RunService:IsServer() then "SERVER" else "CLIENT"

export type Logger = {
	info: (self: Logger, message: string, ...any) -> (),
	warn: (self: Logger, message: string, ...any) -> (),
	fail: (self: Logger, message: string, ...any) -> (),
}

local LoggerFactory = {}

function LoggerFactory.new(moduleName: string): Logger
	local prefix = string.format("[%s][%s]", CONTEXT, moduleName)

	local function format(message: string, ...: any): string
		if select("#", ...) == 0 then
			return prefix .. " " .. message
		end

		return prefix .. " " .. string.format(message, ...)
	end

	local logger = {}

	function logger:info(message: string, ...: any): ()
		print(format(message, ...))
	end

	function logger:warn(message: string, ...: any): ()
		warn(format(message, ...))
	end

	-- Se llama `fail` y no `error` para no sugerir que corta la ejecucion: solo reporta.
	function logger:fail(message: string, ...: any): ()
		warn(format(message, ...))
	end

	return logger :: Logger
end

return table.freeze(LoggerFactory)

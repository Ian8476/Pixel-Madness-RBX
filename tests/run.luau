--!strict
--[[
	Punto de entrada de los tests bajo Lune.  Uso: `lune run tests/run`

	Las specs se listan a mano y no por descubrimiento automatico de archivos:
	agregar una spec nueva es una linea, y a cambio el orden es determinista y
	un archivo mal nombrado se nota al instante en vez de dejar de correr en silencio.
]]

local process = require("@lune/process")

local Runner = require("./Runner")

local specs = {
	require("./specs/Constants.spec"),
	require("./specs/DifficultyMath.spec"),
	require("./specs/SpreadMath.spec"),
}

print("PixelMadness :: tests de logica pura\n")

local allPassed = Runner.run(specs)

process.exit(if allPassed then 0 else 1)

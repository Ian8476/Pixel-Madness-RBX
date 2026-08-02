--!strict
--[[
	Bootstrap del cliente: el unico LocalScript del contexto cliente.

	El orden refleja el flujo de un frame: primero se calcula hacia donde se apunta,
	despues se gira el cuerpo, despues se encuadra la camara, y al final se traduce
	el input en intenciones. Cada modulo se engancha a RenderStep con la prioridad que
	le corresponde, asi que el orden de arranque solo decide quien queda registrado,
	no quien corre primero - pero leerlo en este orden hace evidente la cadena.

	El cliente nunca calcula vida, energia, monedas ni dano: envia intenciones y pinta
	lo que el servidor le replica (regla 5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ServiceLoader = require(Shared:WaitForChild("ServiceLoader"))

local AimProvider = require(script.Parent.Input.AimProvider)
local CharacterFacing = require(script.Parent.Character.CharacterFacing)
local DamagePopups = require(script.Parent.FX.DamagePopups)
local InputController = require(script.Parent.Input.InputController)
local TopDownCamera = require(script.Parent.Camera.TopDownCamera)

local log = Logger.new("Bootstrap")

-- Falla ruidosamente si el servidor no publico los remotes: mejor un error claro al
-- arrancar que un juego mudo en el que nada responde.
Remotes.event("FireRequest")

ServiceLoader.bootstrap({
	AimProvider,
	CharacterFacing,
	TopDownCamera,
	InputController,
	DamagePopups,
})

log:info("Cliente listo")

--!strict
--[[
	Bootstrap del cliente: el unico LocalScript del contexto cliente.

	El orden refleja el flujo de un frame: primero se encuadra la camara, despues se
	calcula hacia donde se apunta (que ahora sale del centro de la pantalla, o sea de la
	camara), despues se gira el cuerpo, y al final se traduce el input en intenciones.
	Cada modulo se engancha a RenderStep con la prioridad que le corresponde, asi que el
	orden de arranque solo decide quien queda registrado, no quien corre primero - pero
	leerlo en este orden hace evidente la cadena.

	La cadena se invirtio con la camara de shooter: antes la camara seguia a la mira
	(look-ahead hacia el cursor), ahora la mira sale de la camara.

	El cliente nunca calcula vida, energia, monedas ni dano: envia intenciones y pinta
	lo que el servidor le replica (regla 5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ServiceLoader = require(Shared:WaitForChild("ServiceLoader"))

local AbilityEffects = require(script.Parent.Character.AbilityEffects)
local AimProvider = require(script.Parent.Input.AimProvider)
local CharacterFacing = require(script.Parent.Character.CharacterFacing)
local ClientState = require(script.Parent.State.ClientState)
local CombatFeedback = require(script.Parent.FX.CombatFeedback)
local DamagePopups = require(script.Parent.FX.DamagePopups)
local InputController = require(script.Parent.Input.InputController)
local LootView = require(script.Parent.FX.LootView)
local PickupView = require(script.Parent.FX.PickupView)
local ShooterCamera = require(script.Parent.Camera.ShooterCamera)
local SoundController = require(script.Parent.Audio.SoundController)
local UIController = require(script.Parent.UI.UIController)

local log = Logger.new("Bootstrap")

-- Falla ruidosamente si el servidor no publico los remotes: mejor un error claro al
-- arrancar que un juego mudo en el que nada responde.
Remotes.event("FireRequest")

-- ClientState arranca PRIMERO: es la cache de lo que el servidor dice de nosotros, y
-- InputController la lee para saber a que ritmo mandar sus intenciones. Empezar a
-- escuchar antes de que llegue el primer snapshot evita perderselo.
-- SoundController va enseguida: la UI y CombatFeedback le piden sonidos desde su start.
ServiceLoader.bootstrap({
	ClientState,
	SoundController,
	CombatFeedback,
	UIController,
	ShooterCamera,
	AimProvider,
	CharacterFacing,
	InputController,
	AbilityEffects,
	DamagePopups,
	PickupView,
	LootView,
})

log:info("Cliente listo")

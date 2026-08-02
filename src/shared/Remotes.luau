--!strict
--[[
	Remotes: la UNICA frontera cliente-servidor del proyecto.

	Regla del documento de contexto: ningun otro archivo crea RemoteEvents.
	El motivo no es estetico. Cuando los remotes se crean donde haga falta, terminas
	con dos sistemas creando "FireRequest" en carpetas distintas, con un cliente
	escuchando el que no es y un bug que solo aparece con dos jugadores conectados.

	Contrato completo (documento de contexto, seccion 4):

	| Remote               | Direccion | Validacion en servidor                          |
	|----------------------|-----------|--------------------------------------------------|
	| FireRequest          | C -> S    | cadencia, energia, vivo, vector unitario horizontal |
	| SwapWeapon           | C -> S    | tiene segunda arma                              |
	| PickupRequest        | C -> S    | tag valido, distancia <= 8 studs, vivo          |
	| UseAbility           | C -> S    | cooldown, costo, vivo                           |
	| SelectCharacter      | C -> S    | id existe, desbloqueado, fase = Lobby           |
	| SetReady             | C -> S    | fase = Lobby                                    |
	| RunStateChanged      | S -> C    | -                                               |
	| PlayerStatsChanged   | S -> dueno| -                                               |
	| DamageDealt          | S -> C    | unreliable, puro FX                             |
	| FXEvent              | S -> C    | unreliable, puro FX                             |

	Los payloads viven tipados en Types.luau. Este modulo entrega el transporte;
	la validacion es responsabilidad del servicio que escucha (SRP).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local CLIENT_WAIT_TIMEOUT_SECONDS = 15

export type ReliableEventName =
	"FireRequest"
	| "SwapWeapon"
	| "PickupRequest"
	| "UseAbility"
	| "SelectCharacter"
	| "SetReady"
	| "RunStateChanged"
	| "PlayerStatsChanged"

export type UnreliableEventName = "DamageDealt" | "FXEvent"

local RELIABLE_EVENTS: { ReliableEventName } = {
	"FireRequest",
	"SwapWeapon",
	"PickupRequest",
	"UseAbility",
	"SelectCharacter",
	"SetReady",
	"RunStateChanged",
	"PlayerStatsChanged",
}

-- Unreliable: FX puro. Si se pierde un paquete se pierde un popup de dano, no estado.
-- Nunca poner aqui nada que el cliente necesite para tener razon sobre el mundo.
local UNRELIABLE_EVENTS: { UnreliableEventName } = {
	"DamageDealt",
	"FXEvent",
}

local Remotes = {}

local cachedFolder: Folder? = nil

local function getFolder(): Folder
	if cachedFolder then
		return cachedFolder
	end

	local found: Instance?

	if RunService:IsServer() then
		found = ReplicatedStorage:FindFirstChild(FOLDER_NAME)

		if not found then
			error("Remotes: el servidor debe llamar Remotes.initServer() en el bootstrap antes de usar remotes", 3)
		end
	else
		found = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_WAIT_TIMEOUT_SECONDS)

		if not found then
			error(
				string.format(
					"Remotes: la carpeta %s no aparecio en %d segundos. Fallo el bootstrap del servidor?",
					FOLDER_NAME,
					CLIENT_WAIT_TIMEOUT_SECONDS
				),
				3
			)
		end
	end

	if not found:IsA("Folder") then
		error(string.format("Remotes: %s existe pero es un %s, no un Folder", FOLDER_NAME, found.ClassName), 3)
	end

	cachedFolder = found

	return found
end

local function resolve(name: string, expectedClass: string): Instance
	local folder = getFolder()
	local instance: Instance?

	if RunService:IsServer() then
		instance = folder:FindFirstChild(name)
	else
		instance = folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT_SECONDS)
	end

	if not instance then
		error(string.format("Remotes: no existe el remote %q. Esta declarado en Remotes.luau?", name), 3)
	end

	if not instance:IsA(expectedClass) then
		error(
			string.format("Remotes: %q es %s pero se esperaba %s", name, instance.ClassName, expectedClass),
			3
		)
	end

	return instance
end

--[[
	Crea la carpeta y todos los remotes declarados. Solo servidor, idempotente.
	Se llama UNA vez, temprano, desde el bootstrap: cualquier servicio que se
	registre despues encuentra los remotes listos y no necesita esperar.
]]
function Remotes.initServer(): ()
	if not RunService:IsServer() then
		error("Remotes.initServer solo puede llamarse desde el servidor", 2)
	end

	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	local folder: Folder

	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for _, name in RELIABLE_EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	for _, name in UNRELIABLE_EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	cachedFolder = folder
end

--[[ Remote confiable. El nombre esta tipado: un typo no compila. ]]
function Remotes.event(name: ReliableEventName): RemoteEvent
	return resolve(name, "RemoteEvent") :: RemoteEvent
end

--[[ Remote no confiable, solo para FX que puede perderse sin consecuencias. ]]
function Remotes.unreliable(name: UnreliableEventName): UnreliableRemoteEvent
	return resolve(name, "UnreliableRemoteEvent") :: UnreliableRemoteEvent
end

return table.freeze(Remotes)

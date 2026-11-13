--!strict
--[[
	ClientState: la copia local de lo que el servidor dice de MI jugador.

	Es una cache de solo lectura, nunca una fuente de verdad. Nada de este modulo
	decide dano, energia ni cooldowns: eso ya se decidio en el servidor y aca solo
	se guarda el ultimo snapshot que llego por `PlayerStatsChanged` (regla 5).

	Guarda las DOS replicas que manda el servidor y que el cliente puede necesitar:
	`PlayerStatsChanged` (lo que le pasa a mi personaje) y `RunStateChanged` (lo que le
	pasa a la partida). Son remotes distintos porque cambian a ritmos muy distintos:
	el primero diez veces por segundo, el segundo tres veces por run.

	Que exista este modulo en vez de que cada interesado abra su conexion al remote es
	lo que permite que InputController (ritmo de disparo), el HUD y la pantalla de
	seleccion lean el mismo estado sin coordinarse entre ellos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))
local Weapons = require(Shared:WaitForChild("Data"):WaitForChild("Weapons"))

local ClientState = {
	name = "ClientState",
}

-- (snapshot nuevo de MI personaje)
ClientState.changed = Signal.new() :: Signal.Signal<Types.PlayerStatsSnapshot>
-- (snapshot nuevo de la RUN: piso, fase, monedas del bote)
ClientState.runChanged = Signal.new() :: Signal.Signal<Types.RunStateSnapshot>

local current: Types.PlayerStatsSnapshot? = nil
local currentRun: Types.RunStateSnapshot? = nil

--[[ Ultimo snapshot recibido, o nil si el servidor todavia no mando ninguno. ]]
function ClientState.get(): Types.PlayerStatsSnapshot?
	return current
end

--[[ Ultimo estado de run recibido. ]]
function ClientState.getRun(): Types.RunStateSnapshot?
	return currentRun
end

--[[ Definicion del arma equipada, para lo que el cliente necesita PINTAR o RITMAR. ]]
function ClientState.getActiveWeapon(): Types.WeaponDef?
	local snapshot = current

	if not snapshot then
		return nil
	end

	local weaponId = if snapshot.activeSlot == 2 then snapshot.secondaryWeaponId else snapshot.primaryWeaponId

	return Weapons.getById(weaponId)
end

--[[ Multiplicador de cadencia vigente (Sobrecarga de Voltio). 1 si no hay snapshot. ]]
function ClientState.getFireRateMultiplier(): number
	local snapshot = current

	return if snapshot then snapshot.fireRateMultiplier else 1
end

function ClientState.start(): ()
	Remotes.event("PlayerStatsChanged").OnClientEvent:Connect(function(snapshot: Types.PlayerStatsSnapshot)
		current = snapshot
		ClientState.changed:fire(snapshot)
	end)

	Remotes.event("RunStateChanged").OnClientEvent:Connect(function(snapshot: Types.RunStateSnapshot)
		currentRun = snapshot
		ClientState.runChanged:fire(snapshot)
	end)
end

return ClientState

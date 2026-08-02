--!strict
--[[
	DevSpawnService: ANDAMIO TEMPORAL. Se borra en la Fase 4.

	Se redujo en la Fase 1: ahora hace UNA sola cosa, pedir que aparezca un cuerpo.
	Toda la configuracion del personaje (salto, rotacion, colision, Health, greybox)
	se mudo a CharacterService, que si es permanente.

	Lo que queda aqui es exactamente la decision que en la Fase 4 pasa a tomar
	GameService: CUANDO spawnea un jugador y donde (lobby o run). Mientras esa
	decision no exista, alguien tiene que llamar a LoadCharacter o no aparece nadie,
	porque el place tiene Players.CharacterAutoLoads = false.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Logger)

local log = Logger.new("DevSpawnService")

local DevSpawnService = {
	name = "DevSpawnService",
}

function DevSpawnService.start(): ()
	local function spawnPlayer(player: Player): ()
		player:LoadCharacter()
	end

	for _, player in Players:GetPlayers() do
		spawnPlayer(player)
	end

	Players.PlayerAdded:Connect(spawnPlayer)

	-- Sin respawn automatico no se puede probar la muerte mas de una vez.
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			task.delay(2, function()
				if player.Parent then
					player:LoadCharacter()
				end
			end)
		end)
	end)

	log:warn("Spawn de desarrollo activo. Borrar este servicio cuando GameService controle el spawn (Fase 4).")
end

return DevSpawnService

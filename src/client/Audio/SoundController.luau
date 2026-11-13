--!strict
--[[
	SoundController: el unico modulo que crea objetos `Sound`.

	Dos responsabilidades, las dos de "reproducir", ninguna de "decidir cuando":

	  1. Efectos (`play`, `playAt`). Quien sabe QUE paso (la UI, CombatFeedback) llama
	     con un nombre de `SoundLibrary`; este modulo sabe COMO suena. Asi un boton no
	     conoce un asset id y cambiar un sonido es tocar un solo dato.

	  2. Musica de fondo segun la fase de la run. Es la excepcion a "no decide": la
	     musica es puro estado (que pista corresponde AHORA), no un evento, y el estado
	     ya lo tiene ClientState. Lobby -> lobby, en la run -> run, jefe vivo -> boss,
	     fin de run -> silencio para que se luzca el jingle de Victoria o Derrota.

	Todo es local al cliente: nada de esto se replica ni le cuesta red al servidor.

	Sobre clonar en vez de reusar un Sound por nombre: el mismo efecto se superpone
	consigo mismo todo el tiempo (cinco monedas en medio segundo) y un Sound unico se
	cortaria a si mismo. Cada reproduccion es un clon que se destruye al terminar.
]]

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tags = require(Shared:WaitForChild("Tags"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.State.ClientState)
local SoundLibrary = require(script.Parent.SoundLibrary)

local FOLDER_NAME = "PixelMadnessAudio"
local MUSIC_FADE_SECONDS = 1.2
local SPATIAL_MIN_DISTANCE = 10
local SPATIAL_MAX_DISTANCE = 140
local CLEANUP_MARGIN_SECONDS = 0.5
local FALLBACK_LIFETIME_SECONDS = 3

local SoundController = {
	name = "SoundController",
}

local folder: Folder? = nil
local templates: { [string]: Sound } = {}
local lastPlayedAt: { [string]: number } = {}
local musicTracks: { [string]: Sound } = {}
local currentMusic: string? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end

	local existing = SoundService:FindFirstChild(FOLDER_NAME)

	-- Idempotente ante una recarga del cliente en Studio.
	if existing then
		existing:Destroy()
	end

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = SoundService

	folder = created

	return created
end

local function assetUrl(id: number): string
	return "rbxassetid://" .. tostring(id)
end

--[[ Resuelve la velocidad final de una reproduccion: base * escala * jitter. ]]
local function resolvePitch(spec: SoundLibrary.SoundSpec, pitchScale: number?): number
	local jitter = spec.pitchJitter or 0

	return (spec.pitch or 1) * (pitchScale or 1) * (1 + (math.random() * 2 - 1) * jitter)
end

--[[ Respeta el `cooldown` del efecto. Devuelve false si todavia no puede sonar. ]]
local function consumeCooldown(name: string, spec: SoundLibrary.SoundSpec): boolean
	local cooldown = spec.cooldown

	if not cooldown then
		return true
	end

	local now = os.clock()
	local last = lastPlayedAt[name]

	if last and now - last < cooldown then
		return false
	end

	lastPlayedAt[name] = now

	return true
end

local function lifetimeOf(sound: Sound): number
	if sound.TimeLength > 0 then
		return sound.TimeLength / math.max(sound.PlaybackSpeed, 0.1) + CLEANUP_MARGIN_SECONDS
	end

	return FALLBACK_LIFETIME_SECONDS
end

--------------------------------------------------------------------------------
-- Efectos
--------------------------------------------------------------------------------

--[[
	Reproduce un efecto en 2D (se oye igual en todos lados). Para la UI y para lo que
	le pasa a TU personaje. `pitchScale` multiplica la velocidad base: la usa, por
	ejemplo, el combo de monedas para que cada una suene un poco mas aguda.
]]
function SoundController.play(name: string, pitchScale: number?, volumeScale: number?): ()
	local spec = SoundLibrary.sfx[name]
	local template = templates[name]

	if not spec or not template or not consumeCooldown(name, spec) then
		return
	end

	local sound = template:Clone()
	sound.PlaybackSpeed = resolvePitch(spec, pitchScale)
	sound.Volume = spec.volume * (volumeScale or 1)
	sound.Parent = getFolder()
	sound:Play()

	Debris:AddItem(sound, lifetimeOf(sound))
end

--[[
	Reproduce un efecto en 3D, en una posicion del mundo. Para lo que les pasa a los
	demas: disparos de enemigos, impactos, enemigos que caen. La atenuacion por
	distancia es la que le dice al jugador de donde viene el peligro.
]]
function SoundController.playAt(name: string, position: Vector3, pitchScale: number?): ()
	local spec = SoundLibrary.sfx[name]
	local template = templates[name]

	if not spec or not template or not consumeCooldown(name, spec) then
		return
	end

	-- Un Attachment en el Terrain es el emisor mas barato posible: no tiene fisica,
	-- no se ve, y se destruye solo junto con el sonido.
	local emitter = Instance.new("Attachment")
	emitter.Name = "SfxEmitter"
	emitter.WorldPosition = position
	emitter.Parent = workspace.Terrain

	local sound = template:Clone()
	sound.PlaybackSpeed = resolvePitch(spec, pitchScale)
	sound.Volume = spec.volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = SPATIAL_MIN_DISTANCE
	sound.RollOffMaxDistance = SPATIAL_MAX_DISTANCE
	sound.Parent = emitter
	sound:Play()

	Debris:AddItem(emitter, lifetimeOf(sound))
end

--------------------------------------------------------------------------------
-- Musica
--------------------------------------------------------------------------------

local function fadeTo(sound: Sound, volume: number, onDone: (() -> ())?): ()
	local tween = TweenService:Create(sound, TweenInfo.new(MUSIC_FADE_SECONDS, Enum.EasingStyle.Sine), {
		Volume = volume,
	})

	if onDone then
		tween.Completed:Once(onDone)
	end

	tween:Play()
end

--[[ Cambia la pista con un fundido cruzado. `nil` apaga la musica. ]]
function SoundController.setMusic(trackName: string?): ()
	if trackName == currentMusic then
		return
	end

	local previous = if currentMusic then musicTracks[currentMusic] else nil

	currentMusic = trackName

	if previous then
		local outgoing = previous

		fadeTo(outgoing, 0, function()
			-- Si en el medio del fundido se volvio a pedir esta misma pista, no se corta.
			if currentMusic == nil or musicTracks[currentMusic] ~= outgoing then
				outgoing:Stop()
			end
		end)
	end

	if not trackName then
		return
	end

	local incoming = musicTracks[trackName]
	local spec = SoundLibrary.music[trackName]

	if not incoming or not spec then
		return
	end

	if not incoming.IsPlaying then
		incoming.Volume = 0
		incoming.TimePosition = 0
		incoming:Play()
	end

	fadeTo(incoming, spec.volume)
end

--[[ Que pista corresponde segun la fase y si hay un jefe vivo. ]]
local function musicForState(): string?
	local run = ClientState.getRun()
	local phase: Types.RunPhase = if run then run.phase else "Lobby"

	if phase == "Lobby" then
		return "lobby"
	elseif phase == "InRun" then
		return if #CollectionService:GetTagged(Tags.Boss) > 0 then "boss" else "run"
	end

	-- Victoria y Derrota: silencio, que suene el jingle.
	return nil
end

local function refreshMusic(): ()
	SoundController.setMusic(musicForState())
end

--------------------------------------------------------------------------------

local function buildTemplates(): ()
	local root = getFolder()

	local templateFolder = Instance.new("Folder")
	templateFolder.Name = "Templates"
	templateFolder.Parent = root

	for name, spec in SoundLibrary.sfx do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = assetUrl(spec.id)
		sound.Volume = spec.volume
		sound.Parent = templateFolder

		templates[name] = sound
	end

	for name, spec in SoundLibrary.music do
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. name
		sound.SoundId = assetUrl(spec.id)
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = root

		musicTracks[name] = sound
	end
end

function SoundController.init(): ()
	buildTemplates()
end

function SoundController.start(): ()
	-- La precarga va en otro hilo: tarda lo que tarde la red y el juego no la espera.
	-- Un efecto que suena antes de terminar de cargar simplemente sale un poco tarde.
	task.spawn(function()
		local toPreload: { Instance } = {}

		for _, sound in templates do
			table.insert(toPreload, sound)
		end

		for _, sound in musicTracks do
			table.insert(toPreload, sound)
		end

		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end)

	ClientState.runChanged:connect(function(_snapshot: Types.RunStateSnapshot)
		refreshMusic()
	end)

	CollectionService:GetInstanceAddedSignal(Tags.Boss):Connect(refreshMusic)
	CollectionService:GetInstanceRemovedSignal(Tags.Boss):Connect(function()
		-- El tag se quita en el mismo frame en que el jefe muere; un frame despues
		-- `GetTagged` ya no lo cuenta.
		task.defer(refreshMusic)
	end)

	refreshMusic()
end

return SoundController

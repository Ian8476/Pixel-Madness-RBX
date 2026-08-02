--!strict
--[[
	Health: la vida de CUALQUIER cosa danable (jugador, enemigo, jefe, rompible).

	Por que no `Humanoid.Health` (decision D2 del plan):
	1. Los rompibles no tienen Humanoid, y queremos un solo camino de dano.
	2. Humanoid trae regeneracion nativa oculta que hay que ir a borrar.
	3. Cualquier script puede escribirlo; nuestro modulo vive solo en el servidor.

	El Humanoid queda como ACTUADOR: cuando la vida logica llega a 0 se le pone
	`Humanoid.Health = 0` para heredar gratis la animacion de muerte y el ragdoll.

	Este modulo NO sabe de popups, ni de loot, ni de UI. Emite senales y se calla
	(regla 2). Quien quiera reaccionar, se suscribe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Signal)

export type HealthConfig = {
	maximum: number,
	-- Ventana de gracia tras recibir un golpe. Evita que una escopeta de 6 balas
	-- borre al jugador en un solo frame, y que el dano por contacto de un enemigo
	-- se aplique 60 veces por segundo.
	invulnerabilitySecondsAfterHit: number?,
	startingHealth: number?,
}

local Health = {}
Health.__index = Health

export type Health = typeof(setmetatable(
	{} :: {
		current: number,
		maximum: number,
		invulnerableUntil: number,
		invulnerabilitySecondsAfterHit: number,
		dead: boolean,
		destroyed: boolean,

		-- (cantidad aplicada, fuente del dano)
		onDamaged: Signal.Signal<number, Instance?>,
		-- (vida actual, vida maxima)
		onHealthChanged: Signal.Signal<number, number>,
		-- (fuente del golpe final)
		onDeath: Signal.Signal<Instance?>,
	},
	Health
))

function Health.new(config: HealthConfig): Health
	if config.maximum <= 0 then
		error(string.format("Health: maximum debe ser > 0, recibido %s", tostring(config.maximum)), 2)
	end

	local starting = config.startingHealth or config.maximum

	return setmetatable({
		current = math.clamp(starting, 0, config.maximum),
		maximum = config.maximum,
		invulnerableUntil = 0,
		invulnerabilitySecondsAfterHit = config.invulnerabilitySecondsAfterHit or 0,
		dead = false,
		destroyed = false,

		onDamaged = Signal.new(),
		onHealthChanged = Signal.new(),
		onDeath = Signal.new(),
	}, Health)
end

function Health.isDead(self: Health): boolean
	return self.dead
end

function Health.isInvulnerable(self: Health): boolean
	return os.clock() < self.invulnerableUntil
end

function Health.getCurrent(self: Health): number
	return self.current
end

function Health.getMaximum(self: Health): number
	return self.maximum
end

--[[
	Cambia la vida maxima. `keepRatio` sirve para el escalado de dificultad: un
	enemigo al 50% que sube de maximo sigue al 50%. Sin el flag, la vida actual
	solo se recorta si excede el nuevo maximo.
]]
function Health.setMaximum(self: Health, maximum: number, keepRatio: boolean?): ()
	if maximum <= 0 then
		error(string.format("Health: maximum debe ser > 0, recibido %s", tostring(maximum)), 2)
	end

	local ratio = self.current / self.maximum

	self.maximum = maximum
	self.current = if keepRatio then math.clamp(ratio * maximum, 0, maximum) else math.min(self.current, maximum)

	self.onHealthChanged:fire(self.current, self.maximum)
end

--[[
	Concede invulnerabilidad por N segundos. Nunca la ACORTA: si ya hay una ventana
	mas larga corriendo (el dash de Nina, por ejemplo), un golpe posterior no debe
	cancelarla.
]]
function Health.grantInvulnerability(self: Health, seconds: number): ()
	self.invulnerableUntil = math.max(self.invulnerableUntil, os.clock() + seconds)
end

--[[
	Aplica dano. Devuelve la cantidad realmente aplicada (0 si fue ignorada), para
	que quien dispara sepa si conecto sin tener que adivinarlo.
]]
function Health.damage(self: Health, amount: number, source: Instance?): number
	if self.destroyed or self.dead then
		return 0
	end

	if amount <= 0 then
		return 0
	end

	if self:isInvulnerable() then
		return 0
	end

	local applied = math.min(amount, self.current)

	self.current -= applied

	if self.invulnerabilitySecondsAfterHit > 0 then
		self:grantInvulnerability(self.invulnerabilitySecondsAfterHit)
	end

	self.onDamaged:fire(applied, source)
	self.onHealthChanged:fire(self.current, self.maximum)

	if self.current <= 0 then
		self.dead = true
		self.onDeath:fire(source)
	end

	return applied
end

--[[ Cura. No revive: un muerto se reemplaza o se revive por otro camino explicito. ]]
function Health.heal(self: Health, amount: number): number
	if self.destroyed or self.dead or amount <= 0 then
		return 0
	end

	local applied = math.min(amount, self.maximum - self.current)

	if applied <= 0 then
		return 0
	end

	self.current += applied
	self.onHealthChanged:fire(self.current, self.maximum)

	return applied
end

--[[ Mata sin pasar por invulnerabilidad ni resistencias. Para caidas al vacio y debug. ]]
function Health.kill(self: Health, source: Instance?): ()
	if self.destroyed or self.dead then
		return
	end

	self.current = 0
	self.dead = true

	self.onHealthChanged:fire(0, self.maximum)
	self.onDeath:fire(source)
end

function Health.destroy(self: Health): ()
	if self.destroyed then
		return
	end

	self.destroyed = true

	self.onDamaged:destroy()
	self.onHealthChanged:destroy()
	self.onDeath:destroy()
end

return Health

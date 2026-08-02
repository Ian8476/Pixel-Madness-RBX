--!strict
--[[
	Signal: eventos tipados genericos dentro de un mismo contexto (regla 2).

	POR QUE NO USAMOS sleitnick/signal DE WALLY (cambio respecto de la Fase 0):
	al escribir Health me tope con que la firma de esa libreria es `Fire(...: any)`,
	o sea que `health.OnDamaged:Connect(function(amount) ... end)` deja `amount` como
	`any`. Con `--!strict` obligatorio y los eventos como columna vertebral de toda la
	comunicacion del juego, perder el tipado justo ahi vacia la regla de su valor.

	Un `Signal<T...>` generico si estrecha: `Signal<number, Instance?>` obliga al
	handler a recibir `(number, Instance?)` y rompe la compilacion si cambias el
	payload y te olvidas de un suscriptor. Eso es exactamente el error que mas
	cuesta encontrar en un sistema orientado a eventos.

	Trade-off aceptado: mantenemos ~120 lineas propias en vez de una dependencia.
	La implementacion sigue el diseno conocido de GoodSignal (reutilizacion de
	corrutinas libres para no pagar `coroutine.create` por cada disparo).

	Alternativa si el equipo prefiere no mantener esto: envolver sleitnick/signal en
	una fachada generica. Se descarto porque la fachada cuesta casi lo mismo y agrega
	una indireccion mas al leer stack traces.
]]

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	disconnectAll: (self: Signal<T...>) -> (),
	destroy: (self: Signal<T...>) -> (),
}

--------------------------------------------------------------------------------
-- Reutilizacion de corrutinas
--
-- Cada handler corre en su propia corrutina para que un error o un yield en un
-- suscriptor no tumbe ni frene a los demas. Crear una corrutina por disparo seria
-- caro con cientos de balas por segundo, asi que se recicla la ultima que quedo libre.
--------------------------------------------------------------------------------

local freeRunnerThread: thread? = nil

local function acquireRunnerAndCall(handler: (...any) -> (), ...: any)
	local acquired = freeRunnerThread
	freeRunnerThread = nil

	handler(...)

	-- El handler termino: esta corrutina queda disponible para el proximo disparo.
	freeRunnerThread = acquired
end

local function runnerLoop(...: any)
	acquireRunnerAndCall(...)

	while true do
		acquireRunnerAndCall(coroutine.yield())
	end
end

local function spawnHandler(handler: (...any) -> (), ...: any)
	if not freeRunnerThread then
		freeRunnerThread = coroutine.create(runnerLoop)
		task.spawn(freeRunnerThread :: thread, handler, ...)
		return
	end

	task.spawn(freeRunnerThread :: thread, handler, ...)
end

--------------------------------------------------------------------------------

local SignalConnection = {}
SignalConnection.__index = SignalConnection

type ConnectionProps = {
	connected: boolean,
	_signal: any,
	_handler: (...any) -> (),
	_next: any,
}

function SignalConnection.disconnect(self: any): ()
	if not self.connected then
		return
	end

	self.connected = false

	local signal = self._signal

	if signal._head == self then
		signal._head = self._next
		return
	end

	local previous = signal._head

	while previous do
		if previous._next == self then
			previous._next = self._next
			return
		end

		previous = previous._next
	end
end

local SignalImpl = {}
SignalImpl.__index = SignalImpl

function SignalImpl.connect(self: any, handler: (...any) -> ()): Connection
	local connection = setmetatable({
		connected = true,
		_signal = self,
		_handler = handler,
		_next = self._head,
	} :: ConnectionProps, SignalConnection)

	self._head = connection

	return connection :: any
end

function SignalImpl.once(self: any, handler: (...any) -> ()): Connection
	local connection: Connection

	connection = self:connect(function(...)
		connection:disconnect()
		handler(...)
	end)

	return connection
end

function SignalImpl.fire(self: any, ...: any): ()
	local connection = self._head

	while connection do
		-- Se guarda el siguiente ANTES de invocar: un handler puede desconectarse
		-- a si mismo (o al de al lado) durante el disparo sin romper el recorrido.
		local nextConnection = connection._next

		if connection.connected then
			spawnHandler(connection._handler, ...)
		end

		connection = nextConnection
	end
end

function SignalImpl.disconnectAll(self: any): ()
	local connection = self._head

	while connection do
		connection.connected = false
		connection = connection._next
	end

	self._head = nil
end

function SignalImpl.destroy(self: any): ()
	self:disconnectAll()
end

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _head = nil }, SignalImpl) :: any
end

return table.freeze(Signal)

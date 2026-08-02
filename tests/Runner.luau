--!strict
--[[
	Runner: framework de tests minimo (describe / it / expect) sin dependencias.

	DECISION Y SU TRADE-OFF, para que nadie se pregunte por que no usamos TestEZ:
	TestEZ y Jest-Lua descubren specs recorriendo Instances de Roblox, asi que bajo
	Lune necesitan shims o un paso de darklua para traducir `require(script.Parent.X)`
	a requires relativos. Eso es infraestructura de build para, hoy, testear cuatro
	funciones puras.

	La contrapartida es la regla dura del proyecto: los modulos de Shared/Logic/ y
	Constants.luau no hacen `require` de nada y no tocan la API de Roblox. Con esa
	restriccion, el mismo archivo corre en Lune y en Roblox sin traduccion, y este
	runner de ~100 lineas alcanza y sobra.

	Cuando Shared/Logic/ crezca (Fase 3: DungeonLayout con TDD real y casos de tabla),
	se reevalua migrar a Jest-Lua + darklua. Hasta entonces, esto no bloquea a nadie.
]]

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: number, tolerance: number?) -> (),
	toThrow: () -> (),
}

export type TestApi = {
	describe: (name: string, body: () -> ()) -> (),
	it: (name: string, body: () -> ()) -> (),
	expect: (value: any) -> Expectation,
}

export type Spec = (api: TestApi) -> ()

type TestCase = {
	path: string,
	body: () -> (),
}

local DEFAULT_TOLERANCE = 1e-9

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end

	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end

	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end

	for key in b do
		if a[key] == nil then
			return false
		end
	end

	return true
end

local function stringify(value: any): string
	if typeof(value) ~= "table" then
		return tostring(value)
	end

	local parts = {}

	for key, item in value do
		table.insert(parts, string.format("%s = %s", tostring(key), tostring(item)))
	end

	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function makeExpectation(value: any): Expectation
	local expectation = {}

	function expectation.toBe(expected: any): ()
		if value ~= expected then
			error(string.format("esperaba %s, obtuve %s", stringify(expected), stringify(value)), 3)
		end
	end

	function expectation.toEqual(expected: any): ()
		if not deepEqual(value, expected) then
			error(string.format("esperaba (deep) %s, obtuve %s", stringify(expected), stringify(value)), 3)
		end
	end

	function expectation.toBeCloseTo(expected: number, tolerance: number?): ()
		local limit = tolerance or DEFAULT_TOLERANCE

		if typeof(value) ~= "number" then
			error(string.format("toBeCloseTo espera un numero, obtuve %s", typeof(value)), 3)
		end

		if math.abs(value - expected) > limit then
			error(string.format("esperaba %s +/- %s, obtuve %s", tostring(expected), tostring(limit), tostring(value)), 3)
		end
	end

	function expectation.toThrow(): ()
		if typeof(value) ~= "function" then
			error(string.format("toThrow espera una funcion, obtuve %s", typeof(value)), 3)
		end

		local ok = pcall(value)

		if ok then
			error("esperaba que lanzara un error, pero no lanzo nada", 3)
		end
	end

	return expectation :: Expectation
end

local Runner = {}

--[[ Ejecuta todas las specs. Devuelve true si todo paso. ]]
function Runner.run(specs: { Spec }): boolean
	local collected: { TestCase } = {}
	local groupStack: { string } = {}

	local api: TestApi
	api = {
		describe = function(name: string, body: () -> ()): ()
			table.insert(groupStack, name)
			body()
			table.remove(groupStack)
		end,

		it = function(name: string, body: () -> ()): ()
			local path = table.clone(groupStack)
			table.insert(path, name)
			table.insert(collected, { path = table.concat(path, " > "), body = body })
		end,

		expect = makeExpectation,
	}

	for _, spec in specs do
		spec(api)
	end

	local failures = 0
	local startClock = os.clock()

	for _, case in collected do
		local ok, err = pcall(case.body)

		if ok then
			print(string.format("  PASS  %s", case.path))
		else
			failures += 1
			print(string.format("  FAIL  %s\n        %s", case.path, tostring(err)))
		end
	end

	local elapsedMs = (os.clock() - startClock) * 1000

	print(
		string.format(
			"\n%d tests, %d fallos, %.1f ms",
			#collected,
			failures,
			elapsedMs
		)
	)

	return failures == 0
end

return Runner

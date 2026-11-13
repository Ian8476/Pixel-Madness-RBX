--!strict
--[[
	UIController: el dueno de la pantalla. Crea el ScreenGui, arma las Views y decide
	cual se ve.

	Por que la UI se CONSTRUYE en codigo en vez de clonarse de StarterGui (decision ya
	tomada en el documento de contexto, seccion 6, y aca es donde se cumple):

	  - `StarterGui` reparte una copia a cada jugador cuando aparece y otra cuando
	    respawnea, con `ResetOnSpawn` metiendo la cola. En un juego donde morir es parte
	    del bucle, eso son sorpresas garantizadas.
	  - Una UI en el `.rbxl` no tiene diff. Una UI en codigo se revisa en un PR.
	  - Las Views dependen de datos que ya viven en el repo (`Data/Characters`): armar
	    tres tarjetas de personaje a mano en Studio seria copiar a mano numeros que ya
	    estan escritos, y desincronizarlos en el primer rebalanceo.

	El precio es que no hay editor visual: cada margen es un numero en un archivo. Se
	acepta porque toda la identidad visual sale de piezas de `Theme` (paneles, botones,
	barras, medallas): cambiar el look de todo el juego es tocar un solo archivo, cosa
	que un editor visual no daria.

	--------------------------------------------------------------------------------
	QUIEN MANDA SOBRE LA VISIBILIDAD (Fase 5)
	--------------------------------------------------------------------------------

	Una sola funcion, `applyPhase`, decide que se ve. Antes cada View se escondia y se
	mostraba sola escuchando el mismo snapshot, y eso ya habia dado un bug: el HUD
	quedaba visible detras del panel de seleccion porque quien lo escondia era la tecla
	C y no el estado.

	La regla es corta:
	  Lobby            -> Menu
	  InRun            -> HUD
	  Victory/Defeat   -> HUD + panel de fin
	  y el panel de seleccion tapa lo que haya, mientras este abierto.

	--------------------------------------------------------------------------------
	Y QUIEN MANDA SOBRE EL CURSOR (camara de shooter)
	--------------------------------------------------------------------------------

	La misma funcion, por el mismo motivo. Con la camara de shooter el cursor esta
	bloqueado en el centro de la pantalla girando la vista, y un panel con botones y sin
	cursor es un panel que no se puede usar. Como quien ya sabe si hay algo abierto es
	`applyPhase`, es `applyPhase` quien le enciende y apaga el control a la camara.

	La dependencia va en un solo sentido (UIController -> camara) a proposito: que la
	camara preguntara "hay un panel abierto?" seria un ciclo de requires.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent.Parent.State.ClientState)
local ShooterCamera = require(script.Parent.Parent.Camera.ShooterCamera)
local Theme = require(script.Parent.Theme)
local BannerView = require(script.Parent.Views.BannerView)
local CharacterSelectView = require(script.Parent.Views.CharacterSelectView)
local HUDView = require(script.Parent.Views.HUDView)
local MenuView = require(script.Parent.Views.MenuView)
local RunEndView = require(script.Parent.Views.RunEndView)

local SCREEN_GUI_NAME = "PixelMadness"
local SELECT_KEY = Enum.KeyCode.C
local VIGNETTE_STRENGTH = 0.8

local UIController = {
	name = "UIController",
}

local hud: HUDView.HUDView? = nil
local menu: MenuView.MenuView? = nil
local characterSelect: CharacterSelectView.CharacterSelectView? = nil
local runEnd: RunEndView.RunEndView? = nil
local phase: Types.RunPhase = "Lobby"

--[[
	Oscurecido de bordes arriba y abajo. Dos Frames con degradado, no una imagen: no
	hace falta subir un asset y se ve igual.

	Cumple una funcion ademas de la estetica: el HUD vive en los bordes de la pantalla,
	y un fondo mas oscuro debajo hace que el texto blanco se lea contra cualquier piso.
]]
local function buildVignette(parent: Instance): ()
	local container = Instance.new("Frame")
	container.Name = "Vignette"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 0
	container.Parent = parent

	for _, edge in { { name = "Top", anchor = 0, rotation = -90 }, { name = "Bottom", anchor = 1, rotation = 90 } } do
		local band = Instance.new("Frame")
		band.Name = edge.name
		band.Size = UDim2.new(1, 0, 0.22, 0)
		band.Position = UDim2.fromScale(0, edge.anchor)
		band.AnchorPoint = Vector2.new(0, edge.anchor)
		band.BackgroundColor3 = Theme.colors.screenDim
		band.BorderSizePixel = 0
		band.ZIndex = 0
		band.Parent = container

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, VIGNETTE_STRENGTH),
		})
		gradient.Parent = band
	end
end

local function buildScreenGui(): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)

	-- Idempotente: si el bootstrap corre dos veces (recarga de Rojo en Studio), no se
	-- apilan dos HUDs.
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")

	screenGui.Name = SCREEN_GUI_NAME
	screenGui.ResetOnSpawn = false -- el HUD sobrevive a la muerte del personaje
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	return screenGui
end

--[[ La unica funcion que decide que se ve (y si hay cursor). ]]
local function applyPhase(): ()
	local selecting = characterSelect ~= nil and (characterSelect :: CharacterSelectView.CharacterSelectView).isOpen

	if hud then
		hud:setVisible(phase ~= "Lobby" and not selecting)
	end

	if menu then
		menu.root.Visible = phase == "Lobby" and not selecting
	end

	-- Con un panel abierto vuelve el cursor y el mouse deja de girar la camara.
	ShooterCamera.setInputEnabled(not UIController.isModalOpen())
end

function UIController.start(): ()
	local screenGui = buildScreenGui()

	local scale = Instance.new("UIScale")
	scale.Parent = screenGui

	local camera = workspace.CurrentCamera

	if camera then
		Theme.applyViewportScale(scale, camera.ViewportSize)

		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			Theme.applyViewportScale(scale, camera.ViewportSize)
		end)
	end

	buildVignette(screenGui)

	local hudView = HUDView.new(screenGui)
	local menuView = MenuView.new(screenGui)
	local bannerView = BannerView.new(screenGui)
	local selectView = CharacterSelectView.new(screenGui)
	local runEndView = RunEndView.new(screenGui)

	hudView:start()
	menuView:start()
	bannerView:start()
	selectView:start()
	runEndView:start()

	hud = hudView
	menu = menuView
	characterSelect = selectView
	runEnd = runEndView

	ClientState.runChanged:connect(function(snapshot: Types.RunStateSnapshot)
		phase = snapshot.phase

		-- Elegir personaje solo se puede en el lobby (lo valida el servidor). Si la
		-- run arranca con el panel abierto, se cierra solo.
		if phase ~= "Lobby" then
			selectView:setOpen(false)
		end

		applyPhase()
	end)

	selectView.openChanged:connect(applyPhase)

	-- El boton del menu y la tecla C hacen lo mismo; el menu no conoce al panel.
	menuView.chooseRequested:connect(function()
		selectView:setOpen(true)
	end)

	-- Camara: el menu pide, la camara decide, y el boton se repinta con lo que la camara
	-- diga. Va por signal y no leyendo el estado al abrir el menu porque la rueda del
	-- mouse cambia el modo en pleno combate, con el menu cerrado.
	menuView.cameraToggleRequested:connect(function()
		ShooterCamera.setFirstPerson(not ShooterCamera.isFirstPerson())
	end)

	ShooterCamera.firstPersonChanged:connect(function(isFirstPerson: boolean)
		menuView:setCameraMode(isFirstPerson)
	end)

	menuView:setCameraMode(ShooterCamera.isFirstPerson())

	UserInputService.InputBegan:Connect(function(input: InputObject, processedByUi: boolean)
		if processedByUi then
			return
		end

		if input.KeyCode ~= SELECT_KEY then
			return
		end

		-- Abrirlo fuera del lobby seria ofrecer algo que el servidor va a rechazar.
		if selectView.isOpen then
			selectView:setOpen(false)
		elseif phase == "Lobby" then
			selectView:setOpen(true)
		end
	end)

	local run = ClientState.getRun()

	if run then
		phase = run.phase
	end

	applyPhase()
end

--[[
	Lo usa el resto del cliente para saber si hay un panel modal abierto.

	Cuenta como modal todo lo que sea "no estas jugando ahora mismo": el lobby, el
	panel de seleccion y la pantalla de fin de run. Disparar en cualquiera de los tres
	no tiene sentido, y en dos de ellos ademas estas apretando botones.
]]
function UIController.isModalOpen(): boolean
	if phase == "Lobby" then
		return true
	end

	if characterSelect and (characterSelect :: CharacterSelectView.CharacterSelectView).isOpen then
		return true
	end

	return runEnd ~= nil and (runEnd :: RunEndView.RunEndView).isOpen
end

return UIController

# PixelMadness (Edición Roblox): Documento de Contexto del Proyecto
> Documento de traspaso: contiene TODO el contexto necesario para que una IA o colaborador nuevo continúe el desarrollo sin perder decisiones previas. Sucesor directo del contexto de la versión Unity (julio 2026). Este documento REEMPLAZA al anterior como fuente de verdad; el documento Unity queda como referencia histórica de diseño. Última actualización: agosto 2026.

---

## 1. Visión del juego

**PixelMadness** es un roguelite de acción 3D en tercera persona (con primera persona opcional; la vista era top-down hasta Fase 6, ver `CHANGELOG.md`), ahora desarrollado en **Roblox** en lugar de Unity, que combina:

- **Jugabilidad de Soul Knight (móvil)**: mazmorras de salas generadas proceduralmente que se cierran hasta eliminar a todos los enemigos, personajes seleccionables con una habilidad única y energía regenerativa, 2 ranuras de arma intercambiables, armas que consumen energía al disparar, monedas, y un jefe al final de la run.
- **Estética "PSX adaptada a Roblox"**: low-poly deliberado, texturas diminutas pixeladas, niebla densa, humor absurdo en nombres y descripciones, exageración visual (números de daño enormes, knockback generoso, proyectiles gigantes). Ver sección 7 para qué se conserva y qué se sustituye del look PSX original.

**Por qué Roblox (la gran decisión de la migración):**

1. **Multijugador nativo**: Soul Knight brilla en co-op. En Unity el co-op era un "quizás algún día"; en Roblox el netcode, la replicación y los servidores vienen gratis. El co-op de 1 a 4 jugadores pasa de sueño a feature de lanzamiento.
2. **Distribución y descubrimiento**: se elimina el plan itch.io → Steam ($100 USD). Publicar en Roblox es gratis, con audiencia integrada, discovery algorítmico y actualizaciones instantáneas sin builds.
3. **Meta-progresión y monetización de primera clase**: DataStores persistentes, Game Passes y Developer Products convierten el "gancho Soul Knight" (gastar monedas entre runs, desbloquear personajes) en un modelo de negocio real desde el día uno.
4. **Cero fricción de arte**: el equipo no domina Blender. Roblox permite greybox jugable con Parts y MeshParts, y el estilo low-poly chunky encaja con la estética del catálogo/Toolbox mientras llega arte propio.

**Trade-off aceptado**: se pierde el control total del pipeline de render (no hay render scale 0.33 ni filtrado nearest-neighbor de pantalla completa) y se gana un motor multijugador, una plataforma de distribución y una economía. El look PSX se re-interpreta, no se replica píxel a píxel.

**Loop objetivo (idéntico en espíritu al de la beta Unity):** Lobby/Menú → selección de personaje (3 disponibles) → Piso 1 (mazmorra generada en el servidor) → sala Portal → Piso 2 (mayor dificultad) → Piso 3, cuya sala final contiene al jefe "El Bonkarón" → pantalla de victoria (o derrota en cualquier punto → reintentar/lobby). En co-op, la run es compartida: mismo dungeon, dificultad escalada por número de jugadores.

**Estado actual (agosto 2026)**: **fases 0 a 5 completas**. El loop entero está jugable: lobby → selección de personaje → run de 3 pisos con mazmorra procedural, salas que encierran, enemigos, loot y jefe → victoria o derrota → vuelta al lobby. 121 tests de lógica pura en verde.

Para el estado operativo (qué falta, cómo correr los tests y el juego sin toolchain, y las trampas ya descubiertas) el documento de arranque es **`.agent/HANDOFF.md`**; el historial fase por fase, con decisiones y bugs, está en `CHANGELOG.md`.

La versión Unity queda como referencia histórica: llegó a plantilla beta completa en código (22 scripts C#) y todo su contenido (personajes, armas, enemigos, fórmulas de dificultad, algoritmo de mazmorra) se tradujo, no se reinventó.

---

## 2. Contexto del equipo y decisiones tomadas

- **Equipo**: 2-3 personas. Perfil web/backend fuerte; experiencia previa en Roblox con arquitectura server-autoritativa, CollectionService por tags, persistencia con ProfileStore y flujos de Studio asistidos por el plugin MCP. Poca o nula experiencia en Blender/arte (irrelevante a corto plazo en Roblox).
- **Plataforma objetivo**: Roblox (PC, móvil y consola a futuro; el MVP se diseña para PC con mouse y teclado, con la capa de input aislada para agregar gamepad/táctil sin tocar gameplay).
- **Motor**: Roblox (motor evergreen, sin versiones que congelar). ⚠️ La advertencia crítica de Unity ("no migrar de versión a mitad del proyecto") se sustituye por: **fijar versiones de toolchain** (Rojo, Wally, StyLua, Selene, Lune) en archivos de configuración del repo y actualizarlas solo de forma deliberada.
- **Lenguaje**: **Luau con `--!strict` obligatorio** en todo módulo nuevo. Tipado explícito en firmas públicas. Comentarios en español sin tildes (seguridad de encoding, regla heredada).
- **Workflow de código**: **Rojo + Git + VS Code**. El código NUNCA se edita dentro de Studio; Studio es para construir salas/prefabs (Models) y probar. Wally para dependencias (Signal, ProfileStore, TestEZ/Jest-Lua). CI en GitHub Actions (lint + formato + tests + build de place).
- **Regla de colaboración** (heredada y adaptada): nunca dos personas editan el mismo Model/lugar a la vez. El código va por PR en Git; los prefabs de sala se dividen por persona y se exportan como `.rbxmx` versionados o se sincronizan vía Rojo.
- **Controles (PC)**: WASD mueve (Humanoid estándar), mouse apunta (intersección rayo-plano a la altura del personaje, NO raycast físico), click izquierdo dispara, ESPACIO = habilidad, Q = alternar arma, E = recoger arma. Nota: ESPACIO ya no salta; se desactiva el salto (`Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)` y JumpPower 0).
- **Herramientas de verificación en Studio**: el plugin MCP se usa con las lecciones ya aprendidas: `execute_luau` corre en un VM separado (no puede `require()` singletons con estado del juego en ejecución), `user_mouse_input` y `character_navigation` cuelgan el server, y la verificación de UI se hace ejecutando en el datamodel de Cliente.
- **Historial de iteraciones**: 2 paquetes Unity pre-beta (descartados), 1 plantilla beta Unity (congelada como referencia de diseño). Ningún script C# se "porta línea a línea": se traduce la responsabilidad, no la sintaxis. ESTILO_PSX.md sobrevive como referencia estética con las adaptaciones de la sección 7.

---

## 3. Filosofía de arquitectura (las 5 reglas del proyecto)

Las 4 reglas de Unity se conservan traducidas, y se agrega una quinta que en Roblox es innegociable:

1. **Contenido = datos, no código.** ScriptableObjects → **ModuleScripts de datos puros** en `ReplicatedStorage/Shared/Data/` (uno por arma, personaje, enemigo, piso). Cada módulo retorna una tabla congelada (`table.freeze`) validada contra un tipo Luau exportado. Agregar contenido nunca debe requerir tocar sistemas. Sigue siendo la regla más importante del proyecto.
2. **Comunicación por eventos.** Eventos C# → **Signals** (librería tipo GoodSignal via Wally) dentro de un mismo contexto, **BindableEvents** solo si hace falta cruzar scripts sin require, y **RemoteEvents/RemoteFunctions** únicamente en la frontera cliente-servidor, centralizados en un solo lugar (`Shared/Remotes.luau`). `Health` emite `OnDeath`/`OnDamaged`/`OnHealthChanged`; nadie pregunta, todos escuchan. La UI (cliente) se suscribe a réplicas de estado; el gameplay (servidor) jamás conoce a la UI.
3. **Un módulo = una responsabilidad.** La entidad jugador se compone de: input (cliente), cámara (cliente), estado de personaje/energía (servidor), inventario de armas (servidor), Health (servidor), presentación/HUD (cliente). Prohibidas las clases Dios y los "Managers" que acumulan responsabilidades ajenas.
4. **Identificación por CollectionService tags y física por CollisionGroups.** Tags: `Player`, `Enemy`, `Boss`, `Bullet`, `Room`, `Coin`, `WeaponPickup`, `Breakable`. CollisionGroups: `PlayerChar`, `EnemyChar`, `PlayerBullet`, `EnemyBullet`, `Ghost` (monedas/pickups). Reglas: PlayerBullet no colisiona con PlayerChar ni PlayerBullet; EnemyBullet no colisiona con EnemyChar ni EnemyBullet; Ghost no colisiona con nada (detección por consulta espacial, no por física).
5. **El servidor es la única fuente de verdad.** (Nueva, crítica en Roblox.) Vida, energía, monedas, cooldowns, daño, generación de mazmorra y muerte se calculan SOLO en el servidor. El cliente envía intenciones (`FireRequest`, `SwapWeapon`, `UseAbility`, `PickupRequest`) y renderiza. Toda entrada de RemoteEvent se valida: tipo, rango, cadencia y estado. Un exploiter con el cliente modificado no debe poder hacer más daño, disparar más rápido ni ganar monedas que un jugador legítimo. Esta regla existe porque en Roblox el cliente SIEMPRE es hostil por defecto.

**Reglas de ejecución** (equivalente a Update/FixedUpdate/LateUpdate de Unity):
- Input y lectura de mouse: cliente, `RenderStepped`/`UserInputService`.
- Simulación (IA, proyectiles, cooldowns): servidor, un único `Heartbeat` por sistema (nunca un loop por entidad).
- Cámara: cliente, `BindToRenderStep` con prioridad `Enum.RenderPriority.Camera`.

---

## 4. Mapa de traducción Unity → Roblox (inventario de módulos objetivo)

Estructura Rojo del repositorio:

```
src/
  server/            → ServerScriptService/Server
    Core/            (GameService, RunService_, DifficultyConfig)
    Combat/          (WeaponService, ProjectileSystem, HealthRegistry, AbilityService, EnergyService)
    World/           (DungeonGenerator, RoomService, PortalService, LootService, PickupService)
    Enemies/         (EnemySystem, EnemyBrains/, BossBrain)
    Data/            (ProfileStoreConfig, PlayerDataService)
  client/            → StarterPlayer/StarterPlayerScripts/Client
    Input/           (InputController, AimProvider)
    Camera/          (ShooterCamera)
    UI/              (UIController, ClientState, Views/{HUDView, MenuView, VictoryView, DefeatView, CharacterSelectView})
    FX/              (DamagePopups, GameFeel, ProjectileVisuals*)
  shared/            → ReplicatedStorage/Shared
    Data/            (Weapons/, Characters/, Enemies/, Floors/)
    Types.luau, Remotes.luau, Tags.luau, CollisionGroups.luau, Constants.luau
    Logic/           (DungeonLayout.luau: algoritmo puro y testeable, SpreadMath.luau, DifficultyMath.luau)
```
`*` ProjectileVisuals es fase 2 (ver decisión de proyectiles en el plan).

### Tabla de equivalencias (script Unity → módulo Roblox → contexto)

| Unity (C#) | Roblox (Luau) | Corre en | Notas de traducción |
|---|---|---|---|
| `GameManager.cs` | `GameService.luau` + `RunService_.luau` | Servidor | Ya no hay DontDestroyOnLoad ni escenas: un solo place, el "cambio de escena" es teleport interno o regeneración del dungeon. Estado de run (piso, monedas de run, personaje por jugador) vive en el servidor y se replica a la UI vía evento `RunStateChanged`. Fórmulas intactas: `EnemyHealthMultiplier = 1 + 0.3*(piso-1)`, `ExtraEnemiesPerRoom = piso-1`, `FloorsPerRun = 3`, más escalado co-op (sección 5). Victoria/derrota NO pausan con timeScale (no existe global en multijugador): congelan input y muestran panel. |
| `Health.cs` | `Health.luau` (clase) + `HealthRegistry.luau` | Servidor | Fuente de verdad propia, NO `Humanoid.Health` (así sirve para rompibles sin Humanoid y evita curaciones/exploits nativos). El Humanoid se mantiene inmortal y se le ordena morir (`Humanoid.Health = 0`) cuando el Health lógico llega a 0, para heredar ragdoll/animación gratis. Conserva `SetMax`, `SetInvulnerable(segundos)`, ventana post-golpe, y Signals `OnDamaged/OnHealthChanged/OnDeath`. El popup de daño ya no lo dispara Health: el servidor emite `DamageDealt` (RemoteEvent unreliable) y el cliente renderiza el popup (regla 2 y 5). |
| `PlayerController.cs` | `InputController.luau` + `AimProvider.luau` (cliente) | Cliente | Movimiento = Humanoid estándar (WASD gratis, replicado, con predicción nativa). `AutoRotate = false`; el cliente rota el HumanoidRootPart hacia el punto de mira cada RenderStepped (el cliente posee la física de su personaje, replica solo). Apuntado: intersección analítica rayo de cámara vs plano Y = altura del pecho (más barato y robusto que raycast contra layer Ground; no requiere colliders de suelo perfectos). Publica `AimDirection` local y la envía al servidor solo cuando dispara. |
| `PlayerCharacter.cs` | `AbilityService.luau` + `EnergyService.luau` (servidor) + espejo en `ClientState` | Servidor | Energía y regeneración tick a tick en servidor; réplica al dueño vía atributo o RemoteEvent throttled (10 Hz basta para una barra). Habilidades por tipo (`Dash`, `DualWield`, `RapidFire`) con costo y cooldown validados en servidor. El Dash aplica impulso en el cliente (respuesta inmediata) pero la invulnerabilidad la concede el servidor con duración fija. |
| `WeaponInventory.cs` | `WeaponService.luau` (servidor) | Servidor | 2 ranuras por jugador en tabla de estado del servidor. Q y E son intenciones del cliente; el servidor valida (¿hay pickup en rango ≤ 8 studs?, ¿ranura válida?). `SetDualMode` y `SetFireRateMultiplier` son flags del estado del jugador aplicados por AbilityService. Evento `LoadoutChanged` replica al dueño para el HUD y a todos para el modelo visible del arma en manos. |
| `Weapon.cs` | Parte de `WeaponService` + `ProjectileSystem.luau` | Servidor | El disparo es: cliente envía `FireRequest(aimDir)` → servidor valida cadencia (con tolerancia 10% por jitter de red), energía y estado → `ProjectileSystem.SpawnVolley` calcula abanico uniforme + jitter ±2° (`SpreadMath.luau`, puro y testeado) y crea proyectiles. |
| `Bullet.cs` / `EnemyBullet.cs` | `ProjectileSystem.luau` (servidor, data-oriented) | Servidor | UN solo sistema para todas las balas vivas: tabla de proyectiles avanzada en un único Heartbeat, con raycast segmento-a-segmento entre posiciones (nunca `Touched`, es poco fiable). Parts ancladas con CanCollide=false y CanQuery=false, movidas con `BulkMoveTo`. Piercing = seguir tras golpear Enemy, morir contra paredes. Knockback = impulso al Humanoid enemigo. Filtro por CollisionGroup/whitelist en RaycastParams reemplaza los checks de tag de Unity. MVP: la Part del servidor se replica sola (gratis); optimización fase 2: balas solo-visuales en cliente. |
| `CameraFollow.cs` | `ShooterCamera.luau` (cliente) | Cliente | `CameraType = Scriptable`. **Reemplazó a la top-down en Fase 6**: cámara orbital detrás del jugador, mouse bloqueado en el centro, offset de hombro, zoom por rueda y primera persona a distancia cero. La mira ya no sale del cursor sino del centro de la pantalla (`AimProvider`). El diseño original (offset (0, 45, -28), pitch ~55°, look-ahead hacia el aim) queda como registro histórico en `CHANGELOG.md`. |
| `WeaponData.cs` / `CharacterData.cs` | `Shared/Data/Weapons/*.luau`, `Shared/Data/Characters/*.luau` | Shared | Tablas congeladas + tipo `WeaponDef`/`CharacterDef` en `Types.luau`. Un test automático valida que TODA definición cumple el esquema (nada de armas con campos faltantes descubiertas en runtime). `modelPrefab` → referencia por nombre a un Model en `ReplicatedStorage/Assets/`. |
| `DungeonGenerator.cs` | `Shared/Logic/DungeonLayout.luau` (puro) + `server/World/DungeonGenerator.luau` (instanciación) | Shared + Servidor | El algoritmo (random walk en grilla `Vector2int`-like, regla anti-bloque de máximo 1 vecino, BFS para sala más lejana = Boss/Portal, un dead-end = objetos, `roomCount = 7 + piso - 1`, seed reproducible con `Random.new(seed)`) se separa en un módulo PURO sin Instances: recibe seed y config, retorna el layout como datos. Esto lo hace testeable en CI con Lune sin abrir Studio (mismo enfoque TDD que el motor de Dirty Pig). El módulo servidor solo clona los Models de `ServerStorage/RoomPrefabs` en celda × roomSize (72 studs) y llama `RoomService.Setup` con conexiones N/S/E/O. |
| `Room.cs` | `RoomService.luau` (servidor, sistema por tags) | Servidor | NO un script por sala: un servicio que registra todas las salas taggeadas `Room` y sus atributos (`RoomType` como Attribute del Model). Cada lado con 3 objetos (SolidWall/OpenWall/Door) igual que Unity. El trigger interior se detecta con consulta espacial (`GetPartBoundsInBox` sobre la zona de la sala en Heartbeat, o Touched sobre una Part trigger si se prefiere para el MVP). Al entrar el PRIMER jugador: cierra puertas (Door.CanCollide=true, visible) para TODOS y spawnea enemigos escalados. En co-op, la sala encierra a los jugadores que están dentro; regla de diseño: los de afuera pueden disparar por los huecos pero no entrar (puertas cerradas), igual que Soul Knight. Al morir todos los enemigos: abre puertas; Portal activa su portal hijo; Boss llama `GameService.BossDefeated()`. Enum `RoomType {Start, Combat, Item, Portal, Boss}`; Start/Item nunca encierran. |
| `Portal.cs` | `PortalService.luau` | Servidor | Trigger: requiere que TODOS los jugadores vivos estén en la sala Portal (o votación mayoritaria con countdown de 10 s, decisión de diseño co-op) → `GameService.NextFloor()`: despawnea el piso, regenera con nueva seed, teletransporta al grupo a la sala Start. |
| `Coin.cs` | `LootService.luau` (servidor) + magnetismo visual en cliente | Servidor | Las monedas son crédito del SERVIDOR: se spawnean con impulso de explosión, el imán (radio 12 studs) y la recolección se validan en servidor (distancia jugador-moneda). El vuelo suave hacia el jugador se anima en cliente (TweenService) tras el evento de recolección para que se sienta instantáneo. Autodestrucción a los 30 s. En co-op: monedas de run compartidas (bote común) para evitar competencia tóxica por loot; decisión revisable con playtesting. |
| `WeaponPickup.cs` | `PickupService.luau` (servidor) + `PickupView` (cliente) | Servidor | Arma en el suelo: Model taggeado `WeaponPickup` con Attribute `WeaponId` (vacío = elegir del `randomPool` al spawnear, servidor). Flotar/girar/etiqueta con nombre = cliente (BillboardGui). E = `PickupRequest` validado por distancia; el intercambio suelta el arma vieja como nuevo pickup. |
| `EnemyChaser.cs` / `EnemyShooter.cs` | `EnemySystem.luau` + `EnemyBrains/{Chaser,Shooter}.luau` | Servidor | UN sistema itera todos los enemigos vivos por Heartbeat (data-oriented, no un Script por enemigo: con 4 jugadores y +3 enemigos extra por sala, la cantidad crece). Chaser: `Humanoid:MoveTo(playerPos)` re-emitido cada 0.25 s hacia el jugador VIVO más cercano (nuevo: co-op requiere selección de objetivo), daño por contacto con cooldown validado por distancia. Shooter: mantiene `preferredDistance` (24 studs), dispara EnemyBullet lenta y visible (leer balas ES el juego). `SetNetworkOwner(nil)` SIEMPRE en enemigos: evita jitter y que exploiters muevan enemigos. |
| `LootDrop.cs` | Dentro de `LootService` | Servidor | Escucha `OnDeath` de cualquier Health con atributo de loot y suelta N monedas. El enemigo sigue sin saberlo (regla 2 intacta). |
| `HUDController.cs` | `UIController` + `ClientState` + `Views/HUDView` | Cliente | Patrón ya validado por el equipo (UIController + ClientState + view modules): ClientState cachea réplicas del servidor (vida, energía, monedas, piso, loadout, personaje) y emite señales; las Views solo pintan. Se elimina el hack del `Invoke(0.05)` de Unity: el servidor envía un snapshot inicial `RunStateSnapshot` al confirmar spawn. |
| `MainMenuUI.cs` | `Views/{MenuView, CharacterSelectView}` + `LobbyService` (servidor) | Ambos | Ya no es una escena: es el estado Lobby del place. Selección de personaje con panel de stats/flavor; botón Listo. La run inicia cuando todos están listos (o countdown). `Time.timeScale=1` desaparece (no aplica). |
| `DamagePopup.cs` | `FX/DamagePopups.luau` | Cliente | BillboardGui + TextLabel: flota, se desvanece, mira a cámara (gratis con BillboardGui). Daño ≥ 30 = 1.8× más grande y naranja (marca de la casa). Se spawnea al recibir `DamageDealt` (unreliable remote). Solo para enemigos, nunca sobre el jugador local. |

### Frontera cliente-servidor (contrato de Remotes, centralizado en `Shared/Remotes.luau`)

| Remote | Dirección | Payload | Validación en servidor |
|---|---|---|---|
| `FireRequest` | C→S | `aimDir: Vector3` (unitario) | cadencia ≥ 90% del intervalo del arma, energía suficiente, jugador vivo, vector unitario y horizontal |
| `SwapWeapon` | C→S | n/a | tiene 2ª arma |
| `PickupRequest` | C→S | `pickup: Instance` | tag válido, distancia ≤ 8 studs, jugador vivo |
| `UseAbility` | C→S | n/a | cooldown, costo, jugador vivo |
| `SelectCharacter` | C→S | `characterId: string` | id existe, personaje desbloqueado, estado = Lobby |
| `SetReady` | C→S | `ready: boolean` | estado = Lobby |
| `RunStateChanged` | S→C | snapshot parcial (piso, monedas, estado) | n/a |
| `PlayerStatsChanged` | S→dueño | vida, energía, loadout | n/a |
| `DamageDealt` (unreliable) | S→C | posición, cantidad | n/a |
| `FXEvent` (unreliable) | S→C | id de efecto + posición (game feel fase 8) | n/a |

Regla: ningún otro archivo crea Remotes. Payloads siempre tipados en `Types.luau`.

---

## 5. Contenido de diseño definido (idéntico en diseño, convertido en unidades)

**Conversión de escala adoptada: 1 unidad Unity ≈ 3 studs** (ancla: un personaje Roblox mide ~5 studs vs cápsula Unity de ~2 m; factor validable en el primer graybox, TODO valor de esta sección es tuneable pero estos son los iniciales).

Derivados: sala 24×24 u → **72×72 studs** (hueco de puerta ~12 studs), imán de moneda 4 u → **12 studs**, distancia preferida del Shooter 8 u → **24 studs**, cámara (0,14,−9) → **(0, 42, −27)** con pitch 55° (redondear a (0, 45, −28) tras probar).

### Personajes (3): stats convertidos

| | Don Bonko | Nina "La Ráfaga" | El Profe Voltio |
|---|---|---|---|
| Flavor | "Golpea primero. Pregunta jamás." | "Si me viste, ya era tarde." | "La ciencia no es segura. Por eso funciona." |
| Color greybox | Naranja | Cian | Verde lima |
| Vida | 130 | 80 | 100 |
| WalkSpeed (5.5/7.5/6 u/s × 3) | 16 | 22 | 18 |
| Energía / Regen por s | 100 / 4 | 90 / 6 | 120 / 7 |
| Habilidad | DualWield "Doble Bonk" (5 s ambas armas) | Dash "Esfumarse" (impulso 36 studs/s + invuln 0.35 s) | RapidFire "Sobrecarga" (4 s cadencia ×2) |
| Costo / CD | 40 / 8 s | 20 / 1.5 s | 35 / 6 s |
| Arma inicial | La Escupechatarra | La Fiel | La Cotorra |

Diseño intencional intacto: la ulti de Bonko no vale nada sin segunda arma (empuja a explorar); Nina es riesgo/recompensa por timing; Voltio potencia cualquier arma mediocre.

### Armas (6): velocidades ×3 (studs/s)

| Arma | fireRate | proj | spread | daño | vel | energía | especial |
|---|---|---|---|---|---|---|---|
| La Fiel ("Nunca te abandona. Nunca impresiona.") | 4 | 1 | 0 | 8 | 66 | 0 | infinita, red de seguridad |
| La Escupechatarra ("Legalmente, una escopeta.") | 1.3 | 6 | 35 | 6 | 54 | 6 | automatic ✖ |
| La Cotorra ("No se calla nunca.") | 10 | 1 | 9 | 5 | 66 | 1 | |
| El Dedo de Dios ("Un disparo, una anécdota.") | 0.9 | 1 | 0 | 45 | 135 | 10 | automatic ✖, knockback fuerte |
| El Tridente ("Tres balas, cero explicaciones.") | 3 | 3 | 22 | 9 | 60 | 5 | |
| El Meteoro Quesero ("Nadie sabe por qué es de queso.") | 0.8 | 1 | 0 | 30 | 24 | 12 | piercing ✔, bulletScale 3 |

### Enemigos y jefe (greybox)

- **EnemyChaser**: rig rojo, HP 30, daño contacto 10, WalkSpeed 12, loot 1-3 monedas.
- **EnemyShooter**: rig morado, HP 20, mantiene 24 studs, balas rojas lentas y visibles (~30 studs/s).
- **Boss "El Bonkarón"**: Chaser escala 2.5, HP 400, daño 25, WalkSpeed 6, 15-25 monedas. Provisional, pendiente jefe real con fases.

### Escalado co-op (NUEVO, exclusivo Roblox)

Por cada jugador adicional en la run: enemigos +40% de vida y +1 enemigo por sala de combate; el jefe +60% de vida por jugador extra. Monedas al bote común. Derrota = TODOS los jugadores muertos (los caídos pueden ser revividos manteniendo E cerca 3 s, feature de fase co-op). Valores iniciales para playtesting, no dogma.

---

## 6. Estructura del place y montaje (referencia)

- **Un solo place para el MVP** (lobby + dungeon conviven; el dungeon se genera lejos del lobby o el lobby se oculta durante la run). Arquitectura hub + reserved servers vía TeleportService queda para la fase de escala (plan, fase 9).
- **ServerStorage/RoomPrefabs/**: `Room_Inicio`, `Room_Combate_01/02/03`, `Room_Objetos`, `Room_Portal`, `Room_Jefe`. Cada sala 72×72 studs, Attribute `RoomType`, 4 lados con SolidWall/OpenWall/Door, carpeta `SpawnPoints` con Parts invisibles, y en Portal/Jefe sus hijos especiales. Todo con tags de CollectionService, cero scripts dentro del prefab (los sistemas los operan desde afuera, regla 3).
- **ReplicatedStorage/Assets/**: modelos de balas, monedas, pickups, personajes (enchufes para arte futuro, igual que `modelPrefab` en Unity).
- **StarterGui** vacío: toda la UI la construye/clona `UIController` desde `ReplicatedStorage/Assets/UI` (control total, sin sorpresas de ResetOnSpawn).
- **StreamingEnabled = false** en el MVP (dungeon pequeño; evita que clientes no tengan las salas cargadas cuando el servidor spawnea cosas). Revisar solo si el place crece.
- **Configuración física**: CollisionGroups registrados al boot por `CollisionGroups.luau` (idempotente). Gravedad default. `Players.CharacterAutoLoads = false`: el spawn lo controla `GameService` (lobby vs run).
- **Errores comunes ya identificados** (heredados y nuevos): tags con mayúsculas inconsistentes (fallan en silencio), Attributes no asignados en prefabs, olvidar `SetNetworkOwner(nil)` en enemigos (jitter y exploits), confiar en `Touched` para balas (fallos a alta velocidad), crear Remotes fuera de `Remotes.luau`, y editar código en Studio rompiendo el sync de Rojo.

---

## 7. Estética: PSX re-interpretado para Roblox

Qué se conserva, qué se sustituye y qué se pierde (honestidad técnica primero):

| Receta Unity (ESTILO_PSX.md) | En Roblox | Estado |
|---|---|---|
| Render Scale 0.33 + Nearest-Neighbor | No existe control de resolución interna | ❌ Se pierde. Sustituto: proporciones chunky, texturas de baja resolución y UI pixelada que "venden" retro sin downscale |
| Niebla Linear densa oscura (start 10, end 40) | `Lighting.FogStart/FogEnd` (30/120 studs) o `Atmosphere` con Density alta | ✔ Directo, es el 60% del look |
| Sin anti-aliasing, sombras off/duras | Sombras: `GlobalShadows = false` o Technology = Compatibility para look plano | ✔ Aproximable |
| Texturas 64×64 point-filter | Texturas 64×64 en MeshParts/Decals (Roblox aplica su propio filtrado; el look pixel se conserva si la densidad de texels es baja). En UI sí existe `ResampleMode = Pixelated` para imágenes | ◐ Parcial: perfecto en UI, aproximado en 3D |
| Low-poly 300-800 tris, Mixamo | MeshParts low-poly (Toolbox/Kenney/Quaternius con licencia verificada) o rigs R6 (¡R6 ya es chunky y retro por naturaleza!) con animaciones del editor de Roblox | ✔ Incluso más fácil: R6 greybox coloreado reemplaza a las cápsulas |
| Vertex wobble / affine mapping PSX | No accesible | ❌ Se pierde, nadie lo va a extrañar en top-down |
| Números de daño enormes, UI con carisma | BillboardGui + fuente pixel (fuente custom subida a Roblox o `Enum.Font.Arcade`) | ✔ Directo |

**Dirección de arte resultante**: "PSX de espíritu, Roblox de cuerpo": R6 rigs deformes con colores planos saturados (Bonko masa naranja cuadrada, Nina delgada angular cian con bufanda, Voltio bata chamuscada y gafas enormes), niebla densa que esconde el fin del dungeon, ColorCorrection con contraste alto y saturación reducida, y UI 100% pixel. Los briefs de silueta del documento Unity siguen vigentes: en top-down identifican silueta + color, no el detalle.

---

## 8. Roadmap

El roadmap detallado, con fases, tareas, criterios de aceptación, riesgos y estrategia de lanzamiento/monetización, vive en el documento hermano **PixelMadness_ROBLOX_PLAN.md**. Resumen del orden: fundaciones de repo → núcleo jugable → mazmorra → contenido data-driven → enemigos/jefe → UI y lobby → co-op → persistencia y meta-progresión → game feel y estética → lanzamiento y LiveOps.

**Progreso: fases 0-5 hechas. La siguiente es la fase 6 (co-op real).** Antes de empezarla hay una deuda que arrastra la fase 5 y que conviene saldar primero: nada se probó nunca con más de un jugador. Ver `.agent/HANDOFF.md`.

---

## 9. Cómo debe comportarse una IA que continúe este proyecto

- Responder en español; comentarios de código en español sin tildes.
- Generar SOLO Luau con `--!strict`, tipos exportados en `Types.luau`, y compatible con el layout Rojo de la sección 4. Nada de código C#/Unity.
- Respetar las 5 reglas de arquitectura de la sección 3. Nuevo contenido = módulo de datos en `Shared/Data/` + assets; jamás lógica nueva para agregar un arma o personaje.
- **Nunca confiar en el cliente**: toda sugerencia que compute daño, monedas, energía o cooldowns en el cliente es un bug de seguridad, no una optimización.
- No proponer un Script por entidad (bala, enemigo, moneda): los sistemas iteran colecciones en un Heartbeat.
- No crear RemoteEvents fuera de `Shared/Remotes.luau` ni usar `Touched` para proyectiles.
- No reintroducir conceptos Unity sin traducir (escenas, timeScale, ScriptableObjects, tags de Unity, prefabs con scripts dentro).
- El equipo aprende: explicar el porqué de las decisiones, no solo el cómo; anticipar errores comunes de Roblox (network ownership, replicación, StreamingEnabled, límites de DataStore).
- Mantener el tono del juego en contenido nuevo: humor absurdo, nombres con carisma, exageración visual.

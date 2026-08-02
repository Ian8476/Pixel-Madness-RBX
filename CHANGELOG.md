# Changelog

Registro de cambios de PixelMadness (Roblox). Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## Como se mantiene

Cada entrada se divide en tres bloques, y el segundo es la razon de ser de este archivo:

- **Repositorio** — codigo, tests, toolchain, CI. Redundante con `git log`, pero legible.
- **Place (Studio)** — configuracion del `.rbxl`: iluminacion, propiedades de servicios, carpetas, geometria. **Esto NO esta versionado en Git.** Hasta que los prefabs se exporten como `.rbxmx` (Fase 3), este changelog es el unico registro de que se toco el place, cuando y por que. Si alguien abre el place dentro de tres meses y la niebla esta rara, esta seccion es donde busca.
- **Decisiones** — elecciones de arquitectura con su trade-off y su punto de reevaluacion. Se anotan aqui mientras sean pocas; si superan ~15, se parten a `docs/adr/`.

Convenciones:

- Una entrada por fase del plan. Dentro de la fase, se van agregando lineas bajo `[Sin publicar]` a medida que se mergean PRs, y al cerrar la fase se sella con version y fecha.
- Las lineas se agrupan con `Agregado`, `Cambiado`, `Eliminado`, `Corregido`.
- Cada linea dice **que cambio y por que**, no solo que archivo se toco.
- Los andamios temporales se marcan con `[ANDAMIO]` y se listan explicitamente en `Eliminado` cuando se borran.

---

## [Sin publicar]

Fase 2 — Datos: armas, personajes, energia y habilidades.

_(vacio)_

---

## [0.2.0] — Fase 1: Nucleo jugable — 2026-08-01

Objetivo de la fase: la sensacion Soul Knight en una sala estatica de prueba. Moverse, apuntar, disparar y romper cosas.

### Repositorio

**Agregado**

- `src/shared/Signal.luau` — signals genericos tipados `Signal<T...>`. Ver Decisiones.
- `src/shared/Logic/SpreadMath.luau` — abanico de disparo, jitter y rotacion horizontal. **Adelantado de Fase 2** porque `ProjectileSystem` lo necesitaba ya; escribirlo despues habria significado reescribir el sistema de proyectiles al mes siguiente. El azar se inyecta como funcion `() -> number` en vez de usar `Random`, para respetar la regla de la carpeta y poder testear el jitter con secuencias fijas.
- `src/server/Combat/Health.luau` — fuente de verdad de vida propia, independiente de `Humanoid.Health` (decision D2). Invulnerabilidad post-golpe, `setMaximum` con `keepRatio` para el escalado de dificultad, y senales `onDamaged` / `onHealthChanged` / `onDeath`. `damage()` devuelve la cantidad aplicada para que quien dispara sepa si conecto.
- `src/server/Combat/HealthRegistry.luau` — puente entre "Part golpeada por un raycast" y "entidad con Health". Claves debiles y limite de profundidad al subir por ancestros (esto corre una vez por bala por frame). Expone `onEntityDied`, donde se enchufa `LootService` en Fase 4.
- `src/server/Combat/ProjectileSystem.luau` — todas las balas del juego en un unico Heartbeat. Raycast del segmento recorrido (nunca `Touched`), Parts ancladas con `CanQuery = false` movidas con una sola llamada a `BulkMoveTo` por frame, piercing con registro de impactos ya aplicados, y knockback por impulso escalado con la masa.
- `src/server/Combat/WeaponService.luau` — valida `FireRequest` en cinco pasos, del filtro mas barato al mas caro. Arma hardcodeada (La Fiel) con la costura de Fase 2 aislada en una sola funcion.
- `src/server/Characters/CharacterService.luau` — configuracion del cuerpo del jugador: `AutoRotate` off, salto deshabilitado por dos vias, borrado del script nativo de regeneracion, grupo de colision, tag, greybox y `Health` registrado. Emite `onCharacterReady`.
- `src/server/World/BreakableService.luau` — adopta cualquier cosa taggeada `Breakable` y le da `Health` leyendo el Attribute `MaxHealth`. Ejemplo minimo de la regla 4: el prefab no lleva scripts adentro.
- `src/server/Core/RateLimiter.luau` — token bucket por jugador y por remote. Exceso = descarte silencioso, sin responderle al cliente.
- `src/client/Input/AimProvider.luau` — interseccion analitica rayo-plano a la altura del pecho.
- `src/client/Character/CharacterFacing.luau` — aplica la mira al cuerpo.
- `src/client/Camera/TopDownCamera.luau` — seguimiento con look-ahead hacia la mira.
- `src/client/Input/InputController.luau` — traduce clicks en intenciones.
- `src/client/FX/DamagePopups.luau` — numeros de dano flotantes; a partir de 30 crecen 1.8x y se ponen naranjas.
- `tests/specs/SpreadMath.spec.luau` — 11 tests nuevos. Total: **30 tests, 0 fallos** (Lune 0.8.9). 30/30 archivos compilan.

**Cambiado**

- `ServiceLoader` movido de `src/server/Core/` a `src/shared/`: el cliente necesita el mismo mecanismo y duplicarlo era peor que compartirlo.
- `wally.toml` sin dependencias. Efecto colateral util: `wally install` deja de ser necesario para correr el proyecto.
- `[ANDAMIO]` `DevSpawnService` reducido a una sola responsabilidad: pedir que aparezca un cuerpo. Toda la configuracion se mudo a `CharacterService`. Se le agrego respawn automatico a los 2 s para poder probar la muerte mas de una vez.

**Eliminado**

- Dependencia `sleitnick/signal@2.0.3` de `wally.toml`.

### Place (Studio)

**Cambiado**

- `StarterPlayer.LoadCharacterAppearance = false` — sin ropa, sombreros ni cara: jugas a Don Bonko, no a tu avatar.
- `StarterPlayer.EnableMouseLockOption = false` — el shift-lock rota la camara y pelea con la camara top-down.

**Agregado**

- `Workspace/TestArena/Dummies` — cuatro muniecos taggeados `Breakable` con Attribute `MaxHealth` (40 / 100 / 200 / 100), repartidos a distancias distintas para leer la velocidad de la bala y calibrar el knockback. Sin scripts adentro.

### Decisiones

- **Signal propio en vez de `sleitnick/signal` (revierte una decision de Fase 0).** Al implementar `Health` quedo claro que la firma `Fire(...: any)` de la libreria deja los payloads de todos los eventos como `any`. Con `--!strict` obligatorio y los eventos como columna vertebral de la comunicacion (regla 2), perder el tipado justo ahi vacia la regla de su valor. Un `Signal<T...>` generico rompe la compilacion si cambias un payload y te olvidas de un suscriptor — el bug mas caro de encontrar en un sistema orientado a eventos. **Trade-off:** mantenemos ~120 lineas propias (diseno de GoodSignal, con reutilizacion de corrutinas libres). **Alternativa descartada:** envolver la libreria en una fachada generica; cuesta casi lo mismo y agrega una indireccion al leer stack traces.
- **El aim usa interseccion rayo-plano, no raycast fisico.** Es una division en vez de una consulta al motor, no depende de que haya piso bajo el cursor (apuntar a un hueco de puerta o al vacio no rompe la mira), y el plano esta a la altura desde la que salen las balas: lo que ves bajo el cursor es lo que recibe el disparo.
- **El suavizado de camara usa `1 - exp(-velocidad * dt)` en vez de un alpha fijo.** Un alpha fijo por frame hace que la camara se mueva mas rapido a 144 fps que a 60, o sea que el game feel depende del monitor del jugador.
- **`AimProvider` y `CharacterFacing` son modulos separados.** Uno calcula hacia donde se apunta (input), el otro lo pinta (presentacion). Cuando el giro pase a interpolarse o a tener animacion de torso en Fase 8, se toca un solo archivo.
- **El throttle de envio del cliente (10 Hz) NO es una medida de seguridad.** Es cortesia de ancho de banda: sin el se mandarian 60 mensajes por segundo para un arma que dispara 4 veces. La cadencia real la impone el servidor y el rate limiter corta al que mande de mas. En Fase 2 el intervalo pasa a derivarse del arma equipada.
- **Tolerancia del 10% en la validacion de cadencia.** Los paquetes no llegan con reloj perfecto y castigar a un jugador con 120 ms de ping por adelantarse 5 ms seria injusto. No es una puerta: un cliente que dispare al doble de cadencia sigue rebotando.
- **El Humanoid queda inmortal (`MaxHealth = math.huge`) y actua como actuador de muerte.** Cuando el `Health` logico llega a 0 se le pone `Humanoid.Health = 0` para heredar gratis la animacion de muerte.
- **La rotacion del personaje se escribe como CFrame directa, no con `AlignOrientation`.** El cliente es dueno de red de su propio personaje, asi que el cambio es inmediato y se replica solo. Revisable si aparece jitter en co-op.
- **El salto se desactiva por dos vias** (`JumpPower`/`JumpHeight` en 0 **y** `SetStateEnabled(Jumping, false)`). Solo bajar `JumpPower` deja al Humanoid entrando igual en estado Jumping.

### Verificacion

- 30/30 tests en verde (Lune 0.8.9).
- 30/30 archivos `.luau` compilan sin errores de sintaxis.
- Pendiente de playtest humano: el criterio de aceptacion de la fase exige probar con **Test → Start Server + 2 clientes** que todo replica bien. Eso no lo puedo ejecutar yo.

### Pendiente de una pasada humana

- **Playtest.** El criterio de aceptacion completo (dos clientes, replicacion, game feel del disparo) necesita manos.
- Opcional: Game Settings → Avatar → Preset **R6** si se quiere el look chunky retro del documento de estetica. R15 funciona igual para esta fase; el greybox se aplica a ambos.
- Calibrar a ojo: `FOLLOW_SPEED` de la camara (12), `CAMERA_LOOK_AHEAD_STUDS` (8) y el knockback de La Fiel (12). Son los tres numeros que mas cambian la sensacion.

---

## [0.1.0] — Fase 0: Fundaciones — 2026-08-01

Objetivo de la fase: que el proyecto sea colaborable, testeable y reconstruible **antes** de escribir gameplay. Criterio de aceptacion del plan cumplido: un colaborador nuevo clona, corre `rojo serve`, abre Studio y ve el place base con niebla; los tests corren en Lune sin abrir Studio.

Estado de partida: place vacio (baseplate default), cero codigo. El diseno venia completo de la version Unity; nada de contenido se reinvento, se tradujo.

### Repositorio

**Agregado**

- Layout Rojo segun la seccion 4 del documento de contexto: `src/server` → `ServerScriptService/Server`, `src/client` → `StarterPlayerScripts/Client`, `src/shared` → `ReplicatedStorage/Shared`. `default.project.json` declara `Packages/` y `ServerPackages/` como rutas **opcionales**, para que `rojo serve` funcione en un clon limpio antes de correr `wally install`.
- `src/shared/Constants.luau` — numeros de diseno derivados de la conversion 1 unidad Unity = 3 studs.
- `src/shared/Types.luau` — esquemas de contenido (`WeaponDef`, `CharacterDef`, `EnemyDef`) y payloads de remotes. `AbilityDef` es una **union discriminada** por `kind`: agregar una habilidad nueva rompe la compilacion en los sitios que hay que tocar, en vez de fallar en runtime.
- `src/shared/Tags.luau` — vocabulario tipado de CollectionService. Mata el error documentado de "tags con mayusculas inconsistentes que fallan en silencio".
- `src/shared/CollisionGroups.luau` — nombres, matriz de reglas y registro idempotente. Solo se declaran las excepciones; lo no listado colisiona.
- `src/shared/Remotes.luau` — unica frontera cliente-servidor. Nombres tipados por union: un typo no compila. Separa remotes confiables de unreliable (FX puro).
- `src/shared/Logger.luau` — prefijo `[SERVER|CLIENT][Modulo]`. Existe porque en co-op vas a leer el Output con un servidor y hasta 4 clientes escribiendo a la vez.
- `src/shared/Logic/DifficultyMath.luau` — primera pieza de logica pura, con las formulas de escalado por piso y por jugadores. Tuning inyectable por parametro.
- `src/server/Core/ServiceLoader.luau` — arranque en dos fases (`init` de todos, despues `start` de todos). Los servicios se declaran con funciones planas, sin `self`.
- `src/server/Bootstrap.server.luau` y `src/client/Bootstrap.client.luau` — un unico Script por contexto. Infraestructura (grupos de colision, remotes) antes que servicios.
- `[ANDAMIO]` `src/server/Dev/DevSpawnService.luau` — spawnea el personaje y le aplica salto off / `AutoRotate` off, y borra el script nativo de regeneracion de vida. **Se elimina en Fase 4** cuando `GameService` controle el spawn. Vive en `Dev/` para que no haya duda de que es temporal.
- `tests/Runner.luau`, `tests/run.luau` y specs de `Constants` y `DifficultyMath` — 19 tests, verificados en verde con Lune 0.8.9.
- CI en GitHub Actions: formato (StyLua), lint (Selene con std de Roblox regenerado en cada run), tests en Lune y `rojo build` publicando el `.rbxl` como artifact.
- Toolchain fijado en `rokit.toml` + `scripts/pin-toolchain.sh` para actualizarlo de forma deliberada.
- `wally.toml` con `sleitnick/signal@2.0.3` como unica dependencia. ProfileStore queda comentado hasta Fase 7: dependencia sin uso es ruido.
- `README.md` con setup, reglas del proyecto y trampas de Roblox ya identificadas.

### Place (Studio)

**Cambiado**

- `Players.CharacterAutoLoads = false` — el spawn lo controla el juego (lobby vs run), no el motor.
- `Workspace.StreamingEnabled = false` — el dungeon lo genera el servidor; si el streaming descarga salas, el cliente termina viendo cosas spawnear en un vacio. Se revisa solo si el place crece.
- Iluminacion PSX: `FogStart = 30`, `FogEnd = 120`, `FogColor` oscuro desaturado, `GlobalShadows = false`, `EnvironmentDiffuseScale` y `EnvironmentSpecularScale` a 0, `ClockTime = 0`. La niebla densa es ~60% del look segun el documento de estetica.

**Agregado**

- `Lighting/PixelMadnessGrade` (ColorCorrectionEffect): saturacion −0.25, contraste +0.3.
- `ReplicatedStorage/Assets/{UI, Projectiles, Characters, Pickups}` — enchufes para arte futuro.
- `ServerStorage/RoomPrefabs` — vacia, se llena en Fase 3.
- `Workspace/TestArena` — sala de pruebas de **72×72 studs**, el tamano exacto de una sala real, para que lo que se sienta bien en Fase 1 se sienta igual en la mazmorra generada. Incluye anillos de referencia a 8 / 12 / 24 studs (rango de pickup, iman de moneda, distancia preferida del Shooter).
- `SpawnLocation` reposicionado en (0, 2, −20), neutral.

**Eliminado**

- `Workspace/Baseplate` — confunde la escala y no aporta nada.
- `Lighting/{SunRays, DepthOfField, Bloom, Atmosphere}` — efectos del template default que pelean contra el look plano.

### Decisiones

- **`Logic/` y `Constants.luau` no hacen `require` de nada ni tocan la API de Roblox.** Es la restriccion que permite que el mismo archivo corra en Lune (CI, sin Studio) y en Roblox sin darklua ni shims. Consecuencia visible: `Constants.CAMERA_OFFSET` es `{x, y, z}` y no un `Vector3`; el consumidor lo construye. Consecuencia de diseno: la configuracion se inyecta por parametro (DIP), no se importa.
- **Runner de tests propio en vez de TestEZ o Jest-Lua.** Ambos descubren specs recorriendo Instances de Roblox, asi que bajo Lune necesitan shims o un paso de darklua. Eso es infraestructura de build para testear hoy cuatro funciones puras. Trade-off aceptado: menos features (sin `beforeEach`, sin mocks, sin reporters). **Punto de reevaluacion: Fase 3**, cuando `DungeonLayout` traiga TDD real con casos de tabla.
- **El escalado por piso y por jugadores compone de forma multiplicativa, no aditiva.** Piso 3 con 4 jugadores da 1.6 × 2.2 = 3.52× en vez de 2.8×. Se elige multiplicativo porque cada eje es una presion independiente y compone correctamente al agregar un tercero (dificultad elegida, modo pesadilla). **Si el playtest lo siente injusto se baja `enemyHealthPerExtraPlayer`, no se cambia la formula.**
- **Arranque de servicios en dos fases.** Con una sola fase, el servicio A que se suscribe a una signal de B falla si A carga primero, y "arreglarlo" es reordenar la lista hasta que deje de romperse. Con `init` de todos antes de cualquier `start`, el cableado nunca depende del orden; solo el orden de los `start` es una decision, y se lee en el bootstrap.
- **Sin descubrimiento automatico de servicios.** El orden de arranque es una decision de diseno explicita, no un efecto secundario del orden alfabetico de los archivos.
- **La matriz de colisiones se registra en codigo, no en el editor de Collision Groups.** Si vive en el `.rbxl` no hay diff, ni PR, ni forma de saber quien la rompio. Nota tecnica: como las balas son Parts con `CanCollide = false`, lo que realmente usa la matriz es `RaycastParams.CollisionGroup` en el raycast segmentado del `ProjectileSystem` — asi "PlayerBullet no colisiona con PlayerChar" significa "la bala del jugador no puede impactarlo", sin un solo `if` de tag.
- **Las balas de bandos opuestos se atraviesan.** No estaba en el documento de contexto. En un top-down con balas grandes y lentas, balas que se anulan entre si son ilegibles para el jugador.
- **`PlayerChar` y `EnemyChar` siguen colisionando entre si** (default). El dano por contacto se resuelve por consulta de distancia, no por fisica, asi que la colision solo sirve para que los cuerpos no se solapen. Revisable si el amontonamiento de enemigos molesta.
- **Un `.rbxl` reconstruible desde el repo queda pendiente.** Hoy el CI produce un place con codigo pero sin salas ni assets. Se cierra en Fase 3, exportando los prefabs como `.rbxmx` versionados.

### Verificacion

- 19/19 tests en verde (Lune 0.8.9).
- 15/15 archivos `.luau` compilan sin errores de sintaxis.
- Place auditado tras la configuracion: 11/11 checks OK, incluyendo que `ReplicatedStorage/Shared` y `ServerScriptService/Server` siguen libres para que Rojo los cree.

### Pendiente de una pasada humana

- Versiones de `stylua`, `selene` y `lune` en `rokit.toml` son punto de partida; solo se verifico Rojo 7.7.0. Correr `scripts/pin-toolchain.sh` y commitear el diff.
- Confirmar que `wally install` resuelve `sleitnick/signal@2.0.3`.
- Guardar el place en Studio: los cambios en modo Edit no persisten solos.

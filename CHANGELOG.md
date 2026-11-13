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

Fase 6 — Co-op real.

### Rediseno de la UI "estilo Roblox popular" + sonido y musica

Pedido de producto: que la UI se parezca a la de los juegos populares de Roblox, con mas color y con sonido. La version anterior (pixel-art sobria, fuente Arcade, sin esquinas redondeadas) se leia bien pero no invitaba a jugar, y el juego era completamente mudo.

**Agregado**

- `src/client/Audio/SoundLibrary.luau` — todos los sonidos como DATOS (id, volumen, pitch, variacion, cooldown). Los ids salen de la Creator Store (toolbox): el set oficial "RBLX UI" de Roblox para la interfaz, catalogos con licencia de Roblox (APM, DistroKid) para la musica, y efectos publicos para combate. Todos se verificaron en Studio con `ContentProvider:PreloadAsync` (26/26 efectos y 3 pistas cargan).
- `src/client/Audio/SoundController.luau` — el unico modulo que crea `Sound`. `play` (2D, para la UI y para lo que le pasa a tu personaje) y `playAt` (3D con atenuacion, para disparos enemigos e impactos: el oido dice de donde viene el peligro). Cada reproduccion es un clon porque el mismo efecto se superpone consigo mismo. Musica con fundido cruzado segun la fase: lobby, run, jefe vivo, y silencio en Victoria/Derrota para que suene el jingle.
- `src/client/FX/CombatFeedback.luau` — traduce el mundo a sonido **sin ningun remote nuevo**: balas (por `CollisionGroup` en `workspace.Projectiles`), `DamageDealt`, tag `Enemy` + Attribute `Health`, Attribute `CollectedBy` de las monedas (con combo de pitch ascendente), Attribute `Closed` de las puertas, y el snapshot de stats (golpe recibido, arma nueva, cambio de arma). Expone dos signals para la UI: `hitConfirmed` y `roomLockChanged`. Que el impacto sea "tuyo" se infiere (bala propia reciente + el impacto no fue sobre vos): en co-op puede dar un hitmarker de mas en un caso borde, y eso no justifica un remote.
- `src/client/UI/Views/BannerView.luau` — anuncios grandes en el centro: cuenta regresiva 3-2-1 del lobby, "A LA MAZMORRA", "PISO N", "PELEA" al cerrarse una sala, "SALA DESPEJADA" al abrirse, "JEFE" al aparecer el Bonkaron. Escucha transiciones, no estados.
- HUD: hitmarker en X sobre la cruz, "+N" flotante al juntar monedas, vineta roja que late con poca vida, pastillas de progreso de pisos, sombra de enfriamiento circular con contador en la habilidad y sonido cuando vuelve a estar lista.
- Menu: tira de controles (teclas dibujadas como teclas) para el que entra por primera vez.
- Fin de run: rayos de luz girando, confeti en la victoria, tarjetas de piso y monedas, jingle propio para cada final.

**Cambiado**

- `src/client/UI/Theme.luau` — nueva identidad visual: esquinas redondeadas, degradados saturados (claro arriba, oscuro abajo), fuentes Luckiest Guy (titulos) y Fredoka One (texto) con contorno `UIStroke`, botones "gomita" que crecen, se aplastan y suenan, brillo que barre los botones importantes, medallas con iconos emoji. Los emoji van como escapes de Luau para que el codigo siga siendo ASCII y ningun script de sincronizacion rompa el encoding.
- `Theme.applyViewportScale` — la escala toma el MENOR factor entre alto (900) y ancho (1200). Antes solo contaba el alto, con un minimo de 0.6, y en ventanas chicas (el viewport de Studio, telefonos) el panel de jugadores tapaba el boton de LISTO.
- `HUDView`, `MenuView`, `CharacterSelectView`, `RunEndView` — reescritas sobre el nuevo Theme. **Su API publica no cambio** (`new`, `start`, `setVisible`, `isOpen`, `openChanged`, `chooseRequested`, `cameraToggleRequested`), asi que `UIController` e `InputController` siguen igual salvo por sumar `BannerView`.
- `DamagePopups` — numeros con Luckiest Guy, degradado y contorno, entrada con rebote; los golpes grandes salen inclinados y con "!".
- `PickupView` — el cartel del arma en el piso es una pastilla dorada redondeada, en el mismo idioma que la UI.
- Bootstrap del cliente — arrancan `SoundController` y `CombatFeedback` justo despues de `ClientState`.

**Corregido (durante el playtest del rediseno)**

- El emoji de moneda (U+1FA99) no lo dibuja Roblox: se usa la bolsa de dinero.
- Corazon rojo sobre medalla roja era invisible: la medalla de vida tiene fondo claro.
- Nombres de arma largos se cortaban; se usa un tamano menor por largo en vez de `TextScaled` (que con el `UIScale` global agrandaba las palabras cortas como "VACIA").

**Place (Studio)**

- El codigo se subio al place script por script (solo los archivos de cliente que cambiaron) y se verifico con hash que cada `Source` coincide con el repo. No se uso `sync-place.ps1` por HTTP porque el plugin MCP ahora bloquea `127.0.0.1` en su allowlist. Nada del place fuera de `StarterPlayerScripts/Client` se toco.

**Decisiones**

- **Audio desde la toolbox y no subido por el equipo.** Gratis y sin pasar por moderacion; el riesgo es que un asset de terceros se retire. Mitigado: `SoundController` saltea en silencio cualquier sonido que no cargue. Reevaluar al publicar el juego: ahi conviene subir audio propio.
- **Emoji como iconos en vez de imagenes.** Cero assets que subir ni moderar, y Roblox los dibuja a color. Precio: dependen de la fuente de respaldo de Roblox (ver el caso de la moneda). Reevaluar en la Fase 8 con iconos propios.

**Pendiente de verificar**

- Probado en un playtest en vivo con un jugador: lobby, seleccion, cuenta regresiva, HUD, PELEA, disparos, hitmarker, popups, Derrota y musica. **No** se jugo hasta Victoria ni con dos clientes.
- StyLua y Selene siguen sin instalarse en la maquina: no se corrio formato ni lint sobre los archivos nuevos. No se toco `Shared/Logic` ni `Shared/Data`, asi que los 121 tests de logica no cambian.

### Camara de shooter en tercera persona (con primera persona)

Cambio de perspectiva pedido por diseno: la camara deja de estar colgada arriba del piso y pasa a ir detras del jugador, como un shooter en tercera persona. La primera persona no es un modo aparte sino la misma camara con la distancia en cero, y por eso se entra y se sale de ella **con la rueda del mouse, sin abrir ningun menu**.

**Agregado**

- `src/client/Camera/ShooterCamera.luau` — camara orbital sobre un pivote a la altura de los ojos, corrida al hombro, con zoom por rueda, raycast de oclusion contra las paredes y primera persona al pasarse de cerca. Expone `firstPersonChanged` porque el modo cambia por dos caminos (rueda y boton) y el boton no puede llevar la cuenta por su lado.
- **Cruz en el centro del HUD.** Con el cursor bloqueado en el centro de la pantalla, sin cruz no hay forma de saber a que se le esta apuntando. Lleva hueco en el medio a proposito: una cruz maciza tapa justo el pixel que el jugador quiere mirar, que en un enemigo lejano es todo el enemigo.
- **Boton de camara en el panel del lobby** (`MenuView`), que alterna tercera y primera persona.

**Cambiado**

- `AimProvider` — **la mira dejo de ser el cursor y paso a ser el centro de la pantalla.** Con el mouse girando la camara ya no hay cursor que intersectar contra un plano; ahora se tira un raycast desde la camara hacia adelante y se apunta al primer impacto. Se apunta al PUNTO y no paralelo a la camara porque la camara esta corrida al hombro: disparar paralelo tira a un par de studs al costado de lo que la cruz tapa, que a 20 studs es fallar un enemigo entero. La direccion se sigue devolviendo aplanada, porque el ProjectileSystem dispara en horizontal y el servidor la aplana igual al validarla.
- **Se invirtio la cadena del frame.** Antes: mira -> cuerpo -> camara (la camara seguia al cursor con look-ahead). Ahora: camara -> mira -> cuerpo -> intencion. Las prioridades de `BindToRenderStep` se reordenaron alrededor de `RenderPriority.Camera` para que cada eslabon lea el dato de ESTE frame y no el del anterior.
- `UIController` — `applyPhase` ademas de decidir que se ve, decide **si hay cursor**: con un panel abierto le apaga el control a la camara y el mouse vuelve. Un panel con botones y sin cursor es un panel que no se puede usar. La dependencia va solo en un sentido (UIController -> camara); al reves seria un ciclo de requires.
- `Constants` — el bloque de camara entero. `FOG_START_STUDS` bajo de 95 a 60: la regla escrita ahi es "FOG_START > distancia de camara + media sala", y esa distancia paso de los 53 studs de la top-down a los 20 del zoom maximo. Dejarlo en 95 con la camara pegada al personaje era arrancar la niebla tan lejos que el piso se veia plano.

**Eliminado**

- `src/client/Camera/TopDownCamera.luau` y sus constantes (`CAMERA_OFFSET`, `CAMERA_PITCH_DEGREES`, `CAMERA_LERP_ALPHA`, `CAMERA_LOOK_AHEAD_STUDS`).
- `Constants.AIM_PLANE_HEIGHT_STUDS` y `AimProvider.getAimPoint()`, que ya no tenian sentido con el nuevo metodo de mira. `getAimPoint` ademas no tenia ni un consumidor.

### Decisiones

- **El toggle de camara vive en el lobby y no en el HUD.** No es pereza de UI: durante la partida el cursor esta bloqueado en el centro de la pantalla girando la camara, asi que un boton en pleno combate seria un boton que no se puede apretar. El camino de jugando es la rueda del mouse, que es justamente lo que se pidio: cambiar de perspectiva sin ir a ningun menu.
- **La rotacion de camara NO se suaviza; el zoom si.** Suavizar el giro de un shooter es lo que se siente como "mando de tanque". El zoom en cambio salta feo, y usa el mismo `1 - exp(-velocidad * dt)` de siempre para no depender de los fps.
- **El raycast de oclusion ignora a los cuerpos (tags `Player` y `Enemy`) y respeta al mundo.** Un enemigo que te pasa por detras no tiene que arrastrarte la camara a la nuca. Balas, monedas y pickups no hace falta filtrarlos: nacen con `CanQuery = false`.
- **En primera persona el cuerpo propio se esconde con `LocalTransparencyModifier`.** Es una propiedad de cliente: no replica, y los demas jugadores te siguen viendo entero. El mismo umbral cubre a la camara aplastada contra una pared, que es el otro caso en el que el cuerpo propio tapa la pantalla.
- **El offset de hombro se apaga proporcionalmente al acercarse.** A distancia cero, un hombro de 2.2 studs dejaria la camara flotando al costado de la cabeza.

### Verificacion

**121 tests, 0 fallos** (`Constants` entra en el bundle y cambio, asi que la suite se volvio a correr entera).

Playtest en Studio con `sync-place.ps1`, con el juego corriendo:

| Comprobacion | Resultado |
|---|---|
| Arranque del cliente | 10 servicios, 0 errores en consola |
| Encuadre en el lobby | camara `Scriptable`, FOV 70, a 12.5 studs del jugador y 3.6 por encima |
| Cursor en el lobby | `MouseBehavior = Default` y cursor visible (hay panel abierto) |
| Cursor al empezar la run | `LockCenter` y cursor oculto, HUD visible con la cruz |
| Convergencia de la mira | el cuerpo apunta 4.9 grados corridos de la camara, que es la correccion del hombro sobre el punto que tapa la cruz |
| Roll de camara | 0.000 (el orden YXZ no la inclina de costado) |

**Pendiente de probar a mano** (no se puede sintetizar input de mouse en este entorno: la trampa conocida del plugin es que cuelga el server): el giro con el mouse, la rueda entrando y saliendo de primera persona, y el boton del lobby.

---

## [0.6.0] — Fase 5: Lobby, seleccion de personaje y HUD completo — 2026-08-02

Objetivo de la fase: reemplazar las "escenas" de la version Unity por estados del place. Al terminar, el circulo cierra entero **sin recargar el servidor**: Menu -> eleges personaje -> te marcas listo -> run -> victoria o derrota -> Menu.

Estado de partida: el servidor arrancaba jugando. No habia menu, no habia lobby, elegir personaje era un andamio que respawneaba a mitad de piso, y el boton de fin de run largaba otra run de una.

### Repositorio

**Agregado**

- `src/shared/Logic/LobbyRules.luau` — cuando arranca una run. Son cuatro lineas y tienen tests porque sus dos fallos posibles son silenciosos: arrancar con cero jugadores deja una mazmorra girando sola, y no arrancar nunca deja a la gente mirando un boton muerto.
- `src/server/Core/LobbyService.luau` — el estado Lobby: quien esta listo, la cuenta atras, y los remotes `SelectCharacter` y `SetReady`.
- `src/server/World/LobbyBuilder.luau` — la sala del lobby por codigo, con una plataforma del color de cada personaje.
- `src/client/UI/Views/MenuView.luau` — titulo, tu personaje, boton de Listo, lista de quien esta en la sala y cuenta atras.
- `tests/specs/LobbyRules.spec.luau` — **6 tests nuevos** (121 en total).

**Cambiado**

- `GameService` — arranca en `Lobby` en vez de jugando, y `RequestRestart` pasa a ser **volver al lobby** en vez de largar otra run: ahi se puede cambiar de personaje antes de reintentar, que es la mitad de la gracia de haber perdido. Guarda el roster que le empuja LobbyService y lo mete en el snapshot solo durante el lobby.
- `CharacterService` — dejo de escuchar `SelectCharacter`. Quedo como un setter puro (ver Decisiones).
- `UIController` — **una sola funcion decide que se ve** (`applyPhase`). Antes cada View se escondia sola y eso ya habia dado un bug: el HUD quedaba visible detras del panel de seleccion porque quien lo escondia era la tecla C y no el estado.
- `Types.luau` — `RunStateSnapshot` sumo `roster` y `countdownRemaining`, que viajan **solo durante el lobby**: el mismo snapshot se emite cuando entran monedas, y repetir en pleno combate una lista que nadie mira es trafico regalado.
- `RunEndView` — el boton dice "VOLVER AL LOBBY".
- La tecla `C` solo abre la seleccion en el lobby: ofrecerla en otra fase seria ofrecer algo que el servidor va a rechazar.

**Corregido**

- **Recursion infinita entre LobbyService y GameService** (`C stack overflow` en el arranque, encontrado en el playtest). La cadena era `LobbyService.publish -> GameService.setRoster -> GameService.publish -> onStateChanged -> LobbyService reacciona publicando -> ...`. Es la trampa clasica de dos servicios que se avisan cambios entre si. La salida no fue cortar la signal sino preguntarse que se esta escuchando de verdad: interesa **"se entro al lobby"**, que pasa una vez, y no "seguimos en el lobby", que pasa todo el tiempo. Ahora se reacciona a cambios de fase, no a snapshots.
- **Las plataformas del lobby salian espejadas** respecto de las tarjetas del panel de seleccion. La camara top-down mira hacia +Z, asi que en pantalla el +X queda a la izquierda; el eje se recorre al reves y ahora los dos ordenes coinciden.

### Place (Studio)

Sin cambios. El lobby lo construye `LobbyBuilder` al arrancar.

### Decisiones

- **Los remotes del lobby se escuchan en LobbyService, no en CharacterService.** `SelectCharacter` tiene que validar "y la fase es Lobby", y si esa comprobacion viviera en CharacterService, CharacterService tendria que preguntarle la fase a GameService, que ya depende de el: ciclo. La salida no fue un truco de dependencias sino darse cuenta de que son dos responsabilidades: CharacterService sabe QUIEN sos, LobbyService sabe QUE PODES HACER en el lobby.
- **LobbyService EMPUJA el roster a GameService en vez de que GameService lo pida.** Por el mismo ciclo, al reves. La dependencia queda en una sola direccion y el snapshot que ya existia no necesita conocer a nadie nuevo.
- **Arranca cuando estan TODOS listos, con 5 segundos de margen.** El margen existe para poder arrepentirse: sin el, tocar Listo sin querer te mete en una run. La alternativa que deja abierta el documento (mayoria + countdown largo) se decide en la fase de co-op, con gente de verdad esperandose: es una decision social, no tecnica, y no se puede tomar bien sin verla pasar.
- **El menu no tapa el mundo, flota sobre el.** Estas parado en el lobby con tu personaje puesto mientras eliges, asi que el cambio de color se ve en el cuerpo y no solo en una tarjeta. Por eso el panel vive abajo y a los costados y deja el centro libre, que es lo contrario de lo que pide un menu tradicional.
- **El boton de fin de run va al lobby y no a otra run.** Es lo que pedia el criterio de aceptacion ("victoria/derrota -> menu") y ademas es mejor: perder y poder cambiar de personaje antes de volver a entrar es parte del bucle de un roguelite.

### Verificacion

- **121 tests, 0 fallos.**
- **Playtest del circulo completo, en vivo y sin errores en consola:**

| Paso | Resultado |
|---|---|
| Arranque | Menu visible, HUD escondido, lobby construido, sin mazmorra |
| Elegir a Nina | el panel pasa a "NINA LA RAFAGA" |
| Marcarse listo | boton -> "NO ESTOY LISTO", estado -> "EMPIEZA EN 4..." |
| Arrepentirse a mitad | cuenta cancelada, vuelve a "FALTA 1 JUGADOR" |
| Dejar que termine | Menu se va, HUD aparece, mazmorra generada, **jugando como Nina con 80/80** (sus stats, no las de Bonko) |
| Morir | panel "DERROTA" con "VOLVER AL LOBBY" |
| Volver | Menu de vuelta, mazmorra destruida, 0 enemigos, "listo" limpio, personaje conservado y vida restaurada |

- **Sin verificar**: el criterio de aceptacion completo pide "con 4 jugadores cada quien ve SU vida/energia/loadout y las monedas comunes". Se probo con UNO. Por construccion deberia cumplirse (`PlayerStatsChanged` va con `FireClient` y `RunStateChanged` con `FireAllClients`), pero eso es un argumento, no una medicion.
- **El formato sigue sin pasar por StyLua** y el lint sin pasar por Selene.

### Pendiente de una pasada humana

- **Probar con dos clientes** (Test -> Start Server + 2 Players). Es lo unico que cierra el criterio de aceptacion de esta fase, y ademas es donde van a aparecer las cosas raras del lobby: dos jugadores marcandose listos a destiempo, uno que se va durante la cuenta atras, uno que entra a mitad de run.
- **Formato y lint**: `stylua --check src tests`, `selene src`.
- **Mirar el lobby con ojos de jugador**: las plataformas de colores no hacen nada al pararse encima. O se las hace interactivas (pararse = elegir) o se asume que son decorativas y se les pone el nombre del personaje al lado.

---

## [0.5.0] — Fase 4: Salas de combate, enemigos y flujo de run — 2026-08-02

Objetivo de la fase: el bucle de presion de Soul Knight. Entrar, encerrarse, limpiar, avanzar. Al terminar, una run de 3 pisos se juega de principio a fin: hay enemigos que te persiguen y te disparan, salas que te encierran hasta limpiarlas, monedas, un jefe y una pantalla de Victoria o de Derrota con un boton para volver a intentarlo.

Estado de partida: una mazmorra generada pero vacia. Se caminaba de la sala de inicio al portal sin que pasara nada, y el "jefe" era un cubo anclado de 400 de vida.

### Repositorio

**Agregado**

- `src/shared/Data/Enemies/` — Chaser, Shooter y El Bonkaron, mas el registro. `combatPool` separa a los que puede sortear una sala de combate del jefe, que sale una sola vez por run: sin esa separacion, evitar "me salieron dos Bonkarones" seria un `if` en el spawner.
- `src/shared/Logic/EnemyTactics.luau` — las dos preguntas de un cerebro (a quien voy, donde me paro) como geometria pura y testeable.
- `src/server/Enemies/EnemyFactory.luau` — el rig minimo de un enemigo, construido en codigo.
- `src/server/Enemies/EnemySystem.luau` — TODOS los enemigos vivos en un unico Heartbeat a 20 Hz, con la lista de objetivos armada una vez por tick y repartida a todos los cerebros.
- `src/server/Enemies/EnemyBrains/{Chaser, Shooter}.luau` — modulos SIN estado: un solo `update` atiende a los treinta bichos de la sala.
- `src/server/World/LootService.luau` — monedas, iman validado en servidor y bote comun.
- `src/client/FX/LootView.luau` — el giro de las monedas y su vuelo hacia quien las levanta.
- `src/client/UI/Views/RunEndView.luau` — las pantallas de Victoria y Derrota, con el boton de Reintentar.
- `tests/specs/EnemyTactics.spec.luau` mas bloques nuevos en `ContentSchema.spec`, `ContentData.spec` y `DifficultyMath.spec` — **29 tests nuevos** (115 en total).
- `scripts/sync-place.ps1` — copia el codigo del repo al place sin Rojo, para poder apretar Play en una maquina que no tiene la toolchain. Es lo que hizo posible el playtest de esta fase. **No reemplaza a Rojo**: es de una sola direccion y lo que se edite dentro de Studio se pierde al resincronizar.
- `src/server/Core/LightingService.luau` — la atmosfera (niebla, ambiente, hora, grade) aplicada desde codigo al arrancar, con los numeros en `Constants`. Es la misma decision que se tomo en la Fase 0 con la matriz de CollisionGroups y por los mismos motivos: si vive en el `.rbxl` no hay diff, no hay PR y no hay forma de saber quien la rompio. Efecto colateral util: la iluminacion deja de depender de que el changelog la recuerde, y un clon del repo se ve bien sin tocar el place.

**Cambiado**

- `RoomService` — dejo de ser solo un registro: ahora lleva el ciclo de vida de la sala de combate (detectar entrada, encerrar, spawnear escalado, abrir al limpiar). La composicion de enemigos sale de un Rng sembrado con el seed del piso y las coordenadas de la sala, o sea que es tan reproducible como el plano.
- `GameService` — se quedo con el spawn de cuerpos, declara la derrota cuando cae el ultimo jugador y la victoria cuando cae el jefe, lleva el bote de monedas y acepta `RequestRestart`.
- `DungeonGenerator` — se le fue el jefe: ahora la sala del Jefe lo spawnea como un enemigo de verdad. Tambien borra enemigos y monedas al regenerar, no solo pickups.
- `DifficultyMath` — nueva `enemyCountForRoom`, para que el redondeo y el minimo de 1 vivan en un solo lugar.
- `ContentSchema` — valida `EnemyDef`.
- `Types.luau` — `EnemyDef` sumo `preferredDistanceStuds` e `isBoss`.
- `Remotes.luau` — se sumo `RequestRestart` (C -> S).
- `WeaponService` — nueva `resetLoadout`, que usa GameService al empezar una run.
- `scripts/bundle-tests.ps1` — empaqueta tambien `EnemyTactics` y `Data/Enemies`.

**Corregido** (los tres salieron del playtest, no de los tests)

- **EL JUEGO SE VEIA NEGRO.** No un poco oscuro: negro. Se descubrio al mirar la primera captura de pantalla del playtest, y llevaba asi desde la Fase 0 sin que nadie lo notara porque hasta la Fase 3 no habia nada que mirar. Eran **cuatro factores que se multiplicaban**, cada uno razonable por separado:

  1. `ClockTime = 0` (medianoche) dejaba al sol bajo el horizonte: la unica luz era el ambiente.
  2. El ambiente estaba en 0.23, y el ambiente **multiplica** el color de la parte.
  3. Los grises del greybox de sala eran del 23% de luminancia.
  4. El ColorCorrection tenia +0.3 de contraste, que empuja lo oscuro hacia el negro.

  0.23 x 0.23 = **5% de brillo**, y el contraste lo bajaba a ~3%.

  Y encima de todo eso, **la niebla estaba calibrada para otra camara**: `FogStart = 30` con una camara top-down que esta a `sqrt(45^2 + 28^2) = 53 studs` del personaje. El jugador nacia ya un 26% difuminado hacia el negro, las esquinas de su propia sala al 53% y la sala de al lado al 100%. La niebla se comia el campo de juego entero.

  Arreglado subiendo el ambiente, poniendo el sol arriba (sin sombras, que el look plano se conserva), aclarando los grises del greybox al ~40% y moviendo la niebla a 95-240 studs. La regla queda escrita en `Constants`: **FOG_START tiene que ser mayor que la distancia de la camara mas media sala** (53 + 36 = 89), o la sala en la que estas parado se empieza a borrar sola.

- **La escopeta no hacia NADA a quemarropa.** Las balas nacian 2.5 studs adelante del jugador, y un raycast que EMPIEZA dentro de una parte no la detecta: cuando un enemigo se te pegaba (medio ancho 1.3 studs), la boca del arma quedaba dentro de su cuerpo y los perdigones lo atravesaban sin tocarlo. Medido en vivo: **3 impactos a 8 studs, 0 impactos a 3.5**. O sea que el arma dejaba de funcionar justo en el momento en que mas la necesitas, que en un juego de perseguidores es todo el tiempo. Ahora la bala nace en el centro del cuerpo, que es seguro porque `PlayerBullet` no colisiona con `PlayerChar`. Mismo arreglo en las balas del Shooter.
- **El jefe pegaba desde ocho studs mas alla de su propio cuerpo.** El radio de contacto era `4.5 * modelScale`, o sea 11.25 studs para el Bonkaron (escala 2.5), cuando su cuerpo mide 6.5 de ancho. En el playtest se sentia como recibir dano de la nada: moria en 3 salvas estando a 15 studs. Ahora el alcance es "medio cuerpo + margen fijo de 3.2": un Chaser sigue alcanzando los mismos 4.5 de siempre y el jefe alcanza 6.45. Con el arreglo, la misma pelea a 15 studs termino con el jugador a 80 de 130.

**Eliminado**

- `[ANDAMIO]` `src/server/Dev/DevSpawnService.luau` y su carpeta. El spawn de cuerpos lo controla `GameService`, que es lo que ese archivo venia anunciando desde la Fase 0.
- Las dos signals `onRoomLocked` / `onRoomCleared` que habia escrito en `RoomService`: se fueron antes de commitear porque no tenian ni un suscriptor ni uno previsto. Es la misma regla que se aplico en la Fase 3, y esta vez me la aplique a mi mismo.

### Place (Studio)

**Esta seccion se achica a proposito, y es una buena noticia.** La iluminacion dejo de ser configuracion del place y paso a ser codigo (`LightingService`), asi que ya no depende de que alguien la anote aca. Lo que el place siga teniendo configurado a mano queda pisado al arrancar el juego.

Lo que sigue viviendo solo en el `.rbxl`: `Players.CharacterAutoLoads = false`, `Workspace.StreamingEnabled = false`, la `TestArena` y `ReplicatedStorage/Assets`.

### Decisiones

- **El jefe es un enemigo, no un caso especial.** Lo unico que lo distingue es el dato `isBoss`, y de ahi salen sus tres diferencias: su vida escala con la formula del jefe (+60% por jugador) en vez de la comun, lleva el tag `Boss` que hace aparecer la barra grande del HUD, y su muerte termina la run. Ningun sistema pregunta "sos el jefe" fuera de esos tres puntos.
- **Un enemigo muerto no reaparece y un jugador muerto tampoco.** Es un roguelite: la muerte tiene que costar la run. En solitario, morir es la derrota; en co-op, los que quedan siguen y el caido espera (la Fase 6 le agrega el revivir). Esta regla es la razon por la que el respawn automatico de desarrollo tenia que morir con el andamio.
- **La sala se abre si no queda a quien matar, sin preguntar por que.** El plan pedia cubrir el caso del enemigo que se cae de la sala; en vez de cazar cada forma de desaparecer, cada tick comprueba una sola cosa: sala cerrada + cero enemigos vivos = abrir. Preferimos abrir de mas que dejar a alguien encerrado para siempre, que es el bug clasico del genero.
- **La moneda se marca como recogida ANTES de acreditarse.** Es la guarda contra el doble credito que el plan pide explicitamente: en co-op, dos jugadores pueden entrar al radio en el mismo tick y el segundo rebota ahi. Como el bote es comun, cual de los dos la agarro no importa; que se sume una sola vez, si.
- **LootService no conoce a GameService.** Anuncia "se recogieron N monedas" con una signal y quien lleva la cuenta se suscribe. Ademas de evitar el ciclo `GameService -> DungeonGenerator -> LootService -> GameService`, es la regla 2 bien aplicada: el que suelta el loot no sabe para que sirve.
- **El EnemySystem corre a 20 Hz, no a 60.** Un enemigo que decide 20 veces por segundo se comporta igual que uno que decide 60 (el movimiento lo interpola el Humanoid, que si corre a full) y cuesta un tercio. El presupuesto se gasta en tener mas enemigos, no en que cada uno piense mas seguido.
- **La lista de objetivos se arma una vez por tick.** Si cada enemigo recorriera la lista de jugadores por su cuenta, el costo seria enemigos x jugadores; asi es enemigos + jugadores. Con 4 jugadores y una sala del piso 3 eso es la diferencia entre 32 y 12 comprobaciones.
- **Las balas enemigas usan el MISMO ProjectileSystem.** No es ahorro de lineas: heredan gratis el raycast segmentado (nunca `Touched`), el `BulkMoveTo`, el filtrado por CollisionGroup y los popups de dano. Un segundo sistema de balas seria un segundo lugar donde se pierden impactos.
- **Los 30 studs/s de la bala del Shooter son un numero de netcode, no de balance.** A esa velocidad la bala tarda casi un segundo en cruzar los 24 studs que el Shooter mantiene, asi que los 50-100 ms de replicacion no le quitan al jugador la posibilidad de esquivarla. Hay un test que lo fija.
- **El Shooter conserva el rumbo: corrige distancia, no rodea.** Un enemigo que orbita al jugador es ilegible en top-down con niebla. Y la banda muerta de 4 studs existe porque sin ella corrige, se pasa, corrige de vuelta, y tiembla en el lugar en vez de plantarse a disparar.
- **El dano por contacto se resuelve por distancia, no con `Touched`.** `Touched` pierde eventos cuando las cosas se mueven rapido y dispara de mas cuando se rozan. Una comparacion de distancia es determinista y ademas deja elegir el radio.
- **`RunEndView` es una sola View para Victoria y Derrota.** Son el mismo panel con distinto texto y distinto color; dos archivos con el 90% repetido significan que el dia que se agregue "monedas depositadas al banco" (Fase 7) hay que acordarse de tocar los dos.

### Verificacion

- **115 tests, 0 fallos** (63 ms), corriendo los archivos reales del repo con `scripts/bundle-tests.ps1` dentro de Studio.
- **El rig de enemigo se audito construyendolo de verdad en Studio**: el Humanoid encuentra su RootPart, `MoveTo` no explota, la escala del jefe se aplica al cuerpo entero, y tanto el Chaser como el Bonkaron nacen APOYADOS en el piso (0.20 y 0.50 studs de despeje). Esa auditoria encontro un bug antes del playtest: `HipHeight` es la distancia entre la BASE del RootPart y el piso, no la altura del personaje; como estaba (proporcional al cuerpo), el Bonkaron habria flotado 3 studs.

#### PLAYTEST EN VIVO (Studio, servidor y cliente corriendo)

Se hizo con `scripts/sync-place.ps1` para meter el codigo al place y manejando al jugador por script. **Arranco sin un solo error**: 14 servicios en el servidor, 10 en el cliente.

Lo que se comprobo jugando, no leyendo:

| Lo que se probo | Resultado |
|---|---|
| Piso generado y jugador en la sala de inicio | 7 salas (Combat x4, Item x1, Portal x1, Start x1), 10 puertas, 42 puntos de spawn, 2 armas en la sala de objetos |
| Entrar a una sala de combate | puertas **0/2 -> 2/2 cerradas**, 3 enemigos (2 chaser + 1 shooter) |
| Enemigos persiguiendo | estado `Running`, network owner del servidor, apoyados en el piso |
| Dano por contacto | mato al jugador quieto en ~4 s |
| Limpiar la sala | 3 enemigos **-> 0**, puertas **2 -> 0** (se abrio sola) |
| Monedas | 3 en el suelo y **6 acreditadas** en el HUD por el iman |
| Portales | PISO 1/3 -> 2/3 -> 3/3 |
| Piso final | Boss=1 Combat=6 Item=1 Start=1, **sin Portal** |
| El jefe | tag `Boss`, 400 de vida, cuerpo 6.5x7.5x6.5 (escala 2.5), barra grande en el HUD con "EL BONKARON" |
| Matar al jefe | 18 salvas, 400 **-> 0**, solto **17 monedas** (su rango es 15-25) |
| Pantalla de Victoria | "VICTORIA / EL BONKARON NO VOLVERA A BONKEAR A NADIE / PISO 3 DE 3 / 17 MONEDAS" |
| Pantalla de Derrota | "DERROTA / LA MAZMORRA SIGUE INVICTA", tras morir de verdad |
| Boton Reintentar | run nueva, vida 130/130, de vuelta en la sala de inicio |

Los dos bugs de la seccion **Corregido** salieron de aca y ninguno lo habria encontrado un test: los dos son geometria en movimiento.

Falso positivo que vale anotar: en las capturas de combate aparecian unas cunas naranjas grandes pegadas a las paredes que parecian un artefacto de render. **Eran las puertas cerradas.** Se confirmo proyectando su posicion al viewport: coincidian al pixel. O sea que el aviso visual de "estas encerrado" funciona y se lee de un vistazo. Unico reparo: el naranja de la puerta (214,92,74) esta cerca del rojo del Chaser (198,62,62); si en el playtest humano se confunden, mover uno de los dos.

Hallazgo de balance (no es bug, es informacion): el Bonkaron **es kiteable pero no se le puede disparar de parado**. Orbitando a 12 studs se lo mata sin recibir un solo golpe; a 8 studs, moviendose igual, mata al jugador en 6 salvas. Que la respuesta correcta sea moverse y no plantarse es exactamente lo que se buscaba de un jefe lento y enorme.

- **El formato sigue sin pasar por StyLua** y el lint sin pasar por Selene.

### Pendiente de una pasada humana

- **Formato y lint**: `stylua --check src tests`, `selene src`. Es lo unico que todavia necesita las herramientas de verdad.
- **Jugarlo con las manos.** El playtest automatizado mueve al jugador por teletransporte, asi que hay dos cosas que NO probo y que solo se sienten jugando: que las puertas cerradas frenen de verdad a un jugador que camina contra ellas (el teletransporte las ignora), y el game feel general (si la camara acompana, si la escopeta se siente contundente, si el ritmo de una sala aburre o agobia).
- **Mirar de cerca al Shooter**: es el que mas posibilidades tiene de verse raro (temblar, trabarse contra una pared al retroceder). Si se traba, el sospechoso es `preferredStandPoint` mandandolo a un punto del otro lado de una pared, y la solucion es acotar el destino a la sala, no tocar la tactica.
- **Calibrar el ritmo**: `BASE_ENEMIES_PER_COMBAT_ROOM` (3) si una sala del piso 1 se siente vacia; `ENEMY_CONTACT_COOLDOWN_SECONDS` (1 s) si morir se siente injusto.
- **Co-op**: todo lo anterior se probo con un solo jugador. El escalado por jugadores y el portal por consenso siguen sin tocarse.

---

## [0.4.0] — Fase 3: Mazmorra procedural (+ adelanto de UI) — 2026-08-02

Objetivo de la fase: el dungeon de la version Unity, generado por el servidor y testeado en CI. Al terminar, cada run genera un piso distinto y navegable, y con una semilla fija el piso es identico (que es lo unico que permite reproducir un bug de generacion).

Ademas, y fuera del plan de la fase, se adelanto la UI de la Fase 5: HUD completo y pantalla de seleccion de personaje. El motivo esta en Decisiones.

Estado de partida: una TestArena estatica de 72x72, sin mazmorra, sin estado de run y sin UI.

### Repositorio

**Agregado**

- `src/shared/Logic/Rng.luau` — generador pseudoaleatorio propio (xorshift32) con semilla. Reemplaza a `Random.new(seed)` porque `Random` es un datatype de Roblox y no corre en Lune. Ver Decisiones.
- `src/shared/Logic/DungeonLayout.luau` — **el algoritmo**, puro y sin una sola Instance: caminata aleatoria con regla anti-bloque, BFS de distancias, salida en la sala mas lejana, sala de objetos en un callejon, y el estado de los cuatro lados de cada sala.
- `src/server/World/RoomBuilder.luau` — construye la geometria de una sala (piso, paredes con hueco de 12 studs, puertas, puntos de spawn para la Fase 4).
- `src/server/World/DungeonGenerator.luau` — pega el plano con la geometria, siembra las armas de la sala de objetos, planta el portal y el jefe provisional, y limpia el piso anterior.
- `src/server/World/RoomService.luau` — registro de las salas del piso y consultas sobre ellas.
- `src/server/World/PortalService.luau` — avanza de piso cuando TODOS los jugadores vivos estan en el portal.
- `src/server/Core/GameService.luau` — el estado de la run (fase, piso, monedas) y quien decide cuando se genera el siguiente piso. Replica por `RunStateChanged`.
- `src/client/UI/Theme.luau` — la identidad visual en un solo archivo: paleta, fuente, bordes y constructores de panel, texto y barra.
- `src/client/UI/UIController.luau` — construye el ScreenGui por codigo, arma las Views y escala la UI segun el alto de la pantalla.
- `src/client/UI/Views/HUDView.luau` — vida y energia con rastro, las dos ranuras de arma con la activa en dorado, la habilidad con su enfriamiento, piso, monedas, barra de jefe y destello rojo al recibir dano.
- `src/client/UI/Views/CharacterSelectView.luau` — las tres tarjetas de personaje con stats comparadas, habilidad y arma inicial. Tecla **C**.
- `tests/specs/Rng.spec.luau` y `tests/specs/DungeonLayout.spec.luau` — **29 tests nuevos** (86 en total). Los de la mazmorra no comprueban un piso concreto: comprueban invariantes sobre 60 semillas y, cuando fallan, dicen con cual.
- `scripts/bundle-tests.ps1` — empaqueta los modulos puros y las specs en un unico archivo Luau autocontenido que se pega en la barra de comandos de Studio. Existe porque hubo dos fases seguidas bloqueadas por no tener Lune instalado, y Studio ya es un interprete de Luau. **No reemplaza al CI**, que sigue usando Lune como fuente de verdad; es la salida de emergencia para una maquina que solo tiene Studio. Salida en `build/` (ignorada por Git).

**Cambiado**

- `Constants.luau` — geometria de sala (alto y grosor de pared, grosor de piso), `DUNGEON_ORIGIN`, puntos de spawn por sala y radio de activacion del portal.
- `Tags.luau` — nuevo tag `Portal`.
- `ClientState` — ahora tambien cachea `RunStateChanged`, no solo las stats del jugador.
- `InputController` — ignora el input mientras hay un panel modal abierto. `processedByUi` cubre los clicks, pero no las teclas: sin esto, elegir personaje tambien gastaba la habilidad.
- `[ANDAMIO]` `DevSpawnService` — se le quitaron los pickups de prueba de la TestArena: ahora las armas del suelo salen de las salas de objetos, que es de donde tienen que salir.

**Corregido**

- **El respawn de desarrollo nunca funciono.** Colgaba de `CharacterRemoving`, y con `Players.CharacterAutoLoads = false` el motor no destruye el cuerpo al morir, asi que ese evento no se disparaba jamas: al morir te quedabas tirado en el piso para siempre. Ahora cuelga de `Humanoid.Died`. El bug venia de la Fase 1 y estaba anotado en su changelog como una funcionalidad que existia.
- **Las armas del suelo sobrevivian al cambio de piso.** Los pickups no cuelgan de la carpeta del piso sino de `workspace/Pickups`, y como todos los pisos se construyen sobre el mismo origen, un arma dejada en el piso 1 reaparecia flotando dentro del piso 2. `DungeonGenerator.clear` ahora llama a `PickupService.clearAll`.
- **El portal era una elipse.** En un Part cilindrico de Roblox, X es el eje del cilindro y las otras dos componentes son el diametro; `Vector3.new(10, 12, 10)` daba una seccion ovalada. Ahora es `(1.5, 14, 14)`: un disco.
- **El enfriamiento de la habilidad se dibujaba siempre casi lleno.** Se normalizaba contra el ultimo valor recibido del servidor (que es "cuanto FALTA", no "cuanto DURA"), asi que la fraccion daba ~1 en cada snapshot. Ahora el total sale del `CharacterDef`, que es donde vive.

### Place (Studio)

Sin cambios permanentes. Durante la verificacion se construyo un piso de muestra y se subio la iluminacion para poder verlo; ambas cosas se revirtieron y se confirmo que `ClockTime`, `FogStart`, `FogEnd` y `Brightness` volvieron a sus valores de la Fase 0.

La mazmorra se construye en runtime alrededor de `Constants.DUNGEON_ORIGIN` (0, 0, 1200), lejos de la `TestArena`, que sigue existiendo para pruebas sueltas.

### Decisiones

- **Las salas se construyen POR CODIGO, no clonando prefabs de `ServerStorage/RoomPrefabs`** (el plan pedia prefabs). Motivo: la Fase 0 dejo anotada la deuda "un `.rbxl` reconstruible desde el repo queda pendiente", y con las salas en codigo el piso entero sale de Git — el CI puede construir un place jugable sin que nadie exporte un `.rbxmx`, y una sala no se puede romper en el place sin que aparezca en un diff. **Costo:** una sala generada no tiene la personalidad de una hecha a mano (columnas, cobertura, recovecos). **Punto de reevaluacion:** cuando alguien construya salas de verdad; la costura es una sola funcion (`RoomBuilder.build` pasa a ser "cloná el prefab y configurá los lados") y los sistemas no se enteran.
- **Generador de azar propio en vez de `Random.new(seed)`.** `Random` no existe en Lune, asi que usarlo dejaria a `DungeonLayout` sin poder testearse en CI, que es justo lo que la fase exige. El segundo motivo pesa mas a largo plazo: la implementacion de `Random` es de Roblox, y si cambian su algoritmo, la misma semilla deja de dar la misma mazmorra y se pierde la reproducibilidad de los reportes de bug.
- **El azar se INYECTA en `DungeonLayout` (funcion `nextInteger`), no se importa.** La regla de `Shared/Logic/` prohibe `require` porque Lune y Roblox resuelven rutas distinto. Es el mismo patron que ya usaba `SpreadMath`.
- **La regla anti-bloque tiene una consecuencia gratis que vale la pena documentar: el mapa resultante es un ARBOL.** Si cada sala nueva toca como mucho una vieja, no se pueden formar ciclos. De ahi salen tres cosas sin escribir codigo extra: "la sala mas lejana" esta bien definida, siempre hay callejones donde poner recompensas, y el test de que el piso no tiene bloques 2x2 es una linea (aristas == salas - 1).
- **El jefe provisional es un saco de golpes anclado, no un enemigo.** El Bonkaron con fases es de la Fase 8 y el Chaser escalado de la Fase 4. Este de aca existe para que la run tenga FINAL desde ya, y su unica gracia es que muere por el mismo camino que usara el jefe real (`HealthRegistry.onEntityDied`), asi que cuando llegue no hay que recablear nada.
- **La UI se adelanto de la Fase 5, y no por gusto.** Sin pantalla de seleccion, probar a Nina o a Voltio pedia disparar un RemoteEvent a mano desde la consola del cliente: dos tercios del contenido de la Fase 2 no los veia nadie, y el criterio de aceptacion de esa fase ("las tres habilidades funcionan") no se podia comprobar jugando. El HUD vino con ella porque una barra de vida es la unica forma de ver que el escalado de dificultad de los pisos hace algo.
- **La UI se CONSTRUYE en codigo, no se clona de StarterGui.** `StarterGui` reparte una copia al aparecer y otra al respawnear, con `ResetOnSpawn` metiendo la cola, y en este juego morir es parte del bucle. Ademas una UI en el `.rbxl` no tiene diff, y las tarjetas de personaje se arman con datos que ya viven en el repo: hacerlas a mano en Studio seria copiar numeros que ya estan escritos y desincronizarlos en el primer rebalanceo. **Costo aceptado:** cada margen es un numero en un archivo, sin editor visual.
- **Cero esquinas redondeadas en todo el proyecto** (`Theme`, regla 1 del look). El redondeo es el tic visual de la UI moderna y es exactamente lo contrario del estilo: en 1997 no habia antialiasing para curvarle la esquina a un rectangulo.
- **Las barras de vida y energia tienen "rastro".** Una barra que salta de 100 a 60 sin transicion no comunica cuanto te pegaron; el rastro deja ver el mordisco. El suavizado usa `1 - exp(-velocidad * dt)` por el mismo motivo que la camara: con alpha fijo, el rastro se moveria mas rapido a 144 fps que a 60.
- **El enfriamiento se interpola en el cliente entre snapshots.** El servidor manda el valor 10 veces por segundo; dibujarlo tal cual daria una barra a escalones. La verdad sigue siendo del servidor: esto es interpolacion visual entre dos verdades, no una cuenta propia.
- **El portal exige a TODOS los jugadores vivos, no a todos los jugadores.** Un caido de la Fase 6 no puede caminar hasta el portal, y exigirselo dejaria al grupo encerrado en el piso.

### Verificacion

- **20 checks en verde** ejecutando `Rng` + `DungeonLayout` dentro de Roblox Studio (`execute_luau`), sobre **60 semillas por invariante**: conteo exacto de salas (2, 7, 8, 9 y 15), cero celdas encimadas, el mapa es un arbol (regla anti-bloque), todas las salas alcanzables, un solo inicio y en el origen, Portal en pisos intermedios y Jefe en el ultimo (nunca los dos), la salida siempre es la sala mas lejana y nunca esta pegada al inicio, sala de objetos siempre en callejon, y los lados abiertos coinciden exactamente con las salas vecinas.
- **Reproducibilidad confirmada**: la misma semilla da el mismo piso; semillas distintas dan pisos distintos.
- **Geometria verificada construyendo un piso real en Studio**: 8 salas, 66 partes, 11 puertas, y cero problemas de encaje — las paredes de dos salas vecinas se tocan exactamente (sin superponerse ni dejar hueco) y el vano mide exactamente los 12 studs declarados.
- La inspeccion VISUAL del piso no se pudo hacer: en modo Edit, Studio le pisa el `CFrame` a la camara del viewport, asi que las capturas salieron desde lejos. Queda para el playtest.
- **LA SUITE COMPLETA CORRIO: 86 tests, 0 fallos** (52 ms). No con Lune —sigue sin haber toolchain en la maquina— sino con `scripts/bundle-tests.ps1` dentro de Studio. Importante: se ejecutaron **los archivos reales del repo**, no copias retipeadas como en las verificaciones anteriores, asi que esto tambien confirma los 27 tests de la Fase 2 que habian quedado escritos pero sin ejecutar.
- El unico fallo que aparecio (2 tests de cobertura de `ContentData.spec`) era **del bundler, no del proyecto**: la regex generica de `require` se comia `require("@lune/fs")` y lo convertia en un modulo inexistente. Corregido en el script y confirmado en verde.
- **El formato sigue sin pasar por StyLua** y el lint sin pasar por Selene: eso si necesita las herramientas de verdad.

### Pendiente de una pasada humana

- **Formato y lint**: es lo unico que todavia necesita las herramientas de verdad (`stylua --check src tests`, `selene src`). Los tests ya no las necesitan. Si StyLua reformatea algo, commitear el diff.
- **Playtest de la run completa**: aparecer en la sala de inicio, recorrer el piso, encontrar la sala de objetos, pararse en el portal, llegar al piso 3, romper al Bonkaron provisional y ver la pantalla volver al piso 1 a los 12 segundos.
- **Mirar el HUD con ojos de jugador**: los tamanos estan calculados para 900 px de alto y escalados desde ahi. Lo mas probable que haya que tocar son las posiciones de las dos ranuras de arma en pantallas anchas.
- **Calibrar**: alto de pared (16 studs) contra la camara a 45 — si se ve el interior de la sala de al lado, subirla; y `PORTAL_ACTIVATION_RADIUS_STUDS` (10), que en co-op tiene que dar lugar a cuatro cuerpos.

---

## [0.3.0] — Fase 2: Datos, energia y habilidades — 2026-08-01

Objetivo de la fase: activar la regla 1 (contenido = datos) y matar el hardcodeo de la Fase 1. Al terminar, cambiar un numero en un archivo de datos cambia el juego sin tocar un solo sistema, y agregar un arma nueva son dos lineas.

Estado de partida: un arma hardcodeada dentro de `WeaponService`, un personaje hardcodeado dentro de `CharacterService`, cero energia, cero habilidades, cero inventario.

### Repositorio

**Agregado**

- `src/shared/Data/Weapons/` — las 6 armas del diseno (`LaFiel`, `LaCotorra`, `ElTridente`, `LaEscupechatarra`, `ElDedoDeDios`, `ElMeteoroQuesero`) con los valores de la seccion 5 del documento de contexto, mas `init.luau` como registro (`getById`, `expect`, `randomId`, `ids`).
- `src/shared/Data/Characters/` — Don Bonko, Nina La Rafaga y El Profe Voltio, mas `init.luau` con la misma forma de registro y `defaultId`.
- `src/shared/Logic/ContentSchema.luau` — validador de contenido, puro y testeable. Los registros lo corren **al cargarse**: un arma con un campo roto no deja levantar el servidor, con un mensaje que dice que campo es.
- `src/server/Combat/EnergyService.luau` — energia por jugador con regeneracion en un unico Heartbeat, `trySpend` todo-o-nada y valores tomados del `CharacterDef`. No regenera a los muertos.
- `src/server/Combat/AbilityService.luau` — las 3 habilidades con costo y cooldown validados en servidor. Dash concede invulnerabilidad; DualWield y RapidFire son flags con vencimiento que consulta `WeaponService`.
- `src/server/World/PickupService.luau` — armas en el suelo por tag, con `randomPool` cuando el Attribute `WeaponId` viene vacio, validacion de distancia y de "reclamado" (co-op: dos E en el mismo frame), y drop del arma desplazada con ventana de armado.
- `src/server/Core/PlayerStatsReplicator.luau` — un unico snapshot por jugador a 10 Hz, con comparacion contra lo ultimo enviado. Parado y con las barras llenas no manda nada.
- `src/client/State/ClientState.luau` — cache de solo lectura del ultimo `PlayerStatsSnapshot`. Hoy la usa `InputController`; en la Fase 5 se le enchufan las Views encima sin tocarla.
- `src/client/Character/AbilityEffects.luau` — el impulso del Dash, aplicado en el cliente (ver Decisiones).
- `src/client/FX/PickupView.luau` — cartelito `[E] <arma>` y flotar/girar de los pickups, todo local, en un unico RenderStep para todos.
- `tests/specs/ContentSchema.spec.luau` y `tests/specs/ContentData.spec.luau` — **27 tests nuevos** (57 en total). El segundo carga los archivos de datos REALES y ademas compara la lista de armas y personajes que valida contra los archivos que hay en disco: agregar un arma y olvidarse de sumarla a la spec falla el CI en vez de pasar en silencio.

**Cambiado**

- `WeaponService` — dos ranuras por jugador, `SwapWeapon` (Q) con su unica validacion real ("tiene segunda arma"), cadencia derivada del arma equipada por el multiplicador de Sobrecarga, cobro de energia antes de disparar y salva doble durante el Doble Bonk (dos bocas de fuego separadas). Expone `equip` para `PickupService`.
- `CharacterService` — vida, velocidad y color salen del `CharacterDef`. Se agrego seleccion de personaje (`select` + remote `SelectCharacter`), por ahora validando solo que el id exista.
- `InputController` — se sumaron Q, E y ESPACIO. El ritmo de envio de `FireRequest` ya no es fijo: sale del arma equipada, y las armas semiautomaticas mandan una intencion por click.
- `Types.luau` — nuevo tipo `Rgb`; `greyboxColor` y el nuevo `projectileColor` lo usan en vez de `Color3`. `PlayerStatsSnapshot` sumo `activeSlot`, `fireRateMultiplier` y `isDualWielding`. Nuevo `AbilityActivatedPayload`.
- `Remotes.luau` — se sumo `AbilityActivated` (S -> dueno, confiable). Es el unico remote agregado al contrato original.
- `Constants.luau` — `DUAL_WIELD_MUZZLE_OFFSET_STUDS`, `WEAPON_DROP_FORWARD_STUDS`, `PICKUP_ARM_DELAY_SECONDS`.
- `[ANDAMIO]` `DevSpawnService` — deja una de cada arma en el suelo de la TestArena al arrancar, para poder probar las dos ranuras sin colocar pickups a mano. Se borra en la Fase 3, cuando las armas las traiga el prefab de la sala de objetos.

**Corregido**

- `BreakableService` — una tilde en un comentario que violaba la regla de encoding del proyecto.

### Place (Studio)

Sin cambios. Todo lo de esta fase es codigo; los pickups de prueba los crea el andamio al arrancar el servidor, no estan guardados en el `.rbxl`.

### Decisiones

- **Los modulos de `Shared/Data/` heredan la regla de `Shared/Logic/`: sin `require` y sin datatypes de Roblox.** Por eso los colores son `{r, g, b}`. El beneficio concreto: el test del CI carga el MISMO archivo que carga el servidor, no una copia de fixtures que se desincroniza al primer cambio. **Costo:** cada consumidor construye su `Color3` (una linea), y `Types.luau` gano el tipo `Rgb`. **Alternativa descartada:** validar solo el validador con fixtures; el contenido real habria quedado sin red.
- **Los registros (`Data/*/init.luau`) validan al cargarse y revientan.** Un servidor que no levanta con un mensaje claro cuesta muchisimo menos que un arma con `damage = nil` descubierta a mitad de una run con cuatro jugadores.
- **La lista de armas del registro es explicita, no un `script:GetChildren()`.** Orden determinista (importa para la UI de la Fase 5) y un archivo mal nombrado se nota al instante. Misma decision que ya se tomo con las specs en `tests/run.luau`. El riesgo de la lista repetida en la spec se cubre con el bloque de cobertura que compara contra el disco.
- **`AbilityActivated`: el servidor decide, el cliente empuja.** El cliente es el dueno de red de su propio personaje, asi que un impulso escrito desde el servidor se pisa con el siguiente paquete de fisica del cliente. Y aunque no se pisara, esperar un round-trip para moverse arruina justo la habilidad que mas depende del timing. Lo que el permiso le concede a un exploiter es moverse rapido un tercio de segundo: la energia ya se cobro, el cooldown ya arranco y la invulnerabilidad la controla el servidor con duracion fija. **Punto de reevaluacion: Fase 6**, si en co-op aparece teletransporte.
- **El Dash usa velocidad directa, no impulso escalado por masa.** Un impulso se suma a la velocidad que ya llevabas, asi que dashear corriendo llegaria mas lejos que dashear parado y la habilidad no se podria calibrar.
- **La replicacion de stats es UN modulo, no una por servicio** (el plan la pedia dentro de `EnergyService`). Vida, energia, loadout y cooldown se dibujan en el mismo HUD y cambian a la vez: tres remotes serian tres throttles y tres oportunidades de mostrar una energia de este frame junto a una vida del anterior. `EnergyService` y `WeaponService` siguen sin saber que existe una UI.
- **Los valores continuos se MUESTREAN, no se emiten por signal.** La energia cambia todos los frames; una signal por cambio serian 60 mensajes por segundo por jugador para mover una barra que se replica a 10 Hz. La regla 2 sigue valiendo para eventos discretos (murio, cambio de arma).
- **`isAutomatic` se aplica en el cliente, no en el servidor.** Que El Dedo de Dios sea de un click por disparo es game feel, no seguridad: un cliente modificado que mantenga el fuego choca igual contra la cadencia del arma. Validar "clicks reales" seria inventar un estado imposible de verificar.
- **La cadencia durante el Doble Bonk la marca el arma ACTIVA.** Si la marcara la mas rapida de las dos, la ulti de Bonko seria tambien un buff de cadencia encubierto y se pisaria con la de Voltio.
- **El loadout sobrevive a la muerte, pero no a cambiar de personaje.** Morir y perder las armas recogidas haria imposible probar nada hoy y sera decision de `GameService` en la Fase 4; cambiar de personaje si las resetea, porque el arma inicial es parte de la definicion del personaje.
- **Las armas del `Data/` no llevan `Color3` pero si `projectileColor`.** Se agrego al esquema (no estaba en el diseno original) porque en un top-down con niebla densa leer las balas ES el juego, y el color por arma es la forma mas barata de saber que te esta llegando.

### Verificacion

- **22 checks en verde** ejecutando `ContentSchema` y el contenido real dentro de Roblox Studio (`execute_luau`, datamodel Edit): las 6 armas y los 3 personajes cumplen el esquema, los rechazos funcionan (campo faltante, `fireRate = 0`, NaN, color fuera de rango, ids duplicados, `kind` desconocido, habilidad mas cara que la energia maxima) y el intervalo `1/fireRate` de las 6 armas es finito.
- La lista de archivos de `Data/` en disco coincide con la que valida `ContentData.spec`.
- **No se pudo correr `lune run tests/run`, `stylua --check` ni `selene` en esta maquina: no hay toolchain instalada** (ni `rokit`, ni `lune`, ni `stylua`, ni `selene`, ni `rojo`). Los 27 tests nuevos estan escritos contra el runner del repo pero **no se ejecutaron**; el formato tampoco se verifico contra StyLua. Es lo primero que hay que correr al abrir esta rama.

### Pendiente de una pasada humana

- ~~**Instalar la toolchain y correr el CI local**~~. **Resuelto en 0.4.0**: los 27 tests de esta fase se ejecutaron con `scripts/bundle-tests.ps1` dentro de Studio, en verde, sin instalar nada. Quedan pendientes solo el formato (StyLua) y el lint (Selene).
- **Playtest**, que es el criterio de aceptacion real de la fase: recoger armas con E, alternar con Q, ver la energia bajar y volver, y probar las tres habilidades con ESPACIO (para cambiar de personaje hoy hay que disparar el remote `SelectCharacter` desde la consola del cliente: `game.ReplicatedStorage.Remotes.SelectCharacter:FireServer({ characterId = "nina_rafaga" })`).
- **Calibrar a ojo**: el knockback de cada arma (`knockback` en su archivo de datos) es la tanda de numeros con menos fundamento del contenido nuevo; se eligieron por proporcion, no por playtest. Tambien la separacion de las dos bocas de fuego del Doble Bonk (1.5 studs) y la distancia a la que cae el arma que se suelta (4 studs).

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

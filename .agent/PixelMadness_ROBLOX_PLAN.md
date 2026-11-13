# PixelMadness (Edición Roblox): Plan de Desarrollo
> Documento hermano de PixelMadness_ROBLOX_CONTEXTO.md. Define decisiones fundacionales con trade-offs, fases con criterios de aceptación, estrategia anti-exploit, pruebas/CI, y el plan para explotar la idea original en la plataforma Roblox (co-op, meta-progresión, monetización, LiveOps). Última actualización: agosto 2026.

---

## 0. Objetivo y criterios de éxito

**Objetivo**: llevar el loop completo de PixelMadness (menú → run de 3 pisos → jefe → victoria/derrota) a Roblox como experiencia jugable multijugador de 1-4 jugadores, con meta-progresión persistente, en calidad "vertical slice pulido" antes que "20 sistemas a medias" (principio heredado del roadmap Unity).

**Criterios de éxito del MVP público**:
1. Una run completa solo o en co-op sin errores bloqueantes, con las fórmulas de dificultad originales más escalado por jugadores.
2. Los 3 personajes y las 6 armas funcionando desde datos, con sus habilidades.
3. Monedas persistentes entre sesiones (ProfileStore) y al menos 1 desbloqueo comprable con monedas.
4. Ningún exploit trivial: disparar más rápido, curarse, duplicar monedas o matar enemigos desde el cliente debe ser imposible.
5. Sesión media ≥ 8 minutos y retención D1 medible con AnalyticsService (números objetivo se calibran tras el soft launch).

---

## 1. Decisiones fundacionales (con trade-offs y recomendación de producción)

### D1. Personaje: Humanoid estándar vs controlador custom
- **Humanoid** (recomendado, producción): movimiento WASD, replicación con predicción, animaciones, muerte/ragdoll y compatibilidad móvil/gamepad futuros, todo gratis. Costo: menos control fino sobre la física (aceptable en un top-down sin plataformeo).
- **Custom**: control absoluto, semanas de trabajo en netcode que Roblox ya resuelve.
- **Decisión**: Humanoid con `AutoRotate=false`, salto deshabilitado, rotación hacia el mouse en cliente. Revisar solo si el game feel lo exige tras la fase 8.

### D2. Vida: Humanoid.Health vs módulo Health propio
- **Humanoid.Health**: gratis pero limitado (no sirve para rompibles, tiene regeneración nativa oculta, y es manipulable por scripts ajenos si no se blinda).
- **Health propio en servidor** (recomendado, producción): universal (jugador, enemigo, jefe, rompible), eventos propios, invulnerabilidad y escalado controlados, imposible de tocar desde el cliente. El Humanoid queda como "actuador" de muerte visual.
- **Decisión**: Health propio; eliminar el script de regeneración nativa del personaje.

### D3. Proyectiles: física nativa vs sistema propio; servidor vs cliente
- **Touched/física nativa**: descartado, `Touched` pierde colisiones a alta velocidad y las balas físicas replicadas generan tráfico y jitter.
- **Sistema propio en servidor** (MVP): una tabla de balas avanzada por Heartbeat con raycasts segmento a segmento y Parts ancladas movidas con `BulkMoveTo`. Simple, autoritativo, las balas enemigas son esquivables porque son lentas (30 studs/s tolera bien los ~50-100 ms de latencia de replicación).
- **Visuales en cliente + lógica en servidor** (fase de optimización): el servidor simula posiciones sin Parts y emite `FXEvent`; cada cliente renderiza sus balas localmente (suavidad perfecta, mínimo tráfico). Más complejo: requiere reconciliación visual.
- **Decisión**: MVP 100% servidor (simplicidad y anti-exploit primero); migrar visuales a cliente en fase 8 SOLO si el playtest muestra balas entrecortadas o el profiler muestra costo de replicación. No optimizar antes de medir.

### D4. Alcance multijugador del MVP
- **Solo single-player**: desperdicia la razón principal de migrar a Roblox.
- **Co-op completo desde el día 1**: riesgo de complejidad (revivir, escalado, portal por votación) antes de validar el core.
- **Decisión escalonada** (recomendada): fases 1-5 se construyen "multiplayer-correct" (servidor autoritativo, sin suposiciones de 1 jugador: nada de `Players:GetPlayers()[1]`) pero se prueban en solo; la fase 6 activa el co-op real (lobby ready-up, escalado, revivir, portal por votación). Así el co-op no es un rewrite sino un switch.

### D5. Arquitectura de places: un place vs hub + reserved servers
- **Un place** (MVP): lobby y dungeon conviven; servidores de 4 jugadores; simple, cero TeleportService.
- **Hub + reserved servers** (escala): lobby social masivo + runs en servidores reservados por party (patrón Dungeon Quest). Mejor para social/discovery, más infraestructura (teleport data, manejo de fallos de teleport).
- **Decisión**: un place hasta validar retención; hub en fase 9 si las métricas lo justifican.

### D6. Toolchain y colaboración
- **Todo en Studio**: descartado (sin PRs, sin tests, sin CI, colisiones de edición).
- **Rojo + Git + Wally + StyLua + Selene + Lune** (recomendado, producción): código revisable, testeable en CI, formateado; Studio solo para construir prefabs y probar. Lección aprendida del equipo aplicada: verificación de UI vía datamodel de Cliente con el plugin MCP; nunca `user_mouse_input`/`character_navigation`.
- **Decisión**: Rojo desde el commit 1. Los prefabs de sala se versionan como `.rbxmx` exportados (o vía sync de Rojo) para que el place sea reconstruible desde el repo.

### D7. Estrategia de pruebas
- La lógica pura va a `Shared/Logic/` sin dependencias de Instances: `DungeonLayout` (random walk + anti-bloque + BFS), `SpreadMath` (abanico + jitter), `DifficultyMath` (multiplicadores por piso y por jugadores), validadores de esquemas de datos. Se testean con TestEZ/Jest-Lua ejecutados por **Lune en CI** (sin abrir Studio), replicando el enfoque TDD del motor de Dirty Pig.
- Los sistemas con Instances (RoomService, ProjectileSystem) se prueban con harness en Studio + smoke tests manuales guiados por checklist.
- **Decisión**: TDD estricto en `Shared/Logic/`; pragmatismo en el resto.

---

## 2. Fases de desarrollo

Cada fase lista: objetivo, tareas, entregable y criterios de aceptación (CA). Los estimados asumen 2-3 personas a tiempo parcial; son orientativos, el orden es lo importante.

### Fase 0: Fundaciones del repositorio (1 semana)
**Objetivo**: que el proyecto sea colaborable, testeable y reconstruible antes de escribir gameplay.
- Repo Git con layout Rojo de la sección 4 del contexto; `default.project.json` mapeando server/client/shared.
- Wally: Signal, ProfileStore, TestEZ o Jest-Lua. Versiones fijadas.
- StyLua + Selene configurados; GitHub Actions: lint + formato + tests Lune + `rojo build` que produce el `.rbxl` como artifact en cada PR.
- `Shared/`: `Types.luau`, `Constants.luau`, `Tags.luau`, `CollisionGroups.luau`, `Remotes.luau` (esqueletos tipados).
- Boot scripts: server bootstrap (registra CollisionGroups, inicializa servicios en orden explícito) y client bootstrap.
- Place base: iluminación con niebla PSX (config de 15 minutos de la sección 7 del contexto), `CharacterAutoLoads=false`, StreamingEnabled=false.

**CA**: un colaborador nuevo clona, corre `rojo serve`, abre Studio y ve el place base con niebla; el CI pasa en verde; un test trivial de `Constants` corre en Lune.

### Fase 1: Núcleo jugable: moverse, apuntar, disparar (1-2 semanas)
**Objetivo**: la sensación Soul Knight en una sala estática de prueba.
- `InputController` + `AimProvider` (intersección rayo-plano) + `TopDownCamera` (offset (0,45,-28), Lerp, look-ahead).
- Spawn de personaje greybox (R6 coloreado) con AutoRotate off, salto off, rotación al mouse.
- `Health` (clase) + `HealthRegistry`; dummy rompible taggeado `Breakable` para probar daño.
- `WeaponService` mínimo (1 arma hardcodeada temporal La Fiel) + `ProjectileSystem` (Heartbeat único, raycast segmentado, BulkMoveTo, filtros por CollisionGroup) + `FireRequest` validado (cadencia y vector).
- `DamagePopups` en cliente vía `DamageDealt`.

**CA**: en una sala de prueba, el jugador se mueve con WASD, el personaje mira al mouse, dispara La Fiel con cadencia correcta, los popups aparecen sobre el dummy, y el dummy muere emitiendo `OnDeath`. Un segundo jugador en Test → Start Server con 2 clientes ve TODO correctamente replicado (criterio multiplayer-correct desde ya).

### Fase 2: Datos: armas, personajes, energía y habilidades (1-2 semanas)
**Objetivo**: activar la regla 1 (contenido = datos) y matar el hardcodeo de la fase 1.
- `Shared/Data/Weapons/` con las 6 armas y `Shared/Data/Characters/` con los 3 personajes (valores de la sección 5 del contexto). Test de esquema en CI: toda definición cumple `WeaponDef`/`CharacterDef`.
- `EnergyService` (regen por tick, `TrySpend`), réplica al dueño (throttled).
- `WeaponService` completo: 2 ranuras, Q alterna, `LoadoutChanged`.
- `AbilityService`: Dash (impulso + invuln servidor), DualWield (flag 5 s), RapidFire (multiplicador de cadencia 4 s), costos y cooldowns.
- `PickupService` + pickups con randomPool; E para recoger con validación de distancia; soltar arma vieja como pickup.
- `SpreadMath` con tests (abanico uniforme + jitter ±2°, La Escupechatarra dispara 6 proyectiles en 35°).

**CA**: cambiar un número en un módulo de datos cambia el juego sin tocar sistemas; agregar un arma nueva de prueba toma < 10 minutos y cero lógica; las 3 habilidades funcionan con costo/CD validados en servidor; un cliente modificado que spamea `FireRequest` no supera la cadencia del arma (test manual con delay artificial).

### Fase 3: Mazmorra procedural (1-2 semanas)
**Objetivo**: el dungeon de Unity, generado por el servidor, testeado en CI.
- `Shared/Logic/DungeonLayout.luau` PURO, con TDD: random walk en grilla, regla anti-bloque (celda nueva con máximo 1 vecino), BFS sala más lejana, asignación Start/Combat/Item/Portal/Boss, `roomCount = 7 + piso - 1`, seed reproducible. Tests: misma seed → mismo layout; ninguna celda con > 1 vecino al crearse; siempre existe exactamente 1 Boss o Portal; siempre ≥ 1 dead-end de objetos cuando hay dead-ends disponibles.
- Prefabs de sala en `ServerStorage/RoomPrefabs` (6 variantes, 72×72 studs, atributos y tags, spawn points, cero scripts internos).
- `DungeonGenerator` servidor: clona salas según layout, configura lados (SolidWall/OpenWall/Door) y registra en `RoomService`.

**CA**: cada run genera un dungeon navegable distinto; con seed fija el layout es idéntico (debug); los tests de layout pasan en CI; caminar los pasillos con 2 clientes no muestra huecos ni paredes mal configuradas.

### Fase 4: Salas de combate, enemigos y flujo de run (2 semanas)
**Objetivo**: el loop de presión de Soul Knight: entrar, encerrarse, limpiar, avanzar.
- `RoomService`: detección de entrada, cierre de puertas para todos, spawn de enemigos escalado (`DifficultyMath`: multiplicador de vida por piso + co-op), apertura al limpiar; Start/Item nunca encierran.
- `EnemySystem` + brains Chaser y Shooter (targeting al jugador vivo más cercano, `SetNetworkOwner(nil)`, daño por contacto con cooldown validado, EnemyBullet en el mismo ProjectileSystem con CollisionGroup propio).
- `LootService`: monedas con explosión, imán servidor-validado con vuelo animado en cliente, bote común de run, autodestrucción 30 s.
- `PortalService` y `GameService.NextFloor`: despawn del piso, regeneración, teleport del grupo; jefe provisional (Chaser 2.5×) y `BossDefeated` → estado Victoria; muerte de todos → Derrota. Paneles Victoria/Derrota mínimos con Reintentar/Lobby.

**CA**: run completa de 3 pisos jugable de inicio a fin, solo y con 2 jugadores; la dificultad escala por piso con las fórmulas originales; las puertas jamás quedan cerradas con la sala limpia (bug clásico: cubrir el caso de enemigos que caen fuera de la sala); las monedas nunca se acreditan dos veces.

### Fase 5: Lobby, selección de personaje y HUD completo (1-2 semanas)
**Objetivo**: reemplazar las "escenas" de Unity por estados del place con UI de calidad.
- `LobbyService` (estados Lobby/EnRun por servidor), `SelectCharacter` + `SetReady`, countdown de inicio.
- `UIController` + `ClientState` + Views: MenuView, CharacterSelectView (stats + flavor + color), HUDView (vida, energía, arma activa y secundaria, monedas, piso X/Y, nombre del personaje), VictoryView, DefeatView. Snapshot inicial del servidor al spawnear (adiós al hack Invoke 0.05 de Unity).
- Estilo UI pixel (fuente pixel, `ResampleMode=Pixelated` en imágenes, paleta del juego).

**CA**: flujo Menú → selección → run → victoria/derrota → menú sin recargar el servidor; el HUD refleja todo estado en < 200 ms; con 4 jugadores cada quien ve SU vida/energía/loadout y las monedas comunes.

### Fase 6: Co-op real (1-2 semanas)
**Objetivo**: convertir "multiplayer-correct" en "multiplayer-fun".
- Ready-up con countdown; entrada de jugadores a mitad de run como espectadores hasta el siguiente piso (decisión inicial, revisable).
- Revivir: jugador a 0 HP entra en estado Caído 30 s; aliado mantiene E cerca 3 s para levantarlo con 30% de vida; si nadie lo revive, espectador hasta el próximo piso; derrota solo si TODOS caen.
- Portal por consenso: todos en la sala Portal o mayoría + countdown 10 s.
- Escalado co-op de `DifficultyMath` activado y balanceado a ojo (+40% HP y +1 enemigo por jugador extra; jefe +60%).
- Playtest dedicado de 4 jugadores con checklist (targeting de enemigos, reparto de pantalla de loot, puertas, revivir bajo fuego).

**CA**: una run de 4 se siente cooperativa, no caótica; caer y ser revivido funciona bajo combate; nadie puede "secuestrar" el portal.

### Fase 7: Persistencia y meta-progresión (2 semanas) [el gancho Soul Knight]
**Objetivo**: razón para volver mañana.
- `PlayerDataService` con ProfileStore (session locking, schema versionado, reconciliación de defaults): monedas del banco, personajes desbloqueados, estadísticas (runs, victorias, mejor tiempo).
- Al terminar la run (victoria O derrota): monedas del bote se reparten equitativamente y se depositan al banco de cada jugador.
- Tienda del lobby v1: desbloquear a Nina y Voltio con monedas (Bonko gratis); precios iniciales para ~3-5 runs por desbloqueo.
- Leaderboard global (OrderedDataStore): victorias totales y mejor tiempo de run, tablero físico en el lobby.
- AnalyticsService: funnel de run (inicio, piso 2, piso 3, jefe, victoria), economía (monedas ganadas/gastadas).

**CA**: cerrar Roblox y volver conserva monedas y desbloqueos; no hay pérdida de datos al cerrar el servidor a mitad de run (guardar en hitos, no solo al final); el leaderboard se actualiza; no existe forma cliente de otorgarse monedas.

### Fase 8: Game feel y estética (2-3 semanas, en paralelo parcial con 6-7)
**Objetivo**: el salto de "funciona" a "se siente increíble" (prioridad 1 del roadmap Unity original).
- `FXEvent` (unreliable) + `GameFeel` cliente: sonido de disparo por arma, partículas de impacto y muerte, muzzle flash, screen shake (impulso sobre `ShooterCamera`, que reemplazó a `TopDownCamera` en Fase 6), hit-stop simulado (micro-freeze visual de 0.05 s SOLO en el cliente, jamás pausar el servidor).
- Look final del place: niebla densa afinada, ColorCorrection, materiales/texturas 64px en salas, R6 rigs de los 3 personajes con sus siluetas (masa naranja / angular cian / bata chamuscada).
- Optimización si el profiler lo pide: balas visuales en cliente (decisión D3 fase 2), pooling de Parts de balas y monedas, `task` budget del EnemySystem.
- Jefe real "El Bonkarón" con fases sobre la base Shooter (patrones de balas + fases por % de vida), aprovechando que los patrones son datos.

**CA**: disparar La Escupechatarra se siente como un evento; 4 jugadores + 20 enemigos + 100 balas mantienen 60 fps en cliente de gama media y el servidor bajo 30% de su presupuesto de Heartbeat; el jefe tiene mínimo 2 fases legibles.

### Fase 9: Lanzamiento y LiveOps (continuo)
**Objetivo**: explotar la plataforma.
- Soft launch sin publicidad: pulir con métricas reales (retención D1/D7, session time, funnel de run, crash de servidores).
- Página del juego: icono y thumbnails con el humor del juego, nombre, descripción con keywords del género (roguelike, dungeon, co-op).
- Monetización ética v1 (ver sección 4): cosméticos y conveniencia, nunca poder puro.
- Cadencia de contenido: 1 arma o variante de sala nueva cada 1-2 semanas (costo casi cero por la regla 1), eventos temporales (fin de semana de monedas dobles vía flag de servidor).
- Evaluar hub + reserved servers (D5) y soporte móvil/gamepad (la capa de input aislada lo permite) según métricas.

**CA**: pipeline de release documentado (PR → CI verde → build → publish); primer update de contenido entregado sin tocar sistemas.

---

## 3. Estrategia anti-exploit (transversal, se aplica desde la fase 1)

1. El cliente solo envía intenciones; el servidor recalcula todo (regla 5 del contexto).
2. Validación por Remote: tipos y rangos (vectores unitarios, ids existentes), cadencia con tolerancia 10%, distancia para pickups/revivir, estado (vivo, en run, en lobby).
3. Rate limiting genérico por jugador y por Remote (presupuesto de N llamadas/s; exceso = drop silencioso + log).
4. Enemigos y objetos del mundo siempre con network ownership del servidor.
5. Nada de valores sensibles en atributos escribibles por el cliente; la réplica de stats es de solo lectura para la UI.
6. Telemetría de anomalías: daño/segundo imposible, monedas/minuto fuera de rango → log para revisión, no ban automático en MVP.

---

## 4. Monetización y explotación de la idea (diseño, no implementación temprana)

Principio: PixelMadness compite en Roblox por diversión y respeto al jugador; el modelo Soul Knight (free + compras justas) es la referencia.

- **Nunca vender**: daño, vida, armas más fuertes que las gratuitas.
- **Vender (Game Passes / Dev Products)**: skins de personajes y de armas (el humor del juego es una mina: "La Fiel, edición dorada. Sigue sin impresionar."), gestos/burlas, aura de bala cosmética, slot de "arma favorita al iniciar" entre las ya desbloqueadas (conveniencia, no poder), y quizá un personaje adicional SIEMPRE desbloqueable también con monedas jugando.
- **Retención**: recompensa diaria con racha (sistema ya dominado por el equipo), misiones simples ("mata 50 enemigos con La Cotorra"), leaderboards, private servers gratis o baratos para jugar con amigos.
- **Social/discovery**: co-op es el motor de crecimiento orgánico en Roblox (invitar amigos); diseñar el lobby para que se vea actividad (leaderboard físico, maniquíes con skins).

---

## 5. Riesgos globales y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Balas replicadas se ven entrecortadas | Game feel del núcleo | Balas lentas por diseño; plan B listo (visuales en cliente, D3) |
| Latencia arruina el "leer balas" | Core loop | Balas enemigas MUY lentas y grandes (ya es el diseño); hitbox del jugador generosa a favor del jugador |
| Costo de servidor con 4 jugadores + hordas | Rendimiento | Sistemas data-oriented desde el día 1 (nunca script por entidad), profiler en cada fase, pooling en fase 8 |
| Pérdida de datos de jugadores | Confianza | ProfileStore con session locking + guardado en hitos + schema versionado (patrón ya validado por el equipo) |
| Scope creep del co-op | Calendario | D4: co-op es un switch sobre sistemas multiplayer-correct, no un rewrite; revivir/votaciones SOLO en fase 6 |
| Look PSX decepciona en Roblox | Identidad visual | Expectativa ajustada por escrito (sección 7 del contexto); la identidad se ancla en humor + siluetas + niebla, no en el downscale |
| Moderación/edad de Roblox | Contenido | Humor absurdo sí, violencia explícita no; revisar Community Standards antes de assets de sangre/gore (no los hay en el diseño actual) |

---

## 6. Backlog inicial sugerido (épicas, en orden)

1. **EP-01 Fundaciones**: repo Rojo, CI, esqueletos shared, place base.
2. **EP-02 Núcleo de combate**: input, cámara, Health, disparo, popups.
3. **EP-03 Contenido data-driven**: datos de armas/personajes, energía, habilidades, pickups.
4. **EP-04 Mazmorra**: DungeonLayout con TDD, prefabs de sala, generación.
5. **EP-05 Loop de run**: RoomService, enemigos, loot, portal, jefe provisional, victoria/derrota.
6. **EP-06 Lobby y UI**: estados del place, selección, HUD, paneles.
7. **EP-07 Co-op**: ready-up, revivir, votación de portal, escalado.
8. **EP-08 Persistencia**: ProfileStore, tienda, leaderboard, analytics.
9. **EP-09 Game feel y arte**: FX, audio, look final, jefe con fases, optimización.
10. **EP-10 Lanzamiento**: página, soft launch, monetización v1, cadencia de contenido.

Cada épica se desglosa en historias con el criterio "demostrable en un playtest de 10 minutos". Las fases 1-5 son el equivalente Roblox de la "plantilla beta" que ya se logró en Unity; las fases 6-9 son lo que Unity nunca habría dado gratis.

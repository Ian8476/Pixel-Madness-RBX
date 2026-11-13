# PixelMadness (Roblox)

Roguelite de accion 3D en tercera persona (con primera persona opcional), co-op 1-4 jugadores. Estetica "PSX de espiritu, Roblox de cuerpo".

Documentos de referencia: **`.agent/HANDOFF.md`** (empezar por aca: estado real, como correr los tests y el juego, trampas ya descubiertas), `.agent/PixelMadness_ROBLOX_CONTEXTO.md` (fuente de verdad de diseno y arquitectura), `.agent/PixelMadness_ROBLOX_PLAN.md` (fases, criterios de aceptacion, riesgos) y `CHANGELOG.md` (que cambio, cuando y por que).

**Estado: Fase 5 completa.** El circulo cierra entero sin recargar el servidor: lobby -> eleges personaje -> te marcas listo -> run de 3 pisos con enemigos, salas que encierran, monedas y jefe -> victoria o derrota -> de vuelta al lobby. Fase 6 (co-op real) es lo siguiente.

Controles (PC): **WASD** mueve, el **mouse** gira la camara y apunta (la mira es el centro de la pantalla), **click izquierdo** dispara, **ESPACIO** usa la habilidad, **Q** alterna arma, **E** recoge el arma mas cercana, **C** abre la seleccion de personaje (solo en el lobby). La **rueda del mouse** acerca y aleja la camara: pasado el tope de cerca entra en **primera persona**, y alejando se vuelve a tercera. El mismo cambio esta como boton en el panel del lobby.

---

## Setup en 5 minutos

```bash
# 1. Toolchain (una sola vez por maquina)
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
rokit install          # lee rokit.toml y baja rojo, wally, stylua, selene, lune

# 2. Dependencias
wally install          # opcional hoy: el proyecto no tiene dependencias externas

# 3. Sync con Studio
rojo serve
```

En Studio: pestana **Plugins -> Rojo -> Connect**. Deberias ver aparecer `ReplicatedStorage/Shared`, `ServerScriptService/Server` y `StarterPlayer/StarterPlayerScripts/Client`.

Verificacion rapida antes de tocar nada:

```bash
lune run tests/run      # 121 tests de logica pura y de contenido, sin abrir Studio
stylua --check src tests
selene generate-roblox-std && selene src
rojo build default.project.json --output PixelMadness.rbxl
```

### Jugar sin instalar nada

Si en tu maquina solo hay Studio y queres apretar Play:

```bash
pwsh scripts/sync-place.ps1
```

Genera `build/place-install.luau`: se copia entero y se pega en la **barra de comandos de Studio**. Aparecen `ReplicatedStorage/Shared`, `ServerScriptService/Server` y `StarterPlayerScripts/Client`, y el juego arranca.

**No es Rojo y no lo reemplaza.** Es una copia de una sola direccion, del repo al place: no hay sync continuo, y lo que edites dentro de Studio se pierde en la proxima corrida. La regla 1 sigue en pie y aca pesa mas que nunca: **el codigo nunca se edita en Studio**. Si dudas de si el place esta al dia, volve a correrlo (es idempotente).

### Correr los tests sin instalar nada

Si en tu maquina solo hay Studio, no hace falta Lune para ver los tests en verde:

```bash
pwsh scripts/bundle-tests.ps1
```

Genera `build/tests-bundle.luau`: se copia entero y se pega en la **barra de comandos de Studio**, y el reporte sale en el Output. Empaqueta exactamente el mismo alcance que Lune (`Constants`, `Shared/Logic/**`, `Shared/Data/**` y las specs), porque es el alcance que la regla de esas carpetas garantiza. **El CI sigue usando Lune**: esto es la salida de emergencia, no la fuente de verdad.

---

## Reglas del proyecto (las que rompen el build si las ignoras)

1. **El codigo NUNCA se edita en Studio.** Studio es para construir prefabs de sala y probar. Editar un Script dentro de Studio rompe el sync de Rojo y el cambio se pierde.
2. **Todo modulo nuevo lleva `--!strict`** y tipos explicitos en firmas publicas. Comentarios en espanol sin tildes.
3. **El servidor es la unica fuente de verdad.** Vida, energia, monedas, cooldowns, dano y generacion de mazmorra se calculan solo en el servidor. El cliente envia intenciones y pinta.
4. **Contenido = datos.** Un arma o personaje nuevo es un modulo en `src/shared/Data/`, jamas logica nueva.
5. **Ningun archivo crea RemoteEvents** fuera de `src/shared/Remotes.luau`.
6. **Ningun tag como string literal**: se usa `Tags.Enemy`, no `"Enemy"`.
7. **Nada de un Script por entidad** (bala, enemigo, moneda). Los sistemas iteran colecciones en un unico Heartbeat.

### La regla que hace testeable el proyecto

`src/shared/Constants.luau` y todo `src/shared/Logic/**` **no hacen `require` de nada y no tocan la API de Roblox**.

Esa restriccion es lo que permite que el mismo archivo corra en Lune (CI, sin Studio) y en Roblox sin traduccion ni darklua. Si un modulo de `Logic/` necesita configuracion, se le **inyecta como parametro** (ver `DifficultyMath.DEFAULT_TUNING`), no se importa.

Aqui va toda la logica testeable con TDD: `DifficultyMath`, `SpreadMath`, `ContentSchema`, `Rng` y `DungeonLayout`.

Corolario que se aplico en la Fase 3: **el azar tambien se inyecta.** `DungeonLayout` no importa `Rng`, recibe una funcion `nextInteger`. Y `Rng` es propio en vez de `Random.new(seed)` porque `Random` es un datatype de Roblox: no corre en Lune, y su algoritmo no es nuestro (si Roblox lo cambia, la misma semilla deja de dar la misma mazmorra).

**La misma regla se extiende a `src/shared/Data/**`** (Fase 2): los modulos de datos no hacen `require` y no usan datatypes de Roblox (por eso los colores son `{r, g, b}` y no `Color3`). Gracias a eso el CI valida el contenido REAL contra su esquema, no una copia de fixtures. Los `init.luau` de cada carpeta si usan la API de Roblox: son registros, no datos.

---

## Estructura

```
src/
  server/                 -> ServerScriptService/Server
    Bootstrap.server.luau   unico Script del servidor
    Core/                   RateLimiter, PlayerStatsReplicator, GameService,
                            LobbyService, LightingService
    Combat/                 Health, HealthRegistry, ProjectileSystem, WeaponService,
                            EnergyService, AbilityService
    Characters/             CharacterService
    Enemies/                EnemySystem, EnemyFactory, EnemyTypes,
                            EnemyBrains/{Chaser, Shooter}
    World/                  BreakableService, PickupService, RoomBuilder,
                            DungeonGenerator, RoomService, PortalService, LootService,
                            LobbyBuilder
  client/                 -> StarterPlayer/StarterPlayerScripts/Client
    Bootstrap.client.luau   unico LocalScript
    Input/                  AimProvider, InputController
    Character/              CharacterFacing, AbilityEffects
    Camera/                 ShooterCamera (tercera y primera persona)
    State/                  ClientState (cache de solo lectura del servidor)
    UI/                     Theme, UIController,
                            Views/{MenuView, HUDView, BannerView, CharacterSelectView, RunEndView}
    Audio/                  SoundLibrary (ids de audio como datos), SoundController
    FX/                     DamagePopups, PickupView, LootView, CombatFeedback
  shared/                 -> ReplicatedStorage/Shared
    Constants.luau          numeros del juego (sin API de Roblox)
    Types.luau              esquemas de contenido y payloads de remotes
    Tags.luau               vocabulario de CollectionService
    CollisionGroups.luau    nombres + matriz + registro idempotente
    Remotes.luau            unica frontera cliente-servidor
    Signal.luau             eventos genericos tipados
    ServiceLoader.luau      arranque en dos fases (lo usan ambos bootstraps)
    Logger.luau
    Data/                   contenido: Weapons/ (6), Characters/ (3), Enemies/ (3)
    Logic/                  logica pura, testeable en CI (DifficultyMath, SpreadMath,
                            ContentSchema, Rng, DungeonLayout, EnemyTactics, LobbyRules)
tests/
  Runner.luau             framework minimo describe/it/expect
  run.luau                entry point de Lune
  specs/
```

Lo que **no** vive en el repo todavia y es propiedad del place (Studio): `ServerStorage/RoomPrefabs`, `ReplicatedStorage/Assets`, iluminacion. Se versionan como `.rbxmx` en Fase 3, cuando existan prefabs de sala reales.

---

## Convenciones de colaboracion

- Codigo por PR. CI verde obligatorio (formato + lint + tests + build).
- **Todo PR actualiza `CHANGELOG.md`** bajo `[Sin publicar]`. Critico para los cambios de place: la configuracion del `.rbxl` no esta en Git, asi que el changelog es su unico registro.
- Nunca dos personas editando el mismo Model o prefab a la vez.
- El toolchain se actualiza corriendo `scripts/pin-toolchain.sh` de forma deliberada, nunca a mitad de sprint.

---

## Trampas de Roblox ya identificadas

- Tags con mayusculas inconsistentes fallan en silencio -> usar `Tags.luau`.
- Olvidar `SetNetworkOwner(nil)` en enemigos -> jitter y exploits.
- Usar `Touched` para balas -> pierde colisiones a alta velocidad. Se usa raycast segmentado.
- Crear Remotes fuera de `Remotes.luau` -> dos sistemas escuchando remotes distintos.
- `StreamingEnabled = true` con dungeon generado por servidor -> clientes sin salas cargadas.

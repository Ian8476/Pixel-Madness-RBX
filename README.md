# PixelMadness (Roblox)

Roguelite de accion 3D top-down, co-op 1-4 jugadores. Estetica "PSX de espiritu, Roblox de cuerpo".

Documentos de referencia: `PixelMadness_ROBLOX_CONTEXTO.md` (fuente de verdad de diseno y arquitectura), `PixelMadness_ROBLOX_PLAN.md` (fases, criterios de aceptacion, riesgos) y `CHANGELOG.md` (que cambio, cuando y por que — incluye los cambios de place, que no estan en Git).

**Estado: Fase 1 completa.** Fase 2 (contenido data-driven) es lo siguiente.

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
lune run tests/run      # 30 tests de logica pura, sin abrir Studio
stylua --check src tests
selene generate-roblox-std && selene src
rojo build default.project.json --output PixelMadness.rbxl
```

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

Aqui va toda la logica testeable con TDD: `DifficultyMath` (hecho), `SpreadMath` y `DungeonLayout` (Fase 2 y 3).

---

## Estructura

```
src/
  server/                 -> ServerScriptService/Server
    Bootstrap.server.luau   unico Script del servidor
    Core/RateLimiter        token bucket por jugador y por remote
    Combat/                 Health, HealthRegistry, ProjectileSystem, WeaponService
    Characters/             CharacterService
    World/                  BreakableService
    Dev/                    ANDAMIO: se borra en Fase 4
  client/                 -> StarterPlayer/StarterPlayerScripts/Client
    Bootstrap.client.luau   unico LocalScript
    Input/                  AimProvider, InputController
    Character/              CharacterFacing
    Camera/                 TopDownCamera
    FX/                     DamagePopups
  shared/                 -> ReplicatedStorage/Shared
    Constants.luau          numeros del juego (sin API de Roblox)
    Types.luau              esquemas de contenido y payloads de remotes
    Tags.luau               vocabulario de CollectionService
    CollisionGroups.luau    nombres + matriz + registro idempotente
    Remotes.luau            unica frontera cliente-servidor
    Signal.luau             eventos genericos tipados
    ServiceLoader.luau      arranque en dos fases (lo usan ambos bootstraps)
    Logger.luau
    Logic/                  logica pura, testeable en CI (DifficultyMath, SpreadMath)
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

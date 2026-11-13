# PixelMadness (Roblox): arranque de sesion

> **Leer este archivo primero.** Es el estado real del proyecto y como trabajar en el,
> a agosto de 2026. Los otros dos documentos de `.agent/` siguen siendo la fuente de
> verdad de DISENO (`PixelMadness_ROBLOX_CONTEXTO.md`) y de PLAN
> (`PixelMadness_ROBLOX_PLAN.md`); este dice donde estamos parados y con que herramientas.
>
> El historial detallado de cada fase, con sus decisiones y sus bugs, esta en
> `CHANGELOG.md`. Si algo de aca contradice al changelog, gana el changelog.

---

## 1. Donde estamos

**Fases 0 a 5 del plan: completas.** El juego se juega de punta a punta.

Lo que corre hoy, verificado en un playtest en vivo dentro de Studio:

- **Lobby**: eleges entre los 3 personajes, te marcas listo, cuenta atras de 5 s, arranca.
- **Run de 3 pisos**: mazmorra procedural distinta cada vez y reproducible por semilla.
- **Combate**: entrar a una sala cierra las puertas y spawnea enemigos escalados por piso
  y por cantidad de jugadores; limpiarla las abre. Chasers que persiguen, Shooters que
  mantienen distancia y disparan balas lentas y esquivables.
- **Loot**: monedas con iman validado en servidor y bote comun.
- **Armas**: 6 armas, 2 ranuras, Q para alternar, E para recoger.
- **Habilidades**: las 3 (Dash, DualWield, RapidFire) con costo y enfriamiento.
- **Jefe**: El Bonkaron con barra propia en el HUD. Al caer, Victoria.
- **Fin de run**: paneles de Victoria y Derrota, boton que devuelve al lobby.
- **UI completa**: HUD con vida/energia/armas/habilidad/piso/monedas, menu, seleccion de
  personaje y pantallas de fin. Estilo "Roblox popular" (redondeado, degradados, fuentes
  Luckiest Guy / Fredoka One, botones que rebotan) desde el rediseno de la Fase 6.
- **Sonido y musica**: efectos de UI y combate, musica por fase (lobby / run / jefe).
  Todo en `src/client/Audio/`; los ids son datos en `SoundLibrary.luau`.

**121 tests de logica pura en verde.** 83 archivos `.luau`.

### Que falta (Fase 6 en adelante)

Lo siguiente en el plan es **Fase 6: co-op real** (revivir, portal por consenso,
balanceo con varios jugadores). Pero antes hay una deuda concreta que arrastra la Fase 5:

> **Nada se probo nunca con mas de un jugador.** El criterio de aceptacion de la Fase 5
> pide "con 4 jugadores cada quien ve SU vida/energia/loadout y las monedas comunes", y
> se probo con uno. Por construccion deberia cumplirse (`PlayerStatsChanged` va con
> `FireClient`, `RunStateChanged` con `FireAllClients`), pero eso es un argumento, no una
> medicion. **Empezar cualquier trabajo de co-op probando con `Test -> Start Server + 2
> Players`.**

Tambien pendiente y sin excusa tecnica: **el formato nunca paso por StyLua ni el lint por
Selene**. Es lo unico que todavia necesita instalar la toolchain de verdad.

---

## 2. Como trabajar sin la toolchain instalada

En la maquina de desarrollo no hay `rokit`, `lune`, `rojo`, `stylua` ni `selene`. Se
armaron dos apanos que cubren lo importante **sin instalar nada**, aprovechando que
Roblox Studio ya es un interprete de Luau.

### Correr los tests

```bash
pwsh scripts/bundle-tests.ps1
```

Genera `build/tests-bundle.luau`. Se copia entero y se pega en la **barra de comandos de
Studio**; el reporte sale en el Output. Empaqueta el mismo alcance que Lune (`Constants`,
`Shared/Logic/**`, `Shared/Data/**` y las specs), porque es el alcance que la regla de
esas carpetas garantiza.

Si agregas un modulo a `Shared/Logic/` o una spec nueva, hay que sumarlos a la lista del
script (los de `Shared/Data/` se descubren solos).

### Jugarlo

```bash
pwsh scripts/sync-place.ps1
```

Genera `build/place-install.luau`. Se pega en la barra de comandos de Studio y aparecen
`ReplicatedStorage/Shared`, `ServerScriptService/Server` y `StarterPlayerScripts/Client`.
Despues, Play normal.

**No es Rojo y no lo reemplaza.** Es una copia de una sola direccion: no hay sync
continuo, y lo que edites dentro de Studio se pierde en la proxima corrida. La regla 1 del
proyecto sigue en pie y aca pesa mas que nunca: **el codigo nunca se edita en Studio**.

### El flujo con el plugin MCP de Studio

Lo que funciono bien en la sesion anterior, por si se repite:

- `execute_luau` **puede escribir `.Source`**, que es lo que hace posible `sync-place.ps1`.
- Para meter archivos grandes en Studio sin pegarlos a mano: servir el `.luau` por HTTP en
  `127.0.0.1`, habilitar `HttpService.HttpEnabled` un momento, `GetAsync` + `loadstring`, y
  **dejar `HttpEnabled` como estaba**.
- `start_stop_play` arranca y para el juego; despues quedan disponibles los datamodels de
  `Server` y `Client` para inspeccionar.
- `execute_luau` corre en una VM aparte: **no se puede `require` un servicio y ver su
  estado vivo** (sale una copia nueva y vacia). Lo que si se puede es mirar el mundo
  (Workspace, tags, Attributes, la UI en el PlayerGui) y disparar remotes desde el
  datamodel de Cliente, que es como se manejo al jugador en el playtest.
- Trampas conocidas del plugin, heredadas: `user_mouse_input` y `character_navigation`
  cuelgan el server. No usarlos.
- En modo Edit, Studio le pisa el `CFrame` a la camara del viewport, asi que no se puede
  encuadrar una captura por script.
- **El truco del servidor HTTP en `127.0.0.1` ya no funciona**: el plugin bloquea ese
  dominio en su allowlist. Lo que si funciona: comparar un hash de cada `Source` del place
  contra el repo (`execute_luau` + un script local) y subir solo los archivos que
  difieren con `multi_edit` (crea el script si no existe). Para reemplazar un archivo
  entero, borrarlo primero y crearlo de nuevo.
- `screen_capture` SI sirve durante un Play para ver la UI, y `user_keyboard_input`
  (por ejemplo la tecla C) funciona sin colgar nada.

---

## 3. Trampas que ya costaron caro

Estan todas explicadas con detalle en el `CHANGELOG.md`; aca va la lista para no
repetirlas.

| Trampa | Sintoma | Regla que quedo |
|---|---|---|
| Un raycast que **empieza dentro** de una parte no la detecta | La escopeta no hacia nada a quemarropa | Las balas nacen en el **centro del cuerpo** del que dispara, no adelante. Es seguro por la matriz de colisiones. |
| `HipHeight` es la distancia entre la **base** del RootPart y el piso | El jefe flotaba 3 studs | Un rig sin piernas lleva `HipHeight` casi cero. |
| La niebla se mide **desde la camara** | El juego entero se veia negro | `FOG_START` > distancia de la camara + media sala (36). Con la camara de shooter esa distancia es `CAMERA_MAX_DISTANCE_STUDS` (20), no los 53 de la vieja top-down. Esta escrito en `Constants`. |
| El ambiente **multiplica** el color de la parte | Grises oscuros bajo luz tenue = negro | Ver `LightingService`: la atmosfera vive en codigo, no en el place. |
| Dos servicios que se avisan cambios por signal | `C stack overflow` al arrancar | Escuchar **transiciones**, no estados. Ver el comentario en `LobbyService.init`. |
| `Players.CharacterAutoLoads = false` | `CharacterRemoving` no se dispara al morir | Para detectar muerte, `Humanoid.Died`. |
| Un Part cilindrico de Roblox | El portal salia eliptico | En un cilindro, X es el **eje**; Y y Z son el diametro y tienen que ser iguales. |

---

## 4. Reglas del proyecto que no se negocian

Estan en el README y en la seccion 3 del documento de contexto. Las que mas se olvidan:

1. **El servidor es la unica fuente de verdad.** El cliente manda intenciones y pinta.
2. **Contenido = datos.** Un arma o un enemigo nuevo es un modulo en `src/shared/Data/`,
   jamas logica nueva.
3. **`src/shared/Logic/**` y `Constants.luau` no hacen `require` de nada ni tocan la API
   de Roblox.** Es lo que los hace testeables sin Studio. La misma regla se extiende a
   `src/shared/Data/**` (por eso los colores son `{r, g, b}` y no `Color3`).
4. **Nada de un Script por entidad.** Balas, enemigos y monedas se iteran en un unico
   Heartbeat por sistema.
5. **Ningun remote fuera de `src/shared/Remotes.luau`.** Ningun tag como string literal.
6. **Comentarios en espanol sin tildes** (seguridad de encoding).
7. **Todo PR actualiza `CHANGELOG.md`**, y cada linea dice **que cambio y por que**.

Una mas, aprendida esta sesion: **no agregar signals ni API "por si acaso"**. Si no tiene
un suscriptor ni uno previsto, no va. Se borraron tres asi.

---

## 5. Por donde seguir

1. Correr `pwsh scripts/bundle-tests.ps1` y confirmar los 121 tests en verde.
2. Correr `pwsh scripts/sync-place.ps1`, apretar Play y jugar una run entera con las manos:
   es lo unico que todavia no se hizo (el playtest anterior movia al jugador por
   teletransporte, asi que las puertas cerradas nunca frenaron a nadie caminando).
3. **Probar con dos clientes.** Es la deuda que arrastra la Fase 5 y la puerta de entrada
   a la Fase 6.
4. Recien ahi, Fase 6 del plan: revivir, portal por consenso, balanceo co-op.

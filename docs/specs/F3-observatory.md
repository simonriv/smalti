# F3 · Observatorio (⌘⇧A) — Spec

Estado: aprobada · 2026-11-22 · Roadmap: `docs/ROADMAP.md#f3--observatorio-a`
Diseño: `docs/design/Observatorio.dc.html` (pantalla completa) y `docs/design/Main.dc.html` (lado derecho de la barra de estado; modelo y `ctx %` en la cabecera del panel).

## Objetivo

Ver de un vistazo cuánto consumen y en qué están todos los Claude de la máquina hoy, esta semana o este mes, junto con los modelos locales y los recursos del Mac. El objetivo es que el consumo de IA deje de ser invisible.

El criterio de cierre manda sobre todo lo demás: los tokens que muestra Smalti coinciden **exactamente** con los de los transcripts. Lo que no se pueda medir sin privilegios aparece como "no disponible", nunca como 0.

## Decisiones de Simón en el brainstorming

| Tema | Elegido | Descartado y por qué |
| --- | --- | --- |
| Qué sesiones entran | **Todas las de Claude Code en la máquina** dentro del periodo: transcripts de `~/.claude/projects` y Claude vivos de `~/.claude/sessions`, dentro o fuera de Smalti | Solo paneles de Smalti: un Claude abierto en otra terminal no aparecería y el total de "hoy" mentiría |
| OTLP | **Fuera de F3**. El USD sale de una tabla de precios por modelo aplicada a los tokens de los transcripts; el receptor OTLP pasa a F7 como extra | OTLP solo llega a los hijos de Smalti: dos calidades de dato en la misma columna, más código (servidor HTTP, inyección de variables) y un formato que cambia sin aviso |
| Periodos | **Hoy / 7 días / 30 días**, alternables, con un índice incremental persistente | Solo hoy: no responde "¿cuánto esta semana?", y el índice hace falta igual (hoy hay 149 MB de transcripts) |
| Resto de decisiones | Las recomendaciones de Claude ("tu recomendación en todo") | — |

Las decisiones de Claude van marcadas con **(Claude)** y se resumen en "Decisiones para aprobar con esta spec".

## Hechos verificados en la máquina de Simón (Claude Code 2.1.330)

- **Usage repetido:** cada mensaje del asistente se escribe en varios registros `type: "assistant"`, uno por bloque de contenido, con el mismo `message.id` y el mismo `usage` (324 de 457 ids repetidos en una sesión). **Cada `message.id` cuenta una sola vez.**
- `usage` trae `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` y `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`. El modelo está en `message.model`; la hora, en `timestamp` (ISO 8601 UTC).
- **Subagentes** en `<proyecto>/<sessionId>/subagents/agent-*.jsonl`, con su `agent-*.meta.json` (`model`, `description`). El archivo principal no los incluye.
- **Compactación:** registro `type: "system"`, `subtype: "compact_boundary"`, `compactMetadata.{trigger, preTokens, postTokens}`. Un `preTokens` de 967.809 confirma que Opus 5.5 usa la ventana de 1M.
- **Herramientas:** el `tool_use` va en el registro del asistente (`id`, `name`, `input`); el `tool_result` va en un registro `user` con el mismo `tool_use_id`, un `is_error` opcional y `toolUseResult`.
- **Sesiones vivas:** `~/.claude/sessions/<pid>.json` con `pid`, `sessionId`, `cwd`, `startedAt` (ms), `procStart`, `status` (visto: `busy`), `name` y `entrypoint`. Los `*.key` del mismo directorio son claves de mensajería: **nunca se leen**.
- También existe un registro `cost-state` con el costo que calcula el propio Claude, pero aparece pocas veces (al reanudar o terminar), así que no sirve como fuente por periodo.
- **Reanudar no copia mensajes:** en los 15.967 `message.id` con usage de todos los transcripts de la máquina (incluidas las sesiones que F2 reanudó con `--resume`), ninguno aparece en más de un archivo. Bifurcar (`--fork-session`) no está medido: se graba con `claude -p` en la primera tarea del adaptador (ver Riesgos).
- Ollama no está instalado.

## Alcance

- **Observatorio a pantalla completa** con ⌘⇧A: resumen, tabla de sesiones, detalle de la sesión seleccionada (actividad, tokens por minuto, compactación), modelos de Ollama y sistema.
- **Lado derecho de la barra de estado:** modelo local cargado, RAM, GPU y tokens de hoy.
- **Cabecera del panel:** modelo (`· opus`) y `ctx 41%` con su barra, que en F2 quedaron fuera.
- **Precios y ventanas de contexto** por modelo, con valores por defecto y editables en el TOML.

## Fuera de alcance

- Receptor OTLP (pasa a F7).
- Filtros por harness ("Todas", "Claude Code", "OpenCode", "Locales") y la fila de OpenCode del tablero: llegan en F6, cuando haya un segundo harness. **(Claude)**
- tok/s de Ollama: su API no lo expone sin generar. **(Claude)**
- Escribir el TOML desde la UI (F5).
- Historial más allá de 30 días.

## Enfoques considerados

| Tema | Elegido | Descartado |
| --- | --- | --- |
| Releer transcripts | **Índice incremental**: por archivo se guarda el offset leído, el tamaño, el inodo y lo ya agregado; cada refresco lee solo lo nuevo **(Claude)** | Releer todo en cada apertura: 149 MB hoy, 600 MB en 30 días |
| Granularidad del índice | **Cubos de 15 minutos en UTC**: todo huso horario es múltiplo de 15 min, así que "hoy" a medianoche local cae justo en un borde **(Claude)** | Cubos por hora local: rompen al cambiar de zona; por mensaje: índice enorme |
| Dónde viven las reglas | **Dominio**: deduplicar, agrupar en cubos, sumar, precios, `ctx %` y formato. El adaptador solo lee, traduce líneas a registros del dominio y persiste **(Claude)** | Agregar en el adaptador: las reglas del criterio de cierre quedarían fuera de las pruebas de dominio y de la mutación |
| Costo de modelos con precio por tramos (Haiku 5.5 > 100K) | **Precio base siempre**; el tablero ya dice "estimado" **(Claude)** | Modelar tramos: complejidad para un número estimado |

## Diseño técnico

### Módulos

```text
SmaltiApp ──▶ SmaltiCore ◀── GhosttyAdapter, TOMLConfigAdapter, FileSessionAdapter, IPCAdapter,
                  ▲          ClaudeHarnessAdapter, UserNotificationsAdapter   (F0–F2)
                  ├────────── ClaudeTelemetryAdapter   (transcripts + índice + ~/.claude/sessions)  nuevo
                  ├────────── OllamaAdapter            (API HTTP local, URLSession)                 nuevo
                  └────────── DarwinMetricsAdapter     (Mach, IOKit, libproc, sysctl)               nuevo
```

Cada paquete nuevo es el único que importa su framework y tiene su prueba de guarda de imports. `SmaltiCore` sigue en Swift puro.

### Dominio (`SmaltiCore/Domain/Observatory`)

- **`TokenUsage`**: `input`, `output`, `cacheRead`, `cacheWrite5m`, `cacheWrite1h`; suma con `+`.
  - `inputTotal = input + cacheRead + cacheWrite5m + cacheWrite1h`. Es "Tokens entrada" del tablero y del criterio de cierre.
  - `cacheShare = cacheRead / inputTotal`, que da "71% desde caché".
  - Si `cache_creation` no trae el desglose, todo `cache_creation_input_tokens` cuenta como escritura de 5 minutos.
- **`TranscriptRecord`** (lo que el adaptador entrega por línea):
  - `.assistantTurn(messageID, model, usage, at, isSubagent)`;
  - `.toolStarted(id, name, input: [String: String], at)`;
  - `.toolFinished(id, isError, exitCode?, at, diffStat?)`;
  - `.compacted(at, preTokens, postTokens)`;
  - `.sessionInfo(sessionID, cwd, at)`.
- **`SessionActivity`** (`Codable`, el estado plegado de una sesión):
  - id, `cwd`, modelo del último turno principal, primera y última actividad;
  - ids de mensajes ya contados (deduplicación entre lecturas incrementales);
  - por cubo de 15 min UTC: `TokenUsage` **por modelo** (con los subagentes incluidos; así el costo es correcto aunque un subagente use otro modelo), herramientas del hilo principal (total y con error) y el minuto de más salida del cubo con su valor. Así todo lo que muestra la tabla se recorta por periodo, y el "pico N/min" de cualquier periodo es el máximo de los picos de sus cubos **(Claude)**;
  - salida por minuto de los últimos 60 min (el gráfico);
  - tokens de contexto del último turno **principal** (`inputTotal` de ese turno);
  - las 5 últimas herramientas del hilo principal, con resumen, inicio, fin y resultado;
  - herramientas en curso por id (un `tool_result` puede llegar en otra lectura);
  - última compactación.
  - `folding(_ records:)` es pura. Un `assistantTurn` con un `messageID` ya visto no suma. Los turnos de modelo `<synthetic>` o con usage 0 no cambian el modelo de la sesión.
- **`ObservatoryPeriod`**: `.today`, `.lastSevenDays`, `.lastThirtyDays`, con `TimeZone` inyectada.
  - "Hoy" = desde las 00:00 locales hasta ahora; 7 y 30 días = desde las 00:00 de hace 6 y 29 días.
  - Una sesión que cruza medianoche solo aporta los cubos que caen dentro del periodo.
- **`ModelCatalog`**: por id, la familia que se muestra (`opus`, `sonnet`, `haiku`, `fable`; si no se reconoce, el id), la ventana de contexto y los precios por MTok (entrada, salida, lectura de caché, escritura 5m, escritura 1h). La búsqueda prueba el id exacto, luego sin sufijo entre corchetes (`[1m]`) y luego sin sufijo de fecha (`-20251001`).

  Valores por defecto (precios de Anthropic al 2026-11-03; escritura de caché = 1,25× la entrada en 5m y 2× en 1h):

  | Modelo | Ventana | Entrada | Salida | Lectura caché | Escritura 5m | Escritura 1h |
  | --- | --- | --- | --- | --- | --- | --- |
  | `claude-fable-5-2` | 1M | 8 | 40 | 0,20 | 10 | 16 |
  | `claude-fable-5-1` | 1M | 10 | 50 | 0,25 | 12,50 | 20 |
  | `claude-fable-5` | 1M | 10 | 50 | 1,00 | 12,50 | 20 |
  | `claude-opus-5-5` | 1M | 4 | 20 | 0,20 | 5 | 8 |
  | `claude-opus-5`, `-4-8`, `-4-7`, `-4-6` | 1M | 5 | 25 | 0,50 | 6,25 | 10 |
  | `claude-sonnet-5-5` | 1M | 2 | 10 | 0,10 | 2,50 | 4 |
  | `claude-sonnet-5` | 1M | 2 | 10 | 0,20 | 2,50 | 4 |
  | `claude-sonnet-4-6` | 1M | 3 | 15 | 0,30 | 3,75 | 6 |
  | `claude-haiku-5-5` | 1M | 0,10 | 0,50 | 0,01 | 0,125 | 0,20 |
  | `claude-haiku-4-5` | 200K | 1 | 5 | 0,10 | 1,25 | 2 |

- **`CostEstimate`**: USD de un `TokenUsage` por modelo. Los tokens de un modelo sin precio no suman y se cuentan aparte: si hay alguno, el subtítulo de la tarjeta lo dice (ver Textos).
- **`ContextLoad`**: `contextTokens / ventana`, redondeado a entero. Sin ventana conocida, es "no disponible" (se muestra "—").
- **`ObservedSession`**: une `SessionActivity`, el `RunningAgent` vivo (si lo hay) y la `AgentSession` del panel de Smalti (si lo hay).
  - **Estado:** la `AgentSession` del panel manda (hooks de F2). Si no hay panel y el proceso vive, se usa el `status` de `sessions/<pid>.json`: `busy` → trabajando; `idle` o `waiting` → te espera; cualquier otro valor → trabajando, registrado en el log una vez por valor. Si el proceso no vive → detenida. **(Claude)**
  - **Etiqueta:** con panel de Smalti, la de las notificaciones de F2 (`<workspace>/<último directorio>`); sin panel, los dos últimos componentes del `cwd` (`solen/api`), o uno si el `cwd` es `~` o está justo debajo. **(Claude)**
- **`ObservatoryReport`** (lo que pinta la vista), construido por una función pura a partir de sesiones, periodo, catálogo, `now` y zona horaria:
  - **Resumen:** sesiones activas (vivas) con "N trabajando · N esperando" (y "· N error" si hay); entrada total y % de caché; salida total con el pico por minuto del periodo y su hora; USD estimado.
  - **Columnas por periodo (Claude):** Entrada, Salida y Err suman solo los cubos del periodo, así que la suma de las filas cuadra con las tarjetas. Vida, Contexto y PID describen la sesión ahora (tiempo desde su inicio si vive, `TimeAgo` de la última actividad si no).
  - **Filas:** las vivas primero, ordenadas por inicio descendente (orden estable); luego las detenidas con actividad en el periodo, por última actividad descendente. Los subagentes nunca son filas. Los `claude -p` sí, porque gastan tokens.
  - **Detalle** de la seleccionada: actividad, salida por minuto de la última hora con su pico, y la compactación.
- **Umbrales (Claude):**
  - barra de contexto en acento por debajo del 75 % y ámbar desde el 75 % (el tablero muestra 41 % y 63 % en acento, 78 % en ámbar);
  - % de errores en rojo desde el 5 % (el tablero muestra 2 % normal y 9 % rojo).
- **`ToolSummary`** (pura, para la columna de actividad):
  - Bash: el `command`;
  - Read, Write, Edit, Update y MultiEdit: el nombre del archivo, más `+N −M` si el resultado trae el parche;
  - Grep y Glob: `"patrón" en <ruta>`;
  - cualquier otra: su primer campo de texto.
  - **Resultado:** en verde, la duración (`1.8s`) para un Bash correcto y `ok` para el resto; en rojo, `exit N` para un Bash con código y `error` para el resto. La duración es el `timestamp` del `tool_result` menos el del `tool_use`.
- **Formato (los textos del tablero tal cual, con punto decimal como en el tablero):**
  - `CompactCount`: `412`, `61.4k`, `982k`, `1.24M`.
  - `Lifetime`: `34m`, `1h 12m`, `2h 05m`.
  - `TimeAgo`: `hace 22 min` (< 1 h), `hace 3h` (< 24 h), `hace 2 días`.
  - Memoria `11.2 / 16 GB` y `6.1 GB`; costo `$18.40`.
  - "hoy 1.24M tokens" = entrada total + salida de hoy, todas las sesiones.

### Puertos (`SmaltiCore/Application`)

| Puerto | Operaciones | Adaptador |
| --- | --- | --- |
| `AgentTranscripts` | `activity(since: Date) async throws(TranscriptError) -> [SessionActivity]` (sesiones con actividad desde esa fecha, ya plegadas y al día) | `ClaudeTranscripts` |
| `LiveAgents` | `running() async -> [RunningAgent]` (`pid`, `sessionID`, `cwd`, `status`, `startedAt`) | `ClaudeSessionRegistry` |
| `LocalModels` | `current() async -> LocalModelsReport` (`.unavailable` o `.available(loaded, onDisk)`) | `OllamaLocalModels` |
| `SystemMetrics` | `sample(agentPIDs:) -> SystemSample` (CPU, GPU, memoria usada/total, memoria de agentes y presión; cada campo puede ser `.unavailable`) | `DarwinSystemMetrics` |

- Los nombres siguen la lista de `CLAUDE.md`: `SystemMetrics` ya estaba; `AgentTranscripts`, `LiveAgents` y `LocalModels` son nuevos y concretan el `TelemetrySource` genérico de PROJECT.md. El `TelemetrySource` de F2 (eventos de hooks) no cambia.
- Cada puerto tiene un fake en memoria en `SmaltiCoreTestSupport` y una prueba de contrato compartida (fake y adaptador real sobre fixtures).

### Casos de uso

- **`ObserveAgents`**: el `ObservatoryReport` para un periodo y una selección.
- **`ReadStatusFigures`**: el lado derecho de la barra de estado.
- **`DescribePaneAgent`**: modelo y `ctx %` de la sesión de un panel.

Los tres se ejecutan con fakes, sin AppKit ni archivos.

### `ClaudeTelemetryAdapter`

- **Raíz:** `~/.claude`, o el valor de `CLAUDE_CONFIG_DIR` si la app lo hereda. Se puede cambiar con el argumento `-SmaltiClaudeHome <dir>`; las pruebas **siempre** lo pasan y nunca leen el `~/.claude` real.
- **`ClaudeTranscripts`** (un `actor`, todo fuera del hilo principal):
  - Recorre `projects/*/*.jsonl` y `projects/*/<id>/subagents/*.jsonl` con `mtime` dentro de los últimos 30 días.
  - Por archivo guarda `{inodo, tamaño, offset, sessionID, esSubagente}` y la `SessionActivity` plegada en `<estado>/observatory/index.json`, con versión de formato y escritura atómica como `session.json`.
  - **Lectura incremental:** desde `offset` hasta el último `\n` completo; una línea a medio escribir se deja para la próxima lectura. Si el inodo cambia o el tamaño baja del offset, el archivo se relee desde 0 y su sesión se rehace.
  - **Línea ilegible:** se salta, se cuenta y se registra en el log; nunca tumba la lectura. Los tipos desconocidos se ignoran.
  - Los turnos de un subagente suman a la sesión de su carpeta (`<id>`). Sus herramientas no cuentan en actividad ni en errores **(Claude)**: el detalle muestra lo que hizo la sesión que Simón ve.
  - Un índice ilegible o de otra versión se descarta y se reconstruye; nunca bloquea el arranque.
  - Se poda lo que tiene más de 30 días.
- **`ClaudeSessionRegistry`:**
  - Lee solo `sessions/*.json`, nunca los `*.key`.
  - Un PID cuenta como vivo si `kill(pid, 0)` responde **y** su hora de arranque (`proc_pidinfo`) coincide con `procStart`; así un PID reutilizado no pasa por un Claude vivo.
  - Un JSON ilegible se salta.
- **Errores:** `TranscriptError` tipado (operación, ruta y causa) solo para fallos de raíz (directorio ilegible). Un archivo concreto que falla se salta y se registra.

### `OllamaAdapter`

- `GET http://127.0.0.1:11434/api/ps` (cargados: `name`, `size`, `size_vram`, `details.quantization_level`, `context_length` si viene) y `GET /api/tags` (en disco: `name`, `size`, `modified_at`), con un tiempo de espera de 500 ms. La URL se cambia con `-SmaltiOllamaURL` en las pruebas.
- Si no hay conexión, la respuesta es `.unavailable`: la tarjeta dice "Ollama no está corriendo" y la barra de estado omite el segmento del modelo.

### `DarwinMetricsAdapter` (sin sudo ni procesos hijos)

- **CPU:** diferencia de ticks de `host_processor_info` entre dos muestras.
- **GPU:** `PerformanceStatistics["Device Utilization %"]` de `IOAccelerator`, leído con la API de IOKit (es lo que imprime `ioreg`). Si falta, `.unavailable`.
- **Memoria:**
  - total = `hw.memsize`; usada = (activa + wired + comprimida) × tamaño de página, de `host_statistics64`;
  - presión: `kern.memorystatus_vm_pressure_level` (1 normal, 2 media, 4 alta);
  - agentes = suma del `phys_footprint` (`proc_pid_rusage`) de los PID vivos de Claude;
  - modelo = suma del `size_vram` de Ollama (lo pone el caso de uso);
  - resto = usada − modelo − agentes.
- **Nombre del Mac:** `product-name` de `IOPlatformExpertDevice`; si no existe, `machdep.cpu.brand_string` ("Apple M4"). Se verifica en la primera tarea del bloque.

### Refresco (lado app)

- Un `ObservatoryRefresher` (`@MainActor`) pide al dominio un informe nuevo **cada 2 s con el Observatorio abierto y cada 10 s cerrado** (barra de estado y cabeceras). También refresca al instante la sesión de un panel cuando llega un hook `Stop`, `PostToolUse` o `SessionStart`. **(Claude)**
- La lectura y el plegado corren en el `actor` del adaptador. El hilo principal solo recibe el informe y pinta: ningún refresco bloquea más de 16 ms (criterio C11).
- Las métricas del sistema se muestrean cada 2 s siempre y se guardan 60 muestras (2 min) para las curvas de CPU y GPU.
- Al abrir la app por primera vez (índice vacío), "hoy" se indexa primero y luego los 30 días en segundo plano. Mientras falta un periodo, sus tarjetas dicen "leyendo transcripts…". **(Claude)**

### UI (`Observatorio.dc.html`)

- **Presentación:** ⌘⇧A cubre toda la ventana (franja, paneles y barra de estado, como en el tablero) sobre el mismo vidrio, con fundido de 150 ms o sin animación si está activo "Reducir movimiento". Los paneles siguen vivos debajo. esc o ⌘⇧A otra vez cierra y devuelve el foco al panel de antes. Comando de ⌘K: "Abrir observatorio".
- **Franja de 40 px:** "Observatorio" (13 px, 600, `#e6e9ef`), "agentes y modelos en esta máquina" (12 px, `#8b919c`), la pastilla del periodo ("Hoy", "7 días", "30 días"; borde `rgba(255,255,255,0.08)`, `#c3c7cf`) y `esc`.
- **Tarjetas, tabla, actividad, gráfico, Ollama y sistema:** medidas, colores y textos del tablero. Rejilla de dos columnas (flexible y 330 px), separación de 12 px y relleno de 14 px. Filas de 44 px y columnas `112 / 1.3fr / 1.3fr / 76 / 76 / 70 / 118 / 56 / 66`. La fila seleccionada lleva el brillo del acento y una barra interior de 2 px.
- **Fila detenida:** texto `#8b919c`, círculo hueco, "detenida", `Vida` = `TimeAgo` de su última actividad, y "—" en contexto y PID.
- **Gráfico de salida por minuto:** polilínea del acento de 1,6 px, relleno con el brillo del acento y el pico marcado con un círculo de 3 px y "4.8k · 10:42". Una sesión sin actividad en la última hora muestra la línea base y "Sin actividad en la última hora".
- **Compactación:** "Compactación hace 22 min · liberó 38% del contexto", con % = (preTokens − postTokens) / ventana; "Sin compactaciones" si no hubo.
- **Sistema:** curvas de CPU (`#7dcfff`) y GPU (`#bb9af7`) de las últimas 60 muestras; barra de memoria con modelo (`#bb9af7`), agentes (acento) y resto (`#6b717c`); el texto "modelo 6.1 · agentes 3.5 · resto 1.6 GB · presión media". Sin Ollama se omite "modelo"; un valor no disponible se escribe "no disponible", nunca 0.
- **Tabla de sesiones:** virtualizada (`NSTableView`): 30 días pueden ser cientos de filas.
- **Ámbito de los atajos (Claude):** el `Keymap` de F1 no gana ámbitos. ⌘⇧A (`observatory.toggle`) y ⌘P (`observatory.period`) son comandos del keymap, editables en TOML. `observatory.period` solo actúa con el Observatorio abierto; cerrado, el `KeyRouter` deja pasar ⌘P a la terminal como cualquier tecla sin comando. ↑↓, ↵ y esc son fijos de la vista, como en la paleta ⌘K de F1.
- **Teclado:** ↑↓ seleccionan fila; ↵ sobre una sesión que vive en un panel de Smalti cierra el Observatorio y enfoca ese panel (si no vive en un panel, no hace nada) **(Claude)**; ⌘P alterna el periodo **(Claude, ⌘P está libre)**; esc cierra. Sin botones fijos: la pastilla del periodo responde al clic y a ⌘P.

### Barra de estado y cabecera (`Main.dc.html`)

- **Lado derecho de la barra de estado** (11 px, `#8b919c`, separación de 16 px): `qwen3.5:9b · 6.1 GB` (solo con un modelo de Ollama cargado), `RAM 11.2 / 16 GB`, `GPU 38%` (o `GPU no disponible`) y `hoy 1.24M tokens` en `#c3c7cf`. Un mensaje de estado sigue ocupando el lado izquierdo, como en F1.
- **Cabecera:**
  - el directorio gana ` · <familia>` cuando el panel tiene una sesión de Claude con modelo conocido (`solen/api · opus`);
  - en estado trabajando, antes del tiempo de vida van `ctx 41%` y una barra de 44 × 4 px (acento; ámbar desde el 75 %);
  - en te espera y error, el detalle de F2 ocupa su lugar, como en el tablero.

### Textos nuevos (no están en los tableros)

- "Hoy", "7 días", "30 días" (la pastilla del periodo; el tablero solo muestra "Hoy").
- "· N error" en el resumen.
- "estimado · incluido en tu plan · sin precio para N modelos" cuando falta el precio de algún modelo.
- "Ollama no está corriendo"; "descargado hace 2 días" en lugar de "última vez hace 2 días" (`modified_at` es la fecha de descarga, no de uso).
- "Sin actividad en la última hora", "Sin compactaciones", "leyendo transcripts…", "no disponible", "Abrir observatorio".
- Nota al pie: "Datos: hooks y transcripts de Claude Code y API local de Ollama. El costo es estimado." (sin "base de OpenCode", que es de F6).

### Configuración (TOML, solo lectura en F3)

```toml
[observatory.models."claude-opus-5-5"]
context = 1000000
input = 4.0
output = 20.0
cache_read = 0.20
cache_write_5m = 5.0
cache_write_1h = 8.0
```

- Cada clave sobrescribe la del valor por defecto. Un modelo que no está en la tabla necesita las seis claves; si falta alguna, es un error de configuración con archivo y línea, como en F1.

### Atajos nuevos (editables en TOML)

| Acción | Atajo | Origen |
| --- | --- | --- |
| Abrir o cerrar el observatorio | ⌘⇧A | PROJECT.md |
| Alternar periodo (dentro del Observatorio) | ⌘P | Propuesta |
| Cerrar el Observatorio / ir al panel de la sesión | esc / ↵ | Tablero (esc) y propuesta |

## Criterios de aceptación

| # | Criterio | Verificación |
| --- | --- | --- |
| C1 | **Cierre del roadmap:** para 3 sesiones reales de Claude Code grabadas sin supervisión con `claude -p` (una con subagente y otra con más de un turno), entrada, salida, lectura y escritura de caché de cada sesión y del total coinciden **exactamente** con una suma independiente de sus transcripts que deduplica por `message.id` | Fixtures reales en `Packages/ClaudeTelemetryAdapter/Tests/Fixtures`; la referencia la calcula `scripts/observatory/sum_transcripts.py` (Python, independiente del código Swift) y se guarda junto a cada fixture; la prueba del adaptador la compara |
| C2 | Deduplicación: un mensaje repetido en N registros cuenta una vez, también si sus repeticiones llegan en lecturas incrementales distintas | Pruebas de dominio (`folding`) y del adaptador (archivo que crece entre dos lecturas) |
| C3 | Periodos: hoy, 7 y 30 días con sesiones que cruzan medianoche, fin de mes y una zona con horario de verano (`America/New_York`) además de `America/Bogota` | Pruebas de dominio |
| C4 | Índice incremental: una línea a medio escribir se lee entera en la siguiente pasada; un archivo truncado o reemplazado se relee; un índice corrupto se reconstruye; una línea ilegible no tumba la lectura | Pruebas del adaptador |
| C5 | Costo y contexto: el USD de cada modelo sale de la tabla (con el TOML encima); un modelo sin precio no suma y se anuncia; `ctx %` usa el último turno principal y la ventana del modelo | Pruebas de dominio + `TOMLConfigAdapter` |
| C6 | Estado de cada fila: hooks para los paneles de Smalti; `status` de `sessions/<pid>.json` fuera de Smalti; detenida si el PID no vive o fue reutilizado (`procStart` distinto) | Pruebas de dominio + contrato de `LiveAgents` |
| C7 | Nada medible se pinta como 0: GPU, Ollama, nombre del Mac y precio ausentes aparecen como "no disponible" o se omiten según la regla de cada uno | Pruebas de casos de uso con fakes que devuelven `.unavailable` + XCUITest |
| C8 | El Observatorio abre con ⌘⇧A y ⌘K, se maneja con teclado (↑↓, ↵ al panel, ⌘P periodo, esc) y muestra tarjetas, filas, detalle, Ollama y sistema a partir de fixtures | XCUITest con `-SmaltiClaudeHome` de fixture y `-SmaltiOllamaURL` a un servidor de pruebas |
| C9 | La barra de estado muestra el lado derecho y la cabecera muestra `· opus` y `ctx N%` de un panel cuyo Claude está en el fixture | XCUITest que reproduce hooks de F2 con el `session_id` del fixture |
| C10 | Primera indexación de los transcripts reales de hoy de Simón (solo lectura) en **≤ 5 s**; un refresco incremental sin cambios en **≤ 50 ms** | Medición en el informe de la fase, build Release, 5 corridas |
| C11 | Ningún refresco bloquea el hilo principal más de 16 ms con el Observatorio abierto durante 60 s | Sonda de latencia de F1 (`LatencyProbe`) |
| C12 | Capturas del Observatorio, de la barra de estado y de una cabecera con `ctx` coinciden con los tableros | Captura superpuesta al 50 % sobre el tablero renderizado con Chrome, adjunta al PR |
| C13 | Guardas: `SmaltiCore` sigue en Swift puro; cada adaptador nuevo es el único que importa su framework; nadie lee `~/.claude/sessions/*.key` | `swift test` (guardas + prueba de que el registro ignora `*.key`) |
| C14 | Las UI tests usan `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiConfigPath`, `-SmaltiStatePath` y `-SmaltiClaudeHome` temporales, restauran el portapapeles y dejan intacto el Smalti diario | `isolatedSmalti()` + `scripts/check-daily-untouched.sh` |
| C15 | Mutación ≥ 80 % en `SmaltiCore` | `scripts/mutation/mutate.py` |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| El formato de los transcripts cambia (Claude Code no lo documenta) | Tokens mal contados en silencio | El adaptador ignora lo desconocido y cuenta las líneas ilegibles; los fixtures reales se regeneran con cada versión mayor de Claude, como el log de hooks de F2; C1 lo detecta |
| Bifurcar una sesión (`--fork-session`) copia el historial con los mismos `message.id` a otro archivo | Tokens contados dos veces | La primera tarea del adaptador graba una bifurcación con `claude -p`. Si se copian ids, la deduplicación pasa de por sesión a global (el primer archivo que los contiene se queda con ellos), con su prueba |
| `/clear` en el mismo proceso crea un `sessionId` nuevo y `sessions/<pid>.json` tarda en reflejarlo | Fila viva unida a la sesión anterior un momento | La fila viva se une por el `sessionId` del archivo en cada refresco; la sesión anterior pasa a detenida. Se acepta el desfase de un refresco |
| `status` de `sessions/<pid>.json` con valores que no conocemos | Estado incorrecto fuera de Smalti | Valor desconocido → trabajando, con aviso en el log; se registran los valores vistos al grabar los fixtures |
| Precios desactualizados | USD inexacto | Es un estimado y lo dice; se pueden editar en el TOML; la tabla lleva su fecha |
| `Device Utilization %` falta en otro Mac o versión | GPU vacía | "no disponible" (C7) |
| 30 días de transcripts (~600 MB) en el primer arranque | CPU alta un rato | Hoy primero, el resto en segundo plano, fuera del hilo principal; C10 lo mide |
| `ctx %` con una ventana que depende del plan o de un beta | % falso | Ventana por modelo en el TOML; sin ventana conocida, "—" |

## Cambios en otros documentos (con esta spec)

- `docs/PROJECT.md`: en el pilar 4, la línea de fuentes deja OTLP para F7. En el diagrama, la caja de telemetría queda como "hooks·JSONL·Ollama", más "OTLP (F7)". La tabla de Decisiones no cambia.
- `docs/ROADMAP.md`: F3 sin el receptor OTLP, con los periodos y sin los filtros por harness; F6 gana los filtros del Observatorio; F7 gana el receptor OTLP.
- `CLAUDE.md`: la lista de puertos gana `AgentTranscripts`, `LiveAgents` y `LocalModels`.

## Decisiones para aprobar con esta spec

1. Sin OTLP en F3 (Simón); el receptor pasa a F7.
2. Todas las sesiones de la máquina, con periodos hoy / 7 días / 30 días e índice incremental (Simón).
3. Tabla de precios y ventanas por defecto (2026-11-03), editable en `[observatory.models]`; los modelos con tramos usan el precio base.
4. "Tokens entrada" = entrada + lectura de caché + escritura de caché. Los subagentes suman tokens a su sesión, pero no actividad ni errores.
5. Estado fuera de Smalti desde `sessions/<pid>.json` (`busy` → trabajando, `idle`/`waiting` → te espera, otro → trabajando); PID vivo verificado con `procStart`.
6. Filtros por harness y la fila de OpenCode, aplazados a F6; tok/s de Ollama, omitido.
7. Umbrales: contexto ámbar desde el 75 %; errores en rojo desde el 5 %.
8. Atajos ⌘P (periodo, solo con el Observatorio abierto; cerrado, ⌘P llega a la terminal) y ↵ (ir al panel de la sesión); comando "Abrir observatorio"; el keymap no gana ámbitos.
13. Entrada, Salida y Err de la tabla son del periodo (cuadran con las tarjetas); Vida, Contexto y PID son del momento. El pico por minuto se guarda por cubo de 15 min.
9. Refresco cada 2 s abierto y cada 10 s cerrado, más refresco inmediato con los hooks; métricas cada 2 s con 2 min de historia.
10. Textos nuevos de la sección "Textos nuevos", incluido "descargado hace …" en lugar de "última vez hace …".
11. Argumentos de lanzamiento nuevos para aislar las pruebas: `-SmaltiClaudeHome` y `-SmaltiOllamaURL`.
12. Puertos nuevos: `AgentTranscripts`, `LiveAgents` y `LocalModels`; paquetes nuevos: `ClaudeTelemetryAdapter`, `OllamaAdapter` y `DarwinMetricsAdapter`.

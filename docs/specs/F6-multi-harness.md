# F6 · Multi-harness y Neovim — Spec

Estado: aprobada · 2026-11-24 · Roadmap: `docs/ROADMAP.md#f6--multi-harness-y-neovim`
Diseño: columna derecha de `Reanudar.dc.html` («Todas las sesiones de agentes»), filas de agentes y de nvim de su columna izquierda, y los filtros y la fila de OpenCode de `Observatorio.dc.html`. Los enlaces «Abrir en Neovim» no salen en ningún tablero: se resolvieron en el brainstorming (ver «Abrir en Neovim»).

## Objetivo

Retomar las sesiones de cualquier harness que Simón use, no solo de Claude, y aprobar los diffs de Claude en Neovim sin salir de Smalti. Hoy Smalti solo retoma Claude, y las demás sesiones (Codex, Antigravity, OpenCode) se pierden al cerrar o hay que buscarlas a mano.

Anti-objetivo: **F6 fracasa si retomar abre una sesión equivocada sin avisar (otra sesión, otro directorio u otro harness), si Smalti escribe en la configuración de un harness o en la de Neovim sin que Simón lo pida, si abrir el buscador o el Observatorio se traba leyendo bases de datos ajenas, si un formato que cambió rompe la app en vez de degradar al respaldo, o si las pruebas leen o escriben `~/.claude`, `~/.codex`, `~/.gemini`, `~/.local/share/opencode` o `~/.config/nvim` reales.**

## Hechos verificados (antes de diseñar)

Verificados en el código fuente de cada harness y con un spike sobre los binarios reales, con homes temporales (2026-11-24). No son supuestos.

| Harness | Versión | Dónde guarda | Reanudar | Continuar la última | Bifurcar |
| --- | --- | --- | --- | --- | --- |
| Claude Code | instalada | `~/.claude/projects/<dir>/<id>.jsonl` (lo lee ya F3) | `claude --resume <id>` | `claude --continue` | `claude --resume <id> --fork-session` |
| Codex | 0.171 (cask) | `$CODEX_HOME` (por defecto `~/.codex`): rollouts en `sessions/AAAA/MM/DD/rollout-<ts>-<uuid>.jsonl`, comprimidos a `.jsonl.zst` pasados 7 días; índice SQLite `state_5.sqlite`, tabla `threads` (`id`, `cwd`, `title`, `created_at`, `updated_at`, `source`, `model_provider`, `tokens_used`, `archived`) | `codex resume <id>` | `codex resume --last` | `codex fork <id>` |
| Antigravity | 1.5.10 (cask, `agy` → binario `antigravity`) | `~/.gemini/antigravity-cli/` (sigue a `HOME`): `conversation_summaries.db`, tabla `conversation_summaries` (`conversation_id`, `title`, `workspace_uris` JSON con `file://…`, `last_modified_time`); última por workspace en `cache/last_conversations.json`; login en `antigravity-oauth-token` | `agy --conversation <id>` | `agy -c` | no tiene |
| OpenCode | 2.3.2 (fórmula) | `$XDG_DATA_HOME/opencode/opencode.db` (por defecto `~/.local/share/opencode`; otro canal usa `opencode-<canal>.db`; `OPENCODE_DB` lo cambia): tabla `session_v2` (`id`, `directory`, `title`, `tokens_*`, `cost`, `time_created`, `time_updated`, `time_archived`, `parent_id`); el modelo y su proveedor van por mensaje en `session_message.data` (`model.providerID`) | `opencode -s <id>` | `opencode -c` | no tiene en 2.x |

Comprobado también en el spike:
- Los cuatro retoman con su comando real dentro de un PTY y muestran el primer mensaje de la sesión.
- **Codex** con un modelo local necesita un `config.toml` en su home, con `model_provider = "ollama"` y `check_for_update_on_startup = false`. La primera vez pregunta si confía en la carpeta.
- **Codex y OpenCode dejan daemons vivos al salir:** `codex app-server … --managed-daemon` y `opencode serve --service`. Hay que matarlos por la ruta de su home temporal.
- **Antigravity** necesita login, y su pantalla muestra el correo de la cuenta.
- Las bases de datos están en WAL. Abiertas en solo lectura sin permiso de escritura en la carpeta, SQLite falla con el error 14; se abren con `immutable=1` o desde una copia.
- **Gemini CLI queda fuera:** Google retiró el login individual gratuito («This client is no longer supported for Gemini Code Assist for individuals… migrate to Antigravity»).
- En la máquina de Simón, `~/.gemini` es de Antigravity. El `~/.local/share/opencode/opencode-.db` es de OpenCode 1.x (tabla `session`, no `session_v2`).

## Decisiones de Simón en el brainstorming

| Tema | Elegido | Descartado y por qué |
| --- | --- | --- |
| Fixtures y «retoma con su comando real» | **Instalar los CLIs, grabar una sesión real de cada uno y sanearla**; la prueba de integración lanza el binario real en un PTY con el home temporal | Solo el listado del harness: no prueba que retome. Fixtures sintéticos: incumplen «fixtures reales» |
| Con qué se graba | **Ollama con `qwen3:4b`** para Codex (`--oss`) y OpenCode; Antigravity con la cuenta de Simón. Todo gratis | API key de OpenAI: de pago. El plan gratuito de ChatGPT no incluye Codex |
| Herramientas instaladas | **Se instalan para la fase y se desinstalan al cerrarla**: codex, opencode, ollama y el modelo (`agy` ya estaba y se queda) | Dejarlas: Simón no las usa a diario |
| Gemini CLI | **Fuera de F6 y del proyecto**: Antigravity cubre a Google | API key de AI Studio: Google está abandonando Gemini CLI para individuos |
| Captura del ID de sesión | **Búsqueda en disco**: la sesión más nueva del harness en el directorio del panel, creada después de que arrancó su proceso | Hooks en cada harness: Smalti escribiría en tres configuraciones de Simón |
| Enlaces «Abrir en Neovim» | **Dos entradas**: grupo «Editados por Claude» en ⌘K y ⌘-clic sobre `ruta:línea` en cualquier panel | Una sola de las dos |
| Lectura de las sesiones | **Directa de cada almacén y bajo demanda**: los harnesses ya tienen índice SQLite | Índice propio de Smalti: duplica índices y se desincroniza |
| Hablar con Neovim | **Cliente msgpack-RPC propio** por el socket, con `nvim_exec_lua` y argumentos | `--remote-send`: inyecta pulsaciones y falla con nvim en modo inserción |
| Prueba de «:w acepta, :q rechaza» | **Cliente de prueba con el protocolo de Claude** contra un nvim de prueba con claudecode.nvim | `claude --ide` real: gasta la suscripción en cada corrida y no es determinista |

Las decisiones de Claude van marcadas con **(Claude)** y se resumen en «Decisiones para aprobar con esta spec».

## Alcance

1. **El puerto `HarnessAdapter` completo:** `detect`, `captureSessionId`, `listSessions`, `resumeCommand`, más `continueCommand` (respaldo) y `forkCommand` (opcional). Cuatro implementaciones: Claude (la de F2, ampliada), Codex, Antigravity y OpenCode.
2. **Captura y restauración multi-harness:** un panel que corre `codex`, `agy` u `opencode` guarda su sesión. Al reabrir se relanza con `resumeCommand`. Si no hubo ID, se relanza con `continueCommand` en su directorio.
3. **Buscador de sesiones** del disco, filtrable por harness: columna derecha de la pantalla «Retomar donde quedaste» y tarjeta propia con atajo y en ⌘K.
4. **Neovim:**
   - `EditorBridge` por socket;
   - abrir nvim junto al agente;
   - «Abrir en Neovim» desde ⌘K («Editados por Claude») y con ⌘-clic sobre `ruta:línea`;
   - restaurar los paneles de nvim con archivo y línea (`nvim +42`);
   - instalador de claudecode.nvim en NvChad desde ⌘K.
5. **Observatorio:**
   - filtros «Todas», «Claude Code», «OpenCode» y «Locales»;
   - filas de OpenCode leídas de su base;
   - el pie con «base de OpenCode».
6. **Fixtures reales saneados** de los cuatro harnesses, prueba de contrato compartida y prueba de integración de reanudación.

## Fuera de alcance

- **Gemini CLI** (ver Decisiones). El chip «Gemini» y la fila de Gemini de `Reanudar.dc.html` no se pintan.
- **Estado por panel** (trabajando, te espera, error) **y notificaciones** de Codex, Antigravity y OpenCode. Necesitan hooks en cada harness, descartados. Sus paneles muestran el nombre del harness y quedan con el círculo hueco de «detenido» cuando el proceso termina. No hay verde ni ámbar **(Claude)**.
- **Codex y Antigravity en el Observatorio:** el tablero solo tiene los filtros de Claude Code, OpenCode y Locales. Sus sesiones salen en el buscador **(Claude)**.
- **Sesiones de OpenCode 1.x** (tabla `session`): solo se lee el esquema 2.x (`session_v2`). Las 23 sesiones antiguas de Simón aparecen cuando OpenCode 2.x migre su base **(Claude)**.
- **Rollouts `.jsonl.zst` de Codex:** el listado sale de `state_5.sqlite` y no hace falta descomprimir. Si `state_5.sqlite` no existe, Codex queda sin listado y la reanudación usa el respaldo **(Claude)**.
- Bifurcar en Antigravity y OpenCode 2.x: no tienen la opción.
- claudecode.nvim con otro editor o con otra distribución de Neovim que no sea NvChad. El MVP es NvChad y Claude Code (PROJECT.md).
- Escribir en `~/.codex`, `~/.gemini` o la config de OpenCode. Smalti solo lee esas carpetas.
- F7 (predicción con API, `smaltid`, OTLP) y F8.

## Enfoques considerados

| Tema | Elegido | Alternativas |
| --- | --- | --- |
| Lectura de sesiones | **Consulta SQLite de solo lectura** (`immutable=1`) por adaptador, bajo demanda, con un helper `SQLiteReader` compartido por los adaptadores **(Claude)** | Índice propio: ver Decisiones. Un adaptador que llame al CLI (`opencode session list`, `codex resume --all`): lento, depende de que esté instalado y de su formato de texto |
| Captura | **Búsqueda en disco** al ver el proceso del harness en primer plano, con reintentos mientras la sesión no aparece | Hooks: ver Decisiones. Leer el ID de la pantalla del TUI: frágil y depende del idioma |
| Neovim | **msgpack-RPC propio** en `NeovimAdapter` | `--remote-send` / `--remote-expr`: inyección y modos |
| Variantes de harness | **Un tipo por harness** que implementa `HarnessAdapter`, registrado en `HarnessRegistry`, con una prueba de contrato compartida (OCP) | Un `switch` por harness en el dominio: prohibido por `CLAUDE.md` |
| Integraciones en ⌘K | **Catálogo de `HarnessIntegration`** con dos implementaciones (plugin de Claude, claudecode.nvim): llega la abstracción que F5.6 aplazó a la segunda integración **(Claude)** | Dos acciones sueltas en el catálogo: duplica la lógica de estado y caché de F5.6 |

## Diseño técnico

### Módulos

| Módulo | Qué añade |
| --- | --- |
| `SmaltiCore/Domain/Harness` (nuevo) | `HarnessID` gana `codex`, `antigravity` y `opencode`. `HarnessSession` (harness, id, directorio, título, `updatedAt`, detalle: modelo o tokens si los hay). `SessionQuery` (filtro por harness, texto). `CaptureWindow` (directorio, arranque del proceso). `SessionCatalog` (une y ordena las listas de varios adaptadores; un adaptador que falla no tumba a los demás) |
| `SmaltiCore/Application/HarnessAdapter.swift` | Puerto ampliado (ver abajo); `HarnessRegistry` busca también por proceso |
| `SmaltiCore/Application` (casos de uso) | `CaptureHarnessSession` (proceso de harness en primer plano → ID → `AgentSnapshot` del panel), `SearchHarnessSessions` (buscador), `OpenHarnessSession` (Enter / ⌘Enter → panel nuevo en el directorio de la sesión con el comando), `TrackEditedFiles` (de `PostToolUse` a la lista «Editados por Claude»), `OpenInEditor` (ruta y línea → nvim existente o nuevo), `InstallIntegration` (catálogo de integraciones) |
| `SmaltiCore/Application/EditorPorts.swift` (nuevo) | Puerto `EditorBridge`: `open(file:line:in:)`, `current(of:) -> EditorPosition?` (archivo y línea del buffer activo, para guardar la sesión). Puerto `EditorProcesses` fuera: el panel de nvim es un panel más y su socket sale de `EditorSocketPath` (dominio) |
| `SmaltiCore/Domain/Session` | `AgentSnapshot.sessionID` se vuelve opcional: un panel de harness sin ID guarda harness y directorio, y se relanza con `continueCommand`. `PaneSnapshot` gana `editor: EditorPosition?` para los paneles de nvim. Las sesiones guardadas por F2–F5.6 se siguen leyendo igual (prueba de compatibilidad) |
| `SmaltiCore/Domain/Agent/AgentEvent` | `PostToolUse` gana `toolName` y `filePath` opcionales, más el texto nuevo (`new_string`, o la primera línea de `content`) para calcular la línea |
| `SmaltiCore/Domain/Observatory` | `ObservedSession` gana `harness` y `isLocalModel`. `ObservatoryFilter` (`all`, `claude`, `opencode`, `local`) filtra la tabla y recalcula el resumen. El pie gana «base de OpenCode» |
| `SmaltiCore/Domain/Terminal` | `ForegroundProcess` gana `pid` y `startedAt`: la captura necesita saber cuándo arrancó el harness. `TerminalEngine.foregroundProcess` lo rellena |
| `SQLiteReader` (paquete nuevo, infraestructura) | Abre una base en `mode=ro&immutable=1`, consulta con parámetros y traduce los errores de SQLite a uno tipado con ruta, operación y causa. Lo usan los adaptadores de Codex, Antigravity y OpenCode. No es un adaptador: no implementa puertos |
| `ClaudeHarnessAdapter` | `ClaudeHarness` gana `detect`, `captureSessionId` (sigue llegando por el hook; la búsqueda en disco es el respaldo), `listSessions` (con el índice de transcripts de F3), `continueCommand` y `forkCommand`. `ClaudecodeNvimInstaller` (segunda `HarnessIntegration`) |
| `CodexHarnessAdapter` (nuevo) | `CodexHarness` sobre `state_5.sqlite` (`archived = 0`, `source` interactivo o `exec`) |
| `AntigravityHarnessAdapter` (nuevo) | `AntigravityHarness` sobre `conversation_summaries.db` y `cache/last_conversations.json` |
| `OpenCodeHarnessAdapter` (nuevo) | `OpenCodeHarness` sobre `session_v2` (sin `parent_id` ni `time_archived`). `OpenCodeTelemetry` para el Observatorio (tokens, costo y modelo por sesión, `providerID` local) |
| `NeovimAdapter` (nuevo) | `NeovimBridge`: cliente msgpack-RPC por socket Unix; `open` llama a `nvim_exec_lua` con un fragmento fijo que recibe ruta y línea como argumentos |
| `SmaltiApp` | Columna del buscador en `RestoreView`; tarjeta del buscador; grupo «Editados por Claude» en ⌘K; ⌘-clic sobre `ruta:línea`; filtros del Observatorio; composition root con los adaptadores nuevos y sus flags de prueba |

### Puerto `HarnessAdapter`

```swift
public protocol HarnessAdapter: Sendable {
    var harness: HarnessID { get }
    var displayName: String { get }                       // "Codex", "Antigravity", "OpenCode"
    func detect(_ process: ForegroundProcess) -> Bool      // el proceso del panel es este harness
    func captureSessionId(in window: CaptureWindow) async throws(HarnessError) -> String?
    func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession]
    func resumeCommand(for agent: AgentSnapshot) -> String
    func continueCommand() -> String                       // continuar la última del directorio
    func forkCommand(for agent: AgentSnapshot) -> String?  // nil si el harness no bifurca
}
```

- `HarnessError` es tipado: almacén ausente, ilegible, con esquema desconocido o con columna que falta. Lleva ruta y causa.
- Un esquema que cambió devuelve `HarnessError.unknownSchema`, nunca un fallo de la app. El buscador lo muestra como texto secundario en la fila del chip («No se pudo leer Codex: esquema desconocido»), y la captura cae al respaldo.
- `detect` mira el nombre del proceso:
  - `claude`;
  - `codex`;
  - `antigravity` (el wrapper `agy` hace `exec` del binario `antigravity`);
  - `opencode`.
  
  Los nombres se verifican en el plan con los binarios instalados.
- Los IDs se citan para el shell como en `ClaudeHarness` (`'…'` si traen algo fuera de `[A-Za-z0-9_-]`).

### Captura del ID (búsqueda en disco)

1. `RunningPrograms` (F2) ve que el proceso en primer plano de un panel cambió. Si algún adaptador lo detecta, `CaptureHarnessSession` arma un `CaptureWindow` con el directorio del panel y `startedAt` del proceso.
2. **Antes de buscar en disco:**
   - si el panel ya conoce el ID, lo conserva: el de la restauración o el del buscador, porque Codex y OpenCode retoman sobre la misma sesión y no crean una nueva;
   - si la línea de comandos del proceso nombra una sesión (`codex resume <id>`, `codex fork` no, `opencode -s <id>`, `agy --conversation <id>`, `claude --resume <id>`), se toma esa **(Claude)**.
   
   Si no hay ninguno de los dos, llama a `captureSessionId`: la sesión más nueva de ese harness cuyo directorio coincide (rutas resueltas con `realpath`, sin `/private` de diferencia) y cuya fecha de creación es ≥ `startedAt` − 2 s. Antigravity no guarda fecha de creación en `conversation_summaries`: usa la fecha de nacimiento (`st_birthtime`) de `conversations/<id>.db`, que se verifica en el plan **(Claude)**.
3. Si aún no hay ninguna (el harness crea la sesión con el primer mensaje), reintenta cada 2 s mientras el proceso siga en primer plano, hasta 10 minutos **(Claude)**. El primer ID que aparece queda fijo en el panel. Si el usuario abre otra sesión dentro del mismo proceso (`/resume`), la captura no la sigue en F6.
4. **Desempate:** si dos paneles del mismo harness y directorio esperan a la vez, cada ID se asigna una sola vez, al panel cuyo proceso arrancó antes. Así nunca dos paneles quedan con el mismo ID.
5. Sin ID al guardar la sesión, el panel guarda harness y directorio, y al reabrir se relanza con `continueCommand()` en ese directorio. Ese es el respaldo «continuar la última del directorio». Su fila en «Retomar» lo avisa: «`agy -c` · la última del directorio» **(Claude)**.
6. **Claude** sigue con su hook `SessionStart` (F2), que manda siempre. La búsqueda en disco solo cubre un Claude sin el plugin.

### Buscador de sesiones

- **Dónde:**
  - columna derecha de «Retomar donde quedaste» (`Reanudar.dc.html`);
  - tarjeta propia centrada sobre el vidrio, con el mismo contenido. Se abre con **⌘⇧O** («Buscar sesiones de agentes») y desde ⌘K **(Claude)**.
- **Contenido (tablero):**
  - título «Todas las sesiones de agentes» y subtítulo «Leídas del disco de cada harness, aunque no las abrieras aquí.»;
  - chips «Todas», «Claude Code», «Codex», «Antigravity», «OpenCode», sin «Gemini»;
  - filas con título, fecha relativa («ayer», «jue») y línea secundaria «Harness · proyecto · detalle» (tokens de Claude, modelo de OpenCode);
  - pie «Enter abre la sesión en un panel nuevo con el comando correcto del harness. ⌘Enter la bifurca cuando el harness lo permite.»
- **Escribir filtra** por título y proyecto, como en ⌘K (búsqueda difusa de F1). El tablero no dibuja campo de texto: lo escrito sale en el lugar del subtítulo mientras haya texto **(Claude)**. ←→ o ⌘1…⌘5 cambian de chip, ↑↓ recorren la lista y Esc cierra.
- **Datos:**
  - se leen al abrir, en segundo plano. Cada adaptador tiene 500 ms; el que tarda más sale después y no bloquea a los demás;
  - se muestran las 200 sesiones más recientes en total, virtualizadas como la lista de ⌘K;
  - solo salen los harnesses cuyo almacén existe; sin ninguno, el texto es «No hay sesiones de agentes en este Mac».
- **Teclado en «Retomar donde quedaste»** (decidido por Simón):
  - el foco empieza en la columna izquierda, con el teclado de F2 (↑↓, espacio, ↵ restaura, Esc «Empezar limpio»);
  - **Tab** pasa el foco entre las dos columnas;
  - con el foco en el buscador, **Esc** devuelve el foco a la izquierda y nunca descarta nada;
  - **Enter** sobre una sesión primero restaura lo marcado a la izquierda, igual que «Restaurar», y después abre la sesión en un panel nuevo del primer workspace restaurado (o de uno nuevo si no se restauró ninguno);
  - **⌘Enter** hace lo mismo, bifurcando.
- **Enter (tarjeta sola):** `OpenHarnessSession` abre un panel nuevo en el workspace activo, con el directorio de la sesión, y escribe `resumeCommand`. Si el directorio ya no existe, abre en el home y avisa en la barra de estado («La carpeta de la sesión ya no existe: <ruta>»).
- **⌘Enter:** usa `forkCommand`. Si el harness no bifurca, nada se abre y la barra de estado dice «Antigravity no permite bifurcar sesiones».
- **Restaurar:** las filas de agentes de la columna izquierda muestran el comando de cada harness (`codex resume 0198…`, `agy --conversation c41e…`), como en el tablero. Una fila sin ID muestra `continueCommand` (`agy -c`).

### Neovim

**Paneles de nvim de Smalti.**
- «Abrir Neovim junto al agente» (**⌘⇧E**, y en ⌘K) abre un panel junto al panel activo, en su directorio, con `nvim --listen <socket>`.
- El socket es `EditorSocketPath`: `<dir corto>/smalti-<uid>/nvim-<pane>.sock`, por debajo de los 104 bytes de `sun_path`; el adaptador lo comprueba con una prueba de longitud **(Claude)**.
- Smalti reconoce un nvim suyo por el socket. Un `nvim` escrito a mano en un panel no tiene socket y no recibe enlaces.

**Claude con `--ide`.**
- Cuando claudecode.nvim está instalado, los Claude que relanza Smalti (restaurar, buscador) añaden `--ide` y se conectan solos al nvim del mismo directorio.
- Un `claude` escrito a mano se conecta con `/ide`.
- Smalti no pone variables de entorno de IDE en los paneles **(Claude)**.

**Abrir en Neovim.**
- **⌘K, grupo «Editados por Claude»:**
  - lista los últimos 20 archivos que tocó el Claude del panel activo, el más reciente primero, con nombre, «línea N» y «hace 2 min»;
  - salen de `PostToolUse` con `tool_name` Edit, MultiEdit, Write o NotebookEdit y `tool_input.file_path`;
  - para calcular la línea, Smalti busca en el archivo la primera línea del texto nuevo; si no la encuentra, usa la línea 1;
  - la lista vive en memoria y no se guarda **(Claude)**;
  - el atajo **⌘⇧L** abre el más reciente **(Claude)**.
- **⌘-clic sobre `ruta:línea[:columna]`** o sobre una ruta sola, en cualquier panel:
  - reutiliza `PointerWord` de F5.5;
  - la ruta relativa se resuelve con el directorio del panel;
  - una ruta que no existe no hace nada;
  - solo va a nvim un archivo regular de texto (sin bytes nulos en sus primeros 8 KB). Smalti intercepta el ⌘-clic antes que libghostty solo en ese caso. URLs, carpetas, imágenes, PDF y binarios siguen con el «⌘clic abre enlaces» de F4.5 **(Claude)**.
- **Destino:** el nvim de Smalti del mismo workspace. Si hay varios, el último que tuvo el foco. Salta al archivo y la línea sin abrir otro nvim y le da el foco a su panel. Sin ninguno, abre un panel nuevo con `nvim --listen <socket> +N <archivo>` junto al panel de origen.

**Restaurar.**
- Al guardar la sesión, Smalti pide a cada nvim suyo el archivo y la línea del buffer activo (`EditorBridge.current`, con 200 ms de límite).
- La fila de «Retomar» muestra «reminder.service.ts · línea 42» y `nvim +42`, como el tablero. Al reabrir se relanza con `nvim --listen <socket> +42 <archivo>`.

**Instalador de claudecode.nvim (NvChad).**
- ⌘K ofrece «Instalar claudecode.nvim en Neovim» o «Desinstalar claudecode.nvim», nunca las dos, con la misma caché de estado de F5.6.
- Instalar escribe un solo archivo propio, `$XDG_CONFIG_HOME/nvim/lua/plugins/smalti-claudecode.lua` (por defecto `~/.config/nvim`). Es una spec de lazy.nvim con `coder/claudecode.nvim` fijado a `v0.4.0`, `terminal = { provider = "none" }` (Claude vive en su panel de Smalti) y una marca `-- Instalado por Smalti`.
- No toca ningún otro archivo de la config. lazy.nvim instala el plugin al siguiente arranque de nvim.
- Desinstalar borra solo ese archivo, y solo si lleva la marca.
- Estado desconocido, y ninguna de las dos acciones, si la config no parece de NvChad (sin `lua/plugins/` ni `import = "plugins"` en `init.lua`) **(Claude)**.

### Observatorio

- Los chips «Todas | Claude Code | OpenCode | Locales» se ponen junto al periodo, como en el tablero. Se cambian con clic, desde ⌘K y con **⌘⇧F** (`observatory.filter`, que recorre los cuatro) **(Claude)**.
- Filtran la tabla, y las tarjetas de resumen se recalculan con lo filtrado.
- **OpenCode:**
  - una fila por sesión de `session_v2` con actividad en el periodo;
  - entrada `tokens_input + tokens_cache_read`, salida `tokens_output`, «OpenCode · <modelo>» con «local» si su `providerID` es local, como en el tablero;
  - la columna de contexto queda en «—» si no hay dato;
  - sin PID ni estado vivo: «detenida», o «—» en vida.
- **Locales:** sesiones cuyo proveedor es local (`ollama`, `lmstudio`, o una `baseURL` en `localhost` / `127.0.0.1`). Claude nunca lo es.
- **Pie:** «Datos: hooks y transcripts de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado.»
- El filtro elegido se recuerda durante la sesión de la app y no se guarda en el TOML **(Claude)**.

### Configuración y flags de prueba

- **Rutas reales por defecto:**
  - Codex: `CODEX_HOME` o `~/.codex`;
  - Antigravity: `~/.gemini/antigravity-cli`;
  - OpenCode: `OPENCODE_DB` o `$XDG_DATA_HOME/opencode/opencode.db`, con `opencode-*.db` como respaldo si solo hay una;
  - Neovim: `XDG_CONFIG_HOME` o `~/.config`; Claude: `CLAUDE_CONFIG_DIR` o `~/.claude`.
- **Flags de las UI tests:** `-SmaltiCodexHome`, `-SmaltiAntigravityHome`, `-SmaltiOpenCodeDB`, `-SmaltiNvimCommand` (nvim con `--clean` o con config temporal), `-SmaltiNvimConfigHome` (XDG temporal del instalador) y `-SmaltiEditorSocketDir`. Se suman a `-SmaltiClaudeHome` de F3.
- No hay sección TOML nueva: nada de esto lo pidió Simón como ajuste **(Claude)**.

### Textos nuevos (interfaz en español)

- **Buscador:** «Todas las sesiones de agentes», «Leídas del disco de cada harness, aunque no las abrieras aquí.», «No hay sesiones de agentes en este Mac», «No se pudo leer <harness>: <motivo>», «<harness> no permite bifurcar sesiones», «La carpeta de la sesión ya no existe: <ruta>».
- **⌘K:** «Buscar sesiones de agentes», «Abrir Neovim junto al agente», «Editados por Claude», «Abrir en Neovim el último archivo editado», «Instalar claudecode.nvim en Neovim», «Desinstalar claudecode.nvim», «Filtrar el Observatorio».
- **Observatorio:** «Todas», «Claude Code», «OpenCode», «Locales» y el pie nuevo.

### Fixtures reales

- `scripts/harnesses/record-fixtures.sh <harness>` graba una sesión de 2–3 mensajes en un home de grabación.
- El home de grabación, `scripts/harnesses/recording.local/`, no se versiona (`.gitignore`): guarda el token de Antigravity y la config de Codex. Ollama se levanta solo mientras graba.
- `scripts/harnesses/sanitize_fixture.py`, con sus pruebas en `unittest` como el saneador de F3:
  - cambia rutas absolutas por un marcador, que la prueba sustituye por su directorio temporal;
  - quita correos, IDs de instalación y de proyecto, y tokens;
  - deja el resto byte a byte.

  Los marcadores personales salen de `scripts/observatory/markers.local`, que ya existe.
- Los fixtures saneados viven en `Packages/<X>HarnessAdapter/Tests/Fixtures/`: la base SQLite, más el rollout de Codex y el de conversación de Antigravity que hagan falta para retomar.
- **Claude:** se reutilizan los fixtures reales de F3. Para la prueba de integración se graba uno nuevo con `claude -p` y la suscripción, si su reanudación lo necesita (ver Riesgos).

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
| --- | --- | --- |
| C1 | **Cierre del roadmap (enmendado):** una prueba de contrato compartida (`HarnessAdapterContract`) pasa para los **4** adaptadores sobre fixtures reales saneados. Cubre `detect`, `listSessions` (orden, filtro por texto, directorio, excluidas archivadas y subsesiones), `captureSessionId` (nueva tras el arranque, ninguna anterior, desempate), `resumeCommand`/`continueCommand`/`forkCommand` (citado de IDs hostiles) y almacén ausente o con esquema desconocido → error tipado | `SmaltiCoreTestSupport` + cada paquete de adaptador |
| C2 | **Cierre del roadmap:** una prueba de integración retoma la sesión de fixture de cada harness con **su comando real**. Ejecuta el `resumeCommand` del adaptador con `/bin/zsh -f -c` en un PTY, con el home temporal, y espera hasta 45 s a que aparezca el primer mensaje de la sesión. Después mata el grupo de procesos y los daemons del harness, buscados por la ruta del home temporal, y comprueba que no queda ninguno. Si el binario no está, o falta el login de Antigravity en `recording.local`, la prueba se salta con el motivo | `HarnessResumeIntegrationTests` por paquete |
| C3 | **Cierre del roadmap (enmendado):** un diff con el protocolo de Claude se acepta con `:w` y se rechaza con `:q`. Un cliente de prueba lee el lock de claudecode.nvim (v0.4.0, vendorizado) en un `CLAUDE_CONFIG_DIR` temporal, abre el WebSocket con su token, llama a `openDiff`, envía `:w` o `:q` por el socket de nvim y recibe `FILE_SAVED` (con el contenido) o `DIFF_REJECTED`. nvim corre con `--clean` y su propio socket | `NeovimAdapter` (integración) |
| C4 | Captura: un panel que ya conoce su ID (restaurado o abierto desde el buscador) lo conserva; un `resume` escrito a mano toma el ID de su línea de comandos; si no, el ID llega al panel cuando aparece la sesión, aunque tarde, con reintentos; nunca se toma una sesión anterior al arranque ni de otro directorio; dos paneles del mismo harness y directorio reciben IDs distintos; sin ID, el panel guarda harness y directorio | Dominio con adaptadores falsos y reloj controlado |
| C5 | Restaurar: un panel con ID se relanza con `resumeCommand` y uno sin ID con `continueCommand`, ambos en su directorio. Las sesiones guardadas por F2–F5.6 se leen igual. La fila de «Retomar» muestra el comando de cada harness | Dominio + compatibilidad de `SessionArchive` + XCUITest de la pantalla de restaurar |
| C6 | Buscador: en «Retomar», Tab cambia de columna, Esc en el buscador devuelve el foco sin descartar nada y Enter restaura lo marcado y luego abre la sesión; chips sin Gemini, filtro por harness y por texto, orden por fecha, tope de 200, un adaptador lento o roto no bloquea a los demás, Enter abre con el comando correcto en el directorio de la sesión, ⌘Enter bifurca o avisa, directorio que no existe → home y aviso | Dominio (`SessionCatalog`, `SearchHarnessSessions`, `OpenHarnessSession`) + XCUITest con fixtures en homes temporales |
| C7 | El buscador abre en ≤ 100 ms con los cuatro almacenes de fixture, y la lectura nunca corre en el hilo principal | Signpost al cierre (como B7) |
| C8 | «Editados por Claude»: archivos de `PostToolUse` (Edit, MultiEdit, Write, NotebookEdit), tope de 20, más reciente primero, línea calculada (o 1), solo del Claude del panel activo | Dominio (`TrackEditedFiles`) + XCUITest con eventos inyectados por el socket de IPC |
| C9 | Abrir en Neovim: ruta absoluta, relativa, con `:línea` y `:línea:columna`, con espacios, comillas y `<CR>` en el nombre (sin inyección); nvim existente → salta y enfoca; sin nvim → panel nuevo con `+N`; ruta inexistente → nada | Dominio (`OpenInEditor`, `EditorTarget`) + `NeovimAdapter` contra `nvim --clean` + XCUITest |
| C10 | Restaurar nvim: archivo y línea del buffer activo guardados y relanzados con `nvim --listen <socket> +N <archivo>`; nvim que no responde en 200 ms → fila de proceso como en F2 | Dominio + `NeovimAdapter` |
| C11 | Instalador: sobre un `XDG_CONFIG_HOME` temporal con un starter de NvChad escribe solo `lua/plugins/smalti-claudecode.lua`, con la marca y `v0.4.0`; desinstalar lo borra solo si lleva la marca; config que no es de NvChad → estado desconocido; ⌘K muestra solo la acción que aplica; un nvim headless con esa config carga claudecode.nvim sin red. Para eso, `scripts/harnesses/prepare-nvim-fixtures.sh` prepara una vez lazy.nvim y claudecode.nvim `v0.4.0` fijados en `build/nvim-fixtures/` (sin versionar), con un `init.lua` mínimo que hace el mismo `import = "plugins"` que NvChad; sin preparación, la prueba se salta con el motivo **(Claude)** | `ClaudeHarnessAdapter` (instalador) + XCUITest con `-SmaltiNvimConfigHome` |
| C12 | Observatorio: los cuatro filtros filtran la tabla y recalculan el resumen; las filas de OpenCode salen de `session_v2` con tokens y modelo, «local» y en «Locales» cuando el proveedor es local; el pie dice «base de OpenCode» | Dominio (`ObservatoryFilter`, `ObservedSession`) + `OpenCodeTelemetry` con fixture + XCUITest |
| C13 | Robustez: base en WAL abierta mientras el harness escribe, base bloqueada, columna que falta, JSON de `workspace_uris` o de `session_message` mal formado, rutas con espacios y Unicode → error tipado o fila omitida, nunca un fallo | Adaptadores con fixtures mutilados |
| C14 | Aislamiento: ninguna prueba lee ni escribe `~/.claude`, `~/.codex`, `~/.gemini`, `~/.local/share/opencode` ni `~/.config/nvim` reales. Una guarda falla si un adaptador construye esas rutas sin pasar por su parámetro de home | Guarda + `isolatedSmalti()` con los flags nuevos + `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID` |
| C15 | Guardas: `SmaltiCore` en Swift puro; solo `SQLiteReader` importa `SQLite3`; ningún `Logger` publica rutas, títulos de sesión ni contenido de archivos | Pruebas de guarda |
| C16 | Sin procesos huérfanos: tras cada suite de integración no queda ningún `nvim`, `codex`, `antigravity`, `opencode` ni `ollama` lanzado por ella | Comprobación al final de cada suite + revisión manual en el cierre |
| C17 | Mutación ≥ 80 % en `SmaltiCore` | `scripts/mutation/mutate.py` al cierre (ver «Plan de pruebas») |

**Criterio de cierre propuesto para el roadmap:** C1 (4 adaptadores), C2 y C3, en verde.

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| `claude --resume` con `CLAUDE_CONFIG_DIR` temporal pide login (la credencial está en el llavero con otro nombre) | C2 de Claude no se puede automatizar | **Primera tarea del plan:** spike. Si pide login, el login se hace una vez en `recording.local` con la suscripción (gratis) y la prueba lo copia, como en Antigravity |
| Codex u OpenCode necesitan Ollama encendido para retomar | La prueba de integración depende de un servidor | Se comprueba en el mismo spike. Si lo necesitan, la prueba lo arranca con su propio `OLLAMA_HOST` y puerto, y lo mata al terminar |
| Los formatos cambian (Codex 0.172 ya existe; OpenCode publica a menudo) | Lista vacía o captura fallida | Esquema comprobado al abrir (`HarnessError.unknownSchema`), respaldo «continuar», fixtures fijados a la versión grabada y anotada en el fixture |
| Codex resume pide confianza o login en el uso real de Simón | — | No es de Smalti: Smalti solo escribe el comando, igual que Simón |
| Daemons de Codex y OpenCode | Procesos huérfanos tras las pruebas | Se matan por la ruta del home temporal; C16 |
| El nombre del proceso en primer plano no es el esperado (wrappers, `node`) | `detect` falla | Se verifica en el plan con los binarios instalados; `detect` también mira `commandLine` |
| La sesión aparece en disco minutos después del arranque | Captura tardía | Reintentos de hasta 10 minutos; respaldo «continuar» |
| `sun_path` de 104 bytes | El socket de nvim no se crea con rutas largas | Directorio corto propio y prueba de longitud |
| claudecode.nvim cambia entre versiones | Instalador o C3 rotos | Versión fijada (`v0.4.0`) y vendorizada para las pruebas; subirla es un cambio a propósito |

## Plan de pruebas y revisiones

Según `.claude/rules/`:
- **Revisiones:**
  - intermedia 1, al terminar dominio y adaptadores (puerto, captura, catálogo, cuatro adaptadores, `SQLiteReader`, `NeovimAdapter`, instalador, fixtures, contrato e integración);
  - intermedia 2, al terminar la app (buscador, restaurar, ⌘K, ⌘-clic, Observatorio);
  - final de la rama, acotada y con el modelo más capaz.
- **Mutación:**
  - una por revisión intermedia, con `--changed-since`, después de sus correcciones; cada sobreviviente se mata con una prueba verificada aplicando el mutante a mano;
  - al cerrar, completa de `SmaltiCore`: esta fase cambia código compartido (`HarnessAdapter`, `AgentSnapshot`, `ForegroundProcess`, `AgentEvent`, `ObservedSession`).
- Mediciones (C7) y capturas (buscador y filtros del Observatorio junto a sus tableros) solo al cierre.
- XCUITest en una sola corrida de `scripts/test-ui.sh` por tanda, solo lo afectado, nunca dos a la vez, siempre por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID`.
- **Aislamiento de las pruebas:**
  - las que abren un shell usan `-SmaltiShellCommand "/bin/zsh -f"`;
  - las apps GUI se lanzan con `env -i`;
  - el nvim de las pruebas usa `--clean` o una config temporal, con su propio socket.
- **Al cerrar la fase,** después de las suites y del checklist, se desinstalan codex, opencode y ollama (con `~/.ollama`) y se borra `recording.local`. A partir de ahí, C2 se salta con su motivo.

## Cambios en otros documentos (con esta spec)

- `docs/ROADMAP.md`, F6:
  - entregables sin Gemini CLI;
  - criterio de cierre: «4 adaptadores», C2, y «un diff con el protocolo de Claude se acepta con `:w` y se rechaza con `:q`»;
  - spec: esta.
- `docs/PROJECT.md`:
  - tabla de reanudación sin Gemini CLI y con las rutas verificadas (Codex `$CODEX_HOME/sessions` + `state_5.sqlite`; OpenCode `opencode.db`; Antigravity `~/.gemini/antigravity-cli`);
  - «HarnessAdapter → Claude Code, Codex, Antigravity, OpenCode»;
  - línea de F6 en «Fases propuestas».
- `docs/design/README.md`: nota bajo `Reanudar.dc.html` (sin chip ni fila de Gemini; la tarjeta del buscador también se abre sola con ⌘⇧O) y bajo `Observatorio.dc.html` (los filtros se cambian también con ⌘⇧F).
- `CLAUDE.md`:
  - paquetes nuevos en «Comandos»: `swift test --package-path Packages/<CodexHarnessAdapter|AntigravityHarnessAdapter|OpenCodeHarnessAdapter|NeovimAdapter|SQLiteReader>`, más `record-fixtures.sh` y el saneador;
  - lista de puertos con `EditorBridge` ya implementado;
  - la línea de `swift format lint`.
- `.gitignore`: `scripts/harnesses/recording.local/`.

## Decisiones para aprobar con esta spec

1. Las de Simón de la tabla del principio: fixtures reales grabados con Ollama y la cuenta de Antigravity, herramientas instaladas solo durante la fase, Gemini fuera, captura por disco, dos entradas a Neovim, lectura directa, msgpack-RPC y cliente de prueba con el protocolo de Claude.
2. **Criterio de cierre enmendado:** 4 adaptadores en lugar de 5, y «diff con el protocolo de Claude» en lugar de «diff de Claude».
3. **Fuera de alcance (Claude):**
   - estado y notificaciones de los harnesses que no son Claude;
   - Codex y Antigravity fuera del Observatorio;
   - solo el esquema de OpenCode 2.x;
   - sin descomprimir `.zst` de Codex.
4. **Captura (Claude):**
   - se conserva el ID conocido, o se lee de la línea de comandos;
   - reintentos cada 2 s hasta 10 minutos, margen de 2 s antes del arranque, desempate por orden de arranque;
   - Antigravity usa la fecha de nacimiento del archivo de la conversación;
   - sin seguir un `/resume` dentro del mismo proceso;
   - la fila de respaldo avisa «la última del directorio».
5. **Buscador:** teclado de «Retomar» con Tab entre columnas, Esc que nunca descarta y Enter que restaura y luego abre (Simón). También como tarjeta propia con ⌘⇧O (Claude); escribir filtra y el texto sale en el lugar del subtítulo; 500 ms por adaptador; tope de 200.
6. **Neovim (Claude):**
   - ⌘⇧E abre nvim junto al agente;
   - ⌘⇧L abre el último archivo editado;
   - `--ide` solo en los Claude que relanza Smalti;
   - lista de editados en memoria, tope de 20;
   - destino: el último nvim enfocado del workspace;
   - el ⌘-clic solo intercepta archivos de texto; lo demás sigue con F4.5;
   - la prueba de NvChad corre sobre lazy.nvim y claudecode.nvim preparados en `build/`, sin NvChad vendorizado.
7. **Instalador (Claude):** un archivo propio con marca en `lua/plugins/`, claudecode.nvim `v0.4.0` sin terminal propio, estado desconocido fuera de NvChad.
8. **Observatorio (Claude):** ⌘⇧F recorre los filtros; el filtro no se guarda; definición de «Locales» por proveedor.
9. **Sin sección TOML nueva;** flags `-Smalti…` para las pruebas (Claude).
10. **`ForegroundProcess` gana `pid` y `startedAt`;** `AgentSnapshot.sessionID` pasa a opcional, con prueba de compatibilidad; paquete `SQLiteReader` compartido (Claude).
11. Mutación completa de `SmaltiCore` al cerrar, porque cambia código compartido.

## Enmiendas

1. **2026-11-24 · Plan, Claude.** «Locales» se decide solo por `providerID` (`ollama`, `lmstudio`): `opencode.db` no guarda la `baseURL` del proveedor, que vive en la config de OpenCode, y Smalti no la lee.

# F9 · Timeline de la sesión — Spec

Estado: aprobada · 2026-11-26 (Simón aprobó de antemano la spec, el plan, las recomendaciones de Claude, los merges, el release y el despliegue. La maqueta de «PARA 1» se le envió; sin respuesta, se sigue con la recomendación, como pidió) · Roadmap: `docs/ROADMAP.md#f9--timeline-de-la-sesión`
Diseño: no hay tablero. La referencia es la maqueta `docs/specs/F9-assets/mockup.html` (`?view=session|search|empty|fallback|unidentified&lang=es|en`, capturas `mockup-*-{es,en}.png`), en la línea de `Observatorio.dc.html` y `Reanudar.dc.html` y con los tokens de `docs/design/README.md`.

## Objetivo

Recuperar lo que hizo un agente aunque ya no se vea. Claude Code y Codex dibujan en la pantalla alternativa: lo que pasó hace veinte minutos no está en el scrollback. F9 lee sus transcripts y lo devuelve:

- un **panel lateral** (⇧⌘T y ⌘K) con los turnos del agente del panel enfocado: el prompt, la respuesta, las herramientas plegadas (nombre, argumentos resumidos, estado) que se despliegan con teclado, los errores, los subagentes y las compactaciones;
- **búsqueda** en todas las sesiones del proyecto, abiertas o cerradas, con salto al turno;
- **copiar íntegro** cualquier prompt, respuesta, llamada o salida de herramienta (⌘C), aunque la vista la pliegue;
- todo con teclado, en inglés y en español, sin coste con el panel cerrado.

Anti-objetivo: **F9 fracasa si**:

- lo copiado no es byte a byte lo que el agente escribió en su transcript (truncado, re-formateado, con saltos de línea cambiados);
- el timeline muestra la sesión de otro panel o una sesión adivinada sin decirlo;
- con el panel cerrado hay lecturas, temporizadores, observadores de archivos o índices en memoria;
- una sesión de 60 MB congela la interfaz o se queda entera en memoria como texto;
- algo escribe en los transcripts, en `~/.claude` o en `~/.codex` (solo lectura, siempre);
- una prueba lee el `~/.claude` o el `~/.codex` reales, o una captura enseña un transcript, un prompt o una ruta de Simón;
- se adelanta F10/F11 (revisión con Neovim, enmascarar secretos), se editan o reenvían turnos, o la app hace otra petición de red.

## Hechos verificados (antes de diseñar)

Medidos el 2026-11-26 en el MacBook Air M4 de Simón, macOS 27.2, con un programa de prueba compilado con `swiftc -O` (`scratchpad/spike`, no se versiona), sobre su `~/.claude/projects` real **en solo lectura**: 917 MB, 278 transcripts, el mayor de 59,6 MB, el proyecto mayor con 412 MB en 136 archivos.

### 1. Fuentes y qué reutilizar

**Claude Code** (`~/.claude/projects/<carpeta>/<sesión>.jsonl`, formato sin documentar, comprobado con 2.1.330):

- Turnos: líneas `type: "user"` con `message.content` texto (o bloques `text` e `image`) son prompts; `isMeta: true` no lo son (avisos inyectados); `isCompactSummary: true` es el resumen de una compactación. Líneas `type: "assistant"`: un bloque por línea; `text` es la respuesta, `tool_use` (`id`, `name`, `input`) una llamada, `thinking` se ignora (Claude Code 2.1 lo guarda vacío). Las líneas `user` con bloques `tool_result` (`tool_use_id`, `content` texto o bloques, `is_error`) son resultados.
- Compactación: `type: "system"`, `subtype: "compact_boundary"`, con `compactMetadata.preTokens/postTokens` (ya lo lee F3).
- Subagentes: `<carpeta>/<sesión>/subagents/agent-<id>.jsonl`, con su `.meta.json` (`toolUseId` = la llamada `Agent`/`Task` que lo lanzó). Si falta el `.meta.json` (fixtures de F3), el `tool_result` de la llamada dice `agentId: <id>` en el texto o en `toolUseResult.agentId`.
- Imágenes: bloques `image` (`source.media_type`, `source.data` en base64) en prompts y en resultados.
- **Qué hay en F3** (`ClaudeTelemetryAdapter`): `TranscriptLineReader` (lectura incremental por offset, bloques de 1 MB, línea a medias para la siguiente), descubrimiento de archivos y subagentes, y un traductor que **recorta** los argumentos a 200 caracteres y **no** guarda prompts, respuestas ni salidas: sirve para el Observatorio, no para el timeline. Se reutiliza el lector (pasa a un paquete compartido) y el descubrimiento; la traducción del timeline es nueva.
- **Qué hay en F6** (`ClaudeHarnessAdapter`): `ClaudeSessionList` (sesiones de un proyecto, título = primer prompt, carpeta codificada de Claude). Se reutiliza para la lista de sesiones y para encontrar el archivo de una sesión.

**Codex** (`$CODEX_HOME/sessions/AAAA/MM/DD/rollout-…-<id>.jsonl`, comprobado con 0.172.0; índice `state_5.sqlite`, tabla `threads`, columna `rollout_path`):

- Turnos: `response_item` con `payload.type: "message"`: `role: "user"` con `input_text` es prompt **salvo** los que empiezan por `<environment_context>`, `<user_instructions>` o `<skills_instructions>` (contexto que inyecta Codex) y `role: "developer"`; `role: "assistant"` con `output_text` es respuesta. `function_call` (`name`, `arguments` en JSON, `call_id`) y `custom_tool_call` (`name`, `input`, `call_id`) son llamadas; `function_call_output` y `custom_tool_call_output` (`call_id`, `output`) sus resultados. El estado sale de la línea `Process exited with code N` de la salida (N ≠ 0 → error). `reasoning` se ignora. `compacted` es una compactación (sin tokens).
- Los rollouts de más de una semana se comprimen a `.zst`: macOS no trae zstd. **No se leen en F9**: la sesión aparece en la lista con la nota «comprimida por Codex» y no se abre ni se busca.
- **Qué hay en F6** (`CodexHarnessAdapter`): la lista de sesiones desde `state_5.sqlite` (con `SQLiteReader`). Se reutiliza; la lectura del rollout es nueva.
- **Fixtures:** los de F6 solo tienen respuestas de texto. Para F9 se grabó uno real nuevo con `--oss` (Ollama local, qwen3:4b, gratis): `Fixtures/codex-timeline`, una sesión de dos turnos (`exec` y `exec resume`) con `exec_command` que acierta (`ls`) y que falla (`cat missing.txt`, exit 1). `record-fixtures.sh codex-timeline` lo regraba.

**Antigravity y OpenCode** (`SQLiteReader`): **se aplazan.**

- Antigravity guarda cada conversación en un SQLite (`conversations/<id>.db`) cuyos pasos (`steps.step_payload`) son blobs protobuf sin esquema publicado: leerlos es ingeniería inversa de un formato que cambia sin aviso.
- OpenCode guarda mensajes y partes en `opencode.db` (`session_message`, `session_part`) en JSON: es viable, pero el alcance de F9 son Claude Code y Codex, y añadirlo después es un tipo nuevo que implementa el puerto (OCP), sin tocar el dominio ni la vista.
- Con esos harnesses en el panel, el timeline muestra el respaldo (maqueta `fallback`).

### 2. Panel ↔ sesión

Lo que ya existe en `Pane`: `agent: AgentSession?` (Claude Code, por sus hooks: `sessionID` en cada evento) y `liveHarnessBinding: HarnessBinding?` (F6: harness + `sessionID` capturado del disco o del comando `resume`). La regla, en el dominio (`TimelineTarget`):

1. El agente de los hooks gana (es el que el panel ve ahora), aunque haya salido al shell: el panel conserva su `agent` y el timeline sigue mostrando esa sesión.
2. Si no, el `harnessBinding` del panel con `sessionID`.
3. Un harness detectado sin `sessionID` (Codex abierto antes de Smalti, captura fallida): **respaldo honesto**, la sesión más reciente de ese harness en la carpeta del panel, con el aviso «Smalti no sabe qué sesión … escribe este panel … puede no ser esta» (maqueta `unidentified`).
4. Un harness sin transcript legible (Antigravity, OpenCode): «<harness> no deja un transcript que Smalti sepa leer» y las sesiones recientes del proyecto (maqueta `fallback`).
5. Sin agente (el shell): «Este panel no tiene un agente» y las sesiones recientes del proyecto (maqueta `empty`).

El timeline sigue al panel enfocado: con el panel lateral abierto, ⌘1…⌘9 y ⌘⌥←→↑↓ cambian de panel y el timeline cambia de sesión.

### 3. Coste

- **Lectura completa de una sesión grande** (59,6 MB, 5.384 líneas, 1.719 `user`/`assistant`): 0,35–0,39 s con el mismo esquema de F3 (bloques de 1 MB, filtro de marcas antes de `JSONSerialization`). Se lee fuera del hilo principal y la vista se pinta cuando termina (con «Leyendo…» si tarda más de 150 ms).
- **Incremental:** el adaptador guarda el offset del último byte leído de cada archivo de la sesión abierta y solo lee lo nuevo (el lector de F3 ya deja la línea a medias para la siguiente).
- **Seguir la sesión viva:** con el panel abierto, se observa **el archivo de la sesión mostrada** (y la carpeta de sus subagentes) con `DispatchSource` (`.write`, `.extend`, `.delete`, `.rename`), coalescido a 150 ms. Elegido frente a refrescar con los eventos de hook: los hooks solo llegan de Claude Code con el plugin y Codex no los tiene, y `Stop` llega antes de que Claude escriba la última línea. Un `kqueue` por archivo abierto es gratis en reposo; al cerrar el panel o cambiar de sesión se cancela.
- **Memoria:** el modelo guarda cada texto recortado a 2.000 caracteres para pintar y **la ubicación** (archivo, offset, longitud de la línea, posición del bloque) para recuperarlo entero. Copiar y desplegar leen la línea del disco y extraen el texto íntegro. Tope: una sesión de 60 MB ocupa unos pocos MB de modelo (se mide al cierre, C8). Con el panel cerrado se suelta todo.
- **Virtualización:** la lista es un `NSTableView` con filas de vista y alturas variables: solo existen las filas visibles.

### 4. Búsqueda

- **Alcance:** las sesiones del proyecto del panel enfocado: su raíz (la de F8.5: el proyecto del workspace, el de `.smalti/layout.json` hacia arriba, el repositorio git más cercano o la carpeta del panel; la misma regla que `SaveProjectLayout.root(of:)`) y todas las carpetas debajo. Claude Code: las carpetas de `projects/` cuyo nombre codificado empieza por el de la raíz, confirmadas por el `cwd` de su cabecera. Codex: `threads.cwd` igual a la raíz o debajo.
- **Bajo demanda, sin índice.** Medido sobre el proyecto mayor (405 MB): con `memmem` sobre bloques de 4 MB pasados a minúsculas ASCII, **0,8–1,0 s** en frío; todo `~/.claude` (904 MB), 2,0 s. Un índice en memoria costaría memoria en reposo y un índice en disco duplicaría los transcripts: se descartan.
- **Cómo:** el adaptador busca la parte ASCII más larga de la consulta (plegada a minúsculas) en los bytes crudos; solo las líneas que la contienen se decodifican, y el dominio confirma la coincidencia sobre el texto visible (sin distinguir mayúsculas ni tildes, `TimelineMatch`). Si la consulta no tiene una parte ASCII de 3 caracteres, se decodifican todas las líneas `user`/`assistant` (más lento, mismo resultado).
- **Orden y streaming:** sesiones de la más reciente a la más antigua; los resultados aparecen por sesión según se encuentran. **Objetivo:** primeros resultados < 300 ms y búsqueda completa < 1,5 s en el proyecto mayor (C5, medido al cierre). Máximo 200 coincidencias (lo dice el resumen).
- **Cancelación:** cada tecla cancela la búsqueda anterior (`Task` cancelado, comprobado entre bloques de 4 MB) y lanza otra tras 150 ms sin teclear. Cerrar el panel la cancela.

### 5. Copiar y saltar

- **⌘C** copia íntegro el elemento elegido: el prompt, la respuesta, la **salida** de una herramienta (o su llamada si aún no tiene salida). **⇧⌘C** copia la **llamada** (los argumentos en el JSON del transcript). En la búsqueda, ⌘C copia el elemento de la coincidencia. Lo copiado sale de releer la línea del transcript, no de lo pintado. El pie dice «Copiado · 18,4 KB» 4 s.
- Una imagen no se copia como imagen: ⌘C sobre ella copia su descripción («Imagen adjunta · image/png · 182 KB»); pintarla queda fuera.
- **Saltar a un turno:** ↵ en un resultado abre esa sesión en el timeline con el elemento elegido y visible. Si es la sesión del panel enfocado, solo se mueve la selección.
- **En el terminal no hay salto:** Claude Code y Codex usan la pantalla alternativa, que no tiene historial; desplazar el scrollback del panel enseñaría lo que había antes de abrir el agente. El timeline es el sitio donde se ve el pasado.

### 6. Punto único para F11 (secretos)

Todo texto de transcript pasa por un único tipo del dominio antes de pintarse, copiarse o buscarse: el puerto `TranscriptTextPolicy` (`func shown(_ text: String, as context: TranscriptTextContext) -> String`, con contexto `.display`, `.copy`, `.searchSnippet`). F9 trae una sola implementación, `VerbatimText`, que devuelve el texto tal cual, y una prueba de guarda (dominio) que comprueba que `TimelineView` y la copia no reciben texto que no pasó por ella (los modelos de fila solo se construyen desde `TimelineRows`, que la aplica). F11 añade su implementación sin tocar la vista. **No se enmascara nada en F9.**

### 7. Atajo y convivencia

- **⇧⌘T** (libre en `Keymap`; ⌘T solo lo usa la vista de procesos mientras está abierta). Sin ⌥.
- Con el timeline abierto: ↑↓ elegir, → desplegar, ← plegar (o subir al padre), ⌘C/⇧⌘C copiar, ⌘F buscar (en lugar de la búsqueda del terminal), ⇧⌘T vuelve a «Sesión» desde la búsqueda, esc vuelve de la búsqueda o cierra. Escribir en «Sesión» abre la búsqueda con lo escrito.
- **No se apilan:** el timeline, el Observatorio (⇧⌘A) y procesos/puertos (⇧⌘M, ⇧⌘U) son excluyentes; abrir uno cierra el otro. ⌘K, la ayuda y la tarjeta de aprobación de F7.5 sí quedan por encima.
- El timeline es un panel a la derecha **sobre** los paneles (480 pt, sin redimensionar los terminales: redimensionarlos haría que Claude Code redibuje y Codex corte líneas). El panel enfocado conserva su anillo.

## Decisiones de diseño

| Decisión | Elegido | Descartado |
| --- | --- | --- |
| Dónde | Panel lateral sobre los paneles, 480 pt, a la derecha | Superposición completa (tapa el terminal que se está mirando); redimensionar los paneles (reflujo en Claude/Codex) |
| Seguir lo nuevo | `DispatchSource` sobre el archivo abierto, solo con el panel abierto | Refrescar con hooks (Codex no tiene; `Stop` llega antes de la última línea); sondeo |
| Memoria | Texto recortado + ubicación; el íntegro se relee del disco | Todo el texto en memoria (60 MB de sesión → cientos de MB de `String`) |
| Búsqueda | Bajo demanda con `memmem`, cancelable, por sesión | Índice en memoria (coste en reposo) o en disco (duplica los transcripts) |
| Alcance de búsqueda | La raíz del proyecto (regla de F8.5) y sus subcarpetas | Solo la carpeta del panel (pierde los paneles de subcarpetas); toda la máquina (lento, ruido) |
| Harnesses | Claude Code y Codex | Antigravity (protobuf sin esquema) y OpenCode (cabe después, OCP) |
| Codex `.zst` | Listado con nota, no se abre | Enlazar zstd (dependencia nueva para sesiones de más de una semana) |
| Sin ID | Respaldo con aviso: la más reciente de la carpeta | Nada (inútil) o adivinar sin decirlo |
| Secretos | Punto único `TranscriptTextPolicy`, identidad en F9 | Enmascarar ya (F11) |
| Copiar | ⌘C salida/texto, ⇧⌘C llamada | Un solo ⌘C ambiguo para las herramientas |

## Alcance

1. **Paquete compartido `JSONLReader`** (SPM nuevo, como `SQLiteReader`): el lector incremental de F3 (movido, con sus pruebas), lectura de una línea por (offset, longitud), escáner `memmem` cancelable por bloques y un observador de archivo (`DispatchSource`) que se cancela al soltarlo. `ClaudeTelemetryAdapter` pasa a usarlo sin cambiar su comportamiento.
2. **Dominio** (`SmaltiCore`, Swift puro):
   - Tipos: `TranscriptEntry` (lo que traduce el adaptador: `prompt`, `reply`, `toolCall`, `toolResult`, `image`, `compaction`, `subagent(start)`), `TextLocation` (archivo, offset, longitud, bloque), `ExcerptText` (recorte + ubicación + tamaño íntegro), `TranscriptSessionRef` (harness, id, archivo), `TranscriptRead` (entradas nuevas + cursor).
   - `Timeline`: pliega entradas en turnos (un turno empieza en un prompt), empareja llamadas y resultados por id (sin resultado = «trabajando»; resultado sin llamada se conserva al final del turno), anida los subagentes bajo su llamada, pone las compactaciones como divisores y es incremental (`appending(_:)` con entradas nuevas da lo mismo que leer de una vez).
   - `ToolSummary`: nombre + argumentos resumidos por herramienta conocida (`Bash`/`exec_command` → comando; `Read`/`Edit`/`Write` → ruta relativa a la raíz y `+n −m` si hay diff; `Grep`/`Glob` → patrón y ruta; `Agent`/`Task` → descripción; otras → primer argumento de texto) y estado (`trabajando`, `listo`, `error · exit N`).
   - `TimelineRows` + `TimelineSelection`: las filas visibles con lo desplegado, ↑↓/→/← (← en un hijo sube al padre), selección estable al llegar entradas nuevas (si estaba en la última, la sigue).
   - `TimelineTarget`: la regla panel ↔ sesión de arriba.
   - `TimelineSearch`: consulta plegada, confirmación sobre el texto visible, fragmento con la coincidencia, agrupado por sesión, tope de 200.
   - `TranscriptTextPolicy` + `VerbatimText`.
   - Casos de uso `ShowTimeline` (abre, lee, sigue, cambia de panel, suelta todo al cerrar), `CopyTimelineItem` y `SearchTranscripts`.
   - Puertos de salida: `SessionTranscripts` (`read(_ session:, from cursor:)`, `fullText(at:)`, `changes(of:) -> AsyncStream<Void>`, `recentSessions(in root:)`) y `TranscriptSearch` (`search(_ query:, in root:) -> AsyncThrowingStream<TranscriptHit, Error>`), con un registro por harness (`TranscriptSources`, como `HarnessRegistry`). Errores tipados `TranscriptReadError` (`missing`, `unreadable`, `compressed`).
   - Textos en `Domain/Texts/TimelineTexts.swift` (`.spanish` y `.english`).
   - Comandos: `timeline.toggle` (⇧⌘T), `timeline.search` (⌘F con el timeline abierto; en ⌘K abre el timeline en la búsqueda), `timeline.copy` (⌘C), `timeline.copyCall` (⇧⌘C); en ⌘K, la ayuda y el menú «Ver».
3. **Adaptadores:** `ClaudeTimeline` en `ClaudeHarnessAdapter` y `CodexTimeline` en `CodexHarnessAdapter`, los dos sobre `JSONLReader`, con una prueba de contrato compartida (`SessionTranscripts` y `TranscriptSearch`) sobre fixtures reales.
4. **App:** `TimelineController` + `TimelineView` (panel lateral, cabecera, sesión, lista virtualizada, búsqueda, vacío, respaldo, aviso, pie de teclas); `KeyRouter` con el contexto del timeline; exclusión con el Observatorio y procesos; `AppComposition` conecta los adaptadores con el `CODEX_HOME` y el `claudeHome` que ya usa (en pruebas, `-SmaltiClaudeHome` y `-SmaltiCodexHome` temporales).
5. **Textos de vistas** en `Localizable.xcstrings` (inglés y español).
6. **Oráculo** `scripts/timeline/timeline_oracle.py` (Python, independiente del Swift, con sus pruebas): para cada transcript, la lista de elementos (tipo y texto íntegro) que debe dar el timeline.
7. **Web** (`smalti-web`, a la par): página del timeline en inglés y español con capturas, atajos nuevos, «Lo que viene» sin F9 y con F10 (Revisión con Neovim) como siguiente; changelog.
8. **Cierre:** mediciones, capturas, checklist, 0.9.0, PRs, release por el pipeline, actualización del Smalti diario por Sparkle.

## La vista

Panel a la derecha del área de paneles (10 pt de margen arriba, abajo y a la derecha; 480 pt de ancho), radio 12, fondo `rgba(15,17,23,0.90)` sobre el vidrio, borde `rgba(255,255,255,0.09)`, sombra hacia la izquierda. Tokens del tema en vigor. Ver la maqueta.

- **Cabecera (40 pt):** «Timeline» en título; chips «Sesión ⇧⌘T» y «Buscar ⌘F» (el activo con el anillo y el brillo del acento); `esc`.
- **Sesión:** punto de estado del agente (el código de toda la app), «<harness> · <workspace> · <n>», el título (primer prompt) en una línea, y «<n> turnos · <m> herramientas · desde <hora>» en mono secundario.
- **Elementos:**
  - Prompt: etiqueta «TÚ» y hora; texto en título con filo izquierdo del acento al 55 %; hasta 3 líneas plegado.
  - Respuesta: etiqueta «CLAUDE»/«CODEX» y hora; hasta 4 líneas plegada; código en línea en mono.
  - Herramienta (24 pt): ▸/▾, nombre en mono cian, argumentos resumidos en mono secundario, estado a la derecha (✓ verde «listo», punto verde «trabajando», punto rojo «error · exit N»). Desplegada: bloque mono «SALIDA» (o «LLAMADA» si no hay salida) hasta 12 líneas y «… N líneas más · ⌘C copia la salida íntegra».
  - Subagente: la llamada `Agent` con «N herramientas»; desplegada, sus herramientas y respuestas sangradas 18 pt con una guía.
  - Imagen: «Imagen adjunta · <nombre o tipo>» con un icono, en secundario.
  - Compactación: divisor «Conversación compactada · 168k → 22k tokens» (sin tokens en Codex: «Conversación compactada»).
  - Elegido: brillo y filo de 2 pt del acento.
- **Búsqueda:** campo con lupa y el anillo del acento; debajo «Proyecto · <nombre>» + la raíz en mono + «N coincidencias en M sesiones» (o «Buscando… k de n sesiones»). Resultados agrupados por sesión: título, «<harness> · este panel|abierta en <ws · n>|cerrada · <cuándo>» y el número; cada coincidencia con quién (TÚ, CLAUDE, CODEX o el nombre de la herramienta), hora y dos líneas con la coincidencia resaltada (acento al 28 %). Sin resultados: «Nada coincide con «<consulta>» en este proyecto».
- **Vacío y respaldo:** círculo hueco, título, explicación y «Sesiones recientes · <proyecto>» (hasta 6, con su punto de estado: verde si está viva en un panel). Sin sesiones: «Aún no hay sesiones de Claude Code ni de Codex en este proyecto».
- **Sin identificar:** aviso con punto ámbar arriba de la sesión (texto de la maqueta).
- **Pie (30 pt):** según la vista: «↑↓ elegir · → ← desplegar · ⌘C copiar íntegro · esc cerrar»; búsqueda «↑↓ elegir · ↵ saltar al turno · ⌘C copiar íntegro · esc volver»; vacío «↑↓ elegir · ↵ abrir · ⌘F buscar · esc cerrar». Avisos a la derecha 4 s («Copiado · 18,4 KB», «412 MB leídos en 0,8 s», errores de lectura en el rojo de error).
- **Movimiento:** fundido y desplazamiento de 8 pt en 150 ms al abrir y cerrar; sin animación con «Reducir movimiento». Desplegar no se anima.
- **Accesibilidad:** grupo `smalti.timeline`, lista `smalti.timeline.list` (filas `smalti.timeline.item.<n>`), búsqueda `smalti.timeline.search` (campo `smalti.timeline.search.field`, resultados `smalti.timeline.hit.<n>`), aviso `smalti.timeline.notice`, vacío `smalti.timeline.empty`. VoiceOver lee quién, la hora, el texto recortado y el estado de la herramienta.

### Textos en inglés (glosario)

| Español | Inglés |
| --- | --- |
| Timeline · Sesión · Buscar | Timeline · Session · Search |
| Tú · Claude · Codex | You · Claude · Codex |
| turnos · herramientas · desde | turns · tools · since |
| listo · trabajando · error | done · working · error |
| Salida · Llamada | Output · Call |
| … N líneas más · ⌘C copia la salida íntegra | … N more lines · ⌘C copies the whole output |
| Conversación compactada | Conversation compacted |
| Imagen adjunta | Attached image |
| copiar íntegro · desplegar · saltar al turno · volver | copy whole · expand · jump to turn · back |
| Copiado | Copied |
| Proyecto · coincidencias · sesiones · Buscando… | Project · matches · sessions · Searching… |
| este panel · abierta en · cerrada | this pane · open in · closed |
| Este panel no tiene un agente | This pane has no agent |
| Sesiones recientes | Recent sessions |
| … no deja un transcript que Smalti sepa leer | … leaves no transcript Smalti can read |
| sin identificar | unidentified |
| comprimida por Codex | compressed by Codex |

## Fuera de alcance

- F10 en adelante. Enmascarar secretos (F11): solo el punto de enganche.
- Editar, reenviar o reanudar desde un turno (reanudar ya está en F6); exportar el timeline.
- Pintar imágenes, el razonamiento (`thinking`, `reasoning`) y los mensajes de sistema o de contexto inyectados.
- Antigravity, OpenCode y los rollouts `.zst` de Codex.
- Buscar fuera del proyecto o con expresiones regulares.

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
| --- | --- | --- |
| C1 | Cada turno y cada resultado de herramienta de los fixtures reales aparece y se copia íntegro | Prueba de contrato de los adaptadores + dominio sobre los fixtures reales de F3 (`ClaudeTelemetryAdapter/…/real`, con el subagente) y de F6 (`ClaudeHarnessAdapter/…/claude`, `CodexHarnessAdapter/…/codex` y `…/codex-timeline`): la secuencia de elementos (tipo, quién) es igual a la del oráculo `timeline_oracle.py`, y el `fullText` de cada uno es igual **byte a byte** a su texto en el oráculo. Más los sintéticos de compactación (`tools-and-compaction.jsonl`) e imagen (nuevo) |
| C2 | El timeline es el de la sesión del panel y cambia con el panel | Dominio: `TimelineTarget` (hooks gana, binding, respaldo, harness sin transcript, shell). XCUITest `TimelineTests`: dos paneles con sesiones de fixture distintas (vía `-SmaltiClaudeHome` y el binding de un panel restaurado), ⇧⌘T muestra la del enfocado; ⌘2 cambia a la otra; un panel sin agente muestra el vacío |
| C3 | Plegar, desplegar y copiar con teclado | `TimelineTests`: → despliega una herramienta y enseña su salida, ← la pliega, ⌘C copia su salida íntegra (el portapapeles igual al del oráculo), ⇧⌘C la llamada; un prompt de más de 2.000 caracteres se copia entero |
| C4 | La búsqueda encuentra una sesión cerrada y salta al turno | Dominio y contrato (`TranscriptSearch` sobre los fixtures). `TimelineTests`: ⌘F, una palabra de una sesión cerrada del proyecto, ↵ abre esa sesión con el elemento elegido |
| C5 | Latencia de la búsqueda | Al cierre, sobre el `~/.claude` real en solo lectura (`scripts/measure-timeline.sh`): primeros resultados < 300 ms y búsqueda completa < 1,5 s en el proyecto mayor (p50 de 5) |
| C6 | Lo nuevo llega solo, sin coste en reposo | Adaptador: el observador avisa al añadir una línea y se cancela al soltarlo (sin descriptores abiertos). Dominio: `ShowTimeline` cerrado no tiene lectura ni observador vivos. Al cierre, GPU y CPU en reposo de Smalti Dev con el timeline cerrado (`measure-gpu-idle.sh 5`) sin empeorar respecto de F8.5, medidas el mismo día en un worktree de `origin/develop` |
| C7 | Abrir una sesión grande no congela | Al cierre, sobre el transcript mayor real (solo lectura): `read` completo < 0,6 s fuera del hilo principal, y la app responde a ⇧⌘T mientras lee (XCUITest con un transcript sintético de 60 MB generado por la prueba) |
| C8 | Memoria acotada | Al cierre: huella de Smalti Dev con la sesión de 60 MB abierta < 150 MB por encima de la de reposo; al cerrar el panel vuelve a ±10 MB |
| C9 | Inglés y español completos | `LocalizationTests` recorre el timeline (sesión, búsqueda, vacío y respaldo) en inglés; `TimelineTexts` en `TextCatalogAuditTests`; `strings-catalog.test.sh` |
| C10 | Todo con atajo y en ⌘K | Dominio: los cuatro comandos en `CommandCatalog`, `HelpCatalog` y `MenuModel`; ninguno con ⌥ solo; ⌘C, ⇧⌘C y ⌘F siguen siendo del terminal con el timeline cerrado; el timeline, el Observatorio y procesos son excluyentes |
| C11 | Arquitectura y solo lectura | Guarda de imports de `SmaltiCore`; solo `JSONLReader` y los dos adaptadores abren transcripts, siempre en lectura (prueba de guarda: ningún `forWritingTo`/`.write` en esos archivos); `network-surface.test.sh` sin cambios; todo texto pasa por `TranscriptTextPolicy` |
| C12 | Release y actualización real | 0.9.0 por el pipeline (DMG, appcast, cask); el Smalti diario 0.8.5 se actualiza solo por Sparkle desde smalti.sh, sin aviso de Gatekeeper y con la sesión intacta |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| Formato sin documentar de Claude Code o de Codex | Turnos que faltan tras una actualización | Contrato sobre fixtures reales con su `VERSION`; tipos de línea desconocidos se ignoran y se cuentan (como F3); el oráculo independiente |
| Clasificación distinta entre oráculo y Swift | C1 en verde por error | El oráculo se escribe desde esta spec, no desde el código, con sus propias pruebas (`test_timeline_oracle.py`) |
| Sesión enorme | Congelar o comer memoria | Lectura fuera del hilo principal, recorte + ubicación, `NSTableView` (C7, C8) |
| El archivo cambia mientras se copia (Claude reescribe al compactar) | Copiar otra cosa | La ubicación lleva el inodo y el tamaño leído; si el archivo se encogió o cambió de inodo, se relee la sesión y la copia se rehace desde la nueva lectura |
| ⌘C del terminal | Romperlo | Solo es del timeline con el panel lateral enfocado y abierto (C10) |
| Búsqueda en proyectos grandes | Esperas | Streaming por sesión, cancelación por tecla, tope de 200 (C5) |
| Pruebas que tocan datos reales | Leer los transcripts de Simón | `-SmaltiClaudeHome`/`-SmaltiCodexHome` temporales con copias de los fixtures; las mediciones sobre lo real, solo en lectura y con su script |

## Plan de pruebas y revisiones

Según `.claude/rules/`:

- **Revisiones:** intermedia 1 al terminar `JSONLReader`, dominio y adaptadores; intermedia 2 al terminar la app, la web y los documentos; final acotada a lo que cruza bloques, a las tandas de correcciones y al cumplimiento de la spec.
- **Mutación:** una por revisión intermedia con `--changed-since`; cada sobreviviente se mata con una prueba verificada aplicando el mutante a mano. Al cierre, solo los archivos de SmaltiCore de la fase (≥ 80 %).
- **XCUITest:** una sola corrida de `scripts/test-ui.sh` por tanda, solo lo afectado (`TimelineTests`, `LocalizationTests` y las clases tocadas), nunca dos a la vez, siempre bajo `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID` sacado de `ps -axo pid=,command=`; shells con `-SmaltiShellCommand "/bin/zsh -f"`. Los transcripts los crea el shell del panel (el runner está en sandbox y no escribe en `/tmp`) o vienen como copia de fixtures en un `-SmaltiClaudeHome` temporal.
- **Capturas** al cierre, solo con fixtures saneados y proyectos neutrales: sesión, búsqueda, vacío y respaldo en inglés y en español, junto a la maqueta.
- **Mediciones** al cierre (C5–C8).

## Cambios en otros documentos (con esta spec)

- `docs/ROADMAP.md`, F9: la spec y el criterio de cierre concretado.
- `docs/design/README.md`: sección «Timeline (F9)» que apunta a la maqueta.
- `CLAUDE.md`: los puertos nuevos, `JSONLReader` en «Comandos» y en `swift format`, el oráculo y `measure-timeline.sh`.

## Enmiendas

Durante la ejecución (2026-11-26), con su porqué:

1. **El prefiltro de búsqueda pliega tildes en los bytes.** Un prefiltro solo ASCII no encuentra «migración» buscando «migracion» (ni al revés). El escáner pliega a minúsculas ASCII, Latin-1 (`0xC3 xx`) y Latin Extended-A (`0xC4`/`0xC5 xx`) a su letra base y omite las marcas combinantes (texto en NFD); la aguja es la consulta plegada entera (el trozo más largo sin `"` ni `\`, de 3 caracteres o más). La confirmación del dominio usa la comparación de Foundation sin mayúsculas ni tildes, fuera del hilo principal, y cada coincidencia guarda solo su fragmento (revisión 1).
2. **Sin progreso «k de n sesiones».** El puerto busca por harness; el resumen dice «Buscando…» y los grupos se ordenan por fecha de la sesión al llegar, de cualquier harness (revisión 1).
3. **El resumen de herramientas es el del Observatorio** (`ToolSummary`, ampliado con `exec_command`, `shell`, `apply_patch`, `Agent` y `Task`): muestra el nombre del archivo, no la ruta relativa a la raíz.
4. **Copiar una imagen o una compactación las describe** sin ir al disco («Imagen adjunta · image/png · 186 KB», «Conversación compactada · 168k → 22k tokens»), igual en los dos harnesses; ⇧⌘C sobre algo sin llamada no copia nada (revisión 1).
5. **La llamada de Claude se copia como JSON canónico** (compacto, claves por punto de código, sin escapar lo no ASCII), el mismo que escribe el oráculo: Foundation no conserva el orden de claves del archivo y su `.sortedKeys` ordena de otra forma (revisión 1).
6. **Los observadores siguen la ruta**, no el inodo: cuando Claude reescribe el transcript con un `rename`, `FileWatch` vuelve a vigilar el archivo nuevo; la carpeta de subagentes y cada subagente se vigilan también si nacen con el timeline abierto (revisión 1).
7. **Solo `Agent` y `Task` anidan subagentes**: un «agentId:» en la salida de otra herramienta no enlaza nada (revisión 1).
8. **Codex: el rollout bajo el propio `CODEX_HOME`.** Si el índice guarda una ruta de otro home (copiado o movido), se usa la misma ruta bajo `<home>/sessions`.
9. **El contrato compartido vive en `SmaltiCoreTestSupport`** (`TranscriptsContract` y `TimelineOracle`, como el de F6) en lugar de dos archivos iguales.
10. **Fixture de las UI tests compuesto por script** (`scripts/timeline/compose-ui-fixture.py`): los transcripts saneados de F6, el sintético y una sesión con un prompt de 3.000 caracteres, con `{{root}}` en lugar de su directorio, y el home de Codex de F9 en base64.

# F9 · Timeline de la sesión — Plan de implementación

> **Para agentes:** ejecución nativa (`.claude/rules/workflow.md`): Claude implementa cada tarea en esta sesión, en bloques, con dos revisiones intermedias y una final acotada. Pasos con casillas (`- [ ]`).

**Objetivo:** panel lateral ⇧⌘T con los turnos del agente del panel enfocado (Claude Code y Codex), herramientas plegables, búsqueda en las sesiones del proyecto y copia íntegra, sin coste en reposo, publicado como 0.9.0.

**Arquitectura:** un paquete compartido `JSONLReader` lee JSONL por offset, relee una línea por ubicación, busca con `memmem` y observa un archivo; dos adaptadores (`ClaudeTimeline`, `CodexTimeline`) traducen líneas a `TranscriptEntry` del dominio; `SmaltiCore` pliega entradas en turnos, empareja, anida, resume, selecciona, decide panel ↔ sesión y confirma búsquedas; la app pinta un panel lateral y solo lee mientras está abierto.

**Stack:** Swift 6, AppKit, Swift Testing, XCUITest, `DispatchSource`, Python 3 (oráculo), Next.js (smalti-web).

**Spec:** `docs/specs/F9-timeline.md` (maqueta `docs/specs/F9-assets/mockup.html`).

## Restricciones globales

- `SmaltiCore` sin imports nuevos ni `Locale`/`Bundle` (plegado de tildes propio, por escalares Unicode).
- Transcripts **solo en lectura**: `FileHandle(forReadingFrom:)` y nada más; ninguna escritura en `~/.claude`, `~/.codex` ni en fixtures.
- Recorte de texto en memoria: 2.000 caracteres (`ExcerptText.limit`); el íntegro sale de `fullText(at:)`.
- Observador coalescido a 150 ms; búsqueda con espera de 150 ms tras teclear, bloques de 4 MB, tope de 200 coincidencias; ASCII mínimo de 3 caracteres para el prefiltro.
- Panel: 480 pt, margen 10 pt, radio 12; fundido 150 ms (sin él con «Reducir movimiento»).
- Atajos: ⇧⌘T (`timeline.toggle`), ⇧⌘C (`timeline.copyCall`, solo con el timeline abierto); ⌘C y ⌘F son del timeline solo con el timeline abierto (respondedor y `searchOpen` redirigido). Ninguno con ⌥.
- Textos: `TimelineTexts.spanish` / `.english`; vistas en `Localizable.xcstrings`.
- Todo texto de transcript pasa por `TranscriptTextPolicy` antes de pintarse, copiarse o mostrarse como fragmento.
- UI tests: `isolatedSmalti(language:)`, `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiClaudeHome`/`-SmaltiCodexHome` temporales con copias de fixtures, `check-daily-untouched.sh` con `SMALTI_DAILY_PID`, una corrida a la vez.
- `swift test --disable-keychain`; `xcodebuild … -packageAuthorizationProvider netrc`.

## Foco de revisión

1. Claude reescribe el transcript (compactación, `/clear` con la misma sesión): inodo distinto o archivo más corto → la lectura se rehace desde cero y la selección se conserva por id si sigue existiendo (T3, T6).
2. Línea a medias al final del archivo mientras Claude escribe: no se pierde ni se duplica al llegar el resto (T1).
3. Resultado de herramienta que llega en una lectura y su llamada en la anterior (o un subagente cuyo archivo aparece después que su llamada): el emparejado incremental da lo mismo que leer de una vez (T3).
4. Consulta con tildes, mayúsculas, solo no-ASCII («ñandú») o con comillas: encuentra lo que el texto visible contiene y no lo que solo está en claves o escapes JSON (T4, T6).
5. Cambiar de panel o cerrar durante una lectura o una búsqueda larga: se cancela, no pinta la sesión vieja y no deja observadores (T5, T8).

---

## Bloque 1 · Base y dominio

### Task 1: Paquete `JSONLReader`

**Files:**
- Create: `Packages/JSONLReader/{Package.swift,Sources/JSONLReader/{JSONLLineReader,JSONLLineAt,JSONLScanner,FileWatch}.swift,Tests/JSONLReaderTests/{LineReaderTests,LineAtTests,ScannerTests,FileWatchTests}.swift}` (`platforms: [.macOS("27.0")]`, como `SQLiteReader`)
- Modify: `Packages/ClaudeTelemetryAdapter/Package.swift` (depende de `../JSONLReader`), `ClaudeTranscripts.swift` (usa `JSONLLineReader`); borrar `TranscriptLineReader.swift` y mover sus pruebas.

**Interfaces (públicas):**
- `JSONLLineReader.read(_ file: URL, from offset: UInt64, line: (Data, _ lineOffset: UInt64) -> Void) -> JSONLReadOutcome` (`offset`, `failure: (any Error)?`). Igual que el de F3 más el offset de cada línea.
- `JSONLLineAt.line(in file: URL, at offset: UInt64, length: Int) throws(JSONLReadError) -> Data`; `JSONLFileIdentity.of(_ file: URL) -> (inode: UInt64, size: UInt64)?`.
- `JSONLScanner.lines(containing needle: [UInt8], in file: URL, isCancelled: () -> Bool, line: (Data, UInt64) -> Void) throws(JSONLReadError)`: bloques de 4 MB, comparación ASCII sin mayúsculas, entrega cada línea completa que contiene la aguja una sola vez; `isCancelled` se consulta entre bloques. Con `needle` vacío entrega todas las líneas.
- `FileWatch(file: URL, coalescing: Duration, onChange: @Sendable () -> Void)`: `DispatchSource` de vnode (`.write`, `.extend`, `.delete`, `.rename`) sobre un `open(O_EVTONLY)`; `cancel()` cierra el descriptor; `deinit` cancela.
- `JSONLReadError: .missing(path), .unreadable(path, reason)`.
- [ ] Pruebas rojas: las de F3 movidas (bloques, línea a medias, fallo a mitad); offset de cada línea; `line(at:)` devuelve los bytes exactos y falla con `.missing`; escáner: aguja partida entre dos bloques, `TiMeLiNe` encuentra `timeline`, una línea con dos apariciones se entrega una vez, cancelado tras el primer bloque no entrega más; `FileWatch` avisa una vez por ráfaga de tres escrituras en 150 ms y, tras `cancel()`, ningún descriptor queda abierto (`lsof -p` del proceso de prueba sin el archivo, o contando `/dev/fd`).
- [ ] Implementar; `swift test --disable-keychain --package-path Packages/JSONLReader` y `…/ClaudeTelemetryAdapter` en verde (F3 sin cambios de comportamiento). Commit `feat(jsonl): shared incremental JSONL reader, scanner and file watch`.

### Task 2: Oráculo y fixture de imagen

**Files:**
- Create: `scripts/timeline/timeline_oracle.py`, `scripts/timeline/test_timeline_oracle.py`
- Create: `Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/timeline-synthetic/{image.jsonl,expected-image.json}` (sintético: un prompt con texto + bloque `image` PNG de 1×1 en base64, un `tool_result` con un bloque `image`, `isMeta`, `isCompactSummary` y un comando `<command-name>/clear</command-name>`)

**Interfaces:** `timeline_oracle.py <claude|codex> <transcript> [--subagents <dir>]` imprime JSON `{"items": [{"kind": "prompt|reply|call|output|image|compaction", "who": "user|agent|<tool>", "scope": "main|<agentId>", "text": "<íntegro>"}]}` según las reglas de la sección 1 de la spec (escrito desde la spec, no desde el Swift): `call` = el `input`/`arguments` del transcript serializado tal cual (Claude: `json.dumps(input, ensure_ascii=False, separators=(",", ":"))` en el orden del archivo; Codex: la cadena `arguments` o `input` sin tocar); `output` = la cadena, o los bloques `text` unidos con `"\n"`; imagen = `"<media_type> · <bytes decodificados>"`.
- [ ] Pruebas rojas (`python3 -m unittest test_timeline_oracle`): sobre el fixture de Claude de F6 work-b la secuencia `prompt, call(Bash), output(exit 127), call, output, reply, prompt, call(Read), output, reply, prompt, reply`; Codex `codex-timeline`: dos prompts, dos `exec_command`, la salida con `Process exited with code 1`, sin `<environment_context>` ni `developer`; `isMeta` fuera; subagente de F3 con `scope` = su id.
- [ ] Implementar. Commit `test(timeline): independent transcript oracle and synthetic image fixture`.

### Task 3: Entradas y pliegue en turnos

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Timeline/{TranscriptEntry,TextLocation,ExcerptText,Timeline,TimelineItem,ToolSummary}.swift`
- Test: `Tests/SmaltiCoreTests/Timeline/{TimelineTests,ToolSummaryTests,TimelineFixtures.swift}`

**Interfaces:**
- `TextLocation { file: String; inode: UInt64; offset: UInt64; length: Int; block: Int; field: TextField }` (Hashable); `TextField: .text, .toolInput, .toolOutput, .image`.
- `ExcerptText { excerpt: String; byteCount: Int; lineCount: Int; location: TextLocation; isTruncated: Bool }`; `static let limit = 2_000`; `ExcerptText.make(full: String, location:)`.
- `TranscriptEntry` (enum) con `scope: EntryScope (.main, .subagent(String))` y `at: Date?`: `.prompt(ExcerptText)`, `.reply(ExcerptText)`, `.toolCall(id: String, name: String, arguments: [String: String], call: ExcerptText)`, `.toolResult(id: String, isError: Bool, exitCode: Int?, output: ExcerptText)`, `.image(ImageNote { mediaType: String; byteCount: Int; location })`, `.compaction(preTokens: Int?, postTokens: Int?)`, `.subagentLink(agentID: String, toolID: String)`.
- `TimelineItemID` (Hashable, `String`): llamada → su id; prompt/respuesta/imagen → `"\(file)#\(offset).\(block)"`; compactación → igual con su línea.
- `TimelineItem` (indirect enum): `.prompt(PromptItem)`, `.reply(ReplyItem)`, `.tool(ToolItem { id; name; summary: String; call: ExcerptText; result: ToolResultNote?; children: [TimelineItem] })`, `.image(ImageNote)`, `.compaction(CompactionNote)`; `ToolItem.status: ToolStatus (.working, .done, .failed(exitCode: Int?))`.
- `Timeline` (valor): `turns: [TimelineTurn { items: [TimelineItem] }]`, `appending(_ entries: [TranscriptEntry]) -> Timeline` (incremental: guarda llamadas pendientes y resultados huérfanos por id, y enlaces de subagente pendientes), `toolCount`, `turnCount`, `startedAt`, `item(_ id) -> TimelineItem?`.
- `ToolSummary.summary(name:, arguments:, root: String?) -> String` con las reglas de la spec (`Bash`/`exec_command`/`shell` → comando; `Read`/`Edit`/`Write`/`MultiEdit`/`NotebookEdit` → ruta relativa a `root`; `Grep`/`Glob` → patrón + ruta; `Agent`/`Task` → `description`; `apply_patch` → primera ruta del parche; otras → primer valor de texto). Una línea, espacios colapsados.
- [ ] Pruebas rojas: turno = prompt + lo que sigue; respuestas antes del primer prompt van a un turno sin prompt; llamada sin resultado `.working`; resultado `is_error` con `exitCode 127` → `.failed(127)`; resultado sin llamada al final de su turno; subagente: entradas con `scope .subagent("a8")` anidadas bajo la llamada enlazada por `.subagentLink`, también si el enlace llega después que las entradas; compactación como elemento; **incremental**: para cada corte posible de la lista de entradas del fixture de F6 work-b (en `TimelineFixtures`), `appending(a).appending(b) == appending(a+b)`; 0 entradas → 0 turnos; resúmenes de cada herramienta y una desconocida.
- [ ] Implementar. Commit `feat(core): timeline entries folded into turns with paired tools and subagents`.

### Task 4: Filas, selección, panel ↔ sesión, búsqueda y política de texto

**Files:**
- Create: `Domain/Timeline/{TimelineRows,TimelineSelection,TimelineTarget,TimelineQuery,TimelineMatch,TranscriptTextPolicy}.swift`, `Domain/Texts/TimelineTexts.swift`
- Modify: `Tests/SmaltiCoreTests/Texts/TextCatalogAuditTests.swift` (añadir `TimelineTexts`)
- Test: `Tests/SmaltiCoreTests/Timeline/{TimelineRowsTests,TimelineSelectionTests,TimelineTargetTests,TimelineMatchTests,TimelineTextsTests}.swift`

**Interfaces:**
- `TimelineRow { id: TimelineItemID; depth: Int; kind: RowKind; who: String; time: String?; text: String (ya pasado por la política); summary: String?; status: ToolStatus?; isExpanded: Bool; expandedText: String? (salida o llamada recortada a 12 líneas); moreLines: Int }`.
- `TimelineRows.rows(_ timeline: Timeline, expanded: Set<TimelineItemID>, policy: any TranscriptTextPolicy, texts: TimelineTexts, clock: TimeFormatting) -> [TimelineRow]`. **Único constructor de filas.**
- `TimelineSelection` (valor): `selected: TimelineItemID?`, `followsTail: Bool`; `moved(_ direction: .up/.down, in rows:)`, `expanding(in:) -> (TimelineSelection, Set<TimelineItemID>)` (→), `collapsing(in:)` (← pliega; en un hijo plegado sube al padre), `updated(for newRows:)` (si seguía la cola y llegan filas, elige la última; si el elegido desapareció, el más cercano anterior).
- `TimelineTarget.resolve(pane: Pane, transcripts: Set<HarnessID>) -> TimelineTarget.Resolution`: `.session(harness, sessionID)`, `.unidentified(harness, directory)`, `.unreadable(harness)`, `.noAgent`. Reglas 1–5 de la spec.
- `TimelineQuery(_ raw: String)`: `folded` (minúsculas + sin marcas combinantes), `asciiNeedle: [UInt8]` (racha ASCII alfanumérica/espacio más larga del plegado, vacía si < 3), `isEmpty`.
- `TimelineMatch.find(_ query:, in text: String) -> Range<String.Index>?` (sobre el texto original, plegado carácter a carácter); `snippet(text, around: Range, width: 120) -> (String, Range)`.
- `SearchResults` (valor): `adding(_ hit: TranscriptHit, query:) -> SearchResults` (confirma con `TimelineMatch`; descarta si no coincide; tope 200; agrupa por sesión en orden de llegada), `groups`, `matchCount`, `isCapped`.
- `protocol TranscriptTextPolicy: Sendable { func shown(_ text: String, as context: TranscriptTextContext) -> String }`; `TranscriptTextContext: .display, .copy, .searchSnippet`; `struct VerbatimText: TranscriptTextPolicy`.
- `TimelineTexts` con los textos de la spec y la maqueta (glosario incluido), plantillas `{count}`, `{harness}`, `{workspace}`, `{number}`, `{query}`, `{size}`.
- [ ] Pruebas rojas: filas con un prompt de 3.000 caracteres (texto recortado, `copy` íntegro aparte); salida de 30 líneas desplegada → 12 + `moreLines 18`; política espía: cada `text`/`expandedText` de fila pasó por ella con `.display` (guarda de C11); ↑↓ en los bordes; → en un prompt no hace nada; ← en un hijo sube al padre; seguir la cola; elegido borrado; las cinco resoluciones de `TimelineTarget` y la precedencia de hooks sobre binding; plegado `"Ñandú Áéí"` → `"nandu aei"`; `asciiNeedle` de `"reembolso parcial"`, de `"ñandú"` (vacía) y de `"a b"` (vacía); coincidencia `"PARCIAL"` en `"reembolso parcial"`; no coincide en `{"type":"reembolso"}` si el texto visible no lo tiene; tope 200; textos completos en los dos idiomas (auditoría).
- [ ] Implementar. Commit `feat(core): timeline rows, selection, pane target, search matching and text policy`.

### Task 5: Puertos, fakes, casos de uso y comandos

**Files:**
- Create: `Application/{TimelinePorts,ShowTimeline,CopyTimelineItem,SearchTranscripts}.swift`, `Sources/SmaltiCoreTestSupport/TimelineFakes.swift`
- Modify: `Domain/Config/{CommandID,Keymap,KeyRouting}.swift`, `Domain/Texts/{CommandTexts,HelpTexts,MenuTexts}.swift`, `Domain/Help/HelpCatalog.swift`, `Domain/Commands/{CommandCatalog,MenuModel}.swift`
- Test: `Tests/SmaltiCoreTests/Timeline/{ShowTimelineTests,CopyTimelineItemTests,SearchTranscriptsTests,TimelineCommandsTests}.swift`

**Interfaces:**
- `TranscriptSessionRef { harness: HarnessID; sessionID: String; file: String; subagentFolder: String? }`; `TranscriptCursor` (valor opaco: offsets e inodos por archivo; `.start`); `TranscriptRead { entries: [TranscriptEntry]; cursor: TranscriptCursor; restarted: Bool }`.
- `TranscriptReadError: .missing(path), .unreadable(path, reason), .compressed(path)`.
- `protocol SessionTranscripts: Sendable { var harness: HarnessID { get }; func locate(sessionID: String) async throws(TranscriptReadError) -> TranscriptSessionRef; func read(_: TranscriptSessionRef, from: TranscriptCursor) async throws(TranscriptReadError) -> TranscriptRead; func fullText(at: TextLocation) async throws(TranscriptReadError) -> String; func changes(of: TranscriptSessionRef) -> AsyncStream<Void> }` (el stream termina y suelta el observador cuando se cancela su consumidor).
- `protocol ProjectTranscripts: Sendable { var harness: HarnessID { get }; func sessions(under root: String, limit: Int) async throws(TranscriptReadError) -> [HarnessSession]; func search(_ query: TimelineQuery, under root: String) -> AsyncThrowingStream<TranscriptHit, any Error> }`; `TranscriptHit { session: HarnessSession; entry: TranscriptEntry; text: String (íntegro del campo buscado) }`.
- `TranscriptSources([any SessionTranscripts], [any ProjectTranscripts])`: por harness, como `HarnessRegistry`.
- `@MainActor final class ShowTimeline(sources:, policy:, texts:)`: `show(_ resolution: TimelineTarget.Resolution, root: String) async` (cancela lo anterior; lee; si `.unidentified`, `sessions(under: directory, limit: 1)` de ese harness; abre `changes` y relee al avisar), `close()` (cancela tareas y observadores, suelta el `Timeline`), `state: TimelineState (.closed, .loading, .session(SessionView), .empty(recent: [HarnessSession]), .unreadable(HarnessID, recent:), .failed(TranscriptReadError))`, `onChange: (() -> Void)?`, `isWatching: Bool` (para C6).
- `CopyTimelineItem(sources:, policy:)`: `copy(_ id: TimelineItemID, in: Timeline, part: CopyPart (.content, .call)) async throws(TranscriptReadError) -> CopiedText { text: String; byteCount: Int }` (`.content`: prompt/respuesta → su texto; herramienta → salida, o la llamada si no hay; imagen → su descripción; siempre `fullText(at:)` + política `.copy`).
- `@MainActor final class SearchTranscripts(sources:, debounce: Duration = .milliseconds(150), sleep: @Sendable (Duration) async throws -> Void)`: `update(query: String, root: String)`, `cancel()`, `results: SearchResults`, `progress: (done: Int, total: Int)?`, `onChange`.
- Comandos: `CommandID.timelineToggle` (`"timeline.toggle"`, ⇧⌘T), `.timelineSearch` (`"timeline.search"`, sin acorde propio: ⌘K lo abre en la búsqueda; con el timeline abierto ⌘F lo hace), `.timelineCopy` (`"timeline.copy"`, ⌘K; el ⌘C lo atiende el respondedor), `.timelineCopyCall` (`"timeline.copyCall"`, ⇧⌘C); `CommandID.timelineContextual: Set = [timelineCopyCall]`, añadido a lo que `KeyContext.overlay` deja pasar.
- [ ] Pruebas rojas: `show` lee y pinta; al avisar `changes` solo pide desde el cursor; `restarted` rehace el `Timeline` y conserva la selección por id; cambiar de sesión durante una lectura lenta (fake con continuación) no pinta la vieja; `close` → `isWatching == false` y el fake no tiene consumidores; `.unidentified` usa la más reciente y lo marca; `.compressed` → `.failed` con su texto; copiar un prompt recortado devuelve el íntegro del fake y pasa por la política `.copy`; copiar llamada vs salida; búsqueda: dos teclas en 100 ms → una sola búsqueda; cancelar a mitad deja de añadir; el tope; comandos en ⌘K, ayuda y menú con sus atajos; ⇧⌘C pasa al terminal con el timeline cerrado; ningún atajo con ⌥ solo.
- [ ] Implementar; SmaltiCore en verde y la app compila. Commit `feat(core): timeline ports, use cases and commands`.

## Bloque 2 · Adaptadores

### Task 6: `ClaudeTimeline`

**Files:**
- Create: `Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/{ClaudeTimeline,ClaudeTimelineTranslator,ClaudeProjectFolders}.swift`
- Modify: `Packages/ClaudeHarnessAdapter/Package.swift` (depende de `../JSONLReader`), `ClaudeSessionList.swift` (extrae la codificación de carpeta a `ClaudeProjectFolders` sin cambiar su comportamiento)
- Create: `Tests/ClaudeHarnessAdapterTests/{TimelineContractTests.swift (compartida, ver T7),ClaudeTimelineTests.swift,TimelineOracle.swift}`. Los fixtures de F3 (con el subagente) se leen del paquete de F3 por ruta relativa al repo (`#filePath`), sin duplicarlos.

**Interfaces:** `ClaudeTimeline(projectsRoot: URL): SessionTranscripts & ProjectTranscripts`. `locate` busca `<id>.jsonl` en las carpetas de `projects/` (la de su `cwd` primero si se conoce) y su carpeta `<id>/subagents`; `read` lee el principal y los subagentes (enlace por `.meta.json` `toolUseId`, si no por `agentId:` en el resultado); `search` recorre las carpetas cuyo nombre empieza por el de la raíz (más el sufijo `-`) confirmando el `cwd` de la cabecera, de la sesión más reciente a la más antigua, con `JSONLScanner`; `fullText` relee la línea y comprueba inodo.
- [ ] Pruebas rojas: **C1** contrato contra el oráculo en los cuatro transcripts de F6 y F3 (+ subagente) y el sintético de imagen: misma secuencia `(kind, who, scope)` y `fullText` byte a byte de cada elemento; incremental: el fixture partido en dos escrituras sobre un archivo temporal da lo mismo; línea a medias; inodo cambiado → `restarted`; búsqueda: `"hola"` en el proyecto `work-a` (dos sesiones) encuentra las dos, una carpeta hermana con prefijo parecido (`work-ab`) no entra; consulta sin coincidencia → vacío; cancelar.
- [ ] Implementar. Commit `feat(claude): timeline transcripts and project search`.

### Task 7: `CodexTimeline`

**Files:**
- Create: `Packages/CodexHarnessAdapter/Sources/CodexHarnessAdapter/{CodexTimeline,CodexTimelineTranslator}.swift`, `Tests/CodexHarnessAdapterTests/{CodexTimelineTests,TimelineOracle}.swift`
- Modify: `Packages/CodexHarnessAdapter/Package.swift` (depende de `../JSONLReader`)

**Interfaces:** `CodexTimeline(home: URL): SessionTranscripts & ProjectTranscripts`. `locate` por `threads.rollout_path` (si termina en `.zst` → `.compressed`); `sessions(under:)` reutiliza la consulta de `CodexHarness` con `cwd = root or cwd like root || '/%'`; estado de herramienta por `Process exited with code N`.
- [ ] Pruebas rojas: contrato C1 sobre `codex` y `codex-timeline` contra el oráculo; `exit 1` → `.failed(1)`; `<environment_context>` y `developer` fuera; `.zst` → `.compressed`; búsqueda `"missing"` encuentra la salida del `cat`; la prueba de contrato compartida (mismo cuerpo que la de Claude, en un archivo idéntico por paquete, comprobado por `scripts/tests/timeline-contract.test.sh` con `cmp`).
- [ ] Implementar. Commit `feat(codex): timeline rollouts and project search`.

### Revisión intermedia 1 + mutación incremental

- [ ] Revisor nuevo sobre el diff de los bloques 1 y 2; corregir todo (RED→GREEN); `mutate.py --package Packages/SmaltiCore --changed-since origin/develop`; matar sobrevivientes con prueba verificada aplicando el mutante a mano.

## Bloque 3 · App

### Task 8: Panel lateral, composición y teclado

**Files:**
- Create: `App/Smalti/Timeline/{TimelineController,TimelineView,TimelineListView,TimelineRowView,TimelineTokens}.swift`
- Modify: `AppComposition.swift` (`ClaudeTimeline(projectsRoot: settings.claudeHome/projects)`, `CodexTimeline(home: settings.codexHome)`, `TranscriptSources`), `WindowComposition.swift` (comandos, `keyContext`, `searchOpen` → timeline si está abierto, exclusión con `ObservatoryController` y `ProcessesController`), `project.pbxproj` (paquete `JSONLReader`)
- Test: `App/SmaltiUITests/TimelineTests.swift` (+ ayudante que copia fixtures a un `-SmaltiClaudeHome` y `-SmaltiCodexHome` temporales y restaura paneles con `agentSessionID`/binding)

**Interfaces:** `TimelineController(window:, show: ShowTimeline, copy: CopyTimelineItem, search: SearchTranscripts, actions: Actions { focusedPane: () -> Pane?; projectRoot: (Pane) -> String; paneNames; closeOtherOverlays; keymap })`: `toggle(theme:)`, `focusedPaneChanged()`, `dismiss()`, `isOpen`. `TimelineListView` es un `NSTableView` de vista con alturas por fila (`noteHeightOfRows` al desplegar). La vista implementa `copy(_:)` del respondedor (⌘C).
- [ ] Pruebas rojas (`TimelineTests`): ⇧⌘T abre con la sesión del panel (C2); ⌘2 cambia a la del otro panel; un panel con `zsh` muestra el vacío y sus recientes; esc cierra y devuelve el foco al terminal; ⇧⌘A con el timeline abierto lo cierra y abre el Observatorio.
- [ ] Implementar; verde. Commit `feat(app): timeline side panel`.

### Task 9: Desplegar, copiar, búsqueda, respaldo, avisos e idioma

**Files:**
- Create: `App/Smalti/Timeline/{TimelineSearchView,TimelineEmptyView}.swift`
- Modify: los de T8, `Localizable.xcstrings`, `App/SmaltiUITests/{TimelineTests,LocalizationTests}.swift`
- [ ] Pruebas rojas: → y ← sobre una herramienta (C3); ⌘C copia la salida íntegra (`NSPasteboard` en la prueba igual al texto del oráculo para ese elemento, guardado en la prueba como constante) y el aviso «Copiado»; ⇧⌘C la llamada; prompt largo íntegro; ⌘F, «missing» → resultado de la sesión cerrada de Codex, ↵ la abre con el elemento elegido (C4); un panel con un binding de Antigravity → respaldo; `LocalizationTests` en inglés con sesión, búsqueda, vacío y respaldo (C9).
- [ ] Implementar; `strings-catalog.test.sh`, `network-surface.test.sh` y `catalog.py missing` en verde. Commit `feat(app): timeline expand, copy, search and fallbacks`.

### Task 10: Documentos y web

**Files:** `CLAUDE.md` (puertos `SessionTranscripts`, `ProjectTranscripts`, `TranscriptTextPolicy`; `JSONLReader` en comandos y en `swift format`; oráculo; `measure-timeline.sh`), `README.md` (timeline), `docs/PROJECT.md` (funcionalidad), `smalti-web` (página del timeline en/es con capturas de fixtures, atajos, «Lo que viene» con F10 como siguiente, changelog; `pnpm lint` y `pnpm build`).
- [ ] Commit `docs(f9): timeline` y PR de smalti-web.

### Revisión intermedia 2 + regresión de UI + mutación incremental

- [ ] Revisor nuevo sobre el diff desde la revisión 1; corregir; una corrida de `TimelineTests`, `LocalizationTests` y las clases tocadas (`ObservatoryTests`, `ProcessesTests`, `PaletteTests` si cambian); mutación `--changed-since`.

## Bloque 4 · Cierre

### Task 11: Mediciones, capturas, checklist, revisión final

**Files:** `scripts/measure-timeline.sh` (C5, C7, C8: lee el `~/.claude` real en solo lectura con un binario de medida del paquete `JSONLReader`/adaptadores, p50 de 5), `docs/specs/F9-checklist.md`, `docs/specs/F9-assets/f9-*-{es,en}.png`.
- [ ] Medir C5–C8 y GPU/CPU en reposo (C6) contra un worktree de `origin/develop` el mismo día; capturas con fixtures; checklist; revisión final acotada; una tanda de correcciones; mutación de cierre ≥ 80 % de los archivos de SmaltiCore de la fase; suites unitarias de los paquetes tocados en verde.

### Task 12: 0.9.0, PRs, release y despliegue

- [ ] `scripts/release/bump-version.sh 0.9.0`; notas `docs/releases/v0.9.0.md` (inglés, `<!-- lang:es -->`, español); PR feature → develop y develop → main con sus merges; tag `v0.9.0`; PR del appcast (smalti-web) y del cask (homebrew-tap) mergeados tras comprobar el sha256 del DMG; el Smalti diario 0.8.5 → 0.9.0 por Sparkle; `progress.md`, KB.

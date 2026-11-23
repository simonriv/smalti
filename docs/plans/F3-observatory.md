# F3 · Observatorio — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (modo nativo, `.claude/rules/workflow.md`). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Observatorio a pantalla completa (⌘⇧A) con el consumo y el estado de todos los Claude de la máquina en tres periodos (hoy, 7 días, 30 días), modelos de Ollama y métricas del Mac sin sudo; lado derecho de la barra de estado; modelo y `ctx %` en la cabecera. Antes, un arreglo de F1: la paleta ⌘K mantiene visible la fila seleccionada.

**Architecture:** las reglas del criterio de cierre son dominio puro en `SmaltiCore/Domain/Observatory`: deduplicación por `message.id`, cubos de 15 min UTC, periodos, precios, `ctx %` y formato. Un caso de uso, `ObserveAgents`, junta una `ObservatorySnapshot` a partir de cuatro puertos nuevos o ampliados, y tres funciones puras la convierten en el informe del Observatorio, la barra de estado y la cabecera. Hay tres paquetes de adaptador nuevos:
- `ClaudeTelemetryAdapter`: transcripts con índice incremental y `~/.claude/sessions`;
- `OllamaAdapter`;
- `DarwinMetricsAdapter`.

La app aporta el `ObservatoryRefresher`, la vista del Observatorio y los cambios en la barra de estado y la cabecera.

**Tech Stack:** Swift 6.4 (Xcode 27.2), AppKit, Swift Testing, XCUITest, Foundation (`FileHandle`, `JSONSerialization`, `URLSession`), Mach (`host_processor_info`, `host_statistics64`), IOKit (`IOAccelerator`, `IOPlatformExpertDevice`), libproc (`proc_pid_rusage`, `proc_pidinfo`), Claude Code 2.1.330 (`claude -p` para los fixtures), Python 3 (oráculo), `scripts/mutation/mutate.py`.

**Spec:** `docs/specs/F3-observatory.md` (aprobada 2026-11-22) · Convenciones: `CLAUDE.md`, `.claude/rules/` · Diseño: `docs/design/README.md`, `Observatorio.dc.html`, `Main.dc.html`, `Paleta.dc.html`

## Global Constraints

- `SmaltiCore` solo importa `Foundation`, y solo para tipos de valor (`URL`, `Date`, `UUID`, `Calendar`, `TimeZone`). `Codable` está permitido en `SessionActivity` y en sus partes; `JSONEncoder`/`JSONDecoder` solo en el adaptador. La guarda de imports no se toca.
- Cada adaptador nuevo es el único que importa su framework y tiene su prueba de guarda, copiada de `TOMLAdapterGuardTests`:
  - `ClaudeTelemetryAdapter`: Foundation para archivos y `JSONSerialization`, y `Darwin` para `kill` y `proc_pidinfo`;
  - `OllamaAdapter`: `URLSession`;
  - `DarwinMetricsAdapter`: `Darwin.Mach`, `IOKit` y `libproc`.
- Valores fijados por la spec:
  - cubos de 15 min UTC; 60 min de salida por minuto; 5 herramientas recientes; historia de 30 días;
  - refresco cada 2 s con el Observatorio abierto y cada 10 s cerrado; métricas cada 2 s con 60 muestras;
  - Ollama en `http://127.0.0.1:11434`, con 500 ms de espera;
  - umbrales: contexto ámbar desde 75 %, errores en rojo desde 5 %;
  - C10: primera indexación de hoy ≤ 5 s y refresco sin cambios ≤ 50 ms; C11: ningún bloqueo del hilo principal > 16 ms.
- "Tokens entrada" = `input + cacheRead + cacheWrite5m + cacheWrite1h`. Si falta el desglose, `cache_creation_input_tokens` cuenta como escritura de 5 minutos. Cada `message.id` cuenta una sola vez. Los subagentes suman tokens a su sesión, pero no herramientas.
- Precios por defecto: la tabla de la spec, tal cual (USD por MTok, fecha 2026-11-03).
- Textos de interfaz en español, tal cual el tablero o la sección "Textos nuevos" de la spec:
  - franja: "Observatorio", "agentes y modelos en esta máquina", "Hoy", "7 días", "30 días";
  - tarjetas: "Sesiones activas", "N trabajando · N esperando" ("· N error"), "Tokens entrada", "N% desde caché", "Tokens salida", "pico 4.8k/min · 10:42", "Equivalente API", "estimado · incluido en tu plan" ("· sin precio para N modelos");
  - tabla: "Estado", "Sesión", "Agente · modelo", "Vida", "Entrada", "Salida", "Contexto", "Err", "PID"; estados "trabajando", "te espera", "detenida";
  - detalle: "Actividad · <sesión>", "Tokens por minuto · última hora", "Compactación hace 22 min · liberó 38% del contexto", "Sin compactaciones", "Sin actividad en la última hora";
  - Ollama: "Modelos locales · Ollama", "cargado", "en disco", "descargado hace 2 días", "Ollama no está corriendo";
  - sistema: "Sistema · <Mac>", "CPU", "GPU", "Memoria unificada", "modelo 6.1 · agentes 3.5 · resto 1.6 GB · presión media", "no disponible", "leyendo transcripts…";
  - nota al pie: "Datos: hooks y transcripts de Claude Code y API local de Ollama. El costo es estimado.";
  - barra de estado: `qwen3.5:9b · 6.1 GB`, `RAM 11.2 / 16 GB`, `GPU 38%`, `hoy 1.24M tokens`; cabecera: `ctx 41%`; ⌘K: "Abrir observatorio".
- Tokens visuales solo desde `Theme.obsidian`. Los nuevos (tarjeta, tabla, gráfico, CPU `#7dcfff`, GPU `#bb9af7`, resto de memoria `#6b717c`) se añaden ahí con los valores de `Observatorio.dc.html`.
- Swift 6 estricto; errores `throws(Tipo)` con contexto; sin `!`/`try!`/`as!`/`unsafe*` sin comentario (lo inseguro, solo en adaptadores); ≤ 3 parámetros (agrupar en un tipo con nombre); `struct`/`enum` por defecto; sin `switch` por variante de harness (OCP).
- Swift Testing, Arrange/Act/Assert, un concepto por prueba. TDD. Contrato compartido para cada puerto con fake y adaptador (`AgentTranscripts`, `LiveAgents`, `LocalModels`; `SystemMetrics` comprueba rangos con el adaptador real).
- UI tests: `XCUIApplication.isolatedSmalti()` pasa, además de lo de F2, `-SmaltiClaudeHome <tmp>` (vacío por defecto) y `-SmaltiOllamaURL http://127.0.0.1:1` (sin servidor). Ninguna prueba lee el `~/.claude` real ni el Ollama real. `PasteboardGuard` en cada clase. La suite corre con `scripts/check-daily-untouched.sh`.
- Una app GUI lanzada desde la sesión se abre con `env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh TMPDIR="$TMPDIR" LANG=es_CO.UTF-8 PATH=/usr/bin:/bin:/usr/sbin:/sbin open -a …` (nota del KB).
- Verificación: los comandos de `CLAUDE.md`, más `swift test --package-path Packages/<Nuevo>` por cada paquete nuevo y el lint ampliado a los paquetes nuevos. Suites de más de 30 s con `"$KB_ROOT/_system/bin/kb-progress" run <etiqueta> -- …`. Siempre el código de salida real, nunca una salida por pipe.
- Ramas y fusiones:
  - Bloque 0 en `fix/palette-keeps-selection-visible`, desde `develop`, con PR propio;
  - bloques 1–4 en `feature/f3-observatory`, que ya tiene la spec y los cambios de documentos;
  - Conventional Commits en inglés, con las líneas de atribución de la sesión;
  - cada tarea se marca en `progress.md`;
  - nada se fusiona sin confirmación de Simón.
- Revisión por bloque: al cerrar cada bloque, un revisor nuevo revisa el diff del bloque. Los hallazgos importantes se corrigen antes del siguiente bloque; los menores, en una tanda al final del bloque, cada uno con su prueba RED→GREEN.

## Desviaciones de la spec (para revisar con el plan)

1. **Un solo caso de uso, `ObserveAgents`, en lugar de tres.**
   - Junta los datos una vez por refresco en una `ObservatorySnapshot`.
   - Tres funciones puras sacan de ella lo que pinta cada vista: `ObservatoryReport.make`, `StatusFigures.make` y `PaneAgentDetail.make`.
   - Así cada refresco lee una sola vez, en lugar de tres. Los nombres `ReadStatusFigures` y `DescribePaneAgent` de la spec pasan a ser esas funciones puras.
2. **`AgentTranscripts.activity(since:)` devuelve `TranscriptActivity { sessions; indexedSince }`, no solo las sesiones.**
   - `indexedSince` dice desde cuándo el índice está completo.
   - Con ese dato la vista sabe cuándo mostrar "leyendo transcripts…".
3. **El refresco siempre pide 30 días.**
   - Con el índice al día, leer 30 días cuesta lo mismo que leer hoy.
   - La barra de estado necesita hoy al mismo tiempo que el Observatorio muestra otro periodo.

## Review Focus

1. **Claude escribe a medias mientras leemos.** Si el archivo termina sin `\n`, la línea incompleta no se pierde ni se cuenta dos veces: se lee entera en la pasada siguiente (Task 7: `partialLastLineIsReadOnNextPass`).
2. **Un transcript gigante o con una línea enorme** (un `tool_result` de varios MB). La lectura avanza por bloques sin cargar el archivo entero, y la línea grande se procesa (Task 7: `multiMegabyteLineIsRead`).
3. **Reloj o zona horaria del Mac cambian con el Observatorio abierto** (viaje, cambio manual). "Hoy" se recalcula con la zona horaria actual en cada refresco, sin reconstruir el índice (Task 3: `periodUsesCurrentTimeZoneEachTime`).
4. **Sesión con modelo `<synthetic>` o sin ningún turno con usage** (un `claude` abierto y cerrado sin escribir). Aparece como fila viva con 0 tokens y sin modelo, sin costo, con "—" en contexto y sin error (Task 2: `syntheticTurnDoesNotSetModel`; Task 3: `liveSessionWithoutTurnsShowsZeroAndNoContext`).
5. **El mismo `sessionId` en un panel de Smalti y en `sessions/<pid>.json` con estados distintos.** Ganan los hooks del panel, y la fila no se duplica (Task 3: `paneStateWinsOverRegistryAndRowIsNotDuplicated`).

---

## Mapa de archivos

```text
App/Smalti/CommandPalette{Controller,View}.swift (modif.)        T0
App/SmaltiUITests/CommandPaletteTests.swift (modif.)              T0
docs/{PROJECT,ROADMAP}.md, CLAUDE.md, progress.md                 (hecho al crear la rama)

Packages/SmaltiCore/Sources/SmaltiCore/
  Domain/Observatory/{TokenUsage,ModelCatalog,CostEstimate,ContextLoad,ObservatoryFormat}.swift    T1
  Domain/Observatory/{TranscriptRecord,SessionActivity,ToolSummary}.swift                         T2
  Domain/Observatory/{ObservatoryPeriod,ObservedSession,ObservatoryReport,StatusFigures,PaneAgentDetail}.swift  T3
  Application/{AgentTranscripts,LiveAgents,LocalModels,SystemMetrics,ObserveAgents}.swift          T4
  Domain/Config/{SmaltiConfig,CommandID,Keymap,LaunchSettings}.swift (modif.)                      T4, T5
  Domain/Commands/CommandCatalog.swift (modif.)                                                    T4
Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/{FakeAgentTranscripts,FakeLiveAgents,FakeLocalModels,
  FakeSystemMetrics,ObservatoryContracts}.swift                                                    T4
Packages/TOMLConfigAdapter/ (modif.: [observatory.models])                                         T5

scripts/observatory/{record-fixtures.sh,sum_transcripts.py,test_sum_transcripts.py}                T6
Packages/ClaudeTelemetryAdapter/                     T6 (fixtures), T7 (transcripts), T8 (registro)
Packages/OllamaAdapter/                              T9
Packages/DarwinMetricsAdapter/                       T10

App/Smalti/{AppComposition,AppIdentity,TilingController,StatusBarView,PaneHeaderView}.swift (modif.)  T11
App/Smalti/Observatory/{ObservatoryRefresher,ObservatoryController}.swift                           T11, T13
App/Smalti/Observatory/{ObservatoryView,SummaryCardsView,SessionTableView,ActivityView,
  OutputChartView,LocalModelsView,SystemView,Sparkline}.swift                                       T12
App/SmaltiUITests/{IsolatedApp,ObservatoryTests,DesignCaptureTests}.swift, Fixtures/claude-home/    T14
scripts/measure-observatory.sh, docs/specs/F3-checklist.md                                          T15
```

---

## Bloque 0 · Arreglo de la paleta — rama `fix/palette-keeps-selection-visible`

### Task 0: La fila seleccionada de ⌘K siempre se ve entera

**Causa (confirmada en el código):**
- `CommandPaletteController.rowCapacity` = `maximumListHeight / rowHeight` no descuenta los encabezados de sección.
- Por eso `ResultWindow` construye más filas de las que caben, y el `NSScrollView` recorta las últimas.
- La selección puede llegar a una fila recortada sin que la lista se desplace (captura de Simón: "Instalar integración con Claude Code" cortada abajo).
- La primera tarea lo confirma con `superpowers:systematic-debugging` antes de tocar nada.

**Files:**
- Modify: `App/Smalti/CommandPaletteView.swift` (`reveal(_ row: NSView)`), `App/Smalti/CommandPaletteController.swift` (llama a `reveal` tras `highlight()` y tras `renderWindow()`)
- Test: `App/SmaltiUITests/CommandPaletteTests.swift`

**Interfaces:**
- Produces: `CommandPaletteView.reveal(_ row: NSView)`. Hace `layoutSubtreeIfNeeded()` y luego `row.scrollToVisible(row.bounds)`, así que la lista se desplaza lo justo para mostrar la fila entera. No hay animación (respeta "Reducir movimiento" sin código extra).

- [ ] **Step 1: Pruebas que fallan** (XCUITest, ventana de 1100 × 700 para que la lista desborde):
  - `testArrowDownKeepsSelectedRowInsideTheList`: abre ⌘K y pulsa ↓ hasta la última fila. Tras cada pulsación, el `frame` de la fila seleccionada (`isSelected`) está contenido en el `frame` de `smalti.palette.list`.
  - `testArrowUpWrapsAndRevealsLastRow`: abre ⌘K y pulsa ↑ una vez (salta a la última fila); la última fila queda contenida en la lista.
  - `testArrowUpBackToTopRevealsFirstRow`: tras bajar hasta el final, pulsa ↓ (vuelve a la primera fila por el salto circular); la primera fila y su encabezado de sección quedan contenidos.

  Si `smalti.palette.list` o el valor `isSelected` aún no existen, se añaden como identificadores de accesibilidad en este mismo paso.
- [ ] **Step 2:** Correr `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh CommandPaletteTests` con `scripts/check-daily-untouched.sh`. Resultado esperado: fallan las 3.
- [ ] **Step 3:** Implementar `reveal` y llamarlo.
- [ ] **Step 4:** `CommandPaletteTests` completo en verde (las 8 pruebas existentes y las 3 nuevas), con el diario intacto.
- [ ] **Step 5:** Commit `fix(app): keep the selected palette row in view`.
- [ ] **Step 6:**
  - revisión del diff (revisor nuevo) y correcciones;
  - PR a `develop` con una captura antes/después;
  - Simón confirma la fusión;
  - `feature/f3-observatory` se rebasa sobre `develop`.

---

## Bloque 1 · Dominio y configuración — rama `feature/f3-observatory`

Todas las rutas son relativas a `Packages/SmaltiCore/Sources/SmaltiCore/`. Las pruebas van en `Tests/SmaltiCoreTests/Observatory/`.

### Task 1: Tokens, catálogo de modelos, costo, contexto y formato

**Files:**
- Create: `Domain/Observatory/{TokenUsage,ModelCatalog,CostEstimate,ContextLoad,ObservatoryFormat}.swift`
- Test: `TokenUsageTests.swift`, `ModelCatalogTests.swift`, `CostEstimateTests.swift`, `ObservatoryFormatTests.swift`

**Interfaces:**
- Produces:
  - `public struct TokenUsage: Codable, Equatable, Sendable { input, output, cacheRead, cacheWrite5m, cacheWrite1h: Int; static let zero; static func + ; var inputTotal: Int; var cacheShare: Double? }`. `cacheShare` es nil si `inputTotal == 0`.
  - `public struct ModelID: Hashable, Codable, Sendable, RawRepresentable`. `var family: String`: `opus`, `sonnet`, `haiku` o `fable` si el id las contiene tras `claude-`; si no, el id. `<synthetic>` es `ModelID.synthetic`.
  - `public struct ModelPricing: Equatable, Sendable { contextWindow: Int; input, output, cacheRead, cacheWrite5m, cacheWrite1h: Double }` (USD por MTok).
  - `public struct ModelCatalog: Equatable, Sendable`:
    - `static let standard` (la tabla de la spec);
    - `func pricing(for: ModelID) -> ModelPricing?` (prueba el id exacto, luego sin `[…]` y luego sin `-YYYYMMDD`);
    - `func overriding(_ overrides: [ModelID: ModelPricingOverride]) -> ModelCatalog`;
    - `public struct ModelPricingOverride: Equatable, Sendable { contextWindow: Int?; input, output, cacheRead, cacheWrite5m, cacheWrite1h: Double? }`.
  - `public struct CostEstimate: Equatable, Sendable { usd: Double; unpricedModels: Set<ModelID>; static func of(_ usage: [ModelID: TokenUsage], catalog: ModelCatalog) -> CostEstimate }`.
  - `public enum ContextLoad: Equatable, Sendable { case percent(Int); case unavailable; static func of(contextTokens: Int?, model: ModelID?, catalog: ModelCatalog) -> ContextLoad; var isHigh: Bool }`. Redondea al entero más cercano; `isHigh` es verdadero con ≥ 75.
  - `public enum ObservatoryFormat` (funciones estáticas puras):
    - `count(_: Int) -> String`: `0`, `412`, `999`, `1k`, `61.4k`, `982k`, `1.24M`. Reglas: < 1000 tal cual; < 100k con una decimal sin `.0`; < 1M sin decimales; desde 1M con dos decimales sin ceros finales.
    - `lifetime(_: TimeInterval) -> String`: `0m`, `34m`, `1h 12m`, `2h 05m`.
    - `ago(_: TimeInterval) -> String`: `hace 22 min`, `hace 3h`, `hace 2 días` (`hace 1 día` en singular).
    - `gigabytes(_ bytes: UInt64) -> String`: `6.1 GB`; < 1 GB → `274 MB`.
    - `memory(used:total:) -> String`: `11.2 / 16 GB`, con el total entero.
    - `usd(_: Double) -> String`: `$18.40`.
    - `percent(_: Int) -> String`: `41%`.
    - `clock(_: Date, timeZone:) -> String`: `10:42`.

- [ ] **Step 1: Pruebas que fallan:**
  - `inputTotalAddsCacheReadsAndWrites`, `cacheShareIsNilWithoutInput`, `usageAddsFieldByField`;
  - `familyComesFromModelID` (opus, sonnet, haiku, fable, desconocido), `pricingFallsBackWithoutBracketSuffix`, `pricingFallsBackWithoutDateSuffix`, `unknownModelHasNoPricing`, `overrideReplacesOnlyGivenFields`, `overrideAddsNewModel`;
  - `costUsesAllFiveRates` (1M de cada tipo con Opus 5.5 = 4 + 20 + 0,20 + 5 + 8 = 37,20), `costSkipsAndReportsUnpricedModel`, `costSumsAcrossModels`;
  - `contextRoundsToNearestPercent`, `contextWithoutWindowIsUnavailable`, `contextAt75IsHigh`, `contextAt74IsNotHigh`;
  - `countFormatsBoardExamples` (412, 61.400, 982.000, 1.240.000), `countDropsTrailingZeros` (1000 → `1k`, 2.000.000 → `2M`), `lifetimePadsMinutesAfterHours`, `agoSwitchesUnitsAtHourAndDay`, `agoSingularDay`, `gigabytesAndMegabytes`, `memoryRoundsTotal`, `usdTwoDecimals`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): add token usage, model pricing and observatory formats`.

### Task 2: Registros del transcript y plegado de la sesión

**Files:**
- Create: `Domain/Observatory/{TranscriptRecord,SessionActivity,ToolSummary}.swift`
- Test: `SessionActivityTests.swift`, `ToolSummaryTests.swift`

**Interfaces:**
- Consumes: T1.
- Produces:
  - `public enum TranscriptRecord: Equatable, Sendable`:
    - `.assistantTurn(AssistantTurn)`, con `AssistantTurn { messageID: String; model: ModelID; usage: TokenUsage; at: Date; isSubagent: Bool }`;
    - `.toolStarted(ToolStart)`, con `ToolStart { id: String; name: String; input: [String: String]; at: Date }`;
    - `.toolFinished(ToolFinish)`, con `ToolFinish { id: String; isError: Bool; exitCode: Int?; diff: DiffStat?; at: Date }` y `DiffStat { added: Int; removed: Int }`;
    - `.compacted(Compaction)`, con `Compaction: Codable { at: Date; preTokens: Int; postTokens: Int }`;
    - `.sessionInfo(sessionID: String, cwd: String, at: Date)`.
  - `public struct QuarterHour: Hashable, Codable, Comparable, Sendable { let start: Date; init(containing: Date) }`. Los bordes van en múltiplos de 900 s desde 1970 (UTC).
  - `public struct ActivityBucket: Codable, Equatable, Sendable { usageByModel: [ModelID: TokenUsage]; toolCalls: Int; toolErrors: Int; peakMinute: Date?; peakOutput: Int }`.
  - `public enum ToolOutcome: Codable, Equatable, Sendable { case running; case succeeded(duration: TimeInterval); case failed(exitCode: Int?) }`.
  - `public struct RecentTool: Codable, Equatable, Sendable { id: String; name: String; summary: String; startedAt: Date; outcome: ToolOutcome }`.
  - `public struct SessionActivity: Codable, Equatable, Sendable`:
    - campos: `sessionID`, `cwd`, `model: ModelID?`, `firstActivity: Date?`, `lastActivity: Date?`, `buckets: [QuarterHour: ActivityBucket]`, `outputByMinute: [Date: Int]` (minuto inicial → tokens), `contextTokens: Int?`, `recentTools: [RecentTool]` (máximo 5, la más reciente primero), `lastCompaction: Compaction?`;
    - privados: `countedMessages: Set<String>`, `pendingTools: [String: RecentTool]`;
    - `init(sessionID: String)`;
    - `func folding(_ records: [TranscriptRecord]) -> SessionActivity`.
  - Reglas de `folding`:
    - un `messageID` ya contado no suma nada;
    - el modelo `.synthetic` o un `usage == .zero` no cambian `model` ni `contextTokens`;
    - los turnos de subagente suman al cubo, pero no cambian `model`, `contextTokens` ni la salida por minuto del gráfico;
    - `outputByMinute` guarda solo los minutos dentro de los 60 anteriores al último turno visto;
    - el pico del cubo se recalcula con la salida por minuto de ese cubo (`peakMinute` y `peakOutput`);
    - herramientas: `toolStarted` crea una pendiente; `toolFinished` la cierra, la suma al cubo de su `at` (`toolErrors` si `isError`) y la pone en `recentTools`; un `toolFinished` sin su inicio se ignora.
  - `public enum ToolSummary { static func text(name: String, input: [String: String], diff: DiffStat?) -> String }`. Reglas de la spec: Bash → `command`; Read, Write, Edit, Update y MultiEdit → nombre del archivo de `file_path` (`+N −M` con diff); Grep y Glob → `"patrón" en <path>` (sin `path`, solo `"patrón"`); otras → el primer valor por orden de clave.

- [ ] **Step 1: Pruebas que fallan:**
  - deduplicación: `repeatedMessageCountsOnce`, `repeatedMessageAcrossFoldsCountsOnce`;
  - cubos: `turnsLandInQuarterHourBuckets` (10:14:59 y 10:15:00 en cubos distintos), `usageIsKeptPerModel`, `subagentAddsTokensButNotModelOrContext`, `syntheticTurnDoesNotSetModel`, `contextComesFromLastMainTurn`;
  - salida por minuto: `outputByMinuteKeepsLastSixtyMinutes`, `bucketPeakIsHighestMinute`;
  - herramientas: `toolFinishCountsCallAndError`, `toolFinishInLaterFoldClosesPendingTool`, `orphanToolFinishIsIgnored`, `recentToolsKeepsFiveNewestFirst`, `bashDurationIsFinishMinusStart`;
  - compactación y actividad: `compactionKeepsLatest`, `firstAndLastActivityTrackTimestamps`;
  - `ToolSummary`: `bashShowsCommand`, `editShowsFileAndDiff`, `grepShowsPatternAndPath`, `grepWithoutPathShowsPattern`, `unknownToolShowsFirstValue`;
  - `activityRoundTripsThroughJSON` (con `JSONEncoder` en la prueba).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): fold transcript records into session activity`.

### Task 3: Periodos, sesiones observadas y lo que pinta cada vista

**Files:**
- Create: `Domain/Observatory/{ObservatoryPeriod,ObservedSession,ObservatorySnapshot,ObservatoryReport,StatusFigures,PaneAgentDetail}.swift`
- Test: `ObservatoryPeriodTests.swift`, `ObservedSessionTests.swift`, `ObservatoryReportTests.swift`, `StatusFiguresTests.swift`, `PaneAgentDetailTests.swift`

**Interfaces:**
- Consumes: T1, T2; `AgentSession` y `AgentStateKind` de F2.
- Produces:
  - `public enum ObservatoryPeriod: CaseIterable, Sendable { case today, lastSevenDays, lastThirtyDays; func start(now: Date, calendar: Calendar) -> Date; var next: ObservatoryPeriod; var title: String }`. `title` es "Hoy", "7 días" o "30 días"; el calendario lleva la zona horaria.
  - `public struct RunningAgent: Equatable, Sendable { pid: Int32; sessionID: String; cwd: String; status: String; startedAt: Date }`.
  - `public struct LocalModel: Equatable, Sendable { name: String; quantization: String?; bytes: UInt64; vramBytes: UInt64?; contextLength: Int?; downloadedAt: Date? }` y `public enum LocalModelsReport: Equatable, Sendable { case unavailable; case available(loaded: [LocalModel], onDisk: [LocalModel]) }`.
  - `public enum Measurement<Value: Equatable & Sendable>: Equatable, Sendable { case value(Value); case unavailable }`.
  - `public struct SystemSample: Equatable, Sendable { cpu: Measurement<Double>; gpu: Measurement<Double>; memoryUsed: Measurement<UInt64>; memoryTotal: UInt64; agentsMemory: Measurement<UInt64>; pressure: Measurement<MemoryPressure>; machineName: String }`, con `MemoryPressure: normal | media | alta`.
  - `public struct ObservatorySnapshot: Equatable, Sendable { activity: TranscriptActivity; running: [RunningAgent]; panes: [PaneAgent]; localModels: LocalModelsReport; system: SystemSample; cpuHistory: [Double]; gpuHistory: [Double]; catalog: ModelCatalog; now: Date }`:
    - `public struct TranscriptActivity: Equatable, Sendable { sessions: [SessionActivity]; indexedSince: Date }`;
    - `public struct PaneAgent: Equatable, Sendable { pane: PaneID; label: String; session: AgentSession }`, construido desde `WorkspaceSet` con la etiqueta de las notificaciones de F2.
  - `public struct ObservedSession: Equatable, Sendable { id: String; label: String; state: AgentStateKind; pane: PaneID?; pid: Int32?; startedAt: Date?; activity: SessionActivity }`:
    - `static func merge(_ snapshot: ObservatorySnapshot) -> [ObservedSession]`;
    - reglas de estado y etiqueta de la spec: el panel gana; si no hay panel, `status` con `busy` → working, `idle`/`waiting` → waiting y otro → working; sin proceso → stopped. La etiqueta, con los dos últimos componentes del `cwd`;
    - una sesión viva sin `SessionActivity` produce una vacía;
    - el mapeo de `status` es una tabla, no un `switch`, y los valores desconocidos se devuelven aparte para registrarlos.
  - `public struct ObservatoryReport: Equatable, Sendable`:
    - `summary: Summary`, con:
      - `active: Int`, `working: Int`, `waiting: Int`, `failed: Int`;
      - `input: Int`, `cacheShare: Int?`, `output: Int`, `peak: (output: Int, at: Date)?`;
      - `cost: CostEstimate`, `isComplete: Bool`;
    - `rows: [Row]`, con `Row { id; state: AgentStateKind; label; agentModel: String ("Claude Code · opus"); lifetime: String; input: String; output: String; context: ContextLoad; errorRate: Int?; isErrorRateHigh: Bool; pid: String; pane: PaneID? }`;
    - `detail: Detail?`, con `Detail { title: String; tools: [RecentTool]; outputPerMinute: [Int] (60 valores, el más antiguo primero); peak: (output: Int, minute: Date)?; compaction: String }`;
    - `static func make(_ snapshot: ObservatorySnapshot, period: ObservatoryPeriod, selection: String?, calendar: Calendar) -> ObservatoryReport`;
    - reglas de orden, columnas por periodo, `isComplete = snapshot.activity.indexedSince <= period.start` y "Sin compactaciones" o "Compactación hace … · liberó N% del contexto" de la spec;
    - `isErrorRateHigh` con ≥ 5 %;
    - la selección por defecto es la primera fila.
  - `public struct StatusFigures: Equatable, Sendable { localModel: String?; ram: String; gpu: String; todayTokens: String; static func make(_ snapshot: ObservatorySnapshot, calendar: Calendar) -> StatusFigures }`. `GPU no disponible` si hace falta; `localModel` solo con un modelo cargado.
  - `public struct PaneAgentDetail: Equatable, Sendable { family: String?; context: ContextLoad; static func make(sessionID: String, snapshot: ObservatorySnapshot) -> PaneAgentDetail }`.

- [ ] **Step 1: Pruebas que fallan** (`America/Bogota` salvo que se diga otra cosa):
  - periodos: `todayStartsAtLocalMidnight`, `sevenDaysStartsSixMidnightsAgo`, `thirtyDaysCrossesMonthEnd`, `dstDayInNewYorkStartsAtLocalMidnight`, `periodUsesCurrentTimeZoneEachTime`, `nextCyclesThroughPeriods`;
  - sesiones observadas: `paneStateWinsOverRegistryAndRowIsNotDuplicated`, `busyIsWorkingIdleIsWaiting`, `unknownStatusIsWorkingAndReported`, `deadSessionIsStopped`, `labelUsesLastTwoPathComponents`, `labelUnderHomeUsesOneComponent`, `liveSessionWithoutTurnsShowsZeroAndNoContext`;
  - informe: `sessionCrossingMidnightCountsOnlyTodayBuckets`, `rowTotalsSumToSummary`, `liveRowsFirstByStartThenStoppedByActivity`, `subagentsNeverBecomeRows`, `peakIsHighestBucketPeakInPeriod`, `incompleteIndexMarksPeriodAsReading`, `compactionFreedShareOfWindow` (pre 967.809, post 57.813, ventana 1M → 91 %), `noCompactionText`, `errorRateAtFivePercentIsHigh`, `defaultSelectionIsFirstRow`, `detailHasSixtyMinuteSeries`;
  - barra de estado y cabecera: `statusShowsLoadedModelOnly`, `statusGpuUnavailableText`, `todayTokensAddInputAndOutput`, `paneDetailGivesFamilyAndContext`, `paneDetailForUnknownSessionIsUnavailable`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): build the observatory report, status figures and pane details`.

### Task 4: Puertos, fakes, contratos, caso de uso y comandos

**Files:**
- Create: `Application/{AgentTranscripts,LiveAgents,LocalModels,SystemMetrics,ObserveAgents}.swift`, `SmaltiCoreTestSupport/{FakeAgentTranscripts,FakeLiveAgents,FakeLocalModels,FakeSystemMetrics,ObservatoryContracts}.swift`
- Modify: `Domain/Config/{CommandID,Keymap,LaunchSettings}.swift`, `Domain/Commands/CommandCatalog.swift`
- Test: `Tests/SmaltiCoreTests/Observatory/{ObserveAgentsTests,ObservatoryContractTests}.swift`, `Domain/{KeymapTests,CommandCatalogTests}.swift`, `Config/LaunchSettingsTests.swift`

**Interfaces:**
- Consumes: T1–T3.
- Produces:
  - Puertos:
    - `public protocol AgentTranscripts: Sendable { func activity(since: Date) async throws(TranscriptError) -> TranscriptActivity }`, con `TranscriptError.unreadableRoot(path: String, reason: String)`;
    - `public protocol LiveAgents: Sendable { func running() async -> [RunningAgent] }`;
    - `public protocol LocalModels: Sendable { func current() async -> LocalModelsReport }`;
    - `@MainActor public protocol SystemMetrics: AnyObject { func sample(agentProcesses: [Int32]) -> SystemSample }`.
  - Contratos compartidos (`ObservatoryContracts`), que cada adaptador corre con sus fixtures:
    - `AgentTranscriptsContract`: sesiones desde la fecha; `indexedSince <= since` tras una lectura completa; una segunda lectura sin cambios devuelve lo mismo.
    - `LiveAgentsContract`: los PID devueltos están vivos; ningún `sessionID` vacío.
    - `LocalModelsContract`: `.unavailable` o modelos con `bytes > 0`.
  - `@MainActor public final class ObserveAgents`:
    - `init(_ sources: ObservatorySources)`, con `public struct ObservatorySources { transcripts: any AgentTranscripts; live: any LiveAgents; localModels: any LocalModels; system: any SystemMetrics; catalog: ModelCatalog }`;
    - `func snapshot(panes: [PaneAgent], now: Date) async -> ObservatorySnapshot`;
    - pide `activity(since: now − 30 días)` y guarda las últimas 60 muestras de CPU y GPU;
    - con `TranscriptError`, la snapshot lleva las sesiones anteriores y `lastError: String?`, que la vista muestra como mensaje de estado; nunca deja de devolver;
    - `var unknownStatuses: Set<String>` para que la app los registre una vez.
  - `CommandID.observatoryToggle = "observatory.toggle"` (⌘⇧A) y `CommandID.observatoryPeriod = "observatory.period"` (⌘P), ambos en `allStandard`. En el catálogo, "Abrir observatorio" va en la sección "Workspaces y sesiones" con su atajo; `observatory.period` no aparece en ⌘K.
  - `LaunchSettings` gana `claudeHome: URL` (`-SmaltiClaudeHome`, si no `CLAUDE_CONFIG_DIR`, si no `~/.claude`) y `ollamaURL: URL` (`-SmaltiOllamaURL`, si no `http://127.0.0.1:11434`).

- [ ] **Step 1: Pruebas que fallan:**
  - contratos con los fakes;
  - caso de uso: `snapshotAsksForThirtyDays`, `snapshotKeepsSixtySystemSamples`, `transcriptErrorKeepsPreviousSessionsAndReports`, `unknownStatusesAreCollected`;
  - comandos y argumentos: `observatoryToggleIsCommandShiftA`, `observatoryPeriodIsCommandP`, `paletteListsOpenObservatory`, `claudeHomeArgumentWins`, `claudeHomeFallsBackToConfigDirThenHome`, `ollamaURLArgumentWins`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): add observatory ports and the observe-agents use case`.

### Task 5: Precios y ventanas en el TOML

**Files:**
- Modify: `Domain/Config/SmaltiConfig.swift` (`observatory: ObservatorySettings`), `Packages/TOMLConfigAdapter/Sources/TOMLConfigAdapter/{TOMLConfigParser.swift}`, más un `ObservatoryReader.swift` nuevo
- Test: `Packages/TOMLConfigAdapter/Tests/…/ObservatoryReaderTests.swift`

**Interfaces:**
- Consumes: T1 (`ModelPricingOverride`, `ModelCatalog.overriding`).
- Produces:
  - `public struct ObservatorySettings: Equatable, Sendable { models: [ModelID: ModelPricingOverride]; var catalog: ModelCatalog }`;
  - el parser acepta la tabla `observatory`, con la subtabla `models."<id>"` y las claves `context`, `input`, `output`, `cache_read`, `cache_write_5m` y `cache_write_1h`;
  - un modelo fuera de `ModelCatalog.standard` sin las seis claves produce `ConfigError` con archivo, línea, clave y la razón "faltan claves: …";
  - un número negativo produce `ConfigError` con la razón "debe ser ≥ 0".

- [ ] **Step 1: Pruebas que fallan:** `overrideOneRateOfKnownModel`, `newModelWithAllKeys`, `newModelMissingKeysFailsWithLine`, `negativeRateFails`, `unknownKeyInModelFails`, `noObservatoryTableKeepsStandard`.
- [ ] **Step 2–4:** Rojo → implementar → verde (`TOMLConfigAdapter` y `SmaltiCore`).
- [ ] **Step 5:** Commit `feat(config): read model pricing overrides from the TOML`.
- [ ] **Step 6: Cierre del bloque 1:**
  - revisión del diff del bloque (revisor nuevo) y correcciones;
  - mutación parcial de `Domain/Observatory` como sondeo, con sus sobrevivientes muertos ahora;
  - `progress.md`.

---

## Bloque 2 · Adaptadores

### Task 6: Fixtures reales y oráculo independiente

**Files:**
- Create:
  - `scripts/observatory/record-fixtures.sh`;
  - `scripts/observatory/sum_transcripts.py`;
  - `scripts/observatory/test_sum_transcripts.py`;
  - `Packages/ClaudeTelemetryAdapter/Package.swift` (esqueleto con su guarda de imports);
  - `Packages/ClaudeTelemetryAdapter/Tests/ClaudeTelemetryAdapterTests/Fixtures/real/<n>/…` (`projects/` y `expected.json`);
  - `Packages/ClaudeTelemetryAdapter/Tests/ClaudeTelemetryAdapterTests/Fixtures/synthetic/…`.

**Interfaces:**
- Produces:
  - **`record-fixtures.sh <out-dir>`** graba sin supervisión en un directorio de trabajo temporal propio.
    - Usa `claude -p --model claude-haiku-5-5`, porque es barato y el modelo da igual para el conteo.
    - Graba tres sesiones:
      - A: un turno;
      - B: tres turnos con `--resume`, uno de ellos con herramientas (`Bash` `ls`, `Read`);
      - C: un turno que lanza un subagente (herramienta `Task`).
    - Graba además una bifurcación de A con `--resume --fork-session`, para el riesgo de la spec.
    - Copia sus `.jsonl`, las carpetas `subagents/` y `meta.json` al destino, con `~/.claude/projects/<cwd>` reescrito a una ruta neutra.
    - Durante la grabación registra los valores de `status` de `~/.claude/sessions/<pid>.json` que ve (solo esa clave).
    - Nunca copia `sessions/*.key`.
  - **`sum_transcripts.py <projects-dir> [--since ISO] [--until ISO]`** imprime un JSON con, por sesión y en total, `input`, `output`, `cacheRead`, `cacheWrite5m` y `cacheWrite1h`.
    - Cuenta cada `message.id` una vez (global si la bifurcación muestra ids copiados; ver Step 3).
    - Suma los subagentes a su sesión y ignora `<synthetic>`.
    - No comparte código con Swift.
  - **Fixtures sintéticos:**
    - `partial-line.jsonl` (sin `\n` final);
    - `malformed.jsonl` (una línea rota en medio);
    - `compaction.jsonl` (registro `compact_boundary` con la forma real);
    - `unknown-model.jsonl`;
    - `huge-line.jsonl` (una línea de 4 MB);
    - `midnight.jsonl` (turnos a las 23:59 y a las 00:01 de Bogotá);
    - `sessions/` con un PID muerto, uno con `procStart` distinto y un `*.key` señuelo.

- [ ] **Step 1:** Pruebas del oráculo que fallan (`cd scripts/observatory && python3 -m unittest test_sum_transcripts`): `repeated_message_counts_once`, `subagent_adds_to_parent`, `synthetic_is_ignored`, `since_until_filter_by_timestamp`, `missing_breakdown_counts_as_5m`.
- [ ] **Step 2:** Implementar el oráculo → verde.
- [ ] **Step 3:** Correr `record-fixtures.sh` y anotar en el ledger:
  - si la bifurcación copia ids; si los copia, Ruling: la deduplicación pasa a ser global en T7 y en el oráculo, con su prueba `forkedSessionDoesNotDoubleCount`;
  - los valores de `status` vistos.

  Generar `expected.json` de cada fixture real con el oráculo.
- [ ] **Step 4:** Revisar que los fixtures no tengan rutas ni contenido personal: solo los prompts de prueba del script.
- [ ] **Step 5:** Commit `test(observatory): record real transcript fixtures and an independent token oracle`.

### Task 7: `ClaudeTranscripts` con índice incremental

**Files:**
- Create: `Packages/ClaudeTelemetryAdapter/Sources/ClaudeTelemetryAdapter/{ClaudeTranscripts,TranscriptLineReader,TranscriptLineTranslator,TranscriptIndex}.swift`
- Test: `ClaudeTranscriptsTests.swift`, `TranscriptLineTranslatorTests.swift`, `ClaudeAdapterGuardTests.swift`, el contrato `AgentTranscriptsContract`

**Interfaces:**
- Consumes: T2 (`TranscriptRecord`, `SessionActivity.folding`), T4 (puerto), T6 (fixtures y `expected.json`).
- Produces:
  - `public actor ClaudeTranscripts: AgentTranscripts`, con `init(claudeHome: URL, indexFile: URL, now: @Sendable () -> Date)`.
  - `TranscriptLineTranslator.records(from line: Data, isSubagent: Bool) -> [TranscriptRecord]`. Traduce solo los tipos conocidos (`assistant`, `user` con `tool_result`, `system`/`compact_boundary`); el resto da `[]`; una línea rota lanza un error interno que el lector cuenta.
  - `TranscriptLineReader` lee desde un offset hasta el último `\n` en bloques de 1 MB (`FileHandle`) y devuelve las líneas y el offset nuevo.
  - `TranscriptIndex: Codable { version: Int; files: [String: FileEntry]; sessions: [String: SessionActivity]; indexedSince: Date }`, con `FileEntry { inode: UInt64; size: UInt64; offset: UInt64; sessionID: String; isSubagent: Bool }`.
    - Se guarda en `<estado>/observatory/index.json` con escritura atómica.
    - Si es ilegible o de otra versión, se reconstruye.
  - Orden de la primera lectura: los archivos por `mtime` descendente. `indexedSince` baja a medida que se completan los días; hoy queda completo primero.

- [ ] **Step 1: Pruebas que fallan:**
  - `realFixturesMatchOracleExactly`: para cada fixture real y para su total, los cinco campos coinciden con `expected.json` (**C1**);
  - lectura incremental: `growingFileCountsRepeatedMessageOnce` (**C2**), `partialLastLineIsReadOnNextPass`, `truncatedFileIsReread`, `replacedFileByInodeIsReread`, `corruptIndexIsRebuilt`, `malformedLineIsSkippedAndCounted`, `multiMegabyteLineIsRead` (**C4**);
  - `compactionRecordIsTranslated`, `toolResultCarriesExitCodeAndDiff`, `filesOlderThanThirtyDaysAreSkipped`, `indexSurvivesRestartWithoutRereading` (un segundo `ClaudeTranscripts` con el mismo `indexFile` no relee: offsets iguales);
  - contrato.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(observatory): read Claude transcripts incrementally`.

### Task 8: `ClaudeSessionRegistry`

**Files:**
- Create: `Packages/ClaudeTelemetryAdapter/Sources/ClaudeTelemetryAdapter/ClaudeSessionRegistry.swift`
- Test: `ClaudeSessionRegistryTests.swift`, el contrato `LiveAgentsContract`

**Interfaces:**
- Consumes: T4 (`LiveAgents`, `RunningAgent`), los fixtures `sessions/` de T6.
- Produces: `public struct ClaudeSessionRegistry: LiveAgents`, con `init(claudeHome: URL, processes: ProcessProbe)`:
  - `ProcessProbe` es un protocolo interno con `isAlive(pid:)` y `startTime(pid:) -> String?`. La implementación real usa `kill(pid, 0)` y `proc_pidinfo(PROC_PIDTBSDINFO)`, y formatea la hora igual que `procStart`; el formato se verifica en este paso contra un `sessions/<pid>.json` real (solo lectura).
  - Lee solo archivos `*.json` del directorio y nunca abre los que acaban en `.key`.

- [ ] **Step 1: Pruebas que fallan:**
  - `liveSessionIsReturned`, `deadPidIsSkipped`, `reusedPidWithOtherStartIsSkipped`, `unreadableJsonIsSkipped`;
  - `keyFilesAreNeverOpened`: un `ProcessProbe` falso y un `*.key` sin permiso de lectura; el registro no falla y no lo abre (**C13**);
  - `realProbeMatchesOwnProcessStart`;
  - contrato.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(observatory): list live Claude sessions from the session registry`.

### Task 9: `OllamaAdapter`

**Files:**
- Create: `Packages/OllamaAdapter/` (`Package.swift`, `OllamaLocalModels.swift`, guarda de imports)
- Test: `OllamaLocalModelsTests.swift` con un `URLProtocol` de pruebas; el contrato `LocalModelsContract`

**Interfaces:**
- Consumes: T3 (`LocalModel`, `LocalModelsReport`), T4 (puerto).
- Produces: `public struct OllamaLocalModels: LocalModels`, con `init(baseURL: URL, session: URLSession = .shared)`:
  - `GET /api/ps` y `/api/tags`, 500 ms de espera por petición;
  - un fallo de red, de estado HTTP o de JSON en `ps` da `.unavailable`; si solo falla `tags`, `onDisk` queda vacío;
  - los modelos cargados no se repiten en `onDisk`.

- [ ] **Step 1: Pruebas que fallan:** `loadedModelsComeFromPs`, `onDiskExcludesLoaded`, `missingContextLengthIsNil`, `connectionRefusedIsUnavailable` (URL a un puerto sin servidor), `slowServerTimesOutUnavailable` (> 500 ms), `badJsonIsUnavailable`, contrato.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(observatory): read local models from the Ollama API`.

### Task 10: `DarwinMetricsAdapter`

**Files:**
- Create: `Packages/DarwinMetricsAdapter/` (`Package.swift`, `DarwinSystemMetrics.swift`, `CPUTicks.swift`, `GPUUtilization.swift`, `MemoryReader.swift`, `MachineName.swift`, guarda de imports)
- Test: `DarwinSystemMetricsTests.swift`

**Interfaces:**
- Consumes: T3 (`SystemSample`, `Measurement`, `MemoryPressure`), T4 (puerto).
- Produces: `@MainActor public final class DarwinSystemMetrics: SystemMetrics`, con `init()`:
  - CPU por diferencia de ticks con la muestra anterior; la primera muestra devuelve `.unavailable`;
  - GPU desde IOKit (`IOServiceMatching("IOAccelerator")` → `PerformanceStatistics` → `Device Utilization %`);
  - memoria según la spec; `agentsMemory` como suma de `ri_phys_footprint` de los PID dados, saltando los que fallan;
  - nombre del Mac: `product-name` de `IOPlatformExpertDevice` (datos con un `\0` al final), y si no está, `machdep.cpu.brand_string`. El paso 3 anota en el ledger qué devuelve este Mac.
  - El cálculo de cada lectura se separa en funciones puras (`CPUTicks.usage(previous:current:)`, `MemoryReader.used(pages:pageSize:)`, `MemoryPressure(level:)`), probadas con valores fijos.

- [ ] **Step 1: Pruebas que fallan:**
  - con valores fijos: `cpuUsageFromTickDeltas`, `firstCpuSampleIsUnavailable`, `usedMemoryAddsActiveWiredCompressed`, `pressureLevelsMapToNormalMediaAlta`, `unknownPressureLevelIsUnavailable`, `productNameTrimsTrailingNull`;
  - con el adaptador real: `realSampleIsInRange` (CPU y GPU entre 0 y 100 o `.unavailable`; memoria usada ≤ total; nombre no vacío), `ownProcessFootprintIsPositive`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(observatory): sample CPU, GPU and memory without privileges`.
- [ ] **Step 6: Cierre del bloque 2:** revisión del diff del bloque (revisor nuevo), correcciones y `progress.md`.

---

## Bloque 3 · App

### Task 11: Composición, refresco, barra de estado y cabecera

**Files:**
- Create: `App/Smalti/Observatory/ObservatoryRefresher.swift`
- Modify: `App/Smalti/{AppComposition,TilingController,StatusBarView,PaneHeaderView}.swift`, `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Workspace/PresentationText.swift` (`PaneHeaderContent` gana `model: String?` y `context: ContextLoad?`), `Domain/Theme/Theme+Obsidian.swift` (tokens de la barra derecha y de la barra de contexto 44 × 4), el proyecto de Xcode (tres paquetes nuevos)
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/PresentationTextTests.swift` (cabecera con modelo y contexto)

**Interfaces:**
- Consumes: T3 (`StatusFigures`, `PaneAgentDetail`), T4 (`ObserveAgents`, `LaunchSettings`), T7–T10 (adaptadores).
- Produces:
  - `AppComposition` crea `ClaudeTranscripts(claudeHome:indexFile: <estado>/observatory/index.json, now:)`, `ClaudeSessionRegistry`, `OllamaLocalModels(baseURL: settings.ollamaURL)` y `DarwinSystemMetrics`, y los pasa a `ObserveAgents`.
  - `@MainActor final class ObservatoryRefresher`:
    - `init(observe: ObserveAgents, panes: @escaping () -> [PaneAgent], onSnapshot: @escaping (ObservatorySnapshot) -> Void)`;
    - `func start()`;
    - `var isObservatoryOpen: Bool` (el periodo pasa de 10 s a 2 s);
    - `func refreshNow()`, que el cableado del IPC llama con `Stop`, `PostToolUse` y `SessionStart`;
    - nunca hay dos refrescos a la vez: uno pedido durante otro se encola una sola vez;
    - los estados desconocidos se registran con `Logger` una vez cada uno;
    - `lastError` va a la barra de estado como mensaje transitorio.
  - `StatusBarView.render(_ state: TilingState, figures: StatusFigures?)`: lado derecho a 11 px, separación de 16 px, `hoy … tokens` en `#c3c7cf`, con el identificador de accesibilidad `smalti.statusFigures`.
  - `PaneHeaderContent.directory` gana ` · <familia>`. `detail` sigue igual en espera y en error; en trabajando, `ctx N%` y la barra van antes del tiempo de vida (identificador `smalti.paneContext`).

- [ ] **Step 1: Pruebas que fallan:** `headerDirectoryGainsModelFamily`, `workingHeaderShowsContextBeforeLifetime`, `waitingHeaderHidesContext`, `headerWithoutAgentIsUnchanged`.
- [ ] **Step 2–4:** Rojo → implementar → verde (SmaltiCore, `xcodebuild … build`, lint).
- [ ] **Step 5:** Commit `feat(app): wire the observatory sources, status figures and pane context`.

### Task 12: Vista del Observatorio

**Files:**
- Create: `App/Smalti/Observatory/{ObservatoryView,SummaryCardsView,SessionTableView,ActivityView,OutputChartView,LocalModelsView,SystemView,Sparkline}.swift`
- Modify: `Domain/Theme/Theme+Obsidian.swift` (grupo `observatory`, con los valores del tablero)

**Interfaces:**
- Consumes: T3 (`ObservatoryReport`, `LocalModelsReport`, `SystemSample`, historias).
- Produces:
  - `@MainActor final class ObservatoryView: NSView`, con `func show(_ report: ObservatoryReport, snapshot: ObservatorySnapshot, period: ObservatoryPeriod)` y `var onSelect: (String) -> Void`.
  - Composición y medidas según el tablero y la sección UI de la spec:
    - rejilla de dos columnas (`1fr` y 330 pt), separación de 12 pt, relleno de 14 pt;
    - cuatro tarjetas de radio 11; una tarjeta en "leyendo transcripts…" cuando `!summary.isComplete`;
    - `SessionTableView` sobre `NSTableView` con filas de 44 pt, las columnas de la spec y la selección con brillo y barra de 2 pt de acento;
    - el gráfico se dibuja con `NSBezierPath` (sin Charts) con el pico marcado;
    - las curvas de 300 × 34 se dibujan con `Sparkline`;
    - la barra de memoria es segmentada.
  - Identificadores de accesibilidad: `smalti.observatory`, `smalti.observatory.card.{sessions,input,output,cost}`, `smalti.observatory.table`, `smalti.observatory.row.<sessionID>`, `smalti.observatory.activity`, `smalti.observatory.chart`, `smalti.observatory.localModels`, `smalti.observatory.system`, `smalti.observatory.period`.

- [ ] **Step 1:** Prueba que falla: `ObservatoryTests.testShowsCardsRowsDetailAndSystemFromFixture` (XCUITest con `-SmaltiClaudeHome` del fixture de T14). Comprueba los textos exactos de las tarjetas calculados para el fixture, el número de filas, la actividad de la primera fila, "Ollama no está corriendo" y "Sistema · …". Las fechas del fixture se reescriben al copiarlo, así que caen en "hoy".
- [ ] **Step 2–4:** Rojo → implementar → verde, con el diario intacto.
- [ ] **Step 5:** Commit `feat(app): draw the observatory`.

### Task 13: Presentación, teclado y ⌘K

**Files:**
- Create: `App/Smalti/Observatory/ObservatoryController.swift`
- Modify: `App/Smalti/{KeyRouter,TilingController,SmaltiWindow}.swift`

**Interfaces:**
- Consumes: T4 (`CommandID.observatoryToggle`, `.observatoryPeriod`), T11 (`ObservatoryRefresher`), T12 (`ObservatoryView`).
- Produces:
  - `@MainActor final class ObservatoryController`, con `func toggle()`, `func cyclePeriod()`, `var isOpen: Bool` y `func jumpToSelectedPane() -> PaneID?`.
    - Cubre todo el contenido de la ventana con un fundido de 150 ms (sin animación si `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`).
    - Al cerrar devuelve el foco al panel anterior.
    - ↑↓ seleccionan, ↵ salta al panel (cierra y enfoca) si la fila tiene `pane`, y esc cierra.
  - `KeyRouter`: `observatory.toggle` siempre; `observatory.period` solo si `isOpen`; si no, el evento sigue a la terminal.
  - ⌘K "Abrir observatorio" llama a `toggle()`.

- [ ] **Step 1: Pruebas que fallan** (XCUITest): `testCommandShiftATogglesObservatory`, `testEscapeClosesAndRefocusesPane`, `testPaletteOpensObservatory`, `testCommandPCyclesPeriodOnlyWhenOpen` (cerrado, ⌘P no cambia nada y el panel recibe la tecla: el contenido del panel no cambia por un comando), `testArrowsMoveSelectionAndDetailFollows`, `testReturnJumpsToPaneOfSelectedSession`.
- [ ] **Step 2–4:** Rojo → implementar → verde, con el diario intacto.
- [ ] **Step 5:** Commit `feat(app): open the observatory with ⌘⇧A and drive it from the keyboard`.

### Task 14: UI tests de datos, aislamiento y capturas

**Files:**
- Create: `App/SmaltiUITests/Fixtures/claude-home/` (fixtures sintéticos de T6 más uno real, con los timestamps reescritos a "hoy" al copiarlos), `App/SmaltiUITests/ObservatoryTests.swift` (amplía la de T12)
- Modify: `App/SmaltiUITests/{IsolatedApp,DesignCaptureTests}.swift`

**Interfaces:**
- Consumes: T11–T13.
- Produces:
  - `isolatedSmalti(claudeHome: URL? = nil)` pasa `-SmaltiClaudeHome` (un directorio temporal vacío por defecto) y `-SmaltiOllamaURL http://127.0.0.1:1`.
  - El helper `copyClaudeFixture(shiftingTimestampsTo: Date)` reescribe cada `timestamp` sumando el desfase y guarda el `.jsonl` en el `claudeHome` temporal.

- [ ] **Step 1: Pruebas que fallan:**
  - `testStatusBarShowsRamGpuAndTodayTokens` (**C9**);
  - `testPaneHeaderShowsModelAndContextForHookedSession`: hooks de F2 con el `session_id` del fixture a través del CLI real, y luego `· haiku` y `ctx N%` en `smalti.paneHeader` (**C9**);
  - `testUnavailableValuesAreNeverZero`: Ollama sin servidor y un precio ausente; la tarjeta de costo dice "sin precio para 1 modelos" ("1 modelo" en singular) (**C7**);
  - `testEmptyClaudeHomeShowsNoRowsAndZeroTokens`.
  - `DesignCaptureTests.testCaptureObservatory`, a demanda.
- [ ] **Step 2–4:** Rojo → implementar → verde. Suite de XCUITest completa con `check-daily-untouched.sh` (**C14**).
- [ ] **Step 5:** Commit `test(app): cover the observatory end to end with isolated Claude data`.
- [ ] **Step 6: Cierre del bloque 3:** revisión del diff del bloque (revisor nuevo), correcciones y `progress.md`.

---

## Bloque 4 · Cierre de fase

### Task 15: Mediciones, checklist, revisión final, mutación y PR

**Files:**
- Create: `scripts/measure-observatory.sh`, `docs/specs/F3-checklist.md`, `docs/specs/F3-assets/` (capturas y superposiciones)

- [ ] **Step 1: C10.**
  - `measure-observatory.sh 5` lanza el Release con `env -i` y un estado temporal; los transcripts reales se leen solo para leer.
  - Mide con signposts `observatory.index.start` / `observatory.index.today` (≤ 5 s) y `observatory.refresh` sin cambios (≤ 50 ms), 5 corridas.
- [ ] **Step 2: C11.** `LatencyProbe` durante 60 s con el Observatorio abierto: 0 retrasos > 16 ms atribuibles al refresco.
- [ ] **Step 3: C12.** Captura del Observatorio, de la barra de estado y de una cabecera con `ctx`, superpuestas al 50 % sobre los tableros renderizados con Chrome (método de la nota del KB); las desviaciones van al checklist.
- [ ] **Step 4:**
  - checklist C1–C15 con evidencia y desviaciones;
  - `docs/ROADMAP.md`, sección F3 cerrada;
  - `progress.md`;
  - tarjeta del KB de smalti actualizada (estado: F3 cerrado);
  - nota del KB sobre el formato de los transcripts y la deduplicación por `message.id` (con `kb-capture`).
- [ ] **Step 5:** Revisión de la rama completa, con un revisor nuevo en el modelo más capaz, y una sola tanda de correcciones, cada una RED→GREEN.
- [ ] **Step 6:**
  - mutación de `SmaltiCore` ≥ 80 % (**C15**), con los sobrevivientes muertos con prueba nueva;
  - todas las suites en verde con su código de salida: SmaltiCore, GhosttyAdapter, TOMLConfigAdapter, FileSessionAdapter, ClaudeHarnessAdapter, IPCAdapter, UserNotificationsAdapter, ClaudeTelemetryAdapter, OllamaAdapter, DarwinMetricsAdapter, XCUITest, lint;
  - el oráculo en verde.
- [ ] **Step 7:**
  - **Lista completa de decisiones del ledger para Simón, antes de borrar el ledger;**
  - PR `feature/f3-observatory` → `develop` y PR `develop` → `main`, con capturas, lista de decisiones y textos nuevos;
  - se fusiona solo con la confirmación de Simón;
  - Release construido para que Simón lo copie a `/Applications` con el diario cerrado.

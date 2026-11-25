# F7 · Extras — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (modo nativo, `.claude/rules/workflow.md`). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** layouts compartibles como archivo JSON portátil y un receptor OTLP en `127.0.0.1` cuya telemetría de Claude Code sale en el detalle del Observatorio.

**Architecture:** dominio puro en `SmaltiCore` (`SharedLayout`, `TelemetryLedger`, casos de uso `ExportLayout`, `ImportLayout`, `CollectTelemetry`) con tres puertos nuevos (`LayoutFiles`, `TelemetryReceiver`, `ClaudeTelemetrySettings`). Adaptadores: paquete nuevo `OTLPReceiverAdapter` (socket TCP propio), `SharedLayoutFiles` en `FileSessionAdapter`, `ClaudeSettingsTelemetryCheck` en `ClaudeTelemetryAdapter`. La app solo conecta, pinta y abre paneles del sistema.

**Tech Stack:** Swift 6 (concurrencia estricta), Swift Testing, XCUITest, sockets BSD + `DispatchSource`, `JSONDecoder`/`JSONSerialization`, Python 3 para el emisor falso.

**Spec:** `docs/specs/F7-extras.md`

## Global Constraints

- `SmaltiCore` sin AppKit, SwiftUI, Combine, Darwin sockets ni SDKs; Foundation solo para tipos de valor. La guarda de imports no se toca.
- Solo `OTLPReceiverAdapter` abre sockets TCP; liga a `INADDR_LOOPBACK` (`127.0.0.1`), puerto 0, nunca `INADDR_ANY` ni IPv6.
- Variables inyectadas exactas (spec, «Variables que reciben los paneles»): `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_METRICS_EXPORTER=none`, `OTEL_TRACES_EXPORTER=none`, `OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/json`, `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://127.0.0.1:<puerto>/v1/logs`, `OTEL_EXPORTER_OTLP_LOGS_HEADERS=Authorization=Bearer <token>`, `OTEL_LOGS_EXPORT_INTERVAL=5000`.
- Límites del receptor: cuerpo 4 MB (413), 16 conexiones, 30 s de silencio; códigos 200/400/401/404/405/411/413/415.
- Límites de layouts: 1–9 paneles, archivo ≤ 256 KB, `smaltiLayout` = 1, extensión `.smalti-layout.json`.
- Telemetría: últimas 200 duraciones por sesión, tope de 200 sesiones.
- Textos de interfaz en español, tal cual la spec («Textos nuevos»). Código, archivos y commits en inglés, Conventional Commits con el trailer de la sesión.
- Errores tipados con operación, dato y causa; sin `!`, `try!`, `as!` ni `unsafe*` sin comentario; lo inseguro solo en adaptadores.
- Pruebas: nunca `~/.claude`, `~/.config/smalti` ni `/Library/Application Support/ClaudeCode` reales; nunca un Claude real; shell `/bin/zsh -f`; UI por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID`; una sola corrida de `scripts/test-ui.sh` a la vez.
- `swift format lint --strict` con la línea de `CLAUDE.md` (más `Packages/OTLPReceiverAdapter`).

## Review Focus

1. **Petición HTTP partida en varios `read`** (cabeceras en un paquete, cuerpo en tres): el receptor acumula hasta `Content-Length` y entrega un solo lote → prueba `assemblesRequestSplitAcrossReads` en T5.
2. **Dos peticiones seguidas en el mismo búfer (pipelining)**: se responden las dos, en orden → `answersTwoPipelinedRequests` en T5.
3. **Layout con raíz `~` cuyo home difiere** (exportado en `/Users/a`, importado en `/Users/b`): la raíz se resuelve con el home de esta máquina, no con la ruta original → `importResolvesTildeWithThisHome` en T1.
4. **Nombre del archivo importado distinto del `name` interno** (`copia.smalti-layout.json` con `"name": "solen-dev"`): manda `name`; el nombre de archivo no importa → `importUsesInternalName` en T2.
5. **Apagar `[extras] otlp` con emisores vivos**: el receptor se detiene, sus conexiones se cierran y el ledger conserva lo recibido; encender de nuevo da puerto y token nuevos → `reconfigureStopsAndRestarts` en T4 y `stopClosesOpenConnections` en T5.

---

## Bloque 1 · Dominio

### Task 1: `SharedLayout`

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Session/SharedLayout.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Session/SharedLayoutTests.swift`

**Interfaces:**
- Consumes: `WorkspaceSnapshot`, `PaneSnapshot`, `SnapshotTree`, `LayoutName`, `HarnessID`, `EditorPosition`, `RelaunchCommand.isTypeable`, `LayoutID`.
- Produces:
  - `public struct SharedLayout: Codable, Equatable, Sendable { smaltiLayout: Int; name: String; root: String; layout: String; focused: Int?; tree: SnapshotTree?; panes: [SharedPane] }` (claves JSON = nombres de propiedad).
  - `public struct SharedPane: Codable, Equatable, Sendable { directory: String; command: [String]?; harness: HarnessID?; editor: SharedEditor? }`, `public struct SharedEditor: Codable, Equatable, Sendable { file: String; line: Int }`.
  - `public init(exporting snapshot: WorkspaceSnapshot, named name: LayoutName, home: String)`.
  - `public func validated() throws(SharedLayoutError) -> ValidatedLayout` — `ValidatedLayout { name: LayoutName; layout: SharedLayout; warnings: [SharedLayoutWarning] }`.
  - `public func resolvedRoot(home: String) -> String` (expande `~`).
  - `public func workspaceSnapshot(root: String, layouts: LayoutCatalog) -> WorkspaceSnapshot` (UUIDs nuevos, scrollback 0, harness desconocido → shell, layout desconocido → `dwindle`).
  - `public enum SharedLayoutError: Error, Equatable, Sendable { case unsupportedFormat(Int), invalidName(String, reason: String), paneCount(Int), treeMismatch(leaves: Int, panes: Int), untypeableCommand(pane: Int), emptyCommand(pane: Int), escapingDirectory(pane: Int, path: String), tooLarge(bytes: Int), notJSON(reason: String) }` con `var message: String` en español («formato 2 no compatible», «tiene 12 paneles; el máximo es 9»…).
  - `public enum SharedLayoutWarning: Equatable, Sendable { case unknownHarness(pane: Int, name: String), unknownLayout(String) }`.
  - `public static let maximumBytes = 262_144`, `formatVersion = 1`, `maximumPanes = 9`.

- [ ] **Step 1: Write the failing tests** (Swift Testing, AAA):
  - `exportDropsIdentityAndHistory` — un `WorkspaceSnapshot` con `id`, `sessionID`, `title`, `processName`, `scrollbackLines: 900` → el JSON codificado no contiene la cadena del UUID, del `sessionID`, `"title"`, `"processName"` ni `"scrollbackLines"`.
  - `exportWritesRootWithTilde` — root `/Users/simon/Projects/solen`, home `/Users/simon` → `root == "~/Projects/solen"`; root `/opt/x` → `"/opt/x"`; root igual al home → `"~"`.
  - `exportWritesDirectoriesRelativeToRoot` — panes en root → `"."`, en `root/api` → `"api"`, en `/Users/simon/other` → `"~/other"`, en `/tmp/y` → `"/tmp/y"`.
  - `exportKeepsCommandHarnessAndEditor` — relaunch `["pnpm","dev"]` → `command`; agente Claude con sesión → `harness == .claude`, `command == nil`; editor `root/src/a.ts` línea 42 → `SharedEditor(file: "src/a.ts", line: 42)`.
  - `roundTripRestoresTreeLayoutFocusAndPanes` — exportar → `workspaceSnapshot(root:)` → mismo `tree`, `layout`, `focusedIndex`, directorios absolutos, relaunch, `agent?.harness`, `editor`.
  - Validación, un test por motivo con su valor límite: `rejectsFormatTwo`, `rejectsInvalidName` (`"a/b"`), `rejectsZeroPanes`, `acceptsNinePanes`, `rejectsTenPanes`, `rejectsTreeWithOtherLeafCount`, `rejectsEmptyCommand` (`[]`), `rejectsUntypeableCommand` (`["echo","a\nb"]`), `rejectsParentEscape` (`"../x"`, `"a/../../x"`), `acceptsDotDotInsideName` (`"a..b"`).
  - `unknownHarnessWarnsAndBecomesShell`, `unknownLayoutWarnsAndBecomesDwindle`.
  - `importResolvesTildeWithThisHome` (Review Focus 3).
  - `errorMessagesAreSpanish` — cada caso tiene `message` no vacío y distinto.
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore --filter SharedLayout` → FAIL (tipos no existen).
- [ ] **Step 3:** Implementar en `SharedLayout.swift`. Hojas del árbol: reutilizar el recuento de `SnapshotTree` (si no hay helper, añadir `var leafCount: Int` en `SnapshotTree.swift`). La decodificación de `HarnessID` desconocido no puede fallar: `SharedPane.harness` se decodifica como `String` y se mapea en `validated()` (guardar `harnessName: String?` en el `Codable` y exponer `harness: HarnessID?` calculado).
- [ ] **Step 4:** misma orden → PASS; `swift test --package-path Packages/SmaltiCore` completo en verde.
- [ ] **Step 5:** Commit `feat(core): add portable shared layout format`.

### Task 2: `ExportLayout`, `ImportLayout`, puerto `LayoutFiles` y ⌘K

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/ShareLayoutCommands.swift`
- Modify: `Packages/SmaltiCore/Sources/SmaltiCore/Application/SessionArchive.swift` (puerto), `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Config/CommandID.swift`, `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Commands/CommandCatalog.swift`, `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/InMemorySessionArchive.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Session/ShareLayoutTests.swift`, `.../Commands/CommandCatalogTests.swift` (añadir)

**Interfaces:**
- Consumes: Task 1, `NamedLayouts`, `NamedLayoutSummary`.
- Produces:
  - `public protocol LayoutFiles: AnyObject { func write(_ layout: SharedLayout, to file: URL) throws(LayoutFileError); func read(from file: URL) throws(LayoutFileError) -> SharedLayout }` (`@MainActor`), `public enum LayoutFileError: Error, Equatable, Sendable { case unreadable(path: String, reason: String), unwritable(path: String, reason: String), invalid(SharedLayoutError) }` con `message`.
  - `public final class InMemoryLayoutFiles: LayoutFiles` (test support; `files: [URL: SharedLayout]`, `failing: Set<URL>`).
  - `@MainActor public struct ExportLayout { init(layouts: any NamedLayouts, files: any LayoutFiles, home: String); func execute(_ name: LayoutName, to file: URL) throws(LayoutFileError) }`.
  - `public struct ImportPreview: Equatable, Sendable { name: LayoutName; commands: [String]; root: String; isRootPresent: Bool; warnings: [SharedLayoutWarning]; layout: SharedLayout }` — `commands` son los textos que se ejecutarán (`RelaunchCommand.displayText`, `"<harness> --continue"` vía `continueCommand` del registro, `nvim +N <archivo>`).
  - `@MainActor public struct ImportLayout { init(layouts: any NamedLayouts, files: any LayoutFiles, harnesses: HarnessRegistry, home: String, directoryExists: @Sendable (String) -> Bool); func preview(_ file: URL) throws(LayoutFileError) -> ImportPreview; func confirm(_ preview: ImportPreview, root: String) throws(SessionArchiveError) -> LayoutName }`.
  - `ImportTexts.confirmationTitle(_:)`, `ImportTexts.confirmationBody(_:)` («Al abrirlo ejecutará: a · b» / «Al abrirlo solo abrirá shells.»; los avisos se añaden en otra línea: «El panel 2 usa un harness desconocido (x): se abrirá como shell.», «Layout desconocido (y): se usará Dwindle.»), `ImportTexts.folderPrompt(_:)`.
  - `CommandID.layoutImport` (`"layout.import"`, en `allStandard`, título «Importar layout…»), `CommandID.layoutExport(_ name: LayoutName)` (`"layout.export:<nombre>"`), `NamedLayoutCommand.export(LayoutName)`; `CommandCatalog` añade por cada layout guardado «Exportar layout “<nombre>”…» justo después de su «Restaurar», y «Importar layout…» en el grupo `.workspaces`.

- [ ] **Step 1: Write the failing tests:**
  - `exportWritesSavedLayoutToFile` (`InMemoryLayoutFiles` tiene el `SharedLayout` esperado), `exportOfMissingLayoutThrowsNotFound`, `exportWriteFailureIsTyped`.
  - `previewListsEveryCommand` — panes con `pnpm dev`, harness claude, editor línea 42, shell → `commands == ["pnpm dev", "claude --continue", "nvim +42 src/a.ts"]`.
  - `previewOfShellsOnlyHasNoCommands`, `previewReportsMissingRoot`, `previewPropagatesValidationError`.
  - `confirmSavesUnderInternalName`, `importUsesInternalName` (Review Focus 4), `confirmPicksFreeName` (existen «solen-dev» y «solen-dev 2» → «solen-dev 3»), `confirmUsesChosenRoot`.
  - `confirmationBodyTexts` (con comandos, sin comandos, con avisos).
  - Catálogo: `catalogOffersExportPerSavedLayout`, `catalogOffersImport`, `layoutExportRoundTripsThroughCommandID`.
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore --filter "ShareLayout|CommandCatalog"` → FAIL.
- [ ] **Step 3:** Implementar. El nombre libre: probar `name`, `"\(name) 2"`, … contra `NamedLayouts.names()` comparando sin distinguir mayúsculas (APFS); si el sufijo pasa de 60 caracteres, recortar la base.
- [ ] **Step 4:** suite completa de `SmaltiCore` en verde (incluidas las de ayuda y menús que recorren `allStandard`; si una exige menú para `layoutImport`, se añade en T9 y aquí la tabla de títulos).
- [ ] **Step 5:** Commit `feat(core): export and import shared layouts`.

### Task 3: Dominio de la telemetría

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Telemetry/TelemetryEvent.swift`, `SessionTelemetry.swift`, `TelemetryLedger.swift`, `TelemetryEnvironment.swift`, `TelemetryTexts.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Telemetry/*.swift`

**Interfaces:**
- Produces:
  - `public enum TelemetryEvent: Equatable, Sendable { case apiRequest(APIRequest), apiError(APIError) }`; `APIRequest { sessionID: String; sequence: Int?; at: Date; model: String?; durationMilliseconds: Int; costMicroUSD: Int }`; `APIError { sessionID: String; sequence: Int?; at: Date; model: String?; statusCode: Int? }`.
  - `public struct SessionTelemetry: Equatable, Sendable { since: Date; requests: Int; errors: Int; errorsByStatus: [Int: Int]; costMicroUSD: Int; var medianMilliseconds: Int? }` — mediana de las últimas `recentDurationLimit = 200`.
  - `public struct TelemetryLedger: Equatable, Sendable { mutating func record(_ events: [TelemetryEvent]); func telemetry(of sessionID: String) -> SessionTelemetry?; var isEmpty: Bool; static let sessionLimit = 200 }` — duplicado = misma sesión y mismo `sequence` no nulo; al superar 200 sesiones descarta la de `lastEventAt` más antigua.
  - `public struct TelemetryEndpoint: Equatable, Sendable { port: UInt16; token: String }`.
  - `public enum TelemetryEnvironment { static func variables(for endpoint: TelemetryEndpoint) -> [String: String] }` — exactamente las 8 variables de Global Constraints.
  - `public enum TelemetryTexts { static func line(_ t: SessionTelemetry, timeZone: TimeZone) -> String }` — «Telemetría · desde 10:42 · 42 peticiones · mediana 1,4 s · 2 errores de API · $3.12 según Claude Code»; «1 petición», «sin errores de API», «1 error de API», mediana < 1000 ms → «mediana 820 ms», ≥ 1000 → una decimal con coma; sin duraciones → se omite el tramo de mediana; costo con `ObservatoryFormat` existente de dólares si lo hay (dos decimales, punto, como `$18.40` del tablero).

- [ ] **Step 1: Write the failing tests:** `ledgerCountsRequestsAndCost`, `ledgerCountsErrorsByStatus`, `ledgerIgnoresRepeatedSequence`, `ledgerKeepsEventsWithoutSequence`, `ledgerSinceIsFirstEvent`, `medianOfOddAndEven` (1, 2, 200, 201 duraciones: solo las 200 últimas), `ledgerDropsOldestSessionPast200`, `environmentHasExactlyEightVariables` (diccionario literal completo con puerto 4318 y token `"t"`), `endpointUsesLoopbackLiteral` (la URL empieza por `http://127.0.0.1:`; parte de C1), `lineTexts` (casos: plural, singular, sin errores, 1 error, ms, s, sin mediana, costo 0 → «$0.00»).
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS y suite completa.
- [ ] **Step 5:** Commit `feat(core): fold Claude Code telemetry events per session`.

### Task 4: `[extras]`, puertos, `CollectTelemetry`, entorno de los paneles y Observatorio

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Config/ExtrasSettings.swift`, `Packages/SmaltiCore/Sources/SmaltiCore/Application/TelemetryPorts.swift`, `.../Application/CollectTelemetry.swift`, `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/FakeTelemetryReceiver.swift`, `Packages/TOMLConfigAdapter/Sources/TOMLConfigAdapter/ExtrasReader.swift`
- Modify: `SmaltiConfig.swift` (`public var extras = ExtrasSettings.standard`), `TOMLConfigParser.swift` (tabla `extras`), `PaneFileLocator.swift` (`PaneEnvironment`), `ObservatorySnapshot.swift`, `ObservatoryReport.swift`, `ObservatoryTexts.swift`
- Test: `SmaltiCoreTests/Telemetry/CollectTelemetryTests.swift`, `SmaltiCoreTests/Observatory/ObservatoryTelemetryTests.swift`, `SmaltiCoreTests/PaneEnvironmentTests.swift` (añadir), `TOMLConfigAdapterTests/ExtrasReaderTests.swift`

**Interfaces:**
- Produces:
  - `public struct ExtrasSettings: Equatable, Sendable { var otlp: Bool; static let standard = ExtrasSettings(otlp: true) }`; TOML `[extras] otlp` con `section.flag("otlp")`, claves desconocidas rechazadas.
  - `public protocol TelemetryReceiver: AnyObject { func start() throws(TelemetryReceiverError) -> TelemetryEndpoint; func stop(); var batches: AsyncStream<[TelemetryEvent]> { get } }` (`@MainActor`; `batches` es un stream nuevo por cada `start`). `public enum TelemetryReceiverError: Error, Equatable, Sendable { case cannotListen(operation: String, errno: Int32) }` con `message`.
  - `public protocol ClaudeTelemetrySettings: Sendable { func isConfiguredByUser() -> Bool }`.
  - `public enum TelemetryStatus: Equatable, Sendable { case off, configuredByUser, listening(TelemetryEndpoint), failed(String) }`.
  - `@MainActor public final class CollectTelemetry { init(receiver: any TelemetryReceiver, settings: any ClaudeTelemetrySettings); func apply(_ extras: ExtrasSettings); var status: TelemetryStatus { get }; var ledger: TelemetryLedger { get }; func currentVariables() -> [String: String]; var onChange: (() -> Void)? }` — `apply` arranca, detiene o no hace nada según el estado; `currentVariables()` solo con `.listening`.
  - `PaneEnvironment` gana `telemetry: (any TelemetryVariablesSource)?` con `@MainActor public protocol TelemetryVariablesSource: AnyObject { func currentVariables() -> [String: String] }` (lo cumple `CollectTelemetry`); en `variables(for:)` se mezclan después de `extra` y antes de las de `SMALTI`.
  - `ObservatorySnapshot` gana `public private(set) var telemetry = TelemetryLedger()` y `telemetryStatus: TelemetryStatus = .off` con `func adding(telemetry: TelemetryLedger, status: TelemetryStatus) -> ObservatorySnapshot`; `ObservatoryReport.Detail` gana `telemetry: String?`; `ObservatoryReport` gana `footnote: String` (`ObservatoryTexts.footnote(hasTelemetry:status:)`; textos exactos de la spec).
  - `FakeTelemetryReceiver` (registra `start`/`stop`, `failNextStart`, `send(_ events:)`).

- [ ] **Step 1: Write the failing tests:**
  - `extrasDefaultsToOtlpOn`, `extrasReadsFalse`, `extrasRejectsNonBoolean`, `extrasRejectsUnknownKey`.
  - `applyOnStartsAndListens`, `applyOffStopsAndClearsVariables`, `configuredByUserNeverStarts`, `startFailureReportsFailedAndNoVariables`, `reconfigureStopsAndRestarts` (Review Focus 5: on → off → on llama `start` dos veces y conserva el ledger), `batchesFoldIntoLedgerAndNotify`.
  - `paneEnvironmentAddsTelemetryVariables`, `paneEnvironmentWithoutListeningAddsNone`, `smaltiVariablesStillWin`.
  - `detailShowsTelemetryLineForSessionWithEvents`, `detailWithoutEventsHasNoLine`, `columnsAndSummaryUnchangedByTelemetry` (mismo `Summary` y `rows` con y sin ledger), `footnoteVariants` (sin telemetría = texto F6 exacto; con eventos; `configuredByUser`).
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore` y `--package-path Packages/TOMLConfigAdapter` → FAIL.
- [ ] **Step 3:** implementar; la app (T8) consume `report.footnote` en lugar de `ObservatoryTexts.footnote`.
- [ ] **Step 4:** ambas suites completas en verde.
- [ ] **Step 5:** Commit `feat(core): collect OTLP telemetry and inject it into panes`.

## Bloque 2 · Adaptadores

### Task 5: `OTLPReceiverAdapter` — socket y HTTP

**Files:**
- Create: `Packages/OTLPReceiverAdapter/Package.swift` (como `NeovimAdapter`), `Sources/OTLPReceiverAdapter/LoopbackOTLPReceiver.swift`, `HTTPRequestParser.swift`, `ReceiverConnection.swift`
- Test: `Tests/OTLPReceiverAdapterTests/LoopbackOTLPReceiverTests.swift`, `HTTPRequestParserTests.swift`, `TestHTTPClient.swift`

**Interfaces:**
- Consumes: `TelemetryReceiver`, `TelemetryEndpoint`, `TelemetryReceiverError` (T4); `OTLPLogsDecoder` (T6; en T5 un decodificador inyectado `(Data) throws -> [TelemetryEvent]` para probar sin T6).
- Produces: `@MainActor public final class LoopbackOTLPReceiver: TelemetryReceiver { public init(decode: @escaping @Sendable (Data) throws -> [TelemetryEvent] = OTLPLogsDecoder.decode, idleTimeout: Duration = .seconds(30), maximumConnections: Int = 16, maximumBody: Int = 4 << 20, token: @escaping @Sendable () -> String = randomToken); public var boundAddress: String? }` — `randomToken` = 32 bytes de `SecRandomCopyBytes` en hex. `HTTPRequestParser` (struct puro: `mutating func feed(_ data: Data) -> [ParsedRequest]`, `ParsedRequest { method, path, headers (claves en minúscula), body } | .failure(status: Int)`).

- [ ] **Step 1: Write the failing tests:**
  - **C1:** `listensOnlyOnLoopback` — tras `start`, `boundAddress == "127.0.0.1"` (de `getsockname`); `connectViaLanAddressFails` — primera IPv4 no loopback de `getifaddrs` (si no hay, la prueba se salta con motivo) al mismo puerto → `ECONNREFUSED`; `connectViaIPv6LoopbackFails` (`::1`).
  - **C3:** `acceptsLogsWithToken` (200, cuerpo `{}`, lote entregado), `rejectsMissingToken` (401), `rejectsWrongToken` (401), `unknownPathIs404`, `getIs405`, `gzipIs415`, `missingContentLengthIs411`, `chunkedIs411`, `oversizedBodyIs413` (sin leer el cuerpo entero), `undecodableBodyIs400`, `keepAliveServesThreeRequests`, `answersTwoPipelinedRequests` (Review Focus 2), `assemblesRequestSplitAcrossReads` (Review Focus 1), `idleConnectionClosesAfterTimeout` (timeout inyectado de 200 ms), `seventeenthConnectionIsRefused` (cerrada en cuanto se acepta), `stopClosesOpenConnections` (Review Focus 5), `restartGivesNewPortAndToken`.
  - El cliente de prueba usa sockets bloqueantes con `SO_RCVTIMEO` de 2 s; cada prueba cierra receptor y clientes en `defer`.
- [ ] **Step 2:** `swift test --package-path Packages/OTLPReceiverAdapter` → FAIL.
- [ ] **Step 3:** implementar sobre el patrón de `IPCAdapter/UnixSocketTelemetry.swift`: `socket(AF_INET, SOCK_STREAM)`, `SO_REUSEADDR` no, `SO_NOSIGPIPE`, `bind` a `INADDR_LOOPBACK`, `listen(16)`, `O_NONBLOCK`, `DispatchSource.makeReadSource` por conexión en una cola serie propia; respuestas `HTTP/1.1 <código> <frase>\r\nContent-Type: application/json\r\nContent-Length: N\r\n\r\n{}`. Cada `unsafe`/puntero lleva su comentario de seguridad.
- [ ] **Step 4:** PASS; comprobar que no queda ningún socket del proceso de prueba (`lsof -p` del runner no es accesible: la prueba `stopClosesOpenConnections` lo cubre).
- [ ] **Step 5:** añadir `Packages/OTLPReceiverAdapter` a la línea de `swift format lint` de `CLAUDE.md` y a «Comandos». Commit `feat(otlp): loopback OTLP/HTTP receiver`.

### Task 6: `OTLPLogsDecoder`

**Files:**
- Create: `Packages/OTLPReceiverAdapter/Sources/OTLPReceiverAdapter/OTLPLogsDecoder.swift`
- Create: `Packages/OTLPReceiverAdapter/Tests/OTLPReceiverAdapterTests/Fixtures/{api-request.json,api-error.json,mixed-batch.json,int-as-number.json,body-only-name.json}` (escritos a mano con los atributos verificados de Claude Code 2.1.332; cabecera `"_note": "Claude Code 2.1.332, atributos de RGe/CGe"` no, JSON no admite comentarios: anotar la versión en `Fixtures/README.md`)
- Test: `OTLPLogsDecoderTests.swift`

**Interfaces:**
- Produces: `public enum OTLPLogsDecoder { public static func decode(_ body: Data) throws(OTLPDecodeError) -> [TelemetryEvent] }`, `OTLPDecodeError.notJSON(reason:)` / `.notLogsRequest` (raíz sin `resourceLogs`).

- [ ] **Step 1: Write the failing tests (C4):** `decodesAPIRequest` (todos los campos; `cost_usd_micros` manda sobre `cost_usd`), `costFallsBackToCostUSD` (`0.0123` → 12300), `decodesAPIErrorWithAndWithoutStatus`, `intValueAsStringAndNumber`, `doubleValueDuration` (`1400.6` → 1401), `nameFromBodyWhenEventNameMissing`, `skipsRecordWithoutSessionID`, `skipsOtherEvents` (`user_prompt`, `tool_result`), `skipsRecordWithUnreadableField` (el resto del lote sale), `timestampFromEventTimestampOrTimeUnixNano`, `rejectsNonJSON`, `rejectsJSONWithoutResourceLogs`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar con `JSONSerialization` (atributos heterogéneos). **Step 4:** PASS, conectar `decode` como valor por defecto de T5.
- [ ] **Step 5:** Commit `feat(otlp): decode Claude Code log events`.

### Task 7: `ClaudeSettingsTelemetryCheck` y `SharedLayoutFiles`

**Files:**
- Create: `Packages/ClaudeTelemetryAdapter/Sources/ClaudeTelemetryAdapter/ClaudeSettingsTelemetryCheck.swift`, `Packages/FileSessionAdapter/Sources/FileSessionAdapter/SharedLayoutFiles.swift`
- Test: `ClaudeTelemetryAdapterTests/ClaudeSettingsTelemetryCheckTests.swift`, `FileSessionAdapterTests/SharedLayoutFilesTests.swift`

**Interfaces:**
- Produces:
  - `public struct ClaudeSettingsTelemetryCheck: ClaudeTelemetrySettings { public init(claudeHome: URL, managedSettings: URL = URL(filePath: "/Library/Application Support/ClaudeCode/managed-settings.json")) }` — lee `settings.json` de `claudeHome` y `managedSettings`; cierto si el objeto `env` tiene `CLAUDE_CODE_ENABLE_TELEMETRY` o alguna clave que empiece por `OTEL_`. Archivo ausente o JSON ilegible → no cuenta (y un `Logger` `.private` lo registra).
  - `public final class SharedLayoutFiles: LayoutFiles` — `JSONEncoder` con `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, escritura atómica; lectura que comprueba el tamaño antes de leer (> 256 KB → `.invalid(.tooLarge)`), JSON inválido → `.invalid(.notJSON)`.

- [ ] **Step 1: Write the failing tests:** `noSettingsIsNotConfigured`, `envWithOtelEndpointIsConfigured`, `envWithEnableTelemetryIsConfigured`, `managedSettingsCount`, `otherEnvKeysDoNotCount`, `malformedSettingsDoesNotCount` (todo en directorios temporales); `writesSortedPrettyJSON`, `roundTripsLayout`, `rejectsOversizedFileWithoutReadingIt`, `rejectsNonJSON`, `unwritableDirectoryIsTyped`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** suites completas de los dos paquetes en verde.
- [ ] **Step 5:** Commit `feat(adapters): detect user telemetry config and store shared layouts`.

### Revisión intermedia 1

- [ ] Revisor nuevo sobre `git diff origin/develop...HEAD` (dominio y adaptadores). Corregir en una tanda todos los hallazgos, cada uno con su prueba RED→GREEN.
- [ ] `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore --changed-since origin/develop`; cada sobreviviente con prueba nueva verificada aplicando el mutante a mano.
- [ ] Commit(s) `fix(...)` / `test(core): kill mutation survivors`; marcar en `progress.md`.

## Bloque 3 · App

### Task 8: Telemetría en la app y emisor falso

**Files:**
- Modify: `App/Smalti.xcodeproj/project.pbxproj` (paquete local `OTLPReceiverAdapter`, mismas cinco entradas que `NeovimAdapter`), `App/Smalti/AppComposition.swift`, `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Config/LaunchSettings.swift` (flags), `App/Smalti/Observatory/SideViews.swift` y la vista del detalle (línea bajo la compactación, mismo estilo), `App/SmaltiUITests/` helpers de `isolatedSmalti()`
- Create: `scripts/otlp/fake-claude.py`, `scripts/otlp/test_fake_claude.py`, `App/SmaltiUITests/TelemetryTests.swift`

**Interfaces:**
- Consumes: T4–T7.
- Produces: flags `-SmaltiManagedSettings`, `-SmaltiTelemetryProbe` (`LaunchSettings.managedSettingsKey`, `.telemetryProbeKey`); el probe escribe JSON `{"status":"listening","port":N}` / `{"status":"off"}` / `{"status":"configuredByUser"}` en cada cambio de estado; `fake-claude.py --session <id> --requests N --errors M [--interval s]` lee `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` y `..._HEADERS` del entorno, sale con código 3 si faltan, manda lotes OTLP JSON y termina.

- [ ] **Step 1: Write the failing tests:**
  - `test_fake_claude.py`: `test_exits_3_without_endpoint`, `test_posts_api_request_batch` (servidor HTTP de prueba en 127.0.0.1 que valida ruta, token y forma del cuerpo).
  - `TelemetryTests` (XCUITest, `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiClaudeHome` y `-SmaltiManagedSettings` temporales, config temporal):
    - `testPaneReceivesTelemetryVariables` — escribir `env | grep -E '^(CLAUDE_CODE_ENABLE_TELEMETRY|OTEL_)' | sort > <tmp>` en el panel y comparar con las 8 líneas (puerto del probe).
    - `testFakeClaudeFeedsObservatoryDetail` — en el panel `python3 <repo>/scripts/otlp/fake-claude.py --session <uuid> --requests 3 --errors 1` con un transcript de fixture de esa sesión en el Claude home temporal; ⌘⇧A, seleccionar la sesión → la línea «Telemetría · desde … · 3 peticiones · … · 1 error de API · $… según Claude Code» y el pie con «telemetría de Claude Code».
    - `testOtlpOffInjectsNothing` — config con `[extras] otlp = false` → `env` sin esas variables y probe `off`.
    - `testUserConfiguredTelemetryIsRespected` — `settings.json` temporal con `env.OTEL_EXPORTER_OTLP_ENDPOINT` → probe `configuredByUser`, sin variables, pie con el texto de la spec.
    - `testReloadTurnsReceiverOff` — cambiar el TOML en caliente a `false` y recargar (⌘K «Recargar configuración») → probe `off`; un panel nuevo sin variables.
- [ ] **Step 2:** `cd scripts/otlp && python3 -m unittest test_fake_claude` → FAIL; XCUITest se ve fallar en la corrida de la tanda (paso 4).
- [ ] **Step 3:** implementar: `AppComposition` crea `LoopbackOTLPReceiver`, `ClaudeSettingsTelemetryCheck(claudeHome: settings.claudeHome ?? default, managedSettings: settings.managedSettings ?? default)` y `CollectTelemetry`; `apply(startup.initial.config.extras)` antes de abrir el primer panel; en cada recarga `apply(config.extras)`; `PaneEnvironment(…, telemetry: collector)`; `stop()` en `applicationWillTerminate`; el Observatorio construye el snapshot con `.adding(telemetry: collector.ledger, status: collector.status)` y refresca con `onChange` (sin temporizador nuevo); `.failed` muestra una vez «No se pudo arrancar el receptor de telemetría: <motivo>» en la barra de estado.
- [ ] **Step 4:** `xcodebuild … build`; `SMALTI_DAILY_PID=<pid> scripts/check-daily-untouched.sh "$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh TelemetryTests` → todas ok; comprobar con `ps -axo pid,command | grep fake-claude` que no queda ningún emisor.
- [ ] **Step 5:** Commit `feat(app): receive Claude Code telemetry and show it in the observatory`.

### Task 9: Exportar e importar layouts en la app

**Files:**
- Modify: `App/Smalti/TilingController.swift` (`perform(_ command: NamedLayoutCommand)` gana `.export`; acción `layoutImport`), `App/Smalti/AppComposition.swift` (`SharedLayoutFiles`), `LaunchSettings.swift` (flags), `App/Smalti/StatusMessage.swift` (mensajes), `App/Smalti/Menus/*` y ayuda si la prueba de consistencia lo exige (`layoutImport` en el menú Archivo/Ventana junto a los layouts)
- Create: `App/Smalti/Restore/LayoutSharing.swift` (paneles de guardar, abrir y carpeta, y la alerta; cada uno sustituible por su flag), `App/SmaltiUITests/SharedLayoutTests.swift`

**Interfaces:**
- Consumes: T2, T7.
- Produces: flags `-SmaltiImportFile`, `-SmaltiPickedFolder`, `-SmaltiConfirmImport yes|no` (`LaunchSettings.importFileKey`, `.pickedFolderKey`, `.confirmImportKey`); exportar usa `-SmaltiExportDirectory` (F5) con el nombre `<nombre>.smalti-layout.json`; `StatusMessage` gana `.layoutExported(String)`, `.layoutExportFailed(String, reason:)`, `.layoutImported(String)`, `.layoutImportFailed(reason:)` con los textos de la spec.

- [ ] **Step 1: Write the failing tests** (`SharedLayoutTests`, config y estado temporales, `/bin/zsh -f`):
  - `testExportWritesPortableFile` — guardar layout «solen-dev» con 2 paneles (uno con `sleep 600` en primer plano), ⌘K «Exportar layout “solen-dev”…» → existe `<export>/solen-dev.smalti-layout.json`, contiene `"command" : [ "sleep", "600" ]`, `"root" : "/…"` o `"~…"`, y no contiene el UUID de ningún panel ni el home absoluto.
  - `testImportConfirmsThenAppearsInPalette` — `-SmaltiImportFile` con un fixture de 3 paneles y `-SmaltiConfirmImport yes` → barra «Layout “equipo” importado»; ⌘K lista «Restaurar layout “equipo”»; restaurarlo abre 3 paneles.
  - `testImportCancelSavesNothing` — `-SmaltiConfirmImport no` → ⌘K sin «Restaurar layout “equipo”».
  - `testImportMissingRootAsksFolder` — raíz inexistente + `-SmaltiPickedFolder <tmp>` → al restaurar, el panel abre en `<tmp>` (comprobado con `pwd > archivo`).
  - `testImportInvalidFileReportsReason` — fixture con 10 paneles → barra «No se pudo importar el layout: tiene 10 paneles; el máximo es 9».
  - `testImportTakesFreeName` — importar dos veces → «equipo» y «equipo 2».
- [ ] **Step 2–4:** implementar; una sola corrida `SMALTI_DAILY_PID=<pid> scripts/check-daily-untouched.sh "$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh SharedLayoutTests HelpTests CommandPaletteTests` → todas ok (ayuda y paleta porque cambian sus listas).
- [ ] **Step 5:** Commit `feat(app): export and import shared layouts from the palette`.

### Task 10: Guardas y documentos

**Files:**
- Modify: la prueba de guarda de imports y la de `Logger` (o crear `OTLPReceiverAdapterTests/GuardTests.swift`), `CLAUDE.md`, `docs/PROJECT.md`, `docs/design/README.md`, guarda de aislamiento existente (`HarnessIsolationGuardTests` o equivalente) con `/Library/Application Support/ClaudeCode` y `~/.config/smalti`.

- [ ] **Step 1: Write the failing tests (C9, C10):** `onlyOTLPReceiverOpensTCPSockets` (ningún archivo fuera de `Packages/OTLPReceiverAdapter` contiene `AF_INET`), `loggersNeverPublishTokenOrBodies` (en los archivos nuevos, todo `Logger` con interpolación usa `privacy: .private`), `managedSettingsPathOnlyAsDefaultParameter` (la ruta real solo aparece como valor por defecto en `ClaudeSettingsTelemetryCheck`).
- [ ] **Step 2–4:** RED → GREEN en las suites de los paquetes.
- [ ] **Step 5:** documentos según «Cambios en otros documentos» de la spec. Commit `test(guards): cover OTLP sockets and logs; docs: F7 in project docs`.

### Revisión intermedia 2

- [ ] Revisor nuevo sobre el diff desde la revisión 1 (app). Corregir todo en una tanda con su RED→GREEN (las de app: revertir y recompilar, todas en una sola corrida de UI).
- [ ] Regresión de las clases de UI tocadas en una corrida: `TelemetryTests SharedLayoutTests ObservatoryTests ObservatoryFilterTests CommandPaletteTests HelpTests ChildEnvironmentTests SessionRestoreTests`.
- [ ] Mutación `--changed-since <commit de la revisión 1>` y sobrevivientes muertos a mano.

## Bloque 4 · Cierre

### Task 11: Mediciones, capturas, checklist y revisión final

- [ ] **C2**, todas con la app de Release apagada/encendida vía `[extras] otlp` en un config temporal, 5 corridas cada una, por `check-daily-untouched.sh`:
  - F0 A12: `scripts/bench/throughput.sh 5` dentro de Smalti Dev (OTLP off / on con 3 `fake-claude.py --requests 100000 --interval 5` en otros paneles);
  - F0 A14: memoria (`footprint` del proceso) tras abrir 3 paneles;
  - GPU en reposo: `scripts/measure-gpu-idle.sh 5` con OTLP off / on;
  - F4 C1: `scripts/measure-input.sh 5`; F4 C13: `TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh InputLatencyTests` off / on;
  - layouts: sin coste en reposo (solo actúan al pedirlo); se anota y se mide la memoria con 9 layouts guardados frente a 0.
  - Si algo empeora > 5 %, investigar con `superpowers:systematic-debugging` antes de seguir.
- [ ] Capturas: detalle del Observatorio con la línea de telemetría junto a `Observatorio.dc.html`; ⌘K con exportar/importar junto a `Paleta.dc.html` (`docs/specs/F7-assets/`).
- [ ] `docs/specs/F7-checklist.md` con C1–C12 y evidencia (formato de `F6-checklist.md`).
- [ ] Revisión final (revisor nuevo, modelo más capaz) acotada a lo que cruza bloques, las tandas de correcciones y el cumplimiento de la spec, con los hallazgos de las revisiones intermedias; una sola tanda de correcciones.
- [ ] Mutación de cierre: `--changed-since origin/develop` (≥ 80 %); la completa solo si la rama cambió código compartido (`PaneEnvironment`, `ObservatoryReport`, `CommandCatalog`, `SmaltiConfig` son compartidos: decidir con el diff y anotarlo).
- [ ] Suites unitarias completas de los paquetes tocados y `swift format lint --strict` en verde; `ps` sin receptores ni emisores huérfanos.

### Task 12: Versión 0.7.0, PRs y despliegue

- [ ] `progress.md` al día; versión 0.7.0 (mismo mecanismo que `chore(release): version 0.6.0`); commit `chore(release): version 0.7.0`.
- [ ] Push de `feature/f7-extras`; PR → `develop`; PR `develop` → `main` (Simón aprobó los merges de antemano).
- [ ] Despliegue desde una sesión que no corra dentro de Smalti: `osascript -e 'quit app "Smalti"'`, `/Applications/Smalti.app` → `/Applications/Smalti.app.old` (borrando el `.old` anterior), `ditto` del Release, `env -i open -a /Applications/Smalti.app`.
- [ ] Actualizar la tarjeta del KB (`projects/smalti/_card.md`) con F7 cerrada y 0.7.0.

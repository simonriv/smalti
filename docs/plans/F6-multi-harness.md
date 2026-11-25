# F6 · Multi-harness y Neovim — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (modo nativo, `.claude/rules/workflow.md`: bloques de 3–5 tareas, dos revisiones intermedias con un revisor nuevo y la final de rama con el modelo más capaz). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retomar sesiones de Claude, Codex, Antigravity y OpenCode (captura por disco, respaldo «continuar», buscador filtrable), abrir y restaurar Neovim por socket con claudecode.nvim instalable desde ⌘K, y filtrar el Observatorio por harness con filas de OpenCode.

**Architecture:**
- **Dominio puro** (`SmaltiCore/Domain/Harness`, nuevo):
  - `HarnessSession`, `SessionQuery`, `CaptureWindow`, `SessionCatalog`, `HarnessBinding`;
  - `AgentSnapshot.sessionID` opcional, `PaneSnapshot.editor`, `ForegroundProcess.pid/startedAt`, `PostToolUse` con archivo;
  - `ObservatoryFilter`.
- **Aplicación:**
  - puerto `HarnessAdapter` ampliado, `EditorBridge`, `HarnessUsage`;
  - casos de uso `CaptureHarnessSession`, `SearchHarnessSessions`, `OpenHarnessSession`, `TrackEditedFiles`, `OpenInEditor`;
  - `IntegrationCatalog` generaliza la integración de F5.6.
- **Adaptadores:**
  - `SQLiteReader` (helper compartido);
  - `CodexHarnessAdapter`, `AntigravityHarnessAdapter`, `OpenCodeHarnessAdapter`, `NeovimAdapter`;
  - `ClaudeHarnessAdapter` ampliado con `ClaudecodeNvimInstaller`;
  - `GhosttyAdapter` con pid y arranque del proceso.
- **App:**
  - columna y tarjeta del buscador;
  - ⌘K («Buscar sesiones», «Editados por Claude», nvim, instalador), ⌘-clic sobre `ruta:línea`;
  - filtros del Observatorio;
  - composition root y flags `-Smalti…`.

**Tech Stack:** Swift 6.4 (Xcode 27.2), AppKit, `SQLite3` del SDK, sockets Unix y msgpack propio, Swift Testing, XCUITest, libghostty v1.4.0 (`83fb956`), Neovim 0.12.6, claudecode.nvim `v0.4.0`, lazy.nvim, Codex 0.171, Antigravity 1.5.10, OpenCode 2.3.2, Ollama 0.40.17 + `qwen3:4b`, Python 3 (`unittest`), `scripts/mutation/mutate.py`.

**Spec:** `docs/specs/F6-multi-harness.md` (aprobada 2026-11-24) · Tableros: `docs/design/Reanudar.dc.html`, `docs/design/Observatorio.dc.html` · Convenciones: `CLAUDE.md`, `.claude/rules/`

## Global Constraints

- **Aislamiento:**
  - `SmaltiCore` solo usa Foundation para tipos de valor; la guarda de imports no se toca.
  - Solo `SQLiteReader` importa `SQLite3`. Solo `GhosttyAdapter` importa GhosttyKit.
  - Ningún adaptador construye `~/.claude`, `~/.codex`, `~/.gemini`, `~/.local/share/opencode` ni `~/.config/nvim`: reciben su raíz por parámetro, y solo el composition root resuelve las reales.
- **Pruebas que tocan procesos:**
  - nunca leen ni escriben las carpetas reales de Simón;
  - las de shell usan `-SmaltiShellCommand "/bin/zsh -f"`, y las apps GUI se lanzan con `env -i`;
  - nvim de prueba con `--clean` o con config temporal, siempre con su propio socket;
  - cada suite que lanza procesos (nvim, codex, antigravity, opencode, ollama) mata su grupo de procesos y los daemons que encuentre por la ruta de su home temporal, y comprueba que no queda ninguno (C16).
- **Valores fijados por la spec:**
  - captura: margen de 2 s antes del arranque, reintentos cada 2 s hasta 10 minutos;
  - buscador: 500 ms por adaptador, 200 sesiones como máximo, abre en ≤ 100 ms (C7);
  - Neovim: «Editados por Claude» con 20 entradas como máximo; `EditorBridge.current` con 200 ms de límite; `sun_path` por debajo de 104 bytes;
  - integración: reanudación en ≤ 45 s; claudecode.nvim fijado a `v0.4.0`.
- **Atajos nuevos** (editables en TOML como los demás): ⌘⇧O `harness.search`, ⌘⇧E `editor.openBeside`, ⌘⇧L `editor.openLastEdited`, ⌘⇧F `observatory.filter`.
- **Textos de interfaz** literales de la spec («Textos nuevos»), en español; los de los tableros, tal cual.
- **Sin Gemini:** no hay `HarnessID.gemini`, chip ni fila.
- **Swift:** Swift 6 estricto; errores tipados con operación, dato y causa; sin `!`, `try!` ni `unsafe*` sin comentario, y lo inseguro solo en adaptadores; `swift format lint --strict`.
- **Rama:** `feature/f6-multi-harness`. Commits con Conventional Commits en inglés y el trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Suites:** las de más de ~30 s se lanzan con `"$KB_ROOT/_system/bin/kb-progress" run <etiqueta> -- …`. Las de UI pasan por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID` (sacado con `ps -axo pid=,command=`), en una sola corrida y nunca dos a la vez.

## Review Focus

1. **Dos paneles de Codex en el mismo directorio, uno restaurado y otro nuevo.** El restaurado conserva su ID; el nuevo recibe la sesión recién creada, nunca la del restaurado. Lo cubre T4 (`restoredPaneKeepsIdWhileNewPaneCapturesFreshOne`).
2. **El harness abierto mientras Smalti lee su base** (WAL con escrituras a medias, base bloqueada). La lista sale o el error es tipado; nunca se cuelga ni falla la app. Lo cubre T6 (`readsWhileWriterHoldsWAL`, `lockedDatabaseIsTypedError`).
3. **Rutas con espacios, comillas, `$`, `<CR>` o Unicode** en el directorio de una sesión o en un archivo que se abre en nvim. El comando se cita bien para el shell y el RPC recibe la ruta como argumento. Lo cubren T3 (`commandsQuoteHostileIdsAndDirectories`) y T12 (`openPassesHostilePathAsArgument`).
4. **Una carpeta de sesión que ya no existe, o un symlink** (`/tmp` → `/private/tmp`). Las rutas se comparan resueltas; si el directorio falta, el panel se abre en el home con aviso. Lo cubren T4 (`directoriesCompareResolved`) y T16 (`missingDirectoryOpensHomeWithNotice`).
5. **Un Esc o un Enter en la columna del buscador de «Retomar»** nunca descarta la sesión guardada. Lo cubre T16 (`escInSearchColumnReturnsFocusWithoutDiscarding`).

## Mapa de archivos

| Ruta | Responsabilidad |
| --- | --- |
| `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Harness/{HarnessSession,SessionQuery,CaptureWindow,SessionCatalog,HarnessBinding,ShellQuoting}.swift` | Tipos y reglas del multi-harness |
| `…/Domain/Agent/{AgentState,AgentEvent}.swift` | `HarnessID` nuevos; `PostToolUse` con archivo |
| `…/Domain/{Pane,TerminalEvent}.swift` | `harnessBinding`; `ForegroundProcess.pid/startedAt` |
| `…/Domain/Session/{PaneSnapshot,ResumeListing}.swift` | `sessionID` opcional, `editor`, filas de respaldo y de nvim |
| `…/Domain/Editor/{EditorPosition,EditorTarget,EditorSocketPath,EditedFiles}.swift` | Neovim en el dominio |
| `…/Domain/Observatory/{ObservatoryFilter,ObservedSession,ObservatoryTexts}.swift` | Filtros y filas de OpenCode |
| `…/Domain/Commands/{CommandCatalog,IntegrationCatalog}.swift`, `…/Domain/Config/{CommandID,Keymap}.swift` | ⌘K y atajos |
| `…/Application/{HarnessAdapter,EditorPorts,CaptureHarnessSession,SearchHarnessSessions,OpenHarnessSession,TrackEditedFiles,OpenInEditor,RestoreSession,SaveSession,ObserveAgents,AgentPorts}.swift` | Puertos y casos de uso |
| `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/{HarnessContracts,HarnessFakes,EditorFakes}.swift` | Contrato compartido y fakes |
| `Packages/SQLiteReader/` | Lectura SQLite inmutable con errores tipados |
| `Packages/{Codex,Antigravity,OpenCode}HarnessAdapter/` | Adaptadores, fixtures e integración |
| `Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/{ClaudeHarness,ClaudeSessionList,ClaudecodeNvimInstaller}.swift` | Claude ampliado e instalador |
| `Packages/NeovimAdapter/` | msgpack-RPC, `NeovimBridge`, prueba del diff (C3) |
| `Packages/IPCAdapter/Sources/IPCAdapter/HookPayloadTranslator.swift` | Campos de `PostToolUse` |
| `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{GhosttySurfaceView,ProcessStart}.swift` | pid y arranque del proceso |
| `scripts/harnesses/{record-fixtures.sh,sanitize_fixture.py,test_sanitize_fixture.py,prepare-nvim-fixtures.sh,PtyResume.swift}` | Grabación, saneo, nvim de prueba |
| `App/Smalti/Harness/{SessionSearchController,SessionSearchView,SessionRowView}.swift` | Buscador |
| `App/Smalti/Restore/{RestoreController,RestoreView}.swift` | Columna derecha y foco |
| `App/Smalti/Editor/{EditorCoordinator,PathClickInterceptor}.swift` | Abrir en Neovim, ⌘-clic |
| `App/Smalti/Observatory/{ObservatoryView,ObservatoryController}.swift` | Chips |
| `App/Smalti/{AppComposition,WindowComposition,ClaudeIntegrationStatus}.swift` | Cableado, flags e integraciones |
| `App/SmaltiUITests/{SessionSearchTests,RestoreSearchTests,EditorTests,ObservatoryFilterTests,IntegrationCatalogTests,IsolatedApp}.swift`, `App/SmaltiUITests/Fixtures/harnesses/` | E2E |

---

## Bloque 1 · Spike, fixtures y dominio

### Task 1: Spike de reanudación, nombres de proceso y fixtures reales

Cierra los riesgos de la spec antes de escribir código de producción.

**Files:**
- Create: `scripts/harnesses/record-fixtures.sh`, `scripts/harnesses/sanitize_fixture.py`, `scripts/harnesses/test_sanitize_fixture.py`, `scripts/harnesses/prepare-nvim-fixtures.sh`, `docs/specs/F6-assets/spike.md`
- Create: `Packages/{Codex,Antigravity,OpenCode}HarnessAdapter/Tests/Fixtures/<harness>/…` y `Packages/ClaudeHarnessAdapter/Tests/Fixtures/claude/…`

**Interfaces:**
- Produces:
  - `record-fixtures.sh <claude|codex|antigravity|opencode>` graba en `scripts/harnesses/recording.local/<harness>/` (home, work, `session-id.txt`). Arranca `ollama serve` en `127.0.0.1:11435` para codex y opencode y lo mata al terminar.
  - `sanitize_fixture.py <in-dir> <out-dir> --root <work> --markers scripts/observatory/markers.local`:
    - reescribe la ruta de trabajo como `@@WORK@@` y el home como `@@HOME@@`, también dentro de las bases SQLite (UPDATE con `replace()` en columnas de texto) y de los JSON/JSONL;
    - borra `antigravity-oauth-token`, `installation_id`, `auth.json`, logs y cachés de marketplace;
    - falla si queda algún marcador personal.
  - Las pruebas copian el fixture a un temporal y sustituyen `@@WORK@@`/`@@HOME@@` con `FixtureHome.materialize(from:into:) throws -> URL`, en `SmaltiCoreTestSupport`.

- [ ] **Step 1:** Escribir las pruebas del saneador (`test_sanitize_fixture.py`):
  - `test_rewrites_paths_in_sqlite_json_and_jsonl`;
  - `test_drops_tokens_and_installation_ids`;
  - `test_fails_when_personal_marker_remains`;
  - `test_leaves_other_bytes_untouched`.
  
  Verlas fallar con `cd scripts/harnesses && python3 -m unittest test_sanitize_fixture`. Implementarlo y verlas pasar.
- [ ] **Step 2:** Spike de Claude: grabar con `claude -p` y la suscripción en `recording.local/claude` (`CLAUDE_CONFIG_DIR` temporal). Lanzar `claude --resume <id>` en un PTY con ese `CLAUDE_CONFIG_DIR` y anotar en `spike.md` si pide login.
  - Si lo pide, el login queda en `recording.local/claude` y la integración de Claude lo copia, igual que Antigravity.
  - Si no se puede automatizar, parar y preguntar a Simón.
- [ ] **Step 3:** Spike de Ollama: con el servidor apagado, retomar codex y opencode (homes del spike) y anotar si lo necesitan.
- [ ] **Step 4:** Anotar en `spike.md`, con los binarios instalados y `ps -o comm=`, el nombre del proceso en primer plano de `codex`, `agy` → `antigravity` y `opencode`. Anotar también si `st_birthtime` de `conversations/<id>.db` de Antigravity es la creación de la conversación (grabar dos y comparar).
- [ ] **Step 5:** Grabar los cuatro fixtures con `record-fixtures.sh`: dos sesiones por harness, en dos directorios de trabajo, para probar el filtro por directorio. Sanearlos dentro de los paquetes. Cada carpeta lleva `VERSION` con la versión del harness.
- [ ] **Step 6:** `prepare-nvim-fixtures.sh` clona lazy.nvim (commit fijado) y claudecode.nvim `v0.4.0` en `build/nvim-fixtures/` y escribe un `init.lua` mínimo con `require("lazy").setup({ { import = "plugins" } }, { install = { missing = false } })`. Es idempotente.
- [ ] **Step 7:** Comprobar que no queda ningún proceso lanzado: `pgrep -lf 'recording.local|ollama serve|nvim-fixtures'` vacío, salvo el `ollama serve` del spike (PID 28617, que se mata en T21).
- [ ] **Step 8:** Commit `test(f6): record and sanitize real harness fixtures`.

### Task 2: Tipos del multi-harness en el dominio

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Harness/{HarnessSession,SessionQuery,CaptureWindow,SessionCatalog,ShellQuoting}.swift`
- Modify: `…/Domain/Agent/AgentState.swift` (`HarnessID`)
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Harness/{SessionCatalogTests,SessionQueryTests,ShellQuotingTests}.swift`

**Interfaces:**
- Produces:
  - `HarnessID.codex`, `.antigravity`, `.opencode`.
  - `struct HarnessSession: Equatable, Sendable { let harness: HarnessID; let id: String; let directory: String; let title: String; let createdAt: Date; let updatedAt: Date; let detail: String? }`.
  - `struct SessionQuery: Equatable, Sendable { var harness: HarnessID?; var text: String; var directory: String?; var limit: Int = 200 }`; `func matches(_ s: HarnessSession) -> Bool` usa la búsqueda difusa de F1 (`FuzzyMatcher`) sobre título y proyecto.
  - `struct CaptureWindow: Equatable, Sendable { let directory: String; let processStartedAt: Date; let excludedIDs: Set<String> }`; `static let margin: TimeInterval = 2`.
  - `enum SessionCatalog { static func merge(_ lists: [Result<[HarnessSession], HarnessError>], query: SessionQuery) -> SessionListing }`.
  - `struct SessionListing { let sessions: [HarnessSession]; let failures: [HarnessID: HarnessError] }`.
  - `enum HarnessError: Error, Equatable, Sendable { case storeMissing(path: String), unreadable(path: String, reason: String), unknownSchema(path: String, missing: String), timedOut(harness: HarnessID) }`, con `message` («No se pudo leer <harness>: <motivo>»).
  - `enum ShellQuoting { static func quoted(_ text: String) -> String }`: se extrae de `ClaudeHarness` y lo usan todos.
  - `ResolvedPath.same(_ a: String, _ b: String) -> Bool` en `Domain/Harness`: compara quitando el prefijo `/private` de `/tmp` y `/var`, y la barra final. Es puro: el `realpath` real lo hace cada adaptador.

- [ ] **Step 1:** Escribir las pruebas:
  - `mergesNewestFirstAcrossHarnesses`;
  - `failingAdapterKeepsOthers` (la falla queda en `failures`);
  - `capsAtLimit` (201 → 200);
  - `filtersByHarnessAndText`;
  - `emptyListsGiveEmptyListing`;
  - `quotesHostileText` (`a'b` → `'a'\''b'`; uuid sin comillas; vacío → `''`);
  - `directoriesCompareResolved` (`/private/tmp/x/` = `/tmp/x`).
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore --filter 'SessionCatalogTests|SessionQueryTests|ShellQuotingTests'` → FAIL.
- [ ] **Step 3:** Implementar. `ClaudeHarness` pasa a usar `ShellQuoting` en T10.
- [ ] **Step 4:** Verde.
- [ ] **Step 5:** Commit `feat(core): harness sessions, queries and catalog`.

### Task 3: Puerto `HarnessAdapter` ampliado, contrato compartido y fake

**Files:**
- Modify: `…/Application/HarnessAdapter.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/{HarnessContracts,HarnessFakes}.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Harness/FakeHarnessAdapterTests.swift`

**Interfaces:**
- Consumes: T2.
- Produces:
  - el protocolo de la spec, exacto:
    - `detect(_:) -> Bool`, `captureSessionId(in:) async throws(HarnessError) -> String?`, `listSessions(_:) async throws(HarnessError) -> [HarnessSession]`;
    - `resumeCommand(for:) -> String`, `continueCommand() -> String`, `forkCommand(for:) -> String?`;
    - más `sessionID(fromCommandLine: [String]) -> String?`, que lee `codex resume <id>`, `opencode -s <id>`, `agy --conversation <id>`, `claude --resume <id>`, y ninguna otra forma.
  - `HarnessRegistry.adapter(detecting: ForegroundProcess) -> (any HarnessAdapter)?` y `var all: [any HarnessAdapter]`.
  - `HarnessAdapterContract` (como `PersistenceContracts`): una función `static func verify(_ make: (FixtureHome) async throws -> any HarnessAdapter, fixture: HarnessFixtureExpectations) async throws`.
  - `struct HarnessFixtureExpectations { let harness: HarnessID; let processName: String; let sessions: [(id: String, directory: String, title: String)]; let resumeCommand: String; let continueCommand: String; let forkCommand: String? }`.
  - `FakeHarnessAdapter` (en memoria, configurable) y `FixtureHome` (de T1).

- [ ] **Step 1:** Contrato, con un caso por concepto:
  - `detectsItsProcessOnly` (también por `commandLine[0]`);
  - `listsNewestFirst`;
  - `listFiltersByDirectory`;
  - `listFiltersByText`;
  - `excludesArchivedAndChildren`;
  - `capturesSessionCreatedAfterStart`;
  - `ignoresSessionCreatedBeforeStart`;
  - `ignoresOtherDirectory`;
  - `skipsExcludedIDs` (desempate);
  - `missingStoreIsTypedError`;
  - `unknownSchemaIsTypedError` (fixture sin una columna);
  - `commandsQuoteHostileIdsAndDirectories`;
  - `readsIdFromCommandLine`.
- [ ] **Step 2:** `FakeHarnessAdapterTests` hace pasar el contrato al fake. FAIL, implementar, verde.
- [ ] **Step 3:** Commit `feat(core): full HarnessAdapter port with shared contract`.

### Task 4: Captura del ID y `HarnessBinding` del panel

**Files:**
- Create: `…/Domain/Harness/HarnessBinding.swift`, `…/Application/CaptureHarnessSession.swift`
- Modify: `…/Domain/Pane.swift`, `…/Domain/TerminalEvent.swift` (`ForegroundProcess`), `…/Application/TerminalEngine.swift` (doc), `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/FakeTerminalEngine.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Harness/CaptureHarnessSessionTests.swift`, `…/Domain/PaneHarnessTests.swift`

**Interfaces:**
- Consumes: T2, T3.
- Produces:
  - `ForegroundProcess(name:commandLine:pid: Int32? = nil, startedAt: Date? = nil)`.
  - `struct HarnessBinding: Equatable, Sendable { let harness: HarnessID; let sessionID: String?; let processStartedAt: Date }`.
  - `Pane.harnessBinding: HarnessBinding?`; `Pane.binding(_:) -> Pane`.
  - `Pane.applying(.foregroundProcessChanged)` borra el binding al volver al shell, pero conserva el ID para guardarlo: `lastHarnessBinding`.
  - `@MainActor final class CaptureHarnessSession`:
    - `init(registry: HarnessRegistry, clock: @escaping () -> Date, sleep: @escaping (Duration) async -> Void)`;
    - `func processChanged(in pane: Pane, to process: ForegroundProcess, knownID: String?) -> CaptureStart?`, que devuelve qué buscar o el binding ya decidido (ID conocido o de la línea de comandos);
    - `func capture(_ start: CaptureStart, claimed: Set<String>) async -> HarnessBinding?`, que reintenta cada 2 s hasta 10 min mientras el panel siga con ese proceso (`isStillRunning: () -> Bool`).
  - Claude: si su `AgentSession` (hook) tiene ID, manda sobre el binding.

- [ ] **Step 1:** Escribir las pruebas (reloj y `sleep` falsos):
  - `knownIdIsKept`;
  - `idFromCommandLineWins`;
  - `capturesWhenSessionAppearsLater` (aparece al 3.er reintento);
  - `stopsRetryingAfterTenMinutes`;
  - `stopsWhenProcessLeaves`;
  - `neverTakesSessionBeforeStartMinusMargin`;
  - `twoPanesSameDirectoryGetDistinctIds` (por orden de arranque);
  - `restoredPaneKeepsIdWhileNewPaneCapturesFreshOne`;
  - `claudeHookIdOverridesDiskCapture`;
  - `returningToShellKeepsLastBindingForSaving`.
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore --filter 'CaptureHarnessSession|PaneHarness'` → FAIL.
- [ ] **Step 3:** Implementar. El orden de arranque decide con `processStartedAt`; `claimed` lo pasa la app con los IDs de los demás paneles.
- [ ] **Step 4:** Verde. Commit `feat(core): capture harness session ids from disk`.

### Task 5: Guardar y restaurar con respaldo, y compatibilidad

**Files:**
- Modify: `…/Domain/Session/PaneSnapshot.swift`, `…/Domain/Session/ResumeListing.swift`, `…/Application/{SaveSession,RestoreSession}.swift`, `…/Domain/Agent/AgentSession.swift` (`snapshot`)
- Test: `…/Session/{HarnessRestoreTests,SnapshotCompatibilityTests}.swift`, más una fixture JSON de una sesión guardada por la 0.5.6

**Interfaces:**
- Consumes: T3, T4.
- Produces:
  - `AgentSnapshot.sessionID: String?`;
  - `PaneSnapshot.editor: EditorPosition?` (el tipo es de T12; aquí se declara `struct EditorPosition: Codable, Equatable, Sendable { let file: String; let line: Int }` en `Domain/Editor/EditorPosition.swift`);
  - `RestoreSession.startup`: con ID → `resumeCommand`; sin ID → `continueCommand()`; en ambos casos, en el directorio del panel. Los Claude relanzados llevan `--ide` cuando `RestoreSession.Dependencies.claudeIDE == true` (T19 lo cablea);
  - `ResumeRow` de respaldo: `code = "agy -c"`, `detail = "la última del directorio"`; fila de nvim: `title = "reminder.service.ts"`, `detail = "línea 42"`, `code = "nvim +42"`.

- [ ] **Step 1:** Escribir las pruebas:
  - `paneWithIdResumes`;
  - `paneWithoutIdContinues`;
  - `continueRowWarnsLastOfDirectory`;
  - `nvimRowShowsFileAndLine`;
  - `claudeGetsIdeFlagWhenEnabled`;
  - `decodesSnapshotSavedBy056` (fixture JSON real de la 0.5.6, saneada);
  - `encodesWithoutEditorAsBefore`.
- [ ] **Step 2:** FAIL, implementar, verde (suite completa de SmaltiCore: es barata).
- [ ] **Step 3:** Commit `feat(core): restore harness panes with continue fallback`.

---

## Bloque 2 · Adaptadores de harness

### Task 6: `SQLiteReader`

**Files:**
- Create: `Packages/SQLiteReader/{Package.swift,Sources/SQLiteReader/SQLiteReader.swift,Tests/SQLiteReaderTests/SQLiteReaderTests.swift}`
- Modify: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Architecture/AdapterGuardTests.swift`: solo `SQLiteReader` importa `SQLite3`. Además, C14: ninguna fuente de `Packages/*/Sources` contiene los literales `".claude"`, `".codex"`, `".gemini"`, `".local/share/opencode"` ni `".config/nvim"`; solo `App/Smalti/AppComposition.swift` puede tenerlos. La guarda falla nombrando archivo y línea.

**Interfaces:**
- Produces:
  - `public struct SQLiteReader: Sendable`, con `public init(url: URL)`;
  - `public func rows(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteReadError) -> [SQLiteRow]`;
  - `public func columns(of table: String) throws(SQLiteReadError) -> Set<String>`;
  - abre con `file:<ruta>?mode=ro&immutable=1` (URI) y `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI`; cierra en cada llamada; `busy_timeout` de 100 ms;
  - `public enum SQLiteValue { case text(String), integer(Int64), real(Double), null }`;
  - `public struct SQLiteRow { subscript(text:) -> String?, subscript(integer:) -> Int64?, subscript(real:) -> Double? }`;
  - `public enum SQLiteReadError: Error, Equatable { case open(path: String, code: Int32, message: String), query(path: String, sql: String, message: String) }`.

- [ ] **Step 1:** Pruebas (bases creadas en un temporal con `sqlite3` CLI desde la prueba):
  - `readsRowsWithBindings`;
  - `listsColumns`;
  - `missingFileIsOpenError`;
  - `readsWhileWriterHoldsWAL` (un proceso `sqlite3` escribiendo en WAL);
  - `lockedDatabaseIsTypedError` (sin colgarse);
  - `directoryWithoutWritePermissionStillReads` (el caso del error 14);
  - `unicodeAndSpacesInPath`.
- [ ] **Step 2:** FAIL, implementar, verde. Commit `feat(sqlite): immutable read-only SQLite reader`.

### Task 7: `CodexHarnessAdapter`

**Files:**
- Create: `Packages/CodexHarnessAdapter/{Package.swift,Sources/CodexHarnessAdapter/CodexHarness.swift,Tests/CodexHarnessAdapterTests/{CodexContractTests,CodexHarnessTests}.swift}`

**Interfaces:**
- Consumes: T3, T6, fixture de T1.
- Produces: `public struct CodexHarness: HarnessAdapter`, con `public init(home: URL)` (la raíz de `CODEX_HOME`).
  - Lee `state_5.sqlite`, tabla `threads`: `archived = 0`, `id`, `cwd`, `title`, `created_at`, `updated_at` (segundos Unix), `model_provider`.
  - `detail` = `model_provider` y `tokens_used` («ollama · 4.439 tokens»).
  - Comandos: `codex resume <id>`, `codex resume --last`, `codex fork <id>`.
  - Columnas requeridas: `id, cwd, title, created_at, updated_at, archived`. Si falta alguna → `unknownSchema`.

- [ ] **Step 1:** `CodexContractTests` llama a `HarnessAdapterContract.verify` con el fixture. `CodexHarnessTests`:
  - `detailNamesProviderAndTokens`;
  - `missingStateDbIsStoreMissing`.
- [ ] **Step 2:** FAIL, implementar, verde. Commit `feat(codex): Codex harness adapter`.

### Task 8: `AntigravityHarnessAdapter`

**Files:**
- Create: `Packages/AntigravityHarnessAdapter/{…}/AntigravityHarness.swift` y sus pruebas

**Interfaces:**
- Produces: `public struct AntigravityHarness: HarnessAdapter`, con `public init(root: URL)` (la carpeta `antigravity-cli`).
  - Lee `conversation_summaries`: `conversation_id`, `title`, `workspace_uris` (JSON → primera `file://` → ruta), `last_modified_time` (texto ISO con zona).
  - `createdAt` = `st_birthtime` de `conversations/<id>.db`. Si el spike de T1 lo descarta, cambia aquí por lo que diga `spike.md`.
  - `detect`: proceso `antigravity`.
  - Comandos: `agy --conversation <id>`, `agy -c`, `forkCommand` → nil.

- [ ] **Step 1:** Contrato y además:
  - `malformedWorkspaceUrisOmitsRow`;
  - `percentEncodedUriDecodes` (espacios y Unicode).
- [ ] **Step 2:** FAIL, implementar, verde. Commit `feat(antigravity): Antigravity harness adapter`.

### Task 9: `OpenCodeHarnessAdapter` y `OpenCodeUsage`

**Files:**
- Create: `Packages/OpenCodeHarnessAdapter/{…}/{OpenCodeHarness,OpenCodeUsage}.swift` y sus pruebas
- Modify: `…/Application/ObservatoryPorts.swift` (puerto `HarnessUsage`), `…/Domain/Observatory/ObservedSession.swift`

**Interfaces:**
- Produces:
  - `public struct OpenCodeHarness: HarnessAdapter`, con `public init(database: URL)`.
    - Lee `session_v2` donde `parent_id` y `time_archived` son nulos o vacíos; tiempos en ms.
    - `detail` = modelo del último mensaje `assistant` (`json_extract(data,'$.model.id')`).
    - Comandos: `opencode -s <id>`, `opencode -c`, `forkCommand` → nil.
  - Puerto `public protocol HarnessUsage: Sendable { func sessions(since: Date) async throws(HarnessError) -> [UsageRow] }`.
  - `public struct UsageRow: Equatable, Sendable { let harness: HarnessID; let sessionID: String; let directory: String; let model: String?; let isLocal: Bool; let input: Int; let output: Int; let updatedAt: Date }`.
  - `OpenCodeUsage: HarnessUsage`:
    - `input = tokens_input + tokens_cache_read`, `output = tokens_output`;
    - `isLocal` si `providerID ∈ {"ollama","lmstudio"}` (la base no guarda la `baseURL`: enmienda 1 de la spec).
  - `OpenCodeHarness.defaultDatabase(dataHome: URL) -> URL`: `opencode.db`, o la única `opencode-*.db` con `session_v2`.

- [ ] **Step 1:** Contrato y además:
  - `usageSumsCacheReadIntoInput`;
  - `ollamaProviderIsLocal`;
  - `oneXSchemaIsUnknownSchema` (fixture con tabla `session`);
  - `defaultDatabasePrefersMainChannel`;
  - `malformedMessageJsonKeepsRowWithoutModel`.
- [ ] **Step 2:** FAIL, implementar, verde. Commit `feat(opencode): OpenCode harness adapter and usage`.

### Task 10: `ClaudeHarness` completo e integración de reanudación de los cuatro

**Files:**
- Modify: `Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/ClaudeHarness.swift`
- Create: `…/ClaudeSessionList.swift`, `scripts/harnesses/PtyResume.swift` (lo comparten las pruebas como fuente añadida a `SmaltiCoreTestSupport`: `PtyResume.run(command:environment:cwd:needle:timeout:) throws -> PtyResumeResult`), `Packages/<X>HarnessAdapter/Tests/<X>HarnessAdapterTests/ResumeIntegrationTests.swift` (×4)

**Interfaces:**
- Produces:
  - `ClaudeHarness(projectsRoot: URL)`:
    - `listSessions` lee los `<id>.jsonl` de `projectsRoot`, con título del primer prompt y `cwd` de la primera línea con `cwd`, reutilizando `TranscriptRecord` de F3;
    - `continueCommand` → `claude --continue`; `forkCommand` → `claude --resume <id> --fork-session`;
    - `resumeCommand(for:ide:)` añade `--ide`.
  - `PtyResumeResult { let found: Bool; let transcript: String; let leftovers: [Int32] }`:
    - corre `/bin/zsh -f -c <command>` con `posix_spawn` + `openpty`;
    - mata el grupo con SIGTERM y luego SIGKILL;
    - busca daemons con `pgrep -f <home temporal>` y los mata;
    - `leftovers` lista los PIDs que siguieran vivos.
  - Cada `ResumeIntegrationTests.resumesFixtureWithRealCommand`:
    - se salta con `Trait.enabled(if:)` si el binario no está o (Antigravity, y Claude si T1 lo pidió) falta el login en `recording.local`;
    - espera `found == true` en ≤ 45 s y `leftovers.isEmpty`.
  - Codex escribe en su home temporal el `config.toml` del spike, con `[projects."<work>"] trust_level = "trusted"` y la ruta resuelta. Si T1 dijo que hace falta Ollama, la prueba lo arranca en un puerto propio y lo mata.

- [ ] **Step 1:** Contrato de Claude con su fixture, y `ideFlagAppended`. FAIL, implementar, verde.
- [ ] **Step 2:** Las cuatro pruebas de integración. Correrlas, cada una con `kb-progress run integration -- swift test --package-path … --filter ResumeIntegrationTests`. Verde, o salto con su motivo solo si falta el binario.
- [ ] **Step 3:** `pgrep -lf 'codex|antigravity|opencode serve|ollama'` sin nada lanzado por las pruebas.
- [ ] **Step 4:** Commit `test(f6): resume each harness fixture with its real command`.

---

## Bloque 3 · Neovim, instalador e IPC

### Task 11: `ForegroundProcess` con pid y arranque, y `PostToolUse` con archivo

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/ProcessStart.swift`
- Modify: `…/GhosttySurfaceView.swift:157-171`, `Packages/IPCAdapter/Sources/IPCAdapter/HookPayloadTranslator.swift`, `…/Domain/Agent/AgentEvent.swift`
- Test: `Packages/GhosttyAdapter/Tests/GhosttyAdapterTests/ProcessStartTests.swift`, `Packages/IPCAdapter/Tests/IPCAdapterTests/HookPayloadTranslatorTests.swift`

**Interfaces:**
- Produces:
  - `enum ProcessStart { static func of(pid: pid_t) -> Date? }`, con `proc_pidinfo(PROC_PIDTBSDINFO)`, `pbi_start_tvsec/usec`.
  - `AgentEvent.edit: FileEdit?`, con `struct FileEdit: Equatable, Sendable { let tool: String; let path: String; let newText: String? }`. Sale de `tool_name` ∈ {Edit, MultiEdit, Write, NotebookEdit} y `tool_input.file_path` (`notebook_path` en NotebookEdit). `newText` es `new_string`, el primer `edits[].new_string` o la primera línea de `content`.

- [ ] **Step 1:** Escribir las pruebas:
  - `startOfOwnProcessIsBeforeNow`;
  - `deadPidIsNil`;
  - `postToolUseEditCarriesPathAndText`;
  - `multiEditTakesFirstEdit`;
  - `writeTakesFirstContentLine`;
  - `otherToolsHaveNoEdit`.
- [ ] **Step 2:** FAIL, implementar, verde (suites completas de GhosttyAdapter e IPCAdapter). Commit `feat(adapters): process start time and edited file in PostToolUse`.

### Task 12: Dominio de Neovim y `NeovimAdapter`

**Files:**
- Create: `…/Domain/Editor/{EditorTarget,EditorSocketPath,EditedFiles}.swift`, `…/Application/{EditorPorts,TrackEditedFiles,OpenInEditor}.swift`, `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/EditorFakes.swift`
- Create: `Packages/NeovimAdapter/{Package.swift,Sources/NeovimAdapter/{MsgPack,NeovimRPC,NeovimBridge}.swift,Tests/NeovimAdapterTests/{MsgPackTests,NeovimBridgeTests}.swift}`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Editor/{EditorTargetTests,EditedFilesTests,OpenInEditorTests,EditorSocketPathTests}.swift`

**Interfaces:**
- Produces:
  - `struct EditorTarget: Equatable { let path: String; let line: Int?; let column: Int? }`, con `static func parse(_ word: String, cwd: String) -> EditorTarget?` (`ruta`, `ruta:12`, `ruta:12:3`; relativa → `cwd`);
  - `EditorSocketPath.make(directory: String, pane: PaneID) -> String`, que lanza `EditorError.socketPathTooLong` si ≥ 104 bytes;
  - `struct EditedFiles { mutating func record(_ edit: FileEdit, line: Int, at: Date); var recent: [EditedFile] }`, con tope de 20, sin duplicados (sube al principio);
  - `@MainActor protocol EditorBridge: AnyObject { func open(_ target: EditorTarget, socket: String) async throws(EditorError); func current(socket: String) async -> EditorPosition? }`;
  - `@MainActor final class OpenInEditor`:
    - `init(bridge: any EditorBridge, panes: EditorPanes)`;
    - `func open(_ target: EditorTarget, from pane: PaneID) async -> EditorOutcome`, con `enum EditorOutcome { case jumped(PaneID), opened(command: String, beside: PaneID), ignored }`;
    - `EditorPanes` es un protocolo pequeño que implementa la app: `nvimPanes(inWorkspaceOf:)`, ordenados por último foco;
  - `TrackEditedFiles.lineOf(newText: String?, in fileText: String) -> Int`: primera línea que contiene la primera línea no vacía de `newText`; si no la encuentra, 1;
  - `NeovimBridge: EditorBridge`, con cliente msgpack-RPC (`[0, msgid, method, params]`) sobre `socket(AF_UNIX)`:
    - `open` llama a `nvim_exec_lua("local f,l,c=...; vim.cmd.edit(vim.fn.fnameescape(f)); if l then vim.api.nvim_win_set_cursor(0,{l,(c or 1)-1}) end", [path, line, column])`;
    - `current` llama a `nvim_exec_lua("return {vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1]}", [])` con 200 ms.

- [ ] **Step 1:** Pruebas de dominio:
  - `parsesPathLineColumn`;
  - `relativeResolvesAgainstCwd`;
  - `rejectsUrlsAndEmpty`;
  - `capsAtTwentyAndDeduplicates`;
  - `lineOfFindsFirstLineOrOne`;
  - `jumpsToLastFocusedNvim`;
  - `opensBesideWhenNoNvim` (comando `nvim --listen <sock> +12 '<ruta>'`);
  - `socketPathTooLongIsError`.
- [ ] **Step 2:** Pruebas del adaptador, contra `nvim --clean --headless --listen <tmp>/s` lanzado por la prueba (y matado en `deinit`/`defer`):
  - `msgpackRoundTripsTypes`;
  - `openPassesHostilePathAsArgument` (archivo `a b'"$x\n.txt`);
  - `openJumpsToLine`;
  - `currentReturnsFileAndLine`;
  - `deadSocketIsTypedError`;
  - `currentTimesOutAt200ms` (un servidor que acepta y no responde).
- [ ] **Step 3:** FAIL, implementar, verde. Sin procesos `nvim` sueltos. Commit `feat(neovim): editor bridge over msgpack-RPC`.

### Task 13: Catálogo de integraciones, `ClaudecodeNvimInstaller` y prueba del diff (C3)

**Files:**
- Create: `…/Domain/Commands/IntegrationCatalog.swift`, `Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/ClaudecodeNvimInstaller.swift`, `Packages/NeovimAdapter/Tests/NeovimAdapterTests/{ClaudeDiffProtocolTests,ClaudeIDEClient}.swift`
- Modify: `…/Domain/Commands/CommandCatalog.swift` (`claudeIntegration` → `integrations: [IntegrationID: IntegrationState]`), `…/Domain/Config/CommandID.swift`, `…/Application/AgentPorts.swift`
- Test: `…/Commands/IntegrationCatalogTests.swift`, `Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/ClaudecodeNvimInstallerTests.swift`

**Interfaces:**
- Produces:
  - `enum IntegrationID { case claudePlugin, claudecodeNvim }`, con títulos «Instalar integración con Claude Code» / «Desinstalar integración con Claude Code» e «Instalar claudecode.nvim en Neovim» / «Desinstalar claudecode.nvim»;
  - `CommandID.integrationInstall(IntegrationID)` y `.integrationUninstall(IntegrationID)` sustituyen a los de F5.6;
  - `ClaudecodeNvimInstaller: HarnessIntegration`, con `init(configHome: URL)` (la carpeta `nvim`):
    - escribe `lua/plugins/smalti-claudecode.lua` con la marca `-- Instalado por Smalti`, `"coder/claudecode.nvim"`, `tag = "v0.4.0"`, `opts = { terminal = { provider = "none" } }`;
    - `installState`: `.installed` si el archivo existe con la marca; `.notInstalled` si es NvChad sin él; `.unknown` si no hay `lua/plugins/` ni `import = "plugins"` en `init.lua`;
    - `uninstall` borra solo un archivo con la marca;
  - `ClaudeIDEClient` (solo pruebas):
    - lee `<CLAUDE_CONFIG_DIR>/ide/<puerto>.lock` (`authToken`);
    - WebSocket con `URLSessionWebSocketTask` y la cabecera `x-claude-code-ide-authorization`;
    - `initialize`, y luego `tools/call` `openDiff` con `old_file_path`, `new_file_path`, `new_file_contents`, `tab_name`.

- [ ] **Step 1:** Pruebas:
  - `catalogOffersOnlyApplicableActionPerIntegration`;
  - `unknownStateOffersNeither`;
  - `installsOwnFileOnly` (sobre un starter de NvChad en un `XDG_CONFIG_HOME` temporal);
  - `uninstallKeepsUnmarkedFile`;
  - `nonNvChadConfigIsUnknown`;
  - `headlessNvimLoadsInstalledPlugin` (`build/nvim-fixtures`, `nvim --headless -u <init.lua> "+lua assert(require('claudecode'))" +qa`; se salta si T1 no preparó la carpeta).
- [ ] **Step 2:** C3 en `ClaudeDiffProtocolTests` (nvim `--clean --headless --listen` con `runtimepath` de claudecode.nvim de `build/nvim-fixtures`, `CLAUDE_CONFIG_DIR` temporal y `require('claudecode').setup({terminal={provider='none'}})`):
  - `writeAcceptsDiff`: `openDiff`, luego `:w` por el socket (`NeovimRPC`) → `FILE_SAVED` y el contenido nuevo;
  - `quitRejectsDiff`: `:q` → `DIFF_REJECTED`.
- [ ] **Step 3:** FAIL, implementar, verde. Sin `nvim` sueltos. Commit `feat(f6): integration catalog, claudecode.nvim installer and diff protocol test`.

### Revisión intermedia 1

- [ ] Revisor nuevo sobre el diff desde `develop` (dominio y adaptadores, T1–T13). Corregir en una sola tanda los hallazgos importantes y menores, cada uno con su prueba RED→GREEN.
- [ ] `kb-progress run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore --changed-since origin/develop`. Matar cada sobreviviente con una prueba nueva, verificada aplicando el mutante a mano, sin repetir la corrida.
- [ ] Suites unitarias completas de todos los paquetes tocados y `swift format lint --strict` con los paquetes nuevos. Marcar el bloque en `progress.md`.

---

## Bloque 4 · App

### Task 14: Composition root, flags y captura en vivo

**Files:**
- Modify: `App/Smalti/AppComposition.swift`, `App/Smalti/WindowComposition.swift`, `App/Smalti.xcodeproj` (paquetes nuevos), `App/SmaltiUITests/IsolatedApp.swift`
- Test: `App/SmaltiUITests/HarnessCaptureTests.swift`, `App/SmaltiUITests/Fixtures/harnesses/fake-codex.sh`

**Interfaces:**
- Produces:
  - flags `-SmaltiCodexHome`, `-SmaltiAntigravityHome`, `-SmaltiOpenCodeDB`, `-SmaltiNvimCommand`, `-SmaltiNvimConfigHome` y `-SmaltiEditorSocketDir`;
  - sin flag, rutas reales del entorno (`CODEX_HOME`, `XDG_*`, `CLAUDE_CONFIG_DIR`) resueltas solo aquí;
  - `isolatedSmalti()` siempre pasa homes temporales vacíos para los tres harnesses y el config de nvim.
  - La captura se cablea al evento `.foregroundProcessChanged` de cada panel y pasa `claimed` con los IDs de los demás paneles.
  - `fake-codex.sh` es un ejecutable llamado `codex`, en un `PATH` temporal, que inserta una fila en el `state_5.sqlite` de fixture del home temporal y se queda leyendo stdin. Así la prueba ve la captura sin el Codex real.

- [ ] **Step 1:** Escribir `HarnessCaptureTests`:
  - `codexPaneCapturesAndRestoresWithResume`: abrir, capturar, cerrar y reabrir → la fila de «Retomar» dice `codex resume <id>`;
  - `paneWithoutSessionRestoresWithContinue`.
- [ ] **Step 2:** Revertir y recompilar para ver el rojo; luego implementar y correr las dos en una sola corrida (`scripts/check-daily-untouched.sh scripts/test-ui.sh HarnessCaptureTests`). Commit `feat(app): wire harness adapters and live capture`.

### Task 15: Buscador como tarjeta propia (⌘⇧O)

**Files:**
- Create: `App/Smalti/Harness/{SessionSearchController,SessionSearchView,SessionRowView}.swift`, `…/Application/{SearchHarnessSessions,OpenHarnessSession}.swift`
- Modify: `…/Domain/Config/{CommandID,Keymap}.swift`, `…/Domain/Commands/CommandCatalog.swift`
- Test: `…/Harness/{SearchHarnessSessionsTests,OpenHarnessSessionTests}.swift`, `App/SmaltiUITests/SessionSearchTests.swift`

**Interfaces:**
- Produces:
  - `SearchHarnessSessions.run(_ query: SessionQuery) async -> SessionListing`: lanza los adaptadores en paralelo con 500 ms cada uno; el que tarda más se entrega después por `AsyncStream<SessionListing>`;
  - `OpenHarnessSession.open(_ s: HarnessSession, forking: Bool, in workspace: WorkspaceID) -> OpenOutcome`, con `enum OpenOutcome { case opened(PaneID), folderMissing(path: String, pane: PaneID), cannotFork(HarnessID) }`;
  - la vista reproduce la columna derecha de `Reanudar.dc.html`, con medidas, colores y textos del tablero y tokens de `docs/design/README.md`;
  - `CommandID.harnessSearch`, ⌘⇧O, «Buscar sesiones de agentes».

- [ ] **Step 1:** Pruebas de dominio:
  - `slowAdapterArrivesLater`;
  - `forkUnsupportedReportsCannotFork`;
  - `missingFolderOpensHome`.
- [ ] **Step 2:** XCUITest, con fixtures de los cuatro en homes temporales:
  - `chipsHaveNoGemini`;
  - `chipFiltersHarness`;
  - `typingFilters`;
  - `enterOpensPaneWithResumeCommand`;
  - `cmdEnterOnAntigravityShowsCannotFork`;
  - `missingDirectoryOpensHomeWithNotice`.
- [ ] **Step 3:** FAIL, implementar, verde (una corrida). Commit `feat(app): harness session search card`.

### Task 16: Columna del buscador en «Retomar donde quedaste»

**Files:**
- Modify: `App/Smalti/Restore/{RestoreController,RestoreView,RestoreRowView}.swift`
- Test: `App/SmaltiUITests/RestoreSearchTests.swift`

**Interfaces:**
- Consumes: T15 (misma `SessionSearchView`), T5 (filas de respaldo y de nvim).
- Produces: foco en dos columnas. Tab alterna. Esc en la derecha devuelve el foco a la izquierda. Enter y ⌘Enter en la derecha restauran lo marcado y luego llaman a `OpenHarnessSession` sobre el primer workspace restaurado (o uno nuevo).

- [ ] **Step 1:** Escribir las pruebas:
  - `tabMovesFocusBetweenColumns`;
  - `escInSearchColumnReturnsFocusWithoutDiscarding`;
  - `enterOnSessionRestoresThenOpens`;
  - `rowsShowEachHarnessCommand` (`codex resume …`, `agy --conversation …`, `opencode -s …`, `agy -c · la última del directorio`).
- [ ] **Step 2:** FAIL, implementar, verde (una corrida). Commit `feat(app): session search column on the restore screen`.

### Task 17: Neovim en la app: ⌘⇧E, «Editados por Claude», ⌘⇧L y ⌘-clic

**Files:**
- Create: `App/Smalti/Editor/{EditorCoordinator,PathClickInterceptor}.swift`
- Modify: `…/Domain/Commands/CommandCatalog.swift`, `…/Domain/Config/{CommandID,Keymap}.swift`, `App/Smalti/PaneContainerView.swift`
- Test: `App/SmaltiUITests/EditorTests.swift`

**Interfaces:**
- Produces:
  - `CommandID.editorOpenBeside` (⌘⇧E), `.editorOpenLastEdited` (⌘⇧L) y `.editorOpen(EditedFile)` (las filas del grupo «Editados por Claude», con subtítulo «línea N · hace 2 min»).
  - `PathClickInterceptor` intercepta ⌘-clic antes que libghostty solo si `EditorTarget.parse` da un archivo regular sin bytes nulos en sus primeros 8 KB. Si no, deja pasar el evento (F4.5).
  - Los paneles de nvim se lanzan con `-SmaltiNvimCommand` o `nvim`, más `--listen <EditorSocketPath>`.

- [ ] **Step 1:** Escribir las pruebas, con `-SmaltiNvimCommand "nvim --clean"` y un `-SmaltiEditorSocketDir` temporal corto:
  - `openBesideStartsNvimWithSocket`;
  - `editedFilesGroupListsInjectedEdits` (eventos `PostToolUse` por el socket de IPC, como las pruebas de F2);
  - `lastEditedJumpsExistingNvim`;
  - `cmdClickOnPathLineOpensNvim`;
  - `cmdClickOnUrlStillOpensLink`;
  - `cmdClickOnImageDoesNotOpenNvim`.
- [ ] **Step 2:** FAIL, implementar, verde (una corrida). Sin `nvim` sueltos tras la corrida. Commit `feat(app): open in Neovim from the palette and cmd-click`.

### Task 18: Observatorio con filtros y filas de OpenCode

**Files:**
- Create: `…/Domain/Observatory/ObservatoryFilter.swift`
- Modify: `…/Domain/Observatory/{ObservedSession,ObservatorySnapshot,ObservatoryTexts,ObservatoryReport}.swift`, `…/Application/ObserveAgents.swift`, `App/Smalti/Observatory/{ObservatoryView,ObservatoryController,SessionTableView}.swift`
- Test: `…/Observatory/ObservatoryFilterTests.swift`, `App/SmaltiUITests/ObservatoryFilterTests.swift`

**Interfaces:**
- Produces:
  - `enum ObservatoryFilter: CaseIterable { case all, claude, opencode, local }`, con títulos «Todas», «Claude Code», «OpenCode», «Locales»; `func includes(_ s: ObservedSession) -> Bool`; `next`;
  - `ObservatorySources` gana `usage: [any HarnessUsage]`;
  - `ObservedSession` gana `harness` e `isLocalModel`; su etiqueta es «OpenCode · qwen3:4b local»;
  - el resumen se recalcula sobre lo filtrado;
  - el pie es el de la spec;
  - `CommandID.observatoryFilter` (⌘⇧F).

- [ ] **Step 1:** Pruebas de dominio:
  - `localFilterKeepsOnlyLocalModels`;
  - `claudeNeverLocal`;
  - `summaryRecomputedForFilter`;
  - `opencodeRowLabelMarksLocal`;
  - `footerNamesOpenCode`.
- [ ] **Step 2:** XCUITest con el fixture de OpenCode en `-SmaltiOpenCodeDB`:
  - `chipsFilterTable`;
  - `cmdShiftFCyclesFilters`.
- [ ] **Step 3:** FAIL, implementar, verde (una corrida). Commit `feat(observatory): harness filters and OpenCode rows`.

### Task 19: Restaurar nvim, `--ide` e integraciones en ⌘K

**Files:**
- Modify: `App/Smalti/{SessionKeeper,ClaudeIntegrationStatus,AppComposition}.swift`
- Test: `App/SmaltiUITests/{IntegrationCatalogTests,EditorRestoreTests}.swift`

**Interfaces:**
- Consumes: T5, T12, T13.
- Produces:
  - al guardar, `EditorBridge.current` (200 ms) por cada panel de nvim de Smalti, en `PaneSnapshot.editor`;
  - `RestoreSession.Dependencies.claudeIDE = (estado de claudecodeNvim == .installed)`;
  - la caché de estado de F5.6 sirve las dos integraciones.

- [ ] **Step 1:** Escribir las pruebas:
  - `nvimPaneRestoresAtFileAndLine`;
  - `unresponsiveNvimRestoresAsProcess`;
  - `paletteOffersInstallClaudecodeOnNvChad` (un starter en `-SmaltiNvimConfigHome`);
  - `installThenOffersUninstall`;
  - `nonNvChadOffersNeither`.
- [ ] **Step 2:** FAIL, implementar, verde (una corrida). Commit `feat(app): restore Neovim panes and claudecode.nvim in the palette`.

### Revisión intermedia 2

- [ ] Revisor nuevo sobre el diff desde la revisión 1 (la app). Una sola tanda de correcciones, cada una con RED→GREEN: en la capa más barata, o revirtiendo y recompilando para XCUITest, todas las de la tanda en una sola corrida.
- [ ] Regresión una vez de las clases de UI tocadas en la fase (`HarnessCaptureTests`, `SessionSearchTests`, `RestoreSearchTests`, `EditorTests`, `ObservatoryFilterTests`, `IntegrationCatalogTests`, `EditorRestoreTests` y las de F2/F3/F5.6 que cambiaron: restaurar, Observatorio, ⌘K).
- [ ] Mutación `--changed-since` de la revisión 1; matar sobrevivientes a mano.
- [ ] `CLAUDE.md`: comandos de los paquetes nuevos, `record-fixtures.sh`, el saneador, `prepare-nvim-fixtures.sh` y la línea de `swift format lint`. Marcar el bloque en `progress.md`.

---

## Bloque 5 · Cierre

### Task 20: Mediciones, capturas, checklist y revisión final

- [ ] **Step 1:** C7: signpost `harness.search.open` con los cuatro fixtures, 7 aperturas en Debug, ≤ 100 ms.
- [ ] **Step 2:** Capturas en `docs/specs/F6-assets/`:
  - la tarjeta del buscador y la columna de «Retomar» junto a `Reanudar.dc.html`;
  - los filtros del Observatorio junto a `Observatorio.dc.html`;
  - ⌘K con «Editados por Claude».
- [ ] **Step 3:** `docs/specs/F6-checklist.md` con C1–C17, evidencia de cada uno y lo aplazado (uso real), en el formato de `F5.6-checklist.md`.
- [ ] **Step 4:** Revisión final de la rama (revisor nuevo, modelo más capaz), acotada según `.claude/rules/workflow.md`, con los hallazgos de las intermedias. Una sola tanda de correcciones.
- [ ] **Step 5:** Mutación completa de `SmaltiCore` (≥ 80 %; la fase cambia código compartido). Suites unitarias de todos los paquetes tocados y las clases de UI afectadas, en verde.

### Task 21: Limpieza, PRs y despliegue

- [ ] **Step 1:**
  - Matar `ollama serve` (y el PID 28617 del spike si sigue).
  - `brew uninstall --cask codex`, `brew uninstall opencode ollama`, `rm -rf ~/.ollama`.
  - Borrar `scripts/harnesses/recording.local/` y los homes del spike del scratchpad.
  - No tocar `agy`.
  - Comprobar con `pgrep` que no queda nada.
  - Anotar en el checklist que C2 se salta desde entonces con su motivo.
- [ ] **Step 2:** Versión 0.6.0, PR `feature/f6-multi-harness` → `develop` y PR `develop` → `main`. Simón aprueba y hace merge.
- [ ] **Step 3:** Despliegue, tras el merge a `main`, desde una sesión que no corra dentro del Smalti diario (comprobar el árbol de procesos):
  1. build Release;
  2. `osascript -e 'quit app "Smalti"'`;
  3. `/Applications/Smalti.app` → `/Applications/Smalti.app.old`;
  4. `ditto` del nuevo;
  5. `env -i … open -a /Applications/Smalti.app`.
- [ ] **Step 4:** `progress.md` y la tarjeta del KB (`kb-capture`) con la fase cerrada.

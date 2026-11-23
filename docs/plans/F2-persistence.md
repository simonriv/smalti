# F2 · Persistencia e integración con Claude Code — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (modo nativo, `.claude/rules/workflow.md`). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** builds `.dev` separados del Smalti diario; guardar y restaurar workspaces, scrollback con colores, historial por panel y sesiones de Claude; estado por panel alimentado por hooks de Claude Code vía socket y CLI; notificaciones, salto al agente que espera y arrastre de imágenes.

**Architecture:** la persistencia y el estado del agente son dominio puro en `SmaltiCore` (`Domain/Session`, `Domain/Agent`) con casos de uso que hablan con puertos nuevos. Cuatro paquetes de adaptador nuevos: `FileSessionAdapter`, `IPCAdapter` (con el ejecutable `smalti` y la librería `SmaltiIPCProtocol`), `ClaudeHarnessAdapter` y `UserNotificationsAdapter`. `GhosttyAdapter` añade exportar y reinyectar scrollback, historial por panel, `initial_input` y arrastre de archivos. La app es el composition root y aporta la pantalla "Retomar", el estado en la UI y el cableado del IPC.

**Tech Stack:** Swift 6.4 (Xcode 27.2), AppKit, Swift Testing, XCUITest, libghostty v1.4.0, Compression (LZFSE), sockets Unix de Darwin, UserNotifications, Claude Code 2.1.330 (`claude plugin …`), `scripts/mutation/mutate.py`.

**Spec:** `docs/specs/F2-persistence.md` (aprobada 2026-11-22) · Convenciones: `CLAUDE.md`, `.claude/rules/` · Diseño: `docs/design/README.md`, `Reanudar.dc.html`, `Main.dc.html`, `Paleta.dc.html`

## Global Constraints

- `SmaltiCore` solo importa `Foundation`, y solo para tipos de valor (`URL`, `Date`, `UUID`, `Calendar`). La guarda de imports no se toca. `Codable` (de la librería estándar) se permite en los tipos de la instantánea; `JSONEncoder` solo en el adaptador.
- Cada adaptador nuevo es el único que importa su framework (Compression → `FileSessionAdapter`; sockets de Darwin → `IPCAdapter`; UserNotifications → `UserNotificationsAdapter`; `Process` para `claude` → `ClaudeHarnessAdapter`) y tiene su prueba de guarda, copiada de `TOMLAdapterGuardTests`.
- Valores fijados: 10.000 líneas de scrollback por panel; retardo de guardado de estructura 1 s; scrollback cada 5 min y al salir; socket 0600 y directorio de estado 0700; mensaje IPC ≤ 1 MB (1.048.576 bytes); espera de conexión del CLI 500 ms, CLI < 1 s; título de sesión: primera línea del prompt, 80 caracteres; restaurar < 5 s con 3 workspaces y 6 paneles.
- Bundle IDs: Release `dev.simonriv.smalti` ("Smalti"), Debug `dev.simonriv.smalti.dev` ("Smalti Dev"). Estado: `~/Library/Application Support/<PRODUCT_NAME>/`. Plugin: `~/Library/Application Support/Smalti/claude-plugin/` (común a los dos builds).
- Variables de entorno de cada panel: `SMALTI=1`, `SMALTI_VERSION`, `SMALTI_PANE_ID`, `SMALTI_SOCKET`, `SMALTI_CLI`, `SMALTI_HISTORY_FILE`; `PATH` con `Contents/Resources/bin` delante.
- Textos de interfaz en español, tal cual el tablero o la lista de decisiones aprobada de la spec: "Retomar donde quedaste", "Cerraste … .", "Restaurar N paneles", "Solo layouts", "Empezar limpio", "Siempre restaurar", "· terminada", "te espera · 2m", "error · 3m", "N trabajando", "N te espera", "N error", "pide permiso para `…`", "terminó y te espera", "error: …", "Saltar al agente que espera", "Instalar integración con Claude Code", "Desinstalar integración con Claude Code", "Guardar layout actual como “…”", "Restaurar layout “…”", `── restaurado · 22 nov 23:48 ──`. Tokens solo desde `Theme.obsidian`; colores de etiqueta de `Reanudar.dc.html` añadidos ahí.
- Swift 6 estricto; errores `throws(Tipo)` con contexto; sin `!`/`try!`/`as!`/`unsafe*` sin comentario; ≤ 3 parámetros (agrupar en un tipo con nombre); `struct`/`enum` por defecto. Sin `switch` por variante de harness o de layout (OCP).
- Swift Testing, Arrange/Act/Assert, un concepto por prueba. TDD. Contrato compartido para cada puerto con más de una implementación (`SessionArchive`, `NamedLayouts`, `TelemetrySource`, `HarnessIntegration`, `Notifier` salvo el adaptador real de UserNotifications, que no corre fuera de un bundle: se documenta).
- UI tests: `XCUIApplication.isolatedSmalti()` con `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiConfigPath` y `-SmaltiStatePath` temporales, `$TMUX` de guarda y `PasteboardGuard`.
- Verificación: los comandos de `CLAUDE.md` más `swift test --package-path Packages/<Nuevo>` por cada paquete nuevo, y el lint ampliado a los paquetes nuevos. Suites > 30 s con `"$KB_ROOT/_system/bin/kb-progress" run <etiqueta> -- …`. Código de salida real, nunca una salida por pipe.
- Ramas: Bloque 1 en `feature/f2-dev-builds` → PR a `develop` (y `develop` → `main`) en cuanto pase su revisión; bloques 2–7 en `feature/f2-persistence`, creada desde `develop` con A fusionado (si aún no lo está, desde `feature/f2-dev-builds` y se rebasa después). Conventional Commits en inglés con las líneas de atribución de la sesión. Cada tarea se marca en `progress.md`. Nada se fusiona sin confirmación de Simón.
- Revisión por bloque: al cerrar cada bloque, un revisor nuevo sobre el diff del bloque; importantes antes del siguiente bloque, menores en una tanda al final del bloque, cada uno con su prueba RED→GREEN.

## Desviaciones de la spec (para revisar con el plan)

1. `DiscardLastSession` no se implementa: "Empezar limpio" deja la instantánea hasta el siguiente guardado (la spec lo dice así), y ningún otro flujo la borra.
2. `DeleteNamedLayout` no se implementa: ningún tablero ni comando de la spec lo usa (YAGNI). Se borra el archivo a mano hasta que haga falta.
3. El `TerminalEngine` recibe el `PaneID` en lugar de generarlo (`open(_:as:)`), para que un panel restaurado conserve su identidad: así su `SMALTI_PANE_ID`, su historial y su scrollback siguen siendo los mismos entre reinicios.
4. La línea de comandos para relanzar viaja en el evento `foregroundProcessChanged` (que ya existe) en lugar de un puerto nuevo.
5. Si en un workspace hay paneles desmarcados, el árbol se reconstruye con la estrategia del layout y se pierden los ratios manuales (la misma regla que un cambio estructural de F1).
6. Puerto pequeño `RestorePreferenceStore` para "Siempre restaurar" (`preferences.json`).

## Review Focus

1. **La ventana es más pequeña al restaurar que al guardar:** el árbol restaurado no cumple el mínimo de 240 × 120. Restaurar abre todos los paneles igualmente, sin error, y ningún frame baja de 1 pt (Task 7: `restoreKeepsAllPanesWhenTheAreaIsTooSmall`).
2. **El directorio guardado ya no existe** (rama borrada, carpeta movida): el panel abre en el `rootDirectory` del workspace y, si tampoco existe, en el home. Nunca se pierde el panel (Task 7: `missingDirectoryFallsBackToRootThenHome`).
3. **Smalti abierto dos veces con el mismo build:** la segunda instancia no roba el socket vivo de la primera ni lo borra (Task 18: `secondServerLeavesLiveSocketAlone`).
4. **Payload de hook raro:** campos desconocidos, sin `session_id`, prompt de varias líneas o de 10.000 caracteres. Los campos de más se ignoran, el título es la primera línea recortada a 80, y un evento sin sesión no crea agente (Task 16: `titleIsFirstLineTruncatedTo80`, `eventWithoutSessionCreatesNoAgent`; Task 18: `unknownFieldsAreIgnored`).
5. **Llega un evento de un panel que ya se cerró** (un hook rezagado): se ignora sin tocar ningún otro panel (Task 17: `eventForMissingPaneIsIgnored`).

---

## Mapa de archivos

```text
App/Smalti.xcodeproj                             T1 (Debug: bundle .dev, "Smalti Dev"), T19 (fase que copia el CLI y el plugin)
App/Smalti/AppIdentity.swift                     T1
App/Smalti/{AppComposition,TilingController}.swift   T1, T12, T13, T20, T22
App/Smalti/Restore/{RestoreView,RestoreRowView,RestoreController}.swift   T14
App/Smalti/{PaneHeaderView,PaneGridView,WorkspaceStripView}.swift (modif.)  T21
App/Smalti/Resources/claude-plugin/…            T19
App/SmaltiUITests/{IsolatedApp,SessionRestoreTests,NamedLayoutTests,AgentStatusTests,DragImageTests}.swift  T2, T15, T24
scripts/{test-ui.sh,bench/throughput.sh,check-daily-untouched.sh}   T2
scripts/tests/zsh-history-chain.test.sh          T11
scripts/measure-restore.sh                       T25

Packages/SmaltiCore/Sources/SmaltiCore/
  Domain/Config/LaunchSettings.swift (modif.)                       T1
  Domain/Session/{SessionSnapshot,SnapshotTree,PaneSnapshot,RestorePlan,
                  RestoreSelection,ClosedAtPhrase,RestoreBanner,LayoutName,ShellNames}.swift   T4–T6
  Domain/Agent/{AgentSession,AgentState,AgentEvent,AttentionQueue,AttentionNotice}.swift  T4 (tipos), T16
  Domain/{Pane,TerminalEvent,TerminalSessionSpec,PaneFileLocator}.swift (modif./nuevo)   T4, T7
  Application/{SessionArchive,PaneTranscripts,ScrollbackSource,NamedLayouts,
               RestorePreferenceStore,HarnessAdapter}.swift (puertos)                  T7
  Application/{SaveSession,LoadLastSession,RestoreSession,SaveNamedLayout,RestoreNamedLayout}.swift  T7
  Application/{TelemetrySource,Notifier,HarnessIntegration}.swift (puertos)            T17
  Application/{HandleAgentEvent,JumpToWaitingAgent,ClaudeIntegration}.swift           T17
  Application/{OpenPane,TerminalEngine,ChildEnvironment}.swift (modif.)                T7, T20
Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/{InMemorySessionArchive,…Contract}.swift  T7, T17

Packages/FileSessionAdapter/        T8
Packages/GhosttyAdapter/ (modif.)   T9, T10, T11, T23
Packages/ClaudeHarnessAdapter/      T12, T19
Packages/IPCAdapter/                T18   (productos SmaltiIPCProtocol, IPCAdapter, smalti)
Packages/UserNotificationsAdapter/  T22
docs/specs/F2-checklist.md          T25
```

---

## Bloque 1 · Builds `.dev` (Parte A, issue #6) — rama `feature/f2-dev-builds`

### Task 1: Identidad del build y directorio de estado

**Files:**
- Modify: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Config/LaunchSettings.swift`
- Create: `App/Smalti/AppIdentity.swift`
- Modify: `App/Smalti.xcodeproj/project.pbxproj` (Debug de la app: `PRODUCT_BUNDLE_IDENTIFIER = dev.simonriv.smalti.dev`, `PRODUCT_NAME = "Smalti Dev"`; Release igual), `App/Smalti/AppComposition.swift`, `App/Smalti/SmaltiAppDelegate.swift`
- Create: `scripts/tests/build-identity.test.sh`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/LaunchSettingsTests.swift`

**Interfaces:**
- Produces:
  - `LaunchSettings.statePathKey = "SmaltiStatePath"`; `init(arguments: [String: String], home: URL, defaultStateDirectory: URL)`; `public let stateDirectory: URL` (el argumento gana sobre el valor por defecto).
  - App: `struct AppIdentity { let bundleIdentifier: String; let productName: String; var isDevelopment: Bool; static let current: AppIdentity; func defaultStateDirectory(home: URL) -> URL }`. `isDevelopment` = el bundle ID termina en `.dev`. Todos los `Logger(subsystem:)` usan `AppIdentity.current.bundleIdentifier`.
  - Debug muestra `NSApp.dockTile.badgeLabel = "dev"`.

- [ ] **Step 1: Pruebas que fallan:** `stateDirectoryDefaultsToGivenDirectory`, `statePathArgumentOverridesDefault`; script `build-identity.test.sh`: construye Debug y Release (`xcodebuild -configuration <c> -derivedDataPath build`), y con `plutil -extract CFBundleIdentifier raw` comprueba `dev.simonriv.smalti.dev` en `Smalti Dev.app` y `dev.simonriv.smalti` en `Smalti.app` (C2).
- [ ] **Step 2:** Correr → fallan.
- [ ] **Step 3:** Implementar; `AppComposition.readStartup` crea el directorio de estado con 0700.
- [ ] **Step 4:** Pruebas, build Debug y lint en verde. `build/Build/Products/Debug/Smalti Dev.app` existe.
- [ ] **Step 5:** Commit `feat(app): separate development builds with their own identity and state`.

### Task 2: Pruebas y scripts que nunca tocan el Smalti diario

**Files:**
- Modify: `App/SmaltiUITests/IsolatedApp.swift` (añade `-SmaltiStatePath <tmp>`), `scripts/test-ui.sh`, `scripts/bench/throughput.sh`
- Create: `scripts/check-daily-untouched.sh`
- Modify: `CLAUDE.md` (sección Comandos: build Debug = "Smalti Dev"; la regla de no desarrollar desde Smalti desaparece de la tarjeta del KB en T25)

**Interfaces:**
- Produces: `XCUIApplication.stateDirectory: URL`, el directorio temporal de esta ejecución; `scripts/check-daily-untouched.sh <comando…>` anota el PID de `Smalti` (Release) y el `mtime` de su `session.json`, ejecuta el comando y falla si el PID murió o el archivo cambió.

- [ ] **Step 1:** Grep de `pkill`, `killall` y `-x Smalti` en `scripts/`: cada script termina por PID el proceso que lanzó (`$!`), y ningún script nombra el proceso "Smalti".
- [ ] **Step 2:** Prueba que falla: `MainWindowTests.testLaunchUsesIsolatedStateDirectory`, que lee la ruta de estado que la app publica como `accessibilityValue` de la ventana (solo en Debug) y la compara con `stateDirectory`.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Abrir el Release de `/Applications` y correr `scripts/check-daily-untouched.sh "$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh` → código 0 y las 35 pruebas `ok` (C1). Anotar el resultado para el PR.
- [ ] **Step 5:** Commit `test(app): isolate UI tests and scripts from the daily Smalti`.

### Task 3: Cierre del bloque 1 y PR de la Parte A

- [ ] **Step 1:** Suites de `CLAUDE.md` en verde (códigos de salida), lint.
- [ ] **Step 2:** Revisión del diff del bloque con un revisor nuevo; correcciones según `.claude/rules/workflow.md`.
- [ ] **Step 3:** `progress.md` (F2: spec aprobada, plan, T1–T3). PR `feature/f2-dev-builds` → `develop` con la spec, el plan y la evidencia de C1/C2, con el token de `simonriv` (`GH_TOKEN=$(gh auth token --user simonriv)`). **Pedir a Simón la confirmación para fusionar** y, después, el PR `develop` → `main`.

---

## Bloque 2 · Dominio de la persistencia — rama `feature/f2-persistence`

### Task 4: Instantánea, árbol serializable y tipos del agente

**Files:**
- Create: `Domain/Session/{SessionSnapshot,SnapshotTree,PaneSnapshot,ShellNames}.swift`, `Domain/Agent/{AgentSession,AgentState}.swift`
- Modify: `Domain/Pane.swift`, `Domain/TerminalEvent.swift`, `Domain/Geometry/SplitAxis.swift` (`Codable`), `GhosttyAdapter/ProcessNameTracker.swift` (solo para compilar: `commandLine: nil` hasta T9)
- Test: `Tests/SmaltiCoreTests/Domain/SessionSnapshotTests.swift`, `SnapshotTreeTests.swift`, `PaneTests.swift`

**Interfaces:**
- Produces:
  - `TerminalEvent.foregroundProcessChanged(ForegroundProcess)` con `public struct ForegroundProcess: Equatable, Sendable { name: String; commandLine: [String]? }`.
  - `Pane` gana `commandCount: Int` (+1 por `commandFinished`), `foregroundCommandLine: [String]?` y `agent: AgentSession?` (sin transiciones hasta T16), con `var isAtShell: Bool` (`processName == nil || ShellNames.contains(processName)`).
  - `public enum ShellNames { static func contains(_ name: String) -> Bool }`: `zsh`, `bash`, `fish`, `sh`, también con `-` delante.
  - `public struct HarnessID: Hashable, Codable, Sendable, RawRepresentable` con `static let claude`.
  - `public enum AgentState: Equatable, Sendable { case working; case waiting(since: Date, reason: WaitReason); case failed(since: Date, message: String); case stopped }`, con `WaitReason: .turnFinished | .permission(String) | .attention(String)` y `var kind: AgentStateKind` (`Codable`: `working`, `waiting`, `failed`, `stopped`).
  - `public struct AgentSession: Equatable, Sendable { harness: HarnessID; sessionID: String; title: String?; state: AgentState; startedAt: Date }`.
  - `public indirect enum SnapshotTree: Codable, Equatable, Sendable { case leaf(index: Int); case split(axis: SplitAxis, ratio: Double, first: SnapshotTree, second: SnapshotTree) }`, con `init(_ tree: LayoutTree, order: [PaneID])` y `func layoutTree(ids: [PaneID]) -> LayoutTree?` (nil si un índice no existe).
  - `public struct AgentSnapshot: Codable, Equatable, Sendable { harness: HarnessID; sessionID: String; title: String?; lastState: AgentStateKind }`.
  - `public struct RelaunchCommand: Codable, Equatable, Sendable { arguments: [String]; var displayText: String }` (los argumentos escapados para el shell, unidos con espacios).
  - `public struct PaneSnapshot: Codable, Equatable, Sendable { id: UUID; workingDirectory: String; title: String?; processName: String?; scrollbackLines: Int; commandCount: Int; relaunch: RelaunchCommand?; agent: AgentSnapshot? }`.
  - `public struct WorkspaceSnapshot: Codable, Equatable, Sendable { name: String; rootDirectory: String; layout: String; tree: SnapshotTree?; focusedIndex: Int?; panes: [PaneSnapshot] }`.
  - `public struct SessionSnapshot: Codable, Equatable, Sendable { static let formatVersion = 1; version: Int; savedAt: Date; workspaces: [WorkspaceSnapshot]; activeIndex: Int }`, con `static func capture(_ set: WorkspaceSet, scrollbackLines: [PaneID: Int], at: Date) -> SessionSnapshot`. `relaunch` solo si `!isAtShell && agent == nil && foregroundCommandLine != nil`.

- [ ] **Step 1: Pruebas que fallan:** `treeRoundTripsThroughIndices` (Dwindle de 3 con ratios editados), `treeWithUnknownIndexYieldsNil`, `captureKeepsOrderLayoutFocusAndDirectories` (0, 1 y 9 paneles), `captureRecordsRelaunchOnlyForNonShellNonAgent`, `captureKeepsAgentSnapshot`, `commandFinishedCountsCommands`, `dashPrefixedLoginShellIsAShell`, `snapshotRoundTripsThroughJSON` (con `JSONEncoder` en la prueba).
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** SmaltiCore y GhosttyAdapter en verde.
- [ ] **Step 5:** Commit `feat(core): add session snapshot and agent session types`.

### Task 5: `RestorePlan` y selección por defecto

**Files:**
- Create: `Domain/Session/{RestorePlan,RestoreSelection}.swift`
- Test: `Tests/SmaltiCoreTests/Domain/RestorePlanTests.swift`

**Interfaces:**
- Consumes: T4.
- Produces:
  - `public enum RestoreMode: Sendable { case full, layoutsOnly }`
  - `public struct RestoreSelection: Equatable, Sendable { var unchecked: Set<UUID>; static func defaults(for: SessionSnapshot) -> RestoreSelection; func toggling(_ id: UUID) -> RestoreSelection; func checkedCount(in: SessionSnapshot) -> Int }`. Por defecto desmarca los paneles con `relaunch` y los agentes con `lastState == .stopped`.
  - `public enum PaneLaunch: Equatable, Sendable { case shell; case resume(AgentSnapshot); case relaunch(RelaunchCommand) }`
  - `public struct PlannedPane: Equatable, Sendable { id: UUID; workingDirectory: String; restoresScrollback: Bool; restoresHistory: Bool; launch: PaneLaunch }`
  - `public struct PlannedWorkspace: Equatable, Sendable { name: String; rootDirectory: String; layout: LayoutID; tree: SnapshotTree?; focusedIndex: Int?; panes: [PlannedPane] }`
  - `public struct RestorePlan: Equatable, Sendable { workspaces: [PlannedWorkspace]; activeIndex: Int; static func make(from: SessionSnapshot, mode: RestoreMode, selection: RestoreSelection) -> RestorePlan }`
  - Reglas: `.full` → `restoresHistory = true`; `restoresScrollback` solo si el panel no tenía agente ni `relaunch` (estaba en el shell); `launch` según el panel. `.layoutsOnly` → todo `false` y `.shell`. Desmarcado → fuera. Workspace sin paneles → fuera. Si se quitó algún panel, `tree = nil` (se reconstruye con la estrategia; desviación 5) y `focusedIndex` se ajusta; `activeIndex` apunta al mismo workspace o al primero.

- [ ] **Step 1: Pruebas que fallan:** `fullRestoresShellScrollbackAndHistory`, `agentPaneResumesWithoutScrollback`, `relaunchPaneRunsCommandWithoutScrollback`, `layoutsOnlyOpensCleanShells`, `uncheckedPaneIsSkipped`, `workspaceWithoutCheckedPanesIsSkipped`, `removedPaneDropsManualTree`, `activeIndexFollowsSkippedWorkspaces`, `defaultsUncheckRelaunchAndStoppedAgents`, `checkedCountCountsSelectedPanes`, `emptySnapshotPlansNothing`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): plan session restores with a default selection`.

### Task 6: Frases de fecha y nombres de layout

**Files:**
- Create: `Domain/Session/{ClosedAtPhrase,RestoreBanner,LayoutName}.swift`
- Test: `Tests/SmaltiCoreTests/Domain/ClosedAtPhraseTests.swift`, `LayoutNameTests.swift`

**Interfaces:**
- Produces:
  - `public enum ClosedAtPhrase { static func text(closedAt: Date, now: Date, calendar: Calendar) -> String }`: "hoy a las 18:05"; día anterior desde las 18:00 → "anoche a las 23:48"; día anterior antes de las 18:00 → "ayer a las 14:10"; anteriores → "el jue 20 a las 09:12". Días con tabla fija `["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]`; horas a dos dígitos.
  - `public enum RestoreBanner { static func text(savedAt: Date, calendar: Calendar) -> String }` → `── restaurado · 22 nov 23:48 ──` (meses `["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]`).
  - `public struct LayoutName: Hashable, Sendable { let rawValue: String; init(_ raw: String) throws(LayoutNameError) }`: recorta espacios; vacío, más de 60 caracteres, `/`, `:` o empezar por `.` → `LayoutNameError.invalid(name:reason:)`.

- [ ] **Step 1: Pruebas que fallan** (calendario gregoriano, `TimeZone(identifier: "America/Bogota")`): `sameDayIsToday`, `previousEveningIsLastNight`, `previousAfternoonIsYesterday`, `exactlySixPmIsLastNight`, `olderDateUsesWeekdayAndDay`, `crossesMonthBoundary` (1 dic vs 30 nov), `usesGivenTimeZone` (el mismo instante en UTC y Bogotá da días distintos), `bannerFormatsDayMonthAndTime`, `layoutNameTrimsSpaces`, `layoutNameRejectsEmptySlashAndLong`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): add restore date phrases and layout names`.

### Task 7: Puertos y casos de uso de persistencia

**Files:**
- Create: `Application/{SessionArchive,PaneTranscripts,ScrollbackSource,NamedLayouts,RestorePreferenceStore,HarnessAdapter}.swift`, `Application/{SaveSession,LoadLastSession,RestoreSession,SaveNamedLayout,RestoreNamedLayout}.swift`, `Domain/PaneFileLocator.swift`
- Modify: `Application/{TerminalEngine,OpenPane}.swift`, `Domain/TerminalSessionSpec.swift`, `SmaltiCoreTestSupport/FakeTerminalEngine.swift`; `GhosttyTerminalEngine` adopta `open(_:as:)` (mínimo para compilar)
- Create: `SmaltiCoreTestSupport/{InMemorySessionArchive,InMemoryNamedLayouts,FakeScrollbackSource,FakeHarnessAdapter,SessionArchiveContract,NamedLayoutsContract}.swift`
- Test: `Tests/SmaltiCoreTests/Application/{SaveSessionTests,RestoreSessionTests,NamedLayoutTests}.swift`, contratos con los fakes

**Interfaces:**
- Consumes: T4–T6.
- Produces:
  - `TerminalEngine.open(_ spec: TerminalSessionSpec, as pane: PaneID) throws(TerminalEngineError)` sustituye a `open(_:) -> PaneID` (desviación 3). `OpenPane` genera el `PaneID`.
  - `public struct Scrollback: Equatable, Sendable { enum Format { case vt, plain }; text: String; format: Format; var lineCount: Int }`
  - `public struct PaneRestoration: Equatable, Sendable { scrollback: Scrollback?; savedAt: Date }`. `TerminalSessionSpec` gana `restoration: PaneRestoration?` e `initialInput: String?` (por defecto nil).
  - `public struct PaneFileLocator: Sendable { init(stateDirectory: URL); func historyFile(for: PaneID) -> URL }` → `<estado>/history/<uuid>.zsh_history`.
  - Puertos (`@MainActor`):
    - `SessionArchive { func save(_ snapshot: SessionSnapshot) throws(SessionArchiveError); func lastSession() -> LastSession }`, con `LastSession: .none | .saved(SessionSnapshot) | .unreadable(reason: String)` y `SessionArchiveError.writeFailed(file: String, reason: String)`.
    - `PaneTranscripts { func keep(_ scrollback: Scrollback, for pane: PaneID) throws(SessionArchiveError); func scrollback(of pane: PaneID) -> Scrollback?; func forget(allExcept panes: Set<PaneID>) }`
    - `ScrollbackSource { func scrollback(of pane: PaneID, lastLines: Int) throws(ScrollbackError) -> Scrollback }`, con `ScrollbackError.unavailable(pane: PaneID, reason: String)`.
    - `NamedLayouts { func save(_ layout: WorkspaceSnapshot, as name: LayoutName) throws(SessionArchiveError); func layout(named: LayoutName) throws(SessionArchiveError) -> WorkspaceSnapshot; func names() -> [LayoutName] }`
    - `RestorePreferenceStore { func current() -> RestorePreference; func set(_ preference: RestorePreference) throws(SessionArchiveError) }`, con `RestorePreference: .ask | .always`.
    - `HarnessAdapter { var harness: HarnessID { get }; func resumeCommand(for agent: AgentSnapshot) -> String }`; los adaptadores se agrupan en `HarnessRegistry { init(_ adapters: [any HarnessAdapter]); func adapter(for: HarnessID) -> (any HarnessAdapter)? }`, sin `switch`.
  - `SaveSession { init(archive:, transcripts:, scrollback:); func saveStructure(of set: WorkspaceSet, at: Date) -> SaveOutcome; func saveWithScrollback(of set: WorkspaceSet, at: Date) -> SaveOutcome }`. `saveWithScrollback` exporta solo los paneles con `isAtShell`, los guarda, guarda la instantánea con sus `scrollbackLines` y llama a `forget(allExcept:)`. `SaveOutcome: .saved | .failed(String)`; un fallo de un panel no impide guardar los demás.
  - `LoadLastSession { init(archive:, preferences:); func execute() -> StartupChoice }`, con `StartupChoice: .startFresh | .ask(SessionSnapshot) | .restoreAll(SessionSnapshot) | .startFreshAfterUnreadable(reason: String)`.
  - `RestoreSession { struct Dependencies { engine; transcripts; harnesses: HarnessRegistry; environment: PaneEnvironment }; func execute(_ plan: RestorePlan, savedAt: Date, home: WorkingDirectory) -> RestoreResult }`, con `RestoreResult { set: WorkspaceSet?; failures: [String] }`. Abre cada panel con `PaneID(rawValue: planned.id)`, scrollback de `transcripts`, `initialInput` (`resumeCommand + "\n"` o `relaunch.displayText + "\n"`), sin comprobar el tamaño mínimo (Review Focus 1); si el motor falla con `surfaceCreationFailed`, reintenta en `rootDirectory` y luego en `home` (Review Focus 2). Árbol: `tree?.layoutTree(ids:)` o, si es nil, la estrategia.
  - `PaneEnvironment` (T20 lo amplía): `struct PaneEnvironment { version: String; files: PaneFileLocator; func variables(for pane: PaneID) -> [String: String] }` = `ChildEnvironment` + `SMALTI_PANE_ID` + `SMALTI_HISTORY_FILE`. `OpenPane` lo recibe en lugar de `version:`.
  - `SaveNamedLayout { init(layouts:); func execute(_ workspace: Workspace, as name: LayoutName) throws(SessionArchiveError) }` (sin scrollback).
  - `RestoreNamedLayout { init(layouts:, restore: RestoreSession); func execute(_ name: LayoutName, into set: inout WorkspaceSet, home:) throws(SessionArchiveError) -> NamedLayoutOutcome }`. Workspace nuevo con el nombre del layout, todos los `relaunch` ejecutados, agentes reanudados salvo los que ya están vivos en `set` (mismo `sessionID`), que abren un shell y salen en `NamedLayoutOutcome.skippedLiveSessions: [String]`.

- [ ] **Step 1: Pruebas que fallan:**
  - Contratos `SessionArchiveContract` y `NamedLayoutsContract` con los fakes (`saveThenLoadReturnsSnapshot`, `emptyArchiveHasNoSession`, `namesListsSavedLayouts`, `missingLayoutThrows`).
  - `saveStructureWritesSnapshotWithoutExporting`, `saveWithScrollbackExportsOnlyShellPanes`, `failingPaneExportStillSavesOthers`, `saveForgetsClosedPanes`.
  - `loadAsksWhenPreferenceIsAsk`, `loadRestoresAllWhenAlways`, `loadReportsUnreadable`.
  - `restoreKeepsPaneIdentity`, `restoreFeedsScrollbackOnlyWhenPlanned`, `restoreResumesAgentWithHarnessCommand`, `restoreRelaunchesCommand`, `restoreUsesSavedRatios`, `restoreRebuildsTreeWhenNil`, `restoreKeepsAllPanesWhenTheAreaIsTooSmall`, `missingDirectoryFallsBackToRootThenHome`, `paneEnvironmentCarriesPaneIDAndHistoryFile`.
  - `namedLayoutOpensNewWorkspaceWithItsName`, `namedLayoutSkipsSessionAlreadyLive`, `namedLayoutRunsSavedCommands`.
  - Las pruebas de `OpenPane` existentes, adaptadas a `open(_:as:)`.
- [ ] **Step 2–4:** Rojo → implementar → verde (`SmaltiCore`, `GhosttyAdapter` compila, `xcodebuild … build`).
- [ ] **Step 5:** Commit `feat(core): add persistence ports and session use cases`.
- [ ] **Step 6: Cierre del bloque 2:** revisión del diff del bloque (revisor nuevo), correcciones, `progress.md`.

---

## Bloque 3 · Adaptadores de persistencia

### Task 8: `FileSessionAdapter`

**Files:**
- Create: `Packages/FileSessionAdapter/{Package.swift, Sources/FileSessionAdapter/{FileSessionArchive,StateDirectory,LZFSECodec,AtomicFile}.swift, Tests/FileSessionAdapterTests/{…ContractTests,FileSessionArchiveTests,FileAdapterGuardTests}.swift}`
- Modify: `App/Smalti.xcodeproj` (dependencia del paquete)

**Interfaces:**
- Consumes: puertos de T7.
- Produces: `public final class FileSessionArchive: SessionArchive, PaneTranscripts, NamedLayouts, RestorePreferenceStore { public init(directory: URL) }`, con el formato en disco de la spec (`session.json`, `scrollback/<uuid>.lzfse`, `layouts/<nombre>.json`, `preferences.json`). JSON con `.sortedKeys` y fechas ISO 8601.

- [ ] **Step 1: Pruebas que fallan:** los contratos de T7 con el adaptador sobre un directorio temporal; `directoryIsCreatedWith0700`; `scrollbackRoundTripsCompressed` (con 10.000 líneas VT, archivo menor que el texto); `corruptSnapshotIsMovedAsideAndReported` (C5: queda `session.corrupt-<fecha>.json` y se devuelve `.unreadable`); `unknownVersionIsMovedAside`; `interruptedWriteKeepsPreviousSnapshot` (una escritura que falla a mitad, simulada con un directorio de solo lectura para el temporal, no reemplaza el archivo bueno); `forgetRemovesOrphanScrollbackAndHistory`; `preferenceDefaultsToAsk`; `layoutFileNameComesFromLayoutName`; guarda de imports (solo este paquete importa Compression).
- [ ] **Step 2–4:** Rojo → implementar (`compression_encode_buffer` con `COMPRESSION_LZFSE`; escritura atómica con temporal y `rename`) → verde.
- [ ] **Step 5:** Commit `feat(session): add file-backed session archive`.

### Task 9: Exportar el scrollback y leer la línea de comandos

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{ScrollbackExporter,ProcessArguments,ScrollbackTrimmer}.swift`
- Modify: `GhosttyRuntime.swift` (interceptar `GHOSTTY_ACTION_OPEN_URL` mientras haya una exportación en curso para esa superficie), `GhosttyTerminalEngine.swift` (adopta `ScrollbackSource`), `ProcessNameTracker.swift` (rellena `commandLine`)
- Test: `Tests/GhosttyAdapterTests/{ScrollbackExportTests,ScrollbackTrimmerTests,ProcessArgumentsTests}.swift`

**Interfaces:**
- Produces: `GhosttyTerminalEngine: ScrollbackSource`; `enum ScrollbackTrimmer { static func lastLines(_ text: String, count: Int) -> String }` (antepone `ESC[0m`); `enum ProcessArguments { static func of(pid: pid_t) -> [String]? }` con `sysctl(KERN_PROCARGS2)`.

- [ ] **Step 1: Verificación previa (riesgo de la spec):** en una prueba con superficie real (patrón de `SurfaceLifetimeTests`), `ghostty_surface_binding_action(surface, "write_scrollback_file:open,vt")` y comprobar si el `OPEN_URL` llega dentro de la llamada (síncrono) o después. Anotar el resultado en el commit. Si es asíncrono, el exportador espera con un `CheckedContinuation` de hasta 500 ms.
- [ ] **Step 2: Pruebas que fallan:** `exportReturnsVTWithColors` (la superficie corre `printf '\e[31mrojo\e[0m\n'`; el VT contiene `\e[31m` y `rojo`); `exportFallsBackToPlainWhenVTFails` (C7: con el exportador VT forzado a fallar por una dependencia inyectada, devuelve `.plain` con `rojo`); `exportDoesNotOpenTheFile` (el temporal se borra y no hay `NSWorkspace.open`); `trimmerKeepsLastLines` (10.001 → 10.000); `trimmerPrefixesReset`; `argumentsOfOwnProcess` (`ProcessArguments.of(getpid())` contiene el ejecutable de la prueba); `argumentsOfMissingProcessIsNil`.
- [ ] **Step 3–4:** Implementar → verde.
- [ ] **Step 5:** Commit `feat(ghostty): export scrollback with colors and read relaunch commands`.

### Task 10: Reinyectar el scrollback y escribir el comando inicial

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/RestoreLauncher.swift`
- Modify: `GhosttySurfaceView.swift` (`initial_input`, comando del lanzador, `SMALTI_RESTORE_FILE`)
- Test: `Tests/GhosttyAdapterTests/RestoreLauncherTests.swift`, `SurfaceLifetimeTests.swift` (caso nuevo)

**Interfaces:**
- Consumes: `PaneRestoration`, `RestoreBanner` (T6, T7).
- Produces: `struct RestoreLauncher { static func command(shell: TerminalCommand, restoreFile: URL, banner: String) -> String }` → `/bin/sh -c 'cat "$SMALTI_RESTORE_FILE"; rm -f "$SMALTI_RESTORE_FILE"; printf "\033[38;2;139;145;156m%s\033[0m\n" "<banner>"; exec <shell>'`. Con `.loginShell`, `<shell>` es `exec -l "$SHELL"`, o la forma que mantenga el login shell según la verificación del Step 1. El archivo se escribe con 0600 en el directorio temporal del usuario.

- [ ] **Step 1: Verificación previa (riesgo de la spec):** con `shell-integration = zsh`, lanzar una superficie con el lanzador y `zsh` (no `-f`) con un `ZDOTDIR` temporal vacío. Comprobar que llega `workingDirectoryChanged` (OSC 7 de la integración) y que `$0` empieza por `-` con login shell. Si la integración no llega, el lanzador exporta a mano el `ZDOTDIR` de Ghostty (`$GHOSTTY_RESOURCES_DIR/shell-integration/zsh`). Anotar el resultado.
- [ ] **Step 2: Pruebas que fallan:** `launcherQuotesBannerAndShell`, `launcherKeepsCustomShellCommand`; con superficie real: `restoredSurfacePrintsScrollbackThenStartsShell` (el texto de `read_text` contiene el scrollback, el banner y después el prompt), `restoreFileIsRemovedAfterStart`, `initialInputIsTypedIntoTheShell` (`initialInput = "echo listo-$((40+2))\n"` → aparece `listo-42`).
- [ ] **Step 3–4:** Implementar → verde.
- [ ] **Step 5:** Commit `feat(ghostty): replay saved scrollback and initial input in restored panes`.

### Task 11: Historial por panel sin romper el compartido

**Files:**
- Create: `App/Smalti/Resources/zsh/.zshenv` (copiado a `Contents/Resources/smalti/zsh/`), `scripts/tests/zsh-history-chain.test.sh`
- Modify: `GhosttySurfaceView.swift` (si el spec trae `SMALTI_HISTORY_FILE`, exporta `ZDOTDIR=<recursos>/smalti/zsh` y `SMALTI_USER_ZDOTDIR` con el `ZDOTDIR` previo o `$HOME`), `App/Smalti.xcodeproj` (recurso)

**Interfaces:**
- Produces: el `.zshenv` de Smalti restaura `ZDOTDIR="$SMALTI_USER_ZDOTDIR"`, carga `$ZDOTDIR/.zshenv` si existe y registra, con `add-zsh-hook`, un `precmd` de un solo uso y un `zshaddhistory`:
  - El `zshaddhistory` hace `print -r -- "${1%%$'\n'}" >> "$SMALTI_HISTORY_FILE"` y devuelve 0, así que zsh guarda el comando también en su historial normal.
  - El `precmd`, si existe `$SMALTI_HISTORY_FILE`, hace `fc -R "$SMALTI_HISTORY_FILE"` y se quita a sí mismo.
  - El orden con la integración de Ghostty: Ghostty pone su `ZDOTDIR` y guarda el anterior (el de Smalti) en `GHOSTTY_ZSH_ZDOTDIR`; su `.zshenv` restaura el de Smalti y lo carga. Se confirma en el Step 1.

- [ ] **Step 1: Prueba que falla (script, C8):** `zsh-history-chain.test.sh` crea un `ZDOTDIR` de usuario temporal con `HISTFILE=$tmp/shared`, `setopt SHARE_HISTORY` e `INC_APPEND_HISTORY`. Corre `zsh -i` con el `ZDOTDIR` de Smalti y `SMALTI_HISTORY_FILE=$tmp/pane`, y le pasa por stdin `echo uno; echo dos`. Comprueba que `pane` y `shared` contienen los dos comandos. Una segunda corrida ejecuta `fc -ln -1` en el primer prompt y debe dar `echo dos`. Salida `[n/total] ok|FAIL`.
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Script y GhosttyAdapter en verde; con `/bin/zsh -f` no cambia nada (`testIsolatedShellsSeeTheTmuxGuard` sigue en verde).
- [ ] **Step 5:** Commit `feat(ghostty): keep a per-pane zsh history next to the shared one`.

### Task 12: `ClaudeHarnessAdapter` (reanudación) y cableado de la persistencia

**Files:**
- Create: `Packages/ClaudeHarnessAdapter/{Package.swift, Sources/ClaudeHarnessAdapter/ClaudeHarness.swift, Tests/…/{ClaudeHarnessTests,HarnessAdapterContractTests,ClaudeAdapterGuardTests}.swift}`
- Create: `SmaltiCoreTestSupport/HarnessAdapterContract.swift`
- Modify: `App/Smalti/AppComposition.swift`, `TilingController.swift` (guardado con retardo de 1 s tras cambios estructurales o de directorio; temporizador de 5 min; `applicationShouldTerminate` → `saveWithScrollback` y después responde `.terminateNow`)

**Interfaces:**
- Produces: `public struct ClaudeHarness: HarnessAdapter` → `harness = .claude`, `resumeCommand` = `claude --resume <id>` con el id escapado para el shell.

- [ ] **Step 1: Pruebas que fallan:** `resumeCommandUsesSessionID`, `sessionIDIsShellEscaped` (`a'b`), el contrato `resumeCommandStartsWithHarnessBinary` y la guarda.
- [ ] **Step 2–4:** Rojo → implementar → verde; build de la app.
- [ ] **Step 5:** Commit `feat(claude): resume Claude Code sessions and wire session saving`.
- [ ] **Step 6: Cierre del bloque 3:** revisión del diff del bloque, correcciones, `progress.md`.

---

## Bloque 4 · Restaurar en la app

### Task 13: Arranque con instantánea y restauración

**Files:**
- Modify: `App/Smalti/AppComposition.swift`, `TilingController.swift`, `StatusMessage.swift`

**Interfaces:**
- Consumes: `LoadLastSession`, `RestorePlan`, `RestoreSession` (T5, T7).
- Produces: `TilingController.start(with choice: StartupChoice)`:
  - `.startFresh` → como F1.
  - `.restoreAll` → `RestorePlan.make(…, .full, .defaults)` + `RestoreSession`.
  - `.ask` → muestra Retomar (T14).
  - `.startFreshAfterUnreadable` → F1 y un aviso en la barra: "No se pudo leer la sesión anterior: <motivo>".
  - Signposts `restore.start` y `restore.done`; `done` llega cuando cada panel restaurado emitió su primer `workingDirectoryChanged`.
  - Ese texto de aviso no está en la spec: es una variante de los avisos de F1. Se señala en el PR.

- [ ] **Step 1: Prueba que falla (XCUITest, en T15 se amplía):** `SessionRestoreTests.testAlwaysRestoreReopensWorkspaces`, con un estado sembrado: el test escribe un `session.json` de fixture con 2 workspaces en `stateDirectory` y `preferences.json` con `always`.
- [ ] **Step 2–4:** Implementar → verde (`scripts/test-ui.sh SessionRestoreTests`).
- [ ] **Step 5:** Commit `feat(app): restore the last session at launch`.

### Task 14: Pantalla "Retomar donde quedaste"

**Files:**
- Create: `App/Smalti/Restore/{RestoreController,RestoreView,RestoreRowView}.swift`
- Modify: `Domain/Theme/Theme+Obsidian.swift` y `Theme.swift` (tokens de `Reanudar.dc.html`: colores de etiqueta de Claude Code y de shell, botón primario, radios 8 y 9), `ObsidianThemeTests.swift`

**Interfaces:**
- Consumes: `SessionSnapshot`, `RestoreSelection`, `ClosedAtPhrase`, `RestorePreferenceStore`.
- Produces: `RestoreController(snapshot:, preferences:, onChoice: (RestoreChoice) -> Void)`, con `RestoreChoice: .restore(RestoreSelection) | .layoutsOnly | .startClean`. Teclado: ↑↓, espacio, ↵, ⌘L, esc, ⌘,. Identificadores de accesibilidad: `restore.row.<uuid>`, `restore.primary`, `restore.layoutsOnly`, `restore.startClean`, `restore.always`.

- [ ] **Step 1: Prueba que falla:** tokens nuevos en `ObsidianThemeTests` (`restoreTagColorsMatchBoard`).
- [ ] **Step 2:** Implementar la vista con las medidas de la spec (título 20/600, subtítulo 12,5, nombre de workspace 13/600, filas `.item` con padding 9 × 12 y radio 9, etiqueta 10,5/500 con radio de píldora, código JetBrains Mono 11,5 `#8b919c`, botones de 36 px de alto y radio 8).
- [ ] **Step 3:** Captura frente a `Reanudar.dc.html` (columna izquierda) renderizado con Chrome a 1440 × 900, superpuesta al 50 % → `docs/specs/F2-assets/c18-restore-overlay.png`.
- [ ] **Step 4:** Commit `feat(app): add the resume screen`.

### Task 15: Layouts con nombre en ⌘K y UI tests de restauración

**Files:**
- Modify: `Domain/Config/CommandID.swift` (`layoutSave`, `layoutRestore(LayoutName)`), `Domain/Commands/CommandCatalog.swift`, `CommandPaletteController.swift` (si la consulta empieza por algo que no es un comando, ofrece "Guardar layout actual como “<consulta>”")
- Create: `App/SmaltiUITests/{SessionRestoreTests,NamedLayoutTests}.swift`
- Test: `CommandCatalogTests.swift`

**Interfaces:**
- Produces: `CommandCatalog.commands(for:keymap:layouts:savedLayouts: [NamedLayoutSummary])`, con `NamedLayoutSummary { name: LayoutName; paneCount: Int; agentCount: Int }`. Subtítulo: "— N paneles, retoma M sesiones de Claude" (sin la cláusula de las sesiones si M = 0), en el grupo "Workspaces y sesiones".

- [ ] **Step 1: Pruebas que fallan:**
  - Dominio: `catalogListsSavedLayoutsWithSubtitle`, `catalogOmitsAgentClauseWithoutAgents`, `saveCommandUsesQueryAsName`.
  - XCUITest:
    - `testQuitAndRelaunchRestoresScrollbackWithColors` (C7: `printf '\e[32mverde-smalti\e[0m\n'`, ⌘Q, relanzar con el mismo `stateDirectory`, ↵ en Retomar → el panel contiene `verde-smalti` y el banner);
    - `testResumeScreenListsWorkspacesAndCounts` (C9);
    - `testResumeScreenIsKeyboardOnly` (↓, espacio y ↵ restauran N − 1 paneles);
    - `testLayoutsOnlyOpensCleanShells`;
    - `testStartCleanKeepsSnapshotUntilNextSave`;
    - `NamedLayoutTests.testSaveAndRestoreNamedLayout` (C10: el layout restaurado abre un workspace nuevo con el nombre y el comando de arranque, `sleep 300` con `echo arranque-ok` delante).
- [ ] **Step 2–4:** Rojo → implementar → verde (`kb-progress run e2e -- scripts/test-ui.sh SessionRestoreTests`, después `NamedLayoutTests`).
- [ ] **Step 5:** Commit `feat(app): named layouts in the palette and restore UI tests`.
- [ ] **Step 6: Cierre del bloque 4:** revisión del diff del bloque, correcciones, `progress.md`.

---

## Bloque 5 · Estado del agente, IPC y plugin

### Task 16: Transiciones del agente y cola de atención

**Files:**
- Create: `Domain/Agent/{AgentEvent,AttentionQueue,AttentionNotice,AgentCounts}.swift`
- Modify: `Domain/Agent/AgentSession.swift`, `Domain/Pane.swift`, `Domain/Workspace/Workspace.swift`
- Test: `Tests/SmaltiCoreTests/Domain/{AgentTransitionTests,AttentionQueueTests,AttentionNoticeTests}.swift`

**Interfaces:**
- Consumes: T4.
- Produces:
  - `public enum AgentHook: String, CaseIterable, Sendable { case sessionStart = "SessionStart", userPromptSubmit = "UserPromptSubmit", postToolUse = "PostToolUse", permissionRequest = "PermissionRequest", notification = "Notification", stop = "Stop", stopFailure = "StopFailure", sessionEnd = "SessionEnd" }`
  - `public struct AgentEvent: Equatable, Sendable { pane: PaneID; hook: AgentHook; at: Date; sessionID: String?; prompt: String?; toolSummary: String?; message: String? }`
  - `public struct AgentTransition: Equatable, Sendable { session: AgentSession?; attention: AttentionReason? }`, con `AttentionReason: .permission(String) | .attention(String) | .turnFinished | .failure(String)`.
  - `AgentSession.start(from: AgentEvent) -> AgentSession?` (nil sin `sessionID`, o si el hook no es `sessionStart`); `func applying(_ event: AgentEvent) -> AgentTransition`, según la tabla de la spec, incluido el duplicado `PermissionRequest`/`Notification` (si ya está en `.waiting(.permission)`, `Notification` no da `attention`).
  - `Pane.applying(_ event: AgentEvent) -> (Pane, AttentionReason?)`. El respaldo de `Pane.applying(TerminalEvent)` hace dos cosas: si el `foregroundProcessChanged` deja de ser `claude` y el agente no está `.stopped`, lo pasa a `.stopped`; si llega `commandFinished(exitCode ≠ 0)` mientras el proceso es `claude`, lo pasa a `.failed`.
  - `public enum AttentionQueue { static func panes(in set: WorkspaceSet) -> [PaneID] }`: paneles en `.waiting` o `.failed`, por `since` ascendente y, a igual `since`, por orden de workspace y de panel.
  - `public struct AgentCounts: Equatable { working: Int; waiting: Int; failed: Int; static func of(_ set: WorkspaceSet) -> AgentCounts }`; `Workspace.agentStatus: AgentStateKind?`, con la prioridad error > te espera > trabajando > detenido.
  - `public struct AttentionNotice: Equatable, Sendable { pane: PaneID; title: String; body: String; static func make(_ reason: AttentionReason, workspace: String, directory: WorkingDirectory, pane: PaneID) -> AttentionNotice }`, con los textos de la spec.
  - `public enum AttentionPolicy { static func shouldNotify(_ reason: AttentionReason, paneIsVisible: Bool) -> Bool }`: `.turnFinished` solo si no está a la vista; los demás siempre.
  - `public enum ElapsedText { static func short(since: Date, now: Date) -> String }`: "2m", "1h 12m", "0m" por debajo de un minuto.

- [ ] **Step 1: Pruebas que fallan:** una por fila de la tabla de transiciones; `notificationAfterStopDoesNotRenotifyOrMoveSince`; `permissionThenNotificationCountsOnce`; `titleIsFirstLineTruncatedTo80`; `titleIsKeptAfterFirstPrompt`; `eventWithoutSessionCreatesNoAgent`; `leavingClaudeStopsAgent`; `claudeNonZeroExitFailsAgent`; `queueOrdersBySinceThenPosition`; `queueSkipsWorkingAndStopped`; `countsAcrossWorkspaces`; `workspaceStatusPriority`; `noticeTextsMatchSpec`; `stopNotifiesOnlyWhenHidden`; `elapsedTextBoundaries` (59 s, 60 s, 3.599 s, 3.600 s).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): agent state transitions and attention queue`.

### Task 17: Casos de uso y puertos del agente

**Files:**
- Create: `Application/{TelemetrySource,Notifier,HarnessIntegration,HandleAgentEvent,JumpToWaitingAgent,ClaudeIntegration}.swift`
- Create: `SmaltiCoreTestSupport/{FakeTelemetrySource,RecordingNotifier,FakeHarnessIntegration,TelemetrySourceContract,NotifierContract,HarnessIntegrationContract}.swift`
- Test: `Tests/SmaltiCoreTests/Application/{HandleAgentEventTests,JumpToWaitingAgentTests,ClaudeIntegrationTests}.swift`

**Interfaces:**
- Produces:
  - `TelemetrySource { func events() -> AsyncStream<AgentEvent> }` (un consumidor).
  - `Notifier { func notify(_ notice: AttentionNotice) }`.
  - `HarnessIntegration { func install() async throws(IntegrationError) -> String; func uninstall() async throws(IntegrationError) -> String; var isInstalled: Bool { get async } }`, con `IntegrationError.commandFailed(command: String, output: String)` y `.harnessMissing(binary: String)`.
  - `HandleAgentEvent { init(notifier:); func execute(_ event: AgentEvent, in set: inout WorkspaceSet, isAppActive: Bool) -> HandleAgentEventOutcome }`, con `.applied | .ignoredMissingPane`. "A la vista" = `isAppActive && el workspace del panel es el activo`.
  - `JumpToWaitingAgent { func execute(in set: inout WorkspaceSet) -> JumpOutcome }`, con `.focused(PaneID) | .nobodyWaiting`; activa el workspace y enfoca.
  - `InstallClaudeIntegration` / `UninstallClaudeIntegration { init(integration:); func execute() async -> StatusText }`, que traducen éxito y error a los textos de la barra.

- [ ] **Step 1: Pruebas que fallan:** contratos con los fakes; `eventForMissingPaneIsIgnored` (Review Focus 5); `permissionNotifiesEvenWhenVisible`; `stopNotifiesOnlyWhenHidden` (la app inactiva y el workspace oculto, por separado); `sessionStartDoesNotNotify`; `jumpFocusesLongestWaitingAcrossWorkspaces`; `jumpWithNobodyWaitingDoesNothing`; `installReportsMissingClaude`; `installReportsCommandOutputOnFailure`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): handle agent events, jump to waiting agents and manage the integration`.

### Task 18: `IPCAdapter`: protocolo, servidor y CLI `smalti`

**Files:**
- Create: `Packages/IPCAdapter/Package.swift`, con tres productos: `SmaltiIPCProtocol` (librería, solo Foundation, sin `SmaltiCore`), `IPCAdapter` (librería; `UnixSocketTelemetry`, `HookPayloadTranslator`) y `smalti` (ejecutable).
- Create: `Sources/SmaltiIPCProtocol/{IPCRequest,IPCResponse,IPCLimits,IPCCodec}.swift`, `Sources/IPCAdapter/{UnixSocketTelemetry,SocketFile,HookPayloadTranslator}.swift`, `Sources/smalti/{main.swift,EventCommand.swift,SocketTransport.swift}`
- Test: `Tests/SmaltiIPCProtocolTests`, `Tests/IPCAdapterTests` (incluye `TelemetrySourceContract` y la guarda), `Tests/SmaltiCLITests`

**Interfaces:**
- Produces:
  - `public struct IPCRequest: Codable { v: Int; kind: String; pane: String; hook: String; payload: Data /* JSON del hook, sin tocar */ }`, `IPCResponse { ok: Bool; error: String? }`, `IPCLimits.version = 1`, `IPCLimits.maxMessageBytes = 1_048_576`. Una línea por petición.
  - `public final class UnixSocketTelemetry: TelemetrySource { init(socketFile: URL, clock: () -> Date) throws(IPCError); func stop() }`: socket 0600; si el archivo existe y conecta, `IPCError.socketInUse`; si no conecta, lo borra. Valida versión, `kind == "event"`, tamaño, `UUID` del panel y nombre del hook.
  - `enum HookPayloadTranslator { static func event(_ request: IPCRequest, at: Date) throws(IPCError) -> AgentEvent }`: `session_id`, `prompt`, `message`; `toolSummary` = `tool_input.command` si `tool_name == "Bash"`, si no `"<tool_name> <tool_input.file_path>"`. Ignora campos desconocidos.
  - CLI: `struct EventCommand { static func run(arguments: [String], environment: [String: String], input: Data, transport: any EventTransport) -> Int32 }`, que siempre devuelve 0 en `event` (`--version` también 0; uso inválido 64). `EventTransport.send(_ request: IPCRequest, to socket: URL, timeout: Duration) throws`.

- [ ] **Step 1: Pruebas que fallan:**
  - Protocolo: `requestRoundTrips`, `oversizedMessageIsRejected`.
  - Servidor:
    - `serverDeliversEventFromSocket`;
    - `serverRejectsUnknownVersion`, `serverRejectsUnknownPaneFormat` y `serverRejectsMessageOver1MB` (C13: las tres responden `ok: false` y el servidor sigue aceptando);
    - `staleSocketFileIsReplaced`;
    - `secondServerLeavesLiveSocketAlone` (Review Focus 3);
    - `socketFileIs0600`;
    - `bashPermissionSummarizesCommand`, `editPermissionSummarizesFile`, `unknownFieldsAreIgnored`.
  - CLI: `exitsZeroWithoutSocketVariable`, `exitsZeroWithoutPaneVariable`, `exitsZeroWhenAppIsGone` en < 1 s, medido (C12); `forwardsStdinAsPayload`; `versionPrints`.
- [ ] **Step 2–4:** Rojo → implementar (`socket(AF_UNIX)`, `DispatchSource` de lectura; en el CLI, conexión no bloqueante con `poll` de 500 ms) → verde.
- [ ] **Step 5:** Commit `feat(ipc): add the Unix socket telemetry server and the smalti CLI`.

### Task 19: Plugin de Claude Code e instalador

**Files:**
- Create: `App/Smalti/Resources/claude-plugin/.claude-plugin/marketplace.json`, `App/Smalti/Resources/claude-plugin/plugins/smalti/{.claude-plugin/plugin.json,hooks/hooks.json}`
- Create: `Packages/ClaudeHarnessAdapter/Sources/ClaudeHarnessAdapter/{ClaudePluginInstaller,CommandRunner}.swift`, pruebas con un `claude` falso
- Modify: `App/Smalti.xcodeproj`: fase "Embed smalti CLI" (`swift build -c release --package-path Packages/IPCAdapter --product smalti` y copia a `Contents/Resources/bin/smalti`, con entradas y salidas declaradas para el sandbox de scripts) y la carpeta `claude-plugin` como referencia de recursos

**Interfaces:**
- Produces:
  - `hooks.json`: los 8 hooks de `AgentHook`, cada uno con `{"type": "command", "command": "\"${SMALTI_CLI:-true}\" event <Hook>"}` y `timeout` de 5.
  - `public struct ClaudePluginInstaller: HarnessIntegration { init(pluginSource: URL, installDirectory: URL, runner: any CommandRunner) }`: copia el plugin a `installDirectory` (en la app, `~/Library/Application Support/Smalti/claude-plugin/`) y ejecuta `claude plugin marketplace add <dir>` y `claude plugin install smalti@smalti`. `uninstall`: `claude plugin uninstall smalti@smalti` y `claude plugin marketplace remove smalti`. `isInstalled`: `claude plugin list` contiene `smalti@smalti`.
  - `protocol CommandRunner { func run(_ arguments: [String]) async -> CommandResult }`, con `CommandResult { status: Int32; output: String }`. `LoginShellRunner` ejecuta `/bin/zsh -lc` con los argumentos escapados (sin `-i`, así no se engancha a tmux); el código 127 da `.harnessMissing("claude")`.

- [ ] **Step 1: Pruebas que fallan:**
  - `pluginValidates`: `claude plugin validate <recursos>/claude-plugin`. Si `claude` no está en la máquina, `.disabled("claude not installed")`.
  - `hooksCoverEveryAgentHook`: lee `hooks.json` y lo compara con `AgentHook.allCases`.
  - `hookIsNoOpOutsideSmalti`: ejecuta el comando del hook con `/bin/sh -c` sin `SMALTI_CLI` → código 0, sin salida.
  - `installRunsMarketplaceAddThenInstall` y `uninstallRunsUninstallThenRemove` (C14: un `claude` falso en un `PATH` temporal registra los argumentos).
  - `missingClaudeIsReported` y `HarnessIntegrationContract` con el instalador.
- [ ] **Step 2–4:** Rojo → implementar → verde; build de la app y `test -x "build/Build/Products/Debug/Smalti Dev.app/Contents/Resources/bin/smalti"`.
- [ ] **Step 5:** Commit `feat(claude): bundle the Claude Code plugin and its installer`.
- [ ] **Step 6: Cierre del bloque 5:** revisión del diff del bloque, correcciones, `progress.md`.

---

## Bloque 6 · Estado y atención en la app

### Task 20: Entorno de los paneles y cableado del IPC

**Files:**
- Modify: `Application/OpenPane.swift` (vía `PaneEnvironment`), `Domain/PaneFileLocator.swift` → `PaneEnvironment` con `socket: URL` y `cli: URL`, `AppComposition.swift`, `TilingController.swift`
- Test: `OpenPaneTests.swift`, `App/SmaltiUITests/ChildEnvironmentTests.swift`

**Interfaces:**
- Produces: `PaneEnvironment.variables(for:)` añade `SMALTI_SOCKET`, `SMALTI_CLI` y `PATH=<dir del CLI>:<PATH heredado>`. La app arranca `UnixSocketTelemetry` en `<estado>/smalti.sock` y consume `events()` en `@MainActor` → `HandleAgentEvent` → `publish()`. Comandos de ⌘K: "Instalar integración con Claude Code" y "Desinstalar integración con Claude Code".

- [ ] **Step 1: Pruebas que fallan:** `environmentCarriesSocketCliAndPath`; XCUITest `testPaneSeesSmaltiVariables` (`echo $SMALTI_PANE_ID $SMALTI_SOCKET`; `command -v smalti` resuelve al CLI del bundle).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(app): export pane identity to children and receive agent events`.

### Task 21: Estado en la cabecera, el borde y la franja

**Files:**
- Modify: `PaneHeaderView.swift`, `PaneGridView.swift`, `PaneContainerView.swift`, `WorkspaceStripView.swift`, `Theme+Obsidian.swift` (borde ámbar `rgba(224,175,104,0.35)`, círculo hueco `#6b717c`)
- Test: `ObsidianThemeTests.swift`

**Interfaces:**
- Consumes: `AgentState`, `AgentCounts`, `Workspace.agentStatus`, `ElapsedText`.
- Produces: identificadores de accesibilidad `pane.header.status.<uuid>` (valor: `working`, `waiting`, `failed`, `stopped`, `none`), `pane.header.detail.<uuid>` ("te espera · 2m"…), `strip.counter.working`, `strip.counter.waiting`, `strip.counter.failed`, `strip.workspace.<n>.status`. Un temporizador de 60 s refresca los minutos solo mientras haya paneles esperando o con error.

- [ ] **Step 1: Prueba que falla:** `waitingBorderAndStoppedRingMatchBoard`.
- [ ] **Step 2:** Implementar con las reglas de la spec (el foco gana sobre el ámbar; un contador en 0 se oculta).
- [ ] **Step 3:** Captura de la franja con contadores y de un panel en ámbar, superpuesta a `Main.dc.html` → `docs/specs/F2-assets/c18-status-overlay.png`.
- [ ] **Step 4:** Commit `feat(app): show agent state in headers, borders and the workspace strip`.

### Task 22: Notificaciones y salto al agente que espera

**Files:**
- Create: `Packages/UserNotificationsAdapter/{Package.swift, Sources/UserNotificationsAdapter/{UserNotificationsNotifier,FileLogNotifier}.swift, Tests/…/{NotifierContractTests,UNAdapterGuardTests}.swift}`
- Modify: `Domain/Config/{CommandID,Keymap}.swift` (`agentJump`, ⌘J), `CommandCatalog.swift`, `AppComposition.swift` (con `-SmaltiNotificationLog <archivo>` usa `FileLogNotifier`; si no, `UserNotificationsNotifier`)
- Test: `KeymapTests.swift`, `CommandCatalogTests.swift`

**Interfaces:**
- Produces:
  - `public final class UserNotificationsNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate { init(onActivate: @MainActor (PaneID) -> Void) }`: pide permiso con el primer aviso, pone `userInfo["pane"]` y, al hacer clic, activa la app y llama a `onActivate`. Un permiso denegado se registra una vez y se informa con el aviso de barra "Notificaciones desactivadas en macOS; el estado sigue en los paneles".
  - `public final class FileLogNotifier: Notifier { init(file: URL) }`: una línea JSON por aviso (`pane`, `title`, `body`).
  - El texto del aviso de barra no está en la spec: es la variante de "la barra de estado lo dice una vez". Se señala en el PR.
  - `TilingController.activate(pane:)` = cambiar al workspace y enfocar; si el panel no existe, solo activa la app.

- [ ] **Step 1: Verificación previa (riesgo de la spec):** con la app firmada ad hoc, `UNUserNotificationCenter.current().requestAuthorization` no falla por la firma. Anotar el resultado; si falla, se documenta y la UI queda solo en ámbar.
- [ ] **Step 2: Pruebas que fallan:** `NotifierContract` con `FileLogNotifier` y `RecordingNotifier`; `cmdJIsBoundToAgentJump`; `jumpCommandIsInPalette`; caso de uso `activatingMissingPaneOnlyActivatesApp` (C16).
- [ ] **Step 3–4:** Implementar → verde.
- [ ] **Step 5:** Commit `feat(app): macOS notifications and jump to the waiting agent`.

### Task 23: Arrastrar imágenes al panel

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/DroppedFiles.swift`
- Modify: `GhosttySurfaceView.swift` (`registerForDraggedTypes([.fileURL])`, `performDragOperation` → `ghostty_surface_text` con las rutas escapadas)
- Test: `Tests/GhosttyAdapterTests/DroppedFilesTests.swift`

**Interfaces:**
- Produces: `enum DroppedFiles { static func pasteText(for urls: [URL]) -> String }`: cada ruta escapada para el shell (con `\` delante de los espacios y de `()'"&;|<>*?$` y las comillas invertidas), unidas con un espacio. `ghostty_surface_text` envía como *bracketed paste* cuando el programa lo activa (Claude Code lo hace). No se toca el portapapeles.

- [ ] **Step 1: Pruebas que fallan:** `escapesSpacesAndShellCharacters` (`/tmp/mi captura (1).png` → `/tmp/mi\ captura\ \(1\).png`), `joinsSeveralFilesWithSpaces`, y con superficie real `dropPastesBracketedWhenProgramAsksForIt` (un script activa `\e[?2004h` y vuelca la entrada con `od -c`; se ven `\e[200~` y `\e[201~` alrededor de la ruta).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(ghostty): paste dropped image paths into the pane`.

### Task 24: UI tests del estado y la atención

**Files:**
- Create: `App/SmaltiUITests/{AgentStatusTests,DragImageTests}.swift`, `App/SmaltiUITests/Fixtures/claude-hooks-2.1.330.jsonl`

**Interfaces:**
- Consumes: el CLI del bundle, `-SmaltiNotificationLog`.
- Produces: el log grabado: por línea, `{"hook": "...", "payload": {...}, "delayMs": n}`, con la secuencia inicio → prompt → herramienta → permiso + notificación → herramienta → stop → notificación de inactividad → prompt → fallo → fin. Los payloads tienen la forma real de los hooks de Claude Code 2.1.330 (capturados con un hook temporal que vuelca stdin, en una sesión real de Simón: se hace una vez al escribir la tarea, y el fixture no lleva datos privados).

- [ ] **Step 1: Pruebas que fallan:**
  - `testRecordedHookLogDrivesTheUI` (C11): en un panel, reproduce el log ejecutando `"$SMALTI_CLI" event <hook> < payload` desde el propio shell del panel. Tras cada paso compara `pane.header.status`, el detalle, el punto del workspace y los contadores. Al final compara el archivo de `FileLogNotifier` con la lista esperada: permiso (1), stop solo si la app no está activa (el test la desactiva antes de ese paso) y fallo (1).
  - `testJumpGoesToLongestWaitingPaneInAnotherWorkspace` (C15).
  - `DragImageTests.testDroppedImagePathReachesThePane` (C17; arrastre sintetizado con `XCUICoordinate.press(forDuration:thenDragTo:)` desde una ventana auxiliar o, si XCUITest no puede, la prueba del adaptador de T23 queda como evidencia y se anota).
- [ ] **Step 2–4:** Rojo → implementar → verde (`kb-progress run e2e -- scripts/test-ui.sh AgentStatusTests` y `DragImageTests`).
- [ ] **Step 5:** Commit `test(app): replay recorded Claude hooks against the UI`.
- [ ] **Step 6: Cierre del bloque 6:** revisión del diff del bloque, correcciones, `progress.md`.

---

## Bloque 7 · Cierre de fase

### Task 25: Mediciones, checklist y PR

**Files:**
- Create: `scripts/measure-restore.sh`, `docs/specs/F2-checklist.md`, `docs/specs/F2-assets/*`
- Modify: `progress.md`, `docs/ROADMAP.md` (F2 cerrada), tarjeta del KB de smalti (vía `kb-capture`: builds `.dev`; ya se puede desarrollar Smalti desde Smalti)

- [ ] **Step 1: C6:** `measure-restore.sh` construye Release, siembra una instantánea de 3 workspaces y 6 paneles con 10.000 líneas cada uno y lanza 5 veces con `-SmaltiShellCommand /bin/zsh`, un `ZDOTDIR` vacío y `-SmaltiStatePath` temporal. Lee los signposts `restore.start`/`restore.done` con `xctrace` (como en F1) y escribe la tabla. Criterio: las 5 por debajo de 5 s.
- [ ] **Step 2:** La sonda de latencia con 6 paneles durante un guardado con scrollback: si hay bloqueos > 16 ms, se anotan (riesgo de la spec).
- [ ] **Step 3:** `F2-checklist.md` con C1–C20, evidencia, desviaciones del diseño y lo aplazado a la app terminada (clic real en notificación, adjunto real en Claude, uso diario).
- [ ] **Step 4:** Revisión final de la rama completa (revisor nuevo, modelo más capaz) y una sola tanda de correcciones.
- [ ] **Step 5:** Mutación de `SmaltiCore` ≥ 80 % (`kb-progress run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore`); los sobrevivientes se matan con pruebas nuevas.
- [ ] **Step 6:** Todas las suites en verde (códigos de salida y totales anotados).
- [ ] **Step 7:** PR `feature/f2-persistence` → `develop` y, con confirmación de Simón, `develop` → `main`. Nada se fusiona sin su confirmación.

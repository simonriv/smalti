# F8 · Puertos y procesos — Plan de implementación

> **Para agentes:** ejecución nativa (`.claude/rules/workflow.md`): Claude implementa cada tarea en esta sesión, en bloques, con dos revisiones intermedias y una final acotada. Pasos con casillas (`- [ ]`).

**Objetivo:** panel de puertos y vista de procesos nativos (⌘⇧U, ⌘⇧M), con detener (SIGTERM → confirmación → SIGKILL) y bajar la prioridad, sin coste en reposo, publicados como 0.8.0.

**Arquitectura:** el dominio (`SmaltiCore`) arma las dos tablas desde muestras puras (registros de proceso y sockets) y decide qué se puede detener; tres puertos pequeños (`RunningProcesses`, `ListeningPorts`, `ProcessControl`) los implementa un adaptador nuevo, `DarwinProcessesAdapter`, con libproc y `sysctl`; la app pinta una superposición como la del Observatorio y muestrea solo mientras está abierta.

**Stack:** Swift 6, AppKit, Swift Testing, XCUITest, libproc/`sysctl`, Next.js (smalti-web).

**Spec:** `docs/specs/F8-puertos-procesos.md`

## Restricciones globales

- `SmaltiCore` sin imports nuevos; los PID son `Int32`, el tiempo de CPU `UInt64` en nanosegundos, los instantes `Date` (hora de inicio) y `UInt64` monotónico en nanosegundos (muestra).
- Identidad = PID + hora de inicio (`ProcessIdentity`); toda acción la lleva y el adaptador la relee antes de actuar.
- El dominio nunca llama a `forceStop` sin un pedido en «confirmando».
- Textos: `ProcessTexts.spanish` / `.english` en el dominio; vistas en `Localizable.xcstrings`.
- UI tests: `isolatedSmalti(language:)`, `-SmaltiShellCommand "/bin/zsh -f"`, `check-daily-untouched.sh` con `SMALTI_DAILY_PID`, una corrida a la vez; solo señalan procesos lanzados por la prueba, en loopback y puertos efímeros.
- `swift test --disable-keychain`; `xcodebuild … -packageAuthorizationProvider netrc`.

## Foco de revisión

1. PID reutilizado entre elegir y detener: `DarwinProcessControl` con una identidad de hora cambiada no señala (T7); `CPUUsage` con el mismo PID y otra hora empieza de cero (T1).
2. Panel con comando propio (`login` de root encabezando el grupo): el panel se atribuye por el terminal y la raíz del subárbol se protege (T2).
3. Filtro en modo árbol: los antepasados de lo que coincide se ven atenuados y lo que no coincide desaparece; un huérfano cuyo padre no es propio queda como raíz (T3).
4. ⌘⌫ dentro de la gracia, sobre lo protegido, sobre un proceso que ya terminó, y ↵ en la confirmación cuando el proceso terminó entre tanto (T4, T9).
5. Con la vista cerrada no hay `Task` de refresco vivo ni muestreo (T8).

---

## Bloque 1 · Dominio

### Task 1: Tipos, CPU y puertos de salida

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Processes/{ProcessIdentity,ProcessRecord,ProcessSample,ListeningSocket,CPUUsage}.swift`, `Application/ProcessPorts.swift`
- Create: `Sources/SmaltiCoreTestSupport/ProcessFakes.swift`
- Test: `Tests/SmaltiCoreTests/Processes/{CPUUsageTests,ListeningSocketTests}.swift`

**Interfaces:**
- `ProcessIdentity { pid: Int32; startedAt: Date }` (Hashable).
- `ProcessRecord { identity; parent: Int32; isOwn: Bool; name: String; executable: String?; arguments: [String]; workingDirectory: String?; terminal: Int32? (nil = sin terminal); run: RunState (.running, .sleeping, .stopped, .zombie); cpuTime: UInt64 (ns); memory: UInt64 (bytes); threads: Int; nice: Int32 }`.
- `ProcessSample { records: [ProcessRecord]; takenAt: UInt64 (ns monotónico); hiddenCount: Int; memoryTotal: UInt64 }`.
- `ListeningSocket { pid: Int32; transport: Transport (.tcp, .udp); port: UInt16; address: String }`; `scope` → `.local`, `.all`, `.specific(String)` (loopback: `127.*`, `::1`, `::ffff:127.*`; comodín: `0.0.0.0`, `::`, `*`).
- `CPUUsage.percentages(previous: ProcessSample?, current: ProcessSample) -> [ProcessIdentity: Double]`: por identidad, `Δcpu / Δwall × 100`; sin previa, sin Δwall o sin la identidad en la previa → ausente.
- Puertos: `RunningProcesses: Sendable { func current() async -> ProcessSample }`, `ListeningPorts: Sendable { func current() async -> [ListeningSocket] }`, `ProcessControl: Sendable { func stop(_: ProcessIdentity) async throws(ProcessControlError); func forceStop(_:) …; func lowerPriority(_:to: Int32) … }`; `ProcessControlError: .gone, .notYours, .refused(code: Int32)`.
- Fakes: `FakeRunningProcesses` (cola de muestras), `FakeListeningPorts`, `FakeProcessControl` (registra llamadas, errores programables).
- [ ] Pruebas rojas: CPU con dos muestras (1 s, 0,5 s de CPU → 50 %), sin previa, PID reutilizado (otra hora) ausente, Δwall 0 ausente, más de un núcleo (> 100 %); `scope` de cada clase de dirección y de un grupo mixto.
- [ ] Implementar; SmaltiCore en verde. Commit `feat(core): process samples, listening sockets and CPU usage`.

### Task 2: Atribución a paneles, política de detener y prioridad

**Files:**
- Create: `Domain/Processes/{PaneAttribution,StopPolicy,NicePriority}.swift`
- Test: `Tests/SmaltiCoreTests/Processes/{PaneAttributionTests,StopPolicyTests,NicePriorityTests}.swift`

**Interfaces:**
- `PaneAttribution(records:, foregroundGroups: [PaneID: Int32])`: terminal de cada panel = terminal del registro de su grupo en primer plano (también si `isOwn == false`); `pane(of: Int32) -> PaneID?` (mismo terminal o antepasado con terminal de panel, con corte de ciclos); `isPaneRoot(_ pid) -> Bool` (en el panel y su padre no lo está).
- `StopPolicy(ownPID: Int32)`: `verdict(for: ProcessRecord, attribution:) -> StopVerdict` (`.allowed` o `.protected(ProtectionReason)`: `.otherUser`, `.system`, `.smalti`, `.paneShell`, `.zombie`); sistema = PID 0/1 o ejecutable bajo los prefijos de la spec; Smalti = PID propio o ejecutable que termina en `.app/Contents/MacOS/Smalti` o `.app/Contents/MacOS/Smalti Dev`.
- `NicePriority.next(after: Int32) -> Int32?` (0→5→10→15→20; 20 → nil; negativos → 0… siempre hacia arriba en *nice*), `level(of:)` → `.normal`, `.low`, `.lowest` para el texto.
- [ ] Pruebas rojas: árbol `smalti → login(root, tty 3) → zsh → npm → node`, `setsid` sin terminal colgando de `node` (atribuido), huérfano re-parentado a `launchd` (sin panel), panel con comando propio `login → claude` (claude es raíz), ciclo de PPID; cada motivo de la política y su orden (otro usuario antes que sistema); los pasos de *nice*.
- [ ] Implementar. Commit `feat(core): pane attribution, stop policy and nice steps`.

### Task 3: Tablas de procesos y de puertos

**Files:**
- Create: `Domain/Processes/{ProcessTable,PortTable,ProcessOrder}.swift`
- Test: `Tests/SmaltiCoreTests/Processes/{ProcessTableTests,PortTableTests}.swift`

**Interfaces:**
- `ProcessOrder: .cpu, .memory, .name, .pid` (`next`); `PortOrder: .port, .process, .pane` (`next`).
- `ProcessRow { identity; name; command (argumentos unidos, o el nombre); pane: PaneID?; cpu: Double?; memory: UInt64; state: ProcessState; depth: Int; guides: [TreeGuide]; isContext: Bool (antepasado atenuado); verdict: StopVerdict; record }`.
- `ProcessTable.rows(sample:, cpu:, attribution:, policy:, query: ProcessQuery { filter: String; order; isTree: Bool }, pending: [ProcessIdentity: StopPhase]) -> [ProcessRow]`. Filtro sin distinguir mayúsculas ni tildes, por palabras (todas deben coincidir) sobre nombre, comando, PID, directorio y el nombre del panel (lo pasa la app en `paneNames: [PaneID: String]`).
- `PortRow { pid; transport; port; scope; addresses: [String]; process: ProcessRow? }`; `PortTable.rows(sockets:, processes: [Int32: ProcessRow], query: PortQuery) -> [PortRow]` agrupando por (PID, transporte, puerto); `summary` → total y abiertos a la red.
- [ ] Pruebas rojas: orden por CPU con `nil` al final, empates por PID; árbol con hermanos ordenados y guías `├─ └─ │`; filtro plano y en árbol (contexto atenuado); filtro por panel y por PID; puertos IPv4+IPv6 agrupados (`.local`), uno comodín (`.all`), dirección concreta; orden por puerto; filtro por número de puerto; 0 y 1 filas.
- [ ] Implementar. Commit `feat(core): process and port tables with filter, order and tree`.

### Task 4: Detener, bajar prioridad y observar

**Files:**
- Create: `Domain/Processes/StopRequests.swift`, `Application/{StopProcess,LowerPriority,ObserveProcesses}.swift`
- Test: `Tests/SmaltiCoreTests/Processes/{StopRequestsTests,StopProcessTests,LowerPriorityTests,ObserveProcessesTests}.swift`

**Interfaces:**
- `StopPhase: .requested(at: UInt64), .unresponsive, .confirming`; `StopRequests` (valor): `request(_, at:)`, `tick(alive: Set<ProcessIdentity>, now:, grace:)` (las que siguen vivas tras la gracia → `.unresponsive`; las que no están → fuera), `confirm(_)` (solo desde `.unresponsive`), `cancel(_)`, `phase(of:)`.
- `StopProcess(control:, policy:)`: `press(_ row: ProcessRow, requests: inout StopRequests, now:) async -> StopOutcome` (`.requested`, `.confirming`, `.waiting`, `.protected(reason)`, `.failed(ProcessControlError)`); `confirm(_ identity, requests: inout) async -> StopOutcome` (`.forced` o error; sin `.confirming` → `.waiting` sin llamar).
- `LowerPriority(control:)`: `lower(_ row) async -> PriorityOutcome` (`.lowered(to:)`, `.alreadyLowest`, `.protected(reason)`, `.failed`).
- `ObserveProcesses(processes:, ports:)`: `refresh(foregroundGroups:) async -> ProcessesSnapshot` (muestra, CPU contra la anterior, sockets, atribución) — la app arma las tablas con la consulta y los nombres de paneles.
- [ ] Pruebas rojas: protegido no llama al puerto; primer ⌘⌫ → `stop`; segundo dentro de la gracia → `.waiting` sin llamar; tras la gracia sigue vivo → `.unresponsive`; ⌘⌫ → `.confirming` sin llamar; `confirm` → `forceStop` una vez; `confirm` sin pedido o dentro de la gracia → nada; proceso que terminó → el pedido se borra; `.gone` del puerto → `.failed(.gone)`; prioridad de 0 a 5, en 20 → `.alreadyLowest` sin llamar, protegido sin llamar; observar dos veces → CPU solo en la segunda.
- [ ] Implementar. Commit `feat(core): stop, lower priority and observe processes`.

### Task 5: Textos, comandos, atajos y motor

**Files:**
- Create: `Domain/Texts/ProcessTexts.swift`, `Domain/Processes/ProcessFormat.swift` (memoria «412 MB»/«1.2 GB», CPU «14.2%», «hace 42 min» con `TimeTexts`)
- Modify: `CommandID.swift` (`processesToggle`, `portsToggle`, `processesStop`, `processesLowerPriority`, `processesTree`, `processesSort`), `Keymap.swift`, `KeyChord.swift` (`backspace` → ⌫), `CommandTexts`, `HelpTexts`, `MenuTexts`, `HelpCatalog`, `MenuModel`, `CommandCatalog` (grupo), `TerminalEngine.swift` (`foregroundGroup(of:)`), `FakeTerminalEngine`, `TextCatalogTests`
- Test: `ProcessTextsTests`, `ProcessFormatTests`, pruebas de keymap, catálogo, ayuda y menú existentes ampliadas.
- [ ] Pruebas rojas: atajos de la spec, ⌫ se muestra «⌘⌫», los seis en ⌘K, ayuda y menú; los cuatro contextuales pasan al terminal con la vista cerrada (`KeyContext` en la app, ver T8: aquí solo `CommandID.processesContextual`); textos sin problemas en la auditoría; formatos.
- [ ] Implementar; la app compila (stubs de `foregroundGroup` en `GhosttyTerminalEngine` devolviendo el PID crudo). Commit `feat(core): process texts, commands and shortcuts`.

## Bloque 2 · Adaptadores

### Task 6: `DarwinProcessesAdapter` — lectura

**Files:**
- Create: `Packages/DarwinProcessesAdapter/{Package.swift,Sources/DarwinProcessesAdapter/{DarwinRunningProcesses,DarwinListeningPorts,KernelProcessTable,ProcessArgumentsReader}.swift,Tests/DarwinProcessesAdapterTests/{RunningProcessesTests,ListeningPortsTests,LsofParityTests,SampleCostTests,Listener.swift}}`
- [ ] Pruebas rojas: un hijo `sleep` aparece con PPID, argumentos, directorio y hora de inicio; los procesos de otro usuario no están y cuentan en `hiddenCount`; CPU de un hijo que gira sube entre dos muestras; C1 (oyentes TCP en `127.0.0.1` y `::1` y UDP en `127.0.0.1`, puertos efímeros, contra lsof); C10 (p95 de 20 muestras < 50 ms).
- [ ] Implementar. Commit `feat(processes): read processes and listening sockets with libproc`.

### Task 7: `DarwinProcessControl` y el motor

**Files:**
- Create: `Sources/DarwinProcessesAdapter/DarwinProcessControl.swift`, `Tests/…/ProcessControlTests.swift`
- Modify: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{GhosttyTerminalEngine,GhosttySurfaceView}.swift` (`foregroundGroup`) y su prueba
- [ ] Pruebas rojas: `stop` termina un hijo; `forceStop` termina un hijo que ignora SIGTERM; `lowerPriority(to: 5)` deja *nice* 5; con `launchd` → `.notYours` sin señal; con el propio PID → `.notYours`; con hora cambiada → `.gone`; con un PID que ya no existe → `.gone`.
- [ ] Implementar. Commit `feat(processes): stop, force and lower priority with identity checks`.

### Revisión intermedia 1 + mutación incremental

- [ ] Revisor nuevo sobre el diff del bloque 1 y 2; corregir todo (RED→GREEN); `mutate.py --changed-since origin/develop`; matar sobrevivientes.

## Bloque 3 · App

### Task 8: Superposición, refresco y teclado

**Files:**
- Create: `App/Smalti/Processes/{ProcessesController,ProcessesView,ProcessesTableView,ProcessesDetailView,ProcessesRefresher,ProcessesTokens}.swift`
- Modify: `AppComposition.swift`, `WindowComposition.swift` (comandos y `keyContext`), `KeyRouter.swift` (⌫), `Theme` tokens si hacen falta, `project.pbxproj` (paquete nuevo)
- [ ] Prueba roja: `ProcessesTests` (C6, parte de abrir/filtrar/árbol/orden/↵); `PortsTests` (C7).
- [ ] Implementar; las pruebas en verde. Commit `feat(app): processes and ports overlay`.

### Task 9: Detener, confirmar, prioridad, avisos e idioma

**Files:**
- Modify: los de T8, `Localizable.xcstrings`, `LocalizationTests.swift`, `IsolatedApp.swift` (`-SmaltiStopGraceSeconds`)
- [ ] Pruebas rojas: C3 en `PortsTests`; resto de C6; C5 en `LocalizationTests`.
- [ ] Implementar; `strings-catalog.test.sh` y `network-surface.test.sh` en verde. Commit `feat(app): stop, force and lower priority from the overlay`.

### Task 10: Documentos y web

- [ ] `CLAUDE.md`, `docs/design/README.md`, `docs/ROADMAP.md`, `docs/PROJECT.md` si aplica; smalti-web (docs de puertos y procesos en/es con capturas, comandos, «Lo que viene», changelog) con `pnpm lint` y `pnpm build`.

### Revisión intermedia 2 + regresión de UI + mutación incremental

## Bloque 4 · Cierre

### Task 11: Mediciones, capturas, checklist, revisión final y mutación de la fase

### Task 12: 0.8.0, PRs, release y despliegue

# F4 · Input inteligente — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (modo nativo, `.claude/rules/workflow.md`). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sugerencias sobre el prompt de zsh en los paneles de Smalti: texto fantasma con predicción heurística, menú de Tab con specs de Fig y ⌃R difuso en paleta, con un historial propio por directorio. Ningún programa que no sea el prompt ve nada distinto.

**Architecture:**
- **Dominio puro** en `SmaltiCore/Domain/Input`: línea y tokens, protocolo del canal, historial e índice, filtro de secretos, reglas de predicción, modelo de spec, motor de completions y máquina de estados del menú.
- **Casos de uso:** `SuggestForLine`, `CompleteLine`, `SearchHistory` y `RecordCommand`, que corren en un actor de input sobre cuatro puertos: `CommandHistory`, `ProjectContext`, `CompletionProvider` y `PredictionProvider`.
- **Adaptadores secundarios:**
  - historial JSONL en `FileSessionAdapter`;
  - `ProjectContextAdapter` nuevo;
  - `FigCompletionAdapter` nuevo, con JavaScriptCore;
  - detección del prompt en `GhosttyAdapter`.
- **Adaptador primario:** el canal con zsh, que tiene dos lados:
  - el servidor `InputSocketServer` en `IPCAdapter`;
  - el script de zsh en `SmaltiZshEnv`, que pinta el fantasma con `POSTDISPLAY`.
- **Capas AppKit** (en la app): el menú de completions y la paleta ⌃R.

**Tech Stack:**
- Swift 6.4 (Xcode 27.2), AppKit, Swift Testing, XCUITest;
- JavaScriptCore;
- zsh 5.9 (`zsh/net/socket`, `zsh/zselect`, `zle -F -w`, `add-zle-hook-widget`);
- `@withfig/autocomplete@2.692.3` (npm, solo para el vendoring) y Python 3;
- libghostty v1.4.0;
- `scripts/mutation/mutate.py`.

**Spec:** `docs/specs/F4-input.md` (aprobada 2026-11-23) · Convenciones: `CLAUDE.md`, `.claude/rules/` · Diseño: `docs/design/README.md`, `Main.dc.html` (menú, fantasma, línea de ayuda), `Paleta.dc.html` (⌃R), maquetas `docs/specs/F4-assets/mockup-{input,history}.png`

## Global Constraints

- **`SmaltiCore`:** solo `Foundation`, para tipos de valor. La guarda de imports no se toca.
- **Fronteras de los adaptadores nuevos**, cada uno con su prueba de guarda copiada de `TOMLAdapterGuardTests`:
  - `FigCompletionAdapter` es el único que importa `JavaScriptCore`;
  - `ProjectContextAdapter` usa solo `Foundation` (archivos), sin `Process`;
  - nadie fuera de `scripts/measure-input.sh` nombra `.zsh_history` (prueba de guarda que busca el texto).
- **Valores fijados por la spec:**
  - historial: límite 100.000 entradas; vida media de recencia de 7 días;
  - generadores: timeout 1 s y caché 30 s por (script, directorio);
  - Tab sin respuesta en 300 ms: nada;
  - menú: 6 filas para anclar debajo y 8 visibles;
  - paleta ⌃R: 86 % del ancho del panel, mín. 480, máx. 720;
  - animación: 120 ms, ninguna con "Reducir movimiento";
  - socket: ruta < 104 bytes, permisos 0600;
  - C1 y C13: p99 < 16 ms.
- **TOML `[input]`:** `enabled = true`, `predictions = true`, `completions = true`, `history_limit = 100000`, `generator_timeout_ms = 1000`.
- **Textos de interfaz** (tal cual): "Tab completar · → aceptar sugerencia · ⌃R historial", "Este directorio", "Todos", "↩ insertar", "⌘↩ ejecutar", "⇥ cambiar ámbito", "esc cerrar", "hace N min" / "hace N h" / "ayer" / "hace N días", "×N", "Sin coincidencias", "Historial vacío: se llena con lo que ejecutes en Smalti", y en ⌘K "Buscar en el historial".
- **Tokens:** solo desde `Theme.obsidian`. Nuevos: `ghostText #5f6672`; menú (`Main.dc.html`: 360 de ancho, radio 10, borde `rgba(255,255,255,0.1)`, fondo `rgba(18,20,27,0.94)`, sombra `0 18px 40px rgba(0,0,0,0.45)`, padding 5, filas de 12 px, columna de nombre de 92); paleta ⌃R = tokens de la paleta ⌘K existentes.
- **Canal (spec, "Canal zsh ↔ Smalti"):**
  - mensajes por línea, campos separados por tab y escapes `\t` `\n` `\\`;
  - zsh descarta toda respuesta cuyo `seq` no sea el último que envió;
  - el directorio sale del panel (OSC 7), nunca del protocolo.
- **Shell nunca colgado ni muerto:**
  - una sola función de envío en zsh con `zselect -t 0 -w`, `setopt localoptions localtraps; trap '' PIPE` y desactivación si falla;
  - el servidor lee en un hilo propio.
- **Swift:**
  - Swift 6 estricto;
  - `throws(Tipo)` con operación, dato y causa;
  - sin `!`/`try!`/`as!`/`unsafe*` sin comentario;
  - ≤ 3 parámetros;
  - `struct`/`enum` por defecto;
  - cada regla de predicción, un tipo (OCP).
- **Pruebas:**
  - Swift Testing, AAA, un concepto por prueba, TDD;
  - contrato compartido para `CommandHistory` (en memoria y JSONL) y `ProjectContext` (fake y adaptador sobre un directorio temporal).
- **Pruebas de zsh real:**
  - `zsh -d -i` con un `ZDOTDIR` temporal pasado por `SMALTI_USER_ZDOTDIR`, nunca `~/.zshrc`;
  - plugins solo desde las fixtures versionadas.
- **UI tests:**
  - `isolatedSmalti(shell: "/bin/zsh -d")` con `-SmaltiUserZdotdir <tmp>` (helper nuevo `isolatedSmaltiWithIntegration()`);
  - el resto de pruebas de UI sigue con `/bin/zsh -f`;
  - `PasteboardGuard` en cada clase;
  - la suite corre con `scripts/check-daily-untouched.sh`.
- **App GUI lanzada desde la sesión:** `env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh TMPDIR="$TMPDIR" LANG=es_CO.UTF-8 PATH=/usr/bin:/bin:/usr/sbin:/sbin open -a …`.
- **`~/.zsh_history`:** solo lo lee `scripts/measure-input.sh`, en solo lectura y en memoria.
- **Verificación:**
  - comandos de `CLAUDE.md`, más `swift test --package-path Packages/{FigCompletionAdapter,ProjectContextAdapter,FileSessionAdapter,IPCAdapter}` y el lint ampliado a los paquetes nuevos;
  - suites de más de 30 s con `"$KB_ROOT/_system/bin/kb-progress" run <etiqueta> -- …`;
  - siempre el código de salida real.
- **Ramas y fusiones:**
  - todo en `feature/f4-input`, que ya tiene la spec;
  - Conventional Commits en inglés con la atribución de la sesión;
  - cada tarea se marca en `progress.md`;
  - nada se fusiona sin Simón.
- **Revisión por bloque:**
  - al cerrar cada bloque, un revisor nuevo revisa el diff del bloque;
  - los hallazgos importantes se corrigen antes del bloque siguiente;
  - los menores, en una tanda al final del bloque, cada uno con su prueba RED→GREEN.

## Desviaciones de la spec (para revisar con el plan)

1. **`FuzzySearch` reutiliza el puntuador de `FuzzyMatch`** (⌘K). Se extrae `fuzzyScore(_ query: String, in text: String) -> Int?` con los mismos bonus (contigüidad +10, inicio de palabra +8, salto −1). La spec describe el mismo algoritmo; así no hay dos (DRY).
2. **Un actor `InputSession` por app**, no por panel. Guarda el índice del historial y las cachés y atiende a todos los paneles; cada mensaje lleva su `PaneID`. Un actor por panel duplicaría 50.000 entradas en memoria.

## Review Focus

1. **Texto no ASCII en la línea** (`echo canción 🎵`): `CURSOR` de zsh cuenta caracteres, no bytes. Si se confunde, el fantasma y las ediciones caen en otra posición. Lo cubre T1 (`cursorCountsCharactersNotBytes`) y T11 (integración con `á` y emoji).
2. **Pegado enorme** (bracketed paste de 20.000 caracteres) o línea de varias líneas: con mensajes `line` gigantes, zsh no debe bloquearse ni Smalti sugerir sobre una línea partida. Un `line` de más de 4096 bytes no se envía y se borra el fantasma. Lo cubren T1 (`lineOverLimitIsNotEncoded`) y T11 (`hugePasteKeepsShellResponsive`).
3. **`cd` justo antes de pedir sugerencia**: la respuesta de un directorio viejo no debe pintarse. La cubren el `seq` y el directorio leído en el momento del mensaje, en T13 (`suggestionUsesDirectoryAtMessageTime`).
4. **Varios paneles a la vez y un panel que se cierra con una petición en vuelo**: ninguna respuesta va al panel equivocado y no quedan conexiones huérfanas. Lo cubre T10 (`responsesGoToTheirOwnConnection`, `closedConnectionIsForgotten`).
5. **Menú junto al borde inferior o derecho del panel, y tras redimensionar o cambiar la fuente**: el menú sube o se desplaza sin salirse. Lo cubre T14 (`menuFlipsAboveNearBottom`, `menuShiftsLeftNearRightEdge`, `menuFollowsCellAfterResize`).

## Mapa de archivos

| Ruta | Responsabilidad |
| --- | --- |
| `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Input/CommandLine.swift` | Texto, cursor y tokens del último comando simple |
| `…/Domain/Input/InputProtocol.swift` | Mensajes del canal, codificar y decodificar |
| `…/Domain/Input/HistoryEntry.swift`, `HistoryIndex.swift` | Entradas, índice por comando, directorio y secuencia |
| `…/Domain/Input/SecretFilter.swift` | Detectar y redactar secretos |
| `…/Domain/Input/HistorySearch.swift` | ⌃R: ámbito, orden y formato de recencia |
| `…/Domain/Input/Prediction/*.swift` | `PredictionRule`, las 4 reglas, `HeuristicPredictor` |
| `…/Domain/Input/Completion/*.swift` | `CompletionSpec`, `CompletionEngine`, `CompletionMenu` |
| `…/Domain/Config/InputSettings.swift` | Ajustes `[input]` |
| `…/Domain/Commands/FuzzyMatch.swift` | Se extrae `fuzzyScore` |
| `…/Application/InputPorts.swift` | `CommandHistory`, `ProjectContext`, `CompletionProvider`, `PredictionProvider` |
| `…/Application/InputSession.swift` | Actor con los 4 casos de uso |
| `Packages/SmaltiCore/Tests/SmaltiCoreTests/Input/…` | Pruebas de dominio, fakes y contratos |
| `Packages/FileSessionAdapter/Sources/FileSessionAdapter/FileCommandHistory.swift` | JSONL |
| `Packages/ProjectContextAdapter/` (nuevo) | `package.json`, `Makefile`, `.git/` |
| `Packages/FigCompletionAdapter/` (nuevo) | JavaScriptCore, specs vendorizadas, generadores |
| `scripts/fig/{package.json,vendor-specs.py,test_vendor_specs.py,commands.txt}` | Vendoring |
| `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{PromptState.swift,GhosttyConfigText.swift,GhosttyTerminalEngine.swift,SmaltiZshEnv.swift,SmaltiInputScript.swift}` | Prompt, config, cadena de zsh, script de F4 |
| `Packages/GhosttyAdapter/Tests/GhosttyAdapterTests/{PromptStateTests,ZshChannelTests,ZshTakeoverTests}.swift` + `Fixtures/zsh-plugins/` | zsh real |
| `Packages/IPCAdapter/Sources/IPCAdapter/InputSocketServer.swift` | Servidor del canal |
| `App/Smalti/Input/{InputCoordinator,CompletionMenuController,CompletionMenuView,HistoryPaletteController,HistoryRowView}.swift` | Cableado y capas |
| `App/SmaltiUITests/{InputTests,InputIsolationTests}.swift`, `Fixtures/byte-recorder.sh` | E2E |
| `scripts/measure-input.sh`, `scripts/input-bench/` | C1 |

---

## Bloque 1 · Dominio

### Task 1: Línea de comando y protocolo del canal

**Files:**
- Create: `Domain/Input/CommandLine.swift`, `Domain/Input/InputProtocol.swift`
- Test: `Tests/SmaltiCoreTests/Input/CommandLineTests.swift`, `InputProtocolTests.swift`

**Interfaces:**
- Produces:
  - `public struct CommandLine: Equatable, Sendable { text: String; cursor: Int }`, con el cursor en `Character`s.
    - `var currentCommand: [Token]`: tokens del último comando simple antes del cursor; los separadores son `;`, `&&`, `||` y `|`.
    - `var currentWord: Token?`: la palabra que contiene el cursor o termina en él.
    - `var isCursorAtEnd: Bool`.
  - `public struct Token: Equatable, Sendable { text: String /* sin comillas */; range: Range<Int> /* en Characters de la línea */; isQuoted: Bool }`.
  - `public enum ShellMessage: Equatable, Sendable { case hello(PaneID), line(seq: Int, CommandLine), exec(seq: Int, command: String), done(seq: Int, exit: Int), complete(seq: Int, CommandLine), history(seq: Int, query: String), bye }`.
  - `public enum SmaltiMessage: Equatable, Sendable { case specs([String]), suggest(seq: Int, String), edit(seq: Int, CommandLine), run(seq: Int), fallback(seq: Int) }`.
  - `public enum InputProtocol`:
    - `static let maxLineBytes = 4096`;
    - `static func decode(_ line: String) throws(InputProtocolError) -> ShellMessage`;
    - `static func encode(_ message: SmaltiMessage) -> String`;
    - `static func encode(_ message: ShellMessage) -> String?`: lo usan las pruebas y el benchmark; nil si pasa de `maxLineBytes`.
  - `public struct InputProtocolError: Error, Equatable { line: String; cause: String }`.

- [ ] **Step 1: Pruebas que fallan:**
  - `tokensSplitOnWhitespace`, `quotedWordKeepsSpaces` (`git commit -m "a b"`), `escapedSpaceJoinsWord`, `currentCommandStartsAfterPipeAndAnd` (`ls | grep x && git ch` → `["git","ch"]`), `unterminatedQuoteIsOneToken`;
  - `currentWordIsEmptyAfterTrailingSpace`, `cursorCountsCharactersNotBytes` (`echo canción 🎵`, cursor 14 = final);
  - `decodesEveryShellMessage`, `escapesRoundTrip` (tab, salto, barra), `unknownVerbThrowsWithTheLine`, `missingFieldThrows`;
  - `lineOverLimitIsNotEncoded` (4097 bytes → nil);
  - `encodesEverySmaltiMessage`, `specsListIsSpaceSeparated`.
- [ ] **Step 2–4:** Rojo → implementar → verde (`swift test --package-path Packages/SmaltiCore`).
- [ ] **Step 5:** Commit `feat(core): add the command line model and the shell input protocol`.

### Task 2: Historial, filtro de secretos y búsqueda ⌃R

**Files:**
- Create: `Domain/Input/{HistoryEntry,HistoryIndex,SecretFilter,HistorySearch}.swift`
- Modify: `Domain/Commands/FuzzyMatch.swift` (se extrae `fuzzyScore`)
- Test: `HistoryIndexTests.swift`, `SecretFilterTests.swift`, `HistorySearchTests.swift`; `FuzzyMatchTests` existentes siguen verdes

**Interfaces:**
- Produces:
  - `public struct HistoryEntry: Codable, Equatable, Sendable { command: String; directory: String; exit: Int?; duration: TimeInterval?; date: Date; pane: PaneID }`.
  - `public struct HistoryIndex: Sendable`:
    - `init(entries: [HistoryEntry], limit: Int)`, que se queda con las `limit` más recientes;
    - `mutating func append(_:)`, que expulsa la más antigua al pasar el límite;
    - `var count: Int`;
    - `func stats(for command: String) -> CommandStats?`;
    - `func commands(in directory: String?) -> [CommandStats]`, donde nil es todos;
    - `func successors(of command: String, in directory: String) -> [String: Int]`;
    - `func lastFailure(in directory: String) -> HistoryEntry?`;
    - `func fixes(after failed: String) -> [String: Int]`: el comando ejecutado justo después de ese mismo comando con exit ≠ 0.
  - `public struct CommandStats: Equatable, Sendable { command: String; uses: Int; lastUsed: Date; lastExit: Int?; usesByDirectory: [String: Int] }`.
  - `public enum SecretFilter`:
    - `static func isSensitive(_ command: String) -> Bool`;
    - `static func redacted(_ text: String) -> String`, que reemplaza cada valor por `«redactado»`.
  - `public func fuzzyScore(_ query: String, in text: String) -> Int?`, que `fuzzyMatch` pasa a usar.
  - `public enum HistoryScope: Sendable { case directory(String), all }`.
  - `public struct HistoryHit: Equatable, Sendable { stats: CommandStats; matched: [Range<Int>] }`.
  - `public enum HistorySearch`:
    - `static func search(_ query: String, scope: HistoryScope, in index: HistoryIndex) -> [HistoryHit]`, que desempata por `lastUsed`;
    - `static func ago(_ date: Date, now: Date, calendar: Calendar) -> String`: "hace N min", "hace N h", "ayer" (día de calendario anterior en la zona dada), "hace N días".

- [ ] **Step 1: Pruebas que fallan:**
  - `indexKeepsMostRecentUpToLimit` (límite 0, 1 y 100.000), `appendPastLimitEvictsOldest`, `statsCountUsesPerDirectory`, `successorsCountOnlySameDirectory`, `fixesFollowSameFailedCommand`;
  - `sensitiveAssignments` (`export OPENAI_API_KEY=x`, `FOO_TOKEN=x cmd`, `PASSWORD=x`), `sensitiveHeaders` (`curl -H "Authorization: Bearer x"`), `sensitiveTokenShapes` (`sk-…`, `ghp_…`, `github_pat_…`, `xoxb-…`, `AKIA…`, JWT de tres partes), `sensitiveURLCredentials` (`https://u:p@host`);
  - `notSensitiveLookalikes` (`echo KEY`, `cat token_list.txt`, `ls ~/.ssh`), `redactionKeepsTheKeyName`;
  - `searchRanksContiguousFirst`, `searchScopeDirectoryFiltersOthers`, `searchTiesByRecency`, `emptyQueryListsByRecency`, `searchReturnsMatchedRanges`;
  - `agoMinutesHoursYesterdayDays` (Bogotá, cruzando medianoche y fin de mes).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): add the command history index, secret filter and history search`.

### Task 3: Predicción heurística

**Files:**
- Create: `Domain/Input/Prediction/{PredictionRule,DirectoryFrequency,LearnedSequence,ProjectCommands,ExitRecovery,HeuristicPredictor,ProjectSnapshot}.swift`
- Test: `Input/PredictionTests.swift` (una `@Suite` por regla, más `HeuristicPredictorTests`)

**Interfaces:**
- Produces:
  - `public struct ProjectSnapshot: Equatable, Sendable { scripts: [String]; makeTargets: [String]; branch: String?; branches: [String]; static let empty }`.
  - `public struct PredictionContext: Sendable { line: CommandLine; directory: String; previous: HistoryEntry?; index: HistoryIndex; project: ProjectSnapshot; now: Date }`.
  - `public struct Candidate: Equatable, Sendable { command: String; score: Double }`.
  - `public protocol PredictionRule: Sendable { func candidates(_ context: PredictionContext) -> [Candidate] }`.
  - Reglas:
    - `DirectoryFrequency(halfLife: 7 * 86_400)`: puntuación `uses × 0.5^(edad/halfLife)`; el directorio actual pesa 1 y los demás 0,25.
    - `LearnedSequence`: sugiere el sucesor del comando anterior en este directorio.
    - `ProjectCommands`: sugiere `npm run <script>`, `make <target>`, y `git checkout <rama>` / `git switch <rama>` sin la rama actual.
    - `ExitRecovery`: si `previous.exit ≠ 0`, sugiere los `fixes(after:)`. Regla fija: `git push` sin upstream → `git push -u origin <branch>`.
  - `public struct HeuristicPredictor: PredictionProvider` (puerto de T5), con `init(rules: [any PredictionRule] = .standard)`. `predict` suma las puntuaciones por comando, se queda con los que empiezan **exactamente** por `line.text` (y son más largos) y devuelve el sufijo. Con la línea vacía solo usa `LearnedSequence` y `ExitRecovery`. Si el cursor no está al final, nil.
  - `public struct Prediction: Equatable, Sendable { suffix: String }`.

- [ ] **Step 1: Pruebas que fallan:**
  - `frequencyDecaysWithHalfLife` (2 usos de hace 7 días = 1 uso de hoy), `currentDirectoryOutweighsOthers`;
  - `sequenceSuggestsSuccessorInDirectory` (`git add .` → `git commit`), `projectSuggestsScriptsTargetsAndBranches`, `projectSkipsCurrentBranch`;
  - `recoveryAfterFailureUsesPastFix`, `recoveryGitPushWithoutUpstream`, `recoveryIgnoredAfterSuccess`;
  - `predictorOnlyCompletesTypedPrefix` (nunca cambia lo escrito), `predictorReturnsSuffixOnly`, `emptyLineUsesSequenceAndRecoveryOnly`, `cursorNotAtEndPredictsNothing`;
  - `emptyHistoryPredictsNothingWithoutProject`, `tiesBreakByRecency`, `exactMatchIsNotSuggested`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): add heuristic prediction rules`.

### Task 4: Specs, motor de completions y menú

**Files:**
- Create: `Domain/Input/Completion/{CompletionSpec,CompletionEngine,CompletionMenu}.swift`
- Test: `Input/CompletionEngineTests.swift`, `CompletionMenuTests.swift`, `Fixtures/` con specs en Swift (git, npm, swift reducidas)

**Interfaces:**
- Produces:
  - `public struct CompletionSpec: Equatable, Sendable { name: [String]; description: String?; subcommands: [CompletionSpec]; options: [OptionSpec]; args: [ArgSpec] }`.
  - `public struct OptionSpec { names: [String]; description: String?; args: [ArgSpec]; isRepeatable: Bool; requiresSeparator: Bool }`.
  - `public struct ArgSpec { name: String?; suggestions: [Suggestion]; templates: Set<ArgTemplate>; generator: GeneratorID?; isOptional: Bool; isVariadic: Bool }`.
  - `public enum ArgTemplate { case filepaths, folders }`.
  - `public struct GeneratorID: Hashable, Sendable { spec: String; path: [String]; ordinal: Int }`.
  - `public struct Suggestion: Equatable, Sendable { name: String; description: String?; insertValue: String? }`.
  - `public enum CompletionTarget: Equatable { case subcommandOrOption(prefix: String, spec: CompletionSpec), optionValue(OptionSpec, prefix: String), argument(ArgSpec, prefix: String) }`.
  - `public enum CompletionEngine`:
    - `static func target(for line: CommandLine, spec: CompletionSpec) -> CompletionTarget?`, que recorre los tokens, baja por subcomandos y salta las opciones y sus valores;
    - `static func rank(_ suggestions: [Suggestion], prefix: String, history: HistoryIndex?) -> [Suggestion]`: primero los que empiezan por el prefijo, luego los difusos (`fuzzyScore`); desempate por uso en el historial y luego por orden de la spec;
    - `static func insertion(of suggestion: Suggestion, into line: CommandLine) -> CommandLine`: reemplaza la palabra actual, añade un espacio salvo en carpetas (que terminan en `/`) y valores con `=`, y escapa espacios.
  - `public struct CompletionMenu: Equatable, Sendable`, estados `closed`, `waiting(seq)`, `open(items, selected)` y refiltrando:
    - `mutating func receive(_ items: [Suggestion], for line: CommandLine) -> MenuEffect`;
    - `mutating func lineChanged(_ line: CommandLine) -> MenuEffect`;
    - `mutating func press(_ key: MenuKey) -> MenuEffect`;
    - `public enum MenuKey { case up, down, tab, enter, escape, other }`;
    - `public enum MenuEffect: Equatable { case none, show, close, insert(CommandLine), fallback }`.
    - Reglas: 0 candidatos → `fallback`; 1 → `insert` sin menú; prefijo común más largo que la palabra → `insert` del prefijo y luego `show`; `tab` y `enter` insertan la selección; `escape` y `other` cierran; ↑ ↓ circulares.

- [ ] **Step 1: Pruebas que fallan:**
  - `targetIsSubcommandAfterCommand` (`git ch`), `targetSkipsOptionsAndTheirValues` (`git -C repo ch`), `targetIsOptionValue` (`git commit -m `), `targetIsArgumentWithTemplate` (`cd Pro`), `targetAfterSeparatorUsesLastCommand`;
  - `rankPrefixBeforeFuzzy`, `rankBreaksTiesByHistoryUse`;
  - `insertionAddsSpace`, `insertionKeepsFolderSlash`, `insertionEscapesSpaces`, `insertionUsesInsertValue`;
  - `menuZeroItemsFallsBack`, `menuOneItemInsertsDirectly`, `menuCommonPrefixInsertsThenShows`, `menuTabAndEnterInsertSelection`, `menuEnterNeverRuns` (el efecto es `insert`, nunca otro), `menuEscapeClosesWithoutChange`, `menuOtherKeyCloses`, `menuWrapsSelection`, `menuRefiltersOnLineChange`, `menuIgnoresItemsForOldLine`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(core): add completion specs, engine and menu state`.

### Task 5: Puertos, fakes, contratos, `InputSession` y `[input]`

**Files:**
- Create: `Application/InputPorts.swift`, `Application/InputSession.swift`, `Domain/Config/InputSettings.swift`, `Tests/.../Input/Support/{InMemoryCommandHistory,FakeProjectContext,FakeCompletionProvider}.swift`, `Tests/.../Input/Contracts/{CommandHistoryContract,ProjectContextContract}.swift`, `Packages/TOMLConfigAdapter/Sources/TOMLConfigAdapter/InputReader.swift`
- Modify: `Domain/Config/SmaltiConfig.swift` (`public var input = InputSettings.standard`), `TOMLConfigParser.swift`
- Test: `InputSessionTests.swift`, `InputSettingsTests.swift`, `Packages/TOMLConfigAdapter/Tests/…/InputReaderTests.swift`

**Interfaces:**
- Consumes: T1–T4.
- Produces:
  - Puertos:
    - `public protocol CommandHistory: Sendable { func load() async throws(HistoryError) -> [HistoryEntry]; func append(_ entry: HistoryEntry) async throws(HistoryError) }`;
    - `public protocol ProjectContext: Sendable { func snapshot(of directory: String) async -> ProjectSnapshot }`;
    - `public protocol CompletionProvider: Sendable { func spec(for command: String) async -> CompletionSpec?; func generate(_ generator: GeneratorID, in directory: String) async throws(CompletionError) -> [Suggestion]; var commands: [String] { get async } }`;
    - `public protocol PredictionProvider: Sendable { func predict(_ context: PredictionContext) -> Prediction? }`.
  - Errores: `HistoryError { operation: String; file: String; cause: String }` y `CompletionError { command: String; cause: String }`.
  - `public actor InputSession`:
    - `init(history: any CommandHistory, project: any ProjectContext, completions: any CompletionProvider, predictor: any PredictionProvider, settings: InputSettings, clock: @escaping @Sendable () -> Date)` (6 dependencias; se agrupan en `InputSession.Ports` para respetar ≤ 3 parámetros);
    - `func start() async`: carga el historial;
    - `func suggest(_ line: CommandLine, pane: PaneID, directory: String) async -> String`, que es `SuggestForLine` y devuelve `""` si no hay sugerencia;
    - `func complete(_ line: CommandLine, directory: String) async -> [Suggestion]?`, que es `CompleteLine`; nil = sin spec (fallback); los ítems fijos van primero y los generados se piden aparte con `generated(for:directory:)`;
    - `func generated(for line: CommandLine, directory: String) async -> [Suggestion]`;
    - `func search(_ query: String, scope: HistoryScope) async -> [HistoryHit]`, que es `SearchHistory`;
    - `func began(_ command: String, pane: PaneID, directory: String) async` y `func finished(pane: PaneID, exit: Int) async`, que son `RecordCommand`: no guarda si `SecretFilter.isSensitive`; la duración va de `began` a `finished`;
    - `var specCommands: [String] { get async }`.
  - `public struct InputSettings: Equatable, Sendable { isEnabled, hasPredictions, hasCompletions: Bool; historyLimit: Int; generatorTimeout: Duration; static let standard }`, con `historyLimit` en 1…1.000.000 y el timeout en 100…10.000 ms.

- [ ] **Step 1: Pruebas que fallan:**
  - los contratos `CommandHistoryContract` (`appendThenLoadReturnsEntry`, `loadEmptyIsEmpty`, `appendKeepsOrder`) y `ProjectContextContract` (`missingDirectoryIsEmpty`), corridos con los fakes;
  - `suggestUsesPredictor`, `suggestDisabledReturnsEmpty`, `completeWithoutSpecReturnsNil`, `completeRanksFixedSuggestions`, `generatedFailureReturnsEmpty`, `recordSkipsSensitive`, `recordMeasuresDuration`, `recordWithoutBeganIsIgnored`, `searchUsesScope`, `startLoadsHistoryOnce`;
  - `inputSettingsDefaults`, `historyLimitOutOfRangeThrows`, y en TOML: `inputTableReadsAllKeys`, `inputTableUnknownKeyThrowsWithLine`.
- [ ] **Step 2–4:** Rojo → implementar → verde (SmaltiCore y TOMLConfigAdapter).
- [ ] **Step 5:** Commit `feat(core): add input ports, the input session and the input settings`.
- [ ] **Step 6: Cierre del bloque 1:** revisión por un revisor nuevo sobre el diff del bloque; corregir según las reglas; marcar en `progress.md`.

---

## Bloque 2 · Adaptadores

### Task 6: `FileCommandHistory` (JSONL)

**Files:**
- Create: `Packages/FileSessionAdapter/Sources/FileSessionAdapter/FileCommandHistory.swift`
- Test: `Packages/FileSessionAdapter/Tests/…/FileCommandHistoryTests.swift`, que corre el `CommandHistoryContract` (las funciones del contrato se exponen desde un target de soporte de pruebas de SmaltiCore, `SmaltiCoreTestSupport`, si aún no existe; si existe, ahí)

**Interfaces:**
- Produces: `public final class FileCommandHistory: CommandHistory`, con `init(file: URL)`. El archivo es `<estado>/input/history.jsonl` (0600, carpeta 0700). `append` escribe una línea JSON con `FileHandle` en modo append. `load` ignora y cuenta las líneas ilegibles. Al cargar con más de `limit × 1.2` líneas, compacta reescribiendo de forma atómica (`AtomicFile`).

- [ ] **Step 1: Pruebas que fallan:** el contrato; `partialLastLineIsSkipped`, `unreadableLineDoesNotStopLoad`, `compactsWhenOverLimit`, `fileIsOwnerOnly`, `missingFileLoadsEmpty`, `appendErrorCarriesFileAndCause` (carpeta sin permisos).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(session): persist the command history as JSON lines`.

### Task 7: `ProjectContextAdapter`

**Files:**
- Create: `Packages/ProjectContextAdapter/{Package.swift,Sources/ProjectContextAdapter/FileProjectContext.swift,Tests/…/{FileProjectContextTests,ProjectContextAdapterGuardTests}.swift}`
- Modify: `App/Smalti.xcodeproj` (paquete nuevo)

**Interfaces:**
- Produces: `public actor FileProjectContext: ProjectContext`, con `init()`, que busca hacia arriba desde el directorio:
  - `package.json` → `scripts` (con `JSONSerialization`);
  - `Makefile` → objetivos `^[A-Za-z0-9_.-]+:`, sin `.PHONY` ni los que empiezan por `.`;
  - `.git/HEAD` → rama (`ref: refs/heads/<x>`) y `.git/refs/heads/**` más `.git/packed-refs` → ramas. Si `.git` es un archivo (worktree), se sigue el `gitdir:`.
  - Caché por directorio, invalidada por el `mtime` de esos archivos.

- [ ] **Step 1: Pruebas que fallan:** el contrato; `readsScriptsFromNearestPackageJSON`, `readsMakeTargetsSkippingSpecial`, `readsBranchAndBranchesIncludingPacked`, `followsWorktreeGitdir`, `invalidJSONYieldsNoScripts`, `cacheRefreshesOnMtimeChange`; guarda: `onlyFoundationIsImported`, `noProcessIsUsed`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(project): read scripts, make targets and git branches for predictions`.

### Task 8: `FigCompletionAdapter` y vendoring

**Files:**
- Create: `scripts/fig/{package.json,package-lock.json,commands.txt,vendor-specs.py,test_vendor_specs.py}`, `Packages/FigCompletionAdapter/{Package.swift,Sources/FigCompletionAdapter/{FigSpecs.swift,FigSpecTranslator.swift,GeneratorRunner.swift,Specs/*.js,LICENSE-fig.txt},Tests/…}`
- Modify: `App/Smalti.xcodeproj`, `.gitignore` (`scripts/fig/node_modules`)

**Interfaces:**
- Produces:
  - `scripts/fig/vendor-specs.py <build-dir> <out-dir>`:
    - lee `commands.txt` (los 36 de la spec);
    - resuelve `loadSpec:"x"` de forma transitiva;
    - reescribe `export{X as default…}` a `globalThis.__smaltiSpec=X;` y cualquier otro `export{…}` a asignaciones en `globalThis.__smaltiExports`;
    - falla con exit 1 si falta un comando o una dependencia;
    - escribe `manifest.json` (nombre → archivo, versión `2.692.3`).
  - `public actor FigSpecs: CompletionProvider`, con `init(bundled: URL, user: URL /* ~/.config/smalti/completions */, runner: GeneratorRunner)`:
    - un `JSContext` por spec cargada, con caché;
    - las specs del usuario ganan;
    - `FigSpecTranslator.spec(from: JSValue) -> CompletionSpec` (subcommands, options, args, `template`, `suggestions`, `generators`);
    - los generadores se guardan por `GeneratorID` dentro del contexto.
  - `public struct GeneratorRunner: Sendable`, con `init(timeout: Duration, cacheLifetime: Duration = .seconds(30))` y `func run(_ script: [String] | String, in directory: String) async throws(CompletionError) -> String`:
    - `/bin/zsh -f -c` con entorno `PATH`, `HOME`, `LANG`;
    - mata el proceso al vencer el timeout.
    - `postProcess`, `splitOn` y `custom(tokens, executeShellCommand)` se evalúan en el `JSContext` con el puente `executeShellCommand → runner`.

- [ ] **Step 1: Pruebas que fallan (Python):** `test_rewrites_default_export`, `test_resolves_loadspec_transitively` (git → git-flow), `test_missing_command_fails`, con una carpeta `build/` de prueba.
- [ ] **Step 2:** Vendorizar: `cd scripts/fig && npm ci && python3 vendor-specs.py node_modules/@withfig/autocomplete/build ../../Packages/FigCompletionAdapter/Sources/FigCompletionAdapter/Specs`. Expected: exit 0 y el manifiesto con 36 comandos más sus dependencias. Medir y anotar el tamaño total en el commit.
- [ ] **Step 3: Pruebas que fallan (Swift):**
  - `gitSpecHasCheckoutSubcommand`, `npmRunArgumentHasScriptGenerator`, `cdUsesFolderTemplate`, `userSpecOverridesBundled` (spec `git` mínima en un directorio temporal);
  - `branchGeneratorListsBranchesInTempRepo`, `generatorTimeoutThrowsWithCommand` (script `sleep 5`, timeout 200 ms), `generatorResultIsCachedFor30Seconds` (reloj inyectado);
  - `brokenUserSpecThrowsAndBundledStillWorks`, `commandsListsBundledAndUser`;
  - guarda: `onlyThisPackageImportsJavaScriptCore`.
- [ ] **Step 4–5:** Implementar → verde.
- [ ] **Step 6:** Commit `feat(completions): load Fig specs with JavaScriptCore and run their generators`.

### Task 9: Prompt, cadena de zsh y `-SmaltiUserZdotdir`

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/PromptState.swift`, `Tests/GhosttyAdapterTests/PromptStateTests.swift` (la prueba del spike convertida, sin capturas ni `/tmp` fijo)
- Modify: `GhosttyConfigText.swift` (`confirm-close-surface = true`, con el porqué en un comentario), `GhosttyTerminalEngine.swift` (`zshChain` según `InputSettings.isEnabled`), `GhosttySurfaceView.swift` (`isAtPrompt`, `cursorCell`), `Domain/Config/LaunchSettings.swift` (`userZdotdirKey = "SmaltiUserZdotdir"`, `userZdotdir: String?`), `App/Smalti/TerminalViewProvider.swift`, `App/Smalti/AppComposition.swift` (`userZdotdir: settings.userZdotdir ?? env ZDOTDIR`), `GhosttyConfigTextTests`, `LaunchSettingsTests`

**Interfaces:**
- Produces:
  - `extension GhosttySurfaceView { var isAtPrompt: Bool /* !needs_confirm_quit && !process_exited */; var cursorCell: Rect? /* en puntos de la vista, origen arriba a la izquierda, desde ime_point y el tamaño de celda */ }`.
  - `protocol TerminalViewProvider { func view(for:) -> NSView?; func isAtPrompt(_ pane: PaneID) -> Bool; func cursorCell(_ pane: PaneID) -> Rect? }`.
  - `zshChain(for:zshDirectory:userZdotdir:isInputEnabled:)`: con `isInputEnabled` encadena siempre; sin él, como hoy.

- [ ] **Step 1: Pruebas que fallan:** `promptAtFirstPromptAndWhileTyping`, `promptInContinuationPS2`, `notPromptDuringCommand`, `notPromptInsideRead`, `notPromptOnAlternateScreen`, `notPromptAfterProcessExited`, `cursorCellMatchesTypedColumns`; `configEnablesConfirmCloseSurface`; `chainAlwaysWithInputEnabled`, `chainNeedsHistoryWithInputDisabled`; `userZdotdirArgumentIsRead`, `emptyUserZdotdirIsAbsent`.
- [ ] **Step 2–4:** Rojo → implementar → verde (GhosttyAdapter, SmaltiCore, build de la app).
- [ ] **Step 5:** Commit `feat(ghostty): detect the shell prompt and always chain Smalti's zsh file`.
- [ ] **Step 6: Cierre del bloque 2:** revisión del bloque; correcciones; `progress.md`.

---

## Bloque 3 · Canal con zsh

### Task 10: `InputSocketServer`

**Files:**
- Create: `Packages/IPCAdapter/Sources/IPCAdapter/InputSocketServer.swift`
- Modify: `Domain/PaneFileLocator.swift` (`IPCEndpoints.inputSocket: URL`; `PaneEnvironment` exporta `SMALTI_INPUT_SOCKET`), `PaneEnvironmentTests`
- Test: `Packages/IPCAdapter/Tests/IPCAdapterTests/InputSocketServerTests.swift`

**Interfaces:**
- Produces: `public final class InputSocketServer: Sendable`, con `init(socketFile: URL, handler: @escaping @Sendable (InputConnection, ShellMessage) -> Void) throws(IPCError)`:
  - un hilo de lectura propio por conexión, que nunca toca el hilo principal;
  - las líneas ilegibles se registran y se descartan;
  - `public struct InputConnection: Hashable, Sendable { id: UUID; func send(_ message: SmaltiMessage) }`: escribe sin bloquear (si el búfer está lleno, descarta y lo registra; `SO_NOSIGPIPE`);
  - `var onClose: @Sendable (InputConnection) -> Void`;
  - `func stop()`;
  - la ruta debe tener < 104 bytes; si no, `IPCError` con la ruta.

- [ ] **Step 1: Pruebas que fallan:** `decodesMessagesFromClient`, `responsesGoToTheirOwnConnection` (dos clientes), `closedConnectionIsForgotten` (`onClose` se llama una vez), `unreadableLineIsDropped`, `clientThatNeverReadsDoesNotBlockServer` (2.000 `send` a un cliente que no lee, en < 100 ms), `longPathThrowsWithPath`, `socketIsOwnerOnly`; en `PaneEnvironmentTests`: `exportsInputSocket`.
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(ipc): add the shell input socket server`.

### Task 11: Script de zsh: canal, fantasma y aceptar

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/SmaltiInputScript.swift` (el texto zsh, que `SmaltiZshEnv.text` incluye detrás del bloque de historial cuando existe `SMALTI_INPUT_SOCKET`), `Tests/GhosttyAdapterTests/ZshChannelTests.swift`, `Tests/GhosttyAdapterTests/Support/{ZshHarness,FakeInputServer}.swift`

**Interfaces:**
- Consumes: T1 (protocolo), T10 (para el servidor real en T13; aquí, `FakeInputServer` con modos `normal`, `slow(2 s)`, `neverReads`, `closesAfter(n)` y `staleSeq`).
- Produces (funciones y widgets zsh, prefijo `_smalti_input_`):
  - conexión y `hello` en el primer `precmd`, con `zmodload zsh/net/socket zsh/zselect` (si falla, no se instala nada);
  - `_smalti_input_send`: la única que escribe (constraints globales);
  - hook de `zle-line-pre-redraw` vía `add-zle-hook-widget`: si cambiaron `BUFFER` o `CURSOR`, envía `line`; si el mensaje pasa de 4096 bytes, borra el fantasma y no envía; pinta el fantasma: `POSTDISPLAY` + `region_highlight+=("${#BUFFER} $((${#BUFFER}+${#POSTDISPLAY})) fg=#5f6672 memo=smalti")`, quitando antes su entrada anterior;
  - `zle -F -w $fd _smalti_input_receive`: aplica `suggest`, `edit`, `run` y `fallback` solo con el `seq` vigente; EOF o error → desactivar;
  - `preexec` → `exec`; `precmd` → `done` con `$?` guardado primero;
  - `smalti-accept`: acepta el fantasma si `CURSOR == ${#BUFFER}`; si no, el widget anterior. Se enlaza a `forward-char` y `end-of-line` (→ y ⌃E) en `emacs` y `viins`.
  - `ZshHarness` (pruebas):
    - lanza `zsh -d -i` en un pty (`posix_openpt` desde Swift, solo en pruebas);
    - `ZDOTDIR` temporal vía `SMALTI_USER_ZDOTDIR` + `GHOSTTY_ZSH_ZDOTDIR` al directorio de Smalti;
    - escribe teclas y lee el estado desde un widget de depuración que vuelca `BUFFER`, `POSTDISPLAY` y `region_highlight` a un archivo temporal.

- [ ] **Step 1: Pruebas que fallan:**
  - `sendsLineWhenBufferChanges`, `doesNotResendUnchangedLine`, `paintsGhostFromSuggest`, `ignoresSuggestWithOldSeq`, `rightArrowAcceptsGhostAtEnd`, `rightArrowMovesCursorWhenNotAtEnd`, `ctrlEAcceptsGhost`;
  - `execAndDoneCarryCommandAndExit`, `nonAsciiCursorMatches` (`echo canción 🎵`);
  - `hugePasteKeepsShellResponsive` (20.000 caracteres: sin `line`, la línea sigue editable);
  - C5: `noSocketLeavesShellNormal`, `slowServerNeverBlocksTyping` (cada tecla < 50 ms), `serverThatNeverReadsNeverBlocks` (500 teclas), `serverClosingMidwayDisablesQuietly` (el shell vive, ningún mensaje, fantasma borrado), `afterDisableChildrenKeepDefaultSigpipe` (`yes | head -1` termina con 0).
- [ ] **Step 2–4:** Rojo → implementar → verde (`kb-progress run zsh -- swift test --package-path Packages/GhosttyAdapter --filter Zsh`).
- [ ] **Step 5:** Commit `feat(ghostty): add the zsh input channel with ghost text`.

### Task 12: Toma de control y Tab

**Files:**
- Create: `Tests/GhosttyAdapterTests/Fixtures/zsh-plugins/{zsh-autosuggestions.zsh,zsh-syntax-highlighting/…,fzf-key-bindings.zsh,LICENSES.md,VERSIONS.md}` (copiados de Homebrew con su versión), `Tests/GhosttyAdapterTests/ZshTakeoverTests.swift`
- Modify: `SmaltiInputScript.swift`

**Interfaces:**
- Produces:
  - `_smalti_input_takeover`: el hook de `precmd` se reubica al final de `precmd_functions` en cada `precmd` y actúa cuando `_zsh_autosuggest_start` ya no está en `precmd_functions`. Entonces:
    - quita `_zsh_autosuggest_bind_widgets` de `precmd`;
    - restaura cada widget `autosuggest-orig-*` sobre su nombre;
    - comprueba que ningún widget enlazado es `_zsh_autosuggest_*`; si queda alguno, desactiva F4 y lo anota con `print -u2` solo con `SMALTI_INPUT_DEBUG`;
  - `bindkey '^R' smalti-history` en `emacs`, `viins` y `vicmd`;
  - `smalti-complete` en `^I`, que guarda el widget anterior de `^I` en `_smalti_input_tab_fallback`. Ejecuta el anterior en el acto si:
    - el comando no está en la lista de `specs`;
    - la palabra termina en `**`;
    - la lista no llegó.
    Si no, envía `complete`. `fallback` ejecuta el anterior.
  - `smalti-history`: envía `history`; `edit` y `run` aplican el resultado.

- [ ] **Step 1: Pruebas que fallan** (`.zshrc` de prueba que carga las fixtures como el de Simón, más un `bindkey '^I' expand-or-complete`):
  - `onlySmaltiGhostWithAutosuggestionsLoaded` (tras escribir: `POSTDISPLAY` = la sugerencia del servidor de pruebas, nunca la de autosuggestions);
  - `autosuggestionWrappersAreRestored`, `syntaxHighlightingStillHighlights` (sus entradas siguen en `region_highlight` junto a `memo=smalti`);
  - `ctrlROpensSmaltiNotFzf` (llega `history` al servidor), `tabWithoutSpecRunsUserWidget` (se ejecuta `expand-or-complete`, sin mensaje `complete`), `tabWithDoubleStarRunsUserWidget`, `tabWithSpecSendsComplete`, `fallbackReplyRunsUserWidget`;
  - `withoutSmaltiPluginsBehaveAsBefore` (mismo `.zshrc` sin `SMALTI_INPUT_SOCKET`: autosuggestions pinta y ⌃R es de fzf).
- [ ] **Step 2–4:** Rojo → implementar → verde.
- [ ] **Step 5:** Commit `feat(ghostty): take over autosuggestions, Ctrl-R and Tab inside Smalti panes`.
- [ ] **Step 6: Cierre del bloque 3:** revisión del bloque; correcciones; `progress.md`.

---

## Bloque 4 · App

### Task 13: `InputCoordinator` y composición

**Files:**
- Create: `App/Smalti/Input/InputCoordinator.swift`
- Modify: `App/Smalti/AppComposition.swift` (crea `FileCommandHistory(<estado>/input/history.jsonl)`, `FileProjectContext()`, `FigSpecs(bundled:user:runner:)`, `HeuristicPredictor()`, `InputSession`, `InputSocketServer(<estado>/input.sock)`), `TilingController.swift` (directorio del panel por id, menú y paleta por panel), `Domain/Theme/Theme+Obsidian.swift` (`ghostText` y tokens del menú), `docs/design/README.md` solo si cambia algún valor
- Test: `Packages/SmaltiCore/Tests/…/Input/InputRoutingTests.swift` (la lógica de qué responder a cada `ShellMessage` vive en el dominio como `InputRouting.respond(to:context:) async -> [SmaltiMessage]` sobre `InputSession`, para probarla sin app)

**Interfaces:**
- Produces:
  - `public enum InputRouting` (dominio) con `static func respond(to message: ShellMessage, pane: PaneID, directory: String, session: InputSession) async -> [SmaltiMessage]`:
    - `hello` → `specs`;
    - `line` → `suggest`;
    - `exec` → `began` y nada;
    - `done` → `finished` y nada;
    - `complete` → si hay spec, nada (la app abre el menú); si no, `fallback`;
    - `history` → nada (la app abre la paleta).
  - `@MainActor final class InputCoordinator`:
    - asocia `InputConnection` ↔ `PaneID` en `hello`;
    - para `complete` y `history`, abre la capa solo si `provider.isAtPrompt(pane)`;
    - cierra las capas cuando `isAtPrompt` pasa a falso (comprobado en cada `wakeup` del motor y en cada mensaje);
    - el directorio sale de `pane.workingDirectory` al recibir el mensaje.

- [ ] **Step 1: Pruebas que fallan:** `helloRepliesSpecs`, `lineRepliesSuggestion`, `lineWithInputDisabledRepliesEmpty`, `completeWithoutSpecRepliesFallback`, `completeWithSpecRepliesNothing`, `execThenDoneRecordsEntry`, `suggestionUsesDirectoryAtMessageTime`.
- [ ] **Step 2–4:** Rojo → implementar → verde; `xcodebuild … build`; prueba manual automatizada: XCUITest mínimo `ghostTextAppearsAfterRunningACommandTwice` (en T16).
- [ ] **Step 5:** Commit `feat(app): wire the input session to the shell channel`.

### Task 14: Menú de completions

**Files:**
- Create: `App/Smalti/Input/{CompletionMenuController,CompletionMenuView,CompletionMenuLayout}.swift` (la colocación, pura, en el dominio: `Domain/Input/Completion/MenuPlacement.swift`)
- Modify: `KeyRouter.swift` (con un menú de F4 abierto, ↑ ↓ ↩ ⇥ esc van al menú; el resto sigue igual), `InputCoordinator.swift`
- Test: `Input/MenuPlacementTests.swift`

**Interfaces:**
- Consumes: T4 (`CompletionMenu`), T9 (`cursorCell`), T13.
- Produces:
  - `public enum MenuPlacement { static func frame(cursor: Rect, pane: Size, rows: Int, theme: InputMenuTokens) -> Rect }`: debajo si caben 6 filas; si no, encima; se desplaza a la izquierda para no salirse;
  - `CompletionMenuView`: filas del tablero (nombre mono 92 pt, descripción Inter en texto secundario, selección `glow`); pie "Tab completar · → aceptar sugerencia · ⌃R historial"; máximo 8 filas con scroll; identificadores de accesibilidad `smalti.completionMenu` y `smalti.completionRow`;
  - `CompletionMenuController`: aplica los `MenuEffect`. `insert` → `InputConnection.send(.edit(seq, line))`; `fallback` → `.fallback(seq)`. Los generados llegan aparte y refiltran sin mover la selección.

- [ ] **Step 1: Pruebas que fallan:** `menuBelowWhenSixRowsFit`, `menuFlipsAboveNearBottom`, `menuShiftsLeftNearRightEdge`, `menuFollowsCellAfterResize` (misma celda con otro tamaño de panel → posición recalculada).
- [ ] **Step 2–4:** Rojo → implementar → verde; build.
- [ ] **Step 5:** Commit `feat(app): add the completion menu anchored at the cursor`.

### Task 15: Paleta ⌃R y comando de ⌘K

**Files:**
- Create: `App/Smalti/Input/{HistoryPaletteController,HistoryRowView}.swift`
- Modify: `Domain/Commands/CommandCatalog.swift` (comando `searchHistory`, "Buscar en el historial", atajo ⌃R mostrado), `Domain/Config/CommandID.swift`, `Keymap.swift` (⌃R **no** se enlaza en el keymap: lo decide zsh; el comando de ⌘K envía `history` al panel activo pidiéndoselo al shell, y solo si `isAtPrompt`), `CommandPaletteView.swift` si hace falta compartir el contenedor
- Test: `CommandCatalogTests` (`searchHistoryIsListed`), `HistorySearchTests` ya cubre el orden

**Interfaces:**
- Produces:
  - `HistoryPaletteController`: reutiliza el contenedor y los tokens de `CommandPaletteController` (`Paleta.dc.html`), centrado en el panel, con ancho 86 % (480…720). Muestra los chips "Este directorio" / "Todos"; ⇥ alterna el ámbito; ↑ ↓ mueven la selección; ↩ → `edit` con el comando; ⌘↩ → `edit` + `run`; esc → nada.
  - Filas: comando en mono con los rangos coincidentes en acento; punto de exit (verde 0, rojo ≠ 0, hueco si no hay), `HistorySearch.ago` y `×N`.
  - Vacío: "Historial vacío: se llena con lo que ejecutes en Smalti". Sin resultados: "Sin coincidencias".
  - Identificadores: `smalti.historyPalette`, `smalti.historyRow`, `smalti.historyScope`.

- [ ] **Step 1: Pruebas que fallan:** `searchHistoryIsListed`, `searchHistoryNeedsPrompt` (el comando no hace nada si `isAtPrompt` es falso, probado con el fake del proveedor en `TilingControllerTests` si existe; si no, en T16).
- [ ] **Step 2–4:** Rojo → implementar → verde; build.
- [ ] **Step 5:** Commit `feat(app): add the Ctrl-R history palette`.

### Task 16: UI tests de F4, aislamiento y capturas

**Files:**
- Create: `App/SmaltiUITests/{InputTests,InputIsolationTests}.swift`, `App/SmaltiUITests/Fixtures/byte-recorder.sh` (lee de la tty en modo raw y escribe los bytes en hex a un archivo)
- Modify: `IsolatedApp.swift` (`isolatedSmaltiWithIntegration()`: shell `/bin/zsh -d`, `-SmaltiUserZdotdir` a un directorio temporal vacío, `TMUX` de guarda), `DesignCaptureTests.swift` (capturas del menú y de la paleta)

**Interfaces:**
- Consumes: todo lo anterior.

- [ ] **Step 1: Pruebas que fallan:**
  - C10/C11: `ghostTextAppearsAfterRunningACommandTwice`, `rightArrowAcceptsGhost`, `tabOpensMenuForGit` (en un repo temporal), `menuEnterInsertsWithoutRunning`, `ctrlROpensHistoryPalette`, `historyScopeToggles`, `historyCommandEnterRuns`, `historyEscapeLeavesLineUntouched`;
  - C2: `keysReachByteRecorderUnchanged` (Tab, ⌃R, →, ↑, ↓ y esc dentro de `byte-recorder.sh` → bytes exactos y ningún `smalti.completionMenu` ni `smalti.historyPalette`), `keysReachReadUnchanged`, `lessReceivesSlashSearch`, `nvimReceivesTabAndCtrlR` (si `nvim` está instalado; si no, la prueba se salta y lo dice), `htopQuitsWithQ` (ídem);
  - C15: `inputTestsUseIsolatedShellAndState` (en `InputIsolationTests`: `$ZDOTDIR` del shell es el temporal y `$TMUX` es la guarda).
- [ ] **Step 2:** Correr: `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/check-daily-untouched.sh scripts/test-ui.sh InputTests` y luego `InputIsolationTests`. Expected: exit 0, todas `ok`, "daily state untouched".
- [ ] **Step 3:** Capturas (C11): menú y paleta superpuestos al 50 % sobre `Main.dc.html` y la maqueta de ⌃R renderizados con Chrome headless, en `docs/specs/F4-assets/`.
- [ ] **Step 4:** Commit `test(app): cover smart input end to end`.
- [ ] **Step 5: Cierre del bloque 4:** revisión del bloque; correcciones; `progress.md`.

---

## Bloque 5 · Cierre de fase

### Task 17: Mediciones, checklist, revisión final, mutación y PR

**Files:**
- Create: `scripts/measure-input.sh`, `scripts/input-bench/{generate-history.py,widget.zsh}`, `docs/specs/F4-checklist.md`
- Modify: `progress.md`, `CLAUDE.md` (comandos nuevos: paquetes, `measure-input.sh`, `scripts/fig/vendor-specs.py`)

**Interfaces:**
- Produces: `scripts/measure-input.sh <runs>`:
  - arranca la app Release con `env -i …` y `-SmaltiStatePath` temporal, sembrado con 50.000 entradas sintéticas (`generate-history.py`, semilla fija, 400 directorios y 3.000 comandos distintos con distribución de Zipf);
  - un `zsh -d -i` con `widget.zsh` escribe 2.000 líneas parciales tecla a tecla y registra, por tecla, el tiempo de `line` enviado → `POSTDISPLAY` aplicado;
  - imprime p50, p95 y p99 por corrida y en total, y el p99 del dominio desde un signpost en `InputSession.suggest`;
  - con `--real-history`, convierte `~/.zsh_history` en memoria (solo lectura, sin directorio) y repite.

- [ ] **Step 1:** C1: `"$KB_ROOT/_system/bin/kb-progress" run bench -- scripts/measure-input.sh 5` y con `--real-history`. Expected: p99 < 16 ms en ambos. Si no se cumple, para y avisa a Simón con los números antes de optimizar.
- [ ] **Step 2:** C13: `ObservatoryLatencyTests`-style con `LatencyProbe` escribiendo 60 s con generadores activos. Expected: ningún bloqueo > 16 ms.
- [ ] **Step 3:** C3: repetir las capturas de la lista de render de F0 (A9–A11) que son automatizables con F4 activo; lo manual queda aplazado en el checklist.
- [ ] **Step 4:** `docs/specs/F4-checklist.md` con C1–C16, evidencia y aplazados.
- [ ] **Step 5:** Revisión final de la rama completa con un revisor nuevo en el modelo más capaz; una sola tanda de correcciones, cada una con su prueba RED→GREEN.
- [ ] **Step 6:** Mutación: `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore`. Expected: ≥ 80 %; los sobrevivientes se matan con pruebas nuevas.
- [ ] **Step 7:** Suites completas en verde, con el código de salida real: SmaltiCore, GhosttyAdapter, TOMLConfigAdapter, FileSessionAdapter, IPCAdapter, FigCompletionAdapter, ProjectContextAdapter, observatorio, `scripts/fig` y `scripts/mutation` en Python, lint, `build-identity.test.sh` y los XCUITest afectados (`InputTests`, `InputIsolationTests`, `CommandPaletteTests`, `TerminalPaneTests`) con `check-daily-untouched.sh`.
- [ ] **Step 8:** Commit `docs(f4): record the F4 close`; push de `feature/f4-input`; PR → `develop` con capturas y mediciones. Tras el merge de Simón, PR `develop` → `main`. Nada se fusiona sin Simón.

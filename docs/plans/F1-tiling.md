# F1 · Tiling y workspaces — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** varios paneles libghostty con tiling automático (Dwindle, Columnas, Maestro + pila), manejables por teclado, agrupados en workspaces, con cabecera, barra de estado, configuración TOML y paleta ⌘K.

**Architecture:** todo el tiling es dominio puro en `SmaltiCore`: geometría propia, `LayoutTree`, estrategias, `Workspace`/`WorkspaceSet`, catálogo de comandos y búsqueda difusa. Los casos de uso reciben el estado como `inout WorkspaceSet` y hablan con los puertos `TerminalEngine` y `ConfigStore`. Hay un adaptador nuevo, `TOMLConfigAdapter` (paquete propio). `GhosttyAdapter` añade nombre de proceso, oclusión, cierre por un solo camino y `keybind = clear`. La app es el composition root y aporta las vistas AppKit y el `KeyRouter`.

**Tech Stack:** Swift 6.4 (Xcode 27.2), AppKit, Swift Testing, XCUITest, libghostty v1.4.0, librería TOML elegida en Task 12, `scripts/mutation/mutate.py`.

**Spec:** `docs/specs/F1-tiling.md` (con los ajustes R1–R10) · Convenciones: `CLAUDE.md` · Diseño: `docs/design/README.md`, `docs/design/Main.dc.html`, `docs/design/Paleta.dc.html` · Riesgos heredados: `docs/specs/F0-spike-report.md`

## Global Constraints

- `SmaltiCore` solo importa `Foundation`, y solo para tipos de valor y operaciones sobre `String`. Prohibido AppKit, SwiftUI, Combine, GhosttyKit, Darwin y la librería TOML (la guarda de imports no se toca).
- Solo `GhosttyAdapter` importa GhosttyKit, y solo `TOMLConfigAdapter` importa la librería TOML. Ningún `ghostty_*_t` cruza un puerto.
- Geometría del dominio: `Point`, `Size`, `Rect` en puntos (`Double`), con el origen arriba a la izquierda (y crece hacia abajo, como los tableros). Nunca `CGRect` en `SmaltiCore`.
- Valores fijados por la spec y los tableros: margen del área de paneles 10, separación 8, `Ratio` en 0,1–0,9, mínimo de panel 240 × 120 pt, Dwindle 1.35 : 1 (`Ratio(1.35 / 2.35)` ≈ 0,574), Maestro 1.15 : 1 de alto (`Ratio(1.15 / 2.15)` ≈ 0,535), splits internos 0,5, redimensionar 5 % por pulsación, franja 40, cabecera 30, barra de estado 28, animación ≤ 150 ms que se desactiva con "Reducir movimiento".
- Variantes: cada layout es un tipo que implementa `LayoutStrategy`, registrado en `LayoutCatalog`. No hay `switch` por tipo de layout.
- Swift 6 con concurrencia estricta. Errores con `throws(Tipo)` y contexto. Sin `!`, `try!`, `as!` ni `unsafe*` sin un comentario que lo justifique. Máximo 3 parámetros: si hacen falta más, se agrupan en un tipo con nombre.
- Pruebas: Swift Testing en formato Arrange/Act/Assert, un concepto por prueba. TDD: la prueba roja va antes que el código.
- Toda prueba que abra un shell usa `XCUIApplication.isolatedSmalti()` (`-SmaltiShellCommand "/bin/zsh -f"` y `-SmaltiConfigPath <fixture>`). Las UI tests restauran todos los tipos del portapapeles (R9).
- Ningún atajo usa ⌥ sin ⌘ o ⌃. Los atajos de la cabecera se muestran como `⌘1`…`⌘9`.
- Textos de interfaz en español, tal cual los tableros. Los tokens visuales salen solo de `Theme.obsidian` (`Theme+Obsidian.swift`); las vistas no llevan literales.
- Verificación (de `CLAUDE.md`):
  - `swift test --package-path Packages/SmaltiCore`
  - `swift test --package-path Packages/GhosttyAdapter`
  - `swift test --package-path Packages/TOMLConfigAdapter`
  - `xcodebuild -project App/Smalti.xcodeproj -scheme Smalti -derivedDataPath build build`
  - `swift format lint --strict -r App Packages/SmaltiCore Packages/GhosttyAdapter/Sources Packages/GhosttyAdapter/Tests Packages/TOMLConfigAdapter`
  - `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh <Clase>` (solo las clases afectadas)
  - `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore`
  - Comprueba el código de salida real; nunca des una suite por buena mirando una salida que pasó por un pipe.
- Rama `feature/f1-tiling` (desde `develop`). Conventional Commits en inglés, terminados en `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Cada tarea terminada se marca en `progress.md`.

## Review Focus

1. **Sale un proceso de un workspace oculto** (`sleep 2; exit` y cambias de workspace): su panel desaparece de ese workspace, el workspace activo no cambia y el foco tampoco (Task 9: `exitInHiddenWorkspaceLeavesActiveUntouched`).
2. **Se cierra el panel enfocado:** el foco pasa al panel anterior en orden (o al siguiente si era el primero) y lo que tecleas llega a ese panel (Task 5: `removingFocusedPaneFocusesPrevious`; Task 17: E2E `testClosingFocusedPaneMovesKeyboardFocus`).
3. **La ventana se encoge por debajo de lo que piden los paneles:** ningún frame queda con ancho o alto negativo ni cero, aunque el área sea menor que la suma de separaciones (Task 2: `framesNeverCollapseBelowOnePoint`).
4. **TOML con erratas:** una clave desconocida (`font_sise`), un tipo erróneo (`font_size = "13"`) o un layout inexistente (`default_layout = "spiral"`) produce un error con archivo, línea y clave, y se conserva la configuración previa (Task 12: `unknownKeyIsReportedWithLine`, `wrongTypeIsReportedWithLine`, `unknownLayoutIsReportedWithLine`).
5. **Atajos con ⇧ en el layout Latin American:** `=` es ⇧0, así que ⇧⌘0 produce `=` con ⇧ y debe disparar "Igualar tamaños". ⌥Q (`@`) debe llegar al shell (Task 15: `shiftedCharacterMatchesShiftedChord`, `optionCharacterPassesThrough`).

---

## Mapa de archivos

```text
Packages/SmaltiCore/
  Sources/SmaltiCore/Domain/Geometry/{Point,Size,Rect,SplitAxis,Direction}.swift   T1
  Sources/SmaltiCore/Domain/Layout/{Ratio,LayoutTree,LayoutGeometry}.swift        T1–T3
  Sources/SmaltiCore/Domain/Layout/{LayoutStrategy,DwindleLayout,ColumnsLayout,
                                    MasterStackLayout,LayoutCatalog}.swift          T4
  Sources/SmaltiCore/Domain/Workspace/{WorkspaceID,Workspace,WorkspaceSet}.swift  T5–T6
  Sources/SmaltiCore/Domain/{Pane,TerminalEvent,WorkingDirectory}.swift (modif.)  T5
  Sources/SmaltiCore/Domain/Config/{SmaltiConfig,KeyChord,Keymap,ConfigError}.swift T7
  Sources/SmaltiCore/Domain/Commands/{CommandID,Command,CommandCatalog,FuzzyMatch}.swift T8
  Sources/SmaltiCore/Domain/Theme/* (tokens de F1)                                 T7
  Sources/SmaltiCore/Application/{TerminalEngine,OpenPane,ClosePane,HandlePaneExit,
       ArrangePanes,WorkspaceCommands,ConfigStore,ReloadConfig,SearchCommands}.swift T9–T11
  Sources/SmaltiCoreTestSupport/{FakeTerminalEngine,InMemoryConfigStore,
       ConfigStoreContract}.swift                                                   T7, T9
Packages/TOMLConfigAdapter/                                                         T12
Packages/GhosttyAdapter/ (config, proceso, oclusión, cierre)                        T13
App/Smalti/ (composition root, vistas, KeyRouter, paleta)                           T14–T16
App/SmaltiUITests/                                                                  T17
docs/specs/F1-checklist.md                                                          T18
```

`SmaltiCoreTestSupport` es un target de biblioteca nuevo dentro del paquete `SmaltiCore` (producto `SmaltiCoreTestSupport`, depende de `SmaltiCore`, importa `Testing`). Ahí viven los fakes y la prueba de contrato de `ConfigStore`, que comparten `SmaltiCoreTests` y `TOMLConfigAdapterTests`. `FakeTerminalEngine` se mueve aquí desde `Tests/SmaltiCoreTests/Support/`. La guarda de imports solo recorre `Sources/SmaltiCore`.

Ejecución: las tareas T1–T13 las hacen subagentes. Las tareas T14–T18 las hago yo directamente, porque necesitan la pantalla y el teclado de Simón (XCUITest toma el foco, hay capturas y mediciones con Instruments), y aviso antes de empezarlas.

---

### Task 1: Geometría y `Ratio`

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Geometry/{Point,Size,Rect,SplitAxis,Direction}.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Layout/Ratio.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/GeometryTests.swift`, `RatioTests.swift`

**Interfaces:**
- Produces:
  - `public struct Point: Hashable, Sendable { x, y: Double }`
  - `public struct Size: Hashable, Sendable { width, height: Double }`
  - `public struct Rect: Hashable, Sendable { origin: Point; size: Size }` con `init(x:y:width:height:)`, `minX`, `maxX`, `minY`, `maxY`, `midX`, `midY` y `func insetBy(_ amount: Double) -> Rect`. Ancho y alto nunca bajan de 0.
  - `public enum SplitAxis: Sendable { case sideBySide, stacked }`. `sideBySide`: `first` a la izquierda y `second` a la derecha. `stacked`: `first` arriba y `second` abajo.
  - `public enum Direction: CaseIterable, Sendable { case left, right, up, down }`, con `var axis: SplitAxis` (left/right → `sideBySide`) y `var pointsTowardSecond: Bool` (right/down → true).
  - `public struct Ratio: Hashable, Sendable { public let value: Double }`, con `init(_ value: Double)` que recorta a `0.1...0.9`, `static let half`, `static let bounds: ClosedRange<Double> = 0.1...0.9` y `func adding(_ delta: Double) -> Ratio`.

- [ ] **Step 1: Pruebas que fallan:**
  - `ratioClampsBelowMinimum` (`Ratio(0.02).value == 0.1`)
  - `ratioClampsAboveMaximum` (`Ratio(0.95).value == 0.9`)
  - `ratioKeepsValuesInsideBounds` (`Ratio(0.574).value == 0.574`)
  - `addingClampsAtTheEdge` (`Ratio(0.88).adding(0.05).value == 0.9`)
  - `insetShrinksEverySide` (`Rect(x: 0, y: 0, width: 100, height: 50).insetBy(10) == Rect(x: 10, y: 10, width: 80, height: 30)`)
  - `insetNeverProducesNegativeSize` (`Rect(x: 0, y: 0, width: 10, height: 10).insetBy(20).size == Size(width: 0, height: 0)`)
  - `directionMapsToAxis`
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore` → falla por tipos inexistentes.
- [ ] **Step 3:** Implementar los tipos.
- [ ] **Step 4:** Las pruebas pasan, `swift format lint` sin salida.
- [ ] **Step 5:** Commit `feat(core): add domain geometry and split ratio`.

### Task 2: `LayoutTree`: hojas, frames e igualar

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Layout/LayoutTree.swift`, `LayoutGeometry.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/LayoutTreeFramesTests.swift`

**Interfaces:**
- Consumes: T1.
- Produces:
  - `public indirect enum LayoutTree: Hashable, Sendable { case leaf(PaneID); case split(axis: SplitAxis, ratio: Ratio, first: LayoutTree, second: LayoutTree) }`
  - `var panes: [PaneID]` (hojas en orden, de izquierda a derecha y de arriba abajo).
  - `func frames(in area: Rect, gap: Double) -> [PaneID: Rect]`
  - `func equalized() -> LayoutTree`
  - `public struct LayoutGeometry: Hashable, Sendable { area: Rect; gap: Double; minimumPaneSize: Size }`, con `static func standard(area: Rect) -> LayoutGeometry` (gap 8, mínimo 240 × 120) y `func fits(_ tree: LayoutTree) -> Bool` (todos los frames ≥ mínimo).

Algoritmo de `frames` (las separaciones se reparten según el `span`, definido abajo): en un split de eje `A` con extensión `E` a lo largo de `A`, el contenido es `C = E - (span(self) - 1) * gap`. `first` recibe `C * ratio + (span(first) - 1) * gap`, y `second` lo que queda tras `first` y una separación `gap`. Con dos hojas equivale a CSS `fr` (`(E - gap) * ratio`), y con `ratio = span(first) / span(self)` todas las hojas miden lo mismo, separaciones incluidas. Ningún frame baja de 1 pt de ancho ni de alto.

Algoritmo de `equalized`: la `ratio` de cada split es `span(first) / (span(first) + span(second))`, donde `span` se mide a lo largo del eje del split. Una hoja vale 1, un split del mismo eje suma y un split del otro eje toma el máximo. Así quedan hojas del mismo tamaño en cada eje (B3).

- [ ] **Step 1: Pruebas que fallan** (tolerancia 0,01):
  - `singleLeafFillsTheArea`
  - `sideBySideSplitHonoursRatioAndGap`: `split(.sideBySide, Ratio(0.5), a, b)` en `Rect(0, 0, 1008, 500)` con gap 8 → `a = (0, 0, 500, 500)`, `b = (508, 0, 500, 500)`.
  - `stackedSplitHonoursRatioAndGap`
  - `panesListsLeavesInOrder`
  - `framesNeverCollapseBelowOnePoint`: árbol de 9 hojas en `Rect(0, 0, 40, 40)` → todos los anchos y altos ≥ 1 (Review Focus 3).
  - `columnChainWithSpanRatiosHasEqualWidths`: cadena `sideBySide` `a | (b | c)` con ratios 1/3 y 1/2 en `Rect(0, 0, 1308, 732)` → los tres anchos ≈ 430.67.
  - `equalizedColumnsHaveEqualWidths`: cadena `sideBySide` de 4 hojas con ratios 0,3 / 0,7 / 0,2 → los 4 anchos son iguales.
  - `equalizedDwindleBalancesEachAxis`: `a | (b / c)` con ratios 0,8 / 0,3 → `a.width == b.width` y `b.height == c.height`.
  - `fitsRejectsFramesBelowMinimum`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Pruebas en verde.
- [ ] **Step 5:** Commit `feat(core): add layout tree frames and equalize`.

### Task 3: `LayoutTree`: redimensionar, intercambiar y vecino

**Files:**
- Modify: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Layout/LayoutTree.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/LayoutTreeEditingTests.swift`

**Interfaces:**
- Consumes: T1 y T2.
- Produces:
  - `public struct ResizeRequest: Hashable, Sendable { pane: PaneID; direction: Direction; step: Double }`, con `static let defaultStep = 0.05`.
  - `func resizing(_ request: ResizeRequest, within geometry: LayoutGeometry) -> LayoutTree`: busca el ancestro más cercano cuyo eje sea `direction.axis` y en el que el panel tenga borde hacia esa dirección (right/down si está en `first`, left/up si está en `second`). Mueve su `ratio` en `+step` (right/down) o `-step` (left/up). Si no hay ancestro, o el resultado no cumple `geometry.fits`, devuelve `self` sin cambios.
  - `func swapping(_ a: PaneID, _ b: PaneID) -> LayoutTree`: intercambia las hojas y conserva los ratios.
  - `func neighbor(of pane: PaneID, toward direction: Direction, in area: Rect, gap: Double) -> PaneID?`: entre los frames que quedan del otro lado del borde del panel (por ejemplo, right: `candidate.minX >= pane.maxX - 0.5`) y que se solapan en el eje perpendicular, elige el de menor distancia entre bordes. Si hay empate, gana el de mayor solape y después el que va antes en `panes`. Si no hay ninguno, devuelve `nil`.

- [ ] **Step 1: Pruebas que fallan:**
  - `resizeRightGrowsFirstChild` (ratio 0,5 → 0,55)
  - `resizeLeftFromSecondChildShrinksFirst`
  - `resizeStopsAtRatioBounds` (0,9 + 0,05 → 0,9)
  - `resizeRefusedWhenNeighborWouldBreakMinimum`: área de 600 de ancho con gap 8, ratio 0,55 → un paso más dejaría el segundo por debajo de 240 → sin cambios (B3).
  - `resizeWithoutMatchingAncestorDoesNothing`
  - `swapExchangesLeavesAndKeepsRatios`
  - `neighborToTheRightInDwindle` (a → b)
  - `neighborDownInStack` (b → c)
  - `neighborLeftFromStackReturnsMaster` (c → a)
  - `noNeighborAtTheEdgeReturnsNil` (a ← nada, B4)
  - `neighborTieBreaksByOverlap`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Pruebas en verde.
- [ ] **Step 5:** Commit `feat(core): add layout tree resize, swap and neighbor`.

### Task 4: Estrategias de layout y catálogo

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Layout/{LayoutStrategy,DwindleLayout,ColumnsLayout,MasterStackLayout,LayoutCatalog}.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/LayoutStrategyTests.swift`

**Interfaces:**
- Consumes: T2.
- Produces:
  - `public struct LayoutID: Hashable, Sendable, RawRepresentable { rawValue: String }`, con `static let dwindle = "dwindle"`, `columns = "columns"` y `master = "master"`.
  - `public protocol LayoutStrategy: Sendable { var id: LayoutID { get }; var displayName: String { get }; var statusName: String { get }; func tree(for panes: [PaneID]) -> LayoutTree? }` (`nil` si `panes` está vacío).
  - `DwindleLayout` (`"Dwindle"`, `"dwindle"`): el primer split es `sideBySide` con `Ratio(1.35 / 2.35)`. Cada panel siguiente divide la última hoja, alternando `stacked`, `sideBySide`…, con `Ratio.half`.
  - `ColumnsLayout` (`"Columnas"`, `"columnas"`): cadena `sideBySide` con `ratio = 1/n` en cada nivel.
  - `MasterStackLayout` (`"Maestro + pila"`, `"maestro"`): con 1 panel, hoja. Con 2 o más, `stacked` con `Ratio(1.15 / 2.15)`; `first` es el maestro y `second` son columnas iguales con el resto.
  - `public struct LayoutCatalog: Sendable { init(_ strategies: [any LayoutStrategy]); static let standard; var all: [any LayoutStrategy]; func strategy(for id: LayoutID) -> (any LayoutStrategy)? }`. `standard` es `[Dwindle, Columns, MasterStack]`, en ese orden.

- [ ] **Step 1: Pruebas que fallan.** Son parametrizadas `@Test(arguments: 1...9)`, con área `Rect(0, 0, 1328, 752).insetBy(10)` y gap 8:
  - `everyStrategyKeepsAllPanesInOrder` (`tree(for:).panes == panes`)
  - `everyStrategyProducesNilForNoPanes`
  - `dwindleWithThreeMatchesMainBoard`: `a | (b / c)`; `a.width ≈ 746.81`, `b.width ≈ 553.19`, `b.height == c.height ≈ 362` (B1).
  - `masterWithThreeMatchesMainBoard`: `a.height ≈ 387.26`, `b.height ≈ 336.74`, `b.width == c.width ≈ 650`.
  - `columnsWithThreeAreEqual` (≈ 430.67 cada una)
  - `dwindleAlternatesAxis` (con 4: `a | (b / (c | d))`)
  - `catalogFindsStrategiesById`
  - `catalogOrderIsDwindleColumnsMaster`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar los tres tipos y el catálogo.
- [ ] **Step 4:** Pruebas en verde.
- [ ] **Step 5:** Commit `feat(core): add dwindle, columns and master-stack layouts`.

### Task 5: `Pane` ampliado y `Workspace`

**Files:**
- Modify: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/{Pane,TerminalEvent,WorkingDirectory}.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Workspace/{WorkspaceID,Workspace}.swift`
- Test: `PaneTests.swift` (ampliar), `WorkingDirectoryTests.swift` (ampliar), `WorkspaceTests.swift`, `WorkspaceInvariantTests.swift`

**Interfaces:**
- Consumes: T2–T4.
- Produces:
  - `TerminalEvent` gana `case foregroundProcessChanged(String)` y `case closeRequested`.
  - `Pane` gana `public private(set) var processName: String?` y `var headerName: String` (`processName ?? title ?? ""`).
  - `WorkingDirectory.abbreviated(home: WorkingDirectory) -> String`: `/Users/s/dev/x` con home `/Users/s` da `~/dev/x`; el propio home da `~`.
  - `var lastComponent: String`.
  - `public struct WorkspaceID: Hashable, Sendable` (UUID, como `PaneID`).
  - `public struct Workspace: Sendable, Equatable`. El `==` es manual y compara `layout.id`. Tiene `id`, `name`, `rootDirectory`, `panes: [Pane]`, `layout: any LayoutStrategy`, `tree: LayoutTree?` y `focusedPane: PaneID?`.
    - `static func empty(name: String, rootDirectory: WorkingDirectory, layout: any LayoutStrategy) -> Workspace`
    - `func adding(_ pane: Pane) -> Workspace`: añade al final, enfoca el panel nuevo y reconstruye `tree`.
    - `func removing(_ pane: PaneID) -> Workspace`: el foco pasa al anterior, o al siguiente si no hay anterior, o a `nil` si queda vacío. Reconstruye `tree`.
    - `func switchingLayout(to layout: any LayoutStrategy) -> Workspace`: reconstruye `tree`.
    - `func focusing(_ pane: PaneID) -> Workspace`
    - `func swapping(_ a: PaneID, _ b: PaneID) -> Workspace`: intercambia en `panes` y en `tree`, y conserva los ratios.
    - `func resizing(_ request: ResizeRequest, within geometry: LayoutGeometry) -> Workspace`
    - `func equalized() -> Workspace`
    - `func applying(_ event: TerminalEvent, to pane: PaneID) -> Workspace`
    - `func contains(_ pane: PaneID) -> Bool`
    - `func index(of pane: PaneID) -> Int?` (1-based)
    - `var directoryForNewPane: WorkingDirectory` (el del panel enfocado o `rootDirectory`)
    - `func renamed(_ name: String) -> Workspace`
    - Un id desconocido deja el workspace igual.

- [ ] **Step 1: Pruebas que fallan:**
  - `paneRecordsForegroundProcess`
  - `headerNameFallsBackToTitle`
  - `abbreviatesHomeWithTilde`
  - `homeItselfIsTilde`
  - `addingFocusesNewPaneAndRebuildsTree`
  - `removingFocusedPaneFocusesPrevious` (Review Focus 2)
  - `removingFirstFocusesNext`
  - `removingLastLeavesEmptyWorkspaceWithoutFocus`
  - `structuralChangeDropsManualRatios` (resize y después add → ratios por defecto)
  - `swapKeepsManualRatios`
  - `newPaneUsesFocusedPaneDirectory`
  - `newPaneFallsBackToRootDirectory`
  - `unknownPaneIsIgnored`
- [ ] **Step 2: Prueba de invariantes (B2)** en `WorkspaceInvariantTests`. Usa un generador congruencial propio con semilla fija `0x5A17`, sin dependencias. Corre 500 operaciones aleatorias (add, remove, swap, switchLayout, resize, equalize, focus) y, tras cada una, comprueba que `Set(tree?.panes ?? []) == Set(panes.map(\.id))`, que `tree?.panes.count == panes.count` y que `focusedPane` está en `panes`, o es `nil` si y solo si `panes` está vacío. Si falla, el mensaje incluye la semilla y el número de paso.
- [ ] **Step 3:** Correr → falla.
- [ ] **Step 4:** Implementar.
- [ ] **Step 5:** Pruebas en verde.
- [ ] **Step 6:** Commit `feat(core): add workspace aggregate with layout invariants`.

### Task 6: `WorkspaceSet`

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Workspace/WorkspaceSet.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/WorkspaceSetTests.swift`

**Interfaces:**
- Consumes: T5.
- Produces: `public struct WorkspaceSet: Sendable, Equatable`, con:
  - `init(first: Workspace)`, `workspaces: [Workspace]`, `activeID: WorkspaceID` y `active: Workspace`.
  - `func adding(_ workspace: Workspace) -> WorkspaceSet` (lo activa).
  - `func activating(_ id: WorkspaceID) -> WorkspaceSet` y `func activating(index: Int) -> WorkspaceSet` (1-based; fuera de rango no hace nada).
  - `func removing(_ id: WorkspaceID) throws(WorkspaceSetError) -> WorkspaceSet` (`.cannotCloseLastWorkspace`). Si se cierra el activo, se activa el anterior, o el siguiente si no hay anterior.
  - `func updating(_ id: WorkspaceID, _ transform: (Workspace) -> Workspace) -> WorkspaceSet`
  - `func workspace(containing pane: PaneID) -> WorkspaceID?`
  - `func paneIndex(of pane: PaneID) -> Int?` (solo en el activo, 1…9; `nil` por encima de 9).

- [ ] **Step 1: Pruebas que fallan:**
  - `addingActivatesNewWorkspace`
  - `activatingByIndexIsOneBased`
  - `activatingOutOfRangeDoesNothing`
  - `closingActiveActivatesPrevious`
  - `closingOnlyWorkspaceThrows`
  - `findsWorkspaceContainingPane`
  - `paneIndexOnlyCountsActiveWorkspace`
  - `paneIndexAboveNineIsNil`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Pruebas en verde.
- [ ] **Step 5:** Commit `feat(core): add workspace set`.

### Task 7: `SmaltiConfig`, atajos, puerto `ConfigStore`, contrato y tokens de F1

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Config/{SmaltiConfig,KeyChord,Keymap,ConfigError}.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/ConfigStore.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/{InMemoryConfigStore,ConfigStoreContract}.swift`
- Move: `Tests/SmaltiCoreTests/Support/FakeTerminalEngine.swift` → `Sources/SmaltiCoreTestSupport/` (público)
- Modify: `Packages/SmaltiCore/Package.swift` (target y producto `SmaltiCoreTestSupport`)
- Modify: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Theme/{Theme,Theme+Obsidian}.swift`
- Test: `SmaltiConfigTests.swift`, `KeyChordTests.swift`, `KeymapTests.swift`, `InMemoryConfigStoreContractTests.swift`, `ObsidianThemeTests.swift` (ampliar)

**Interfaces:**
- Consumes: T4 (`LayoutID`).
- Produces:
  - `public struct KeyChord: Hashable, Sendable { key: String; modifiers: Set<KeyModifier> }`, con `enum KeyModifier { command, option, control, shift }`.
  - `static func parse(_ text: String) throws(KeyChordError) -> KeyChord`. El formato es `"cmd+opt+d"`, `"ctrl+1"`, `"shift+cmd+="`, `"cmd+opt+left"`; las teclas con nombre son `left`, `right`, `up`, `down`, `enter`, `escape` y `tab`.
  - `var display: String` (`"⇧⌥⌘←"`, orden de Apple ⌃⌥⇧⌘) y `var usesOptionAlone: Bool`.
  - `public struct CommandID: Hashable, Sendable, RawRepresentable` (definido aquí; lo usa T8). Las constantes están en la tabla de abajo.
  - `public struct Keymap: Sendable, Equatable`, con `static let standard`, `func command(for chord: KeyChord) -> CommandID?`, `func chord(for command: CommandID) -> KeyChord?` y `func overriding(_ bindings: [KeyChord: CommandID?]) throws(ConfigError) -> Keymap` (`nil` desactiva el atajo).
  - `public struct AppearanceSettings: Equatable, Sendable { accent: RGBAColor; glassOpacity: Double; blur: Double; fontFamily: String; fontSize: Double; gap: Double; radius: Double }`, con `static let obsidian` (los valores del TOML de la spec).
  - `public struct SmaltiConfig: Equatable, Sendable { appearance; defaultLayout: LayoutID; shell: TerminalCommand; keys: Keymap }`, con `static let defaults`.
  - `extension Theme { func applying(_ appearance: AppearanceSettings) -> Theme }`
  - `public struct ConfigError: Error, Equatable, Sendable { file: String; line: Int?; key: String?; reason: String }`, con `var summary: String` (`"config.toml:12 · font_size: se esperaba un número"`).
  - `@MainActor public protocol ConfigStore: AnyObject { func current() -> SmaltiConfig; func reload() throws(ConfigError) -> SmaltiConfig }`. `current()` es la última configuración válida, o `defaults`. `reload()` relee el origen y, si falla, conserva la anterior. **Refinamiento de la firma de la spec** (`current() throws`): con "conservar la última válida", `current()` nunca falla; el error solo sale de `reload()`.
  - `overriding` valida: un atajo con `usesOptionAlone` lanza `ConfigError(file: "", line: nil, key: <atajo>, reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir")` (R8). El adaptador TOML completa `file` y `line`.
  - TestSupport:
    - `public protocol ConfigStoreHarness { @MainActor func makeStore() -> any ConfigStore; func write(_ scenario: ConfigScenario) }`
    - `public enum ConfigScenario { case missing, customShellAndColumns, invalid }`. `customShellAndColumns` equivale a `shell = .custom("/bin/zsh -f")` y `defaultLayout = .columns`.
    - `public enum ConfigStoreContract { @MainActor static func verify(_ harness: some ConfigStoreHarness) throws }`, que cubre tres casos: missing → defaults; valid → valores; valid, después invalid y `reload` → lanza `ConfigError` y `current()` conserva los valores.
    - `InMemoryConfigStore` con su harness.
  - Tokens de F1 en `Theme`, todos copiados de `Main.dc.html` y `Paleta.dc.html`:
    - `StripTokens`: pastilla de alto 26, radio 7, padding 11, gap 6; padding de la franja 16 / 14; texto inactivo `#9aa0ab`; punto 6 en `#565c68`; borde inferior blanco al 0,05.
    - `HeaderTokens`: alto 30, padding 12, gap 8, fuente 11,5, punto 7, directorio `#9aa0ab`, borde inferior 0,05.
    - `KbdTokens`: JetBrains Mono 10,5, padding 2 × 6, radio 5, borde 0,12, texto `#aeb3bd`, fondo 0,04.
    - `StatusBarTokens`: alto 28, padding 16, gap 16, fuente 11, `#8b919c`, borde superior 0,05.
    - `FocusTokens`: anillo con acento al 0x80/255, brillo con acento al 0x22/255, radio de brillo 28.
    - `PaletteTokens`: ancho 640, radio 14, fondo `rgba(20,22,30,0.82)`, desenfoque 36, borde 0,12, campo de 52 a 16 pt, fila de 38 con radio 8, gap 12 y fuente 13,5, grupo de 10,5 con tracking 0,06em y padding 10 / 12 / 4, selección con acento al 0x26/255, pie de 36 con fuente 11,5 y borde 0,07, offset superior 110, opacidad del fondo de paneles 0,45.
    - `MotionTokens`: reacomodo de 0,15 s.

Atajos por defecto (`Keymap.standard`) y sus `CommandID`:

| CommandID | Atajo |
| --- | --- |
| `palette.open` | `cmd+k` |
| `layout.dwindle` / `layout.columns` / `layout.master` | `cmd+opt+d` / `cmd+opt+c` / `cmd+opt+m` |
| `panes.equalize` | `shift+cmd+=` |
| `pane.new` / `pane.close` | `cmd+d` / `cmd+w` |
| `pane.focus.1`…`pane.focus.9` | `cmd+1`…`cmd+9` |
| `pane.focus.left/right/up/down` | `cmd+opt+<flecha>` |
| `pane.swap.left/right/up/down` | `shift+cmd+opt+<flecha>` |
| `pane.resize.left/right/up/down` | `ctrl+cmd+opt+<flecha>` |
| `workspace.1`…`workspace.9` / `workspace.new` | `ctrl+1`…`ctrl+9` / `ctrl+cmd+n` |
| `workspace.rename`, `workspace.close`, `config.reload` | sin atajo (solo ⌘K) |

- [ ] **Step 1: Pruebas que fallan:**
  - `parsesModifiersAndNamedKeys`
  - `rejectsUnknownModifier`
  - `displayUsesAppleOrder` (`shift+cmd+opt+left` → `"⌥⇧⌘←"`)
  - `standardKeymapHasNoOptionOnlyChord` (B11)
  - `overridingRebindsAndUnbinds`
  - `overridingRejectsOptionOnlyChord` (R8)
  - `defaultsMatchObsidianTokens` (accent `#7aa2f7`, glass 0,62, blur 28, fuente "JetBrains Mono" 13, gap 8, radius 11, layout `dwindle`, shell `.loginShell`)
  - `themeApplyingAppearanceChangesAccentAndGap`
  - `inMemoryStoreSatisfiesContract` (llama a `ConfigStoreContract.verify`)
  - Tokens nuevos en `ObsidianThemeTests`.
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar. Mover el fake y actualizar los imports de las pruebas existentes (`import SmaltiCoreTestSupport`). `scripts/mutation/mutate.py` solo muta `Sources/SmaltiCore`: excluye los targets `*TestSupport`, y la exclusión lleva su prueba en `test_mutate.py`, que se ve fallar antes.
- [ ] **Step 4:** `swift test --package-path Packages/SmaltiCore` en verde, guarda incluida.
- [ ] **Step 5:** Commit `feat(core): add config, keymap, config store contract and F1 tokens`.

### Task 8: Comandos, catálogo y búsqueda difusa

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Commands/{Command,CommandCatalog,FuzzyMatch}.swift`
- Test: `CommandCatalogTests.swift`, `FuzzyMatchTests.swift`

**Interfaces:**
- Consumes: T4, T6 y T7.
- Produces:
  - `public enum CommandGroup: String, Sendable { case tiling = "Tiling", panes = "Paneles", workspaces = "Workspaces y sesiones", configuration = "Configuración" }`
  - `public struct Command: Hashable, Sendable { id: CommandID; title: String; subtitle: String?; group: CommandGroup; shortcut: KeyChord?; isCurrent: Bool }`
  - `public enum CommandCatalog { static func commands(for set: WorkspaceSet, keymap: Keymap, layouts: LayoutCatalog) -> [Command] }`
  - `public struct RankedCommand: Hashable, Sendable { command: Command; score: Int }`
  - `public func fuzzyMatch(_ query: String, in commands: [Command]) -> [RankedCommand]`

Textos del catálogo. Los de Tiling son del tablero; el resto son **propuestas que Simón aprueba al revisar este plan**:

| Grupo | Título | Subtítulo | Disponible si |
| --- | --- | --- | --- |
| Tiling | `Layout: Dwindle` | `cada panel nuevo divide el último` | siempre; `isCurrent` si está activo |
| Tiling | `Layout: Columnas` / `Layout: Maestro + pila` | — | siempre |
| Tiling | `Igualar tamaños de paneles` | — | ≥ 2 paneles |
| Paneles | `Nuevo panel` / `Cerrar panel` | — | siempre / ≥ 1 panel |
| Paneles | `Ir al panel N` | proceso del panel | por panel, N ≤ 9 |
| Paneles | `Enfocar / Intercambiar / Agrandar panel hacia la izquierda, derecha, arriba, abajo` | — | ≥ 2 paneles |
| Workspaces y sesiones | `Nuevo workspace`, `Renombrar workspace…`, `Ir a workspace <nombre>` | — | siempre / por workspace no activo |
| Workspaces y sesiones | `Cerrar workspace` | — | ≥ 2 workspaces |
| Configuración | `Recargar configuración` | `~/.config/smalti/config.toml` | siempre |

Puntuación de `fuzzyMatch`: se buscan los caracteres de la consulta como subsecuencia de `title + " " + subtitle`, sin distinguir mayúsculas ni tildes (`folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`). Bonos: +10 por carácter consecutivo, +8 al inicio de una palabra, +15 si el título empieza por la consulta. Penalización: −1 por cada carácter saltado. Si no es subsecuencia, se descarta. Una consulta vacía devuelve todo en el orden del catálogo, y los empates conservan ese orden.

- [ ] **Step 1: Pruebas que fallan:**
  - `layQueryRanksThreeLayoutsFirst` (B7)
  - `queryIgnoresCaseAndAccents` (`"tamanos"` → Igualar)
  - `emptyQueryKeepsCatalogOrder`
  - `nonMatchingQueryReturnsNothing`
  - `currentLayoutIsMarked`
  - `equalizeHiddenWithOnePane`
  - `closeWorkspaceHiddenWithOneWorkspace`
  - `commandsCarryKeymapShortcut` (Columnas → `⌥⌘C`)
  - `paneCommandsStopAtNine`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Pruebas en verde.
- [ ] **Step 5:** Commit `feat(core): add command catalog and fuzzy search`.

### Task 9: Abrir, cerrar y salida de paneles (R1, R4)

**Files:**
- Modify: `Packages/SmaltiCore/Sources/SmaltiCore/Application/{TerminalEngine,OpenPane,HandlePaneExit}.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/ClosePane.swift`
- Modify: `Packages/SmaltiCore/Sources/SmaltiCoreTestSupport/FakeTerminalEngine.swift`
- Modify: `App/Smalti/AppComposition.swift` (solo lo mínimo para que siga compilando con un workspace)
- Test: `OpenPaneTests.swift`, `ClosePaneTests.swift`, `HandlePaneExitTests.swift` (reescritas)

**Interfaces:**
- Consumes: T5 y T6.
- Produces:
  - `TerminalEngine` gana `func show(_ pane: PaneID)` y `func hide(_ pane: PaneID)`. Documenta que `close` libera sin emitir eventos y termina el stream, que `.closeRequested` y `.exited` son peticiones que la app enruta a `ClosePane`, y que el motor puede emitirlas desde dentro de su propia pila de llamadas: el adaptador las aplaza al siguiente ciclo del run loop. El fake registra `shownPanes` y `hiddenPanes`.
  - `public enum ChildEnvironment { static func smalti(version: String) -> [String: String] }` → `["SMALTI": "1", "SMALTI_VERSION": version]`.
  - `public struct OpenPaneRequest: Sendable { shell: TerminalCommand; geometry: LayoutGeometry }`
  - `public enum OpenPaneError: Error, Equatable { case paneTooSmall(minimum: Size); case engine(TerminalEngineError) }`
  - `@MainActor public struct OpenPane { init(engine: any TerminalEngine, environment: [String: String]); func execute(_ request: OpenPaneRequest, in set: inout WorkspaceSet) throws(OpenPaneError) -> PaneID }`. Primero comprueba el mínimo, construyendo el árbol candidato con un `PaneID` provisional; después abre en `active.directoryForNewPane` con el `environment` mezclado en la spec, y por último añade el panel.
  - `public enum ClosePaneOutcome: Equatable { case closed, alreadyClosed }`
  - `@MainActor public struct ClosePane { init(engine:); func execute(_ pane: PaneID, in set: inout WorkspaceSet) -> ClosePaneOutcome }`. Busca en todos los workspaces. Es idempotente: si el panel no existe, devuelve `.alreadyClosed` y no llama al motor.
  - `public struct PaneExit: Sendable { pane: PaneID; exitCode: Int?; lifetime: Duration }`
  - `public enum PaneExitOutcome: Equatable { case closed, closedAfterFailedStart(exitCode: Int?), alreadyClosed }`
  - `@MainActor public struct HandlePaneExit { init(engine:); static let minimumHealthyLifetime: Duration = .milliseconds(250); func execute(_ exit: PaneExit, in set: inout WorkspaceSet) -> PaneExitOutcome }`, que usa `ClosePane`.

- [ ] **Step 1: Pruebas que fallan:**
  - `openPassesSmaltiEnvironment` (R1, B13)
  - `openKeepsSpecEnvironmentAndAddsSmalti`
  - `openUsesFocusedPaneDirectory`
  - `openRefusesWhenMinimumWouldBreak` (sin llamar al motor)
  - `openPropagatesEngineFailure`
  - `closeRemovesPaneAndClosesEngine`
  - `closingTwiceClosesEngineOnce` (B15)
  - `closingLastPaneKeepsEmptyWorkspace`
  - `closeFindsPaneInHiddenWorkspace`
  - `healthyExitClosesPane`
  - `exitRightAfterStartIsReported`
  - `exactlyMinimumLifetimeIsHealthy`
  - `exitOfAlreadyClosedPaneIsIgnored`
  - `exitInHiddenWorkspaceLeavesActiveUntouched` (Review Focus 1)
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar. En `AppComposition`, crear un `WorkspaceSet` con un workspace y llamar a la nueva `OpenPane`, sin más cambios de UI. Mientras tanto, `GhosttyTerminalEngine` implementa `show` y `hide` vacíos con `// T13`.
- [ ] **Step 4:** `swift test --package-path Packages/SmaltiCore` en verde, y además `swift test --package-path Packages/GhosttyAdapter` y `xcodebuild … build` compilan.
- [ ] **Step 5:** Commit `feat(core): open, close and exit panes across workspaces`.

### Task 10: Casos de uso de distribución y workspaces

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/{ArrangePanes,WorkspaceCommands}.swift`
- Test: `ArrangePanesTests.swift`, `WorkspaceCommandsTests.swift`

**Interfaces:**
- Consumes: T3–T9.
- Produces, cada uno como `@MainActor public struct` con `execute(…, in set: inout WorkspaceSet)`:
  - `FocusPane`: `execute(_ target: FocusTarget, geometry: LayoutGeometry, in:)`, con `enum FocusTarget { case direction(Direction), index(Int) }`. Sin vecino o con un índice fuera de rango, no hace nada.
  - `SwapPane`: `execute(toward: Direction, geometry:, in:)` (con el vecino).
  - `ResizePane`: `execute(toward: Direction, geometry:, in:)` con `ResizeRequest.defaultStep`.
  - `EqualizePanes` y `SwitchLayout` (`execute(to: any LayoutStrategy, in:)`).
  - `CreateWorkspace(engine:environment:)`: `execute(_ request: CreateWorkspaceRequest, in:) throws(OpenPaneError) -> WorkspaceID`, con `struct CreateWorkspaceRequest { pane: OpenPaneRequest; layout: any LayoutStrategy }` (el layout por defecto del config). La raíz es `active.directoryForNewPane` y el nombre `root.lastComponent`. Abre un panel y llama a `hide` para los paneles del workspace anterior.
  - `RenameWorkspace`: un nombre vacío o de solo espacios no cambia nada; se recortan los espacios.
  - `SwitchWorkspace(engine:)`: `execute(_ target: WorkspaceTarget, in:)`, con `enum WorkspaceTarget { case id(WorkspaceID), index(Int) }`. Llama a `hide` para los paneles del saliente y a `show` para los del entrante (R7).
  - `CloseWorkspace(engine:)`: `execute(_ id:, in:) throws(WorkspaceSetError)`. Cierra todos sus paneles en el motor; si era el activo, llama a `show` para los del nuevo activo.

- [ ] **Step 1: Pruebas que fallan:**
  - `focusByDirectionMovesToNeighbor`
  - `focusWithoutNeighborDoesNothing`
  - `focusByIndexIsOneBased`
  - `swapWithRightNeighbor`
  - `resizeStepsFivePercent`
  - `switchLayoutRebuildsTree`
  - `createWorkspaceOpensPaneAndHidesPrevious`
  - `createWorkspaceNamesAfterRootDirectory`
  - `renameTrimsAndIgnoresBlank`
  - `switchHidesOutgoingAndShowsIncoming`
  - `switchToActiveDoesNotHideOrShow`
  - `closeWorkspaceClosesItsPanes`
  - `closeLastWorkspaceThrows`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Pruebas en verde.
- [ ] **Step 5:** Commit `feat(core): add arrange and workspace use cases`.

### Task 11: `ReloadConfig` y `SearchCommands`

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/{ReloadConfig,SearchCommands}.swift`
- Test: `ReloadConfigTests.swift`, `SearchCommandsTests.swift`

**Interfaces:**
- Consumes: T7 y T8.
- Produces:
  - `public struct ConfigReload: Equatable { config: SmaltiConfig; error: ConfigError? }`
  - `@MainActor public struct ReloadConfig { init(store: any ConfigStore); func execute() -> ConfigReload }`. Si falla, devuelve `store.current()` junto con el error.
  - `@MainActor public struct SearchCommands { init(layouts: LayoutCatalog); func execute(_ query: String, set: WorkspaceSet, keymap: Keymap) -> [RankedCommand] }`

- [ ] **Step 1: Pruebas que fallan:**
  - `reloadReturnsNewConfig`
  - `failedReloadKeepsPreviousAndReportsError` (B6)
  - `searchUsesCurrentState`
- [ ] **Step 2:** Correr → falla.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Pruebas en verde. Después, mutación de control: `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore` → puntuación ≥ 80 %. Cada sobreviviente se arregla con una prueba nueva antes de seguir.
- [ ] **Step 5:** Commit `feat(core): add reload config and command search`.

### Task 12: `TOMLConfigAdapter`

**Files:**
- Create: `Packages/TOMLConfigAdapter/Package.swift` (depende de `../SmaltiCore` y de la librería TOML; el target de producción usa `SmaltiCore` y la librería TOML, y solo el test target usa `SmaltiCoreTestSupport`)
- Create: `Packages/TOMLConfigAdapter/Sources/TOMLConfigAdapter/{TOMLConfigStore,TOMLConfigParser,TOMLKeyLocator}.swift`
- Create: `Packages/TOMLConfigAdapter/Tests/TOMLConfigAdapterTests/{TOMLConfigParserTests,TOMLConfigStoreContractTests,TOMLAdapterGuardTests}.swift` y `Fixtures/*.toml`
- Modify: `App/Smalti.xcodeproj` (dependencia de paquete local), `CLAUDE.md` (comando de prueba del adaptador)

**Interfaces:**
- Consumes: T7.
- Produces:
  - `@MainActor public final class TOMLConfigStore: ConfigStore { public init(file: URL) }`. Si el archivo no existe, usa `defaults`.
  - `enum TOMLConfigParser { static func parse(_ text: String, file: String) throws(ConfigError) -> SmaltiConfig }`
  - `enum TOMLKeyLocator { static func line(of key: String, inTable table: String, text: String) -> Int? }`: busca `key =` dentro de la sección `[table]` del texto crudo. Da la línea de los errores semánticos aunque la librería no la informe.

Elección de la librería (Step 1). Primera candidata: **TOMLDecoder** (`dduan/TOMLDecoder`), porque es Swift puro y no necesita interoperabilidad con C++. Respaldo: **TOMLKit** (`LebJe/TOMLKit`). Se acepta la primera que cumpla tres condiciones: compila con Swift 6 y concurrencia estricta sin avisos, sus errores de sintaxis dan la línea, y la versión se fija con `exact:` en el último tag que tenga al menos 2 semanas (`git ls-remote --tags`). La elección y su porqué van al mensaje del commit.

Reglas del parser:
- Las claves y tablas son las del TOML de la spec.
- Una clave o tabla desconocida es un error con su línea.
- `default_layout` debe existir en `LayoutCatalog.standard`.
- `accent` debe tener la forma `#rrggbb`.
- `glass_opacity` debe estar en 0,3–0,95 y `blur` en 0–48 (rangos de `Main.dc.html`).
- `shell.command`: `"login"` equivale a `.loginShell`; cualquier otro texto no vacío, a `.custom`.
- `[keys]`: `"cmd+k" = "palette.open"`; `"none"` desactiva el atajo; los `CommandID` desconocidos son error. Se aplica con `Keymap.standard.overriding`, que rechaza ⌥ solo.

- [ ] **Step 1:** Spike de la librería según el criterio anterior. Anotar versión y motivo.
- [ ] **Step 2: Pruebas que fallan:**
  - `missingFileGivesDefaults`
  - `fullDefaultFileRoundTripsToDefaults` (fixture con el TOML de la spec)
  - `customShellIsParsed`
  - `loginShellKeywordIsLoginShell`
  - `syntaxErrorReportsLine`
  - `unknownKeyIsReportedWithLine` (Review Focus 4)
  - `wrongTypeIsReportedWithLine`
  - `unknownLayoutIsReportedWithLine`
  - `optionOnlyShortcutIsRejectedWithLine` (R8)
  - `unbindWithNone`
  - `tomlStoreSatisfiesContract` (`ConfigStoreContract.verify` con un harness que escribe en un directorio temporal)
  - `onlyThisAdapterImportsTheTOMLLibrary` (R10: recorre `Packages/*/Sources` y `App/`. `ImportScanner` se mueve de `SmaltiCoreTests/Architecture` a `SmaltiCoreTestSupport` como API pública y lo usan las dos guardas, sin copiarlo)
- [ ] **Step 3:** Correr → falla.
- [ ] **Step 4:** Implementar.
- [ ] **Step 5:** `swift test --package-path Packages/TOMLConfigAdapter` en verde. Añadir el paquete al proyecto de Xcode y comprobar que `xcodebuild … build` compila.
- [ ] **Step 6:** Commit `feat(config): add TOML config store`.

### Task 13: `GhosttyAdapter` para F1 (R3, R4, R6, R7)

**Files:**
- Modify: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{GhosttyConfigText,GhosttyTerminalEngine,GhosttySurfaceView,GhosttyRuntime,GhosttyActionMapper}.swift`
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{ForegroundProcess,ProcessNameTracker}.swift`
- Test: `GhosttyConfigTextTests.swift`, `ProcessNameTrackerTests.swift`, `ForegroundProcessTests.swift`, `SurfaceLifetimeTests.swift`, `OcclusionTests.swift`

**Interfaces:**
- Consumes: T5 (eventos) y T9 (`show`, `hide`, contrato de `close`).
- Produces:
  - `GhosttyConfigText.render` empieza con `keybind = clear` y añade `keybind = super+c=copy_to_clipboard` y `keybind = super+v=paste_from_clipboard` (R6).
  - `enum ForegroundProcess { static func name(ofProcessGroup pid: pid_t) -> String? }` usa `proc_name` y devuelve `nil` si falla o si `pid <= 0`.
  - `struct ProcessNameTracker { mutating func observe(_ name: String?) -> TerminalEvent? }` solo emite si el nombre cambia y no es `nil`. Se puede probar sin libghostty.
  - `GhosttySurfaceView` consulta `ghostty_surface_foreground_pid` tras `titleChanged` y `commandFinished`, y con un `Timer` de 1 s que solo corre mientras la superficie está visible.
  - `close_surface_cb`: si `ghostty_surface_process_exited`, entrega `.exited(code: últimoCódigoDe SHOW_CHILD_EXITED)`; si no, `.closeRequested`. En los dos casos se aplaza con `DispatchQueue.main.async`. Se elimina `onCloseRequested → engine.close`.
  - `GhosttyTerminalEngine.close` libera la superficie sin emitir `.exited` y termina el stream.
  - `show` y `hide` llaman a `ghostty_surface_set_occlusion(surface, visible)`, arrancan o paran el sondeo y guardan `isVisible` (observable en pruebas).
  - `GhosttyRuntime.apply(_ appearance: TerminalAppearance) throws(TerminalEngineError)` regenera el archivo de configuración y llama a `ghostty_app_update_config`. Lo usa "Recargar configuración" desde el composition root; no forma parte del puerto. Prueba: `applyingAppearanceReloadsWithoutDiagnostics`.

- [ ] **Step 1: Pruebas que fallan:**
  - `configStartsWithKeybindClear`
  - `configRebindsOnlyCopyAndPaste` (B16)
  - `trackerEmitsOnlyOnChange`
  - `trackerIgnoresUnknownName`
  - `nameOfOwnProcessGroupIsKnown` (`getpgrp()` del proceso de pruebas → no `nil`)
  - `nameOfInvalidPidIsNil`
  - `closeEmitsNoExitedEvent`
  - `closeSurfaceWithLiveProcessRequestsClose`
  - `hideMarksSurfaceOccluded`
  - `showMarksSurfaceVisible`
  - La configuración generada pasa por `GhosttyConfig.load` sin diagnósticos.
- [ ] **Step 2:** Correr `swift test --package-path Packages/GhosttyAdapter` → falla.
- [ ] **Step 3:** Implementar. Los callbacks se crean en funciones `nonisolated` (hallazgo de F0).
- [ ] **Step 4:** Pruebas en verde y `xcodebuild … build` compila.
- [ ] **Step 5:** Commit `feat(ghostty): process names, occlusion, single close path and own keybinds`.

### Task 14: Composition root y rejilla de paneles *(directo, necesita pantalla)*

**Files:**
- Modify: `App/Smalti/AppComposition.swift`
- Create: `App/Smalti/{TilingController,PaneGridView,LaunchOptions}.swift`
- Modify: `App/Smalti/{PaneContainerView,SmaltiWindow}.swift`

**Interfaces:**
- Consumes: T9–T13.
- Produces:
  - `struct LaunchOptions { configFile: URL; shellOverride: TerminalCommand? }`, leído de `-SmaltiConfigPath` y `-SmaltiShellCommand` (`UserDefaults` del dominio de argumentos). Por defecto, `~/.config/smalti/config.toml`. Precedencia: defaults < TOML < override (R2).
  - `@MainActor final class TilingController`: adaptador primario. Guarda el `WorkspaceSet`, ejecuta casos de uso por `CommandID` (`func perform(_ command: CommandID)`), enruta los eventos de cada panel (`.closeRequested` y `.exited` van a `HandlePaneExit`; el resto, a `Workspace.applying`) y avisa a las vistas con `onChange: (WorkspaceSet, StatusMessage?) -> Void`. No contiene reglas de negocio.
  - `final class PaneGridView: NSView`: `isFlipped = true`. Coloca un `PaneContainerView` por panel según `frames(in: bounds.insetBy(areaPadding), gap:)`. Los paneles de workspaces ocultos se quitan de la vista sin destruirse. Anima solo el marco, en 150 ms con `NSAnimationContext`, y sin animación si `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` está activo. El contenido Metal no se anima. El panel enfocado lleva anillo y brillo de `FocusTokens`. El primer responder es la superficie del panel enfocado. Un clic en un panel lo enfoca (`FocusPane` por índice). Arrastrar el separador, que la spec marca como opcional, queda fuera de F1 salvo que Simón lo pida en el uso real.
  - El shell que muere al arrancar ya no abre un `NSAlert`: el mensaje va a la barra de estado. El estado vacío de un workspace se acuerda con Simón antes de dibujarlo, porque el tablero no lo cubre.
- [ ] **Step 1:** Prueba que falla: `LaunchOptionsTests`, en un test target `SmaltiTests` (unit tests de la app) si no existe; si no se puede crear sin tocar mucho el `.pbxproj`, va en E2E en T17. Cubre `overrideWinsOverConfig` y `configPathArgumentIsHonoured`.
- [ ] **Step 2:** Implementar. Como `⌘D` llega en T15, la verificación visual con 1, 3 y 9 paneles en los 3 layouts usa el argumento temporal `-SmaltiDebugPanes <n>` (solo en Debug), que se borra en T15.
- [ ] **Step 3:** `xcodebuild … build`, abrir con `-SmaltiShellCommand "/bin/zsh -f"`, y el anterior más `scripts/test-ui.sh MainWindowTests TerminalPaneTests` en verde.
- [ ] **Step 4:** Commit `feat(app): tile panes from the workspace set`.

### Task 15: `KeyRouter`, franja, cabecera y barra de estado *(directo)*

**Files:**
- Create: `App/Smalti/{KeyRouter,WorkspaceStripView,PaneHeaderView,StatusBarView,KbdView}.swift`, `App/Smalti/Fonts/Inter*.ttf` (OFL, con su licencia), `Info.plist` `ATSApplicationFontsPath`
- Modify: `App/Smalti/{SmaltiWindow,DragStripView,PaneContainerView}.swift`

**Interfaces:**
- Produces:
  - `struct KeyChordTranslator { static func chord(from event: NSEvent) -> KeyChord? }`: modificadores (⇧ incluido) más `charactersIgnoringModifiers` en minúsculas, y las flechas por `keyCode`.
  - `KeyRouter`: en `performKeyEquivalent` y `keyDown` del panel, si `keymap.command(for:)` existe, llama a `controller.perform` y se come la tecla; si no, la tecla sigue intacta hacia la superficie.
  - `WorkspaceStripView`, `PaneHeaderView` (`headerName`, `abbreviated(home:)`, `⌘N` con `KbdView`) y `StatusBarView` (`"<workspace> · N paneles · <statusName>"` o el `StatusMessage` de error), todos con `Theme` como única fuente. Se empaqueta Inter 400/500/600 desde el release oficial de `rsms/inter`.
- [ ] **Step 1: Pruebas que fallan** en unit tests de la app (o en GhosttyAdapter si el traductor se separa):
  - `shiftedCharacterMatchesShiftedChord` (Review Focus 5)
  - `optionCharacterPassesThrough`
  - `arrowsUseKeyCode`
- [ ] **Step 2:** Implementar. Quitar `-SmaltiDebugPanes`.
- [ ] **Step 3:** Verificación visual frente a `Main.dc.html` con 3 paneles en los 3 layouts.
- [ ] **Step 4:** Commit `feat(app): key router, workspace strip, pane headers and status bar`.

### Task 16: Paleta ⌘K *(directo)*

**Files:**
- Create: `App/Smalti/{CommandPaletteController,CommandPaletteView,CommandRowView,LayoutIcons}.swift`

**Interfaces:**
- Consumes: `SearchCommands` (T11) y `TilingController.perform`.
- Produces: un panel hijo de la ventana, centrado y a 110 pt del borde superior, con los tokens de `PaletteTokens`. Mientras está abierto, los paneles quedan al 0,45. La navegación es ↑↓ ↵ esc, con selección inicial en la primera fila y grupos en mayúsculas. Lleva los iconos SVG de layouts del tablero como `NSBezierPath`, "actual" en acento para el layout activo y `Renombrar workspace…` en modo de texto en el mismo campo. El pie dice `↑↓ navegar`, `↵ ejecutar` y `Todo lo que hacen los botones vive aquí`. **Desviación:** sin `⌘↵ en panel nuevo`, porque en F1 no hay comandos que se ejecuten en un panel. Se justifica en el PR. La apertura se mide con `os_signpost` (`palette.open`), con un objetivo de ≤ 50 ms (B7).
- [ ] **Step 1:** E2E `CommandPaletteTests` que falla: `testPaletteFiltersLayoutsAndSwitches` (⌘K, escribir `col`, ↵ → barra de estado `· columnas`) y `testEscapeClosesPalette`.
- [ ] **Step 2:** Implementar.
- [ ] **Step 3:** `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh CommandPaletteTests` en verde.
- [ ] **Step 4:** Commit `feat(app): command palette`.

### Task 17: UI tests de F1 (R1, R2, R9, B13–B17) *(directo, toma el teclado)*

**Files:**
- Modify: `App/SmaltiUITests/IsolatedApp.swift` (añade `-SmaltiConfigPath` a un fixture temporal vacío)
- Create: `App/SmaltiUITests/{PasteboardGuard,TilingTests,WorkspaceTests,ChildEnvironmentTests}.swift`
- Modify: `App/SmaltiUITests/TerminalPaneTests.swift` (usa `PasteboardGuard`)

**Interfaces:**
- Produces: `final class PasteboardGuard` guarda todos los `pasteboardItems` con todos sus tipos y datos en `setUp`, y los restaura en `tearDown`, aunque la prueba falle (R9, B17).
- [ ] **Step 1:** Pruebas:
  - `testNewPaneSplitsAndShowsThreePanes`
  - `testClosingFocusedPaneMovesKeyboardFocus` (Review Focus 2)
  - `testExitClosesOnlyThatPane`
  - `testLastPaneLeavesWindowOpen` (B15)
  - `testEachPaneSeesSmaltiVariable`: 2 paneles, `echo $SMALTI` → `1` en ambos, y `tmux list-clients` igual antes y después (B13). Recuerda: las pruebas no teclean espacios (hallazgo de F0), así que se usa `printenv`, Tab o similar.
  - `testHeaderShowsForegroundProcess` (`sleep` y luego `zsh`, B14)
  - `testCmdKOpensPaletteNotClearScreen` (B16)
  - `testWorkspaceSwitchKeepsProcessesAlive` (versión automática de B9 con un archivo marcador)
- [ ] **Step 2:** `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh TilingTests WorkspaceTests ChildEnvironmentTests TerminalPaneTests` → todo en verde, con el código de salida comprobado.
- [ ] **Step 3:** Commit `test(app): F1 tiling, workspace and environment UI tests`.

### Task 18: Mediciones, capturas y cierre de fase *(directo)*

**Files:**
- Create: `docs/specs/F1-checklist.md`, `docs/specs/F1-assets/`
- Modify: `progress.md`, `docs/ROADMAP.md`, tarjeta del KB de smalti

- [ ] **Step 1:** B8: (a), (b) y (c) con Instruments (Hangs / Time Profiler) y Monitor de Actividad, comparados con Ghostty.app con 9 splits. Tabla y trazas en el checklist.
- [ ] **Step 2:** B10: capturas de 3 paneles en los 3 layouts y de la paleta, superpuestas a los tableros. Las diferencias se justifican.
- [ ] **Step 3:** B9 y B11: lista manual para Simón (caracteres ⌥ del layout Latin American, `sleep 30; say listo` con otro workspace visible).
- [ ] **Step 4:** Revisión final de la rama con un revisor nuevo. Cada hallazgo se corrige con su prueba RED→GREEN.
- [ ] **Step 5:** Mutación de `SmaltiCore` ≥ 80 % y todas las suites en verde (`SmaltiCore`, `GhosttyAdapter`, `TOMLConfigAdapter`, las UI tests afectadas y `swift format lint`).
- [ ] **Step 6:** PR `feature/f1-tiling` → `develop`, y después PR `develop` → `main`. Simón confirma cada merge.

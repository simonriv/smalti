# F0 · Spike del motor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** una app macOS con ventana de vidrio sin botones y un panel libghostty con zsh, que se sienta igual que Ghostty.app, sobre un esqueleto hexagonal que aísla el motor tras `TerminalEngine`.

**Architecture:** el paquete SwiftPM `SmaltiCore` (Swift puro: dominio, puerto `TerminalEngine` y caso de uso `OpenPane`) no sabe nada de Ghostty. El paquete `GhosttyAdapter` es el único que enlaza `GhosttyKit.xcframework`, construido desde el submódulo `vendor/ghostty` fijado a v1.4.0. La app de Xcode (`App/Smalti.xcodeproj`) es el composition root y aporta la ventana AppKit.

**Tech Stack:** Swift 6.4 (Xcode 27.2), AppKit, Swift Testing, XCUITest, libghostty (Ghostty v1.4.0, Zig ≥ 0.17.0), Muter.

**Spec:** `docs/specs/F0-spike.md` · Convenciones: `CLAUDE.md` · Diseño: `docs/design/README.md`, `docs/design/Main.dc.html`

## Global Constraints

- Ghostty fijado a `83fb95624b0439ee660c2679b43b38c8b63769cd` (tag `v1.4.0`). El SHA del submódulo es el único lugar donde se fija.
- `minimum_zig_version = 0.17.0`; se usa Zig de Homebrew (0.17.1).
- macOS 27 como mínimo. Bundle ID `dev.simonriv.smalti`. Firma ad hoc (`CODE_SIGN_IDENTITY = "-"`), sin sandbox ni hardened runtime.
- `SmaltiCore` solo importa `Foundation` (tipos de valor). Prohibido: AppKit, SwiftUI, Combine, GhosttyKit, Darwin/C.
- Solo `GhosttyAdapter` importa `GhosttyKit`. Nunca se llama a `ghostty_config_load_default_files`, `ghostty_config_load_cli_args` ni `ghostty_config_load_recursive_files`.
- ⌥ no actúa como Meta (`macos-option-as-alt = false`).
- Tokens visuales: un único `Theme.obsidian` en `SmaltiCore`, con valores de `docs/design/README.md`. No hay literales de color o medida en las vistas.
- Swift 6 con concurrencia estricta. Errores con `throws(Tipo)`. Sin `!`, `try!` ni `unsafe*` sin un comentario de justificación. Todo lo inseguro vive solo en `GhosttyAdapter`.
- Identificadores, archivos y commits en inglés (Conventional Commits). Docs en español.
- Rama de trabajo `feature/f0-spike` desde `develop`; al final, PR a `develop` (merge de Simón).

## Review Focus

1. **Teclas muertas e IME:** `´` + `a` → `á` y `¨` + `u` → `ü` deben componer como en TextEdit, con el texto marcado visible mientras se compone (Task 7, paso de verificación A11).
2. **El shell termina** (`exit` o ⌃D): el panel registra `exited` y la ventana se cierra sin cuelgues; con la última ventana cerrada, la app termina (Task 3: prueba de `Pane`; Task 7: verificación).
3. **Ventana diminuta o redimensionada a 0:** nunca se envía un tamaño de 0 px a `ghostty_surface_set_size`; mínimo de ventana 480 × 300 pt (Task 5: prueba de `SurfaceSizing`).
4. **La configuración generada no es válida para v1.4.0** (clave renombrada): error visible con los diagnósticos, nunca un fallo silencioso con valores por defecto (Task 5: prueba de `GhosttyConfigLoader`).
5. **Cambio de pantalla o de escala** (Retina ↔ externa): el texto sigue nítido porque se actualiza la escala de contenido (Task 7: verificación manual con monitor externo o cambio de resolución).

---

### Task 1: Esqueleto del repo, `SmaltiCore` y prueba de guarda de imports

**Files:**
- Create: `Packages/SmaltiCore/Package.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/PaneID.swift`
- Create: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Architecture/ImportGuardTests.swift`
- Create: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Architecture/ImportScanner.swift`
- Create: `.swift-format`
- Modify: `.gitignore` (añadir `Packages/GhosttyAdapter/Frameworks/`)

**Interfaces:**
- Produces: paquete `SmaltiCore` (`// swift-tools-version: 6.2`, `platforms: [.macOS("27.0")]`, sin dependencias); `public struct PaneID: Hashable, Sendable, CustomStringConvertible` con `init()` (UUID) e `init(rawValue: UUID)`.
- Produces (tests): `func forbiddenImports(in source: String, file: String) -> [ImportViolation]`, con `ImportViolation(file: String, line: Int, module: String)`.

- [ ] **Step 1:** Comprobar que estás en `feature/f0-spike` (creada desde `develop` junto con este plan): `git branch --show-current`.
- [ ] **Step 2: Pruebas que fallan** en `ImportGuardTests.swift`:
  - `scannerFlagsForbiddenModule`: `forbiddenImports(in: "import Foundation\nimport AppKit\n", file: "X.swift") == [ImportViolation(file: "X.swift", line: 2, module: "AppKit")]`.
  - `scannerIgnoresCommentsAndAllowedModules`: `"// import AppKit\nimport Foundation"` → `[]`.
  - `scannerFlagsAttributedImports`: `"@preconcurrency import GhosttyKit"` → un `ImportViolation` con `module == "GhosttyKit"`.
  - `coreSourcesHaveNoForbiddenImports`: recorre `Sources/SmaltiCore` (ruta desde `#filePath`) y espera `[]`. Si falla, el mensaje lista `file:line module`.
  - Lista prohibida: `AppKit`, `SwiftUI`, `Combine`, `GhosttyKit`, `Darwin`, `Cocoa`, `CoreGraphics`, `Metal`, `QuartzCore`. Se detecta cualquier `import` que no sea `Foundation`, `Testing` o `SmaltiCore`, con o sin atributos o `@testable`.
- [ ] **Step 3:** `swift test --package-path Packages/SmaltiCore` → falla (no existe `forbiddenImports`).
- [ ] **Step 4:** Implementar `ImportScanner.swift`: un regex por línea `^\s*(@\w+\s+)*import\s+(\w+)`, ignorando las líneas que empiezan por `//`. Crear `PaneID.swift`.
- [ ] **Step 5:** `swift test --package-path Packages/SmaltiCore` → `Test run with 4 tests passed`.
- [ ] **Step 6:** Crear `.swift-format` (indentación 4, ancho 120, `"rules": {"NeverForceUnwrap": true, "NeverUseForceTry": true, "AllPublicDeclarationsHaveDocumentation": false}`). `swift format lint --strict --recursive Packages` → sin salida, código 0.
- [ ] **Step 7:** Commit `chore(core): scaffold SmaltiCore package with import guard`.

### Task 2: Dominio del panel y tema Obsidiana

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/WorkingDirectory.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/TerminalSessionSpec.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/TerminalEvent.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Pane.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Theme/RGBAColor.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Theme/Theme.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Domain/Theme/Theme+Obsidian.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Domain/{WorkingDirectoryTests,PaneTests,ObsidianThemeTests}.swift`

**Interfaces:**
- Produces:
  - `public struct WorkingDirectory: Hashable, Sendable`: `init(path: String) throws(WorkingDirectoryError)` y `let path: String`. `WorkingDirectoryError.notAbsolute(path: String)`.
  - `public enum TerminalCommand: Hashable, Sendable { case loginShell; case custom(String) }`
  - `public struct TerminalSessionSpec: Hashable, Sendable { workingDirectory: WorkingDirectory; command: TerminalCommand; environment: [String: String] }` y `static func loginShell(in: WorkingDirectory) -> TerminalSessionSpec`.
  - `public enum TerminalEvent: Equatable, Sendable { case titleChanged(String); case workingDirectoryChanged(WorkingDirectory); case commandFinished(exitCode: Int?, duration: Duration); case bell; case exited(code: Int?) }`
  - `public struct CommandOutcome: Equatable, Sendable { exitCode: Int?; duration: Duration }`
  - `public struct Pane: Equatable, Sendable { id: PaneID; title: String?; workingDirectory: WorkingDirectory; lastCommand: CommandOutcome?; isRunning: Bool }`, con `init(id:workingDirectory:)` y `func applying(_ event: TerminalEvent) -> Pane`.
  - `public struct RGBAColor: Equatable, Sendable { red, green, blue: UInt8; alpha: Double }`, con `init(hex: String) throws(ColorError)` (`#rrggbb`, alfa 1).
  - `public struct Theme: Equatable, Sendable { name; window: WindowTokens; panel: PanelTokens; chrome: ChromeTokens; text: TextTokens; accent: RGBAColor; terminal: TerminalAppearance }`
    - `WindowTokens { background: RGBAColor; blurRadius: Double; border: RGBAColor; cornerRadius: Double }`
    - `PanelTokens { background; border; cornerRadius; gap; areaPadding }`
    - `ChromeTokens { topStripHeight }`
    - `TextTokens { primary; title; secondary }`
    - `TerminalAppearance { fontFamily: String; fontSize: Double; lineHeight: Double; foreground: RGBAColor; cursor: RGBAColor; palette: [RGBAColor]; paddingX: Double; paddingY: Double }`
  - `extension Theme { static let obsidian: Theme }`

- [ ] **Step 1: Pruebas que fallan**
  - `WorkingDirectoryTests`: `"/tmp"` es válido; `"tmp"` y `""` lanzan `.notAbsolute`; `"/Users/x/"` normaliza a `"/Users/x"`; `"/"` queda como `"/"`.
  - `PaneTests` (un concepto por prueba):
    - `.titleChanged("claude")` → `title == "claude"`.
    - `.workingDirectoryChanged(/tmp)` actualiza `workingDirectory`.
    - `.commandFinished(exitCode: 1, duration: .milliseconds(400))` → `lastCommand == CommandOutcome(exitCode: 1, duration: .milliseconds(400))`.
    - `.exited(code: 0)` → `isRunning == false`.
    - `.bell` devuelve un `Pane` igual al original.
    - Un panel nuevo tiene `isRunning == true` y `title == nil`.
  - `ObsidianThemeTests`:
    - `window.background == RGBAColor(13,15,21, alpha: 0.62)`, `blurRadius == 28`, `border == (255,255,255, 0.09)`, `cornerRadius == 16`.
    - `panel.background == (6,7,10, 0.34)`, `panel.border == (255,255,255, 0.07)`, `cornerRadius == 11`, `gap == 8`, `areaPadding == 10`.
    - `chrome.topStripHeight == 40`.
    - `text.primary == #d7dae0`, `title == #e6e9ef`, `secondary == #8b919c`, `accent == #7aa2f7`.
    - `terminal.fontFamily == "JetBrains Mono"`, `fontSize == 13`, `lineHeight == 1.62`, `foreground == #d7dae0`, `cursor == accent`, `paddingX == 16`, `paddingY == 12` (padding del panel en `Main.dc.html`).
    - `terminal.palette` es exactamente: `#15161e #f7768e #9ece6a #e0af68 #7aa2f7 #bb9af7 #7dcfff #a9b1d6 #414868 #ff99ad #b9f27c #ffc777 #a3bdfa #d3b8ff #a4e3ff #c0caf5` (paleta ANSI de `Apariencia.dc.html`).
  - `RGBAColor(hex: "#7aa2f7")` → `(122,162,247,1)`; `"7aa2f7"` y `"#zzzzzz"` lanzan error.
- [ ] **Step 2:** `swift test --package-path Packages/SmaltiCore` → falla al compilar.
- [ ] **Step 3:** Implementar los tipos. `Theme+Obsidian.swift` es el **único** archivo con literales de tokens. En un literal estático, el `try!` de `RGBAColor(hex:)` se justifica con un comentario (valor constante verificado por prueba), o se usa el inicializador por componentes.
- [ ] **Step 4:** `swift test --package-path Packages/SmaltiCore` → todo en verde, incluida la guarda de imports.
- [ ] **Step 5:** Commit `feat(core): add pane domain, terminal events and obsidian theme`.

### Task 3: Puerto `TerminalEngine`, `OpenPane` y `FakeTerminalEngine`

**Files:**
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/TerminalEngine.swift`
- Create: `Packages/SmaltiCore/Sources/SmaltiCore/Application/OpenPane.swift`
- Create: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Support/FakeTerminalEngine.swift`
- Test: `Packages/SmaltiCore/Tests/SmaltiCoreTests/Application/OpenPaneTests.swift`

**Interfaces:**
- Consumes: `PaneID`, `TerminalSessionSpec`, `TerminalEvent` y `Pane` (Task 2).
- Produces:
  ```swift
  @MainActor public protocol TerminalEngine: AnyObject {
      func open(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> PaneID
      func close(_ pane: PaneID)
      func events(for pane: PaneID) -> AsyncStream<TerminalEvent>
  }
  public enum TerminalEngineError: Error, Equatable, Sendable {
      case engineStartFailed(reason: String)
      case configurationInvalid(diagnostics: [String])
      case surfaceCreationFailed(workingDirectory: String, reason: String)
  }
  @MainActor public struct OpenPane {
      public init(engine: any TerminalEngine)
      public func execute(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> Pane
  }
  ```
  `FakeTerminalEngine` (solo en tests): `openedSpecs: [TerminalSessionSpec]`, `closedPanes: [PaneID]`, `failure: TerminalEngineError?` y `emit(_ event: TerminalEvent, for: PaneID)`.

- [ ] **Step 1: Pruebas que fallan** (`OpenPaneTests`):
  - `opensLoginShellInRequestedDirectory`: `execute(.loginShell(in: /tmp))` → `fake.openedSpecs == [.loginShell(in: /tmp)]` y el `Pane` devuelto tiene `workingDirectory == /tmp` e `isRunning == true`.
  - `propagatesEngineFailure`: con `fake.failure = .surfaceCreationFailed(workingDirectory: "/tmp", reason: "x")`, `execute` lanza ese mismo error.
  - `eventsReachSubscriber`: tras abrir, `fake.emit(.titleChanged("zsh"), for: id)` llega al primer elemento de `fake.events(for: id)`.
- [ ] **Step 2:** `swift test` → falla al compilar.
- [ ] **Step 3:** Implementar el puerto, el caso de uso y el fake (un `AsyncStream.makeStream()` por panel).
- [ ] **Step 4:** `swift test --package-path Packages/SmaltiCore` → todo en verde.
- [ ] **Step 5:** Commit `feat(core): add TerminalEngine port and OpenPane use case`.

### Task 4: Ghostty fijado y build reproducible de GhosttyKit

**Files:**
- Create: submódulo `vendor/ghostty` en `83fb95624b0439ee660c2679b43b38c8b63769cd`
- Create: `scripts/bootstrap`, `scripts/build-ghostty.sh`, `scripts/check-ghostty-pin.sh`
- Test: `scripts/tests/check-ghostty-pin.test.sh`, `scripts/tests/build-ghostty-zig-version.test.sh`

**Interfaces:**
- Produces, en `Packages/GhosttyAdapter/Frameworks/` (ignorado por git):
  - `GhosttyKit.xcframework`
  - `GhosttyKit.sha` (SHA del submódulo con el que se construyó)
  - `ghostty-resources/ghostty/` (integración de shell y temas)
  - `ghostty-resources/terminfo/`
- Produces: `scripts/check-ghostty-pin.sh [repo_root]` → código 0 si `GhosttyKit.sha` coincide con `git -C vendor/ghostty rev-parse HEAD`. Si no, código 1 y en stderr: `GhosttyKit.xcframework was built from <a> but vendor/ghostty is at <b>. Run scripts/build-ghostty.sh`.

- [ ] **Step 1:** `git submodule add https://github.com/ghostty-org/ghostty.git vendor/ghostty && git -C vendor/ghostty checkout 83fb95624b0439ee660c2679b43b38c8b63769cd`.
- [ ] **Step 2: Pruebas que fallan** (bash, con `set -euo pipefail`, en un directorio temporal falso con `vendor/ghostty` como repo git mínimo):
  - `check-ghostty-pin.test.sh`: con el SHA igual → 0; con el SHA distinto → 1 y stderr contiene `was built from`; sin `GhosttyKit.sha` → 1 y stderr contiene `Run scripts/build-ghostty.sh`.
  - `build-ghostty-zig-version.test.sh`: con `ZIG=<script falso que imprime 0.16.0>`, `build-ghostty.sh` sale con 1 y stderr contiene `requires Zig >= 0.17.0 (found 0.16.0)`.
- [ ] **Step 3:** `bash scripts/tests/check-ghostty-pin.test.sh; echo $?` → distinto de 0 (los scripts no existen).
- [ ] **Step 4: Implementar**
  - **`build-ghostty.sh`:**
    - Lee `minimum_zig_version` de `vendor/ghostty/build.zig.zon` y lo compara con `${ZIG:-zig} version`.
    - En `vendor/ghostty` ejecuta `$ZIG build -Doptimize=ReleaseFast -Demit-xcframework=true -Dxcframework-target=native`.
    - Localiza el `GhosttyKit.xcframework` generado. La primera vez se confirma la ruta con `find vendor/ghostty -maxdepth 3 -name GhosttyKit.xcframework` y se fija en el script.
    - Copia el xcframework, `zig-out/share/ghostty` y `zig-out/share/terminfo` a `Packages/GhosttyAdapter/Frameworks/`, y escribe `GhosttyKit.sha`.
  - **`check-ghostty-pin.sh`:** según Interfaces.
  - **`bootstrap`:** `brew list zig || brew install zig`, `git submodule update --init --recursive` y `scripts/build-ghostty.sh`.
- [ ] **Step 5:** `bash scripts/tests/check-ghostty-pin.test.sh && bash scripts/tests/build-ghostty-zig-version.test.sh; echo $?` → `0`.
- [ ] **Step 6:** `scripts/bootstrap` real. Comprobar que `Packages/GhosttyAdapter/Frameworks/GhosttyKit.xcframework/Info.plist` existe, `ghostty-resources/terminfo` contiene la entrada `xterm-ghostty` y `scripts/check-ghostty-pin.sh; echo $?` → `0`. Anotar el tiempo de build y la versión de Zig para el informe (A1).
- [ ] **Step 7:** Commit `build(ghostty): pin libghostty v1.4.0 and add reproducible xcframework build`.

### Task 5: `GhosttyAdapter`: configuración, mapeo de acciones y tamaños

**Files:**
- Create: `Packages/GhosttyAdapter/Package.swift`
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{GhosttyProcess,GhosttyConfigText,GhosttyConfigLoader,GhosttyActionMapper,SurfaceSizing}.swift`
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/ThirdParty/LICENSE-ghostty.txt` (MIT de Ghostty)
- Test: `Packages/GhosttyAdapter/Tests/GhosttyAdapterTests/{GhosttyConfigTextTests,GhosttyConfigLoaderTests,GhosttyActionMapperTests,SurfaceSizingTests,AdapterGuardTests}.swift`

**Interfaces:**
- Consumes: `Theme`, `TerminalAppearance`, `TerminalEvent`, `WorkingDirectory` y `TerminalEngineError` (Tasks 2–3).
- Produces:
  - **`Package.swift`:**
    - `binaryTarget(name: "GhosttyKit", path: "Frameworks/GhosttyKit.xcframework")`.
    - Target `GhosttyAdapter` que depende de `SmaltiCore` (`../SmaltiCore`) y de `GhosttyKit`.
    - `linkerSettings`: `c++`, `Metal`, `MetalKit`, `QuartzCore`, `CoreText`, `CoreGraphics`, `IOSurface`, `Carbon`, `AppKit`. La lista exacta se ajusta según los fallos de enlace y se compara con `vendor/ghostty/macos/Ghostty.xcodeproj`.
  - `enum GhosttyProcess { @MainActor static func ensureInitialized(resourcesDirectory: URL?) throws(TerminalEngineError) }`: fija `GHOSTTY_RESOURCES_DIR` si se le pasa y llama una sola vez a `ghostty_init`.
  - `enum GhosttyConfigText { static func render(_ appearance: TerminalAppearance) -> String }`
  - `final class GhosttyConfig`: posee `ghostty_config_t` y lo libera en `deinit`. `@MainActor static func load(text: String, writingTo url: URL) throws(TerminalEngineError) -> GhosttyConfig`.
  - `enum GhosttyActionMapper { static func event(for action: ghostty_action_s) -> TerminalEvent? }`
  - `enum SurfaceSizing { static func pixelSize(points: (width: Double, height: Double), scale: Double) -> (width: UInt32, height: UInt32) }`

- [ ] **Step 1: Pruebas que fallan**
  - **`GhosttyConfigTextTests`:** `render(Theme.obsidian.terminal)` contiene estas líneas exactas:
    - `font-family = "JetBrains Mono"`, `font-size = 13`
    - `foreground = #d7dae0`, `cursor-color = #7aa2f7`
    - `background-opacity = 0`
    - `window-padding-x = 16`, `window-padding-y = 12`, `window-padding-balance = false`
    - `macos-option-as-alt = false`
    - `shell-integration = zsh`
    - `confirm-close-surface = false`
    - `adjust-cell-height = 23%`: valor inicial; se calibra en Task 7 contra el interlineado 1.62.
    - `palette = 0=#15161e` … `palette = 15=#c0caf5`: 16 líneas en orden.
  - **`GhosttyConfigLoaderTests`:**
    - `loadsGeneratedConfigWithoutDiagnostics`: `load(text: render(.obsidian.terminal), writingTo: tmp)` no lanza.
    - `invalidKeyThrowsWithDiagnostics`: `load(text: "not-a-real-key = 1", …)` lanza `.configurationInvalid(diagnostics:)` con un diagnóstico no vacío que menciona `not-a-real-key` (Review Focus 4).
  - **`GhosttyActionMapperTests`**, con `ghostty_action_s` construidos en Swift:
    - `SET_TITLE("zsh")` → `.titleChanged("zsh")`.
    - `PWD("/tmp")` → `.workingDirectoryChanged(/tmp)`.
    - `PWD("relative")` → `nil`.
    - `COMMAND_FINISHED(exit_code: 1, duration: 400_000_000)` → `.commandFinished(exitCode: 1, duration: .milliseconds(400))`.
    - `COMMAND_FINISHED(exit_code: -1, …)` → `exitCode: nil`.
    - `RING_BELL` → `.bell`.
    - `SHOW_CHILD_EXITED(exit_code: 0)` → `.exited(code: 0)`.
    - `NEW_SPLIT` → `nil`.
  - **`SurfaceSizingTests`** (Review Focus 3): `(100, 50)` a escala 2 → `(200, 100)`; `(0, 0)` → `(1, 1)`; `(-5, 10)` → `(1, 20)`; `(100.6, 50.2)` a escala 1 → `(100, 50)`, redondeando hacia abajo.
  - **`AdapterGuardTests`:** ningún archivo de `Sources/GhosttyAdapter` contiene `ghostty_config_load_default_files`, `ghostty_config_load_cli_args` ni `ghostty_config_load_recursive_files`. Si aparece uno, el mensaje da archivo y línea (A8).
- [ ] **Step 2:** `swift test --package-path Packages/GhosttyAdapter` → falla al compilar.
- [ ] **Step 3: Implementar**
  - `GhosttyConfig.load`: escribe el texto en `url`, llama a `ghostty_config_new`, `ghostty_config_load_file` y `ghostty_config_finalize`. Si `ghostty_config_diagnostics_count > 0`, junta los mensajes y lanza el error.
  - `GhosttyActionMapper`: convierte cada `const char*` con `String(cString:)`, tras comprobar que no es nulo.
  - Las secciones que se adapten del código de Ghostty llevan la cabecera `// Adapted from ghostty v1.4.0 <ruta> (MIT, see ThirdParty/LICENSE-ghostty.txt)`.
- [ ] **Step 4:** `swift test --package-path Packages/GhosttyAdapter` → todo en verde. `swift test --package-path Packages/SmaltiCore` sigue en verde.
- [ ] **Step 5:** Commit `feat(ghostty): add config generation, action mapping and surface sizing`.

### Task 6: App de Xcode con la ventana de vidrio (sin terminal)

**Files:**
- Create: `App/Smalti.xcodeproj` (pbxproj `objectVersion = 77` con `PBXFileSystemSynchronizedRootGroup` para `App/Smalti` y `App/SmaltiUITests`; esquema compartido `Smalti.xcscheme`)
- Create: `App/Smalti/{SmaltiAppDelegate,AppComposition,SmaltiWindow,WindowGlass,DragStripView,PaneContainerView,Theme+AppKit}.swift`
- Create: `App/Smalti/Smalti.entitlements`
- Test: `App/SmaltiUITests/MainWindowTests.swift`
- Create: `scripts/test-ui.sh`

**Interfaces:**
- Consumes: `Theme.obsidian` (Task 2) mediante `XCLocalSwiftPackageReference` a `../Packages/SmaltiCore`.
- Produces:
  - `extension RGBAColor { var nsColor: NSColor }` en `Theme+AppKit.swift`.
  - `final class SmaltiWindow: NSWindow`, `init(theme: Theme)`.
  - `final class PaneContainerView: NSView`, `init(theme: Theme)` y `func embed(_ terminalView: NSView)`.
  - `enum WindowGlass { static func apply(blurRadius: Double, to window: NSWindow) }`.
  - Identificadores de accesibilidad: `smalti.window`, `smalti.dragStrip`, `smalti.pane`.
  - Ajustes de build:
    - `MACOSX_DEPLOYMENT_TARGET = 27.0`, `PRODUCT_BUNDLE_IDENTIFIER = dev.simonriv.smalti`
    - `CODE_SIGN_IDENTITY = "-"`, `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = NO`
    - `SWIFT_VERSION = 6.0`, `ENABLE_USER_SCRIPT_SANDBOXING = NO`
    - `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_NSPrincipalClass = NSApplication`

- [ ] **Step 1: Prueba que falla** (`MainWindowTests`, XCUITest):
  - `windowHasDesignSize`: el frame de `app.windows["smalti.window"]` mide 1328 × 820.
  - `trafficLightsAreHidden`: los botones `_XCUI:CloseWindow`, `MinimizeWindow` y `FullScreenWindow` no existen o no son `isHittable`.
  - `dragStripIs40PointsTall`: `app.otherElements["smalti.dragStrip"].frame.height == 40`.
  - `paneIsInsetByAreaPadding`: `smalti.pane.frame.minX - window.frame.minX == 10` y `pane.minY - dragStrip.maxY == 10`.
- [ ] **Step 2:** Crear `scripts/test-ui.sh`, que sigue la regla de suites largas:
  - Obtiene el total con `xcodebuild test-without-building -enumerate-tests` (antes, `build-for-testing`).
  - Convierte cada `Test Case '-[… …]' passed|failed` en `[n/total] ok|FAIL <Clase.prueba>`.
  - Conserva el código de salida de xcodebuild (`PIPESTATUS`).
- [ ] **Step 3:** `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh MainWindowTests` → FAIL (no hay app).
- [ ] **Step 4: Implementar**
  - **`SmaltiWindow`:**
    - `styleMask` `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`, `titlebarAppearsTransparent`, `titleVisibility = .hidden`.
    - Botones estándar con `isHidden = true`.
    - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, `minSize = 480 × 300`, tamaño inicial 1328 × 820 centrado.
  - **Vista de contenido:**
    - Capa con `cornerRadius = theme.window.cornerRadius`, `masksToBounds`, borde de 1 px `theme.window.border` y fondo `theme.window.background`.
    - `invalidateShadow()` tras cada layout.
  - **`WindowGlass`:** `CGSSetWindowBackgroundBlurRadius` por `dlsym` sobre `CGSMainConnectionID`, como hace Ghostty. Si `dlsym` devuelve nulo, usa como respaldo un `NSVisualEffectView` (`.hudWindow`, `.behindWindow`) bajo el contenido. La saturación del 150 % no la da la API privada: se anota en el informe.
  - **`DragStripView`:** alto `theme.chrome.topStripHeight`; `mouseDown` → `window?.performDrag(with:)`.
  - **`PaneContainerView`:** margen `areaPadding`, radio `panel.cornerRadius`, fondo `panel.background` y borde `panel.border`.
  - **`AppComposition`:** construye la ventana. `applicationShouldTerminateAfterLastWindowClosed` → `true`.
- [ ] **Step 5:** `xcodebuild -project App/Smalti.xcodeproj -scheme Smalti -derivedDataPath build build | tail -1` → `** BUILD SUCCEEDED **`. Después, `kb-progress run e2e -- scripts/test-ui.sh MainWindowTests` → `[4/4] ok …` y código 0.
- [ ] **Step 6:** Captura de la ventana (`screencapture -l <windowid>`) superpuesta a `Main.dc.html` sin paneles (radio, borde, franja y margen). Guardarla en `docs/specs/F0-assets/window-shell.png` (A5, parcial).
- [ ] **Step 7:** Commit `feat(app): add glass window shell with drag strip and pane container`.

### Task 7: Terminal viva: runtime, superficie y motor de Ghostty

**Files:**
- Create: `Packages/GhosttyAdapter/Sources/GhosttyAdapter/{GhosttyRuntime,GhosttySurfaceView,GhosttyTerminalEngine}.swift`
- Create: `App/Smalti/TerminalViewProvider.swift`
- Modify: `App/Smalti/AppComposition.swift`
- Modify: `App/Smalti.xcodeproj` (dependencia `GhosttyAdapter` y dos fases de script: `scripts/check-ghostty-pin.sh` antes de compilar, y copia de `Packages/GhosttyAdapter/Frameworks/ghostty-resources/{ghostty,terminfo}` a `Contents/Resources/`)
- Test: `App/SmaltiUITests/TerminalPaneTests.swift`

**Interfaces:**
- Consumes: `TerminalEngine`, `OpenPane` y `Pane` (Task 3); `GhosttyConfig`, `GhosttyActionMapper`, `SurfaceSizing` y `GhosttyProcess` (Task 5); `PaneContainerView` (Task 6).
- Produces:
  - `@MainActor final class GhosttyRuntime`, `init(config: GhosttyConfig) throws(TerminalEngineError)`.
    - Implementa `ghostty_runtime_config_s`.
    - `wakeup_cb` → `DispatchQueue.main.async { ghostty_app_tick }`.
    - `action_cb` → entrega el `TerminalEvent` mapeado al `GhosttySurfaceView` del `userdata` y devuelve `true` solo si lo maneja.
    - Portapapeles con `NSPasteboard.general`. `confirm_read_clipboard_cb` deniega las lecturas por OSC 52 en F0.
    - `close_surface_cb` → el motor cierra el panel.
  - `@MainActor public final class GhosttyTerminalEngine: TerminalEngine`, `init(runtime: GhosttyRuntime)` y `public func view(for pane: PaneID) -> NSView?`.
  - `protocol TerminalViewProvider { func view(for pane: PaneID) -> NSView? }` en la app, y `extension GhosttyTerminalEngine: TerminalViewProvider {}` en `AppComposition.swift`. Así el dominio no ve AppKit.
  - `GhosttySurfaceView: NSView, NSTextInputClient`. Es un subconjunto adaptado de `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` v1.4.0, y solo incluye:
    - `keyDown` / `keyUp` / `flagsChanged` con `interpretKeyEvents`, `insertText`, `setMarkedText` y `unmarkText` → `ghostty_surface_key` / `ghostty_surface_text`.
    - Ratón: pulsar, soltar, mover, arrastrar y scroll.
    - `becomeFirstResponder` / `resignFirstResponder` → `ghostty_surface_set_focus`.
    - `setFrameSize` → `SurfaceSizing` → `ghostty_surface_set_size`.
    - `viewDidChangeBackingProperties` → `ghostty_surface_set_content_scale`.
    - Nada de inspector, búsqueda, arrastre de archivos ni barra de progreso.

- [ ] **Step 1: Prueba que falla** (`TerminalPaneTests`, XCUITest):
  - `paneHostsTerminalSurface`: dentro de `smalti.pane` existe un elemento `smalti.terminal` con un tamaño mayor que 0.
  - `typingReachesShell`:
    - Escribe `echo smalti-ok > "$TMPDIR/smalti-uitest"` + Enter.
    - La prueba lee ese archivo (ruta pasada por `launchEnvironment`) y espera `smalti-ok`.
    - El archivo prueba que el shell recibió la entrada sin depender de leer el contenido de la pantalla Metal.
- [ ] **Step 2:** `kb-progress run e2e -- scripts/test-ui.sh TerminalPaneTests` → FAIL.
- [ ] **Step 3: Implementar**
  - Runtime, vista y motor.
  - `open(spec)`:
    - Crea la vista y la superficie con `ghostty_surface_config_new()`: `platform_tag = GHOSTTY_PLATFORM_MACOS`, `nsview` = la vista, `userdata` = la vista, `scale_factor` de la pantalla y `working_directory`.
    - `command`: nulo para `.loginShell`; `env_vars` desde `spec.environment`.
    - Contexto `GHOSTTY_SURFACE_CONTEXT_WINDOW`. Si la superficie sale nula, lanza `.surfaceCreationFailed`.
  - Cada evento se registra con `Logger(subsystem: "dev.simonriv.smalti", category: "engine")`.
  - **`AppComposition`:**
    - `GhosttyProcess.ensureInitialized(resourcesDirectory: Bundle.main.resourceURL/ghostty)`.
    - `GhosttyConfig.load(text: GhosttyConfigText.render(Theme.obsidian.terminal), writingTo: ~/Library/Application Support/Smalti/ghostty.conf)`.
    - Runtime, motor y `OpenPane.execute(.loginShell(in: home))`, con la vista embebida en `PaneContainerView`.
    - Suscribe los eventos: `Pane.applying`, y con `exited` cierra la ventana.
    - Si la configuración o el motor fallan, muestra un `NSAlert` con los diagnósticos y termina.
- [ ] **Step 4:** `kb-progress run e2e -- scripts/test-ui.sh` → todas en verde, de Task 6 y Task 7, código 0.
- [ ] **Step 5: Calibrar `adjust-cell-height`.** Captura con `seq 1 30` y comparación del paso de línea con `Main.dc.html` (12,5–13 px × 1,62). Se ajusta el valor en `GhosttyConfigText` y en su prueba hasta que la diferencia sea ≤ 1 px por línea.
- [ ] **Step 6: Verificación manual de la spec**, con evidencia en `docs/specs/F0-assets/`:
  - A6: `echo $TERM` y `infocmp xterm-ghostty`.
  - A7: `cd /tmp` y `false`, con el log de `log stream --predicate 'subsystem == "dev.simonriv.smalti"'`.
  - A8: cambiar `font-size` en `~/.config/ghostty/config` y comprobar que nada cambia en Smalti.
  - A11: á é í ó ú ñ ü ¿ ¡ con teclas muertas y los caracteres de ⌥ (Review Focus 1).
  - `exit`: la ventana se cierra y la app termina (Review Focus 2).
  - Mover la ventana a otra pantalla o cambiar la resolución: el texto sigue nítido (Review Focus 5).
- [ ] **Step 7:** Commit `feat(ghostty): embed libghostty surface behind TerminalEngine`.

### Task 8: Lista de render, mediciones y pregunta técnica 7

**Files:**
- Create: `scripts/bench/throughput.sh`
- Create: `docs/specs/F0-render-checklist.md`
- Create: `spikes/prompt-overlay/` (exploración; se borra en Task 9)

**Interfaces:**
- Produces: `scripts/bench/throughput.sh [runs=5]`. Genera un archivo de 50 MB en `$TMPDIR`, mide `cat` y `seq 1 5000000` con `/usr/bin/time -p` e imprime `cat50mb median=<s>` y `seq5m median=<s>`. Se ejecuta dentro de cada terminal.

- [ ] **Step 1:** Escribir `throughput.sh`. `bash scripts/bench/throughput.sh 1` en Terminal.app → imprime las dos líneas con números.
- [ ] **Step 2:** `F0-render-checklist.md`: casillas de A9 y A10, copiadas de la spec, con columnas Smalti y Ghostty.app.
- [ ] **Step 3: Simón ejecuta** A9, A10 (grabaciones), A12 (`throughput.sh` en Smalti y en Ghostty.app), A13 (Instruments, plantilla Hangs, 2 min escribiendo con Claude en streaming), A14 (`footprint -p Smalti` contra `footprint -p ghostty`), A15 (contraste con el color picker sobre un escritorio oscuro y uno claro) y A16 (A/B a ciegas de 10 minutos por terminal). Claude prepara los comandos y registra los resultados.
- [ ] **Step 4: Pregunta técnica 7** (máximo medio día):
  - En `spikes/prompt-overlay/`, una vista transparente sobre la superficie que se posiciona con la marca de prompt.
  - Explorar `ghostty_surface_*` para leer la posición del cursor y la celda en v1.4.0.
  - Conclusión escrita: viable, viable con cambios o no viable.
  - Probar también `ghostty_surface_foreground_pid` con `sleep 30` en primer plano (pregunta técnica 6).
- [ ] **Step 5:** Commit `chore(spike): add throughput bench and render checklist`.

### Task 9: Informe del spike, Muter y cierre

**Files:**
- Create: `docs/specs/F0-spike-report.md`
- Modify: `CLAUDE.md` (sección Comandos con los comandos reales), `progress.md`
- Delete: `spikes/`

- [ ] **Step 1: Muter.** Comprobar en su repositorio y documentación si Muter soporta Swift Testing y paquetes SwiftPM.
  - Si los soporta: configurar `muter.conf.yml` para `Packages/SmaltiCore`, ejecutarlo y anotar la puntuación de mutación.
  - Si solo soporta XCTest o no funciona con SwiftPM: **parar y preguntar a Simón**. No se migran pruebas a XCTest por iniciativa propia.
- [ ] **Step 2: Informe:**
  - Tabla A1–A16 con resultado y evidencia.
  - Respuestas a las preguntas técnicas 1–7.
  - Lista cerrada de funciones `ghostty_*` usadas (con `grep -ho 'ghostty_[a-z_]*' Packages/GhosttyAdapter/Sources -r | sort -u`).
  - Desviaciones del diseño: saturación del vidrio, sombra del sistema frente a `0 30px 90px` y `⌘1` en lugar de `⌥1` para F1.
  - Riesgos que quedan para F1, F4 y F7.
  - Veredicto: F0 cerrado o qué falta.
- [ ] **Step 3:** Borrar `spikes/`. Pasar `swift format lint --strict --recursive Packages App`, `swift test` en ambos paquetes y `kb-progress run e2e -- scripts/test-ui.sh` → todo en código 0, con el total de pruebas anotado.
- [ ] **Step 4:** Actualizar la sección Comandos de `CLAUDE.md` y `progress.md`.
- [ ] **Step 5:** Commit `docs(spike): add F0 spike report` y PR `feature/f0-spike` → `develop`, con el informe como descripción. El merge lo hace Simón.

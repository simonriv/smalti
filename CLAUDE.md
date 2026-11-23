# Smalti

Terminal nativa para macOS, en Swift + AppKit sobre libghostty. Herramienta personal de Simón: no es un producto de Xolken, así que no aplican `xolken/infra`, Cloud Run ni Supabase, ni el stack por defecto Next.js/TypeScript.

## Fuentes de verdad

- `docs/PROJECT.md`: visión, funcionalidades, arquitectura y **Decisiones**. Las Decisiones están cerradas: si una tarea choca con alguna, para y propón el cambio con su porqué antes de implementarlo.
- `docs/ROADMAP.md`: fases F0–F7 con criterio de cierre. No adelantes trabajo de fases posteriores.
- `docs/specs/F<n>-*.md`: la spec de la fase en curso. Sin spec aprobada no se escribe código de esa fase.
- `docs/design/`: **referencia visual obligatoria**. Lee su `README.md` antes de cualquier trabajo de UI.
- `progress.md`: avance por spec → plan → tareas.

## Diseño visual

- Reproduce los tableros de `docs/design/*.dc.html` en AppKit/SwiftUI: colores, medidas, radios, tipografías, jerarquía y textos de interfaz (en español, tal cual).
- Los tokens viven en un único sitio del código (tema Obsidiana por defecto) y salen de `docs/design/README.md`. No hay valores mágicos sueltos en las vistas.
- Toda diferencia visual con un tablero se justifica en el PR. Si el tablero no cubre un caso, pregunta antes de inventarlo.
- Principios no negociables: sin botones fijos (toda acción tiene atajo y está en ⌘K); estado codificado siempre igual (verde trabajando, ámbar te espera, rojo error, círculo hueco detenido); un solo acento; contraste ≥ 4.5:1 sobre el vidrio; animaciones de 150 ms como máximo, que respetan "Reducir movimiento".
- Cada PR de UI adjunta una captura junto al tablero correspondiente.

## Arquitectura hexagonal

```text
SmaltiApp (Xcode)  → composition root + adaptadores primarios (AppKit/SwiftUI, IPC, CLI)
SmaltiCore (SPM)   → Domain/ + Application/ (casos de uso + puertos). Swift puro.
<X>Adapter (SPM)   → un target por adaptador secundario (GhosttyAdapter, TOMLConfigAdapter…)
```

- **Dominio en Swift puro.** `SmaltiCore` no importa AppKit, SwiftUI, Combine, GhosttyKit, librerías de C ni SDKs. Foundation solo para tipos de valor (`URL`, `Date`, `UUID`). Usa geometría propia (`Rect`, `Size`), nunca `CGRect`.
- **Puertos** (`TerminalEngine`, `HarnessAdapter`, `TelemetrySource`, `AgentTranscripts`, `LiveAgents`, `LocalModels`, `CompletionProvider`, `PredictionProvider`, `EditorBridge`, `SystemMetrics`, `ConfigStore`, `Notifier`):
  - Los define `SmaltiCore`, desde el caso de uso que los usa.
  - Usan vocabulario de dominio (`open`, `close`, `current`), no técnico.
  - Son pocos y pequeños (ISP).
- **Adaptadores secundarios:** cada uno vive en su propio target y es el único que importa su librería externa. Traduce los errores de esa librería a errores tipados del dominio en la frontera.
- **Adaptadores primarios:** vistas, controladores, el `KeyRouter`, el IPC y la CLI validan la entrada, llaman a un caso de uso y pintan el resultado. No contienen reglas de negocio.
- **Composition root:** un único `AppComposition` en `SmaltiApp` conecta puertos y adaptadores. Nada más instancia infraestructura.
- **Pruebas sin infraestructura:** cada caso de uso corre en una prueba con fakes en memoria (`FakeTerminalEngine`, `InMemoryConfigStore`…), sin AppKit ni libghostty.
- **Guarda de imports:** una prueba de guarda falla nombrando archivo y línea si `SmaltiCore` importa algo prohibido. No se desactiva.
- **Variantes:** cada layout, harness o proveedor nuevo es un tipo nuevo que implementa el protocolo, no un `case` más en un `switch` (OCP). Las implementaciones intercambiables comparten una prueba de contrato.

## libghostty

- **Commit fijado:** se fija en un único lugar, el SHA del submódulo `vendor/ghostty`; hoy es Ghostty `v1.4.0` (`83fb956`). `scripts/build-ghostty.sh` construye `GhosttyKit.xcframework` (en `.gitignore`), y el build falla si el xcframework no corresponde a ese SHA.
- **Frontera:** solo el target `GhosttyAdapter` importa GhosttyKit. Punteros, `ghostty_*_t` y tipos de C nunca cruzan el puerto `TerminalEngine`; la vista (`NSView`) sale por `TerminalViewProvider`, del lado de la app.
- **Actualizaciones a propósito:** se actualiza en un PR propio, `chore(ghostty): bump to <sha>`. El PR incluye el diff de las APIs de `ghostty.h` que usamos y la lista de render de F0 (`docs/specs/F0-spike.md`, A9–A11) repetida.
- **Configuración aislada:** Smalti nunca lee `~/.config/ghostty/`. La configuración del motor se genera desde `SmaltiConfig`.
- **Hilos:** las llamadas a la API de C respetan el hilo que exige; cada callback documenta su hilo.

## Plataforma

- Solo macOS 27 o posterior, en Apple Silicon. Bundle ID `dev.simonriv.smalti`.
- Firma ad hoc local, sin Developer ID ni notarización.
- Se permiten APIs privadas de AppKit/CoreGraphics solo en adaptadores y con respaldo público. Ejemplo: el desenfoque de ventana con radio exacto.
- ⌥ queda reservado para escribir caracteres (layout Latin American): ningún atajo usa ⌥ sin ⌘ o ⌃, y ⌥ no actúa como Meta.

## Swift

- Swift 6 con concurrencia estricta. La UI y los callbacks del motor van en `@MainActor`; los puentes con C son explícitos.
- **Prohibido:**
  - `!`, `try!`, `as!` y `unsafe*` sin un comentario que justifique por qué es seguro. Lo inseguro solo existe en adaptadores.
  - `// swiftlint:disable` o equivalentes para hacer compilar.
- **Errores:** tipados (`throws(TerminalEngineError)`) con contexto: operación, dato y causa. Sin `nil` como señal de fallo ni `catch` vacíos.
- **Nombres:**
  - `UpperCamelCase` para tipos y `lowerCamelCase` para valores.
  - Protocolos sin prefijo ni sufijo de rol (`TerminalEngine`, no `TerminalEngineProtocol`).
  - Predicados con `is/has/can`.
- **Funciones:** pequeñas, de una sola cosa y con 3 parámetros como máximo. `struct` y `enum` por defecto; `final class` solo con identidad o estado compartido; nada de herencia salvo la que exige AppKit.
- **Formato:** `swift format` (incluido en la toolchain) con la configuración del repo. No se discute a mano.
- **Idiomas:** código, identificadores, archivos y commits en inglés. Textos de interfaz en español, tal cual los tableros. Docs en español.

## Pruebas

- TDD: la prueba que falla va antes del código de producción.
- **Unitarias y de dominio:** Swift Testing (`import Testing`), en formato Arrange/Act/Assert, un concepto por prueba. Prueba los límites: 0, 1 y 9 paneles, ratios en los bordes y tamaños mínimos.
- **Contrato compartido:** obligatorio para cada puerto con más de una implementación.
- **Mutation testing:** `scripts/mutation/mutate.py` (propio; Muter v16 no aplica mutaciones con SwiftPM + Swift Testing, issue #321). Puntuación mínima 80 % en `SmaltiCore`; los sobrevivientes se arreglan con una prueba nueva, no se ignoran.
- **E2E de la UI nativa:** XCUITest, solo las pruebas afectadas por el cambio.
- **Verificación manual:** las listas de render y las mediciones de cada spec se registran en el PR o en el informe de la fase.
- **Suites largas:** toda suite de más de ~30 s se lanza con `"$KB_ROOT/_system/bin/kb-progress" run <etiqueta> -- <comando>` y muestra `[n/total] ok|FAIL <unidad>`.
- No des una suite por buena mirando una salida que pasó por un pipe: comprueba el código de salida.

## Comandos

- `scripts/bootstrap`: Zig (Homebrew), Metal Toolchain de Xcode, submódulo `vendor/ghostty` y build de GhosttyKit.
- `scripts/check-ghostty-pin.sh`: comprueba que GhosttyKit corresponde al SHA fijado (también corre como fase de build).
- `swift test --package-path Packages/SmaltiCore`: dominio y casos de uso.
- `swift test --package-path Packages/GhosttyAdapter`: adaptador de libghostty (requiere GhosttyKit construido).
- `swift test --package-path Packages/TOMLConfigAdapter`: adaptador de configuración TOML.
- `xcodebuild -project App/Smalti.xcodeproj -scheme Smalti -derivedDataPath build build`: app de desarrollo `build/Build/Products/Debug/Smalti Dev.app` (`dev.simonriv.smalti.dev`, estado propio); el Release (`Smalti.app`, `dev.simonriv.smalti`) es el diario.
- `scripts/check-daily-untouched.sh <comando…>`: falla si el comando cerró el Smalti diario o tocó su estado (C1 de F2).
- `scripts/tests/build-identity.test.sh`: bundle ID y nombre de Debug y Release.
- `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh [Clase]`: XCUITest, con una línea `[n/total] ok|FAIL` por prueba.
- `swift format lint --strict -r App Packages/SmaltiCore Packages/GhosttyAdapter/Sources Packages/GhosttyAdapter/Tests Packages/TOMLConfigAdapter`: formato.
- `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore`: mutation testing; pruebas del mutador con `cd scripts/mutation && python3 -m unittest test_mutate`.
- Pruebas automáticas que abran un shell: siempre `-SmaltiShellCommand "/bin/zsh -f"` (el login shell de Simón se engancha a su tmux).

## Git

- Repo `simonriv/smalti` (cuenta personal `simonriv`). Rama principal `main`.
- Flujo: `feature/*` desde `develop` → PR a `develop` → PR `develop` → `main`. Conventional Commits en inglés.
- Proyecto personal: Simón aprueba y hace merge. Claude no hace merge ni push a `main` sin pedirlo.

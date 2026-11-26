# Smalti

Terminal nativa para macOS, en Swift + AppKit sobre libghostty. Herramienta personal de Simón: no es un producto de Xolken, así que no aplican `xolken/infra`, Cloud Run ni Supabase, ni el stack por defecto Next.js/TypeScript.

## Fuentes de verdad

- `docs/PROJECT.md`: visión, funcionalidades, arquitectura y **Decisiones**. Las Decisiones están cerradas: si una tarea choca con alguna, para y propón el cambio con su porqué antes de implementarlo.
- `docs/ROADMAP.md`: fases F0–F7 con criterio de cierre. No adelantes trabajo de fases posteriores.
- `docs/specs/F<n>-*.md`: la spec de la fase en curso. Sin spec aprobada no se escribe código de esa fase.
- `docs/design/`: **referencia visual obligatoria**. Lee su `README.md` antes de cualquier trabajo de UI.
- `progress.md`: avance por spec → plan → tareas.

## Diseño visual

- Reproduce los tableros de `docs/design/*.dc.html` en AppKit/SwiftUI: colores, medidas, radios, tipografías, jerarquía y textos de interfaz (en español, tal cual; el inglés sale del glosario de `docs/specs/F7.7-primer-uso.md`).
- **Textos de interfaz (F7.7):** ninguno suelto. Los del dominio viven en `SmaltiCore/Domain/Texts/` (un `struct` por área con `.spanish` y `.english`; plantillas `{nombre}`; el idioma llega como parámetro); los de las vistas, en `App/Smalti/Localizable.xcstrings` (`String(localized:)`, claves en inglés). La app resuelve el idioma una vez (`InterfaceLanguage.current`, desde `Bundle.main.preferredLocalizations`) y exporta `SMALTI_LANGUAGE` a los paneles para el CLI.
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
- **Puertos** (`TerminalEngine`, `HarnessAdapter`, `TelemetrySource`, `AgentTranscripts`, `LiveAgents`, `LocalModels`, `CompletionProvider`, `PredictionProvider`, `CommandHistory`, `ProjectContext`, `EditorBridge`, `SystemMetrics`, `ConfigStore`, `AppearanceStore`, `PromptFacts`, `Notifier`, `ImageFiles`, `PathFacts`, `LayoutFiles`, `TelemetryReceiver`, `ClaudeTelemetrySettings`, `GuardRequests`, `ProjectPermissions`, `AppUpdates`, `WelcomeRecord`, `RunningProcesses`, `ListeningPorts`, `ProcessControl`, `ProjectFiles`, `ProjectRecords`):
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
- Ningún atajo usa ⌥ sin ⌘ o ⌃ (⌥ escribe caracteres en layouts como el Latin American). ⌥ como Meta lo decide `[keyboard] option_as_meta` (F7.7): `auto` por defecto deja que libghostty decida por la distribución (Meta solo en U.S. y U.S. International).

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
- **Idiomas:** código, identificadores, archivos y commits en inglés. Interfaz en inglés y español según el sistema (F7.7), siempre desde el catálogo. Docs en español; `README.md` y `CONTRIBUTING.md` en inglés.

## Pruebas

- TDD: la prueba que falla va antes del código de producción.
- **Unitarias y de dominio:** Swift Testing (`import Testing`), en formato Arrange/Act/Assert, un concepto por prueba. Prueba los límites: 0, 1 y 9 paneles, ratios en los bordes y tamaños mínimos.
- **Contrato compartido:** obligatorio para cada puerto con más de una implementación.
- **Mutation testing:** `scripts/mutation/mutate.py` (propio; Muter v16 no aplica mutaciones con SwiftPM + Swift Testing, issue #321). Puntuación mínima 80 % en `SmaltiCore`; los sobrevivientes se arreglan con una prueba nueva, no se ignoran.
- **E2E de la UI nativa:** XCUITest, solo las pruebas afectadas por el cambio.
- **Verificación manual:** las listas de render y las mediciones de cada spec se registran en el PR o en el informe de la fase.
- **Suites largas:** toda suite de más de ~30 s se lanza con `"$KB_ROOT/_system/bin/kb-progress" run <etiqueta> -- <comando>` y muestra `[n/total] ok|FAIL <unidad>`.
- No des una suite por buena mirando una salida que pasó por un pipe: comprueba el código de salida.
- **Idioma en pruebas (F7.7):** ninguna depende del idioma del Mac. `isolatedSmalti(language:)` fuerza `-AppleLanguages` (español por defecto, `"en"` para las inglesas) y escribe la marca de bienvenida salvo `welcome: true`; nunca `XCUIApplication()` fuera de `IsolatedApp.swift` (lo vigila `UITestLanguageGuardTests`). Las pruebas de dominio pasan `.spanish`/`.english` explícito.

## Comandos

- `scripts/bootstrap`: Zig (Homebrew), Metal Toolchain de Xcode, submódulo `vendor/ghostty` y build de GhosttyKit.
- `scripts/check-ghostty-pin.sh`: comprueba que GhosttyKit corresponde al SHA fijado (también corre como fase de build).
- `swift test --package-path Packages/SmaltiCore`: dominio y casos de uso.
- `swift test --package-path Packages/GhosttyAdapter`: adaptador de libghostty (requiere GhosttyKit construido).
- `swift test --package-path Packages/TOMLConfigAdapter`: adaptador de configuración TOML.
- `swift test --package-path Packages/<FigCompletionAdapter|ProjectContextAdapter|IPCAdapter|FileSessionAdapter>`: adaptadores del input (F4): specs de Fig con JavaScriptCore, contexto de git y del proyecto, socket de input e historial de comandos.
- `cd scripts/fig && python3 vendor_specs.py` (pruebas: `python3 -m unittest test_vendor_specs`): regenera las specs de Fig vendorizadas desde `commands.txt` (`@withfig/autocomplete` fijado en `package.json`).
- `"$KB_ROOT/_system/bin/kb-progress" run bench -- scripts/measure-input.sh 5 [--real-history]`: C1 de F4, latencia de la sugerencia de extremo a extremo con 50.000 entradas; `--real-history` lee `~/.zsh_history` solo en lectura y en memoria.
- `TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh InputLatencyTests`: C13 de F4, a demanda (`TEST_RUNNER_SMALTI_MEASURE_IDLE=1` da la línea base).
- `swift test --package-path Packages/<ClaudeHarnessAdapter|CodexHarnessAdapter|AntigravityHarnessAdapter|OpenCodeHarnessAdapter|SQLiteReader>`: adaptadores de harness (F6): contrato compartido sobre fixtures reales (`Tests/*/Fixtures`, rutas fijas `/private/tmp/smalti-fx/<harness>`) y la reanudación de integración con el comando real de cada harness (se salta si el binario no está).
- `swift test --package-path Packages/NeovimAdapter`: puente msgpack-RPC con Neovim (F6) y C3 (diff con el protocolo de Claude, `:w` acepta y `:q` rechaza); necesita `nvim` y `scripts/harnesses/prepare-nvim-fixtures.sh` (lazy.nvim y claudecode.nvim `v0.4.0` en `build/nvim-fixtures`). Siempre `nvim --clean` o config temporal con su propio socket.
- `scripts/harnesses/record-fixtures.sh <claude|codex|antigravity|opencode>`: regraba los fixtures de un harness (los de Codex usan `--oss` con Ollama; los demás pueden gastar suscripción: preguntar antes). El home crudo queda en `scripts/harnesses/recording.local/` (no se versiona); el fixture es la copia de `sanitize_fixture.py` y `fixture_expectations.py` escribe el oráculo. Pruebas: `cd scripts/harnesses && python3 -m unittest test_sanitize_fixture test_fixture_expectations test_mark_claude_prompt`.
- `swift test --package-path Packages/ImageIOAdapter`: lectura y miniaturas de imágenes (F5.5) para la vista previa y `smalti img`.
- `"$KB_ROOT/_system/bin/kb-progress" run bench -- scripts/measure-cli-startup.sh 50 [binario…]`: C9 de F5.5, arranque de `smalti event` (lo que paga cada hook).
- `TEST_RUNNER_SMALTI_MEASURE=1 scripts/test-ui.sh PreviewLatencyTests`: C3 de F5.5, a demanda (`-SmaltiPreviewTimings <archivo>` escribe cada carga). `TEST_RUNNER_SMALTI_CAPTURE=1 scripts/test-ui.sh PreviewTests/testCaptureCard` saca la tarjeta para `docs/specs/F5.5-assets/compose-card.py`. `PREVIEW_HOVER=false scripts/measure-gpu-idle.sh` mide con la vista previa apagada.
- `cd scripts/otlp && python3 -m unittest test_fake_claude`: emisor falso de telemetría de Claude Code (F7, `fake-claude.py`), que usan las UI tests y las mediciones; nunca un Claude real.
- Telemetría y layouts compartibles (F7): `[extras] otlp` en `config.toml`; en pruebas, `-SmaltiManagedSettings` (nunca los managed settings de la máquina), `-SmaltiTelemetryProbe`, y en Debug `-SmaltiImportFile`, `-SmaltiPickedFolder`, `-SmaltiConfirmImport yes|no` y `-SmaltiExportDirectory`.
- Guardas para agentes (F7.5): `[guards]` en `config.toml`; el plugin llama a `smalti guard PreToolUse` (`onFailure: "block"`, vuelve a `event` solo si el CLI es anterior y sale con 64). En pruebas: `-SmaltiApprovalTimeoutSeconds` y `-SmaltiProjectPermissionsRoot` (⌘K escribe ahí `.claude/settings.local.json`, nunca en un proyecto real); los hooks se prueban con payloads falsos por `"$SMALTI_CLI" guard PreToolUse`, nunca con un Claude real.
- `"$KB_ROOT/_system/bin/kb-progress" run bench -- scripts/measure-guard.sh 50`: C12 de F7.5, arranque de `smalti guard PreToolUse` frente a `smalti event PreToolUse` con un servidor falso.
- `swift test --package-path Packages/OTLPReceiverAdapter`: receptor OTLP/HTTP de F7 (socket TCP solo en `127.0.0.1`, token por arranque, eventos `api_request` y `api_error` de Claude Code).
- `swift test --package-path Packages/DiagnosticsAdapter`: exportación de los registros de la sesión (F4.5, `OSLogStore` del propio proceso) y la guarda de que ningún `Logger` publica texto escrito.
- `swift test --disable-keychain --package-path Packages/DarwinProcessesAdapter`: procesos, puertos en escucha y señales (F8) con libproc y `sysctl`; la paridad con lsof (C1) y el control solo tocan hijos `python3` que lanzan las propias pruebas en loopback, y la guarda de que nadie más lista sockets, cambia prioridades ni manda SIGTERM/SIGKILL.
- Puertos y procesos (F8): en UI tests, `-SmaltiStopGraceSeconds <s>` (solo Debug) acorta la espera antes de ofrecer «Forzar»; `ProcessesTests` y `PortsTests` lanzan su oyente en su propio panel y solo detienen ese.
- `swift test --package-path Packages/<ClaudeTelemetryAdapter|OllamaAdapter|DarwinMetricsAdapter>`: adaptadores del Observatorio (F3). Las pruebas nunca leen el `~/.claude` real; las de UI pasan `-SmaltiClaudeHome` y `-SmaltiOllamaURL` temporales.
- `cd scripts/observatory && python3 -m unittest test_sum_transcripts test_sanitize_fixture`: oráculo de tokens y saneador de fixtures. `scripts/observatory/record-fixtures.sh <dir>` regraba los fixtures reales con `claude -p` (API de pago) y exige los marcadores personales en `scripts/observatory/markers.local`, que no se versiona.
- `"$KB_ROOT/_system/bin/kb-progress" run bench -- scripts/measure-observatory.sh 5`: C10 de F3 sobre el `~/.claude` real, solo lectura.
- `"$KB_ROOT/_system/bin/kb-progress" run bench -- scripts/check-daily-untouched.sh scripts/measure-gpu-idle.sh 5 [probe]`: C6 de F5, GPU en reposo de Smalti Dev delante de `scripts/gpu-backdrop.swift` (estático por defecto; `BACKDROP=moving` con contenido que cambia detrás, `BACKDROP=none` sin tapar el escritorio). Activa la app (roba el foco unos segundos por corrida) y deja una captura por corrida en `build/`.
- `cd scripts/fonts && python3 -m unittest test_build_symbols_font`: fuente `SmaltiSymbols` (iconos del prompt, U+E900–U+E91F). Se regenera con `swift outline-icons.swift icons icons.txt > icons.json && python3 build-symbols-font.py icons.json ../../App/Smalti/Fonts/SmaltiSymbols.ttf`. Lámina antes/después (F5.6): `python3 icons-sheet.py <antes.ttf> <después.ttf> <salida.html>` y Chrome sin interfaz.
- Apariencia y prompt (F5): la UI escribe solo `~/.config/smalti/theme.toml` (junto a `config.toml`, que nunca toca); en pruebas va junto al config temporal. `-SmaltiPickedColor`, `-SmaltiExportDirectory`, `-SmaltiNerdFontAvailable` y `-SmaltiReduceMotion` sustituyen al panel de color, al panel de guardado, a la detección de Nerd Font y a "Reducir movimiento" en las UI tests.
- `xcodebuild -project App/Smalti.xcodeproj -scheme Smalti -derivedDataPath build build`: app de desarrollo `build/Build/Products/Debug/Smalti Dev.app` (`dev.simonriv.smalti.dev`, estado propio); el Release (`Smalti.app`, `dev.simonriv.smalti`) es el diario.
- `scripts/check-daily-untouched.sh <comando…>`: falla si el comando cerró el Smalti diario o tocó su estado (C1 de F2).
- `scripts/tests/build-identity.test.sh`: bundle ID y nombre de Debug y Release.
- `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh Clase | Clase/prueba …`: XCUITest, una sola compilación para todo lo pedido y una línea `[n/total] ok|FAIL` por prueba. Sin clases se niega (sale con 2): la suite e2e completa nunca corre (`scripts/tests/test-ui-args.test.sh`).
- `swift test --disable-keychain --package-path Packages/SparkleUpdatesAdapter`: actualizaciones con Sparkle 2.10.1 (F7.6). En esta máquina SwiftPM se cuelga descargando el binario de Sparkle si consulta el llavero: `--disable-keychain` siempre (también en `swift package resolve`).
- Textos (F7.7): `scripts/tests/strings-catalog.test.sh` (cada clave del catálogo con `en` y `es`, ninguna clave de la app fuera de él y ningún literal español fuera de los catálogos; `// strings-catalog: keep` marca un literal que no es interfaz). Tras compilar la app, `python3 scripts/l10n/catalog.py sync` añade al catálogo las claves nuevas del compilador y `catalog.py translate <mapa.json>` fija su español; `catalog.py missing` lista las que faltan. `"$KB_ROOT/_system/bin/kb-progress" run e2e -- scripts/test-ui.sh LocalizationTests` recorre la interfaz en inglés buscando español.
- Privacidad (F7.7): `scripts/tests/network-surface.test.sh` falla si aparece una API de red o una URL literal fuera de los archivos permitidos (Sparkle, Ollama y OTLP en `127.0.0.1`, sockets Unix, enlaces de la web).
- `scripts/tests/notices.test.sh` y `scripts/tests/issue-forms.test.sh`: avisos de terceros (`THIRD_PARTY_NOTICES.md`, regenerado con `python3 scripts/release/compose-notices.py` tras construir GhosttyKit; `scripts/release/check-notices.sh` comprueba el binario) y formularios de issue (F7.6).
- Release (F7.6): `scripts/tests/release.test.sh` (scripts de `scripts/release/` sobre repos y claves de usar y tirar, `brew style` y `actionlint`). De punta a punta, al cerrar la fase y bajo `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID`: `scripts/release/test-install.sh dmg|brew` y `scripts/release/test-update.sh valid|invalid` (builds Release con bundle ID `dev.simonriv.smalti.updatetest`, estado y defaults de prueba, cuarentena puesta a propósito, appcast en 127.0.0.1; nunca tocan `/Applications/Smalti.app`). **Nunca `brew uninstall --zap` con el cask real** en esta máquina: borraría `~/.config/smalti`. En UI tests, `-SmaltiUpdateFeedURL` (solo Debug) apunta Smalti Dev a un feed local servido desde un panel.
- `swift format lint --strict -r App Packages/SmaltiCore Packages/GhosttyAdapter/Sources Packages/GhosttyAdapter/Tests Packages/TOMLConfigAdapter Packages/ClaudeTelemetryAdapter Packages/OllamaAdapter Packages/DarwinMetricsAdapter Packages/DarwinProcessesAdapter/Sources Packages/DarwinProcessesAdapter/Tests Packages/FigCompletionAdapter/Sources Packages/FigCompletionAdapter/Tests Packages/ProjectContextAdapter Packages/IPCAdapter Packages/FileSessionAdapter Packages/DiagnosticsAdapter Packages/ImageIOAdapter Packages/SQLiteReader Packages/NeovimAdapter Packages/ClaudeHarnessAdapter Packages/CodexHarnessAdapter Packages/AntigravityHarnessAdapter Packages/OpenCodeHarnessAdapter Packages/OTLPReceiverAdapter Packages/SparkleUpdatesAdapter/Sources Packages/SparkleUpdatesAdapter/Tests scripts/input-bench/Sources`: formato.
- `"$KB_ROOT/_system/bin/kb-progress" run mutation -- python3 scripts/mutation/mutate.py --package Packages/SmaltiCore [--changed-since <base>]`: mutation testing (con `--changed-since`, solo las líneas que cambió la rama; un archivo nuevo, entero); pruebas del mutador con `cd scripts/mutation && python3 -m unittest test_mutate`.
- Pruebas automáticas que abran un shell: siempre `-SmaltiShellCommand "/bin/zsh -f"` (el login shell de Simón se engancha a su tmux). Las que necesitan la integración de shell (F4: OSC 133 y widgets) usan `"/bin/zsh -d"` con un ZDOTDIR temporal vacío vía `-SmaltiUserZdotdir`.

## Git

- Repo `simonriv/smalti` (cuenta personal `simonriv`). Rama principal `main`.
- Flujo: `feature/*` desde `develop` → PR a `develop` → PR `develop` → `main`. Conventional Commits en inglés.
- Proyecto personal: Simón aprueba y hace merge. Claude no hace merge ni push a `main` sin pedirlo.

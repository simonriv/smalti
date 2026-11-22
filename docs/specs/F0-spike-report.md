# F0 · Informe del spike

2026-11-22 · Rama `feature/f0-spike` · Spec `docs/specs/F0-spike.md` · Plan `docs/plans/F0-spike.md` · Evidencia `docs/specs/F0-render-checklist.md` y `docs/specs/F0-assets/`

## Veredicto

**F0 queda técnicamente cerrado; el cierre formal depende de una sesión corta de Simón.**

- **Lo que confirma el spike:** Swift + AppKit + libghostty v1.4.0 dan una terminal con vidrio, sin botones, aislada tras `TerminalEngine`. Rinde igual o mejor que Ghostty.app (A12 y A14), sin bloqueos del hilo principal (A13) y con contraste suficiente sobre el vidrio (A15).
- **Lo que falta para el cierre formal:** los casos que exigen teclado físico, segundo monitor o juicio humano: A16 (A/B a ciegas), espacios y teclas muertas físicas, y los casos interactivos de Claude Code (prompt de permiso, redimensionar, `/help`, scroll). La lista exacta está en "Pendientes".

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| A1 | ✅ | `scripts/bootstrap` desde cero. Requisitos que aparecieron: Zig 0.17.1 de Homebrew y el Metal Toolchain de Xcode (`xcodebuild -downloadComponent MetalToolchain`, 839 MB). Build de GhosttyKit en 74 s |
| A2 | ✅ | El pin es el SHA del submódulo (`83fb956`, commit del tag v1.4.0). La fase "Check Ghostty pin" falla si `GhosttyKit.sha` no coincide (pruebas en `scripts/tests/`) |
| A3 | ✅ | `swift test` en `SmaltiCore`: 28 pruebas, sin GhosttyKit; la guarda de imports detecta `import AppKit` con archivo y línea |
| A4 | ✅ | `OpenPaneTests` con `FakeTerminalEngine` |
| A5 | ⚠️ | XCUITest verifica 1328 × 820, sin semáforo, franja de 40 px y margen de 10. La superposición pixel a pixel con `Main.dc.html` no se hizo; las capturas están en `F0-assets/` |
| A6 | ✅ | `TERM=xterm-ghostty`, terminfo empaquetado, `infocmp` resuelve |
| A7 | ✅ | `workingDirectoryChanged(/tmp)` y `commandFinished(exitCode: 1)` con la integración de shell real |
| A8 | ✅ | Solo se lee `Application Support/Smalti/ghostty.conf`; `AdapterGuardTests` |
| A9 | ⚠️ | Arranque, streaming y diff limpios; los casos interactivos quedan pendientes |
| A10 | ⚠️ | nvim, htop, emoji, CJK y paleta iguales a Ghostty; faltan ratón en nvim y pegado multilínea |
| A11 | ⚠️ | Texto, ⌘V y ⌘Q por E2E; acentos y caracteres de ⌥ con entrada sintetizada; faltan la tecla muerta física y los espacios físicos |
| A12 | ✅ | `cat50mb` 0,14 s frente a 0,14 s; `seq5m` 7,46 s frente a 7,93 s |
| A13 | ✅ | Peor retraso del hilo principal: 5,0 ms con 10 M líneas; 0 eventos > 16 ms (aproximación, ver checklist) |
| A14 | ✅ | 123 MB frente a 153 MB (0,80 ×) |
| A15 | ✅ | 13,5:1 sobre el escritorio actual; 5,25:1 sobre blanco |
| A16 | ⏳ | Requiere a Simón |

Pruebas automáticas al cierre: `SmaltiCore` 28, `GhosttyAdapter` 20 y XCUITest 10, todas en verde. Mutation testing de `SmaltiCore` con `scripts/mutation/mutate.py`: 100 % (12 muertos, 0 sobrevivientes, 3 inválidos de 15). El mutador detecta un sobreviviente al quitar una prueba.

## Preguntas técnicas

1. **Zig.** v1.4.0 exige `minimum_zig_version = 0.17.0`; Homebrew da 0.17.1 y compila. El script lo verifica antes de compilar. Además hace falta `-Demit-macos-app=false` (si no, intenta compilar Ghostty.app) y el Metal Toolchain.
2. **API usada.** Lista cerrada de funciones (29):
   - App: `ghostty_init`, `ghostty_app_new`, `ghostty_app_free`, `ghostty_app_tick`, `ghostty_app_set_focus`, `ghostty_app_keyboard_changed`.
   - Config: `ghostty_config_new`, `ghostty_config_load_file`, `ghostty_config_finalize`, `ghostty_config_free`, `ghostty_config_diagnostics_count`, `ghostty_config_get_diagnostic`.
   - Superficie: `ghostty_surface_config_new`, `ghostty_surface_new`, `ghostty_surface_free`, `ghostty_surface_userdata`, `ghostty_surface_set_size`, `ghostty_surface_set_content_scale`, `ghostty_surface_set_focus`, `ghostty_surface_key`, `ghostty_surface_key_is_binding`, `ghostty_surface_key_translation_mods`, `ghostty_surface_preedit`, `ghostty_surface_ime_point`, `ghostty_surface_mouse_button`, `ghostty_surface_mouse_pos`, `ghostty_surface_mouse_scroll`.
   - Portapapeles: `ghostty_surface_complete_clipboard_request`, `ghostty_surface_deny_clipboard_request`.
3. **Fondo transparente.** `background-opacity = 0` funciona. El contenedor pinta el panel (`rgba(6,7,10,0.34)`) sobre el vidrio de la ventana. Con salida masiva no hay bloqueos medibles; el coste en batería no se midió.
4. **Desenfoque.** `CGSSetWindowBackgroundBlurRadius` por `dlsym` funciona con radio exacto (28 px), con `NSVisualEffectView` como respaldo. La saturación del 150 % del diseño no se puede conseguir con esa API.
5. **Integración de shell.** Se inyecta sola en zsh sin tocar `.zshrc`, también con un `ZDOTDIR` propio: libghostty guarda el original y lo restaura.
6. **Proceso en primer plano.** `ghostty_surface_foreground_pid` devuelve el grupo de procesos en primer plano (`tcgetpgrp`). En zsh interactivo cada trabajo es líder de su grupo, así que sirve para la cabecera de F1 (nombre con `proc_name`). El fd del PTY no se expone.
7. **Dibujar sobre el prompt (F4/F5).** Viable, pero con cambios. Hay posición del cursor (`ghostty_surface_ime_point`), tamaño de celda y fin de comando, pero **no** inicio de prompt (OSC 133;A/B). El estado "en el prompt" debe llegar por hooks propios del shell (precmd/preexec → `smalti event` por el IPC de F2). Es el principal riesgo para F4: sincronizar el overlay con el redibujado.

## Hallazgos que cambian decisiones de diseño o de proceso

- **Callbacks de libghostty fuera del hilo principal.** `wakeup` y `action` llegan desde el hilo del renderer. En Swift 6, un closure creado dentro de un `init` `@MainActor` hereda el aislamiento y aborta. Los callbacks se crean en una función `nonisolated` y las acciones se entregan en el main a vistas vivas. Nota global del KB.
- **Texto de tecla.** Los caracteres de control no deben enviarse como texto; libghostty los codifica por keycode (igual que `String.keyEventText` de Ghostty).
- **Pruebas y tmux del usuario.** El `.zshrc` de Simón engancha todo shell interactivo a `tmux main`. Las pruebas automáticas usan `-SmaltiShellCommand "/bin/zsh -f"`. F1 debe convertir ese override en `[shell] command` de `config.toml`. Nota del KB del proyecto.
- **XCUITest y el layout Latin American.** XCUITest sintetiza el espacio como ⌃Espacio; las pruebas no teclean espacios. Nota global del KB.
- **Fuente.** JetBrains Mono no está instalada en el sistema; libghostty usa su copia embebida y deja un aviso en el log. Para F5 conviene empaquetar JetBrains Mono e Inter en la app.

## Desviaciones del diseño

| Desviación | Motivo | Cuándo se revisa |
| --- | --- | --- |
| Sin saturación del 150 % en el vidrio | La API privada de desenfoque no la ofrece | F5 (apariencia) |
| Sombra del sistema en vez de `0 30px 90px rgba(0,0,0,0.5)` | macOS calcula la sombra de la ventana | F5 |
| `⌘1…⌘9` en vez de `⌥1…⌥9` (cabecera de F1) | ⌥ escribe caracteres en el layout Latin American | Decidido en la spec de F1 |
| Contraste sobre fondo blanco 5,25:1, cerca del mínimo | Vidrio al 62 % | F5 ("Proteger legibilidad") |

## Riesgos que quedan

| Fase | Riesgo |
| --- | --- |
| F1 | Varias superficies Metal reacomodándose a la vez; medir con 4 y 9 paneles |
| F2 | El estado de prompt y de agente depende del IPC y de hooks, no de libghostty |
| F4 | Overlay del editor de input sin evento de inicio de prompt (pregunta 7) |
| F7 | `smaltid` dueño de los PTY choca con que libghostty sea dueño del PTY y del proceso |
| Proceso | Mutation testing: Muter v16 no funciona con SwiftPM + Swift Testing (issue #321). Lo reemplaza `scripts/mutation/mutate.py`; todavía no cubre paquetes con dependencias relativas (`GhosttyAdapter`) |

## Pendientes para el cierre formal (Simón, unos 15 min)

1. A16: diez minutos escribiendo y usando Claude en Smalti y en Ghostty, sin saber cuál es cuál.
2. Con el teclado físico: espacios, `´` + `a` → `á`, `¨` + `u` → `ü`, ⌥ + teclas (@, |, #), ⌃C, ⌃R, ⌘C tras seleccionar con el ratón.
3. Claude Code: prompt de permiso con flechas, redimensionar durante el streaming, `/help`, scroll del historial.
4. nvim con ratón y pegado multilínea (no debe ejecutarse línea a línea).
5. Si hay un segundo monitor: mover la ventana y comprobar que el texto siga nítido.

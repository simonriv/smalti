# F1 · Tiling y workspaces — verificación

2026-11-22 · Rama `feature/f1-tiling` · Spec `docs/specs/F1-tiling.md` · Plan `docs/plans/F1-tiling.md` · Evidencia `docs/specs/F1-assets/`

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| B1 | ✅ | `LayoutStrategyTests`: árbol correcto para 1…9 paneles en las 3 estrategias; con 3 paneles, Dwindle 746,81 / 553,19 (1,35 : 1), Maestro 387,26 / 336,74 de alto (1,15 : 1), Columnas 430,67 × 3; margen 10, separación 8 |
| B2 | ✅ | `WorkspaceInvariantTests`: 500 operaciones aleatorias, semilla `0x5A17`, invariantes de árbol, orden y foco en cada paso |
| B3 | ✅ | `LayoutTreeEditingTests`: mínimo 240 × 120, límites de `Ratio`; igualar deja hojas del mismo tamaño en cada eje |
| B4 | ✅ | `LayoutTreeEditingTests`: vecino geométrico en las 4 direcciones, sin vecino → nada, desempates independientes del orden |
| B5 | ✅ | Todos los casos de uso con `FakeTerminalEngine` / `InMemoryConfigStore`; `ConfigStoreContract` pasa con el fake y con `TOMLConfigStore` |
| B6 | ✅ | `TOMLConfigParserTests` (55): valores por defecto sin archivo; un archivo inválido conserva la configuración previa y da archivo, línea y clave |
| B7 | ✅ | `fuzzyMatch("lay")` → los 3 layouts primero; la paleta abre en **21–32 ms** (8 aperturas, signpost `palette.open` con Instruments, build Release; antes de virtualizar las filas, 41–53 ms); navegación solo con teclado en `CommandPaletteTests` |
| B8 | ✅ con nota | Ver "Rendimiento". Escribir no bloquea el hilo principal más de 16 ms con 4 ni con 9 superficies; cada reacomodo cuesta un fotograma de ~20 ms |
| B9 | ✅ automatizado | `WorkspaceTests.testWorkspaceSwitchKeepsProcessesAlive`: `sleep 4; <<<listo>…` termina mientras otro workspace está visible (archivo marcador en lugar de `say`) |
| B10 | ✅ con desviaciones | Capturas superpuestas al 50 % sobre los tableros renderizados con Chrome a 1440 × 900: `b10-dwindle-overlay.png`, `b10-columns-overlay.png`, `b10-master-overlay.png`, `b10-palette-overlay.png`. Bordes, cabeceras, franja, barra de estado y paleta coinciden a 1–2 px |
| B11 | ⏳ teclado físico | Con entrada sintetizada: ⌥ nunca forma atajo (`KeyRoutingTests`, `KeyChordTranslatorTests`), ⇧⌘0 → igualar en el layout Latin American; falta la lista manual con teclado físico (abajo) |
| B12 | ✅ | `ImportGuardTests` (SmaltiCore) y `TOMLAdapterGuardTests`: solo `TOMLConfigAdapter` importa TOMLDecoder; la guarda comprueba que escanea `App/` |
| B13 | ✅ | `ChildEnvironmentTests`: `$SMALTI` = 1 en dos paneles; `tmux list-clients` igual antes y después (dentro de la prueba cuando el runner llega al servidor tmux y desde el shell en todas las corridas) |
| B14 | ✅ | `TilingTests.testHeaderShowsForegroundProcess`: la cabecera dice `cat` y vuelve a `zsh` |
| B15 | ✅ | `TilingTests` (salida y ⌘W cierran una sola vez, el último panel deja el workspace vacío y la ventana abierta) y `TerminalPaneTests.testShellThatFailsToStartIsReportedInTheStatusBar` |
| B16 | ✅ | `GhosttyConfigTextTests` (`keybind = clear` + ⌘C/⌘V) y `TilingTests.testCmdKAndCmd1ReachSmaltiNotTheTerminal` |
| B17 | ✅ | `PasteboardGuard` en todas las UI tests; comprobado con texto + HTML en el portapapeles antes de las suites: vuelven intactos |

Pruebas al cierre: `SmaltiCore` 300, `GhosttyAdapter` 73, `TOMLConfigAdapter` 55, XCUITest 30 (MainWindow 5, TerminalPane 8, Tiling 6, Workspace 2, ChildEnvironment 1, CommandPalette 8).

## Rendimiento (B8)

Build Release, MacBook Air M4. Salida continua simulada (~50 líneas/s por panel, `stream.sh`) en **todos** los paneles, más exigente que "3 de 4"; las sesiones reales de Claude no se pueden lanzar sin supervisión. Sonda del hilo principal `-SmaltiLatencyProbe` (temporizador de 5 ms; cuenta los retrasos de más de 16 ms con su instante). GPU: `ioreg` `Device Utilization %` del sistema, media de 10 muestras.

| Medición | 4 superficies | 9 superficies |
| --- | --- | --- |
| Retrasos > 16 ms al escribir 20 s | **0** | **0** |
| Retraso al reacomodar (3 cambios de layout) | 19,7 / 20,5 / 21,3 ms | 18,6 / 17,7 ms (uno bajo 16) |
| Retraso al abrir cada panel | ~20 ms | 19–38 ms |
| Memoria (`footprint`), con salida | 186–197 MB | 209 MB |
| GPU con salida continua visible | 63 % | 75 % |

| Comparación en reposo, 9 paneles `zsh -f` | Smalti | Ghostty.app 1.4.0 (9 splits) |
| --- | --- | --- |
| Memoria | 163 MB | 255 MB (Smalti 0,64 ×) ✅ |
| GPU del sistema | 26 % | 3 % ❌ ver issue #5 |

| Oclusión (c), 9 paneles con salida continua | GPU |
| --- | --- |
| Visibles | 75 % |
| En un workspace oculto (`ghostty_surface_set_occlusion`) | 26 % (= reposo de la ventana) |

**Hallazgo heredado de F0 (issue #5):** con Smalti abierto en reposo la GPU del sistema sube de ~5 % a ~25 %, también sin superficies, sin desenfoque y en el build de F0; Ghostty con vidrio se queda en ~3 % y la CPU de Smalti está a 0. Simón decidió registrarlo y estudiarlo en F5.

## Desviaciones del diseño

| Desviación | Motivo |
| --- | --- |
| `⌘1…⌘9` en la cabecera en lugar de `⌥1…⌥9` | ⌥ escribe caracteres en el layout Latin American (decidido en la spec) |
| Punto neutro `#565c68` casi invisible sobre la pastilla activa | La spec fija el punto neutro en F1; F2 lo colorea por estado |
| Contadores de la franja, rama de git, `ctx`, modelo y lado derecho de la barra de estado ausentes | F2–F5 |
| Pie de la paleta sin "⌘↵ en panel nuevo" | Ningún comando de F1 se ejecuta en un panel |
| Desenfoque de la paleta con `NSVisualEffectView` (`.hudWindow`) | El radio exacto de 36 pt solo existe para ventanas completas (API privada) |
| Comandos sin icono en el tablero dejan la columna del icono vacía | No hay icono que copiar |
| Estado vacío del workspace y error de tamaño mínimo | No están en los tableros; textos y estilo decididos por Simón (2026-11-22) |
| Atajos ⌘1…⌘9 y ⌃1…⌃9 no se repiten al mantenerlos; solo foco y tamaño direccionales se repiten | Evita cerrar o crear paneles en ráfaga |
| El router de teclado actúa en la ventana, no en cada panel | No depende del primer respondedor; intercepta antes del menú y de la superficie |
| Inter se registra en tiempo de ejecución (`CTFontManager`) en lugar de `ATSApplicationFontsPath` | Equivalente y deja el fallo en el log |

## Pendiente para Simón (teclado físico, B11)

1. En un panel, con el layout Latin American: ⌥Q (`@`), ⌥1 (`|`), ⌥3 (`#`) y ⌥+teclas varias llegan al shell y a Claude Code.
2. `´` + vocal y `¨` + `u` componen; durante la composición ⌘1 no cambia de panel.
3. ⇧⌘0 iguala tamaños; mantener ⌃⌥⌘→ redimensiona de forma continua; mantener ⌘W cierra un solo panel.
4. Opcional: repetir B8 con 3 sesiones reales de Claude en streaming (`-SmaltiLatencyProbe /tmp/probe.json`, salir con ⌘Q y leer el JSON).

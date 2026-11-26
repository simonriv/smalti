# Progress

## Fundación del proyecto (2026-11-22)

- [x] Roadmap F0–F7 (`docs/ROADMAP.md`)
- [x] Spec F0 (`docs/specs/F0-spike.md`)
- [x] Spec F1 (`docs/specs/F1-tiling.md`)
- [x] Convenciones del proyecto (`CLAUDE.md`)
- [x] Simón responde las preguntas previas a F0 (recomendaciones aceptadas) y aprueba las specs

## F0 · Spike del motor

### Spec
- [x] Aprobada (2026-11-22)

### Plan
- [x] Plan de implementación (`docs/plans/F0-spike.md`), aprobado

### Tareas
- [x] T1 · Esqueleto, `SmaltiCore` y guarda de imports
- [x] T2 · Dominio del panel y tema Obsidiana
- [x] T3 · Puerto `TerminalEngine`, `OpenPane` y fake
- [x] T4 · Ghostty v1.4.0 fijado y build de GhosttyKit
- [x] T5 · `GhosttyAdapter`: config, acciones y tamaños
- [x] T6 · App de Xcode con ventana de vidrio
- [x] T7 · Terminal viva tras `TerminalEngine`
- [x] T8 · Lista de render, mediciones y pregunta técnica 7
- [x] T9 · Informe del spike (`docs/specs/F0-spike-report.md`); Muter reemplazado por `scripts/mutation/mutate.py` (100 % en SmaltiCore)
- [x] Revisión final de la rama: 4 importantes y 12 menores corregidos
- [x] F0 cerrado (2026-11-22); pruebas manuales descartadas por Simón

## F1 · Tiling y workspaces

### Spec
- [x] Aprobada (2026-11-22); se revisa con el informe de F0
- [x] Revisada con el informe de F0: ajustes R1–R10 aprobados; requisito de cmux descartado (2026-11-22)

### Plan
- [x] Plan de implementación (`docs/plans/F1-tiling.md`), aprobado (2026-11-22)

### Tareas
- [x] T1 · Geometría y `Ratio`
- [x] T2 · `LayoutTree`: frames e igualar
- [x] T3 · `LayoutTree`: redimensionar, intercambiar y vecino
- [x] T4 · Estrategias de layout y catálogo
- [x] T5 · `Pane` ampliado y `Workspace`
- [x] T6 · `WorkspaceSet`
- [x] T7 · Config, atajos, `ConfigStore`, contrato y tokens
- [x] T8 · Comandos y búsqueda difusa
- [x] T9 · Abrir, cerrar y salida de paneles
- [x] T10 · Casos de uso de distribución y workspaces
- [x] T11 · `ReloadConfig` y `SearchCommands`
- [x] T12 · `TOMLConfigAdapter`
- [x] T13 · `GhosttyAdapter` para F1
- [x] T14 · Composition root y rejilla
- [x] T15 · `KeyRouter`, franja, cabecera y barra de estado
- [x] T16 · Paleta ⌘K
- [x] T17 · UI tests de F1
- [x] T18 · Mediciones y capturas (`docs/specs/F1-checklist.md`); paleta virtualizada (B7 21–32 ms); issue #5 GPU en reposo (heredado de F0, a F5)
- [x] Revisión final de la rama: 3 importantes y 10 menores corregidos (M9 sin cambio, decidido); re-revisión: N1 corregido (guarda TMUX)
- [x] Mutación de SmaltiCore 99,2 % (2 sobrevivientes muertos con prueba nueva); SmaltiCore 317, GhosttyAdapter 76, TOMLConfigAdapter 55, XCUITest 35
- [x] PR #7 a `develop` y PR #8 `develop` → `main` (fusionados con confirmación de Simón; Release instalado en `/Applications`)

## F2 · Persistencia e integración con Claude Code

### Spec
- [x] Aprobada (`docs/specs/F2-persistence.md`, 2026-11-22), con el issue #6 como Parte A

### Plan
- [x] Plan de implementación (`docs/plans/F2-persistence.md`), aprobado (2026-11-22)

### Tareas
#### Bloque 1 · Builds `.dev` (PR propio, `feature/f2-dev-builds`)
- [x] T1 · Identidad del build y directorio de estado
- [x] T2 · Pruebas y scripts que nunca tocan el Smalti diario
- [x] T3 · Cierre del bloque 1 y PR de la Parte A (revisión: 2 importantes y 6 menores corregidos; XCUITest 38/38 con el diario intacto)
#### Bloque 2 · Dominio de la persistencia (`feature/f2-persistence`)
- [x] T4 · Instantánea, árbol serializable y tipos del agente
- [x] T5 · `RestorePlan` y selección por defecto
- [x] T6 · Frases de fecha y nombres de layout
- [x] T7 · Puertos y casos de uso de persistencia (revisión del bloque 2: 2 importantes y 6 menores corregidos)
#### Bloque 3 · Adaptadores de persistencia
- [x] T8 · `FileSessionAdapter`
- [x] T9 · Exportar scrollback y leer la línea de comandos
- [x] T10 · Reinyectar scrollback y comando inicial
- [x] T11 · Historial por panel
- [x] T12 · `ClaudeHarnessAdapter` y cableado del guardado (revisión del bloque 3: 2 importantes y 7 menores corregidos)
#### Bloque 4 · Restaurar en la app
- [x] T13 · Arranque con instantánea
- [x] T14 · Pantalla "Retomar donde quedaste"
- [x] T15 · Layouts con nombre y UI tests de restauración (revisión del bloque 4: 3 importantes y 9 menores corregidos)
#### Bloque 5 · Estado del agente, IPC y plugin
- [x] T16 · Transiciones del agente y cola de atención
- [x] T17 · Casos de uso y puertos del agente
- [x] T18 · `IPCAdapter` y CLI `smalti`
- [x] T19 · Plugin de Claude Code e instalador (revisión del bloque 5: 2 importantes y 7 menores corregidos; hook `PreToolUse` añadido)
#### Bloque 6 · Estado y atención en la app
- [x] T20 · Entorno de paneles y cableado del IPC
- [x] T21 · Estado en cabecera, borde y franja
- [x] T22 · Notificaciones y salto ⌘J
- [x] T23 · Arrastrar imágenes
- [x] T24 · UI tests del estado y la atención (ejecutados al cierre: 53/53) · revisión del bloque 6: 1 crítico, 2 importantes y 6 menores corregidos
#### Bloque 7 · Cierre
- [x] T25 · Mediciones (C6: 0,27–0,52 s), checklist (`docs/specs/F2-checklist.md`), revisión final (1 crítico, 3 importantes y 9 menores corregidos), mutación 94,7 % con los 19 sobrevivientes muertos, XCUITest 53/53 con el diario intacto

## F3 · Observatorio

### Spec
- [x] Aprobada (`docs/specs/F3-observatory.md`, 2026-11-22): todas las sesiones de la máquina, sin OTLP (a F7), periodos hoy / 7 / 30 días

### Plan
- [x] Plan de implementación (`docs/plans/F3-observatory.md`)

### Tareas
#### Bloque 0 · Arreglo de la paleta (PR propio, `fix/palette-keeps-selection-visible`)
- [x] T0 · La fila seleccionada de ⌘K siempre se ve entera (PR #17 → develop, #18 → main; revisión: 5 menores corregidos)
#### Bloque 1 · Dominio y configuración (`feature/f3-observatory`)
- [x] T1 · Tokens, catálogo de modelos, costo, contexto y formato
- [x] T2 · Registros del transcript y plegado de la sesión
- [x] T3 · Periodos, sesiones observadas y lo que pinta cada vista
- [x] T4 · Puertos, fakes, contratos, caso de uso y comandos
- [x] T5 · Precios y ventanas en el TOML (revisión del bloque 1: 5 importantes y 7 menores corregidos)
#### Bloque 2 · Adaptadores
- [x] T6 · Fixtures reales y oráculo independiente
- [x] T7 · `ClaudeTranscripts` con índice incremental
- [x] T8 · `ClaudeSessionRegistry`
- [x] T9 · `OllamaAdapter`
- [x] T10 · `DarwinMetricsAdapter` (revisión del bloque 2: 2 importantes y 9 menores corregidos; hallazgo: los forks copian ids)
#### Bloque 3 · App
- [x] T11 · Composición, refresco, barra de estado y cabecera
- [x] T12 · Vista del Observatorio
- [x] T13 · Presentación, teclado y ⌘K
- [x] T14 · UI tests de datos, aislamiento y capturas (revisión del bloque 3: 1 crítico, 6 importantes y 8 menores corregidos)
#### Bloque 4 · Cierre
- [x] T15 · Mediciones (C10 1,3 s / 11 ms / 53 MB; C11 ⚠️ 1 tick de 17,3 ms, igual que en reposo), checklist (`docs/specs/F3-checklist.md`), revisión final (5 importantes y 9 menores corregidos), mutación 100 %, XCUITest 71/71 con el diario intacto

## F4 · Input inteligente

### Spec
- [x] Mini-spike (`spike/f4-prompt-overlay`, desechable): prompt por `needs_confirm_quit` (OSC 133) y fantasma sobre libghostty
- [x] Aprobada (`docs/specs/F4-input.md`, 2026-11-23): zsh edita y Smalti sugiere, input en línea, ⌃R en paleta, historial desde cero, toma de control de plugins

### Plan
- [x] Plan de implementación (`docs/plans/F4-input.md`)

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · Línea de comando y protocolo del canal
- [x] T2 · Historial, filtro de secretos y búsqueda ⌃R
- [x] T3 · Predicción heurística
- [x] T4 · Specs, motor de completions y menú
- [x] T5 · Puertos, fakes, contratos, `InputSession` y `[input]`
#### Bloque 2 · Adaptadores
- [x] T6 · `FileCommandHistory` (JSONL)
- [x] T7 · `ProjectContextAdapter`
- [x] T8 · `FigCompletionAdapter` y vendoring
- [x] T9 · Prompt, cadena de zsh y `-SmaltiUserZdotdir`
#### Bloque 3 · Canal con zsh
- [x] T10 · `InputSocketServer`
- [x] T11 · Script de zsh: canal, fantasma y aceptar
- [x] T12 · ⌃R, Tab y enlaces (enmienda 1: sin toma de control de plugins)
#### Bloque 4 · App
- [x] T13 · `InputCoordinator` y composición
- [x] T14 · Menú de completions
- [x] T15 · Paleta ⌃R y comando de ⌘K
- [x] T16 · UI tests, aislamiento y capturas
#### Bloque 5 · Cierre
- [x] T17 · Mediciones, checklist, revisión final, mutación y PR (checklist `docs/specs/F4-checklist.md`; mutación 98,6 %)

## F4.5 · Ayuda, ventanas y funciones básicas

### Spec
- [x] Auditoría de usabilidad aprobada (`docs/specs/F4.5-auditoria.md`, 2026-11-23): 25 huecos entran en F4.5
- [x] Aprobada (`docs/specs/F4.5-ayuda-ventanas.md`, 2026-11-23): enfoque A de ventanas, menú y ayuda desde el `Keymap`, búsqueda de libghostty, sesión v2

### Plan
- [x] Plan de implementación (`docs/plans/F4.5-ayuda-ventanas.md`)

### Tareas
#### Bloque 1 · Dominio y verificación
- [x] T1 · Verificar la API de libghostty v1.4.0: `search:<texto>`, `navigate_search:next|previous` y `end_search` funcionan; `SEARCH_TOTAL` cuenta también la línea del comando y llega con el tick de la app; `-1` es "sin búsqueda". `select_all`, `clear_screen`, `scroll_*`, `jump_to_prompt:±1` y `*_font_size` aceptados. `read -s` emite `SECURE_INPUT` ON (`macos-auto-secure-input` por defecto). `MOUSE_OVER_LINK` con ⌘ llega en un frame posterior al movimiento. El texto visible ya existía (`accessibilityValue`)
- [x] T2 · Ids nuevos, varios atajos por comando y teclas con nombre (⇧ forma parte del carácter en símbolos: ayuda en ⌘?, ⌘+ en los dos layouts, sin aviso de ⇧⌘=)
- [x] T3 · Ventanas y sesión v2
- [x] T4 · Acciones del terminal, tamaño de letra y confirmar cierre (ocupado = programa en primer plano que no es el shell, sin depender de OSC 133)
- [x] T5 · Catálogo, ayuda y modelo del menú
#### Bloque 2 · Adaptadores
- [x] T6 · Feedback, plantilla del TOML y versión (0.4.5 y commit en el Info.plist)
- [x] T7 · GhosttyAdapter: acciones, búsqueda, texto, eventos y letra (config del motor solo con `keybind = clear` y entrada segura automática)
- [x] T8 · FileSessionAdapter: sesión v2 (lee v1 y v2, guarda v2, aparta versiones desconocidas)
- [x] T9 · DiagnosticsAdapter (OSLogStore del proceso, privados redactados, guarda de logs públicos)
#### Bloque 3 · Ventanas en la app
- [x] T10 · `WindowComposition` (refactor; 64 pruebas de UI de F1–F4 iguales antes y después)
- [x] T11 · Varias ventanas, pantalla completa, Dock y restauración (WindowTests 7/7; regresión de 8 clases en verde)
- [x] T12 · Confirmar antes de cerrar (CloseConfirmationTests 8/8; regresión de 8 clases en verde)
#### Bloque 4 · Descubrimiento y terminal en la app
- [x] T13 · Menú de macOS, contextual y comandos de la app (MenuTests 8/8; capturas f45-menu-*)
- [x] T14 · Ayuda (HelpTests 6/6; captura f45-help.png)
- [x] T15 · Buscar en el scrollback (SearchTests 8/8; captura f45-search.png)
- [x] T16 · Feedback, registros y funciones básicas del terminal (TerminalBasicsTests 8/8, FeedbackTests 4/4; captura f45-feedback.png)
#### Bloque 5 · Cierre
- [x] T17 · Checklist (`docs/specs/F4.5-checklist.md`), revisión final de la rama (6 importantes y 10 menores corregidos, cada uno con su prueba en rojo y en verde), mutación de lo cambiado en F4.5 90,2 % (23 sobrevivientes muertos con prueba nueva); SmaltiCore 1107, GhosttyAdapter 208, TOMLConfigAdapter 80, DiagnosticsAdapter 10
- [x] PR a `develop` (#23) y PR `develop` → `main` (#24) fusionados por Simón; Release 0.4.5 (`81f154d`) instalado en `/Applications` y confirmado (2026-11-23)

## F5 · Apariencia y prompt

### Spec
- [x] Aprobada (`docs/specs/F5-apariencia-prompt.md`, 2026-11-23): prompt generado por Smalti (A), previews a F5.5, `theme.toml`, "Proteger legibilidad" activa sobre el peor escritorio, AppKit, agentes que esperan en vivo, prompt de Smalti por defecto

### Plan
- [x] Plan de implementación (`docs/plans/F5-apariencia-prompt.md`)

### Tareas
#### Bloque 1 · Verificaciones y dominio de apariencia
- [x] T1 · `font-codepoint-map` alcanza una fuente registrada solo para el proceso (captura de la propia ventana: 3565 píxeles con el map frente a 1929 sin él). GPU en reposo (`scripts/measure-gpu-idle.sh`, 3 × 10 s, diario cerrado): base 6,8/5,9 %, por defecto 9,1 %, sin sombra 4,8 %, sin recorte de paneles 9,5 %; sin máscara 20,7 % y sin desenfoque 20,3 % por un pico aislado (las otras muestras, 8–10 %). El desenfoque no es la causa; el ~25 % del issue no aparece en reposo limpio (hipótesis: recomposición del vidrio con contenido que cambia detrás). T13 añade ese escenario y ataca la sombra
- [x] T2 · Contraste WCAG y `LegibilityGuard` (opacidad mínima en pasos de 0,01 y mezcla del 1 %): Obsidiana 65 %, Niebla 82 %, chrome 89 % como en la spec; compuesto en 8 bits
- [x] T3 · Cuatro temas (`ThemeColors` + `Theme.make`), ANSI por tema, `ThemeCatalog.apply` con la protección (colores inalcanzables ajustados sin forzar panel opaco)
- [x] T4 · `PromptConfig`, `WindowButtons`, 8 comandos nuevos, ⌘, Apariencia, ⌥⌘, config.toml, ⇧⌘P Estudio (en ⌘K, ayuda y menú)
#### Bloque 2 · Dominio del prompt
- [x] T5 · Módulos (un tipo por módulo), estilos Limpio/Píldoras/Solo símbolo, `DirectoryLabel`, `PromptHeaderText`, iconos
- [x] T6 · `ZshPromptRenderer`: prompt inmediato con expansiones de zsh y completo con valores en `${_smalti_p_N}` (`%` escapado)
- [x] T7 · Mensajes `context`/`prompt`/`promptstyle`, puerto `PromptFacts`, `RenderPrompt` con reenvío espontáneo
- [x] T8 · `AppearanceStore`, `ChangeAppearance` (300 ms), `EditPrompt` con las tres vistas previas, `StarshipPreset`
#### Bloque 3 · Adaptadores
- [x] T9 · `theme.toml` leído encima de `config.toml` clave a clave (aviso de claves repetidas), escritor atómico que respeta ediciones a mano, `starship.toml` con dorados
- [x] T10 · `FilePromptFacts`: raíz y rama, `git status` con 300 ms y caché, versión de runtime, contexto de k8s; procesos solo en `CommandRunner`
- [x] T11 · Script de zsh del prompt con `psvar` (enmienda 1), hook antes del de Ghostty con marcas OSC 133, input opcional; corregido un fallo de F4 (respuestas junto al EOF)
- [x] T12 · `SmaltiSymbols.ttf` (9 iconos de trazo fino) y lámina `F5-assets/icons-sheet.png` para aprobar
#### Bloque 4 · App: vidrio, temas y ventana
- [x] T13 · GPU en reposo (#5): la causa es la sombra del sistema de una ventana no opaca (WindowServer la recalcula en cada cambio de contenido); sombra propia en una ventana hija: 2,2 % en reposo (antes 29,5 %), 38,5 % con contenido moviéndose detrás (antes 71,1 %). El script activa la app y tapa el escritorio (T1 midió con la ventana detrás de la terminal)
- [x] T14 · Tema en vivo y capas de legibilidad (C2 medido en pantalla con calibración por parches de gris; C12 en dos ventanas)
- [x] T15 · Botones de ventana (ocultos, al pasar el cursor, visibles; cerrar pregunta; Zoom con `performZoom`)
- [x] T16 · Panel Apariencia (revisión del bloque 4: 1 crítico, 4 importantes y 6 menores corregidos; regresión 68/68)
#### Bloque 5 · App: prompt
- [x] T17 · Prompt conectado y contexto en la cabecera (hallazgo: `/usr/bin/git` es el shim de xcrun y nunca llegaba a los 300 ms; `GitLocator`)
- [x] T18 · Estudio de prompt (`KeyContext.panel` para ⌘↑ ⌘↓)
- [x] T19 · Capturas y comparación con los tableros (hallazgo: `SmaltiSymbols` sin nombre PostScript; revisión del bloque 5: 4 importantes y 9 menores corregidos; regresión 72/72)
#### Bloque 6 · Cierre
- [x] T20 · Checklist (`docs/specs/F5-checklist.md`), revisión final (4 importantes y 4 menores corregidos), mutación 99,5 %, XCUITest 191/191 con el diario intacto, C6 2,6 % al cierre, PR y despliegue 0.5.0

## F5.5 · Previews

### Spec
- [x] Spike: libghostty v1.4.0 pinta imágenes kitty en un surface embebido sin cambios (`F5.5-assets/spike-kitty.png`)
- [x] `docs/specs/F5.5-previews.md` aprobada (2026-11-24): miniatura al pasar el cursor, ⌘Y Quick Look, `smalti img`

### Plan
- [x] `docs/plans/F5.5-previews.md`: 14 tareas en 5 bloques

### Tareas
#### Bloque 1 · Puerta y dominio
- [x] T1 · Puerta: arranque de `smalti event Stop` (50 corridas, release, `scripts/measure-cli-startup.sh`): base p50 3,33/3,28 ms; con `SmaltiCore` e ImageIO enlazados 3,50/3,53 ms (+0,2 ms, binario de 138 KB → 3,9 MB). `img` va dentro de `smalti`
- [x] T2 · `ImageFileKind`, `PointerWord` y `PreviewCandidates`
- [x] T3 · Config, ⌘Y, menú, ayuda y token del pie
- [x] T4 · `ImageGrid` y `KittyPlacement`
#### Bloque 2 · Casos de uso y adaptadores
- [x] T5 · Puerto `ImageFiles`, `PreviewCard` y `PreviewUnderPointer`
- [x] T6 · `ImageIOAdapter`
- [x] T7 · Palabra bajo el ratón en `GhosttyAdapter`
#### Bloque 3 · Config, CLI y kitty de terceros
- [x] T8 · `[preview]` en `TOMLConfigAdapter`
- [x] T9 · `ShowImageGrid` y `smalti img`
- [x] T10 · Imágenes kitty de terceros y lista de render
#### Bloque 4 · App
- [x] T11 · Tarjeta de vista previa
- [x] T12 · ⌘Y abre Quick Look
- [x] T13 · Capturas, mediciones y reposo
#### Bloque 5 · Cierre
- [x] T14 · Checklist (`docs/specs/F5.5-checklist.md`), revisión final (3 importantes y 9 menores corregidos), mutación 100 %, XCUITest de la fase 79/79 + 22/22 y 12/12 tras los últimos cambios, versión 0.5.5

## F5.6 · Resaltado del input

### Spec
- [x] `docs/specs/F5.6-resaltado.md` aprobada (2026-11-24): resaltado calculado en Smalti y pintado por zsh, una sola acción de integración en ⌘K, scroll de toda la lista, iconos a la altura de las mayúsculas

### Plan
- [x] `docs/plans/F5.6-resaltado.md`: 14 tareas en 4 bloques

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · `HighlightLexer`
- [x] T2 · `LineHighlighter`, `HighlightSpan` e `isCommand`
- [x] T3 · `PathFacts`, `loadedSpec`, `HighlightCodec` y `HighlightLine`
- [x] T4 · `HighlightPalette`, `[input] highlighting` y estilo
- [x] T5 · `IntegrationState` y catálogo con una sola acción
#### Bloque 2 · Adaptadores
- [x] T6 · `FigSpecs.loadedSpec` e `isCommand`
- [x] T7 · `FileSystemPathFacts`
- [x] T8 · Lado zsh del resaltado
- [x] T9 · Iconos del prompt a la altura de las mayúsculas
- [x] T10 · `ClaudePluginInstaller.installState` y binario configurable
- [x] Revisión intermedia 1 (6 importantes, 8 menores) + mutación incremental (45 sobrevivientes matados y verificados a mano)
#### Bloque 3 · App
- [x] T11 · Resaltado en la app
- [x] T12 · Estado de la integración con Claude en la app
- [x] T13 · Lista de ⌘K con `NSTableView`
- [x] Revisión intermedia 2 (3 importantes, 6 menores) + mutación incremental (22/22)
#### Bloque 4 · Cierre
- [x] T14 · Mediciones (C1 ✅ con enmienda 6 y repetición limpia, B7 17,8–23,9 ms, C12 ⚠️ no atribuible al resaltado), capturas, checklist (`docs/specs/F5.6-checklist.md`), revisión final acotada (2 importantes, 4 menores), mutación de la fase 100 % (328 mutantes), PRs #30 y #31, versión 0.5.6 desplegada

## F6 · Multi-harness y Neovim

### Spec
- [x] Aprobada (2026-11-24, `docs/specs/F6-multi-harness.md`): Gemini CLI fuera, 4 adaptadores, fixtures reales grabados con Ollama (`qwen3:4b`) y la cuenta de Antigravity, captura por disco

### Plan
- [x] Plan de implementación (`docs/plans/F6-multi-harness.md`)

### Tareas
#### Bloque 1 · Spike, fixtures y dominio
- [x] T1 · Spike de reanudación, nombres de proceso y fixtures reales
- [x] T2 · Tipos del multi-harness en el dominio
- [x] T3 · Puerto `HarnessAdapter` ampliado, contrato compartido y fake
- [x] T4 · Captura del ID y `HarnessBinding`
- [x] T5 · Guardar y restaurar con respaldo, y compatibilidad
#### Bloque 2 · Adaptadores de harness
- [x] T6 · `SQLiteReader`
- [x] T7 · `CodexHarnessAdapter`
- [x] T8 · `AntigravityHarnessAdapter`
- [x] T9 · `OpenCodeHarnessAdapter` y `OpenCodeUsage`
- [x] T10 · `ClaudeHarness` completo e integración de reanudación
#### Bloque 3 · Neovim, instalador e IPC
- [x] T11 · `ForegroundProcess` con pid y arranque, `PostToolUse` con archivo
- [x] T12 · Dominio de Neovim y `NeovimAdapter`
- [x] T13 · Catálogo de integraciones, instalador de claudecode.nvim y prueba del diff (C3)
- [x] Revisión intermedia 1 (1 crítico, 4 importantes, 12 menores; corregidos salvo M11, por decisión) + mutación incremental (96,7 %; 5 sobrevivientes matados y verificados a mano)
#### Bloque 4 · App
- [x] T14 · Composition root, flags y captura en vivo
- [x] T15 · Buscador como tarjeta propia (⌘⇧O)
- [x] T16 · Columna del buscador en «Retomar»
- [x] T17 · Neovim en la app
- [x] T18 · Observatorio con filtros y filas de OpenCode
- [x] T19 · Restaurar nvim, `--ide` e integraciones en ⌘K
- [x] Revisión intermedia 2 + mutación incremental (10 importantes y 9 menores corregidos; mutación 95,9 %, 9 sobrevivientes muertos)
#### Bloque 5 · Cierre
- [x] T20 · Mediciones, capturas, checklist y revisión final (C7 p95 53,6 ms; revisión final: 1 crítico, 2 importantes y 6 menores corregidos; mutación completa 99,9 %)
- [x] T21 · Limpieza (modelo, Codex, OpenCode y Ollama desinstalados; grabaciones crudas borradas), 0.6.0, PRs y despliegue

## F7 · Extras

### Spec
- [x] Aprobada (2026-11-25, `docs/specs/F7-extras.md`): layouts compartibles en JSON portátil y receptor OTLP en 127.0.0.1 con solo logs `http/json`; Simón aprobó de antemano spec, plan y recomendaciones

### Plan
- [x] Plan de implementación (`docs/plans/F7-extras.md`)

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · `SharedLayout`
- [x] T2 · `ExportLayout`, `ImportLayout`, `LayoutFiles` y ⌘K
- [x] T3 · Dominio de la telemetría
- [x] T4 · `[extras]`, puertos, `CollectTelemetry`, entorno y Observatorio
#### Bloque 2 · Adaptadores
- [x] T5 · `OTLPReceiverAdapter`: socket y HTTP
- [x] T6 · `OTLPLogsDecoder`
- [x] T7 · `ClaudeSettingsTelemetryCheck` y `SharedLayoutFiles`
- [x] Revisión intermedia 1 (3 críticos, 6 importantes, 8 menores; corregidos, I5 como enmienda) + mutación incremental (97,4 %; 4 sobrevivientes muertos y verificados a mano)
#### Bloque 3 · App
- [x] T8 · Telemetría en la app y emisor falso
- [x] T9 · Exportar e importar layouts en la app
- [x] T10 · Guardas y documentos
- [x] Revisión intermedia 2 (0 críticos, 2 importantes, 9 menores; corregidos, I1 como enmienda 7) + regresión de UI (64/65 → 13/13 tras la tanda; 2 pruebas viejas rotas desde F6 arregladas) + mutación incremental (100 %, 107 mutantes)
#### Bloque 4 · Cierre
- [x] T11 · Mediciones (C2 ✅: A12/A14 sin cambio, GPU alternada 9,18/8,65/8,28 %, C1 independiente, C13 sin empeorar), capturas, checklist (`docs/specs/F7-checklist.md`), revisión final (2 importantes, 3 menores, corregidos), mutación de la fase 97,8 % (4 sobrevivientes muertos y verificados a mano; completa detenida por decisión de Simón)
- [x] T12 · 0.7.0, PRs #37 y #38, despliegue (0.6.0 en `/Applications/Smalti.app.old`)

## F7.5 · Guardas para agentes

### Spec
- [x] Aprobada (2026-11-25, `docs/specs/F7.5-guardas.md`): guardia en el CLI con reglas de `SmaltiCore`, aprobación nativa, falla cerrado en tres capas (`onFailure: "block"`, CLI, app); PocketOS cubierto por la regla de APIs de proveedores; Simón aprobó de antemano spec, plan, recomendaciones, merges y despliegue

### Plan
- [x] Plan de implementación (`docs/plans/F7.5-guardas.md`)

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · `ShellCommandLine`
- [x] T2 · `SecretPaths` y reglas de secretos
- [x] T3 · Reglas destructivas, entorno y redacción
- [x] T4 · `ScreenToolUse` y `[guards]`
- [x] T5 · `AgentApprovals` y estado del panel
- [x] T6 · `ProtectProjectSecrets`, integración desactualizada y ⌘K
#### Bloque 2 · Adaptadores
- [x] T7 · Protocolo `guard`, servidor y CLI
- [x] T8 · `ClaudeProjectPermissions`, versión del plugin y `[guards]` en TOML
- [x] Revisión intermedia 1 + mutación incremental
#### Bloque 3 · App
- [x] T9 · Aprobaciones en la app
- [x] T10 · Proteger secretos, integración desactualizada y documentos
- [x] Revisión intermedia 2 + regresión de UI + mutación incremental
#### Bloque 4 · Cierre
- [x] T11 · Mediciones, capturas, checklist, revisión final y mutación de la fase
- [x] T12 · 0.7.5, PRs y despliegue (#41, #42; instalada el 2026-11-25, la 0.7.0 en `/Applications/Smalti.app.old`; web smalti-web #5)

## F7.6 · Distribución y actualizaciones

### Spec
- [x] Aprobada (2026-11-25, `docs/specs/F7.6-distribucion.md`): spike de Sparkle 2.10.1 con firma ad hoc (actualiza sin Gatekeeper, rechaza EdDSA ajena, falla si la app está trasladada), Homebrew 7 pone cuarentena en taps de terceros, PR limitados a colaboradores por API, deploy keys + workflow en destino en lugar del token; Simón aprobó de antemano spec, plan, recomendaciones, merges y despliegue

### Plan
- [x] Plan de implementación (`docs/plans/F7.6-distribucion.md`)

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · `FormatCompatibility`, sesión y layouts con versión
- [x] T2 · `config.toml`, `theme.toml` e índice del Observatorio
- [x] T3 · Puerto `AppUpdates`, comandos, enlaces y feedback
#### Bloque 2 · Adaptadores
- [x] T4 · `SparkleUpdatesAdapter`
- [x] T5 · `LICENSE` y avisos de terceros
- [x] Revisión intermedia 1 (0 críticos, 2 importantes, 8 menores; corregidos) + mutación incremental (99,1 %; 1 sobreviviente muerto y verificado a mano)
#### Bloque 3 · App, repo y pipeline
- [x] T6 · La app
- [x] T7 · Documentos del repo
- [x] T8 · Scripts de release y workflow
- [x] T9 · Repos satélite
- [x] T10 · Pruebas de instalación y actualización
- [x] Revisión intermedia 2 (1 crítico, 6 importantes, 10 menores; corregidos) + regresión de UI (86/86) + mutación incremental (sin archivos de SmaltiCore nuevos desde la revisión 1)
#### Bloque 4 · Cierre
- [x] T11 · Verificación, capturas y checklist
- [x] T12 · Público, release y despliegue (repo público el 2026-11-25; PRs #43–#48; 0.7.6 instalada, la 0.7.5 en `/Applications/Smalti.app.old`; release `v0.7.6` por el pipeline, appcast smalti-web #8 y cask homebrew-tap #3; web smalti-web #6, #7 y #9)

## F7.7 · Primer uso e inglés

### Spec
- [x] Aprobada (2026-11-25, `docs/specs/F7.7-primer-uso.md`): catálogo Swift puro por área en el dominio + String Catalog en la app (región `en`); spike: con `en`+`es` declarados, app, Sparkle y paneles siguen `AppleLanguages` (hoy todo queda en español); `option_as_meta = "auto"` (libghostty decide por distribución); lazy.nvim con `plugins`; bienvenida por teclado con marca en el estado; Simón aprobó de antemano spec, plan, recomendaciones, merges y release

### Plan
- [x] Plan de implementación (`docs/plans/F7.7-primer-uso.md`)

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · Base del catálogo
- [x] T2 · ⌘K, menús, ayuda, integraciones y enlaces
- [x] T3 · Observatorio, telemetría, tiempos y barra de estado
- [x] T4 · Guardas, cierre, sesiones, layouts, búsqueda y vista previa
- [x] T5 · Prompt, Apariencia, plantilla de config, problemas tipados y `option_as_meta`
- [x] T6 · Bienvenida en el dominio
#### Bloque 2 · Adaptadores
- [x] T7 · Problemas tipados en adaptadores y `option_as_meta`
- [x] T8 · Marca de bienvenida, Neovim con lazy.nvim y CLI
- [x] Revisión intermedia 1 (0 críticos, 2 importantes, 8 menores; corregidos) + mutación 1 (871 mutantes, 99,1 %; 6 sobrevivientes muertos)
#### Bloque 3 · App, CLI y repositorio
- [x] T9 · Base de localización en la app
- [x] T10 · Vistas localizadas y recorrido en inglés
- [x] T11 · Bienvenida y privacidad en la app
- [x] T12 · Release, guarda de red y documentos
- [x] Revisión intermedia 2 (0 críticos, 3 importantes, 10 menores; corregidos) + regresión de UI de las clases afectadas (33/33) + mutación 2 (solo líneas cambiadas: 3 mutantes, 1 sobreviviente muerto). Revisión final y mutación de cierre omitidas por decisión de Simón
#### Bloque 4 · Cierre
- [x] T13 · Verificación, capturas y checklist
- [x] T14 · 0.7.7, release, web y actualización real (PRs #51–#52; release `v0.7.7` por el pipeline, appcast smalti-web #12 y cask homebrew-tap #4; web smalti-web #11; el diario 0.7.6 → 0.7.7 por Sparkle, sin Gatekeeper y con la sesión intacta)

## F8 · Puertos y procesos

### Spec
- [x] Maqueta (`docs/specs/F8-assets/mockup.html`, capturas en/es); Simón dejó el diseño a criterio de Claude
- [x] Aprobada (2026-11-25, `docs/specs/F8-puertos-procesos.md`): libproc + `sysctl` (2–8 ms con 657 procesos, igual que lsof sin sudo), solo procesos propios, atribución por terminal del panel, identidad PID + inicio, SIGTERM → 3 s → confirmación → SIGKILL, *nice* solo hacia abajo; Simón aprobó de antemano spec, plan, recomendaciones, merges, release y despliegue

### Plan
- [x] Plan de implementación (`docs/plans/F8-puertos-procesos.md`)

### Tareas
#### Bloque 1 · Dominio
- [x] T1 · Tipos, CPU y puertos de salida
- [x] T2 · Atribución a paneles, política de detener y prioridad
- [x] T3 · Tablas de procesos y de puertos
- [x] T4 · Detener, bajar prioridad y observar
- [x] T5 · Textos, comandos, atajos y motor
#### Bloque 2 · Adaptadores
- [x] T6 · `DarwinProcessesAdapter`: lectura
- [x] T7 · `DarwinProcessControl` y el motor
- [x] Revisión intermedia 1 (0 críticos, 1 importante, 5 menores; corregidos) + mutación incremental (105 mutantes, 93,8 %; 5 sobrevivientes muertos y verificados a mano)
#### Bloque 3 · App
- [x] T8 · Superposición, refresco y teclado
- [x] T9 · Detener, confirmar, prioridad, avisos e idioma
- [x] T10 · Documentos y web
- [x] Revisión intermedia 2 (0 críticos, 2 importantes, 9 menores; corregidos salvo los valores de accesibilidad en inglés, enmienda 8; el menor 5 no se reproducía y quedó fijado con prueba) + regresión de UI (68/68 de 9 clases) + mutación incremental (21 mutantes, 88,9 %; 2 sobrevivientes muertos y verificados a mano)
#### Bloque 4 · Cierre
- [x] T11 · Mediciones, capturas, checklist, revisión final (0 críticos, 2 importantes, 4 menores; corregidos) y mutación de la fase (132 mutantes, 99,0 %; el sobreviviente muerto y verificado)
- [x] T12 · 0.8.0, PRs, release y despliegue (PRs #55–#56; release `v0.8.0` por el pipeline, appcast smalti-web #14 y cask homebrew-tap #5; web smalti-web #13; el diario 0.7.7 → 0.8.0 por Sparkle, sin Gatekeeper y con la sesión intacta)

## F8.5 · Proyectos

### Spec
- [x] Maqueta (`docs/specs/F8.5-assets/mockup.html`) enviada a Simón (PARA 1); sin respuesta, se sigue con la recomendación (2026-11-26)
- [x] Spec `docs/specs/F8.5-proyectos.md`, aprobada de antemano (2026-11-26)

### Plan
- [x] Plan `docs/plans/F8.5-proyectos.md`, aprobado de antemano (2026-11-26)

### Tareas
- [x] T1 · Formato de proyecto
- [x] T2 · Tipos, puertos, fakes y descubrimiento
- [x] T3 · Recientes, cambios y textos
- [x] T4 · Casos de uso y workspace del proyecto
- [x] T5 · Adaptador de archivos y estado
- [x] Revisión intermedia 1
- [x] T6 · Comandos, atajo, ayuda y menú
- [x] T7 · Selector, confirmación y apertura en la app
- [x] T8 · XCUITest
- [x] T9 · Web y documentos
- [x] Revisión intermedia 2
- [x] Revisión final (2 importantes y 6 menores corregidos), mutación de cierre 98,7 %, mediciones, capturas y checklist (`docs/specs/F8.5-checklist.md`)
- [x] Release 0.8.5 (#59, #60, tag `v0.8.5`, appcast #16, cask #6, docs web #15) y el diario actualizado por Sparkle (2026-11-26)
- [x] F8.5 cerrado (2026-11-26)

## F9 · Timeline de la sesión

### Spec
- [x] Investigación previa: fuentes, panel ↔ sesión, coste (60 MB en 0,37 s), búsqueda (405 MB en 0,8 s), copiar y saltar, punto para F11 y atajo (2026-11-26)
- [x] Fixture real nuevo de Codex con herramientas (`codex-timeline`, Ollama local) (2026-11-26)
- [x] Maqueta (`docs/specs/F9-assets/mockup.html`) enviada a Simón (PARA 1); sin respuesta, se sigue con la recomendación (2026-11-26)
- [x] Spec `docs/specs/F9-timeline.md`, aprobada de antemano (2026-11-26)

### Plan
- [x] Plan `docs/plans/F9-timeline.md`, aprobado de antemano (2026-11-26)

### Tareas
#### Bloque 1 · Base y dominio
- [x] T1 · Paquete `JSONLReader`
- [x] T2 · Oráculo y fixture de imagen
- [x] T3 · Entradas y pliegue en turnos
- [x] T4 · Filas, selección, panel ↔ sesión, búsqueda y política de texto
- [x] T5 · Puertos, fakes, casos de uso y comandos
#### Bloque 2 · Adaptadores
- [x] T6 · `ClaudeTimeline`
- [x] T7 · `CodexTimeline`
- [ ] Revisión intermedia 1 + mutación
#### Bloque 3 · App
- [ ] T8 · Panel lateral, composición y teclado
- [ ] T9 · Desplegar, copiar, búsqueda, respaldo, avisos e idioma
- [ ] T10 · Documentos y web
- [ ] Revisión intermedia 2 + regresión + mutación
#### Bloque 4 · Cierre
- [ ] T11 · Mediciones, capturas, checklist, revisión final
- [ ] T12 · 0.9.0, PRs, release y despliegue

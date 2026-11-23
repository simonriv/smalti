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
- [ ] Plan de implementación (`docs/plans/F4-input.md`)

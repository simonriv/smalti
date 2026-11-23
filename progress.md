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

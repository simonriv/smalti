# F9 · Timeline de la sesión — Checklist de cierre

Spec: `docs/specs/F9-timeline.md` · Plan: `docs/plans/F9-timeline.md` · Fecha: 2026-11-26

## Cómo se verificó

- **Guarda del Smalti diario:** todas las corridas de UI, las capturas y las mediciones pasaron por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID` sacado de `ps -axo pid=,command=`. El diario siguió abierto y con su estado intacto.
- **Datos:** las pruebas usan copias de los fixtures saneados en `-SmaltiClaudeHome`/`-SmaltiCodexHome` temporales (`App/SmaltiUITests/Fixtures/timeline-home.json`, compuesto por `scripts/timeline/compose-ui-fixture.py`). Las mediciones C5, C7 y C8 leyeron el `~/.claude` real solo en lectura (`scripts/measure-timeline.sh`); solo se anotan cifras.
- **Fixture nuevo:** Codex con herramientas grabado con `--oss` (Ollama local, qwen3:4b), sin coste: `record-fixtures.sh codex-timeline`.

## Criterios

| # | Criterio | Resultado |
| --- | --- | --- |
| C1 | Cada turno y salida de los fixtures reales aparece y se copia íntegra | ✅ `TranscriptsContract` contra `timeline_oracle.py` en los 3 transcripts de F6 (Claude), el de F3 con su subagente, el sintético (imágenes, `isMeta`, compactación, prompt en varios bloques, claves `B`/`a`/`_c`), los 2 rollouts de F6 (Codex), el de F9 con herramientas y uno sintético (mensaje en varias partes, `custom_tool_call`, `compacted`): secuencia igual y `fullText` byte a byte; ids únicos; el extracto es el comienzo del texto |
| C2 | El timeline es el de la sesión del panel y cambia con él | ✅ Dominio `TimelineTarget`, `TimelineFocus`; XCUITest `testShowsTheFocusedPanesSessionAndFollowsTheFocus`, vacío y respaldo |
| C3 | Plegar, desplegar y copiar con teclado | ✅ `testExpandsAToolAndCopiesItsOutputAndCallWhole`, `testCopiesALongPromptWhole` (3.000 caracteres) |
| C4 | La búsqueda encuentra una sesión cerrada y salta al turno | ✅ contrato `verifySearch` (Claude y Codex); `testSearchFindsAClosedSessionAndJumpsToTheTurn` (el turno elegido queda visible), `testAHitInTheShownSessionOnlyMovesTheChoice` |
| C5 | Latencia de la búsqueda | ✅ proyecto mayor (446 MB, 136 sesiones), p50 de 5: primer resultado **17 ms**, con el tope de 200 **118 ms**; peor caso sin coincidencias (todo leído) **1,32 s** (objetivos < 300 ms y < 1,5 s) |
| C6 | Sin coste en reposo | ✅ dominio (`closingStopsWatchingAndForgets`, `switchingCancelsTheReadOnItsWay`), adaptador (`stoppingToListenClosesEveryDescriptor`, `FileWatch`); GPU/CPU: ver abajo |
| C7 | Abrir una sesión grande no congela | ✅ transcript mayor (59 MB, 1.470 entradas, 876 filas): lectura + filas **540 ms** fuera del hilo principal (objetivo < 0,6 s) |
| C8 | Memoria acotada | ✅ **+18 MB** con la sesión de 59 MB leída y sus filas (objetivo < 150 MB) |
| C9 | Inglés y español completos | ✅ `LocalizationTests/testEnglishTimelineHasNoSpanish` (sesión, herramienta desplegada, copia, búsqueda, sin coincidencias, vacío, respaldo y sin identificar); `TimelineTexts` en la auditoría; `strings-catalog.test.sh` |
| C10 | Todo con atajo y en ⌘K | ✅ `TimelineCommandsTests` (contextos `.terminal` y `.besideTimeline`); XCUITest `testItsChordsBelongToTheTerminalWhileClosed`, exclusión con Observatorio y procesos |
| C11 | Arquitectura y solo lectura | ✅ guarda de imports; `TranscriptReadOnlyGuardTests`; `network-surface.test.sh`; filas solo desde `TimelineRows` con la política (prueba espía) |
| C12 | Release y actualización real | ver «Release» |

## GPU y CPU en reposo (C6)

PENDIENTE_GPU

## Revisiones y mutación

- Revisión intermedia 1: 0 críticos, 6 importantes, 10 menores; corregidos con prueba RED→GREEN.
- Revisión intermedia 2: 3 críticos, 6 importantes, 8 menores; corregidos, más dos hallados por las pruebas nuevas (clic dentro del terminal y ⌘V con el timeline abierto).
- Mutación 1: 135 mutantes, 76,9 %; 25 sobrevivientes resueltos (21 muertos con prueba verificada a mano, 4 equivalentes quitados). Mutación 2: 136 mutantes, 100 %.
- Revisión final y mutación de cierre: ver abajo.

## Capturas

`docs/specs/F9-assets/f9-{session,search,empty}-{es,en}.png`, junto a las de la maqueta. Diferencias con la maqueta: el punto de la sesión fijada sale del estado de su panel (hueco si está cerrada), «abierta en» o «cerrada · fecha» en la cabecera, y el resumen de búsqueda sin «Buscando… k de n» (enmienda 2).

## Aplazado al uso real

- Sesiones largas reales de Simón con subagentes en vivo y compactaciones mientras el timeline está abierto.
- La sensación de seguir el foco con ⌘1…⌘9 en una jornada de trabajo.

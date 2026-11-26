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
| C5 | Latencia de la búsqueda | ✅ proyecto mayor (446 MB, 136 sesiones), p50 de 5: primer resultado **17 ms**, con el tope de 200 **118 ms**; peor caso sin coincidencias (todo leído) **1,32 s** (objetivos < 300 ms y < 1,5 s). Medido con `TimelineBench` solo sobre Claude Code y confirmando en serie; la app busca a la vez en Codex, cuyo coste no entra en la cifra |
| C6 | Sin coste en reposo | ✅ dominio (`closingStopsWatchingAndForgets`, `switchingCancelsTheReadOnItsWay`), adaptador (`stoppingToListenClosesEveryDescriptor`, `FileWatch`); GPU/CPU: ver abajo |
| C7 | Abrir una sesión grande no congela | ✅ XCUITest `testALargeSessionNeverFreezesTheApp`: transcript sintético de 61 MB (9.000 entradas); ⇧⌘T cierra el timeline mientras lee y al reabrir se muestra la sesión. Banco: transcript real mayor (59 MB) leído y convertido en filas en **540 ms** (la lectura va fuera del hilo principal; el plegado y las filas, en él) |
| C8 | Memoria acotada | ✅ Smalti Dev con la sesión sintética de 61 MB abierta: **138 → 176 MB (+37 MB)**, leído desde el shell de otro panel sin consultas de accesibilidad (objetivo < 150 MB). Bajo las instantáneas de XCUITest, `NSTableView` construye todas las filas (≈1,5 GB): **riesgo** con VoiceOver y una sesión enorme, anotado para después |
| C9 | Inglés y español completos | ✅ `LocalizationTests/testEnglishTimelineHasNoSpanish` (sesión, herramienta desplegada, copia, búsqueda, sin coincidencias, vacío, respaldo y sin identificar); `TimelineTexts` en la auditoría; `strings-catalog.test.sh` |
| C10 | Todo con atajo y en ⌘K | ✅ `TimelineCommandsTests` (contextos `.terminal` y `.besideTimeline`); XCUITest `testItsChordsBelongToTheTerminalWhileClosed`, exclusión con Observatorio y procesos |
| C11 | Arquitectura y solo lectura | ✅ guarda de imports; `TranscriptReadOnlyGuardTests`; `network-surface.test.sh`; filas solo desde `TimelineRows` con la política (prueba espía) |
| C12 | Release y actualización real | ✅ ver «Release» |

## GPU y CPU en reposo (C6)

`scripts/measure-gpu-idle.sh 5` con el timeline cerrado, en esta rama y en un worktree de `origin/develop`, uno detrás de otro el mismo día:

| Corrida | Media GPU | CPU de la app | WindowServer |
| --- | --- | --- | --- |
| F9 (1.ª tanda) | 17,2 % (0,2 % en la 1.ª corrida) | 0,1–0,2 % | 11–33 % |
| develop (1.ª tanda) | 0,4 % | 0,1–0,3 % | 9–14 % |
| F9 (2.ª tanda) | 26,6 % (4,1 % en la 1.ª) | 0,1–0,4 % | 12–36 % |
| develop (2.ª tanda) | 22,8 % (0,2 % en la 1.ª) | 0,2–0,3 % | 9–38 % |

En la segunda tanda, `develop` subió igual que F9 en cuanto pasó la primera corrida. La CPU de la app es idéntica en las dos ramas. Lo que sube es WindowServer, por lo que cambia en pantalla detrás del vidrio (la Mac estaba en uso), no Smalti. Con el timeline cerrado no hay lecturas ni observadores (pruebas de C6 arriba). La medición en reposo con la Mac quieta queda para repetirse en el cierre de F10.

## Revisiones y mutación

- Revisión intermedia 1: 0 críticos, 6 importantes, 10 menores; corregidos con prueba RED→GREEN.
- Revisión intermedia 2: 3 críticos, 6 importantes, 8 menores; corregidos, más dos hallados por las pruebas nuevas (clic dentro del terminal y ⌘V con el timeline abierto).
- Mutación 1: 135 mutantes, 76,9 %; 25 sobrevivientes resueltos (21 muertos con prueba verificada a mano, 4 equivalentes quitados). Mutación 2: 136 mutantes, 100 %.
- Revisión final (Opus, acotada): 0 críticos, 2 importantes (salto a una coincidencia dentro de un subagente; checklist sin respaldo en C7, C8 y las capturas), 7 menores (CRLF, búsqueda pegada al saltar, lectura tras cerrar, búsqueda sin panel enfocado, atajo del encabezado escrito a mano, README, C5 solo Claude). Corregidos en una tanda, con RED→GREEN donde la capa lo permitía: `aSubagentItemKnowsTheToolsAboveIt`, `crlfOutputsSplitIntoLines`, `testAHitInsideASubagentOpensItsCall`, `testTheHeaderShowsTheRemappedChord`. Las tres carreras (M2–M4) quedaron con guardas, sin una prueba de UI que las reproduzca. ⌘C y ⌘F del timeline son fijos (no están en el keymap). Regresión `TimelineTests` + `LocalizationTests/testEnglishTimelineHasNoSpanish`: 17/17.
- Mutación de cierre: por decisión de Simón, solo lo cambiado desde la mutación 2 (`--changed-since e7a84f7`): 5 mutantes, 100 %.

## Capturas

`docs/specs/F9-assets/f9-{session,search,empty}-{es,en}.png`, junto a las de la maqueta. Diferencias con la maqueta: el punto de la sesión fijada sale del estado de su panel (hueco si está cerrada), «abierta en» o «cerrada · fecha» en la cabecera, y el resumen de búsqueda sin «Buscando… k de n» (enmienda 2).

## Aplazado al uso real

- Sesiones largas reales de Simón con subagentes en vivo y compactaciones mientras el timeline está abierto.
- La sensación de seguir el foco con ⌘1…⌘9 en una jornada de trabajo.

## Release

- PR #63 (feature → develop) y #64 (develop → main); tag `v0.9.0` en main; pipeline `release.yml` en verde, con el DMG publicado.
- Appcast (smalti-web #18): versión 900, `length` 19.659.491 igual al DMG. Cask (homebrew-tap #7): sha256 `6327b297…ec5d5`, igual al del DMG descargado. Integrados los dos.
- Web (smalti-web #17): docs del timeline en/es con capturas, botón de GitHub e idioma arriba; `pnpm lint` y `pnpm build` en verde.
- Smalti diario: «Buscar actualizaciones…» por System Events desde una sesión fuera de Smalti → Sparkle → 0.9.0 (900), relanzado sin aviso de Gatekeeper y sin atributo de cuarentena.

# F6 · Multi-harness y Neovim — verificación

2026-11-25 · Rama `feature/f6-multi-harness` · Spec `docs/specs/F6-multi-harness.md` (con las enmiendas 1–2) · Plan `docs/plans/F6-multi-harness.md`

## Cómo se verificó

- **Aislamiento:**
  - las UI tests corrieron con `isolatedSmalti()` (`/bin/zsh -f`, `$TMUX` de guarda) y los flags de F6: `-SmaltiCodexHome`, `-SmaltiAntigravityHome`, `-SmaltiOpenCodeDB`, `-SmaltiNvimConfigHome`, `-SmaltiEditorSocketDir` y `-SmaltiNvimCommand "/opt/homebrew/bin/nvim --clean"`;
  - todas pasaron por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID`, y todas dejaron el Smalti diario corriendo y su estado intacto;
  - las pruebas de adaptadores usan homes temporales y las rutas fijas de fixture `/private/tmp/smalti-fx/<harness>`;
  - ninguna prueba lee `~/.claude`, `~/.codex`, `~/.gemini`, `~/.local/share/opencode` ni `~/.config/nvim` reales (`HarnessIsolationGuardTests`).
- **XCUITest:** solo lo afectado, una corrida a la vez.
  - Primera corrida, tras activar Automation Mode: 14/24.
  - Regresión de la revisión 2: 7 clases de F6 más `SessionRestoreTests`, `ObservatoryTests`, `CommandPaletteTests` y `AgentStatusTests`, 66/73.
  - Los fallos se corrigieron en corridas 3–7, cada uno con su rojo visto: unos en la corrida 1, otros con el código de la app apartado en un stash (`ui-red`, `ui-red2`).
- **Procesos:** tras cada suite de integración y de UI no queda ningún `nvim`, `codex`, `agy`, `opencode` ni daemon de harness.
  - Dos casos necesitaron un arreglo propio: los daemons de Codex y OpenCode se matan buscando la raíz temporal; el nvim ocupado de la prueba de C10 lo mata un proceso desacoplado, porque el runner de XCUITest no puede señalar procesos de la app.
- **Suites unitarias** de los paquetes tocados y `swift format lint --strict`, en verde.

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| C1 | ✅ | `HarnessAdapterContract.verify` sobre fixtures reales saneados: `claudeSatisfiesTheHarnessContract`, `codexSatisfiesTheHarnessContract`, `antigravitySatisfiesTheHarnessContract`, `opencodeSatisfiesTheHarnessContract`; oráculo `fixture_expectations.py` |
| C2 | ✅ | `resumesFixtureWithRealCommand` en los cuatro adaptadores, con el binario real (Codex 0.171 con `--oss` y Ollama `qwen3:4b`, Antigravity 1.5.10, OpenCode 2.3.2, Claude), PTY con `zsh -f` y comprobación de huérfanos. Última corrida verde el 2026-11-25, antes de desinstalar las herramientas; desde entonces se saltan sin el binario |
| C3 | ✅ | `ClaudeDiffProtocolTests.writeAcceptsDiff` (`FILE_SAVED` con el contenido) y `quitRejectsDiff` (`DIFF_REJECTED`), con claudecode.nvim `v0.4.0` vendorizado y `nvim --clean` |
| C4 | ✅ | `Capture harness session`, `Capture interim binding`, `Capture window`, `Pane harness binding` (dominio); `captureReadsOnlyTheProjectFolderOfTheDirectory`, `captureIgnoresTranscriptsBornBeforeTheStart`; `HarnessCaptureTests.testCodexPaneCapturesAndRestoresWithResume` |
| C5 | ✅ | `HarnessRestoreTests`; compatibilidad `session-v2-0.5.6.json`; `RestoreSearchTests.testRowsShowEachHarnessCommand`, `HarnessCaptureTests.testPaneWithoutSessionRestoresWithContinue` |
| C6 | ✅ | `Search harness sessions` (lento y roto no bloquean, cada adaptador tardío manda su listado, cancelar detiene a los lentos), `Session search state`, `Open harness session`; `SessionSearchTests` (11) y `RestoreSearchTests` (6): Tab, Esc devuelve el foco, Enter restaura y abre, chips sin Gemini, ⌘1…⌘5, ←→, ⌘↩ bifurca o avisa, carpeta inexistente → home y aviso |
| C7 | ✅ | `SessionSearchLatencyTests` (a demanda): signpost `harness.search.open` con los cuatro almacenes de fixture, 7 aperturas en Debug: **p50 20,5 ms, p95 53,6 ms** (límite 100 ms). La lectura corre fuera del hilo principal (`SQLiteReader` en tareas desacopladas; `listingReadsOnlyTheNewestTranscripts`) |
| C8 | ✅ | `Edited files`, `Edited files in the palette` (tope 20, más reciente primero, línea o 1, el espacio de trabajo desde un panel sin ediciones); `HookPayloadTranslatorTests`; `fileToolsKeepTheTextTheyWrote` (la CLI reenvía lo que escribió la herramienta); `EditorTests.testEditedFilesGroupListsInjectedEdits` |
| C9 | ✅ | `Editor target`, `Open in editor`; `CommandClickWordTests` (libghostty corta la palabra en «:»); `openPassesHostilePathAsArgument`, `openJumpsToLine`; `EditorTests`: ⌘⇧E, ⌘⇧L desde el agente y desde el propio nvim, el salto enfoca el nvim, ⌘-clic en `ruta:línea` abre nvim, ⌘-clic en un binario no. La URL no tiene E2E (abriría el navegador real; ruling de T17) |
| C10 | ✅ | `currentReturnsFileAndLine`, `currentTimesOutAt`, `EditorCommand.reopen`, `SaveSessionTests` (`editorPositionIsSavedForItsPane`, `editorWithoutPositionKeepsItsProcessRelaunch`); `EditorRestoreTests`: nvim reabre en la línea 150 con su socket; un nvim ocupado en Lua se guarda como proceso |
| C11 | ✅ | `ClaudecodeNvimInstallerTests` (solo su archivo, con marca y `v0.4.0`; desinstalar solo con la marca; fuera de NvChad, desconocido); `IntegrationCatalogTests` (solo la acción que aplica, instalar → desinstalar, nada fuera de NvChad); carga sin red con `prepare-nvim-fixtures.sh` |
| C12 | ✅ | `ObservatoryFilterTests` de dominio (filtros, resumen recalculado, «OpenCode · qwen3:4b local», «—» en vida, caché con lecturas de OpenCode, pie); `OpenCodeUsage`; `ObservatoryFilterTests` de UI (chips y ⌘⇧F) |
| C13 | ✅ | `SQLiteReaderTests` (WAL con escritor, base bloqueada, sin permiso de escritura, Unicode y espacios); `malformedWorkspaceUrisOmitsRow`, `malformedMessageJsonKeepsRowWithoutModel`, `oneXSchemaIsUnknownSchema`, `malformedTranscriptIsSkipped` |
| C14 | ✅ | `HarnessIsolationGuardTests`; `isolatedSmalti()` con los flags nuevos; `check-daily-untouched.sh` en cada corrida de UI |
| C15 | ✅ | `Import guard` (SmaltiCore en Swift puro), guarda de `SQLite3` solo en `SQLiteReader`, guarda de `Logger` de F4.5; el único registro nuevo con texto (`harness usage unreadable`) es `.private` |
| C16 | ✅ | Comprobación de huérfanos al final de cada integración (`PtyResume` busca la raíz temporal en la línea de comandos y el entorno) y `ps` tras cada corrida |
| C17 | ✅ | Mutación completa de SmaltiCore al cierre: **99,9 %** (1861 mutantes, 2 sobrevivientes muertos). Ver «Mutación» |

## Capturas junto a los tableros

- `c-search-card-side-by-side.png`: la tarjeta ⌘⇧O junto a `Reanudar.dc.html`.
- `c-restore-column-side-by-side.png`: «Retomar» con la columna del buscador junto a `Reanudar.dc.html`.
- `c-observatory-filters-side-by-side.png`: los chips del Observatorio junto a `Observatorio.dc.html`.
- `f6-edited-files.png`: ⌘K con «Editados por Claude».
- Diferencias justificadas:
  - sin el chip ni las filas de Gemini (fuera de la fase, `docs/design/README.md`);
  - los datos son los de los fixtures;
  - el aviso «No se pudo leer Claude Code» sale porque el home de Claude de la prueba no tiene `projects/`: es el error tipado de C13 a la vista.
- Se componen con `F6-assets/compose-boards.py` sobre los tableros renderizados con Chrome headless.

## Revisiones

- **Intermedia 1** (dominio y adaptadores): 1 crítico, 4 importantes y 12 menores. Todos corregidos con su prueba RED→GREEN, salvo M11, que quedó como ruling (un login de Antigravity caducado falla con un mensaje claro).
- **Intermedia 2** (la app): 10 importantes y 9 menores, todos corregidos.
  - Además apareció un bug propio: la CLI `smalti event` descartaba lo que escribía la herramienta, así que la línea siempre salía 1.
  - Y libghostty corta la palabra del ⌘-clic en «:».
- **Final** (revisor nuevo, modelo más capaz, acotada): 1 crítico, 2 importantes y 6 menores, todos corregidos en una sola tanda, cada uno con su prueba RED→GREEN. UI afectada: 25/25.
  - **C1:** un panel podía quedarse con la sesión que otro abandonó por competencia. Ahora las sesiones en disputa no las captura nadie.
  - **I1:** un Claude terminado bloqueaba la captura de otro harness en el mismo panel y se guardaba en su lugar.
  - **I2:** el chip lee solo su almacén, y ↩ actúa con el primer listado, sin esperar al almacén más lento.
  - **Menores:**
    - la bifurcación de Claude también lleva `--ide`;
    - la carpeta de proyecto de Claude se nombra como lo hace Claude 2.1.332 (`replace(/[^a-zA-Z0-9]/g, "-")`, con hash pasados 200 caracteres), sobre la ruta real (`realpath`, que conserva `/private`);
    - «Editados por Claude» se ordena por hora;
    - el intervalo del signpost se cierra también al cerrar la tarjeta;
    - la carpeta de sockets debe ser propia y 0700;
    - un nvim restaurado como proceso conserva su socket.

## Mutación

- Intermedia 1: 96,7 %, con los sobrevivientes muertos.
- Intermedia 2 (`--changed-since 3dbff3a`): 301 mutantes, 95,9 %. Los 9 sobrevivientes murieron con pruebas nuevas, verificadas aplicando el mutante a mano.
- Cierre: mutación completa de SmaltiCore, porque la rama cambió código compartido (`PaneSnapshot`, puertos de sesión): 1861 mutantes, 1550 muertos, 309 inválidos, 2 sobrevivientes; **99,9 %**. Los dos murieron con pruebas nuevas, verificadas aplicando el mutante a mano:
  - `SearchHarnessSessions.swift:65` (`==` → `!=`): `fastAdapterDoesNotCancelTheSlowOnes`;
  - `PaneSnapshot.swift:87` (`&&` → `||`): `stoppedAgentInItsProcessIsSavedAsTheAgent`.

## Aplazado (uso real, `.claude/rules/testing.md`)

- Retomar sesiones reales de Codex, Antigravity y OpenCode tras días de uso.
- claudecode.nvim con un `claude --ide` real (C3 usa el protocolo con un cliente de prueba).
- ⌘-clic en una URL abre el navegador.

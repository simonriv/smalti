# F3 · Observatorio — verificación

2026-11-23 · Rama `feature/f3-observatory` (y `fix/palette-keeps-selection-visible`, fusionada en #17 y #18) · Spec `docs/specs/F3-observatory.md` · Plan `docs/plans/F3-observatory.md`

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| C1 | ✅ | `ClaudeTranscriptsTests.realFixturesMatchOracleExactly`. Cuatro sesiones reales de Claude Code 2.1.330 grabadas sin supervisión con `claude -p` y Haiku 5.5 (`scripts/observatory/record-fixtures.sh`): un turno; tres turnos reanudados con `Bash` y `Read`; un subagente; un fork. Entrada, salida, lectura y escritura de caché coinciden exactamente, por sesión y en total, con `scripts/observatory/sum_transcripts.py`, un oráculo en Python que no comparte código con Swift. Hallazgo: `--fork-session` copia los `message.id` de su origen, así que la deduplicación es global y las copias se quedan con el origen, incluso en cadenas de forks (`chainedForksKeepTheirOwnTokens…`) |
| C2 | ✅ | `SessionActivityTests.repeatedMessageCountsOnce`, `repeatedMessageAcrossFoldsCountsOnce`; `ClaudeTranscriptsTests.growingFileCountsRepeatedMessageOnce`; `MessageOwnersTests` |
| C3 | ✅ | `ObservatoryPeriodTests`: medianoche local, 7 días, 30 días cruzando fin de mes, día de cambio de hora en `America/New_York`, zona horaria en cada refresco. `ObservatoryReportTests.sessionCrossingMidnightCountsOnlyTodayBuckets` y `summaryDependsOnTheTimeZoneOfEachRefresh` |
| C4 | ✅ | `partialLastLineIsReadOnNextPass`, `truncatedFileIsReread`, `replacedFileByInodeIsReread`, `corruptIndexIsRebuilt`, `malformedLineIsSkippedAndCounted`, `multiMegabyteLineIsRead` (4 MB), `indexSurvivesRestartWithoutRereading`, `failingIndexWriteIsCounted` |
| C5 | ✅ | `CostEstimateTests` (las cinco tarifas, modelo sin precio que no suma y se anuncia, modelo con 0 tokens que no cuenta), `ModelCatalogTests` (respaldos `[1m]` y de fecha, sobrescrituras), `ObservatoryReaderTests` (TOML con línea del error), `ContextLoad` del último turno principal |
| C6 | ✅ | `ObservedSessionTests` (`busy`/`idle`, estado desconocido, panel que gana sin duplicar), `ClaudeSessionRegistryTests` (PID muerto, PID reutilizado con otro `procStart`, `procStart` o `startedAt` ausentes o ilegibles), contrato `LiveAgentsContract` con `isAlive` |
| C7 | ✅ | `SystemFiguresTests.unavailablePartReadsNoDisponible`, `memorySplitOmitsModelWithoutOllama`; `StatusFiguresTests.statusGpuUnavailableText`; XCUITest `testUnavailableOllamaIsNamedNeverZero` y `testUnpricedModelIsNamedNotCountedAsZero` ("sin precio para 1 modelo") |
| C8 | ✅ | XCUITest `ObservatoryTests`: ⌘⇧A, ⌘K "Abrir observatorio", ↑↓ con el detalle siguiendo la selección, ↵ al panel de la sesión también en otro workspace (comprobado con el `pwd` del panel), ⌘P solo con el Observatorio abierto, esc, clic en una fila, hook con el Observatorio abierto. Fixture en un `claudeHome` temporal; Ollama inalcanzable |
| C9 | ✅ | XCUITest `testStatusBarShowsRamGpuAndTodayTokens` ("hoy 236k tokens") y `testPaneHeaderShowsModelAndContextForHookedSession` (" · haiku", "ctx N%") |
| C10 | ✅ | `scripts/measure-observatory.sh 5`, build release, con los transcripts reales de Simón (solo lectura) y el índice vacío en cada corrida. "Hoy" completo en 1,31–1,39 s (límite 5 s); refresco sin cambios 10,5–11,2 ms en 9 de 10 corridas y 91 ms en una (límite 50 ms); 30 días completos en ~6 s; huella de memoria 50–55 MB. La primera medición dio 1,2 GB por buffers autoliberados sin drenar en el actor: corregido con un autorelease pool por bloque y por línea |
| C11 | ⚠️ | `ObservatoryLatencyTests`, a demanda: 300 sesiones sintéticas × 60 turnos repartidas en 30 días, "30 días" abierto 60 s con la sonda de latencia. Antes: 10 bloqueos de 16–29 ms al ritmo del refresco. Tras construir el informe y las cifras fuera del hilo principal: 1 tick de 17,3 ms en 60 s (unos 30 refrescos). Línea base con el Observatorio cerrado: 1 tick de 17,4 ms en 60 s |
| C12 | ✅ con desviaciones | `DesignCaptureTests.testCaptureObservatory` y `testCaptureStatusAndHeader`, a demanda, superpuestas al 50 % sobre los tableros renderizados con Chrome: `F3-assets/c12-observatory-overlay.png` y `c12-status-header-overlay.png`. Ver "Desviaciones del diseño" |
| C13 | ✅ | Guardas de `SmaltiCore` y de `DarwinMetricsAdapter` (IOKit). `ClaudeSessionRegistryTests.keyFilesAreNeverRead`: un `*.key` con un JSON de sesión viva válido no aparece |
| C14 | ✅ | `isolatedSmalti()` pasa `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiConfigPath`, `-SmaltiStatePath`, `-SmaltiClaudeHome` y `-SmaltiOllamaURL` temporales; `PasteboardGuard`; suite completa con `scripts/check-daily-untouched.sh`. El PID del diario siguió vivo en todas las corridas; los cambios de su estado fueron solo su guardado periódico de 5 minutos, porque esta sesión corría en un panel del diario |
| C15 | (al cierre) | Mutación de `SmaltiCore` |

Pruebas: SmaltiCore 677, GhosttyAdapter 121, TOMLConfigAdapter 66, FileSessionAdapter 17, ClaudeHarnessAdapter 20, IPCAdapter 24, UserNotificationsAdapter 7, ClaudeTelemetryAdapter 42, OllamaAdapter 11, DarwinMetricsAdapter 13; Python: oráculo y saneador OK, mutador OK; XCUITest 71 + 4 capturas y 1 medición a demanda.

## Desviaciones del diseño

| Desviación | Motivo |
| --- | --- |
| Sin filtros por harness ("Todas", "Claude Code", "OpenCode", "Locales") ni fila de OpenCode | F6 (decisión de la spec) |
| Sin tok/s de Ollama | Su API no lo da sin generar (decisión de la spec) |
| "descargado hace 2 días" en lugar de "última vez hace 2 días" | Ollama solo guarda la fecha de descarga |
| En las filas detenidas, "hace 5 min" se trunca en la columna Vida de 76 pt | El tablero solo muestra "hace 3h", que cabe |
| El vidrio del Observatorio es el de la ventana (0,62); el tablero dibuja 0,72 | Un solo vidrio por ventana |
| La curva de CPU necesita dos muestras antes de dibujarse | Es una diferencia entre dos lecturas de ticks |
| La tabla muestra hasta 5 filas antes de desplazarse; el tablero tiene 4 | Los datos del fixture tienen 6 sesiones |
| Memoria en unidades binarias con la etiqueta "GB" (RAM, reparto, Ollama) | Como macOS y el Monitor de Actividad |

## Aplazado a la app terminada

- Uso diario con sesiones reales de varios días (los periodos de 7 y 30 días se prueban con fixtures y con el historial real de Simón en C10).

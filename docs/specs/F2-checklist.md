# F2 · Persistencia e integración con Claude Code — verificación

2026-11-22 · Ramas `feature/f2-dev-builds` (fusionada, #11 y #12) y `feature/f2-persistence` · Spec `docs/specs/F2-persistence.md` · Plan `docs/plans/F2-persistence.md`

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| C1 | ✅ | `scripts/check-daily-untouched.sh` sobre la suite completa de XCUITest: 38/38 (bloque 1), 47/47 (bloque 4) y 53/53 al cierre (más 2 capturas a demanda). El Smalti diario (PID 5609) siguió vivo y su directorio de estado no cambió en ninguna corrida, tampoco en la medición de C6 |
| C2 | ✅ | `scripts/tests/build-identity.test.sh` 6/6: bundle ID, `CFBundleName` y nombre visible de Debug ("Smalti Dev", `dev.simonriv.smalti.dev`) y de Release |
| C3 | ✅ | `SessionSnapshotTests`, `SnapshotTreeTests`, `RestorePlanTests` y `RestoreSessionTests` con 0, 1 y 9 paneles; contrato `SessionArchiveContract` con el fake y con `FileSessionArchive` |
| C4 | ✅ | `RestorePlanTests`: paneles desmarcados, workspaces vacíos, `.layoutsOnly`, árbol descartado y foco recolocado |
| C5 | ✅ | `FileSessionArchiveTests`: `corruptSnapshotIsMovedAsideAndReported`, `unknownVersionIsMovedAside` e `interruptedWriteKeepsPreviousSnapshot` |
| C6 | ✅ | `scripts/measure-restore.sh 5` con Release, 3 workspaces, 6 paneles y 10.000 líneas cada uno: 0,27–0,52 s (peor caso 0,52 s, criterio < 5 s). Control: con un shell que tarda 2 s en arrancar mide 2,31 s, así que el fin del signpost espera de verdad al primer prompt |
| C7 | ✅ | Adaptador: `exportReturnsVTWithColors` (el rojo ANSI sale como `38;2;247;118;142`), `exportFallsBackToPlainWhenVTFails` y `restoredSurfacePrintsScrollbackThenStartsShell`. XCUITest: `SessionRestoreTests.testQuitAndRelaunchRestoresScrollback` (⌘Q, relanzar, ↵: el texto y el banner vuelven) |
| C8 | ✅ | `PaneHistoryTests` (11) con un `zsh -i` real y la cadena de Ghostty: el archivo del panel y el compartido reciben los comandos; ↑ trae primero el del panel; se respetan `HIST_IGNORE_SPACE` y `HISTORY_IGNORE`; un comando de varias líneas vuelve como una sola entrada |
| C9 | ✅ | `ClosedAtPhraseTests` (hoy, anoche, ayer, días anteriores, medianoche, fin de mes, zona horaria) y `ResumeListingTests`. XCUITest `SessionRestoreTests` 8/8: listado, solo teclado, solo layouts, empezar limpio, ⌘, y ⌃↵ que no actúa |
| C10 | ✅ | `NamedLayoutTests` (dominio) y XCUITest `NamedLayoutTests` 3/3 (guardar y restaurar con `sleep 300`, restauración parcial avisada, error al guardar) |
| C11 | ✅ | XCUITest `AgentStatusTests.testRecordedHookLogDrivesTheUI`: 13 hooks enviados por el CLI real desde el panel. Los payloads son reales de Claude Code 2.1.330 (`claude -p`) y, para `PermissionRequest`, `Notification` y `StopFailure`, el esquema documentado. Tras cada paso se comprueban el estado del panel y el contador; al final las notificaciones son exactamente permiso, turno terminado (en un workspace oculto) y error. El dominio lo cubren `AgentTransitionTests` y `AgentUseCaseTests` |
| C12 | ✅ | `EventCommandTests` (9): sale con 0 sin socket, sin panel y sin app en menos de 1 s; un servidor que acepta y no responde se abandona en 1 s; `--version` no lee stdin. `hookIsNoOpOutsideSmalti` |
| C13 | ✅ | `UnixSocketTelemetryTests`: rechaza versión, panel, hook y mensajes de más de 1 MB sin caer; acepta escrituras en trozos; un cliente mudo no retiene a los demás |
| C14 | ✅ | `ClaudePluginInstallerTests` (14) con un `claude` falso; `pluginValidates` con el `claude` real |
| C15 | ✅ | `AgentUseCaseTests.jumpFocusesLongestWaitingAcrossWorkspaces` y XCUITest `testJumpGoesToLongestWaitingPaneInAnotherWorkspace` |
| C16 | ✅ caso de uso | `activatingMissingPaneOnlyActivatesApp`; el clic real en una notificación queda aplazado a la app terminada |
| C17 | ✅ adaptador | `DroppedFilesTests` y `dropPastesBracketedWhenProgramAsksForIt` (superficie real, `\e[200~`… `\e[201~`); el arrastre en XCUITest no es fiable y el adjunto real en Claude queda aplazado |
| C18 | ✅ con desviaciones | `DesignCaptureTests` (a demanda) superpuesto al 50 % sobre los tableros renderizados con Chrome: `F2-assets/c18-restore-overlay.png` y `c18-status-overlay.png`. Etiquetas, colores, botones, contadores, borde ámbar y "te espera · Nm" coinciden en posición y estilo; ver "Desviaciones del diseño" |
| C19 | ✅ | Guardas de imports de SmaltiCore, FileSessionAdapter (Compression) y UserNotificationsAdapter (UserNotifications) |
| C20 | ✅ | `isolatedSmalti()` con `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiConfigPath` y `-SmaltiStatePath` temporales; `PasteboardGuard` en todas las clases |

Pruebas al cierre: SmaltiCore 522, GhosttyAdapter 121, TOMLConfigAdapter 55, FileSessionAdapter 17, ClaudeHarnessAdapter 20, IPCAdapter 41, UserNotificationsAdapter 7, XCUITest 53 (+2 capturas a demanda). Mutación de SmaltiCore 94,7 % (426 mutantes; los 19 sobrevivientes se mataron después con `MutantKillerTests`, comprobados uno a uno).

## Desviaciones del diseño

| Desviación | Motivo |
| --- | --- |
| Retomar va centrado y sin la columna "Todas las sesiones de agentes" | La columna derecha es F6 |
| Casilla delante de "Siempre restaurar" | La spec dice "casilla"; el tablero solo muestra texto y `kbd` |
| Sin filas "· terminada" en Retomar | Un panel cuyo agente terminó vuelve como shell con su scrollback (revisión final, C1) |
| Filas de procesos sin "archivo · línea" (nvim) | Necesita `EditorBridge` (F6) |
| Textos nuevos de barra y notificaciones | Listados en el PR; no están en los tableros |

## Aplazado a la app terminada

- El clic real en una notificación de macOS y el permiso de notificaciones con firma ad hoc (lo pide macOS en pantalla).
- Que Claude Code adjunte como imagen una ruta soltada sobre el panel.
- El uso diario (30 días) como criterio global.

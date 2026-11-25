# F7 · Extras — verificación

2026-11-25 · Rama `feature/f7-extras` · Spec `docs/specs/F7-extras.md` (con las enmiendas 1–9) · Plan `docs/plans/F7-extras.md`

## Cómo se verificó

- **Aislamiento:**
  - las UI tests corrieron con `isolatedSmalti()` (`/bin/zsh -f`, `$TMUX` de guarda, Claude home temporal) y los flags nuevos: `-SmaltiManagedSettings` (nunca los managed settings de la máquina), `-SmaltiTelemetryProbe` y, en Debug, `-SmaltiImportFile`, `-SmaltiPickedFolder`, `-SmaltiConfirmImport` y `-SmaltiExportDirectory`;
  - la telemetría de las pruebas salió de `scripts/otlp/fake-claude.py`, nunca de un Claude real; el emisor rechaza cualquier endpoint que no sea `127.0.0.1` y no usa proxies;
  - ninguna prueba leyó ni escribió `~/.claude` ni `~/.config/smalti` reales.
- **Guarda del Smalti diario:** todas las corridas de UI y de medición pasaron por `scripts/check-daily-untouched.sh`, y todas dejaron su estado intacto. El Smalti diario no estaba abierto durante la fase (no lo ven ni `ps` ni LaunchServices), y no se abrió para no relanzar agentes con la suscripción. Por eso `SMALTI_DAILY_PID` apuntó a un proceso centinela: la mitad de la guarda que comprueba el PID no demostró nada; la del directorio de estado sí.
- **XCUITest:** solo lo afectado, una corrida a la vez.
  - Primera corrida de T8 y T9: 30/33. Los tres fallos se corrigieron: dos en las pruebas nuevas (orden de `sort` y `/private/var`) y uno preexistente desde F6 (`MenuTests.testAboutShowsVersionAndCommit` fijaba «0.5.6»).
  - Regresión de la revisión 2 (9 clases): 64/65. El fallo era otra prueba rota desde F6 (`NamedLayoutTests.testPartlyRestoredLayoutIsReported` usaba `codex` como harness desconocido). Tras la tanda: 13/13.
- **Procesos:** tras cada corrida no quedó ningún `fake-claude.py` ni `Smalti Dev` (`ps`); el receptor se detiene con la app y sus sockets llevan `FD_CLOEXEC`.
- **Suites unitarias** de los paquetes tocados en verde: SmaltiCore 1919, OTLPReceiverAdapter 48, FileSessionAdapter 41, ClaudeTelemetryAdapter 54, TOMLConfigAdapter 129, `test_fake_claude` 3. `swift format lint --strict` en verde.

## Criterios de aceptación

| # | Resultado | Evidencia |
| --- | --- | --- |
| C1 | ✅ | `listensOnlyOnLoopback` (`getsockname` → `127.0.0.1`), `connectViaLanAddressFails` (`ECONNREFUSED` por la IPv4 de la red local), `connectViaIPv6LoopbackFails`; `endpointUsesTheLoopbackLiteral`; `TelemetryTests.testPaneReceivesTelemetryVariables` (el panel recibe `http://127.0.0.1:<puerto>/v1/logs`) |
| C2 | ✅ (GPU no atribuible) | Ver «Mediciones». F0 A12 y A14 sin cambio; F4 C1 independiente de los extras; F4 C13 sin empeorar; GPU en reposo con ruido del sistema, sin diferencia en la CPU de la app ni de WindowServer |
| C3 | ✅ | `acceptsLogsWithToken`, `rejectsMissingToken`, `rejectsWrongToken`, `unknownPathIs404`, `getIs405`, `gzipIs415`, `missingContentLengthIs411`, `chunkedIs411`, `oversizedBodyIs413WithoutReadingIt`, `undecodableBodyIs400`, `keepAliveServesThreeRequests`, `answersTwoPipelinedRequests`, `assemblesRequestSplitAcrossReads`, `idleConnectionClosesAfterTimeout`, `slowHeadersAreCutAtTheIdleTimeout`, `seventeenthConnectionIsRefused`, `stopClosesOpenConnections`; parser byte a byte (`HTTPRequestParserTests`) |
| C4 | ✅ | `OTLPLogsDecoderTests` sobre fixtures con los atributos de Claude Code 2.1.332: `intValue` en número y texto, `doubleValue`, nombre por `event.name` (con y sin prefijo) o por `body`, marca de tiempo con respaldo a `timeUnixNano`, registros sin `session.id`, de otro evento o fuera de rango omitidos |
| C5 | ✅ | `CollectTelemetryTests` (variables exactas, apagado, fallo, configurado por el usuario, configuración que aparece o desaparece en caliente); `ClaudeSettingsTelemetryCheckTests` (`settings.json`, managed settings y entorno del proceso); `TelemetryTests`: `testPaneReceivesTelemetryVariables`, `testOtlpOffInjectsNothing`, `testUserConfiguredTelemetryIsRespected`, `testReloadTurnsReceiverOff`, `testReloadTurnsReceiverOn` |
| C6 | ✅ | `TelemetryLedgerTests` (repetidos por secuencia y hora, ventana de 1.000 entregas, saturación, tope de 200 sesiones, mediana), `TelemetryTextsTests`, `ObservatoryTelemetryTests` (columnas y resumen sin cambios, pies); `TelemetryTests.testFakeClaudeFeedsObservatoryDetail` compara la línea entera salvo la hora |
| C7 | ✅ | `SharedLayoutTests` de dominio (sin `id`, `sessionID`, título ni scrollback; raíz con `~`; argumentos con `~`; ida y vuelta), `SharedLayoutFilesTests`; UI `testExportWritesPortableFile` |
| C8 | ✅ | `ShareLayoutTests` (vista previa con la regla de restaurar, carpeta elegida, nombre libre sin distinguir mayúsculas, avisos) y los rechazos de `SharedLayoutTests`; UI: confirmar, cancelar (con control positivo), carpeta elegida, archivo inválido, nombre ocupado |
| C9 | ✅ | `isolatedSmalti()` con `-SmaltiManagedSettings`; `HarnessIsolationGuardTests` ampliada a la ruta de los managed settings; `check-daily-untouched.sh` en cada corrida |
| C10 | ✅ | `TelemetryGuardTests` (solo `OTLPReceiverAdapter` usa `AF_INET` en producción, sin `privacy: .public` en los adaptadores de telemetría, la ruta de los managed settings solo como valor por defecto), con controles positivos y rojo visto inyectando una violación; `Import guard` de SmaltiCore |
| C11 | ✅ | `stopClosesOpenConnections`, `releasingTheReceiverClosesItsSocket`, `descriptorsAreCloseOnExec`; `ps` tras cada corrida sin emisores ni apps |
| C12 | ✅ | Ver «Mutación» |

## Mediciones (C2)

Smalti Dev (Debug), `env -i`, config y estado temporales, `zsh -f`. «Encendido + carga»: 3 `fake-claude.py` en segundo plano en el panel medido, un lote cada 5 s cada uno.

**F0 · A12 y A14** (`scripts/measure-extras.sh 5`, mediana de 5 corridas):

| | Apagado | Encendido | Encendido + carga |
| --- | --- | --- | --- |
| `cat50mb` | 0,140 s | 0,140 s | 0,140 s |
| `seq5m` | 8,08 s | 8,08 s | 8,02 s |
| Memoria en reposo (`footprint`) | 131 MB | 131 MB | 132 MB (+0,8 %) |

**GPU en reposo** (`scripts/measure-gpu-idle.sh`, `OTLP=off|on`, delante de `gpu-backdrop`):
- Tanda de 5 + 5: 7,0 % apagado y 10,9 % encendido.
- Repetición alternada de 6 pares: 4,5 % y 6,7 % de media (medianas 4,25 % y 5,15 %), con un pico de 14,9 % en una sola corrida encendida. Solo con el receptor apagado varía entre 1,9 % y 8,8 %.
- La CPU de la app (0,6 %) y la de WindowServer (1,8 %) son idénticas en los dos modos, y el receptor no tiene temporizadores: sin tráfico no hace nada.
- Conclusión: la utilización de GPU de `ioreg` es de todo el sistema y su ruido supera la diferencia. **No atribuible a F7** (como C12 de F5.6).

**F4 · C1** (`scripts/measure-input.sh 5`): p99 de extremo a extremo 5,41–5,52 ms (p50 4,61–4,67 ms). El benchmark no pasa por la app ni por el receptor, así que no depende de los extras.

**F4 · C13** (`InputLatencyTests`, a demanda, `SMALTI_MEASURE_NO_OTLP=1` para apagado): falla igual con el receptor apagado y encendido, como en F4 y F5.6 (ticks tardíos de 16–31 ms). Encendido: 130 ticks tardíos (mediana 18,2 ms, máximo 28,3 ms); apagado: 158 (mediana 18,4 ms, máximo 31,4 ms). El receptor no lo empeora.

**Layouts compartibles:** sin coste en reposo; solo actúan al exportar o importar.

## Capturas

- `F7-assets/c-observatory-telemetry-side-by-side.png`: `Observatorio.dc.html` junto al detalle con la línea «Telemetría · desde 07:50 · 42 peticiones · mediana 1,4 s · 2 errores de API · $0.53 según Claude Code», bajo la de compactación y con su estilo, y el pie con «telemetría de Claude Code».
- `F7-assets/c-palette-sharing-side-by-side.png`: `Paleta.dc.html` junto a ⌘K con «Importar layout…», «Restaurar layout “solen-dev”» y «Exportar layout “solen-dev”…».
- Observación preexistente (F2): la fila «Restaurar layout» muestra «— — 1 panel», con dos rayas.

## Mutación

- Revisión intermedia 1 (`--changed-since origin/develop`): **97,4 %** (206 mutantes, 4 sobrevivientes). Tres muertos con pruebas verificadas aplicando el mutante a mano (`exportIsNeverMarkedCurrent`, `extrasStandardTurnsOtlpOn`, `homeWithTrailingSlashStillBecomesTilde`); el cuarto era una rama inalcanzable y se quitó.
- Revisión intermedia 2 (`--changed-since cf704a5`): **100 %** (107 mutantes).
- Cierre: ver abajo.

## Revisiones

- Intermedia 1 (dominio y adaptadores): 3 críticos, 6 importantes y 8 menores, corregidos con su prueba RED→GREEN; enmiendas 1–6.
- Intermedia 2 (app): 0 críticos, 2 importantes y 9 menores, corregidos; enmiendas 7–9.
- Final: ver abajo.

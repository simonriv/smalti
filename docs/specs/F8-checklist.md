# F8 · Puertos y procesos — verificación

2026-11-26 · Rama `feature/f8-puertos-procesos` · Spec `docs/specs/F8-puertos-procesos.md` (con las enmiendas 1–11) · Plan `docs/plans/F8-puertos-procesos.md`

## Cómo se verificó

- **Guarda del Smalti diario:** todas las corridas de UI, las capturas y las mediciones pasaron por `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID=89069`, sacado de `ps -axo pid=,command=`. El diario siguió abierto y con su estado intacto en todas.
- **Solo se detiene lo que la prueba lanzó:**
  - Las pruebas del adaptador lanzan hijos `python3` en `127.0.0.1`/`::1` y puertos efímeros.
  - Las de UI lanzan un oyente en su propio panel, lo filtran por el nombre aleatorio de su script y comprueban que la fila elegida es la suya antes de cada ⌘⌫ o ⇧⌘↓.
  - La captura detiene solo su servidor del puerto 8711.
  - La protección se prueba con `launchd`, que nunca se puede señalar.
- **XCUITest solo de lo afectado,** una corrida a la vez, shells `zsh -f`.
- **Sin procesos huérfanos** tras cada corrida (`pgrep` de `Python.app`, `http.server`, `Smalti Dev` y `gpu-backdrop`). La limpieza del hijo del adaptador ya no usa `waitUntilExit` (revisión final).
- **Nada de `~/.claude`, `~/.config/smalti` ni `/Applications/Smalti.app` en ninguna prueba.**
- **Capturas sin datos personales:** los procesos de ejemplo corren en `/tmp/acme-web` y `/tmp/acme-api`, y el filtro deja fuera el resto. Una primera captura en la que se colaron procesos de la sesión de Simón se descartó.

## Criterios

| # | Estado | Evidencia |
| --- | --- | --- |
| C1 | ✅ | `LsofParityTests`: oyentes TCP en `127.0.0.1` y `::1` y UDP sin conexión en `127.0.0.1`, contra `lsof -iTCP -sTCP:LISTEN` + `lsof -iUDP` sin `->`, con la familia del comodín (`-FpPtn`). También todos los oyentes propios de la máquina (con rapportd y ControlCenter en `*`), con reintento. |
| C2 | ✅ | Dominio: `StopPolicyTests` cubre los cinco motivos y el orden; además, lo adoptado por `launchd` sí se puede detener y el `sudo` dentro del panel no es el shell. `PaneAttributionTests` cubre el grupo sin líder; `StopProcessTests` comprueba que lo protegido no llega al puerto. Adaptador: `ProcessControlTests` se niega con `launchd`, con el PID propio y con una hora de inicio cambiada sin señalar, y da `.gone` con lo que ya terminó. UI: `ProcessesTests.testTreeShowsThePaneShellAsProtectedParent`. |
| C3 | ✅ | Dominio: `StopRequestsTests` y `StopProcessTests` (sin pedido, en gracia o sin confirmar no se fuerza; doble ↵ manda un solo SIGKILL; cerrar desarma todo). UI: `PortsTests.testForceOnlyAfterTermFailsAndConfirmation` (SIGTERM ignorado → «sin responder» → ⌘⌫ abre la confirmación → esc la cierra y sigue vivo → ⌘⌫ + ↵ lo termina). |
| C4 | ✅ | `ProcessesRefresherTests` comprueba que no se lee antes de `start` ni después de `stop`, ni dos lecturas a la vez, y que reabrir con una lectura en vuelo refresca enseguida. Medición abajo. |
| C5 | ✅ | `ProcessTextsTests` (`TextCatalogAudit`), `LocalizationTests.testEnglishProcessesAndPortsHaveNoSpanish` (procesos, árbol, aviso de protegido, puertos y confirmación en inglés), `strings-catalog.test.sh` 5/5. |
| C6 | ✅ | `ProcessesTests`, 11 pruebas: panel, comando y directorio; filtro sin coincidencias; árbol con el shell protegido; orden; «baja (5)» leído con `getpriority`; detener; ↵ salta al panel 1 desde el 2; esc limpia y cierra; teclas especiales fuera del filtro; el menú no apila vistas; ⌘K. |
| C7 | ✅ | `PortsTests`, 4 pruebas: puerto, «TCP · solo local», PID, directorio y panel; resumen; ↵; C3. |
| C8 | ✅ | `ProcessCommandsTests` (atajos de la spec, ninguno con ⌥ solo, los seis en ⌘K y la ayuda), `MenuModelTests`, `KeyChordTranslatorTests` (⌘⌫), `KeyRoutingTests` (los contextuales no se roban a los campos de texto). Enmienda 8: con la vista cerrada, el menú desactiva los cuatro contextuales. |
| C9 | ✅ | Guarda de imports de SmaltiCore. `ProcessesGuardTests`: solo el adaptador lista procesos, lee sockets, cambia prioridades y manda SIGTERM/SIGKILL o una señal literal. `network-surface.test.sh` 2/2 sin cambios. |
| C10 | ✅ | `SampleCostTests`: procesos + puertos con ~650 procesos, p95 de 20 muestras 13–16 ms (< 50 ms). |
| C11 | ✅ | Release `v0.8.0` por el pipeline (DMG firmado con EdDSA, sha256 del cask igual al del DMG publicado). Appcast en smalti-web (#14) con la build 800 servida por smalti.sh; cask en homebrew-tap (#5); docs en smalti-web (#13). El Smalti diario 0.7.7 estaba en «Retomar donde quedaste», donde «Buscar actualizaciones…» está desactivado por diseño: se restauró la sesión (3 workspaces) y se lanzó la comprobación por System Events desde una sesión de Ghostty. Ventana de Sparkle en español con las notas de 0.8.0, «Instalar actualización» y luego «Instalar y volver a abrir». Quedó en 0.8.0 (800), en `/Applications` (sin traslado), sin atributo de cuarentena y sin aviso de Gatekeeper; «Retomar donde quedaste» mostró los mismos 3 workspaces. |

**C4, reposo con la vista cerrada** (`measure-gpu-idle.sh 5`, Debug, misma máquina y misma sesión, F7.7 en un worktree de `origin/develop`):

| Medición | F7.7 | F8 |
| --- | --- | --- |
| GPU, media de 5 corridas | 24,6 % | 23,7 % |
| CPU de Smalti Dev | 0,2–0,3 % | 0,1–0,2 % |
| CPU de WindowServer | 32–34 % | 34–35 % |

La GPU absoluta la pone WindowServer con el escritorio de esa sesión. La primera corrida de cada lado dio 0 % y las demás ~30 %, igual en ambos. F8 no empeora.

## Revisiones y mutación

- **Revisión 1** (dominio y adaptador): 0 críticos, 1 importante, 5 menores; corregidos. Mutación 1: 105 mutantes, 93,8 %; 5 sobrevivientes muertos y verificados a mano.
- **Revisión 2** (app): 0 críticos, 2 importantes, 9 menores. Corregidos salvo los valores de accesibilidad en inglés (enmienda 11). El menor 5 no se reproducía y quedó fijado con una prueba. Regresión de UI de las clases tocadas: 68/68. Mutación 2: 21 mutantes, 88,9 %; 2 sobrevivientes muertos y verificados a mano.
- **Revisión final** (lo que cruza bloques, las tandas y la spec): 0 críticos, 2 importantes, 4 menores; corregidos en una tanda, cada uno con su rojo verificado. El menor del menú quedó como enmienda 8.
- **Mutación de la fase** (`mutate.py --changed-since origin/develop`, solo las líneas de SmaltiCore que cambió F8): 132 mutantes, 99,0 % (mínimo 80 %). El único sobreviviente, el valor inicial de `ProcessesRefresher.isRefreshing`, era equivalente porque `start` siempre reiniciaba. Ahora `start` solo para si ya corría, y la prueba de la lectura inmediata lo mata (verificado aplicándolo a mano). Los bucles de espera de esas pruebas quedaron acotados.

## Afirmaciones nuevas (README, web, notas) y su prueba

| Afirmación | Prueba o hecho |
| --- | --- |
| La lista de puertos es la de lsof (TCP en escucha y UDP sin conexión), sin sudo | C1; spec, hecho 1 |
| Solo tus procesos; los de otros usuarios y del sistema no se pueden leer sin sudo | Spec, hechos 1–2; `RunningProcessesTests.otherUsersProcessesAreCountedButNotRead` |
| Detener nunca toca otro usuario, el sistema, Smalti ni el shell de un panel | C2 |
| SIGKILL solo tras 3 s sin responder y con ↵ en la confirmación | C3 |
| Comprueba PID y hora de inicio antes de actuar | `ProcessControlTests.staleIdentityIsGoneAndNothingIsSignalled` |
| La prioridad solo baja, de 5 en 5 hasta 20 | `NicePriorityTests`, `ProcessControlTests.raisingPriorityIsRefusedWithoutCalling`, C6 |
| Cerradas, las vistas no cuestan nada; abiertas, refrescan cada 2 s | C4 |
| Memoria como Monitor de Actividad; 100 % de CPU es un núcleo | Spec, hecho 2; `CPUUsageTests` |
| En inglés y en español | C5 |

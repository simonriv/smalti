# F8 · Puertos y procesos — Spec

Estado: aprobada · 2026-11-25 (Simón aprobó de antemano la spec, el plan, las recomendaciones de Claude, los merges, el release y el despliegue; también dejó el diseño a criterio de Claude, así que la maqueta de «PARA 1» se aprobó con esta spec) · Roadmap: `docs/ROADMAP.md#f8--puertos-y-procesos`
Diseño: no hay tablero. La referencia es la maqueta `docs/specs/F8-assets/mockup.html` (tableros `?view=processes|ports|confirm&lang=es|en`, capturas `mockup-*-{es,en}.png`), en la línea de `Observatorio.dc.html` y con los tokens de `docs/design/README.md`.

## Objetivo

Ver qué está escuchando y qué está consumiendo, y detenerlo, sin salir de Smalti:

- un **panel de puertos**: puerto, protocolo, dirección (solo local o todas), proceso, PID, directorio y, si lo lanzó un panel, ese panel; detener el proceso y saltar al panel;
- una **vista de procesos** (un htop nativo): CPU, memoria, árbol, filtro y orden, con el estado codificado del resto de la app; detener y bajar la prioridad;
- todo con atajo y en ⌘K, sin botones fijos, en inglés y en español.

Anti-objetivo: **F8 fracasa si**:

- detener o bajar la prioridad toca un proceso de otro usuario, el propio Smalti, el shell de un panel o un proceso del sistema;
- se manda SIGKILL sin confirmación o sin que SIGTERM haya fallado antes;
- se señala un PID reutilizado (el proceso que se eligió ya no es el que lleva ese PID);
- algo cuesta en reposo: muestreo, temporizadores o hilos con la vista cerrada;
- algo pide `sudo`, una contraseña o un permiso nuevo de macOS;
- una prueba detiene un proceso que no lanzó ella misma, toca el Smalti diario, `~/.claude` o `~/.config/smalti` reales;
- se adelanta F8.5, se tocan contenedores o procesos remotos, o la app hace otra petición de red.

## Hechos verificados (antes de diseñar)

Medidos el 2026-11-25 en el MacBook Air M4 de Simón, macOS 27.2.1, sin `sudo`, con un programa de prueba compilado con `swiftc -O` (`scratchpad/spike/spike.swift`, no se versiona).

### 1. Puertos en escucha: libproc frente a lsof

- **libproc** (`proc_listallpids` → `proc_pidinfo(PROC_PIDLISTFDS)` → `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` sobre los descriptores `PROX_FDTYPE_SOCKET`): con 657 procesos, 413 propios y 243 de otros usuarios o del sistema, lista los 13 sockets TCP en `TSI_S_LISTEN` en **2–8 ms** en total. `PROC_PIDLISTFDS` falla con `EPERM` en los procesos de otro usuario: solo se ven los propios.
- **lsof** sin `sudo` ve exactamente lo mismo (13 sockets, los mismos PID) y tarda **~26 ms** más el coste de lanzar un proceso y parsear texto. Tampoco ve los de otros usuarios.
- **Decisión:** libproc. Mismo resultado que lsof, sin proceso hijo, sin parseo y diez veces más barato. lsof queda como oráculo en la prueba de C1.
- **UDP:** los sockets UDP sin conexión (sin dirección remota) con puerto propio son el equivalente de «escuchar». En la máquina de Simón son pocos y del sistema (`identityservicesd`, `sharingd`). **Entran**, con su protocolo en la columna; los UDP conectados (QUIC de navegadores) no.
- **Direcciones:** cada servidor suele escuchar dos veces (IPv4 e IPv6). La vista agrupa por proceso, protocolo y puerto: «solo local» si todas sus direcciones son de loopback (`127.0.0.0/8`, `::1`), «todas» si alguna es comodín (`0.0.0.0`, `::`), y la dirección concreta en otro caso.

### 2. Procesos

- **Lista y árbol:** `sysctl(KERN_PROC_ALL)` da `kinfo_proc` de **todos** los procesos sin privilegios: PID, PPID, UID, grupo, estado (`SRUN`, `SSLEEP`, `SSTOP`, `SZOMB`), terminal (`e_tdev`), nombre corto y hora de inicio (`p_starttime`). Coste: < 1 ms.
- **CPU:** `proc_pidinfo(PROC_PIDTASKINFO)` da `pti_total_user + pti_total_system` en unidades de `mach_timebase_info`; el porcentaje es la diferencia entre dos muestras sobre el tiempo de pared (100 % = un núcleo, como htop y Monitor de Actividad). Solo procesos propios.
- **Memoria:** `proc_pid_rusage(RUSAGE_INFO_V4).ri_phys_footprint`, la «Memoria» de Monitor de Actividad (la que ya usa F3 para los agentes). RSS cuenta páginas compartidas y comprimidas de forma engañosa en Apple Silicon: no se usa.
- **Comando completo:** `KERN_PROCARGS2` (ya lo lee `GhosttyAdapter.ProcessArguments`); **directorio de trabajo:** `PROC_PIDVNODEPATHINFO`; **ruta del ejecutable:** `proc_pidpath`; **hilos y prioridad:** `PROC_PIDTASKINFO.pti_threadnum` y `getpriority(PRIO_PROCESS)`. Para los 413 propios, argumentos y directorio cuestan **3 ms**. Todo junto: < 15 ms por muestra, sin caché.
- **Otros usuarios:** sin `sudo` solo se sabe nombre, PID, PPID y UID; ni CPU, ni memoria, ni comando. **Decisión:** la vista muestra solo los procesos propios y dice cuántos quedan fuera («243 de otros usuarios o del sistema no se pueden leer sin sudo»).
- **Lo que ya da F3:** el puerto `SystemMetrics` (`DarwinMetricsAdapter`) da CPU, GPU y memoria **de la máquina** y la huella de una lista de PID de agentes. No lista procesos, no da CPU por proceso, ni árbol, ni comando, ni directorio, ni sockets. Falta todo lo de esta fase: va en un adaptador nuevo, `DarwinProcessesAdapter`; `SystemMetrics` no cambia.

### 3. Proceso ↔ panel

- libghostty lanza cada panel como `Smalti → /usr/bin/login (root) → shell → …`. `ghostty_surface_foreground_pid` da el líder del grupo en primer plano del PTY del panel; aunque sea `login` (root) y no se pueda nombrar, `kinfo_proc` sí da su terminal (`e_tdev`).
- **Regla:** el terminal de un panel es el `e_tdev` de su proceso en primer plano. Un proceso pertenece a un panel si comparte ese terminal o si alguno de sus antepasados lo comparte (así se atribuyen los que hicieron `setsid` o cerraron su terminal pero siguen colgando del árbol).
- **Los que se desligan del todo** (`nohup … &` + `disown` con doble `fork`, demonios que se re-parentan a `launchd`) pierden el terminal y el padre: quedan «sin panel» (`—`). Es lo honesto: no hay forma fiable de saber de dónde salieron.
- **El shell del panel** (la raíz del subárbol del panel, hijo de `login`) se marca: es lo que cierra ⌘W.
- Hace falta un método nuevo en el puerto `TerminalEngine`: `foregroundGroup(of:) -> Int32?`, el PID crudo, aunque no se pueda nombrar (`foregroundProcess(of:)` devuelve `nil` cuando no hay nombre).

### 4. Detener y priorizar

- `kill(pid, SIGTERM)` y `kill(pid, SIGKILL)` sobre procesos propios no piden privilegios; sobre otro usuario dan `EPERM`.
- **PID reutilizado:** entre que se elige una fila y se pulsa ⌘⌫ el proceso puede terminar y su PID reutilizarse. Cada proceso se identifica por **PID + hora de inicio**; el adaptador relee `kinfo_proc` justo antes de señalar y no hace nada si no coinciden (o si el UID no es el propio).
- `setpriority(PRIO_PROCESS, pid, n)` sin privilegios solo sube el *nice* (baja la prioridad); bajarlo da `EACCES`. Pasos: 0 → 5 → 10 → 15 → 20.
- **Nunca se ofrecen** (la fila se ve, con la etiqueta «protegido», y la acción explica por qué):
  - procesos de otro usuario (no aparecen; el adaptador lo comprueba otra vez);
  - `kernel_task` (0) y `launchd` (1);
  - procesos del sistema: ejecutable bajo `/System/`, `/usr/libexec/`, `/usr/sbin/`, `/sbin/` o `/Library/Apple/` (SIP), lo que incluye `WindowServer`, `loginwindow`, `Dock`, `Finder`, `ControlCenter`, `rapportd`…;
  - Smalti: el propio proceso y cualquier otra instancia de Smalti o Smalti Dev (ejecutable dentro de un `.app` cuyo binario es `Smalti` o `Smalti Dev`). El socket de input, el receptor OTLP y el servidor de guardas son hilos de Smalti, no procesos: quedan cubiertos;
  - el shell de un panel (se cierra con ⌘W, que avisa si hay algo corriendo);
  - un zombi (ya terminó; lo recoge su padre).

## Decisiones de diseño

| Decisión | Elegido | Descartado |
| --- | --- | --- |
| Lectura | libproc + `sysctl`, en un adaptador nuevo `DarwinProcessesAdapter` | lsof o `ps` como proceso hijo (más lento, parseo de texto) |
| Puertos | Una sola vista, `⌘⇧U`, superpuesta como el Observatorio | Un panel lateral fijo (no hay botones ni barras fijas) |
| Procesos | Otra vista de la misma superposición, `⌘⇧M`; las dos se cambian con su atajo y sus chips | Dos superposiciones distintas (duplica cabecera y estado) |
| Qué procesos | Solo los propios, con el recuento de los ocultos | Todos, con CPU y memoria vacías en dos tercios de filas |
| Refresco | Cada 2 s solo con la vista abierta (la primera muestra al abrir y la segunda al segundo, para tener CPU) | Muestreo continuo en segundo plano |
| Detener | SIGTERM; si a los 3 s sigue vivo, la fila pasa a «sin responder» (ámbar); otro ⌘⌫ pide confirmación y ↵ manda SIGKILL | SIGKILL directo, o un temporizador que lo mande solo |
| Prioridad | Solo bajar, +5 hasta 20 | Subir (pide `sudo`) |
| Identidad | PID + hora de inicio | Solo PID |

## Alcance

1. **Dominio** (`SmaltiCore`, Swift puro):
   - Tipos: `ProcessIdentity` (PID + inicio), `ProcessRecord` (lo que lee el adaptador), `ProcessSample` (registros + instante monotónico + ocultos + memoria total), `ListeningSocket` (PID, protocolo, puerto, dirección), `ProcessState` (activo, en reposo, detenido, zombi; más «sin responder» por una detención pendiente).
   - `CPUUsage`: porcentaje por proceso entre dos muestras (identidad igual; un PID reutilizado empieza de cero).
   - `PaneAttribution`: terminal de cada panel → panel de cada proceso, shell de cada panel.
   - `StopPolicy`: puede detenerse / por qué no (`otherUser`, `system`, `smalti`, `paneShell`, `zombie`), la misma para bajar la prioridad.
   - `ProcessTable`: filas de la vista de procesos con filtro (nombre, comando, PID, directorio, panel), orden (CPU ↓, memoria ↓, nombre ↑, PID ↑) y árbol (hermanos ordenados; con filtro, los antepasados de lo que coincide se ven atenuados).
   - `PortTable`: filas de la vista de puertos agrupadas por (PID, protocolo, puerto), con alcance (solo local, todas, dirección concreta), filtro (puerto, proceso, comando, PID, directorio, panel) y orden (puerto ↑, proceso ↑, panel ↑).
   - `StopRequests`: la máquina de estados de detener (pedido → sin responder → confirmando → forzado), con el periodo de gracia de 3 s, que solo permite SIGKILL desde «confirmando».
   - `NicePriority`: siguiente paso hacia abajo y su texto («normal (0)», «baja (5)»…).
   - Casos de uso `ObserveProcesses` (muestrea, atribuye y arma las dos tablas), `StopProcess` y `LowerPriority`.
   - Puertos de salida: `RunningProcesses` (`current() async -> ProcessSample`), `ListeningPorts` (`current() async -> [ListeningSocket]`) y `ProcessControl` (`stop(_:)`, `forceStop(_:)`, `lowerPriority(_:to:)`, con `throws(ProcessControlError)`).
   - Textos en `Domain/Texts/ProcessTexts.swift` (`.spanish` y `.english`).
   - Comandos y atajos: `processes.toggle` (⌘⇧M), `ports.toggle` (⌘⇧U), `processes.stop` (⌘⌫), `processes.lowerPriority` (⌘⇧↓), `processes.tree` (⌘T), `processes.sort` (⌘⇧S); en ⌘K, la ayuda y el menú «Ver» (o el que corresponda por `MenuModel`). Tecla nueva `backspace` (⌫) en `KeyChord`.
2. **Adaptador** `DarwinProcessesAdapter` (paquete SPM nuevo): `DarwinRunningProcesses`, `DarwinListeningPorts`, `DarwinProcessControl` (relee la identidad y el UID antes de cada señal o `setpriority`, y se niega con el propio PID). Errores de libproc/POSIX traducidos a `ProcessControlError` tipado (`gone`, `notYours`, `refused(errno)`).
3. **`GhosttyAdapter`:** `foregroundGroup(of:)` en `GhosttyTerminalEngine` (y en `FakeTerminalEngine`).
4. **App:** `ProcessesController` + `ProcessesView` (superposición sobre la ventana, como `ObservatoryController`), con tabla, detalle, tarjeta «Tus procesos» / «Resumen», pie de teclas y tarjeta de confirmación; `ProcessesRefresher` con un `Task` que existe solo mientras la vista está abierta. Escribir filtra; esc limpia el filtro y, vacío, cierra; ↑↓ eligen; ↵ salta al panel; los atajos de arriba actúan mientras está abierta y pasan al terminal mientras está cerrada (⌘⌫, ⌘T, ⌘⇧S y ⌘⇧↓). Desde ⌘K o el menú con la vista cerrada, «Detener…», «Bajar prioridad…», «Árbol» y «Ordenar» la abren primero.
5. **Textos de vistas** en `Localizable.xcstrings` (inglés y español).
6. **Web** (`smalti-web`, a la par): página de puertos y procesos en inglés y español con capturas, comandos nuevos, y «Lo que viene» sin F8 y con F8.5 como siguiente; changelog.
7. **Cierre:** mediciones, capturas, checklist, 0.8.0, PRs, release por el pipeline, actualización del Smalti diario por Sparkle.

## La vista

Superposición sobre toda la ventana, con el fondo, la franja superior y las tarjetas del Observatorio (`ObservatoryView`), y los tokens del tema en vigor. Ver la maqueta.

- **Franja superior (40 pt):** «Procesos» + «lo que corre y escucha en esta máquina»; chips «Procesos ⌘⇧M» y «Puertos ⌘⇧U» (el activo con el anillo y el brillo del acento); separador; campo de filtro (210 pt, lupa, texto fantasma «filtrar»); chip del orden («CPU ↓», «Puerto ↑»); en procesos, chip «Árbol» con anillo cuando está activo; `esc`.
- **Tabla de procesos:** Estado (punto + texto) · Proceso (nombre en peso medio, comando en mono secundario, guías de árbol `├─ └─ │` en el color de separación, etiqueta «protegido» con borde fino) · Panel («<workspace> · <n>» o `—`) · CPU (barra de 46 pt en el acento + porcentaje en mono, secundario por debajo del 0,5 %) · Memoria · PID (secundario). Filas de 36 pt. La elegida con el brillo y el filo de 2 pt del acento.
- **Estado codificado** (el de toda la app): verde «activo» (≥ 0,5 % de CPU en la última muestra); hueco «en reposo» (dormido) o «detenido» (`SSTOP`); ámbar «sin responder» (no terminó tras ⌘⌫, con «⌘⌫ para forzar» en ámbar junto al comando); rojo «zombi».
- **Tabla de puertos:** Puerto (mono, título) · Protocolo · Dirección («solo local» secundario, «todas» en texto principal) · Proceso (punto de estado + nombre + comando) · PID · Directorio (mono, `~` abreviado) · Panel.
- **Detalle** (columna derecha, 330 pt): de procesos, «Proceso · <nombre>», comando completo en un bloque mono con ajuste de línea, y Directorio, Panel («↵ ir»), Padre, Inicio («hace 42 min»), Escucha (sus puertos), Prioridad, Hilos; debajo, las acciones con su tecla (⌘⌫ Detener, ⌘⇧↓ Bajar prioridad, ↵ Ir al panel …), solo las que aplican; si está protegido, en su lugar «No se puede detener: <motivo>». De puertos, «Puerto <n> · <protocolo>», Escucha en, Proceso, Comando, Directorio, Panel, Inicio y las acciones.
- **Tarjeta inferior:** en procesos, «Tus procesos · <n>», CPU sumada con su línea de los últimos 60 valores (cian, como el Observatorio), memoria («<usada> / <total> GB», barra con la parte de los paneles de Smalti en el acento y el resto en gris) y la nota de los ocultos y el refresco. En puertos, «Resumen», «<n> puertos», «<m> abiertos a la red» y la nota sobre «todas» y lsof.
- **Pie de teclas (30 pt):** «↑↓ elegir · ↵ ir al panel · ⌘⌫ detener · ⌘⇧↓ bajar prioridad · ⌘T árbol · ⌘⇧S ordenar · esc cerrar» (en puertos, sin prioridad ni árbol y con «⌘⇧M procesos»). Un aviso (protegido, ya no existe, ya tiene la prioridad más baja) ocupa la derecha del pie 4 s, en secundario; un error de señal, en el rojo de error.
- **Confirmación de forzar:** tarjeta abajo y centrada (520 pt), con el fondo de la tarjeta de aprobación de F7.5 y su borde y punto ámbar: «¿Forzar el cierre de <nombre> (<pid>)?», «No respondió a «Detener» en 3 s. Forzarlo (SIGKILL) lo termina sin dejarle guardar nada.», el comando y el directorio en mono, «↵ forzar · esc cancelar». El resto de la vista se oscurece un 28 %.
- **Vacíos:** «Nada coincide con «<filtro>»»; en puertos sin filtro, «Ningún proceso tuyo escucha en un puerto».
- **Movimiento:** el fundido de 150 ms de las superposiciones; sin animación con «Reducir movimiento». Las filas no se animan al reordenar.
- **Accesibilidad:** grupo `smalti.processes`, tabla `smalti.processes.table` (filas `smalti.processes.row.<pid>` y en puertos `smalti.ports.row.<pid>.<protocolo>.<puerto>`), detalle `smalti.processes.detail`, confirmación `smalti.processes.confirm`, aviso `smalti.processes.notice`, filtro `smalti.processes.filter`. VoiceOver lee estado, nombre, panel, CPU y memoria.

### Textos en inglés (glosario)

| Español | Inglés |
| --- | --- |
| Procesos · Puertos | Processes · Ports |
| lo que corre y escucha en esta máquina | what runs and listens on this Mac |
| activo · en reposo · detenido · sin responder · zombi | active · idle · stopped · not responding · zombie |
| protegido | protected |
| solo local · todas | local only · all |
| Detener · Bajar prioridad · Ir al panel | Stop · Lower Priority · Go to Pane |
| ¿Forzar el cierre de …? · forzar · cancelar | Force … to quit? · force · cancel |
| Tus procesos · Resumen · puertos · abiertos a la red | Your processes · Summary · ports · open to the network |
| Árbol · ordenar · filtrar | Tree · sort · filter |

## Fuera de alcance

- F8.5 en adelante; contenedores (Docker) y procesos remotos; cualquier acción con `sudo`.
- Procesos de otros usuarios (más allá del recuento), subir la prioridad, enviar otras señales (SIGHUP, SIGINT), reanudar procesos detenidos.
- Detener todo un grupo o un árbol de una vez: se detiene el proceso elegido (sus hijos reciben lo que el propio proceso decida).
- Puertos en ⌘K como filas dinámicas («Detener lo que escucha en :5173»): se puede añadir después si se echa de menos.
- Gráficas por proceso o historial más allá de la línea de CPU de la tarjeta.

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
| --- | --- | --- |
| C1 | La lista de puertos coincide con lsof | Prueba del adaptador: lanza oyentes TCP en `127.0.0.1` y `::1` y un UDP sin conexión en `127.0.0.1`, todos en puertos efímeros; el conjunto (PID, protocolo, puerto, dirección) de `DarwinListeningPorts` es igual al de `lsof -iTCP -sTCP:LISTEN -nP` + `lsof -iUDP -nP` sin `->`, para esos PID y para todos los propios (con reintento si otro proceso abre o cierra uno entre las dos lecturas) |
| C2 | Detener nunca toca lo protegido | Dominio: `StopPolicy` para cada motivo (otro usuario, 0 y 1, rutas del sistema, el propio Smalti y otra instancia, shell de panel, zombi) y `StopProcess` no llama al puerto. Adaptador: `DarwinProcessControl` se niega con `launchd` (PID 1, root), con el propio PID y con una identidad de hora de inicio cambiada, sin señalar |
| C3 | SIGKILL solo tras confirmación y solo si SIGTERM no bastó | Dominio: `StopRequests` y `StopProcess` (forzar sin pedido, con pedido dentro de la gracia o sin confirmar no llama a `forceStop`). XCUITest `PortsTests`: un oyente que ignora SIGTERM pasa a «sin responder», ⌘⌫ abre la confirmación, esc la cierra y sigue vivo, ⌘⌫ + ↵ lo termina |
| C4 | Sin coste en reposo | `ProcessesRefresherTests`/dominio: sin muestreo con la vista cerrada; al cierre, GPU y CPU en reposo de Smalti Dev (`measure-gpu-idle.sh 5`) con la vista cerrada sin empeorar respecto de F7.7, medidas el mismo día |
| C5 | Inglés y español completos | `LocalizationTests` recorre procesos, puertos y la confirmación en inglés; `ProcessTexts` en `TextCatalogAuditTests`; `strings-catalog.test.sh` |
| C6 | La vista de procesos funciona | `ProcessesTests`: ⌘⇧M abre; un proceso lanzado en un panel aparece con su panel, comando y directorio; el filtro lo aísla; ⌘T muestra el árbol con el shell protegido; ⌘⇧S cambia el orden; ⌘⇧↓ lo deja en «baja (5)»; ⌘⌫ sobre un proceso que atiende SIGTERM lo termina; ⌘⌫ sobre el shell muestra el aviso y no lo toca; ↵ salta a su panel |
| C7 | El panel de puertos funciona | `PortsTests`: ⌘⇧U abre; el oyente de la prueba aparece con puerto, «TCP», «solo local», PID, directorio y panel; ↵ salta a su panel; C3 |
| C8 | Todo con atajo y en ⌘K | Dominio: los seis comandos en `CommandCatalog`, `HelpCatalog` y `MenuModel` con sus atajos; ninguno usa ⌥ solo; los atajos pasan al terminal con la vista cerrada |
| C9 | Arquitectura | Guarda de imports de `SmaltiCore`; `DarwinProcessesAdapter` es el único que llama a libproc para estas lecturas; `network-surface.test.sh` sin cambios |
| C10 | Coste de una muestra | Prueba del adaptador: con todos los procesos de la máquina, `current()` de procesos + puertos tarda < 50 ms (p95 de 20) |
| C11 | Release y actualización real | 0.8.0 por el pipeline (DMG, appcast, cask); el Smalti diario 0.7.7 se actualiza solo por Sparkle desde smalti.sh, sin aviso de Gatekeeper y con la sesión intacta |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| Señalar un PID reutilizado | Matar otro proceso | Identidad PID + inicio, releída en el adaptador justo antes de la señal (C2) |
| Una prueba que detiene lo que no debe | Matar algo de Simón | Las pruebas solo señalan PID que lanzaron ellas (oyentes efímeros en 127.0.0.1); la protección se prueba con `launchd`, que nunca se puede señalar; `check-daily-untouched.sh` en cada corrida |
| El cortafuegos de macOS pregunta al abrir un puerto | Una ventana en medio de las pruebas | Las pruebas solo escuchan en loopback (`127.0.0.1`, `::1`) |
| El shell del panel no se reconoce (panel con comando propio, `login` de root) | Proteger o atribuir mal | El terminal sale de `kinfo_proc`, que lee también procesos de root; prueba de dominio con un árbol `login → claude` |
| Coste con la vista abierta | CPU de Smalti alta mientras se mira | < 15 ms por muestra cada 2 s, fuera del hilo principal (C10) |
| ⌘⌫ en el terminal | Romper el atajo de borrar línea del shell | El atajo solo actúa con la vista abierta; prueba de dominio de paso al terminal (C8) |

## Plan de pruebas y revisiones

Según `.claude/rules/`:

- **Revisiones:** intermedia 1 al terminar dominio y adaptadores; intermedia 2 al terminar la app, la web y los documentos; final acotada a lo que cruza bloques, a las tandas de correcciones y al cumplimiento de la spec.
- **Mutación:** una por revisión intermedia con `--changed-since`; cada sobreviviente se mata con una prueba verificada aplicando el mutante a mano. Al cierre, solo los archivos de SmaltiCore de la fase (≥ 80 %).
- **XCUITest:** una sola corrida de `scripts/test-ui.sh` por tanda, solo lo afectado (`ProcessesTests`, `PortsTests`, `LocalizationTests` y las clases tocadas), nunca dos a la vez, siempre bajo `scripts/check-daily-untouched.sh` con `SMALTI_DAILY_PID` sacado de `ps -axo pid=,command=`; shells con `-SmaltiShellCommand "/bin/zsh -f"`. Argumento de prueba `-SmaltiStopGraceSeconds` (solo Debug) para acortar la gracia.
- **Procesos de prueba:** los oyentes son scripts de `python3` en loopback y puertos efímeros, lanzados por la prueba en su panel o como hijos del runner; se terminan en el `tearDown` (y su grupo si se cortan por tiempo).
- **Capturas** al cierre: procesos, puertos y confirmación en inglés y en español, junto a la maqueta.
- **Mediciones** al cierre (C4, C10).

## Cambios en otros documentos (con esta spec)

- `docs/ROADMAP.md`, F8: la spec y el criterio de cierre concretado.
- `docs/design/README.md`: sección «Puertos y procesos (F8)» que apunta a la maqueta.
- `CLAUDE.md`: el puerto nuevo en la lista, `DarwinProcessesAdapter` en «Comandos» y en `swift format`, y `-SmaltiStopGraceSeconds`.

## Enmiendas

Durante la ejecución (2026-11-25/26), con su porqué:

1. **El refresco vive en el dominio.** `ProcessesRefresher` (SmaltiCore, `Application/`) arranca y para el muestreo; la app solo lo llama al abrir y cerrar. Así C4 («sin muestreo con la vista cerrada») tiene prueba de dominio (`ProcessesRefresherTests`) en lugar de depender de la app (revisión 2).
2. **La confirmación la sabe el dominio.** `StopProcess.confirming` dice qué proceso espera que se confirme «Forzar» y `cancelConfirmations()` la desarma al cerrar la vista; `confirm` suelta el pedido antes de mandar SIGKILL, así que un segundo ↵ no manda otro (revisión 2).
3. **El shell del panel es hijo de `login` en el mismo terminal.** Lo que `launchd` adoptó o lo que lanzó un `sudo` dentro del panel no cuenta como shell aunque comparta el terminal (revisión 1).
4. **El tiempo de CPU ilegible es desconocido, no 0** (`ProcessRecord.cpuTime: UInt64?`), para que la muestra siguiente no parezca un pico (revisión 1).
5. **La fila muestra el comando corto.** Nombre del programa y sus argumentos («Python server.py»), sin la ruta de `argv[0]`; el bloque del detalle conserva el comando completo. La nota de memoria escribe MB o GB.
6. **Columna «Protocolo» de 104 pt** (la maqueta usaba 84): «PROTOCOLO» no cabía en español.
7. **La lupa del filtro** es el símbolo `magnifyingglass` de la búsqueda de sesiones (F6), no un dibujo propio.
8. **Valores de accesibilidad «selected», «on» y «off» en inglés.** Es la convención de toda la app (las UI tests la leen); localizarlos es un cambio transversal fuera de F8.

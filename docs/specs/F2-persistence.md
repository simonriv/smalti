# F2 · Persistencia e integración con Claude Code — Spec

Estado: aprobada · 2026-11-22 · Roadmap: `docs/ROADMAP.md#f2--persistencia-e-integración-con-claude-code` · Issue #6
Diseño: `docs/design/Reanudar.dc.html` (columna izquierda, "Retomar donde quedaste"), `docs/design/Main.dc.html` (estado en franja, cabeceras y borde) y `docs/design/Paleta.dc.html` (comandos de layouts).

## Objetivo

Cerrar y reabrir Smalti sin perder trabajo, y que ningún Claude que espera pase inadvertido. Al cerrar F2, Smalti es la terminal diaria de Simón. Para que eso no rompa el desarrollo de Smalti, la primera parte separa los builds de desarrollo del Smalti diario.

## Partes

| Parte | Contenido | Por qué en este orden |
| --- | --- | --- |
| A · Builds `.dev` (issue #6) | Bundle ID, nombre de proceso, datos y socket propios para Debug, XCUITest y scripts | Sin esto, usar Smalti a diario y desarrollarlo choca: XCUITest cierra la instancia en uso |
| B · Persistencia | Instantánea de workspaces y paneles, scrollback con colores, historial por panel, pantalla "Retomar donde quedaste", layouts con nombre | Base de la terminal diaria |
| C · IPC e integración con Claude | Socket Unix, CLI `smalti`, plugin de Claude Code, estado por panel, `claude --resume` | Necesita el identificador de panel y la instantánea de B |
| D · Atención | Notificaciones de macOS, salto al agente que más espera, arrastrar imágenes | Consume el estado de C |

## Alcance

- **Builds separados:** Debug → `dev.simonriv.smalti.dev`, app y proceso "Smalti Dev", `~/Library/Application Support/Smalti Dev/`; Release sigue igual (`dev.simonriv.smalti`, "Smalti").
- **Guardar y restaurar:** workspaces, layout y ratios, foco, directorio, título y proceso de cada panel; scrollback de hasta 10.000 líneas por panel con colores; historial de comandos por panel; sesión de Claude de cada panel.
- **Retomar donde quedaste:** columna izquierda de `Reanudar.dc.html`, en versión Claude Code.
- **Layouts con nombre:** "Guardar layout actual como …" y "Restaurar layout …" en ⌘K, con el comando de arranque de cada panel y las sesiones de Claude.
- **IPC y CLI:** socket Unix por instancia y ejecutable `smalti` empaquetado en la app.
- **Plugin de Claude Code** con hooks, instalable y desinstalable desde ⌘K.
- **Estado por panel:** trabajando, te espera, error y detenido, en la cabecera, el borde del panel, el punto del workspace y los contadores de la franja.
- **Notificaciones de macOS** con contexto; un clic lleva al panel.
- **Saltar al agente que más espera**, con atajo y en ⌘K.
- **Arrastrar una imagen** al panel de Claude la adjunta.

## Fuera de alcance

- Columna derecha de `Reanudar.dc.html` ("Todas las sesiones de agentes", buscador multi-harness) y adaptadores de Codex, Gemini, Antigravity y OpenCode (F6). El puerto `HarnessAdapter` nace aquí con una sola implementación.
- Modelo y `ctx %` en la cabecera, tokens y lado derecho de la barra de estado (F3: salen de los transcripts y de OTLP).
- Filas de nvim con archivo y línea ("reminder.service.ts · línea 42", `nvim +42`): necesitan `EditorBridge` (F6). En F2 una fila de nvim es un proceso más (ver "Procesos en primer plano").
- Escribir en el TOML desde la UI (F5). La casilla "Siempre restaurar" se guarda en el estado de la app en F2 y pasa al TOML en F5.
- Revivir procesos en vivo (decisión cerrada: se relanzan; el daemon es F7).
- Varias ventanas.

## Enfoques considerados

| Tema | Elegido | Descartado |
| --- | --- | --- |
| Scrollback | **VT con colores**: el adaptador ejecuta la acción de libghostty `write_screen_file:open,vt` (historial y pantalla visible; `write_scrollback_file` solo exporta el historial), intercepta el `OPEN_URL` que produce y lee el archivo; si falla, cae a `ghostty_surface_read_text` (texto plano). Decidido por Simón | Solo texto plano: más estable, pierde colores |
| Reinyectar el scrollback | **Lanzador**: el panel restaurado arranca con un lanzador que imprime el archivo guardado y hace `exec` del shell. Funciona con cualquier shell, también con `zsh -f` en pruebas | Snippet de zsh: no corre con `zsh -f`. API para escribir salida en la superficie: libghostty v1.4.0 no la tiene |
| Historial | **Por panel, sin romper `SHARE_HISTORY`** (modelo de Terminal.app): un snippet de zsh que Smalti encadena vía `GHOSTTY_ZSH_ZDOTDIR` guarda cada comando también en el archivo del panel y, al restaurar, lo carga encima del historial compartido. El `HISTFILE` de Simón no cambia. Decidido por Claude a petición de Simón | `HISTFILE` por panel: rompe el historial compartido. No guardar historial: no cumple el roadmap |
| Hooks de Claude | **Plugin local** `smalti` con marketplace local, instalado con `claude plugin marketplace add` + `claude plugin install`. Decidido por Simón | Hooks escritos en `~/.claude/settings.json`: se mezclan con los de Simón y desinstalar es editar ese archivo |
| Notificación al terminar un turno | **`Stop` → ámbar siempre; notificación de macOS solo si el panel no está a la vista** (app inactiva o workspace oculto). Decidido por Simón | Ámbar sin notificación; notificación siempre |
| Identificar el panel desde un hook | **Variables de entorno** que Smalti exporta a cada hijo (`SMALTI_PANE_ID`, `SMALTI_SOCKET`, `SMALTI_CLI`) y que heredan Claude y sus hooks | Asociar por `cwd` o por PID: ambiguo con dos Claude en el mismo directorio |

## Diseño técnico

### Módulos

```text
SmaltiApp ──▶ SmaltiCore ◀── GhosttyAdapter
                  ▲   ▲   ▲
                  │   │   └── TOMLConfigAdapter
                  │   ├────── FileSessionAdapter      (instantánea, scrollback, historial, layouts; LZFSE)
                  │   ├────── IPCAdapter              (servidor del socket + protocolo; producto SmaltiIPCProtocol)
                  │   ├────── ClaudeHarnessAdapter    (comando de reanudación, plugin, instalador)
                  │   └────── UserNotificationsAdapter (UNUserNotificationCenter)
smalti (CLI, ejecutable SPM en IPCAdapter) ──▶ SmaltiIPCProtocol
```

- Cada adaptador es un paquete SPM propio y el único que importa su framework (Compression, Network o `Darwin` sockets, UserNotifications). Cada uno tiene su prueba de guarda de imports, como `TOMLAdapterGuardTests`.
- El CLI no depende de `SmaltiCore`: solo del protocolo, para arrancar rápido dentro de un hook.

### Parte A · Builds `.dev`

- **Xcode:** la configuración Debug usa `PRODUCT_BUNDLE_IDENTIFIER = dev.simonriv.smalti.dev` y `PRODUCT_NAME = Smalti Dev`. La acción Test usa Debug, así que XCUITest lanza y cierra solo "Smalti Dev". Release no cambia.
- **`AppIdentity`** (lado app): sale del `Bundle` y da el directorio de estado (`~/Library/Application Support/<PRODUCT_NAME>/`), la ruta del socket y el subsistema de `Logger` (el bundle ID). Nada más lee el bundle ID.
- **Aislamiento de pruebas:** nuevo argumento `-SmaltiStatePath <dir>`, al lado de `-SmaltiConfigPath` y `-SmaltiShellCommand`; `isolatedSmalti()` pasa los tres. Las pruebas nunca leen el estado real.
- **Configuración:** los dos builds leen `~/.config/smalti/config.toml` (es de solo lectura en F2). Solo el estado y el socket se separan.
- **Señal visual:** el build Debug muestra la insignia "dev" en el icono del Dock (`dockTile.badgeLabel`). Es mi propuesta: no está en los tableros y no toca la ventana.
- **Scripts:** `scripts/bench/*` y cualquier script que hoy use `pkill -x Smalti` pasan a esperar y terminar por PID la instancia que lanzaron, nunca por nombre.

### Parte B · Persistencia

#### Dominio (`SmaltiCore/Domain/Session`)

- **`SessionSnapshot`**: versión de formato, `savedAt: Date`, workspaces en orden, índice del activo.
  - `WorkspaceSnapshot`: nombre, `rootDirectory`, layout (id del catálogo), árbol con ratios (`LayoutTree` con índices de panel en lugar de `PaneID`, porque los `PaneID` se regeneran), índice del panel enfocado y paneles.
  - `PaneSnapshot`: `workingDirectory`, `title`, `processName`, número de líneas de scrollback guardadas, número de comandos, `relaunch: RelaunchCommand?` y `agent: AgentSnapshot?`.
  - `AgentSnapshot`: harness (`claude` en F2), `sessionID`, título (el primer prompt, ver Parte C) y último estado.
- **`SessionSnapshot.capture(from: WorkspaceSet, …)`** y **`RestorePlan`**: funciones puras. `RestorePlan` recibe la instantánea, el modo (`.full` o `.layoutsOnly`) y los paneles marcados, y devuelve, por workspace, el layout, los ratios y un `TerminalSessionSpec` por panel.
  - `.full`: directorio, historial y comando inicial (reanudación del agente o relanzamiento del proceso). El scrollback solo se reinyecta en los paneles que tenían el shell en primer plano: Claude y los TUI relanzados repintan su propia pantalla, y el scrollback se vería duplicado (como en el tablero, donde `scrollback` solo aparece en las filas de shell). Tampoco se exporta para esos paneles.
  - Selección por defecto (la de la pantalla, la de "Siempre restaurar" y la de una restauración sin pantalla): shells y agentes no detenidos marcados; procesos relanzables desmarcados. "Siempre restaurar" nunca relanza procesos.
  - `.layoutsOnly`: solo layout, ratios y directorios; shells limpios.
  - Un panel desmarcado no se abre. Un workspace sin paneles marcados no se crea. Si no queda ninguno, se arranca como hoy.
- **`ClosedAtPhrase`** (pura, con `TimeZone` inyectada): "hoy a las 18:05", "anoche a las 23:48" (día anterior desde las 18:00), "ayer a las 14:10", y "el jue 20 a las 09:12" para fechas anteriores. Da el texto "Cerraste … ." del tablero.
- **`TerminalSessionSpec`** gana `restoration: PaneRestoration?` (scrollback, historial) e `initialInput: String?` (lo que el shell recibe escrito al arrancar, como `claude --resume <id>\n`).

#### Procesos en primer plano

- Al guardar, si el proceso en primer plano de un panel no es su shell ni un agente, se guarda su línea de comandos como `RelaunchCommand` (el adaptador la lee con `sysctl(KERN_PROCARGS2)` a partir de `ghostty_surface_foreground_pid`).
- Al restaurar se ofrece como fila con el comando a la derecha (como `nvim +42` en el tablero), desmarcada por defecto: relanzar algo a ciegas puede tener efectos (un `pnpm db:migrate`). Los shells y los agentes vienen marcados, salvo los agentes detenidos.

#### Aplicación: casos de uso

`SaveSession`, `LoadLastSession`, `RestoreSession`, `DiscardLastSession`, `SaveNamedLayout`, `RestoreNamedLayout`, `ListNamedLayouts` y `DeleteNamedLayout`, todos ejecutables con fakes en memoria.

- **Cuándo se guarda:**
  - Metadatos y layout: tras cada cambio estructural o de directorio, con un retardo de 1 s.
  - Scrollback: al salir (⌘Q, `applicationShouldTerminate`) y cada 5 minutos. Si Smalti muere de golpe, se pierden como mucho 5 minutos de salida.
  - Escritura atómica (archivo temporal + `rename`); una instantánea a medio escribir nunca reemplaza a la buena.
- **Al abrir:** si hay instantánea y la preferencia es "preguntar" (por defecto), se muestra "Retomar donde quedaste"; con "Siempre restaurar", se restaura todo sin preguntar; sin instantánea, se arranca como hoy.
- **Layouts con nombre:** guardan lo mismo que un `WorkspaceSnapshot`, sin scrollback ni historial. Restaurar uno abre un workspace nuevo con ese nombre y nunca reemplaza el actual. Los agentes del layout se reanudan con su sesión ("retoma 2 sesiones de Claude", como en la paleta); si una sesión ya no existe, Claude lo dice en su panel y el shell queda abierto. Los comandos de arranque guardados sí se ejecutan: guardar el layout y restaurarlo son dos actos explícitos de Simón, y para eso existen los layouts con nombre. Si la sesión de Claude de un panel ya está viva en otro panel de Smalti, ese panel abre el shell sin reanudar y la barra de estado lo dice (evita dos procesos sobre la misma sesión).

#### Puertos

| Puerto | Operaciones (vocabulario de dominio) | Adaptador |
| --- | --- | --- |
| `SessionArchive` | `save(_ snapshot:)`, `lastSession() -> LastSession` (`.none` o `.saved(snapshot)`), `discard()` | `FileSessionArchive` |
| `PaneTranscripts` | `keep(_ scrollback:, for pane:)`, `scrollback(of:)` | `FileSessionArchive` (mismo archivo de estado, puerto aparte por ISP) |
| `ScrollbackSource` | `scrollback(of pane: PaneID, lastLines: Int) -> Scrollback` | `GhosttyTerminalEngine` |
| `NamedLayouts` | `save(_ layout:, as name:)`, `layout(named:)`, `names()`, `delete(named:)` | `FileSessionArchive` |

- `Scrollback` es un valor del dominio: texto y formato (`.vt` o `.plain`).
- Prueba de contrato compartida para `SessionArchive` y `NamedLayouts` (fake en memoria y adaptador de archivos).

#### Formato en disco (`<estado>/`)

```text
session.json                 instantánea (JSON legible, con versión de formato)
scrollback/<uuid>.lzfse      scrollback por panel, comprimido con LZFSE
history/<uuid>.zsh_history   historial por panel (formato de zsh)
layouts/<nombre>.json        layouts con nombre
preferences.json             { "restore": "ask" | "always" } hasta F5
smalti.sock                  socket IPC (Parte C)
```

- El directorio se crea con permisos 0700. Un `session.json` ilegible o de una versión desconocida se renombra a `session.corrupt-<fecha>.json`, se registra en el log y se arranca limpio, con un aviso en la barra de estado. Nunca bloquea el arranque.
- Al guardar se borran los scrollback e historiales de paneles que ya no existen.

#### Adaptador de libghostty (cambios de F2)

- **Exportar scrollback:** `ghostty_surface_binding_action(surface, "write_screen_file:open,vt")` (revisado en el bloque 3: `write_scrollback_file` omite la pantalla visible). El `OPEN_URL` llega de forma síncrona dentro de la llamada (verificado); el adaptador borra el archivo y, con `rmdir`, su carpeta solo si queda vacía. El callback de acciones recibe `OPEN_URL` con la ruta del archivo temporal; si hay una exportación en curso para esa superficie, el adaptador se queda con la ruta en lugar de abrirla, lee el archivo, se queda con las últimas 10.000 líneas, antepone un `ESC[0m` y borra el temporal. Si la acción no responde o falla, usa `ghostty_surface_read_text` con una selección `GHOSTTY_POINT_SCREEN` (texto plano). Hay que verificar en la primera tarea del bloque que el `OPEN_URL` llega de forma síncrona dentro de la llamada.
- **Reinyectar:** si el spec trae scrollback, el adaptador lo escribe en un archivo temporal (0600) y lanza el panel con `/bin/sh -c 'cat "$SMALTI_RESTORE_FILE"; rm -f "$SMALTI_RESTORE_FILE"; printf … "$SMALTI_RESTORE_BANNER"; exec <shell>'`, con el login shell como `exec "${SHELL:-/bin/zsh}" -l` (POSIX). El banner viaja en el entorno, nunca dentro del comando. Si la superficie no llega a crearse, el adaptador borra el archivo. La integración de zsh de Ghostty llega al shell final porque libghostty exporta su `ZDOTDIR` a todo el árbol (verificado).
- **Separador** tras el scrollback restaurado, en gris secundario: `── restaurado · 22 nov 23:48 ──` (aprobado con la spec).
- **`initialInput`** va al campo `initial_input` de `ghostty_surface_config_s`.
- **Historial por panel:** las variables de entorno del panel se aplican después de la integración de libghostty, así que un `ZDOTDIR` propio la anularía. Smalti exporta en cambio `GHOSTTY_ZSH_ZDOTDIR=<estado>/zsh` (y `SMALTI_USER_ZDOTDIR` si la app arrancó con uno): el `.zshenv` de Ghostty carga el de Smalti y luego su propia integración. El `.zshenv` de Smalti, que el adaptador escribe en `<estado>/zsh`, restaura el `ZDOTDIR` del usuario, carga su `.zshenv` y registra:
  - `zshaddhistory`: copia cada comando al archivo del panel, salvo lo que `HIST_IGNORE_SPACE` o `HISTORY_IGNORE` dejan fuera, con la continuación del formato de zsh (barra invertida y salto de línea) para que un comando de varias líneas sea una sola entrada. Se registra en el `.zshenv`, así que un `.zshrc` que reasigna `precmd_functions` no lo quita.
  - Primer `precmd`: si el panel viene restaurado (`SMALTI_RESTORE_HISTORY`), `fc -R` del archivo del panel. Un `.zshrc` que reasigna `precmd_functions` sí lo quita; el panel arranca entonces solo con el historial compartido.
  - El archivo del panel se recorta a sus últimas 10.000 líneas al guardar.
  - Con `zsh -f` no corre. Se prueba en `PaneHistoryTests` con un `zsh -i` real y la cadena de Ghostty.
- **Contar comandos:** los `commandFinished` de OSC 133 suman el número de comandos del panel, que muestra la pantalla de retomar ("38 comandos").

#### Pantalla "Retomar donde quedaste" (`Reanudar.dc.html`, columna izquierda)

- Se muestra centrada en la ventana, sobre el vidrio, antes de abrir ningún panel. Es la única tarjeta de la pantalla en F2: la columna derecha es F6.
- Título "Retomar donde quedaste" (20 px, 600, `#e6e9ef`). Subtítulo (12,5 px, `#9aa0ab`): "Cerraste <ClosedAtPhrase>. Los shells vuelven con su historial y salida; los agentes se relanzan con su propio comando de reanudación."
- Por workspace: nombre (13 px, 600) y "<Layout> · N paneles" (11,5 px, `#8b919c`); por panel, una fila `.item` con casilla, etiqueta, texto principal y código a la derecha:
  - Claude: etiqueta "Claude Code" (`rgba(217,119,87,0.16)` / `#f0a98f`), título de la sesión, `claude --resume 7f3a…` (4 caracteres del id).
  - Shell: etiqueta con su nombre (`rgba(255,255,255,0.07)` / `#c3c7cf`), directorio abreviado "· 1.240 líneas · 38 comandos" y `scrollback` a la derecha.
  - Proceso relanzable: etiqueta con el nombre del proceso, directorio, y su línea de comandos a la derecha.
  - Agente detenido: texto en `#9aa0ab` con "· terminada", desmarcado.
- Botones: "Restaurar N paneles" (acento, cuenta los marcados), "Solo layouts" y "Empezar limpio"; casilla "Siempre restaurar ⌘,".
- **Teclado:** ↑↓ mueven entre filas; espacio marca y desmarca; ↵ restaura; ⌘L "Solo layouts"; esc "Empezar limpio"; ⌘, alterna "Siempre restaurar". ⌘L es mi propuesta: el tablero no le pone atajo. Los botones son del tablero; el principio "sin botones fijos" se cumple porque cada uno tiene atajo.
- "Empezar limpio" deja la instantánea sin borrar hasta el siguiente guardado, para poder deshacerlo cerrando sin hacer nada.

### Parte C · IPC e integración con Claude Code

#### Entorno de cada panel

`OpenPane` añade, además de `SMALTI` y `SMALTI_VERSION`: `SMALTI_PANE_ID=<uuid>`, `SMALTI_SOCKET=<ruta>` y `SMALTI_CLI=<ruta absoluta del ejecutable empaquetado>`, y antepone su directorio al `PATH` del panel, para que `smalti` funcione en el shell. Los builds Debug y Release se distinguen solos: cada uno exporta su socket y su CLI.

#### Protocolo y socket

- Socket Unix en `<estado>/smalti.sock`, permisos 0600, uno por instancia. Si al arrancar ya existe y nadie responde, se borra; si responde otra instancia del mismo build, la segunda no lo toma y lo registra.
- Una petición por conexión, una línea JSON con versión: `{"v":1,"kind":"event","pane":"<uuid>","hook":"Stop","payload":{…}}`. Respuesta `{"ok":true}` o `{"ok":false,"error":"…"}`.
- Los tipos del protocolo viven en `SmaltiIPCProtocol`, con pruebas de ida y vuelta. El servidor valida versión, panel y tamaño (máximo 1 MB) y traduce a `AgentEvent` del dominio en la frontera.

#### CLI `smalti`

- `smalti event <Hook>`: lee de stdin el JSON del hook de Claude Code y lo reenvía con el `SMALTI_PANE_ID` del entorno. Si no hay socket, panel o app, **sale con 0 sin escribir nada**, en menos de 1 s (tiempo de espera de conexión 500 ms). Un hook nunca puede bloquear ni romper a Claude.
- `smalti --version`.
- Empaquetado en `Smalti.app/Contents/Resources/bin/smalti`, no en `Contents/MacOS`, porque en APFS sin distinción de mayúsculas `smalti` choca con el binario `Smalti`.

#### Plugin de Claude Code

- Empaquetado en `Contents/Resources/claude-plugin/` como marketplace local `smalti` con un plugin `smalti`. Cada hook ejecuta `"${SMALTI_CLI:-true}" event <Hook>`: fuera de Smalti la variable no existe y el hook ejecuta `true`, así que no hace nada.
- Hooks: `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure` y `SessionEnd`. Respecto al roadmap se añaden `UserPromptSubmit` (sin él, el panel no vuelve a verde al escribir un prompt nuevo), `PermissionRequest` (da el comando concreto para la notificación), `StopFailure` (estado de error) y `SessionEnd` (detenido). Los cuatro existen en Claude Code 2.1.330.
- **Instalar** (⌘K "Instalar integración con Claude Code"): copia el plugin a `~/Library/Application Support/Smalti/claude-plugin/`, una ruta común a los dos builds y fuera del bundle. El plugin es igual para los dos builds (cada hook enruta por el `SMALTI_CLI` del panel que lanzó a Claude), así que instalarlo desde "Smalti Dev" no rompe el diario, y borrar el estado de Dev no lo toca. Las pruebas usan un `claude` falso y nunca llegan a esa ruta. Después ejecuta `claude plugin marketplace add <ruta>` y `claude plugin install smalti@smalti`. **Desinstalar**: `claude plugin uninstall smalti@smalti` y `claude plugin marketplace remove smalti`. El resultado, o el error con la salida de `claude`, va a la barra de estado. Si `claude` no está en el `PATH` del login shell, se dice así.
- El plugin pasa `claude plugin validate` en una prueba.

#### Dominio del agente (`SmaltiCore/Domain/Agent`)

- **`AgentState`**: `.working`, `.waiting(since:, reason:)`, `.failed(since:, message:)`, `.stopped`. `reason` es `.turnFinished`, `.permission(toolSummary)` o `.attention(message)`.
- **`AgentSession`**: harness, `sessionID`, título, estado, `startedAt`. Vive en el `Pane` (`agent: AgentSession?`).
- **Transiciones** (`AgentSession.applying(_ event: AgentEvent, at:)`, pura):

| Evento | Nuevo estado | Notificación (Parte D) |
| --- | --- | --- |
| `SessionStart` | crea la sesión (id, `startedAt`); `.waiting(.turnFinished)`: Claude espera tu prompt, y al restaurar 3 sesiones las 3 esperan de verdad. Cuenta en los contadores y en ⌘J. Un quinto estado "inactivo" rompería el código de 4 estados del diseño | no |
| `UserPromptSubmit` | `.working`; si no hay título, el prompt (primera línea, 80 caracteres) | no |
| `PostToolUse` | `.working` | no |
| `PermissionRequest` | `.waiting(.permission("pnpm db:migrate …"))` | sí |
| `Notification` | `.waiting(.attention(mensaje))`; si ya estaba esperando, no cambia `since` ni notifica otra vez (evita el aviso de inactividad de 60 s tras un `Stop`) | sí, salvo duplicado |
| `Stop` | `.waiting(.turnFinished)` | sí, si el panel no está a la vista |
| `StopFailure` | `.failed(mensaje)` | sí |
| `SessionEnd` | `.stopped` | no |

  - Respaldo: si el proceso en primer plano deja de ser `claude` sin `SessionEnd`, `.stopped`; si el comando `claude` termina con código distinto de 0 (OSC 133), `.failed`.
  - `PermissionRequest` y `Notification` llegan juntos ante un permiso: cuenta como un solo aviso.
- **`AttentionQueue`** (pura): los paneles en `.waiting` o `.failed` ordenados por `since`. Da el destino del salto y los contadores.
- **Estado del workspace** (para su punto): el más urgente de sus paneles, en este orden: error > te espera > trabajando > detenido. Sin agentes, neutro como en F1.

#### Casos de uso y puertos

- Casos de uso: `HandleAgentEvent`, `JumpToWaitingAgent`, `InstallClaudeIntegration`, `UninstallClaudeIntegration`.
- `RestoreSession` pide a `HarnessAdapter` el comando de reanudación de cada agente.

| Puerto | Operaciones | Adaptador |
| --- | --- | --- |
| `HarnessAdapter` | `resumeCommand(for: AgentSnapshot) -> String` (`claude --resume <id>`); `canResume` | `ClaudeHarness` (de F6 en adelante, un tipo por harness y una prueba de contrato compartida) |
| `HarnessIntegration` | `install()`, `uninstall()`, `isInstalled` | `ClaudePluginInstaller` (ejecuta `claude plugin …` con `Process`) |
| `TelemetrySource` | `events() -> AsyncStream<AgentEvent>` | `UnixSocketTelemetry` (servidor del socket) |
| `Notifier` | `notify(_ notice: AttentionNotice)` | `UserNotificationsNotifier` |

- `detect`, `captureSessionId` y `listSessions` del `HarnessAdapter` de PROJECT.md llegan en F6, cuando haya más de un harness y un buscador que los use (YAGNI).

#### UI del estado (`Main.dc.html`)

- **Cabecera:** el punto de 7 px toma el color del estado; los paneles sin agente quedan neutros como en F1. A la derecha:
  - te espera: "te espera · 2m" en `#e0af68`;
  - trabajando: el tiempo de vida de la sesión ("1h 12m") en `#8b919c`;
  - error: "error · 3m" en `#f7768e`.
  - detenido: círculo hueco `#6b717c`, sin texto.
  - El texto de error no está en el tablero; sigue el patrón de "te espera" y va en la lista de decisiones.
- **Borde:** un panel que espera, sin foco, lleva borde `rgba(224,175,104,0.35)`, como el tablero. El anillo de foco gana sobre el ámbar.
- **Franja:** el punto de cada workspace con su estado agregado y, a la derecha de las pastillas, los contadores "N trabajando" (punto verde) y "N te espera" (punto y texto ámbar), como el tablero; "N error" en rojo con el mismo formato. Un contador en 0 no se muestra.
- Los minutos se refrescan una vez por minuto, solo si hay agentes esperando o con error.

### Parte D · Atención

- **Notificaciones** (`UNUserNotificationCenter`; se pide permiso la primera vez que hay algo que notificar):
  - Título: `<workspace>/<último componente del directorio>`, por ejemplo "rizaria/web".
  - Cuerpo: "pide permiso para `pnpm db:migrate --name add_user_prefs`" (`PermissionRequest`), "terminó y te espera" (`Stop`), el mensaje de Claude (`Notification`) o "error: <mensaje>" (`StopFailure`). Son textos nuevos y van en la lista de decisiones.
  - "A la vista" = la app está activa y el panel está en el workspace visible. `PermissionRequest`, `Notification` y `StopFailure` notifican siempre; `Stop` solo si no está a la vista.
  - Un clic activa Smalti, cambia al workspace y enfoca el panel (`userInfo` con el `PaneID`). Si el panel ya no existe, solo activa la app.
  - El permiso denegado no es un error: el estado ámbar sigue en la UI y la barra de estado lo dice una vez.
- **Saltar al agente que más espera:** ⌘J (propuesta: libre en el keymap de F1 y sin ⌥) y comando de ⌘K "Saltar al agente que espera". Enfoca el primero de `AttentionQueue`, cambiando de workspace si hace falta. Sin agentes esperando, no hace nada y la barra de estado lo dice.
- **Arrastrar imágenes:** `GhosttySurfaceView` acepta archivos arrastrados. Si el proceso en primer plano es `claude`, pega la ruta escapada como *bracketed paste*, y Claude Code la convierte en un adjunto (`[Image #1]`). En cualquier otro proceso pega la ruta escapada, como Ghostty. No toca el portapapeles. Que Claude la muestre como adjunto se comprueba a mano al terminar la app (regla de pruebas); la prueba automática verifica los bytes que recibe el PTY.

### Atajos nuevos (editables en TOML)

| Acción | Atajo | Origen |
| --- | --- | --- |
| Saltar al agente que espera | ⌘J | Propuesta |
| Guardar layout actual como … / Restaurar layout … | solo ⌘K | Paleta |
| Instalar / desinstalar integración con Claude Code | solo ⌘K | Propuesta |
| Retomar: restaurar / solo layouts / empezar limpio / siempre restaurar | ↵ / ⌘L / esc / ⌘, | Tablero (⌘,) y propuesta |

## Criterios de aceptación

| # | Criterio | Verificación |
| --- | --- | --- |
| C1 | Con el Smalti diario (Release) abierto, una corrida completa de XCUITest y de `scripts/bench` no lo cierra: su PID sigue vivo, ningún evento sintético le llega y su `session.json` no cambia (issue #6). Robar el foco es inevitable mientras XCUITest maneja "Smalti Dev"; el criterio es que el diario nunca reciba eventos | Script que anota el PID antes y después + XCUITest |
| C2 | Debug produce "Smalti Dev.app" con `dev.simonriv.smalti.dev`, su propio directorio de estado y socket; Release no cambia | Prueba de build (`plutil` sobre los dos Info.plist) |
| C3 | Ida y vuelta de la instantánea: capturar → guardar → leer → `RestorePlan` reproduce workspaces, orden, layout, ratios, foco, directorios y agentes, con 0, 1 y 9 paneles | Pruebas de dominio y de contrato (`SessionArchive` fake y de archivos) |
| C4 | `RestorePlan` con paneles desmarcados, workspaces vacíos y `.layoutsOnly` | Pruebas de dominio |
| C5 | Un `session.json` corrupto o de versión desconocida se aparta y la app arranca limpia con aviso; una escritura interrumpida no reemplaza la instantánea buena | Pruebas del adaptador |
| C6 | Al reabrir, layout, directorios y scrollback vuelven en **menos de 5 s** con 3 workspaces y 6 paneles, desde el lanzamiento hasta que el último panel es interactivo (su shell emitió el primer OSC 7) | Signposts `restore.start` / `restore.done`, build Release, 5 corridas en el informe |
| C7 | El scrollback vuelve con colores: un panel imprime texto con SGR, se cierra Smalti, se reabre y el panel restaurado contiene el texto, con colores en el VT exportado; con la exportación VT forzada a fallar, vuelve en texto plano | Prueba del adaptador + XCUITest |
| C8 | El historial por panel: tras restaurar, el primer comando de ↑ es el último del panel, y el `HISTFILE` compartido también recibió los comandos | Test de script de zsh con `ZDOTDIR` temporal |
| C9 | "Retomar donde quedaste" muestra workspaces, filas, conteos y la frase de cierre; se maneja solo con teclado; "Restaurar N paneles" cuenta los marcados | XCUITest + pruebas de `ClosedAtPhrase` (hoy, anoche, ayer, días anteriores, cambio de mes, zona horaria) |
| C10 | Un layout con nombre se guarda y se restaura en un workspace nuevo con sus comandos de arranque y la reanudación de sus agentes | Pruebas de casos de uso + XCUITest |
| C11 | **Repetición de hooks:** una prueba reproduce un log grabado de eventos de hooks de Claude (inicio, prompt, herramienta, permiso, notificación de inactividad, stop, fallo, fin) a través del CLI real y del socket, y compara contra la UI: punto, texto y borde de la cabecera, punto del workspace, contadores y notificaciones emitidas. Todo `Notification` y `PermissionRequest` produce ámbar y una notificación | XCUITest con un `Notifier` de grabación activado por argumento de lanzamiento + pruebas de dominio de la tabla de transiciones |
| C12 | `smalti event` sin socket, sin panel o con la app cerrada sale con 0 en menos de 1 s sin salida; fuera de Smalti el hook del plugin ejecuta `true` | Pruebas del CLI |
| C13 | El protocolo rechaza versión desconocida, panel inexistente y mensajes de más de 1 MB sin tumbar el servidor | Pruebas del adaptador IPC |
| C14 | El plugin empaquetado pasa `claude plugin validate`; instalar y desinstalar ejecutan los comandos esperados y muestran el resultado | Prueba del adaptador con un `claude` falso en el `PATH` |
| C15 | ⌘J enfoca el agente que más tiempo lleva esperando, también en otro workspace; sin ninguno, no hace nada | Pruebas de `AttentionQueue` + XCUITest |
| C16 | Un clic en una notificación lleva al workspace y al panel | Prueba del caso de uso con la respuesta simulada; el clic real queda aplazado a la app terminada |
| C17 | Soltar una imagen sobre un panel con `claude` en primer plano envía al PTY la ruta escapada entre marcas de *bracketed paste*; con otro proceso, la ruta escapada | Prueba del adaptador + XCUITest con un proceso que vuelca su entrada |
| C18 | Capturas de la pantalla de retomar, de la franja con contadores y de un panel en ámbar coinciden con los tableros | Captura superpuesta al tablero, adjunta al PR |
| C19 | Guardas: `SmaltiCore` sigue en Swift puro; cada adaptador nuevo es el único que importa su framework | `swift test` |
| C20 | Las UI tests usan `-SmaltiShellCommand "/bin/zsh -f"`, `-SmaltiConfigPath` y `-SmaltiStatePath` temporales, y restauran el portapapeles | Helper compartido en `SmaltiUITests` |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| La exportación VT depende de interceptar `OPEN_URL` de una acción de teclado | Un bump de Ghostty la rompe en silencio | Respaldo a texto plano; C7 fuerza el fallo; el PR de bump repite C7 |
| El lanzador del scrollback y la integración de zsh de Ghostty | Paneles restaurados sin OSC 133/7, o sin login shell | Se verifica en la primera tarea del bloque; si no funciona, el lanzador exporta el `ZDOTDIR` de Ghostty a mano |
| Encadenar `ZDOTDIR` delante del de Ghostty y del usuario | Un `.zshenv` raro del usuario se carga mal | El snippet solo restaura variables y hace `source`; test de script con `ZDOTDIR` propio y vacío |
| Notificaciones con firma ad hoc | `UNUserNotificationCenter` podría negarse | Se comprueba al inicio del bloque D; si falla, la UI sigue en ámbar y la barra de estado lo dice |
| Formato y nombres de los hooks de Claude Code cambian | Estado incorrecto | El protocolo ignora campos desconocidos; el log grabado de C11 se regenera con cada versión mayor de Claude |
| Claude Code no convierte la ruta pegada en adjunto | La imagen llega como texto | Verificación manual aplazada; alternativa documentada: imagen al portapapeles + ⌃V con restauración del portapapeles |
| Exportar el scrollback de 6 paneles cada 5 min | Pausa en el hilo principal | Se mide con la sonda de latencia; si pasa de 16 ms, se reparte por panel |
| `sysctl(KERN_PROCARGS2)` sobre procesos ajenos | Sin línea de comandos para relanzar | El proceso no se ofrece para relanzar; nunca es un error |

## Decisiones para aprobar con esta spec

1. Textos nuevos que no están en los tableros:
   - el separador del scrollback (`── restaurado · 22 nov 23:48 ──`);
   - "error · 3m" y "N error";
   - los cuerpos de las notificaciones ("pide permiso para …", "terminó y te espera", "error: …");
   - "Saltar al agente que espera" e "Instalar/Desinstalar integración con Claude Code".
2. Atajos ⌘J (saltar) y ⌘L (solo layouts en Retomar).
3. Insignia "dev" en el Dock para el build Debug.
4. Hooks añadidos al roadmap: `UserPromptSubmit`, `PermissionRequest`, `StopFailure` y `SessionEnd`.
5. Procesos relanzables desmarcados por defecto en Retomar.
6. "Siempre restaurar" en `preferences.json` hasta F5.
7. Un Claude recién arrancado o reanudado aparece en ámbar ("te espera") sin notificación.
8. Puertos nuevos que no están en la lista de `CLAUDE.md`: `SessionArchive`, `PaneTranscripts`, `ScrollbackSource`, `NamedLayouts` y `HarnessIntegration`. Ninguna Decisión de `PROJECT.md` cambia.

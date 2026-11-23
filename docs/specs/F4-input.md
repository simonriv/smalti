# F4 · Input inteligente — Spec

Estado: aprobada · 2026-11-23 · Roadmap: `docs/ROADMAP.md#f4--input-inteligente`
Diseño: `docs/design/Main.dc.html` (texto fantasma, menú de completions y línea de ayuda del panel derecho), adaptado al prompt en línea (ver "Decisiones de Simón"). ⌃R reutiliza la paleta de `docs/design/Paleta.dc.html`. Maquetas aprobadas en el brainstorming: `F4-assets/mockup-input.png` y `F4-assets/mockup-history.png`.

## Objetivo

Escribir comandos con completions, historial por directorio y predicción en texto fantasma sin romper nunca un programa que no sea el shell: Claude Code, nvim, htop, less o cualquier `read` reciben el teclado tal cual.

El anti-objetivo manda sobre todo lo demás: **F4 fracasa si una tecla llega distinta a un programa que no es el prompt de zsh, o si el shell se cuelga o se vuelve lento porque Smalti no responde.**

## Decisiones de Simón en el brainstorming

| Tema | Elegido | Descartado y por qué |
| --- | --- | --- |
| Quién edita la línea | **zsh (ZLE) sigue siendo el editor; Smalti sugiere encima** (texto fantasma, menú de Tab, ⌃R) | Editor propio estilo Warp: se pierde ZLE (vi-mode, `bindkey`, widgets) y es la clase de editor que falla con TUIs. Selección con ratón, multilínea y atajos propios quedan fuera de F4 |
| Aspecto del input | **En línea (opción 2):** el prompt es el del usuario; fantasma en `#5f6672` como el tablero; el menú del tablero se ancla bajo el cursor (encima si no cabe) con la línea de ayuda "Tab completar · → aceptar sugerencia · ⌃R historial" dentro | Caja fija abajo con bloques por comando (tablero tal cual): exige editor propio |
| ⌃R | **Paleta centrada sobre el panel, como ⌘K**, con ámbito "Este directorio" / "Todos", estado del último exit, recencia y veces | Lista en línea estilo fzf: menos contexto por fila |
| Historial de partida | **Vacío: aprende solo de lo que se ejecuta en Smalti.** `~/.zsh_history` nunca se importa; solo se lee, en solo lectura, para el benchmark | Importar una vez: sin directorio ni exit, ensucia la predicción por directorio |
| Plugins del usuario (zsh-autosuggestions, fzf ⌃R, `bindkey '^I' expand-or-complete`) | **En los paneles de Smalti, Smalti toma el control**: apaga zsh-autosuggestions, ⌃R abre su paleta, Tab usa specs de Fig si hay una para el comando y si no cae en el widget que el usuario tenía en Tab. Ningún archivo del usuario se toca; fuera de Smalti todo sigue igual | Convivir alimentando a zsh-autosuggestions: F4 dependería de un plugin del usuario y no se podría probar sin él |
| Pruebas | `-SmaltiShellCommand "/bin/zsh -d"` con un `ZDOTDIR` temporal vacío en lugar de `zsh -f` (que no carga la integración, así que no habría OSC 133 ni widgets). Igual de aislado: no lee `~/.zshrc` ni engancha a tmux | — |
| Ayuda y pantalla completa | Fuera de F4: nueva entrada "F4.5 · Ayuda y ventana" en el roadmap (vista de ayuda con todos los atajos, pantalla completa nativa, y lo que se sume) | Meterlo en F4: mezcla fases |

Las decisiones de Claude van marcadas con **(Claude)** y se resumen en "Decisiones para aprobar con esta spec".

## Hechos verificados en el mini-spike (rama `spike/f4-prompt-overlay`, desechable)

Prueba `F4SpikeTests` con libghostty v1.4.0 y zsh 5.9 aislado. Registro completo en `F4-assets/spike-log.txt`; captura en `F4-assets/spike-ghost-text.png`.

- **"En el prompt" sale de la API pública.** libghostty no emite acción por OSC 133;A/B, pero guarda el estado semántico por fila y celda. `ghostty_surface_needs_confirm_quit()` devuelve `!cursorIsAtPrompt()` si la config lleva `confirm-close-surface = true`. Smalti ignora el flag de confirmación de `close_surface_cb`, así que activarlo no cambia el cierre.
- Resultados: prompt y escribiendo → sí; PS2 (comilla abierta) → sí; `sleep 1` → no (detectado a 1,3 ms; vuelve a 1018 ms); `read x` → no; pantalla alternativa → no. Coste: 0,37 µs por consulta.
- **Trampa:** con el hijo terminado también devuelve "en el prompt"; se combina con `ghostty_surface_process_exited`.
- **Trampa:** un comando muy corto (`echo`) puede ir y volver entre dos consultas; nada de F4 depende de ver esa transición.
- **Capa sobre el Metal:** una vista AppKit en la celda del cursor queda alineada a la rejilla y a la línea base. `ghostty_surface_ime_point` da x = centro de la celda del cursor, y = borde inferior, origen arriba a la izquierda, en puntos. JetBrains Mono no está instalada: la capa registra para el proceso el mismo archivo que trae libghostty. El cursor se mueve 0,6 ms después de la tecla.
- `zsh -f` no carga la integración de Ghostty: no hay OSC 133.
- **SIGPIPE mata el shell.** Con un socket de `zsocket` que el otro extremo cerró, el siguiente `print -u $fd` termina zsh en silencio. Con la escritura dentro de una función con `setopt localoptions localtraps; trap '' PIPE`, `print` devuelve 1, el shell sigue y los hijos que se lancen después tienen SIGPIPE normal (verificado con `yes | head -1`).
- Las rutas de socket Unix tienen un máximo de 104 bytes (`AF_UNIX path too long` con la ruta del scratchpad).
- zsh-syntax-highlighting (Homebrew, zsh 5.9) se registra con `add-zle-hook-widget` en `zle-line-pre-redraw`. zsh-autosuggestions instala `_zsh_autosuggest_start` en `precmd` y, sin `ZSH_AUTOSUGGEST_MANUAL_REBIND`, vuelve a envolver todos los widgets en cada `precmd`.

En la máquina de Simón (solo lectura de `~/.zshrc`): zsh 5.9, zsh-autosuggestions, zsh-syntax-highlighting, fzf (`source <(fzf --zsh)`), starship, `bindkey '^I' expand-or-complete`. Specs de Fig: `@withfig/autocomplete` 2.692.3 (licencia ISC, última publicación 2025-05-05), 739 módulos ES compilados (`export{X as default}`), 76 MB; la mayoría usa generadores (`script` + `postProcess`, o `custom` con `executeShellCommand`).

## Alcance

1. Canal por panel entre zsh y Smalti: zsh informa de la línea, del cursor y de cada comando ejecutado; Smalti responde con sugerencias y ediciones.
2. Historial propio de Smalti por directorio, con exit, duración y hora.
3. Predicción heurística en texto fantasma, también con la línea vacía.
4. Menú de completions con Tab desde specs de Fig, con generadores.
5. ⌃R: búsqueda difusa en paleta.
6. Toma de control de zsh-autosuggestions, ⌃R y Tab dentro de los paneles de Smalti.
7. Filtro de secretos en el dominio, listo para F7.
8. Benchmark de 50.000 entradas y pruebas de que los programas que no son el shell no ven nada.

## Fuera de alcance

- Editor propio: selección con ratón, multilínea editable, atajos propios (pasa a "después de F4" en `PROJECT.md`).
- Aceptar solo una palabra del fantasma (⌥→ está reservado para escribir; se revisa con el uso real).
- Shells distintos de zsh, SSH y tmux dentro del panel: el widget solo vive en el zsh local que lanza Smalti.
- Predicción con API o `claude -p`, `#` en lenguaje natural y "Arreglar" (F7).
- Editar specs o ajustes desde la UI (F5); el TOML sí gana las claves de F4.
- Ayuda de atajos y pantalla completa (F4.5).

## Enfoques considerados

| Tema | Elegido | Alternativas |
| --- | --- | --- |
| Quién edita | zsh (Simón) | Editor propio (ver arriba) |
| Cómo sabe Smalti lo escrito | **Widget de zsh que envía `BUFFER` y `CURSOR` por un socket del panel en `zle-line-pre-redraw`** **(Claude)** | Leer la fila del cursor en pantalla: frágil con prompt derecho, colores, línea partida y multilínea |
| Quién pinta el fantasma | **zsh, con `POSTDISPLAY` + `region_highlight` (`memo=smalti`)** **(Claude)**. Ajuste de línea, prompt derecho y PS2 salen bien solos; aceptar con → lo resuelve zsh sin que Smalti intercepte teclas | Capa AppKit del spike: hay que perseguir el redibujado, el ajuste de línea y el prompt derecho. Se usa solo para los menús |
| Detección del prompt | **`needs_confirm_quit` + `process_exited`** como guarda de los menús **(Claude)** | Fork de libghostty con una acción por OSC 133: rompe el pin; hooks por IPC: llegan desfasados del dibujo |
| Specs de Fig | **JavaScriptCore en un adaptador; se versiona un subconjunto curado, convertido a script en el build** **(Claude)** | Reescribir las specs a JSON: se pierden los generadores, que son lo valioso (ramas, scripts de npm); un runtime de Node: proceso extra y arranque en frío |
| Historial | **JSONL propio, cargado en memoria al arrancar** **(Claude)** | SQLite: más piezas para 100.000 filas que caben en memoria; `HISTFILE` de zsh: sin directorio ni exit |

## Diseño técnico

### Módulos

| Módulo | Qué añade |
| --- | --- |
| `SmaltiCore/Domain/Input` | Línea de comando, tokenización, modelo de spec, motor de completions, historial, puntuación de la predicción, búsqueda difusa, filtro de secretos |
| `SmaltiCore/Application` | Puertos `CompletionProvider`, `PredictionProvider`, `CommandHistory`, `ProjectContext`; casos de uso |
| `GhosttyAdapter` | `confirm-close-surface = true`; `isAtPrompt` y posición del cursor por `TerminalViewProvider` (lado app); script de zsh de F4 |
| `IPCAdapter` | Servidor del canal de input (socket Unix por app, mensajes por panel) — adaptador primario |
| `FigCompletionAdapter` (nuevo) | Único que importa JavaScriptCore; carga specs, ejecuta generadores |
| `FileSessionAdapter` | `CommandHistory` en JSONL |
| `ProjectContextAdapter` (nuevo) | Scripts de `package.json`, objetivos de `Makefile`, rama y estado de git (leyendo `.git/`, sin procesos) |
| `SmaltiApp` | Capa de menú de completions, paleta ⌃R, composición, línea de ayuda |

### Canal zsh ↔ Smalti

- Smalti abre un socket Unix de input (`input.sock`, junto al de F2, permisos 0600, ruta < 104 bytes) y exporta su ruta en `SMALTI_INPUT_SOCKET`, con `SMALTI_PANE_ID` ya existente.
- **Carga en todos los paneles:** hoy `GhosttyTerminalEngine.zshChain` solo encadena el `.zshenv` de Smalti si el panel tiene `SMALTI_HISTORY_FILE`. F4 lo encadena siempre que `[input] enabled`; el historial por panel de F2 sigue condicionado a su variable. Las pruebas pasan su ZDOTDIR temporal por `SMALTI_USER_ZDOTDIR` (libghostty se queda con `ZDOTDIR`), con un argumento de lanzamiento nuevo `-SmaltiUserZdotdir`.
- El script de zsh de F4 vive en el `.zshenv` de Smalti (`SmaltiZshEnv`) y se instala en `precmd`, después de `.zshrc` (ver "Toma de control" para el orden).
- Conexión: `zmodload zsh/net/socket zsh/zselect; zsocket "$SMALTI_INPUT_SOCKET"`, una por shell, y `hello <pane>`; Smalti contesta `specs <comando>…` con los comandos que tienen spec, para que zsh decida Tab sin esperar.
- **Lectura:** asíncrona con `zle -F -w <fd> <widget>` (con `-w` el manejador es un widget y puede tocar `BUFFER`, `POSTDISPLAY`, `region_highlight` y llamar a `accept-line`).
- **Escritura que nunca cuelga ni mata el shell:** una sola función de envío que (1) comprueba con `zselect -t 0 -w $fd` que se puede escribir y, si no, descarta el mensaje (solo importa el último `line`); (2) escribe con `setopt localoptions localtraps; trap '' PIPE`; (3) si `print` falla, desregistra el `zle -F`, cierra el fd, borra el fantasma y desactiva F4 en ese shell sin mensaje. Del lado de Smalti, el servidor lee en un hilo propio que nunca depende del hilo principal.
- Mensajes, uno por línea, campos separados por tab y escapados (`\t`, `\n`, `\\`):
  - zsh → Smalti: `hello <pane>`, `line <seq> <cursor> <buffer>` (solo si cambió), `exec <seq> <command>` (en `preexec`), `done <seq> <exit>` (en `precmd`), `complete <seq> <cursor> <buffer>`, `history <seq> <buffer>`, `bye`.
  - Smalti → zsh: `specs <comando>…`, `suggest <seq> <texto>` (el resto de la línea en fantasma; vacío borra), `edit <seq> <buffer> <cursor>` (reemplaza la línea tras elegir en un menú), `run <seq>` (ejecuta tras ⌘↩ en ⌃R), `fallback <seq>` (Tab sin candidatos: zsh llama al widget guardado).
  - zsh descarta toda respuesta cuyo `seq` no sea el del último mensaje que envió: un `edit` tardío nunca pisa lo que se escribió después.
- **Directorio:** el del panel por OSC 7 (`pane.workingDirectory`, ya existente), en el momento del mensaje; vale para predicción, generadores, `ProjectContext` y el historial (`exec`).
- El historial respeta lo que zsh no guardaría: `HIST_IGNORE_SPACE` y `HISTORY_IGNORE` (como el hook de F2), y lo que marque el filtro de secretos **(Claude)**.
- Duración: Smalti la mide entre `exec` y `done`.

### Toma de control dentro de Smalti

Resultado exigido (C7); el mecanismo exacto lo fija el constructor contra las fixtures:

- **Orden:** el hook de `precmd` de Smalti se registra en `.zshenv`, así que en el primer prompt corre **antes** que los de los plugins. Por eso se reubica al final de `precmd_functions` en cada `precmd` y hace la toma de control cuando ya corrieron los arranques de los plugins (en la práctica, el segundo paso del primer prompt o el primero en que `_zsh_autosuggest_start` ya no esté); se repite si un plugin vuelve a enlazar.
- **zsh-autosuggestions:** no basta con apagarlo. Se quitan sus hooks (`_zsh_autosuggest_start`, `_zsh_autosuggest_bind_widgets` en `precmd`) y se restauran los widgets originales que guardó (`autosuggest-orig-*`), para que sus envoltorios no borren ni acepten el fantasma de Smalti. Tras instalarse, Smalti comprueba que ningún widget enlazado es un envoltorio de autosuggestions; si queda alguno, F4 se desactiva en ese shell y lo anota en el log.
- **`zle-line-pre-redraw`:** con `add-zle-hook-widget`, nunca con `zle -N zle-line-pre-redraw` (eso borraría el de zsh-syntax-highlighting). El hook de Smalti queda el último, para añadir la entrada `memo=smalti` del fantasma después de que zsh-syntax-highlighting reescriba `region_highlight`.
- ⌃R: `bindkey '^R' smalti-history` en `emacs`, `viins` y `vicmd`, sustituyendo a fzf.
- Tab: se guarda el widget que el usuario tenía en `^I` (ver "Tab" abajo).
- →: `smalti-accept` acepta el fantasma si el cursor está al final y hay fantasma; si no, ejecuta el widget que había en → (`forward-char` por defecto). Igual para `end-of-line` (⌃E).
- Las pruebas usan copias versionadas de zsh-autosuggestions, zsh-syntax-highlighting y del `key-bindings.zsh` de fzf (MIT), de las versiones de Homebrew de hoy, como fixtures; no las del sistema.

### Tab y el menú de completions **(Claude)**

- zsh decide sin esperar con la lista de `specs`: si el comando de la palabra actual no tiene spec, o la palabra termina en `**` (fzf), o la lista aún no llegó, Tab ejecuta **en el acto** el widget guardado del usuario.
- Con spec, zsh envía `complete` y vuelve; nunca espera. Si Smalti contesta `fallback` (sin candidatos), zsh ejecuta el widget guardado. Si no contesta en 300 ms, no pasa nada (el siguiente Tab lo reintenta).
- Archivos y carpetas (`template` de Fig) los completa el menú de Smalti, con la ruta relativa al directorio del panel.
- Un solo candidato se inserta directamente, sin menú, como zsh. Un prefijo común a todos se inserta antes de abrir el menú.
- Con el menú abierto: las letras y ⌫ llegan a zsh y el menú se refiltra con cada `line` nuevo; ↑ ↓ mueven la selección; Tab y ↩ insertan la selección (↩ nunca ejecuta la línea); esc cierra sin cambiar nada; cualquier otra tecla cierra el menú y llega a zsh.
- La máquina de estados del menú (cerrado, esperando, abierto, refiltrando) vive en el dominio, con sus pruebas.

### Detección del prompt (lado app)

- `TerminalViewProvider` expone `isAtPrompt` (consulta de 0,37 µs, en el hilo principal) y el rectángulo de la celda del cursor.
- El menú de completions y la paleta ⌃R solo se abren si `isAtPrompt`; se cierran solos si deja de serlo (comando lanzado, pantalla alternativa, proceso terminado).
- `KeyRouter` solo toma ↑, ↓, ↩, ⇥ y esc mientras un menú de F4 está abierto. Con el menú cerrado no intercepta nada nuevo.

### Dominio (`SmaltiCore/Domain/Input`)

- `CommandLine`: texto + cursor; `tokens` con comillas simples y dobles, escapes y `;`, `&&`, `||`, `|` (la completion actúa sobre el último comando simple).
- `CompletionSpec`: nombre, subcomandos, opciones (con `isRepeatable`, `requiresSeparator`, argumentos), argumentos (`template` de archivos o carpetas, sugerencias fijas, generador), `description`. Es el modelo que el adaptador de Fig produce.
- `CompletionEngine`: dado `CommandLine` y la spec, decide qué se completa (subcomando, opción, valor de opción, argumento) y filtra por prefijo y luego difuso; ordena por coincidencia y por uso del historial.
- `HistoryEntry`: comando, directorio, exit, duración, hora, panel. `HistoryIndex`: por comando (veces, último uso, por directorio, último exit) y por secuencia (`anterior → siguiente`); límite 100.000 entradas con compactación de las más antiguas **(Claude)**.
- `Prediction`: cada fuente es un tipo que implementa `PredictionRule` (OCP), y el resultado mezcla sus puntuaciones:
  - `DirectoryFrequency` (frecuencia × caída exponencial por recencia, vida media de 7 días **(Claude)**, en el directorio actual y, con menor peso, en todos);
  - `LearnedSequence` (qué se ejecutó después del comando anterior en este directorio);
  - `ProjectCommands` (scripts de `package.json` como `npm run <x>`, objetivos de `Makefile`, ramas de git para `git checkout`/`switch`);
  - `ExitRecovery` (tras un exit ≠ 0: la corrección que el usuario ejecutó después de ese mismo fallo en el pasado; reglas fijas iniciales: `git push` sin upstream → `git push -u origin <rama>`, comando con `sudo` olvidado no, porque requiere contraseña).
- La predicción con la línea vacía usa `LearnedSequence` y `ExitRecovery`; con texto, todas, filtradas por prefijo exacto (el fantasma solo completa, nunca cambia lo escrito).
- `FuzzySearch` para ⌃R: subsecuencia con bonus por inicio de palabra y por contigüidad; ámbito directorio o todos; empate por recencia.
- `SecretFilter`: detecta `*_KEY=`, `*_TOKEN=`, `*_SECRET=`, `PASSWORD=`, cabeceras `Authorization:`, tokens con forma conocida (`sk-…`, `ghp_…`, `github_pat_…`, `xox…-`, AWS `AKIA…`, JWT) y URLs con credenciales. Devuelve "limpio" o el texto redactado. En F4 decide qué no entra al historial; F7 lo usará antes de enviar contexto.

### Puertos (`SmaltiCore/Application`)

- `CompletionProvider`: `spec(for command:) async -> CompletionSpec?` y `generate(_ generator:, in directory:) async throws(CompletionError) -> [Suggestion]`.
- `PredictionProvider`: `predict(_ context: PredictionContext) -> Prediction?`. La implementación heurística vive en el dominio; F7 añade otras.
- `CommandHistory`: `load() async throws(HistoryError) -> [HistoryEntry]` y `append(_:)`.
- `ProjectContext`: `snapshot(of directory:) async -> ProjectSnapshot` (scripts, objetivos, rama, ramas locales), con caché por `mtime`.

### Casos de uso

`SuggestForLine`, `CompleteLine`, `SearchHistory`, `RecordCommand`. Cada uno corre en pruebas con fakes (`InMemoryCommandHistory`, `FakeCompletionProvider`, `FakeProjectContext`). Los dos primeros corren fuera del hilo principal (un actor de input).

### `FigCompletionAdapter`

- `scripts/fig/` con un `package.json` que fija `@withfig/autocomplete@2.692.3` (npm) y `scripts/fig/vendor-specs.py`, que copia el subconjunto curado a `Packages/FigCompletionAdapter/Sources/FigCompletionAdapter/Specs/` reescribiendo `export{X as default}` a `globalThis.__smaltiSpec = X`. Se versiona el resultado (no `node_modules`).
- Subconjunto inicial de 36 comandos **(Claude)**, todos verificados en 2.692.3: `git`, `gh`, `npm`, `npx`, `node`, `swift`, `xcodebuild`, `xcrun`, `brew`, `docker`, `cd`, `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `open`, `ssh`, `scp`, `curl`, `make`, `python3`, `pip3`, `kill`, `ps`, `grep`, `rg`, `fd`, `tar`, `nvim`, `code`, `supabase`, `terraform`, `kubectl`, `zig`. Fuera: `claude` (Fig no tiene spec; se puede escribir como spec propia) y `gcloud` (14 MB de subspecs). Ampliable sin código añadiendo nombres a la lista del script.
- El script resuelve `loadSpec` de forma transitiva (p. ej. `git` → `git-flow`, `docker` → `docker-compose`) y copia también esas dependencias; una dependencia que falte hace fallar el script.
- Specs propias del usuario: `~/.config/smalti/completions/*.js`, mismo formato (módulo con `export default`), con prioridad sobre las incluidas.
- Generadores: `script` (array o función) se ejecuta con `/bin/zsh -f -c` en el directorio del panel, entorno mínimo, **timeout 1 s y caché de 30 s por (script, directorio)** **(Claude)**; `postProcess`, `splitOn` y `custom` (con `executeShellCommand` puenteado al mismo ejecutor). El menú muestra primero lo fijo y añade lo generado al llegar.
- Un error de JS o de generador se traduce a `CompletionError` con el comando y la causa; el menú sigue con lo que tenga.

### UI

- **Fantasma:** lo pinta zsh en `#5f6672` (color de `Theme`, nuevo token `ghostText`). **Excepción de contraste:** ~3:1 sobre el vidrio, por debajo de 4.5:1; se acepta porque es un indicio que no hay que leer para usar la terminal, y se revisa en F5 con "Proteger legibilidad".
- **Menú de completions:** el de `Main.dc.html` (ancho 360, radio 10, borde `rgba(255,255,255,0.1)`, fondo `rgba(18,20,27,0.94)`, filas de 12 px con nombre en mono a 92 px y descripción en Inter en texto secundario, selección con `glow`). Se ancla a la celda del cursor: debajo si caben 6 filas, si no encima. Máximo 8 filas visibles con scroll. Pie con la línea de ayuda del tablero.
- **Paleta ⌃R:** la de `Paleta.dc.html` (radio 14, `rgba(20,22,30,0.82)` + desenfoque 36), centrada en el panel, 86 % de su ancho (mín. 480, máx. 720). Filas: comando en mono con las letras coincidentes en acento; a la derecha punto de estado del último exit (verde 0, rojo ≠ 0, hueco si no hay), recencia y `×N`. Chips "Este directorio" / "Todos" en la cabecera; pie "↩ insertar · ⌘↩ ejecutar · ⇥ cambiar ámbito · esc cerrar".
- Animaciones de aparición de 120 ms, ninguna con "Reducir movimiento".

### Textos nuevos (no están en los tableros)

"Este directorio", "Todos", "↩ insertar", "⌘↩ ejecutar", "⇥ cambiar ámbito", "esc cerrar", "hace N min" / "hace N h" / "ayer" / "hace N días", "×N", "Sin coincidencias", "Historial vacío: se llena con lo que ejecutes en Smalti". En ⌘K: "Buscar en el historial" (⌃R).

### Configuración (TOML)

```toml
[input]
enabled = true           # apaga todo F4 (el shell queda como sin Smalti)
predictions = true
completions = true
history_limit = 100000
generator_timeout_ms = 1000
```

### Atajos (editables en TOML)

| Acción | Atajo | Origen |
| --- | --- | --- |
| Aceptar sugerencia | → al final de la línea | Tablero |
| Completar | Tab | Tablero |
| Historial | ⌃R | Tablero |
| Moverse / elegir / cerrar en menús | ↑ ↓ / ↩ / esc | Propuesta |
| Ejecutar desde ⌃R / cambiar ámbito | ⌘↩ / ⇥ | Propuesta (maqueta aprobada) |

Ninguno usa ⌥.

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
| --- | --- | --- |
| C1 | **Cierre del roadmap:** p99 < 16 ms **de extremo a extremo**, desde que zsh envía `line` hasta que el fantasma está en `POSTDISPLAY`, con un historial de 50.000 entradas, tecla a tecla sobre 2.000 líneas parciales **(Claude)**. Se reporta aparte el p99 del dominio (`SuggestForLine`) | `scripts/measure-input.sh`, build Release, zsh real con un widget de medición y el servidor de input de Smalti, 5 corridas: historial sintético de 50.000 y, aparte, el `~/.zsh_history` real leído en solo lectura y en memoria (nunca se guarda). Informe de la fase |
| C2 | **Cierre del roadmap:** fuera del prompt nada cambia: en `cat -v`, `read`, pantalla alternativa, nvim, htop y less, las teclas Tab, ⌃R, →, ↑, ↓ y esc llegan como bytes al programa y no aparece ningún menú ni fantasma | XCUITest con un programa de prueba que registra los bytes recibidos; nvim/htop/less con captura y comprobación de que la acción de la tecla ocurrió (p. ej. `/` en less) |
| C3 | La lista de render de F0 (A9–A11) se repite con F4 activo y no empeora | Capturas antes/después en el informe; lo manual queda aplazado como en F0 |
| C4 | Detección del prompt: sí en el prompt, escribiendo y en PS2; no durante un comando, en `read`, en pantalla alternativa y con el proceso terminado | Prueba de integración de `GhosttyAdapter` (la del spike, convertida en prueba de verdad) |
| C5 | El shell nunca espera a Smalti ni muere por él: sin socket, con un servidor lento (responde a 2 s), con uno que **nunca lee** (búfer lleno), con uno que **cierra a mitad** (SIGPIPE) y con uno que responde `seq` viejos, escribir y ejecutar sigue igual, no queda fantasma viejo y, tras desactivarse, `yes \| head -1` sigue terminando normal | Pruebas de integración de zsh real (`zsh -d -i` con ZDOTDIR temporal, un servidor de pruebas por caso) |
| C6 | Canal: escape de tab, salto y barra; `seq` viejos descartados; `exec`/`done` dan comando, directorio, exit y duración; `HIST_IGNORE_SPACE`, `HISTORY_IGNORE` y secretos no entran al historial | Pruebas de dominio del protocolo + integración con zsh real |
| C7 | Toma de control: con las copias fixture de zsh-autosuggestions, zsh-syntax-highlighting y fzf cargadas por `.zshrc`, en Smalti solo hay un fantasma (el de Smalti), ⌃R abre la paleta y Tab sin spec ejecuta el widget anterior; sin Smalti, los tres funcionan como antes | Integración con zsh real |
| C8 | Completions: subcomandos, opciones, valores y argumentos de `git`, `npm` y `swift` con fixtures; archivos y carpetas; generador de ramas de git en un repo temporal; timeout de generador sin colgar el menú; spec propia del usuario con prioridad | Pruebas de dominio + del adaptador |
| C9 | Predicción: frecuencia/recencia por directorio, secuencias, scripts y objetivos del proyecto, recuperación tras un exit ≠ 0; límites con 0, 1 y 100.000 entradas, empates y cambio de día/zona (`America/Bogota`) | Pruebas de dominio |
| C10 | ⌃R: orden difuso, ámbito, ↩ inserta, ⌘↩ ejecuta, esc deja la línea como estaba | Dominio + XCUITest |
| C11 | Menú y paleta se ven como el tablero y las maquetas aprobadas | Captura superpuesta al 50 % sobre el tablero renderizado con Chrome, adjunta al PR |
| C12 | Filtro de secretos: cada forma listada se detecta y se redacta; falsos positivos conocidos (`echo KEY`, rutas con `token` en el nombre) no | Pruebas de dominio |
| C13 | Ningún trabajo de F4 bloquea el hilo principal más de 16 ms escribiendo 60 s seguidos con predicción y generadores activos | Sonda de latencia de F1 (`LatencyProbe`) |
| C14 | Guardas: `SmaltiCore` en Swift puro; solo `FigCompletionAdapter` importa JavaScriptCore; nada lee `~/.zsh_history` salvo `scripts/measure-input.sh` | `swift test` (guardas) + búsqueda en la prueba de guarda |
| C15 | Las UI tests usan `-SmaltiShellCommand "/bin/zsh -d"`, `ZDOTDIR` temporal, `-SmaltiConfigPath` y `-SmaltiStatePath` temporales, restauran el portapapeles y dejan intacto el Smalti diario | `isolatedSmalti()` + `scripts/check-daily-untouched.sh` |
| C16 | Mutación ≥ 80 % en `SmaltiCore` | `scripts/mutation/mutate.py` |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| zsh-autosuggestions cambia su forma de apagarse entre versiones | Dos fantasmas a la vez | Fixture de la versión de Homebrew actual; la toma de control comprueba tras instalarse que `POSTDISPLAY` solo lo escribe Smalti y, si no, se apaga a sí misma y lo anota en el log |
| zsh-syntax-highlighting o starship pisan `region_highlight` o el redibujado | Fantasma sin color o parpadeo | Se añade después de ellos en `zle-line-pre-redraw`; C7 lo prueba con las fixtures |
| Specs de Fig sin mantenimiento (última versión 2025-05) | Opciones nuevas de herramientas que faltan | Specs propias del usuario con prioridad; el subconjunto se puede regenerar |
| Generadores lentos o con efectos | Menú lento o comandos inesperados | Solo los de specs incluidas o del usuario; timeout, caché y entorno mínimo; nunca en el camino del fantasma |
| `zle -F` y `zsocket` con fd que se cierra a mitad | Shell muerto por SIGPIPE (verificado) o colgado escribiendo | Función de envío única con `zselect -w` y `trap '' PIPE` local; desactivación sin mensaje; C5 cubre los cinco casos |
| Ancho de JetBrains Mono de la capa distinto al de libghostty a otros tamaños | Menú desalineado | Se ancla por la celda que da `ime_point`, no por medir texto; captura a 11, 13 y 16 pt |

## Cambios en otros documentos (con esta spec)

- `docs/PROJECT.md`: pilar 5 — "editor de input" pasa a "zsh sigue siendo el editor; Smalti sugiere (fantasma, Tab, ⌃R)"; selección, multilínea y atajos propios, a "después de F4". Decisiones: fila nueva "Input en el prompt: ZLE + sugerencias de Smalti / Editor propio: rompe TUIs y pierde ZLE".
- `docs/ROADMAP.md`: F4 con el historial que empieza vacío y la toma de control de plugins; nueva "F4.5 · Ayuda y ventana" (vista de ayuda con todos los atajos, abierta con ⌘? y desde ⌘K; pantalla completa nativa ⌃⌘F; ideas que se sumen).
- `CLAUDE.md`: puertos `CommandHistory` y `ProjectContext`; paquetes `FigCompletionAdapter` y `ProjectContextAdapter`; las pruebas que necesitan la integración usan `"/bin/zsh -d"` con `ZDOTDIR` temporal.
- `docs/design/README.md`: token `ghostText` (`#5f6672`) y la excepción de contraste.

## Decisiones para aprobar con esta spec

1. zsh edita y Smalti sugiere; input en línea; ⌃R en paleta; historial desde cero; toma de control de plugins en los paneles de Smalti; pruebas con `zsh -d` y ZDOTDIR temporal; ayuda y pantalla completa a F4.5 (Simón).
2. Canal por socket con hook en `zle-line-pre-redraw` (vía `add-zle-hook-widget`), respuestas asíncronas con `zle -F -w`, escritura con `zselect -w` y SIGPIPE ignorado solo al escribir; fantasma pintado por zsh; capa AppKit solo para menús; directorio del panel por OSC 7.
3. Detección del prompt por `needs_confirm_quit` + `process_exited`, con `confirm-close-surface = true`.
4. Specs de Fig con JavaScriptCore; subconjunto curado de 36 comandos (sin `claude` ni `gcloud`) con sus `loadSpec`, versionado en el repo; specs propias en `~/.config/smalti/completions/`; generadores con timeout 1 s y caché 30 s.
10. Tab: decide zsh sin esperar con la lista `specs`; sin spec, con `**` o sin candidatos cae en el widget del usuario; un candidato se inserta sin menú; ↩ en el menú solo inserta; escribir con el menú abierto lo refiltra.
11. C1 se mide de extremo a extremo (zsh → fantasma en `POSTDISPLAY`), no solo el dominio.
12. El `.zshenv` de Smalti se encadena en todos los paneles con `[input] enabled`; argumento de lanzamiento nuevo `-SmaltiUserZdotdir` para las pruebas.
5. Historial JSONL en memoria, límite 100.000; lo que el filtro de secretos marca no se guarda.
6. Predicción por reglas (frecuencia/recencia con vida media de 7 días, secuencias, proyecto, recuperación por exit); el fantasma solo completa lo escrito.
7. Token `ghostText` `#5f6672` con excepción de contraste hasta F5.
8. Claves `[input]` en el TOML y los atajos de la tabla.
9. Puertos `CommandHistory` y `ProjectContext` nuevos; paquetes `FigCompletionAdapter` y `ProjectContextAdapter`.

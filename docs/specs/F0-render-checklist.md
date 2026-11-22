# F0 · Lista de render y verificación manual

Comparación lado a lado: Smalti (build de `feature/f0-spike`) y Ghostty.app 1.4.0, ejecutada por Claude el 2026-11-22 con capturas compuestas de pantalla (`docs/specs/F0-assets/`).

- **Comando de prueba:** cada caso se lanzó con un comando propio (`-SmaltiShellCommand`, y `ghostty -e` en Ghostty), sin el `.zshrc` de Simón, que engancha el shell a tmux.
- **Marcas:** ✅ verificado · ⚠️ verificado en parte · ⏳ pendiente de una persona.

## A9 · Claude Code

| Caso | Smalti | Ghostty.app | Evidencia / nota |
| --- | --- | --- | --- |
| Arranque de `claude` sin artefactos | ✅ | — | `a9-smalti-1.png`: logo, hook SessionStart y línea de estado limpios |
| Spinner animado sin parpadeo ni restos | ⚠️ | — | Visto en la captura a media respuesta; el parpadeo solo se juzga a ojo |
| Respuesta larga en streaming | ✅ | — | `a9-smalti-1.png` → `a9-smalti-2.png` |
| Diff con colores (añadido/borrado) | ✅ | — | `a9-smalti-2.png`: rojo/verde de la paleta Obsidiana |
| Prompt de permiso navegado con flechas | ⏳ | | No se pudo provocar sin herramientas reales |
| Redimensionar la ventana durante el streaming | ⏳ | | XCUITest no redimensiona ventanas de macOS de forma fiable |
| `/help` | ⏳ | | |
| Scroll del historial durante el streaming | ⏳ | | |
| Salir de Claude y volver al shell limpio | ⏳ | | |

Ghostty.app no se repitió para Claude Code: comparte el mismo libghostty v1.4.0 y el caso ya está limpio en Smalti.

## A10 · Programas de pantalla completa y texto

| Caso | Smalti | Ghostty.app | Evidencia / nota |
| --- | --- | --- | --- |
| nvim (pantalla alternativa, resaltado de sintaxis) | ✅ | ✅ | `a10-nvim-*.png` |
| Ratón en nvim (clic, selección, scroll) | ⏳ | | |
| htop | ✅ | ✅ | `a10-htop-*.png`: barras, colores y teclas de función |
| less / vim | ⏳ | | Mismo camino de pantalla alternativa que nvim |
| Emoji (`🙂👍🏽`) y CJK (`漢字かな`) con ancho correcto | ✅ | ✅ | `a10-text-*.png` |
| Paleta ANSI (rojo, verde, ámbar, azul, morado, cian) | ✅ | ✅ | `a10-text-*.png`: Smalti usa la paleta del diseño |
| Pegado entre corchetes (⌘V de varias líneas) | ⏳ | | ⌘V de una línea ✅ (E2E `testCommandVPastesClipboard`) |

## A11 · Teclado (layout Latin American)

| Caso | Smalti | Evidencia / nota |
| --- | --- | --- |
| Texto normal | ✅ | E2E `testTypingReachesShell` |
| Espacios | ⏳ | XCUITest los sintetiza como ⌃Espacio en este layout (ver nota del KB); hay que probarlos con el teclado físico |
| Acentos y ñ (á é í ó ú ñ ü), ¿ ¡ | ⚠️ | E2E `testSpecialCharactersReachShell` con entrada sintetizada; la composición real con tecla muerta queda ⏳ |
| Caracteres con ⌥ (@, \|, #, [, ], {, }) | ⚠️ | Llegan intactos con entrada sintetizada (misma prueba); falta pulsar ⌥ en el teclado físico |
| ⌃C, ⌃D, ⌃R, ⌃L en zsh | ⏳ | |
| ⌘V | ✅ | E2E `testCommandVPastesClipboard` (restaura el portapapeles) |
| ⌘C | ⏳ | Necesita seleccionar con el ratón |
| ⌘Q cierra la app | ✅ | E2E `testCommandQQuits` |

## Verificaciones del plan (Task 7, paso 6)

| Caso | Resultado | Evidencia / nota |
| --- | --- | --- |
| A6: `TERM` y terminfo | ✅ | `TERM=xterm-ghostty`; `TERMINFO` en `Smalti.app/Contents/Resources/terminfo`; `infocmp xterm-ghostty` resuelve |
| A7: eventos de la integración de shell | ✅ | zsh interactivo con `ZDOTDIR` vacío: `cd /tmp` → `workingDirectoryChanged(/tmp)`; `false` → `commandFinished(exitCode: 1)`; títulos llegan |
| A8: configuración aislada | ✅ | libghostty solo lee `Application Support/Smalti/ghostty.conf`; prueba de guarda `AdapterGuardTests` |
| `exit`: la ventana se cierra y la app termina | ✅ | E2E `testShellExitTerminatesApp` |
| Cambio de pantalla o de escala | ⏳ | Sin segundo monitor disponible |
| Interlineado frente al diseño | ✅ | 21,0 pt medido frente a 21,06 pt (13 px × 1,62) con `adjust-cell-height = 23%` |

## Mediciones (A12–A16)

| Medición | Smalti | Ghostty.app | Criterio | Resultado |
| --- | --- | --- | --- | --- |
| A12 `cat50mb` (mediana de 5) | 0,14 s | 0,14 s | ±10 % | ✅ 0 % |
| A12 `seq5m` (mediana de 5) | 7,46 s | 7,93 s | ±10 % | ✅ −6 % |
| A13 retraso máximo del hilo principal con 10 M líneas de salida (sonda de 5 ms, build Release) | 5,0 ms; 0 eventos > 16 ms | — | ninguno > 16 ms | ✅ (Instruments Hangs: 0 hangs) |
| A14 memoria en reposo con un panel (`footprint`) | 123 MB (Debug) | 153 MB | ≤ 1,2 × Ghostty | ✅ 0,80 × |
| A15 contraste `#d7dae0` sobre vidrio | 13,5:1 (escritorio actual) · 5,25:1 (fondo blanco) | — | ≥ 4.5:1 | ✅ (margen justo sobre blanco) |
| A16 A/B a ciegas, 10 min por terminal | — | — | indistinguibles | ⏳ requiere a Simón |

A13 es una aproximación: mide la latencia del hilo principal bajo salida masiva, que carga más que escribir con Claude en streaming, pero no mide las dos cosas a la vez.

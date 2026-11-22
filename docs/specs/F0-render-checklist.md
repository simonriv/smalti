# F0 · Lista de render y verificación manual

Se ejecuta lado a lado: Smalti (build Debug de `feature/f0-spike`) y Ghostty.app 1.4.0. Cada fila se marca con ✅, ❌ (con nota) o — (no aplica). Las grabaciones van en `docs/specs/F0-assets/`.

## A9 · Claude Code

| Caso | Smalti | Ghostty.app | Nota |
| --- | --- | --- | --- |
| Arranque de `claude` sin artefactos | | | |
| Spinner animado sin parpadeo ni restos | | | |
| Respuesta larga en streaming | | | |
| Diff con colores (añadido/borrado) | | | |
| Prompt de permiso navegado con flechas | | | |
| Redimensionar la ventana durante el streaming | | | |
| `/help` | | | |
| Scroll del historial durante el streaming | | | |
| Salir de Claude y volver al shell limpio | | | |

## A10 · Programas de pantalla completa y texto

| Caso | Smalti | Ghostty.app | Nota |
| --- | --- | --- | --- |
| nvim: abrir, editar, salir (pantalla alternativa) | | | |
| Ratón en nvim (clic, selección, scroll) | | | |
| htop | | | |
| less sobre un archivo largo | | | |
| vim | | | |
| Emoji (`echo 🙂👍🏽`) y CJK (`echo 漢字`) con ancho correcto | | | |
| Pegado entre corchetes (⌘V de varias líneas no ejecuta cada línea) | | | |

## A11 · Teclado (layout Latin American)

| Caso | Smalti | Nota |
| --- | --- | --- |
| Espacios y texto normal | | |
| Teclas muertas: á é í ó ú ñ ü | | |
| ¿ ¡ | | |
| Caracteres con ⌥ (@, \|, #, \\, [, ], {, }) | | |
| ⌃C, ⌃D, ⌃R, ⌃L en zsh | | |
| ⌘C / ⌘V | | |
| ⌘Q cierra la app; ⌘H la oculta | | |

## Verificaciones del plan (Task 7, paso 6)

| Caso | Resultado | Nota |
| --- | --- | --- |
| A7: `cd /tmp` → `workingDirectoryChanged`; `false` → `commandFinished(exitCode: 1)` (log `dev.simonriv.smalti` / `engine`) | | |
| `exit`: la ventana se cierra y la app termina | | |
| Mover la ventana a otra pantalla o cambiar la resolución: texto nítido | | |

## Mediciones (A12–A16)

| Medición | Smalti | Ghostty.app | Criterio |
| --- | --- | --- | --- |
| A12 `cat50mb` (mediana de 5, `scripts/bench/throughput.sh`) | | | ±10 % |
| A12 `seq5m` (mediana de 5) | | | ±10 % |
| A13 bloqueos del hilo principal > 16 ms escribiendo con Claude en streaming (Instruments, Hangs, 2 min) | | — | ninguno |
| A14 memoria en reposo con un panel (`footprint`) | | | ≤ 1,2 × Ghostty |
| A15 contraste `#d7dae0` sobre vidrio: escritorio oscuro / claro | | — | ≥ 4.5:1 |
| A16 A/B a ciegas, 10 min por terminal | | — | indistinguibles |

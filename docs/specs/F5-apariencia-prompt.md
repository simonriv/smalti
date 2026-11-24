# F5 · Apariencia y prompt — Spec

Estado: aprobada · 2026-11-23 · Roadmap: `docs/ROADMAP.md#f5--apariencia-y-prompt`
Diseño: `docs/design/Apariencia.dc.html` y `docs/design/Prompt.dc.html` (tableros aprobados). Lo que los tableros no cubren está en las maquetas de `F5-assets/`, que se aprueban con esta spec: `mockup-themes` (los cuatro temas), `mockup-buttons` (botones de ventana), `mockup-prompt` (el prompt en el panel y "Solo símbolo") y `mockup-legibility` ("Proteger legibilidad" sobre escritorio blanco). Cada una es un `.html` más su `.png`, y se regeneran con `generate-mockups.py`, que además comprueba el contraste de los temas.

## Objetivo

Cambiar tema, vidrio, colores, botones de ventana, tipografía y prompt desde la propia app, con vista en vivo y sin editar archivos. Todo lo que se cambia en la UI queda en un TOML legible, y lo que se edita a mano en ese TOML se ve en la UI.

Anti-objetivo: **F5 fracasa si el prompt hace esperar al shell (Smalti caído o lento nunca retrasa un prompt), si un nombre de rama o de directorio puede ejecutar algo o romper el prompt, si la app reescribe el `config.toml` del usuario, o si el contraste baja de 4.5:1 con "Proteger legibilidad" activo.**

## Decisiones de Simón en el brainstorming

| Tema | Elegido | Descartado y por qué |
| --- | --- | --- |
| Cómo se dibuja el prompt | **A: Smalti genera el `PROMPT` de zsh** desde `PromptConfig`, con colores truecolor del tema. Los iconos de trazo fino salen de una fuente propia de Smalti, mapeada con `font-codepoint-map`. Git y el runtime los calcula Smalti y llegan por el socket de F4, de forma asíncrona | B: capa AppKit sobre las filas del prompt. Frágil con el scroll, el redimensionado y el ajuste de línea, y el scrollback guardaría un prompt vacío |
| Previews de imágenes | **Salen de F5 a una fase nueva, F5.5.** No comparten nada con temas ni prompt | Dejarlas en F5: duplica una fase que ya es grande |
| Dónde escribe la UI | **Solo en `~/.config/smalti/theme.toml`, reescrito entero.** El `config.toml` del usuario nunca lo toca la app. Si `config.toml` aún trae `[appearance]`, gana `theme.toml` y "Recargar configuración" lo avisa | Editar `config.toml` en el sitio conservando comentarios: escritor frágil con tablas en línea y claves con puntos, y la app tocaría un archivo escrito a mano |
| "Proteger legibilidad" | **Activa por defecto, garantizada sobre el peor escritorio** (blanco detrás de los temas oscuros, negro detrás de Niebla). Sube la opacidad solo bajo las superficies con texto, y el fantasma se aclara hasta 4.5:1 | Desactivada por defecto: conserva el look del tablero, pero el fantasma se queda en ~3:1. Muestrear el fondo real: exige el permiso de Grabación de pantalla |
| UI de los paneles | **AppKit**, con las mismas piezas que la paleta, la ayuda y el feedback | SwiftUI en `NSHostingView`: un segundo sistema de UI y tokens que traducir |
| Módulo del agente | **Agentes que esperan del mismo workspace, actualizado en vivo** (Smalti manda el prompt sin esperar a zsh) | Último estado del agente de este panel: casi nunca se ve, porque el prompt vuelve cuando el agente ya terminó. Quitar el módulo |
| Prompt por defecto | **El de Smalti (`source = "smalti"`)**; el script fija `PROMPT` al final de `precmd` y gana al de `.zshrc` | El del shell por defecto: al instalar no cambia nada, contra "configurada desde que se instala" |
| Resto de propuestas | Aceptadas en bloque ("tus recomendaciones en todo"): las marcadas **(Claude)** abajo | — |

Las decisiones de Claude van marcadas con **(Claude)** y se resumen en "Decisiones para aprobar con esta spec".

## Alcance

1. Panel **Apariencia**: tema, vidrio (opacidad 30–95 % y desenfoque 0–48 px), "Proteger legibilidad", paleta ANSI editable, botones de ventana, fuente, espacio y radio, con vista en vivo en todos los paneles y ventanas abiertos.
2. Los cuatro temas completos: Obsidiana, Niebla (claro), Ámbar nocturno y Bosque.
3. "Proteger legibilidad" y el contraste del fantasma (heredado de F4).
4. Botones de ventana: Ocultos, Al pasar el cursor, Visibles (heredado de F4.5: Zoom hoy está en el menú y sin botón).
5. **Estudio de prompt**: vista previa en tres situaciones, plantillas, módulos ordenables, iconos, símbolo y disposición. "Aplicar a todos los paneles" y "Exportar como starship.toml".
6. Prompt generado por Smalti en zsh, con iconos propios y datos asíncronos. Opción de usar el prompt del shell.
7. `theme.toml`, equivalente a la UI en las dos direcciones.
8. Issue #5: GPU en reposo.

## Fuera de alcance

- **Previews de imágenes** (kitty, hover sobre enlace y Quick Look): pasan a **F5.5**.
- Temas propios del usuario más allá de los cuatro con su paleta ANSI editable. También un selector de acento en la UI: el tablero no lo tiene, así que `accent` sigue solo en el TOML.
- Prompt para shells distintos de zsh, o por SSH. Para eso existe la exportación a Starship.
- "Aumentar contraste" del sistema (A6 de la auditoría): sigue en "Después".
- Multi-harness y Neovim (F6); daemon y layouts compartibles (F7).

## Enfoques considerados

| Tema | Elegido | Alternativas |
| --- | --- | --- |
| Prompt | Generado por Smalti y pintado por zsh (Simón) | Capa AppKit (ver arriba) |
| Iconos de trazo fino | **Fuente `SmaltiSymbols` empaquetada, con los SVG en el área privada de Unicode (U+E900–U+E91F) y `font-codepoint-map` hacia ella** **(Claude)** | Nerd Font obligatoria: contradice `PROJECT.md`. Imágenes inline (kitty): no van en la línea del prompt de zsh |
| Datos del prompt | **Dos fases: zsh pinta al instante lo local** (directorio, símbolo, exit, duración, hora y el entorno de k8s y AWS); **Smalti responde después** con git, runtime y agente, y zsh hace `zle reset-prompt` **(Claude)** | Esperar a Smalti en `precmd` con tiempo máximo: el shell espera, que es el anti-objetivo. Calcular git en zsh: lento en repos grandes (el problema de Powerlevel10k) |
| Quién arma el texto del prompt | **El dominio (`ZshPromptRenderer`, Swift puro)**: zsh solo recibe cadenas ya escapadas **(Claude)** | Plantilla en el script de zsh: lógica duplicada entre Swift y zsh, sin pruebas de dominio ni mutación |
| Escritura de `theme.toml` | **Serializador propio y determinista en `TOMLConfigAdapter`**, que escribe el archivo entero en orden fijo **(Claude)** | Edición en el sitio (descartada por Simón) |
| UI | AppKit (Simón) | SwiftUI |

## Diseño técnico

### Módulos

| Módulo | Qué añade |
| --- | --- |
| `SmaltiCore/Domain/Theme` | `ThemeID`, `ThemeCatalog` (los cuatro `Theme` completos), `ANSIPalette` con diferencias por tema, `ContrastRatio` (WCAG 2.x), `LegibilityGuard` |
| `SmaltiCore/Domain/Prompt` (nuevo) | `PromptConfig`, protocolo `PromptModule` (un tipo por módulo), protocolo `PromptStyle` (Limpio, Píldoras, Solo símbolo), `PromptLayout`, `PromptIcons`, `PromptContext`, `ZshPromptRenderer`, `StarshipPreset` (modelo de la exportación), `HeaderContext` |
| `SmaltiCore/Domain/Config` | `AppearanceSettings` con `theme`, `protectLegibility` y `ansiOverrides`; `WindowSettings.buttons`; `SmaltiConfig.prompt`; ids y atajos nuevos |
| `SmaltiCore/Application` | Puertos `AppearanceStore` (`save`) y `PromptFacts` (`facts(for:)`); casos de uso `ChangeAppearance`, `EditPrompt`, `RenderPrompt`, `ExportStarship` |
| `TOMLConfigAdapter` | Lee `theme.toml` y lo mezcla sobre `config.toml`; `AppearanceStore` (serializador); texto de `starship.toml` |
| `ProjectContextAdapter` | `PromptFacts`: cambios de git y versiones de runtime, con caché y tiempo máximo |
| `GhosttyAdapter` | Config del motor por tema (paleta, fondo y primer plano), `font-codepoint-map` hacia `SmaltiSymbols`; script de zsh del prompt; mensajes nuevos del canal |
| `SmaltiApp` | Paneles Apariencia y Estudio de prompt, botones de ventana, capas de legibilidad, cabecera con contexto, registro de la fuente `SmaltiSymbols` |

### Temas

- **Un tema es un `Theme` completo** con todos los tokens que hoy tiene Obsidiana: ventana, panel, chrome, texto, estados, menús y superposiciones. Los tokens de tamaño y movimiento son comunes. Cada tema define sus colores. `Theme.obsidian` pasa a ser `ThemeCatalog.obsidian`.
- **Colores de partida (Claude):** salen de las muestras del tablero (fondo, acento, texto y verde de cada tarjeta), completadas en `F5-assets/generate-mockups.py` (`THEMES`), que es la tabla fuente hasta escribir `ThemeCatalog`. Los tokens que esa tabla no lista (bordes de menús, selección y superposiciones) se derivan con la misma regla que en Obsidiana: el mismo color base con la misma opacidad.
- **Niebla es claro (Claude):** bordes `rgba(0,0,0,…)` en lugar de blanco, sombra más suave y los estados con el mismo tono pero más oscuros (`#2f9e44`, `#c77c02`, `#e03131`). "Estado codificado siempre igual" se refiere al significado y al tono, no al hex exacto. Sus ANSI están oscurecidos respecto a la muestra del tablero (el verde `#2f9e44` daba 3,4:1 sobre blanco).
- **Regla de los temas (Claude):** sobre el color opaco de su panel, todo color protegido de cada tema da ≥ 4.5:1 sin ajustes (lo comprueba `check_themes()` y, en el código, una prueba de dominio). Son colores protegidos el texto, el secundario y los ANSI salvo la pareja de fondo: 0 y 8 en los temas oscuros, 7 y 15 en Niebla.
- **Paleta ANSI editable:** cada muestra del panel abre el `NSColorPanel` del sistema. Lo editado se guarda como diferencia del tema activo (`[appearance.ansi.<tema>]`): tocar Bosque no cambia Obsidiana. "Restablecer paleta ANSI" va en ⌘K **(Claude)**.
- **Acento:** cada tema trae el suyo. Si `accent` está en un TOML, gana sobre el del tema, y elegir un tema en la UI lo quita de `theme.toml` **(Claude)**.
- **Cambio en vivo:** cambiar el tema o la paleta actualiza todas las ventanas y superficies sin relanzar shells, por el mismo camino que "Recargar configuración". El texto que ya está en el scrollback conserva los colores con los que se pintó (lo pinta libghostty con sus índices ANSI: cambia con la paleta; lo truecolor no).

### "Proteger legibilidad"

- **Regla (`LegibilityGuard`, dominio):** sea el escritorio peor (blanco para los temas oscuros, negro para Niebla), el vidrio de la ventana a la opacidad elegida y, encima, cada superficie con texto. Para cada superficie se calcula la **opacidad mínima** que deja todo color protegido que se pinta sobre ella a ≥ 4.5:1. Si la opacidad del usuario es menor, se usa la mínima. La opacidad elegida nunca baja.
- **Superficies (Claude):** paneles (texto del terminal), franja superior, cabeceras de panel, barra de estado y superposiciones (⌘K, ayuda, búsqueda, menús, Apariencia y Estudio). Los márgenes y los huecos de 8 px conservan el vidrio del usuario. Con Obsidiana a 62 %: paneles del 34 al 66 %, franja y barra de estado al 89 % (`mockup-legibility`). Niebla: paneles al 83 %. La búsqueda apunta a 4.55, un margen sobre el 4.5 para la mezcla sin redondeo de Core Animation (revisión del bloque 1).
- **Fantasma:** con la protección activa se mezcla hacia el color del texto en pasos del 1 % hasta llegar a 4.5:1 sobre el panel protegido. Sin protección, queda en el ~3:1 del tema: la excepción de F4 sigue documentada solo para ese caso.
- **Colores ANSI editados por el usuario:** si alguno no llega a 4.5:1 ni con el panel opaco, se ajusta al pintarlo (mezcla hacia el texto o hacia el fondo, según el tema). El TOML guarda lo que eligió el usuario y el panel lo avisa con "Ajustados por legibilidad: N colores" **(Claude)**.
- **Sin protección:** se pinta exactamente lo que dice el tema.
- El desenfoque no entra en el cálculo: el peor caso es un escritorio uniforme, que el desenfoque no cambia.

### Botones de ventana

- `[window] buttons = "hidden" | "hover" | "visible"`; `hidden` por defecto (`mockup-buttons`).
- **Visibles:** los tres semáforos nativos de AppKit (`standardWindowButton`), centrados en la franja de 40 px. Las pastillas de workspace se corren 72 px.
- **Al pasar el cursor:** aparecen cuando el cursor entra en la franja y se ocultan al salir, con un fundido de 150 ms que se quita con "Reducir movimiento". Las pastillas no se mueven: los botones aparecen sobre el margen izquierdo, que se ensancha a 72 px solo en este modo **(Claude)**.
- **Cerrar:** pasa por la misma confirmación que ⇧⌘W. La ventana gana `.closable` en el `styleMask`, y ⌘W sigue siendo "Cerrar panel" porque el `KeyRouter` lo atiende antes que AppKit. **Minimizar** = ⌘M. **Zoom** = `performZoom`, igual que en el menú Ventana.
- En pantalla completa se ven los que pone macOS, como hoy.

### Estudio de prompt

**Modelo (dominio):**

- `PromptConfig`: `source` (`smalti` | `shell`), `style` (`clean` | `pills` | `symbolOnly`), `layout` (`twoLines` | `oneLine`), `modules` (lista ordenada de los activos), `icons` (`thin` | `nerd` | `none`) y `symbol` (`›` `❯` `λ` `$`).
- **Plantillas = combinaciones, no un campo (Claude):**

  | Plantilla | Estilo | Disposición |
  | --- | --- | --- |
  | Línea limpia | Limpio | Dos líneas |
  | Una sola línea | Limpio | Una línea |
  | Píldoras | Píldoras | Una línea |
  | Solo símbolo | Solo símbolo | (no aplica) |

  La tarjeta marcada es la que coincide. Si se cambia la disposición a mano, la marca sigue a la combinación nueva. El TOML guarda `style` y `layout`, así que no hay un dato duplicado.
- **Módulos:** cada uno es un tipo que implementa `PromptModule` (`id`, `segment(in: PromptContext) -> PromptSegment?`, `starship`). Un módulo que no aplica devuelve `nil` y no aparece. Los módulos, con su origen:

  | Módulo (texto del tablero) | Contenido | Origen |
  | --- | --- | --- |
  | Directorio · últimos 2 niveles | Fuera de un repo, los 2 últimos niveles (`%2~`, `~` para el home). Dentro de un repo, desde su raíz con el nombre del repo (`solen/apps/api`, como en el tablero) **(Claude)** | zsh al instante (`%2~`, o la raíz del repo que recuerda el script para ese directorio); Smalti confirma la raíz en la respuesta completa |
  | Rama git | rama, o el SHA corto si HEAD está suelto | Smalti (`ProjectContext`, ya existe) |
  | Cambios git · ●2 +1 | ● modificados sin preparar, + preparados | Smalti (`PromptFacts`: `git status --porcelain=v2 --untracked-files=no`, máximo 300 ms; si se pasa, el módulo no sale) |
  | Runtime · Node, Bun, Python, Go | versión del primero que aplique según los archivos del proyecto (`package.json`/`bun.lockb`, `pyproject.toml`/`requirements.txt`, `go.mod`) | Smalti (`PromptFacts`, `--version` del ejecutable que zsh resuelve con `$commands[…]`, en caché por ruta y fecha de modificación) |
  | Duración · si pasa de 2 s | `4.2s` | zsh (`EPOCHREALTIME` en `preexec`/`precmd`) |
  | **Agentes que esperan** (en el tablero, "Estado del agente del panel"; renombrado por Simón) | Los agentes **del mismo workspace** que te esperan o fallaron, con el color de su estado: `● claude te espera`; con varios, `● 2 te esperan`. No sale si ninguno espera ni falló | Smalti (estado de los paneles, F2), **actualizado en vivo**: cuando cambia el estado, Smalti manda un `prompt` nuevo sin esperar a `context` |
  | Hora | `HH:mm` | zsh |
  | Contexto de Kubernetes / AWS | `$AWS_PROFILE` y el contexto actual de `$KUBECONFIG` (o `~/.kube/config`) | zsh manda el entorno y Smalti lee el kubeconfig |

  Por defecto quedan activos los seis primeros, como en el tablero.
- **Exit:** el símbolo se pinta con el color de error y le sigue `exit N` en texto secundario cuando el último comando falló (tablero: "Después de un error"). No es un módulo: va siempre con el símbolo **(Claude)**.
- **Solo símbolo:** la línea lleva solo el símbolo. El contexto (los mismos módulos, en texto secundario) va en la cabecera del panel, en el lugar de la ruta, recortado por la izquierda del directorio si no cabe (`mockup-prompt`).
- **Píldoras:** cada segmento lleva como fondo su color al 16 %, mezclado con el fondo del panel en un color opaco. zsh no tiene transparencia **(Claude)**.
- **Iconos:**
  - `thin`: glifos de `SmaltiSymbols` (carpeta, rama y hexágono del tablero; los de Bun, Python, Go, reloj, Kubernetes y nube se dibujan con el mismo trazo de 1.4 px sobre una rejilla de 16 y van en una lámina de iconos en el PR del bloque, para aprobarlos ahí).
  - `nerd`: los glifos de Nerd Font, ofrecidos solo si hay una instalada (`CTFontManager`). Sin ella, la opción se ve desactivada con "No hay una Nerd Font instalada".
  - `none`: sin iconos.

**Del dominio a zsh:**

- `ZshPromptRenderer` produce dos cadenas por panel. La **inmediata** usa escapes de zsh para lo local (`%~` recortado, `%(?..)` para el exit y la duración desde una variable del script). La **completa** añade lo que trae Smalti. Las dos llevan colores `%F{#rrggbb}` del tema, ya protegidos.
- **Escapado (obligatorio):** todo texto que viene de fuera (directorio, rama, perfil de AWS o contexto de k8s) llega a zsh en las casillas de `psvar` y el prompt lo muestra con `%Nv`: zsh inserta ese texto tal cual, sin expandir `%`, `$(…)`, `` ` `` ni `\`, y sin depender de `PROMPT_SUBST` ni de otra opción del usuario. Casillas: 1 el símbolo, 2 el directorio, 3 la duración (con `%(3V.…)` para que solo aparezca si existe) y de la 4 en adelante los valores del prompt completo. Solo se cambian saltos de línea y tabuladores y se quitan los caracteres de control. Hay prueba con una rama llamada `$(touch pwned)%F{red}` con y sin `PROMPT_SUBST` (enmienda 1: antes eran variables `${_smalti_p_N}` con `PROMPT_SUBST` activado por el script).
- **Mensajes nuevos del canal de F4** (mismas reglas: una línea, campos separados por tab y escapados, menos de 2000 bytes, envío que nunca cuelga):
  - zsh → Smalti: `context <seq> <pwd> <exit> <duración_ms> <aws_profile> <kubeconfig> <rutas de runtime>` en `precmd`, después de `done`.
  - Smalti → zsh: `prompt <seq> <inmediata> <completa>`. zsh guarda la inmediata para los prompts siguientes y pinta la completa con `zle reset-prompt` si `seq` es el último que mandó. **Envío espontáneo:** cuando cambia el estado de un agente del workspace, Smalti vuelve a mandar `prompt` con el `seq` del último `context` de ese shell. zsh lo aplica solo si sigue en el prompt de ese `seq` (no ha ejecutado nada después) y hace `zle reset-prompt` sin tocar `BUFFER` ni el fantasma. Durante un comando no se manda nada. Además, `promptstyle <inmediata> <color_fantasma>` llega al conectar y cada vez que cambia la configuración, sin `seq`: zsh lo aplica en el siguiente redibujado. Así el fantasma cambia en vivo y deja de depender de `SMALTI_GHOST_COLOR` fijado al lanzar.
- **Sin respuesta de Smalti:** el prompt se queda con la inmediata. Si el canal cae, el script vuelve a la última inmediata recibida y, si nunca recibió una, deja el `PROMPT` del usuario.
- `source = "smalti"` es el valor por defecto (Simón). El script reasigna `PROMPT` y `RPROMPT` en una función que se coloca **la última** de `precmd_functions` en cada `precmd`, así gana a lo que ponga `.zshrc` o un framework.
- `source = "shell"`: el script no toca `PROMPT` ni `RPROMPT`.
- **Independiente de `[input] enabled` (Claude):** el script y el canal se cargan si `[input] enabled` o si `source = "smalti"`. Dentro del script, las funciones de F4 (fantasma, Tab, ⌃R) solo se activan con `[input] enabled`. C8 y C10 se prueban con el input encendido y apagado.
- **Aplicar a todos los paneles:** el estudio edita un borrador con vista previa en las tres situaciones del tablero (con datos fijos de ejemplo). Aplicar guarda `theme.toml` y manda `promptstyle` a todos los shells. Los prompts que ya están en el scrollback no cambian.

**Exportar como starship.toml:**

- Un `NSSavePanel` con el nombre `starship.toml` en `~/.config`. El panel avisa si el archivo existe, y escribir solo pasa con confirmación.
- `StarshipPreset` mapea cada módulo a `directory` (`truncation_length = 2`, `truncate_to_repo = true`), `git_branch`, `git_status`, `nodejs`/`bun`/`python`/`golang`, `cmd_duration` (`min_time = 2000`), `time`, `kubernetes` y `aws`, más `character` con el símbolo.
- Colores en hex del tema. `nerd` exporta los símbolos de Nerd Font. `thin` y `none` exportan sin iconos, porque la fuente de Smalti no existe fuera.
- "Agentes que esperan" no tiene equivalente y sale como comentario.
- Hay prueba con un archivo dorado y otra que lo vuelve a leer como TOML válido.

### Paneles de la app

- **Apariencia** (`Apariencia.dc.html`) y **Estudio de prompt** (`Prompt.dc.html`) son superposiciones dentro de la ventana activa, del mismo tamaño y en la misma posición que en el tablero. Su contenido no se pinta sobre los paneles: la zona de paneles se encoge a la izquierda y sigue viva, para que la vista en vivo sea real **(Claude)**.
- En el Estudio, la izquierda muestra la vista previa de las tres situaciones (no los paneles), como el tablero.
- **Abrir y cerrar:** ⌘, abre Apariencia y ⇧⌘P abre el Estudio. Las dos están en ⌘K, en el menú Smalti ("Apariencia…" y "Estudio de prompt…") y en la ayuda. Esc cierra.
- "Abrir config.toml" pasa a ⌥⌘, (antes era ⌘,). Hay una entrada nueva "Abrir theme.toml" en ⌘K **(Claude)**.
- **Teclado:** Tab recorre los controles, las flechas mueven los deslizadores (1 % y 1 px; con ⇧, 10), Espacio activa, y los módulos se reordenan también con ⌘↑ y ⌘↓, además de arrastrarlos. "Sin botones fijos" se cumple: "Aplicar a todos los paneles" y "Exportar como starship.toml" están dentro de un panel que se abre a propósito y también en ⌘K.
- **Cuándo se guarda:** Apariencia escribe `theme.toml` 300 ms después del último cambio, agrupando los arrastres de un deslizador. El Estudio guarda al pulsar Aplicar.
- Textos: los de los tableros, tal cual. "se guarda en ~/.config/…/theme.toml" muestra la ruta real abreviada.

### `theme.toml`

```toml
# Lo escribe Smalti (Apariencia y Estudio de prompt). Puedes editarlo a mano: la app lo lee al recargar y lo reescribe entero al guardar.
[appearance]
theme = "obsidiana"            # obsidiana | niebla | ambar-nocturno | bosque
glass_opacity = 0.62           # 0.30–0.95
blur = 28                      # 0–48
protect_legibility = true
font_family = "JetBrains Mono"
font_size = 13
gap = 8
radius = 11

[appearance.ansi.bosque]       # solo los colores cambiados, por índice 0–15
1 = "#ff6b6b"

[window]
buttons = "hidden"             # hidden | hover | visible

[prompt]
source = "smalti"              # smalti | shell
style = "clean"                # clean | pills | symbol-only
layout = "two-lines"           # two-lines | one-line
modules = ["directory", "git-branch", "git-status", "runtime", "duration", "agents"]
icons = "thin"                 # thin | nerd | none
symbol = "›"
```

- **Precedencia:** valores por defecto < `config.toml` < `theme.toml`, clave a clave. Si una clave de apariencia, ventana o prompt está en los dos archivos, gana `theme.toml` y "Recargar configuración" muestra un aviso con las claves repetidas. `[window] confirm_close` (F4.5) sigue en `config.toml`, porque la UI no lo toca.
- **Errores:** igual que `config.toml`: un valor inválido no se aplica, se mantiene la última configuración válida y el aviso dice el archivo, la línea y la clave.
- **Ida y vuelta:** `parse(write(x)) == x` para toda configuración válida. Lo que la UI no muestra (`accent`) se conserva al reescribir.
- **Escritura atómica:** archivo temporal y renombrado. Si `theme.toml` cambió en disco desde la última lectura, antes de escribir se recarga y se aplica el cambio de la UI encima, para no pisar una edición a mano **(Claude)**.

### Issue #5: GPU en reposo

- **Primera tarea del bloque de vidrio: un spike medido.** Hay que separar las tres hipótesis del issue (máscara de esquinas, desenfoque y sombra) con builds que quiten una cada vez, y medir con `ioreg` (`Device Utilization %`, media de 10 muestras de 1 s, sin sudo) en un script nuevo, `scripts/measure-gpu-idle.sh`, que usa el build Debug "Smalti Dev" y nunca el diario.
- **Criterio (Claude): ≤ 10 % de GPU en reposo** con la configuración por defecto y un panel, frente al ~25 % de hoy y a una base del sistema del 5 %.
- **Si la causa es el desenfoque privado y no tiene arreglo sin perderlo:** la fase se para y se lleva el dato a Simón antes de decidir. No se cambia el aspecto en silencio.

### Comandos y atajos nuevos

| Id | Texto (⌘K y menú) | Atajo |
| --- | --- | --- |
| `appearance.open` | Apariencia… | ⌘, |
| `prompt.studio` | Estudio de prompt… | ⇧⌘P |
| `config.open` | Abrir config.toml | ⌥⌘, (antes ⌘,) |
| `theme.open` | Abrir theme.toml | — |
| `theme.next` | Siguiente tema | — |
| `ansi.reset` | Restablecer paleta ANSI | — |
| `prompt.apply` | Aplicar prompt a todos los paneles | — (en el Estudio) |
| `prompt.export` | Exportar como starship.toml | — |
| `legibility.toggle` | Proteger legibilidad | — |

Todos aparecen en la ayuda (⌘?). Los atajos nuevos no usan ⌥ sin ⌘.

### Textos nuevos (no están en los tableros)

"Apariencia…", "Estudio de prompt…", "Abrir theme.toml", "Siguiente tema", "Restablecer paleta ANSI", "Agentes que esperan" (reemplaza "Estado del agente del panel" del tablero), "2 te esperan", "Ajustados por legibilidad: N colores", "No hay una Nerd Font instalada", "Prompt del shell" (el interruptor de `source`, bajo "Disposición"), los textos del diálogo de exportación y el aviso de claves repetidas: "theme.toml manda sobre config.toml en: …".

## Criterios de aceptación

| # | Criterio | Cómo se verifica |
| --- | --- | --- |
| C1 | **Cierre del roadmap, ida y vuelta:** cada ajuste de los dos tableros cambiado desde la UI aparece en `theme.toml`, y cada uno escrito en `theme.toml` y recargado aparece en la UI y se aplica | Dominio (`parse(write(x)) == x` con todas las combinaciones de enums y los bordes de los rangos) + XCUITest que recorre los controles y lee el archivo, y al revés |
| C2 | **Contraste ≥ 4.5:1 con la protección activa**, en los cuatro temas, con opacidades de 30 a 95 %, paletas editadas y el fantasma | Dominio (`LegibilityGuard` contra el peor escritorio) + medición: captura de la app sobre una ventana blanca y contraste de los tokens contra el fondo de panel muestreado |
| C3 | Sin protección, se pinta el tema exacto y el fantasma queda en ~3:1 | Dominio |
| C4 | Los cuatro temas se ven como `mockup-themes` y el panel Apariencia como su tablero | Captura superpuesta al 50 % sobre la maqueta o el tablero, adjunta al PR |
| C5 | Botones: los tres modos; "al pasar el cursor" los muestra en la franja y los oculta fuera; cerrar pide confirmación con un proceso en marcha; Zoom y Minimizar funcionan | XCUITest |
| C6 | **#5:** GPU en reposo ≤ 10 % con la config por defecto y un panel (o la decisión de Simón con el dato del spike) | `scripts/measure-gpu-idle.sh`, informe en el checklist |
| C7 | Prompt: las cuatro plantillas, los módulos ordenados, los iconos y el símbolo salen en un zsh real (`zsh -d` con ZDOTDIR temporal) tal como en la vista previa | Integración del adaptador (texto del `PROMPT` resultante) + XCUITest con captura |
| C8 | **El shell nunca espera:** con Smalti sin responder (servidor que no lee), el prompt inmediato aparece en el mismo tiempo que sin canal (± 5 ms en 20 prompts) | Prueba de integración con un servidor mudo |
| C9 | Escapado: una rama `$(touch pwned)%F{red}` y un directorio con `%` se muestran literales y no crean archivos, con y sin `PROMPT_SUBST` | Dominio + integración con zsh |
| C10 | `source = "shell"` deja `PROMPT` y `RPROMPT` del usuario intactos; con `source = "smalti"` (por defecto) el de Smalti gana a un `PROMPT` de `.zshrc` y a un hook de `precmd` que imita a Starship | Integración con zsh |
| C10b | Agentes que esperan: con el shell quieto en el prompt, un agente de otro panel del workspace pasa a "te espera" y el prompt lo muestra sin pulsar nada, sin tocar lo escrito; tras ejecutar un comando, un `prompt` espontáneo viejo se descarta | Integración del adaptador + XCUITest con un evento de hooks grabado |
| C11 | Exportación: el `starship.toml` coincide con el dorado de cada plantilla y es TOML válido | Dominio + `TOMLConfigAdapter` |
| C12 | Vista en vivo: cambiar tema, vidrio, paleta y prompt actualiza todas las ventanas y paneles abiertos sin relanzar shells | XCUITest con 2 ventanas |
| C13 | ⌘, abre Apariencia, ⇧⌘P el Estudio, ⌥⌘, el `config.toml`; todo está en ⌘K, en el menú y en la ayuda | Dominio (catálogo y `Keymap`) + XCUITest |
| C14 | `config.toml` no cambia nunca por la UI (hash antes y después de recorrer los dos paneles); el aviso de claves repetidas sale | XCUITest + `TOMLConfigAdapter` |
| C15 | "Reducir movimiento" quita los fundidos de los botones y de los paneles | Prueba de la app |
| C16 | La lista de render de F0 (A9–A11) se repite con cada tema y no empeora | Capturas en el informe |
| C17 | Guardas: `SmaltiCore` en Swift puro; solo `GhosttyAdapter` importa GhosttyKit; ningún `Logger` publica el texto del prompt ni rutas | Pruebas de guarda |
| C18 | Las UI tests usan `-SmaltiShellCommand "/bin/zsh -f"` (o `zsh -d` con ZDOTDIR temporal en las del prompt), config y estado temporales (también `theme.toml` y el destino de la exportación), restauran el portapapeles y dejan intacto el Smalti diario | `isolatedSmalti()` + `scripts/check-daily-untouched.sh` |
| C19 | Mutación ≥ 80 % en `SmaltiCore` | `scripts/mutation/mutate.py` |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| `font-codepoint-map` no alcanza una fuente registrada solo para el proceso | Sin iconos de trazo fino | Primera tarea del bloque del prompt: verificarlo con libghostty v1.4.0 (como hizo F4 con JetBrains Mono). Plan B: instalar `SmaltiSymbols` en `~/Library/Fonts` con aviso, o caer a `none` |
| El parpadeo entre el prompt inmediato y el completo molesta | Prompt que "salta" | Lo inmediato reserva el hueco de los módulos de Smalti con lo último conocido para ese directorio (caché en el script). Se mide en C7 |
| `git status` lento en repos grandes | Sin "Cambios git" | Tiempo máximo de 300 ms, `--no-optional-locks` y una sola consulta por repo cada segundo (enmienda 2: la firma de `.git/index` no cambia al editar un archivo); el módulo no sale si no hay dato |
| La protección deja el vidrio casi opaco | El tablero se ve distinto | Decidido por Simón; los huecos conservan el vidrio, y la UI muestra la opacidad efectiva junto al deslizador ("62 % · 65 % bajo el texto") **(Claude)** |
| La causa de #5 es el desenfoque privado | No se llega al 10 % sin perder el vidrio | Se para y se decide con el dato (ver #5) |
| Cambiar ⌘, rompe la costumbre de F4.5 | Molestia | La convención de macOS manda; ⌥⌘, y ⌘K siguen abriendo el TOML |

## Cambios en otros documentos (con esta spec)

- `docs/ROADMAP.md`: F5 apunta a esta spec y se le quitan las previews. Nueva **F5.5 · Previews** (kitty, hover sobre enlace y Quick Look), entre F5 y F6.
- `docs/PROJECT.md`:
  - pilar 7: "prompt generado por Smalti y pintado por zsh, con iconos de trazo fino de una fuente propia";
  - Decisión "Prompt": "Generado por Smalti (zsh lo pinta), exportable a Starship". Descartado: capa AppKit sobre la terminal, por frágil con el scroll y el scrollback;
  - la fase F5 sin previews, y F5.5 añadida.
- `docs/design/README.md`: los tokens de los cuatro temas y la nota del fantasma (excepción solo sin protección); maquetas de F5 como referencia aprobada.
- `CLAUDE.md`: puertos `AppearanceStore` y `PromptFacts`; `theme.toml`; comando de `measure-gpu-idle.sh`.

## Decisiones para aprobar con esta spec

1. Las de Simón de la tabla del principio: prompt A, previews a F5.5, `theme.toml`, protección activa sobre el peor escritorio, AppKit, agentes que esperan en vivo y prompt de Smalti por defecto.
2. Colores completos de Niebla, Ámbar nocturno y Bosque (`mockup-themes`), con estados de Niebla más oscuros y la regla de ≥ 4.5:1 sobre su propio panel.
3. Superficies protegidas: paneles, franja, cabeceras, barra de estado y superposiciones; huecos y márgenes conservan el vidrio. Colores ANSI editados se ajustan al pintar y el TOML guarda lo elegido.
4. Paleta ANSI con diferencias por tema; `accent` solo en el TOML y elegir un tema lo quita.
5. Botones: semáforos nativos; en "al pasar el cursor" el margen crece sin mover las pastillas; cerrar con confirmación.
6. Plantillas como combinaciones de estilo y disposición; el exit va con el símbolo; contexto en la cabecera para "Solo símbolo"; píldoras con fondo opaco mezclado.
7. Prompt en dos fases (inmediato de zsh y completo de Smalti), texto armado en el dominio y escapado por variables; mensajes `context`, `prompt` y `promptstyle`.
8. `SmaltiSymbols` en U+E900–U+E91F; los iconos nuevos se aprueban en una lámina en el PR del bloque.
9. Paneles como superposiciones que encogen la zona de paneles; ⌘, = Apariencia, ⇧⌘P = Estudio, ⌥⌘, = `config.toml`; guardado de Apariencia con 300 ms de espera y del Estudio al aplicar.
10. GPU en reposo ≤ 10 % como criterio de #5, con spike al principio.
11. Exportación a Starship con diálogo de guardado y confirmación al sobrescribir.

## Enmiendas

1. **2026-11-23 · Bloque 3 (T11), Claude.** El prompt muestra el texto de fuera con `psvar` y `%Nv` en lugar de variables `${…}` con `PROMPT_SUBST`. Motivo: el script corre con `emulate -L zsh`, que devuelve las opciones al salir, así que activar `PROMPT_SUBST` de forma global desde ahí no era fiable y un redibujado podía mostrar `${…}` literal. Con `psvar`, zsh inserta el texto tal cual sin ninguna opción, y la garantía de seguridad es más fuerte (comprobado en zsh 5.9, incluso con `PROMPT_SUBST` activo). Con `source = "shell"`, Smalti sigue enviando `promptstyle` con el prompt inmediato vacío, para devolver el prompt del usuario y seguir mandando el color del fantasma.
2. **2026-11-23 · Revisión del bloque 3, Claude.** La caché de "Cambios git" deja de usar la firma de `.git/index` (editar un archivo no la cambia y el prompt mentía): las consultas de un mismo repo dentro de un segundo comparten una sola ejecución de `git --no-optional-locks status`, que tampoco toma `index.lock`.

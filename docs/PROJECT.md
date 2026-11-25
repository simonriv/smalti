# Smalti — Documento de proyecto

22 nov 2026 · Simón Rivera Agudelo · Fuente editable: https://claude.ai/artifact/WhnV24ZHdg7VtXT9uAGMVH

## Visión

Smalti es una terminal nativa para macOS, hecha para desarrollar con varios agentes de IA a la vez: ves todas tus sesiones en una sola pantalla, sabes cuál te necesita y retomas todo al reabrir. Es una herramienta personal de Simon, no un producto comercial.

**Para quién:** un desarrollador que trabaja 2 o 3 sesiones de Claude Code en paralelo (Solen, Rizaria, Xolken), en una MacBook Air M4 con 16 GB.

**Principio rector:** minimalista pero muy maniobrable. Cero botones fijos; todo se hace con teclado y con la paleta ⌘K. La terminal se siente configurada desde que se instala, sin tocar `.zshrc` ni instalar plugins.

**Criterios de éxito**

- Reemplaza a Ghostty y Warp como terminal diaria durante 30 días seguidos.
- Nunca se traba: escribir y redibujar siguen fluidos con 4 paneles y 3 agentes trabajando.
- Al cerrar y reabrir, el trabajo vuelve en menos de 5 segundos con un solo clic.
- Saber qué agente te espera toma un vistazo, no recorrer pestañas.
- Cambiar tema, prompt o layout no exige editar archivos de configuración a mano.

## Problemas que resuelve

Ninguna terminal actual junta motor rápido, input inteligente, conciencia de agentes y un diseño cuidado; hoy Simon reparte eso entre Ghostty, Warp y herramientas sueltas.

| Dolor | Hoy | Smalti |
| --- | --- | --- |
| Ver varias sesiones a la vez | Splits de Ghostty poco estéticos, sin layouts automáticos | Tiling automático tipo Arch (Dwindle, Columnas, Maestro), con espacios y bordes cuidados |
| Saber qué agente necesita atención | Notificación genérica "Claude is waiting", hay que revisar pestaña por pestaña | Estado por panel (trabajando, te espera, error) y salto directo al que espera |
| Escribir comandos | Warp tiene autocompletado nativo, pero falla con Claude Code | Editor de input en el shell con completions, historial y predicción |
| Retomar el trabajo | Warp reabre pestañas; los agentes hay que retomarlos a mano | Restaura layout, scrollback y sesiones de cualquier harness |
| Ver consumo de IA | Nada integrado; cctop solo corre en Linux | Observatorio con tokens, contexto, costo estimado y recursos |
| Interfaz | Warp: botones y barra lateral difíciles de administrar | Sin botones fijos, todo por teclado y ⌘K |
| Configurar prompt y tema | Powerlevel10k: lento y genérico; requiere tocar zsh | Estudio visual de prompt y temas, sin tocar el shell |

## Panorama

Cada pieza existe por separado; el hueco de Smalti es juntarlas con buen diseño, para un solo usuario.

| Referente | Qué toma Smalti | Qué le falta |
| --- | --- | --- |
| [Warp](https://www.warp.dev/blog/warp-is-now-open-source) | Editor de input tipo IDE, completions, restauración de pestañas | Fallas de render con Claude Code, botones en exceso; cliente abierto bajo AGPL pero acoplado a su plataforma Oz |
| [Ghostty / libghostty](https://github.com/ghostty-org/ghostty) | Motor de emulación, renderer Metal, protocolo de imágenes de kitty | Layouts declarativos, notificaciones útiles con agentes, estética de splits |
| [cmux](https://github.com/mars171/cmux) | Prueba de que libghostty + Swift funciona; notificaciones por OSC y CLI | Editor de input, observatorio, diseño refinado; no restaura procesos vivos |
| [cctop](https://docs.rs/crate/cctop/0.27.1) | Qué mostrar en el observatorio: costo, contexto, estado, errores de herramientas | Solo Linux; es una TUI aparte |
| [Fig autocomplete](https://www.github.com/withfig/autocomplete) | Formato declarativo de specs de completions | Producto descontinuado; quedan las specs |
| [claudecode.nvim](https://github.com/coder/claudecode.nvim) | Diffs de Claude Code dentro de Neovim | Nada: se integra tal cual |
| [Starship](https://starship.rs) | Modelo de módulos de prompt; formato de exportación | Configuración solo por archivo |

Antes de la fase 1 conviene usar cmux una semana con el flujo real; lo que siga faltando confirma el alcance de la v1.

## Funcionalidades

Smalti tiene nueve pilares; los cuatro primeros forman el núcleo de la v1.

### 1. Tiling y workspaces

- Layouts automáticos: **Dwindle** (cada panel nuevo divide el último), **Columnas** y **Maestro + pila**. Cambio con atajo o ⌘K.
- Igualar tamaños, mover y redimensionar paneles por teclado; arrastre con el mouse como opción.
- Workspaces por proyecto (solen, rizaria, xolken) en la franja superior, con un punto de estado.
- Layouts guardables y restaurables por nombre ("solen-dev"), con el comando de arranque de cada panel.
- Cabecera mínima por panel: proceso, proyecto, modelo, % de contexto, tiempo de vida y atajo (⌥1…⌥9).
- Espacios de 8 px entre paneles, radio de 11 px y un brillo sutil en el panel activo.

### 2. Sesiones y reanudación multi-harness

- Al reabrir se restauran layout, directorio, scrollback (comandos y salida) e historial de cada shell.
- Los procesos no se reviven. Los procesos largos (`pnpm dev`) se pueden relanzar con un clic.
- Los agentes se relanzan con el comando de su harness, en el mismo panel:

| Harness | Comando de reanudación | Origen del ID |
| --- | --- | --- |
| Claude Code | `claude --resume <id>` | Hook `SessionStart` y transcripts JSONL en `~/.claude/projects` |
| Codex | `codex resume <id>` | Almacén de sesiones de Codex |
| Gemini CLI | `gemini --resume <id o índice>` | `~/.gemini/tmp/<hash>/chats/` |
| Antigravity | `agy --conversation <id>` / `agy -c` | Caché de última conversación por workspace |
| OpenCode | `opencode -s <id>` / `-c`, `--fork` | Base de datos de OpenCode |

- Pantalla "Retomar donde quedaste" al abrir: lista por workspace con casillas, "Restaurar", "Solo layouts" y "Empezar limpio".
- Buscador de todas las sesiones de agentes del disco, filtrable por harness; Enter la abre en un panel nuevo, ⌘Enter la bifurca si el harness lo permite.
- Si un adaptador no logra leer el ID, usa el modo "continuar la última del directorio".

### 3. Integración con agentes

- Estado por panel: trabajando, te espera, error o detenido, leído de hooks.
- Notificaciones de macOS con contexto real ("rizaria/web: pide permiso para `pnpm db:migrate`"); clic lleva al panel.
- Atajo para saltar al agente que espera más tiempo.
- Drag-and-drop de imágenes al panel de un agente adjunta la imagen, no la ruta.
- **Plugin de Claude Code incluido** (hooks): alimenta estado, IDs de sesión, eventos de edición y observatorio. Se instala desde Smalti con un comando.

### 4. Observatorio de agentes (⌘⇧A)

- Resumen: sesiones activas, tokens de entrada (y % de caché), tokens de salida y equivalente en dólares (estimado; Simon usa suscripción).
- Tabla por sesión: estado, proyecto, harness y modelo, tiempo de vida, entrada, salida, % de contexto, % de errores de herramientas y PID.
- Detalle de la sesión seleccionada: últimas herramientas usadas y tokens por minuto, con las compactaciones.
- Modelos locales de Ollama: cargados, tamaño en memoria, contexto y tokens/s.
- Sistema: CPU, GPU y memoria unificada, desglosada en modelo, agentes y resto.
- Fuentes: hooks, transcripts en disco (todas las sesiones de Claude de la máquina, por periodos de hoy, 7 y 30 días) y la API local de Ollama. La telemetría OpenTelemetry de Claude Code (receptor OTLP local) queda como extra de F7 (decidido por Simón, 2026-11-22).

### 5. Input inteligente y predicción

- zsh sigue siendo el editor de la línea; Smalti sugiere encima en el prompt del shell (no dentro de TUIs como Claude Code): texto fantasma, menú de Tab y ⌃R. Un editor propio (selección con ratón, multilínea, atajos propios) queda para después de F4 (spec F4, 2026-11-23).
- Completions declarativas compatibles con las specs de Fig; las propias se escriben en el mismo formato.
- Historial por directorio y búsqueda difusa con ⌃R.
- **Predicción heurística por defecto** (texto fantasma, en menos de 16 ms): frecuencia y recencia por directorio, secuencias aprendidas (`git add` → `git commit`), contexto del proyecto (scripts de `package.json`, Makefile, estado de git) y sugerencias de recuperación según el código de salida.
- **Modo con API propia, opcional y bajo demanda:** `#` + lenguaje natural produce un comando; "Arreglar" propone una corrección después de un error. Proveedores: Anthropic, OpenAI, OpenRouter o cualquier endpoint compatible, con la clave del usuario. También puede usar `claude -p` con la suscripción instalada.
- Antes de enviar contexto a una API se filtran secretos (tokens, claves, variables `*_KEY`).

### 6. Neovim (NvChad)

- Smalti abre Neovim con socket (`--listen`) en un panel junto a Claude y lanza Claude con `--ide`; [claudecode.nvim](https://github.com/coder/claudecode.nvim) muestra los diffs de Claude como diff nativo (`:w` acepta, `:q` rechaza).
- Cada archivo que Claude edita aparece como enlace "Abrir en Neovim", que salta a la línea exacta en el panel existente.
- Un comando instala y configura claudecode.nvim en la config de NvChad.
- MVP solo con Claude Code.

### 7. Estudio de prompt

- Prompt generado por Smalti y pintado por zsh, con iconos de trazo fino de una fuente propia (`SmaltiSymbols`); no depende de Nerd Fonts (spec F5).
- Módulos que aparecen solo cuando aplican: directorio, rama y cambios de git, runtime (Node, Bun, Python, Go), duración si pasa de 2 s, estado del agente del panel, hora, contexto de Kubernetes o AWS.
- Plantillas minimalistas por defecto: Línea limpia, Una sola línea, Píldoras y Solo símbolo.
- Editor visual: arrastrar para ordenar, activar o desactivar módulos, elegir símbolo e iconos, con vista previa en tres situaciones reales.
- "Exportar como starship.toml" para usar el mismo prompt por SSH o en otra terminal; opción de usar el prompt del shell.

### 8. Apariencia y temas

- Vidrio: opacidad (30–95 %) y desenfoque (0–48 px) ajustables.
- "Proteger legibilidad": sube la opacidad bajo el texto si el contraste cae de 4.5:1.
- Temas: Obsidiana (por defecto), Niebla (claro), Ámbar nocturno y Bosque; paleta ANSI de 16 colores editable.
- Botones de ventana: ocultos (por defecto), al pasar el cursor o visibles. La franja superior sirve para arrastrar la ventana.
- Tipografía, espacio entre paneles y radio configurables.
- Todo se guarda en un archivo TOML legible y versionable; la UI y el archivo son equivalentes.

### 9. Previews

- Imágenes inline vía el protocolo de gráficos de kitty (que libghostty soporta) y `smalti img` para ver las de una carpeta en cuadrícula.
- Miniatura al pasar el cursor sobre un nombre de imagen local; ⌘Y abre Quick Look (spec F5.5).
- Rutas y URLs clicables en toda la salida.

## Diseño y UX

El diseño visual está aprobado. Sus fuentes están en `docs/design/` (ver su README) y son la referencia visual obligatoria para toda la implementación. Canvas original: https://claude.ai/artifact/9nZ1hJvmU1asdcEN4SLtYT

| Tablero | Archivo | Qué define |
| --- | --- | --- |
| Ventana principal | `docs/design/Main.dc.html` | Vidrio, workspaces, tiling con 3 paneles, cabeceras, editor de input con completions, preview de imagen, barra de estado |
| Observatorio | `docs/design/Observatorio.dc.html` | Resumen, tabla de sesiones, actividad, modelos locales y sistema |
| Paleta ⌘K | `docs/design/Paleta.dc.html` | Centro de control único, agrupado por tiling, workspaces y apariencia |
| Apariencia | `docs/design/Apariencia.dc.html` | Temas, vidrio, protección de legibilidad, paleta ANSI, botones de ventana |
| Estudio de prompt | `docs/design/Prompt.dc.html` | Vista previa en tres situaciones, plantillas, módulos, iconos, exportación |
| Retomar sesiones | `docs/design/Reanudar.dc.html` | Restauración al abrir y buscador de sesiones multi-harness |

**Principios**

- Sin botones fijos. Cada acción tiene atajo y aparece en ⌘K; la paleta reemplaza barras laterales y menús.
- El estado se codifica en forma y color, siempre igual: verde trabajando, ámbar te espera, rojo error, círculo hueco detenido.
- Un solo acento configurable (azul por defecto) para foco y selección; los colores semánticos no lo reemplazan.
- El vidrio nunca sacrifica lectura: el texto mantiene 4.5:1 de contraste.
- Tipografía: JetBrains Mono para la terminal, Inter para la interfaz.
- Información en capas: cabecera del panel → barra de estado → observatorio. El detalle aparece solo cuando se pide.
- Animaciones cortas (≤150 ms) y desactivables; respeta "Reducir movimiento" de macOS.

## Arquitectura y stack

Smalti es una app nativa en Swift sobre libghostty, organizada en arquitectura hexagonal: el dominio no conoce ni a Ghostty ni a ningún harness.

```text
┌──────────────────────────────────────────────────────────────────────┐
│ App Swift + AppKit                                                   │
│ ventana de vidrio · paneles · ⌘K · observatorio · estudio de prompt  │
└──────────────────────────────────┬───────────────────────────────────┘
                                   ▼
┌───────────────────────┐   ┌──────────────────┐   ┌───────────────────────┐
│ Motor: libghostty     │◀──┤                  ├──▶│ Input y predicción    │
│ TerminalEngine·Metal  │   │     DOMINIO      │   │ Fig·heurística·API    │
├───────────────────────┤   │                  │   ├───────────────────────┤
│ Harnesses             │◀──┤ Workspace · Pane ├──▶│ Neovim                │
│ HarnessAdapter·5 CLIs │   │ LayoutTree       │   │ EditorBridge·socket   │
├───────────────────────┤   │ ShellSession     │   ├───────────────────────┤
│ Telemetría            │◀──┤ AgentSession     ├──▶│ Configuración         │
│ hooks·JSONL·Ollama    │   │ Theme            │   │ ConfigStore·TOML      │
│ (OTLP en F7)          │   │ PromptConfig     │   │                       │
├───────────────────────┤   │                  │   ├───────────────────────┤
│ Sistema               │◀──┤                  ├──▶│ Notificaciones        │
│ SystemMetrics         │   │                  │   │ Notifier·macOS        │
└───────────────────────┘   └────────▲─────────┘   └───────────────────────┘
                                     │
┌────────────────────────────────────┴─────────────────────────────────┐
│ IPC: socket Unix — CLI smalti · plugin de Claude Code (hooks) ·      │
│ futuro daemon smaltid                                                │
└──────────────────────────────────────────────────────────────────────┘
```

La app y el canal IPC hablan con el dominio; el dominio llama a cada adaptador a través de su puerto, así que cambiar libghostty o un harness no toca el resto.

**Stack decidido**

| Capa | Tecnología | Por qué |
| --- | --- | --- |
| App y ventanas | Swift + AppKit, SwiftUI para paneles de configuración | Vidrio real de macOS, control fino de ventana y teclado |
| Motor de terminal | libghostty (C API), renderer Metal | Mismo motor que [Ghostty](https://github.com/ghostty-org/ghostty), cuya app de macOS ya consume libghostty; soporta imágenes de kitty |
| Integración de shell | Inyección automática para zsh (OSC 133, OSC 7) | Marcas de prompt, directorio, duración y código de salida, sin tocar `.zshrc` |
| IPC | Socket Unix + CLI `smalti` | Hooks de agentes, notificaciones y control desde la terminal |
| Configuración | TOML en `~/.config/smalti/` | Legible, versionable, equivalente a la UI |
| Estado | `~/Library/Application Support/Smalti/` | Layouts, scrollback comprimido, índice de sesiones |

**Módulos (hexagonal)**

- **Dominio:** Workspace, Pane, LayoutTree (árbol binario de splits), ShellSession, AgentSession, Theme, PromptConfig.
- **Puertos:** `TerminalEngine`, `HarnessAdapter`, `TelemetrySource`, `CompletionProvider`, `PredictionProvider`, `EditorBridge`, `SystemMetrics`, `ConfigStore`, `Notifier`.
- **Adaptadores:**
    - `TerminalEngine` → libghostty.
    - `HarnessAdapter` → Claude Code, Codex, Gemini CLI, Antigravity, OpenCode. Cada uno implementa `detect`, `captureSessionId`, `listSessions` y `resumeCommand`.
    - `TelemetrySource` → hooks vía socket; `AgentTranscripts` → lector de transcripts JSONL; `LiveAgents` → `~/.claude/sessions`; `LocalModels` → API de Ollama. Receptor OTLP local en F7.
    - `CompletionProvider` → specs de Fig e historial.
    - `PredictionProvider` → heurístico (por defecto), API del usuario, `claude -p`.
    - `EditorBridge` → Neovim por socket.
    - `SystemMetrics` → métricas de CPU, GPU y memoria de macOS sin sudo.
    - `ConfigStore` → TOML. `Notifier` → notificaciones de macOS.

**Plugin de Claude Code:** hooks (`SessionStart`, `Stop`, `Notification`, `PostToolUse`) que llaman `smalti event …`; el CLI reenvía al socket de la app. Un solo plugin alimenta estado de paneles, IDs de sesión, observatorio y enlaces a Neovim.

**Más adelante:** un daemon `smaltid` dueño de los PTY, como el servidor de tmux. Si la ventana se cierra, los procesos siguen vivos y al reabrir se reconectan. Candidato a escribirse en Rust.

## Decisiones

Estas decisiones están cerradas; cambiarlas exige volver a este documento.

| Decisión | Elegido | Descartado y por qué |
| --- | --- | --- |
| Alcance | Herramienta personal, solo macOS | Producto de Xolken: no hace falta licencia comercial, soporte multiplataforma ni registro de marca |
| Nombre | Smalti (repo existente `termotty` se renombra) | Termotty: casi descriptivo, copia el patrón de Ghostty y kitty, "termo" evoca otra cosa |
| Motor | libghostty | Escribir un emulador propio: años de trabajo en casos raros |
| Stack | Swift + AppKit + libghostty | Rust + GPUI + alacritty_terminal: misma velocidad, framework pre-1.0 que rompe compatibilidad, sin imágenes en terminal, vidrio puenteado. Fork de Warp: código enorme acoplado a Oz. Tauri o Electron: más lento y mal manejo de teclado |
| Velocidad | Depende del núcleo (Zig + Metal), no del lenguaje de la UI | — |
| Predicción | Heurística local + API propia opcional bajo demanda | Modelo local: arranque en frío, compite por 16 GB de RAM. API gratuita: se agota |
| Plugins | Integraciones propias (Claude Code, harnesses, Neovim, Ollama) | Sistema de plugins genérico en la v1: frena el proyecto |
| Autocompletado | Solo en el prompt del shell | Dentro de Claude Code: el input es de Claude |
| Input en el prompt | zsh (ZLE) edita; Smalti sugiere por un widget y un socket | Editor propio estilo Warp: pierde ZLE y rompe TUIs (spec F4) |
| Procesos al reabrir | Se relanzan (shell, agentes con su comando) | Revivirlos en vivo: requiere el daemon, queda para después |
| Prompt | Generado por Smalti (zsh lo pinta; datos de git y runtime asíncronos), exportable a Starship (spec F5) | Powerlevel10k: lento y genérico. Capa AppKit sobre la terminal: frágil con el scroll y el scrollback guardaría un prompt vacío |

## Fases propuestas

Nueve fases (más F4.5, F5.5 y F5.6, intercaladas); Smalti se vuelve la terminal diaria al cerrar la fase 2, y cada fase termina con una terminal usable. Es un borrador: Claude Code lo convierte en roadmap y specs.

```text
F0 Spike ──▶ F1 Tiling ──▶ F2 Persistencia ──▶ F3 Observatorio
                          (terminal diaria)              │
   ┌─────────────────────────────────────────────────────┘
   ▼
F4 Input ──▶ F5 Apariencia ──▶ F6 Multi-harness ──▶ F7 Extras ──▶ F8 Puertos y procesos
```

1. **F0 · Spike.** App Swift con ventana de vidrio sin botones, un panel libghostty y zsh.
    - Cierre: Claude Code corre sin errores de render; escribir y redibujar se sienten iguales a Ghostty.
2. **F1 · Tiling y workspaces.** Árbol de splits, layouts Dwindle, Columnas y Maestro, foco y tamaño por teclado, workspaces, cabeceras de panel, barra de estado, config TOML y ⌘K básica.
    - Cierre: reemplaza a Ghostty para trabajar con 3 sesiones de Claude.
3. **F2 · Persistencia e integración con Claude Code.** Guardar y restaurar layout, directorio y scrollback; plugin de Claude Code con hooks; estado por panel; notificaciones con contexto; salto al agente que espera; reanudación de Claude; drag-and-drop de imágenes.
    - Cierre: cerrar y reabrir devuelve todo en menos de 5 s; ningún "te espera" pasa inadvertido.
4. **F3 · Observatorio.** Lector de transcripts con índice incremental, tabla de sesiones de toda la máquina por periodos, detalle por sesión, Ollama y métricas del sistema.
    - Cierre: los tokens coinciden con los transcripts de Claude Code.
5. **F4 · Input inteligente.** Editor en el prompt del shell, completions con specs de Fig, historial por directorio, ⌃R difuso y predicción heurística.
    - Cierre: sugerencias en menos de 16 ms y ninguna regresión en programas de pantalla completa.
6. **F5 · Apariencia y prompt.** Temas, vidrio ajustable, protección de legibilidad, estudio de prompt y exportación a Starship.
    - Cierre: tema, prompt y layout se cambian sin editar archivos.
    - **F5.5 · Previews.** Miniatura al pasar el cursor sobre nombres de imagen, ⌘Y Quick Look y `smalti img` (kitty) (separada de F5 por Simón, 2026-11-23).
    - **F5.6 · Resaltado del input.** Coloreado nativo de la línea de comando con los colores del tema, sin plugins de zsh, más dos correcciones de ⌘K y los iconos del prompt a la altura del texto (idea de Simón, 2026-11-24; spec F5.6).
7. **F6 · Multi-harness y Neovim.** Adaptadores de Codex, Gemini CLI, Antigravity y OpenCode; buscador de sesiones; puente con Neovim e instalador de claudecode.nvim.
    - Cierre: se retoman sesiones de los 5 harnesses y los diffs de Claude se aprueban en Neovim.
8. **F7 · Extras.** Predicción con API propia y `claude -p`; daemon `smaltid` para procesos persistentes; layouts compartibles; receptor OTLP local para la telemetría de Claude Code.
    - Cierre: cada extra se activa sin afectar el rendimiento base.
9. **F8 · Puertos y procesos.** Panel de puertos en uso con la opción de detenerlos y vista de procesos nativa (un htop más bonito), con atajo y en ⌘K (idea de Simón, 2026-11-23).
    - Cierre: la lista de puertos coincide con `lsof` y detener nunca toca procesos ajenos.

## Riesgos y preguntas abiertas

El riesgo principal es depender de APIs ajenas que cambian sin aviso: la de libghostty y los formatos de sesión de cada harness.

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| libghostty aún no tiene versión etiquetada ni API estable | Una actualización rompe el motor | Fijar un commit, aislarlo detrás del puerto `TerminalEngine`, actualizar a propósito |
| Formatos de sesión de los harnesses cambian | Falla la reanudación de un harness | Un adaptador por harness con pruebas sobre fixtures; respaldo a "continuar la última del directorio" |
| Editor de input propio rompe TUIs | Fallas como las de Warp con Claude Code | El editor solo actúa en el prompt del shell (OSC 133); cualquier programa en pantalla completa recibe el PTY directo |
| Vidrio reduce legibilidad | Texto difícil de leer con fondos claros | Contraste mínimo 4.5:1 forzado por defecto |
| Alcance excesivo | El proyecto no llega a uso diario | Fases con criterios de cierre; cada fase deja una terminal usable |
| Swift y C API nuevos para Simon | Curva de aprendizaje | Claude Code escribe el código; la app de Ghostty y cmux sirven de referencia |
| Métricas de GPU en macOS sin sudo | Observatorio incompleto | Mostrar solo lo que se obtenga sin privilegios; marcar lo no disponible |

**Preguntas abiertas**

- [ ] ¿Qué shell además de zsh debe soportar la integración? (por defecto, solo zsh)
- [ ] ¿Cuántas líneas de scrollback guardar por panel al cerrar? (propuesta: 10.000)
- [ ] ¿El daemon `smaltid` se hace en Swift o en Rust cuando llegue su fase?
- [ ] ¿Homebrew tiene algo llamado smalti? Verificar antes de crear el cask.

## Nombre

Smalti queda en verde para uso personal: no hay otra terminal ni herramienta de desarrollo para macOS con ese nombre, y el binario y el dominio `.sh` están libres.

**Origen:** *smalti* es el vidrio esmaltado del que se cortan las teselas de los mosaicos. Une los dos rasgos del producto, el vidrio y los paneles en mosaico, sin describirlos. En italiano también significa "esmaltes", incluido el de uñas; en español roza "esmalte".

| Dónde | Resultado | Riesgo |
| --- | --- | --- |
| Software con el mismo nombre | [Smalti](https://github.com/DavidNyholm/Smalti), librería GUI en C++20 para Windows y Linux, MIT | Bajo: otra categoría y otra plataforma |
| Terminales y CLIs | Ninguna encontrada | Ninguno |
| Binario `smalti` | No existe como comando común | Ninguno |
| npm | Nombre reservado por un tercero (versión 0.0.2, sin contenido) | Ninguno: Smalti no se publica en npm |
| crates.io y PyPI | Libres | Ninguno |
| Homebrew | Sin verificar | Bajo |
| Repo en GitHub | `<tu-usuario>/smalti`: libre por espacio de nombres | Ninguno |

Dominios: `smalti.sh` libre (recomendado), `smaltiapp.com` libre, `smalti.co` premium; `.com`, `.io`, `.app`, `getsmalti.com` y `usesmalti.com` tomados.

## Cómo usar este documento con Claude Code

Claude Code no puede abrir enlaces de claude.ai, así que este documento y el diseño viven dentro del repo.

1. Renombra el repo `termotty` a `smalti` en GitHub y actualiza el remoto local con `git remote set-url origin <nueva-url>`.
2. Copia al repo `docs/PROJECT.md` (este archivo) y `docs/design/` (fuentes de los seis tableros).
3. Abre Claude Code en la raíz del repo, en modo plan, y pega el prompt de abajo.
4. Revisa el roadmap y las specs de F0 y F1 antes de aprobar que escriba código.

```markdown
Lee completo docs/PROJECT.md y los archivos de docs/design/ (README incluido).
Este repo pasa de termotty a Smalti: terminal nativa para macOS en Swift + AppKit sobre libghostty, de uso personal.
No escribas código todavía.

1. Crea docs/ROADMAP.md con las fases F0–F7 del documento: objetivo, entregables, criterio de cierre y dependencias de cada una.
2. Crea docs/specs/F0-spike.md y docs/specs/F1-tiling.md con: objetivo, alcance, fuera de alcance, diseño técnico (dominio, puertos y adaptadores según la arquitectura hexagonal del documento), criterios de aceptación verificables y riesgos.
3. Crea CLAUDE.md con las convenciones del proyecto: Swift, arquitectura hexagonal, libghostty fijado a un commit detrás del puerto TerminalEngine, y docs/design como referencia visual obligatoria.
4. Lista las preguntas que necesitas que responda antes de empezar F0.

Respeta la sección Decisiones. Si quieres cambiar alguna, explica por qué antes de proponerlo.
```

# Smalti — Roadmap

Fuente: `docs/PROJECT.md` (secciones Funcionalidades, Arquitectura, Decisiones y Fases propuestas). Diseño: `docs/design/`.
Cada fase termina con una terminal usable. Smalti pasa a ser la terminal diaria al cerrar **F2**.

```text
F0 Spike ──▶ F1 Tiling ──▶ F2 Persistencia ──▶ F3 Observatorio
                          (terminal diaria)              │
   ┌─────────────────────────────────────────────────────┘
   ▼
F4 Input ──▶ F5 Apariencia ──▶ F6 Multi-harness ──▶ F7 Extras
```

El orden es el del documento. Las dependencias técnicas reales son menos estrictas (ver cada fase): F3 y F4 podrían invertirse, y F6 solo necesita F2.

## Convenciones del roadmap

- **Criterio de cierre**: se verifica con una prueba o con una medición concreta, no con una impresión. Sin pruebas físicas ni de uso real hasta que la app esté terminada (decidido por Simón, 2026-11-22): todo criterio de fase se comprueba con pruebas automáticas, mediciones o capturas.
- **Spec**: cada fase tiene `docs/specs/F<n>-<slug>.md` antes de escribir código. Hoy existen F0, F1, F2, F3 y F4.
- Las Decisiones de `PROJECT.md` están cerradas. Una fase no las reabre sin pasar antes por ese documento.

---

## F0 · Spike del motor

- **Objetivo:** demostrar que Swift + AppKit + libghostty dan una terminal con vidrio, sin botones y con la misma sensación que Ghostty.
- **Entregables**
  - libghostty fijado a un commit, compilado a `GhosttyKit.xcframework` con un script reproducible.
  - App macOS: ventana de vidrio sin botones de semáforo, arrastrable desde una franja superior de 40 px, con un panel libghostty que corre zsh.
  - Integración de shell de zsh inyectada (OSC 133 y OSC 7) sin tocar `.zshrc`, más terminfo `xterm-ghostty` empaquetado.
  - Esqueleto hexagonal: paquete `SmaltiCore` con el puerto `TerminalEngine` y el adaptador `GhosttyTerminalEngine`.
  - Informe del spike (`docs/specs/F0-spike-report.md`): qué funcionó, las APIs de libghostty que se usan, mediciones y riesgos que quedan.
- **Criterio de cierre:** Claude Code pasa la lista de render de la spec sin errores visuales. El rendimiento queda dentro de ±10 % de Ghostty.app en las mediciones de la spec. Una prueba A/B a ciegas de escritura no distingue Smalti de Ghostty.
- **Dependencias:** ninguna. libghostty fijado a Ghostty `v1.4.0`, que pide Zig ≥ 0.17.0.

## F1 · Tiling y workspaces

- **Objetivo:** trabajar con 3 sesiones de Claude en una sola ventana mejor que con los splits de Ghostty.
- **Entregables:** árbol de splits (`LayoutTree`); layouts Dwindle, Columnas y Maestro + pila; foco, intercambio y tamaño por teclado; igualar tamaños; workspaces en la franja superior; cabecera de panel; barra de estado; configuración TOML en `~/.config/smalti/`; paleta ⌘K básica.
- **Criterio de cierre:** la suite de dominio y los criterios de `docs/specs/F1-tiling.md` en verde. ~~5 días laborales con 3 sesiones de Claude en Smalti~~ aplazado al uso con la app terminada (Simón, 2026-11-22).
- **Dependencias:** F0 cerrado (motor y esqueleto hexagonal). ~~Requisito de entrada: una semana usando cmux~~ descartado por Simón (2026-11-22).

## F2 · Persistencia e integración con Claude Code

- **Objetivo:** cerrar y reabrir sin perder trabajo, y que ningún agente que espera pase inadvertido. **Con esto Smalti es la terminal diaria.**
- **Entregables**
  - Guardar y restaurar layout, directorio, scrollback (propuesta: 10.000 líneas por panel) e historial de cada shell, en `~/Library/Application Support/Smalti/`.
  - Layouts con nombre ("solen-dev"), con el comando de arranque de cada panel.
  - Pantalla "Retomar donde quedaste" en su versión de Claude Code (`Reanudar.dc.html`).
  - Canal IPC (socket Unix) y CLI `smalti`.
  - Plugin de Claude Code con hooks `SessionStart`, `Stop`, `Notification` y `PostToolUse` que llaman a `smalti event …`, e instalación desde Smalti con un comando.
  - Estado por panel (trabajando, te espera, error, detenido) en la cabecera, la franja y los contadores.
  - Notificaciones de macOS con contexto; un clic lleva al panel.
  - Atajo para saltar al agente que lleva más tiempo esperando.
  - Reanudación de Claude con `claude --resume <id>`.
  - Arrastrar una imagen al panel de un agente adjunta la imagen.
  - Builds de desarrollo separados del Smalti diario: bundle ID `dev.simonriv.smalti.dev`, nombre de proceso y datos propios, para que las pruebas y los scripts de medición nunca cierren la instancia en uso (decidido por Simón, 2026-11-22).
- **Criterio de cierre**
  - Al reabrir, layout, directorios y scrollback vuelven en menos de 5 s, medido desde el lanzamiento hasta que el último panel es interactivo, con 3 workspaces y 6 paneles.
  - Todo `Notification` de Claude produce estado ámbar y notificación de macOS: una prueba reproduce un log de eventos de hooks grabado y lo compara contra la UI.
  - ~~30 días seguidos como terminal diaria~~: pasa a ser el criterio de éxito global con la app terminada (tras F7).
- **Dependencias:** F1 (workspaces, `LayoutTree` serializable, cabecera y barra de estado). Introduce el puerto `HarnessAdapter` (solo Claude), `TelemetrySource` (hooks), `Notifier` y el IPC.

## F3 · Observatorio (⌘⇧A)

- **Objetivo:** ver de un vistazo el consumo y el estado de todos los agentes y modelos locales.
- **Entregables:** lector de transcripts JSONL con índice incremental (todas las sesiones de Claude de la máquina, periodos hoy / 7 días / 30 días); sesiones vivas desde `~/.claude/sessions`; resumen (sesiones, tokens de entrada con % de caché, tokens de salida, equivalente estimado en USD con tabla de precios editable); tabla por sesión; detalle con últimas herramientas, tokens por minuto y compactaciones; modelos de Ollama; CPU, GPU y memoria unificada sin sudo; lado derecho de la barra de estado y modelo + `ctx %` en la cabecera (`Observatorio.dc.html`, pie de `Main.dc.html`). Spec: `docs/specs/F3-observatory.md`. Sin OTLP (pasa a F7) ni filtros por harness (F6), decidido por Simón (2026-11-22).
- **Criterio de cierre:** para 3 sesiones reales, los tokens de entrada y salida del observatorio coinciden exactamente con la suma de los transcripts JSONL. Una prueba sobre fixtures compara ambos. Lo que no se pueda medir sin privilegios aparece marcado como "no disponible", nunca como 0.
- **Cerrada (2026-11-23):** ver `docs/specs/F3-checklist.md`. C1 con 4 sesiones reales (incluidos un subagente y un fork) contra un oráculo independiente.
- **Dependencias:** F2 (plugin de hooks, IPC, modelo `AgentSession`). Técnicamente es independiente de F4.

## F4 · Input inteligente

- **Objetivo:** escribir comandos con completions, historial y predicción sin romper ningún programa de pantalla completa.
- **Entregables:** sugerencias sobre el prompt de zsh, que sigue siendo el editor (prompt detectado por OSC 133; canal por socket con un widget de zsh); toma de control de zsh-autosuggestions, ⌃R de fzf y Tab dentro de los paneles de Smalti; historial propio que empieza vacío; completions con specs de Fig; historial por directorio; ⌃R difuso; predicción heurística con texto fantasma (frecuencia, recencia, secuencias, contexto del proyecto, recuperación según el código de salida); filtro de secretos listo para F7.
- **Criterio de cierre:** p99 de la sugerencia por debajo de 16 ms en un benchmark con un historial de 50.000 entradas. Claude Code, nvim, htop y less siguen pasando la lista de render de F0, porque el editor no intercepta nada fuera del prompt.
- **Dependencias:** F0 (OSC 133 confirmado) y F1. Es la fase de mayor riesgo técnico (ver riesgos de F0): conviene un mini-spike al inicio.

## F4.5 · Ayuda y ventana

- **Objetivo:** que todo atajo y función se pueda descubrir sin leer documentación, y que la ventana pueda ocupar toda la pantalla.
- **Entregables:** vista de ayuda con la guía de todos los atajos y acciones (⌘? y desde ⌘K); pantalla completa nativa de macOS (⌃⌘F); otras ideas de Simón que se sumen antes de su spec.
- **Criterio de cierre:** se define en su spec.
- **Dependencias:** F4 (sus atajos aparecen en la ayuda). Añadida por Simón en el brainstorming de F4 (2026-11-23).

## F5 · Apariencia y prompt

- **Objetivo:** cambiar tema, prompt y layout sin editar archivos a mano.
- **Entregables:** temas Obsidiana, Niebla, Ámbar nocturno y Bosque; vidrio ajustable (opacidad 30–95 %, desenfoque 0–48 px); "Proteger legibilidad" (contraste 4.5:1); paleta ANSI editable; botones de ventana (ocultos, al pasar el cursor o visibles); tipografía, espacio y radio; estudio de prompt con plantillas, módulos, iconos y exportación a `starship.toml`; previews de imágenes (kitty, hover sobre enlace, Quick Look). UI y TOML equivalentes en las dos direcciones.
- **Criterio de cierre:** cada ajuste de `Apariencia.dc.html` y `Prompt.dc.html` se cambia desde la UI y se refleja en el TOML, y al revés. Una prueba de ida y vuelta lo verifica. El contraste medido nunca baja de 4.5:1 con "Proteger legibilidad" activo.
- **Dependencias:** F1 (`ConfigStore`) y F4 (la zona del prompt la controla Smalti).

## F6 · Multi-harness y Neovim

- **Objetivo:** retomar sesiones de cualquier harness y aprobar los diffs de Claude en Neovim.
- **Entregables:** adaptadores `HarnessAdapter` de Codex, Gemini CLI, Antigravity y OpenCode (`detect`, `captureSessionId`, `listSessions`, `resumeCommand`); respaldo "continuar la última del directorio"; buscador de sesiones del disco filtrable por harness; `EditorBridge` con Neovim por socket; instalador de claudecode.nvim en NvChad; enlaces "Abrir en Neovim"; filtros por harness del Observatorio (Todas, Claude Code, OpenCode, Locales).
- **Criterio de cierre:** una prueba de contrato compartida pasa para los 5 adaptadores sobre fixtures reales. Una prueba de integración retoma una sesión de fixture de cada harness con su comando real. Un diff de Claude se acepta con `:w` y se rechaza con `:q`.
- **Dependencias:** F2 (puerto `HarnessAdapter` y adaptador de Claude como primera implementación). F3 suma la telemetría de OpenCode, pero no bloquea.

## F7 · Extras

- **Objetivo:** capacidades opcionales que no tocan el rendimiento base.
- **Entregables:** predicción con API propia (Anthropic, OpenAI, OpenRouter o compatible) y con `claude -p`; daemon `smaltid` dueño de los PTY (se decide en Swift o Rust al llegar); layouts compartibles; receptor OTLP local inyectado a los procesos hijos (telemetría de Claude Code, movido desde F3).
- **Criterio de cierre:** con cada extra apagado y encendido, las mediciones de F0 y F4 no empeoran más de 5 %. Ningún secreto sale a una API; las pruebas del filtro lo cubren.
- **Dependencias:** F4 (`PredictionProvider`) y F2 (persistencia). El daemon choca con que libghostty sea dueño del PTY (ver riesgos de F0) y necesita su propio spike.

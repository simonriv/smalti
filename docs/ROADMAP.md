# Smalti — Roadmap

Fuente: `docs/PROJECT.md` (secciones Funcionalidades, Arquitectura, Decisiones y Fases propuestas). Diseño: `docs/design/`.
Cada fase termina con una terminal usable. Smalti pasa a ser la terminal diaria al cerrar **F2**.

```text
F0 Spike ──▶ F1 Tiling ──▶ F2 Persistencia ──▶ F3 Observatorio
                          (terminal diaria)              │
   ┌─────────────────────────────────────────────────────┘
   ▼
F4 Input ──▶ F4.5 Ayuda ──▶ F5 Apariencia ──▶ F5.5 Previews ──▶ F5.6 Resaltado ──▶ F6 Multi-harness ──▶ F7 Extras
   ┌──────────────────────────────────────────────────────────────────────────────────────────────────┘
   ▼
F7.5 Guardas para agentes ──▶ F7.6 Distribución y actualizaciones ──▶ F7.7 Primer uso e inglés ──▶ F8 Puertos y procesos ──▶ F8.5 Proyectos ──▶ F9 Timeline ──▶ F10 Revisión con Neovim ──▶ F11 Baúl de secretos
```

F7.5 y F8.5–F11 salen de la evaluación de `smalti-diferenciacion.md` (Simón, 2026-11-25): ver «Ideas evaluadas» al final. F7.6 y F7.7 salen de la decisión de publicar Smalti para otros usuarios, gratis, con web en Vercel y dominio propio (Simón, 2026-11-25): van antes de las fases de producto para que esas lleguen ya por actualización automática.

El orden es el del documento. Las dependencias técnicas reales son menos estrictas (ver cada fase): F3 y F4 podrían invertirse, y F6 solo necesita F2.

## Convenciones del roadmap

- **Criterio de cierre**: se verifica con una prueba o con una medición concreta, no con una impresión. Sin pruebas físicas ni de uso real hasta que la app esté terminada (decidido por Simón, 2026-11-22): todo criterio de fase se comprueba con pruebas automáticas, mediciones o capturas.
- **Spec**: cada fase tiene `docs/specs/F<n>-<slug>.md` antes de escribir código. Hoy existen F0, F1, F2, F3, F4, F4.5, F5, F5.5 y F5.6.
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

## F4.5 · Ayuda, ventanas y funciones básicas

- **Objetivo:** que Smalti sea usable por cualquier persona, no solo por quien lo construyó: que todo atajo y función se pueda descubrir sin leer documentación y que estén las funciones básicas que se esperan de una app de macOS y de una terminal, incluidas las que no se ven en pantalla.
- **Primer paso, antes de la spec: auditoría de usabilidad básica.** Recorrer la app como un usuario nuevo y compararla con lo que se espera de una terminal de macOS (Terminal.app, Ghostty, iTerm2). Sale una lista de huecos, y cada uno se clasifica en: entra en F4.5, ya está en una fase posterior (se queda allí) o queda para después. Se comprueban al menos:
  - descubrimiento: vista de ayuda con todos los atajos y acciones (⌘? y desde ⌘K) y menú de macOS completo (Smalti, Edición, Ver, Ventana, Ayuda) con cada acción y su atajo;
  - ventanas: pantalla completa nativa (⌃⌘F); varias ventanas a la vez (⌘N), cada una con sus propios workspaces, que se guardan y se restauran por ventana; cerrar una ventana sin cerrar las demás; confirmar antes de cerrar con procesos en marcha;
  - feedback: una forma de reportar un fallo o una idea desde la app (⌘K y menú Ayuda) que adjunte la versión y, si el usuario quiere, los registros;
  - terminal básica: buscar en el scrollback (⌘F), tamaño de letra (⌘+, ⌘−, ⌘0), selección y copiado, abrir enlaces con ⌘clic, arrastrar archivos para pegar su ruta, entrada de teclado segura;
  - app: "Acerca de Smalti" con la versión, abrir la configuración (⌘,), registros para diagnosticar y accesibilidad básica (VoiceOver y tamaño de texto).
- **Entregables:** el informe de la auditoría (`docs/specs/F4.5-auditoria.md`) aprobado por Simón; después, la vista de ayuda, la pantalla completa, las varias ventanas con workspaces propios, el canal de feedback y los huecos de la auditoría marcados como "entra en F4.5".
- **Spec:** `docs/specs/F4.5-ayuda-ventanas.md` (aprobada 2026-11-23), sobre la auditoría `docs/specs/F4.5-auditoria.md` (aprobada).
- **Límites:** no adelanta trabajo de F5 (temas, vidrio, botones de ventana, tipografía, estudio de prompt; la ventana de configuración visual es de F5, en F4.5 ⌘, solo abre el TOML), de F6 (multi-harness, Neovim) ni de F7 (layouts compartibles, OTLP). Nada de producto de venta: ni licencias, ni actualizaciones automáticas, ni telemetría de uso.
- **Criterio de cierre:** se define en su spec, a partir de la auditoría. Como mínimo: cada acción de ⌘K aparece en la ayuda y en el menú con el mismo atajo (prueba automática), y dos ventanas con workspaces distintos se restauran cada una con los suyos (XCUITest).
- **Dependencias:** F4 (sus atajos aparecen en la ayuda) y F2 (la persistencia pasa de una ventana a varias). Añadida por Simón en el brainstorming de F4 (2026-11-23) y ampliada el mismo día con la auditoría de funciones básicas.

## F5 · Apariencia y prompt

- **Objetivo:** cambiar tema, prompt y layout sin editar archivos a mano.
- **Entregables:** temas Obsidiana, Niebla, Ámbar nocturno y Bosque; vidrio ajustable (opacidad 30–95 %, desenfoque 0–48 px); "Proteger legibilidad" (contraste 4.5:1); paleta ANSI editable; botones de ventana (ocultos, al pasar el cursor o visibles); tipografía, espacio y radio; estudio de prompt con plantillas, módulos, iconos y exportación a `starship.toml`. UI y TOML (`theme.toml`) equivalentes en las dos direcciones. Heredado: contraste del texto fantasma, botones de ventana (Zoom sin botón desde F4.5) e issue #5 (GPU en reposo). Las previews de imágenes pasan a F5.5 (Simón, 2026-11-23).
- **Spec:** `docs/specs/F5-apariencia-prompt.md` (aprobada 2026-11-23).
- **Criterio de cierre:** cada ajuste de `Apariencia.dc.html` y `Prompt.dc.html` se cambia desde la UI y se refleja en el TOML, y al revés. Una prueba de ida y vuelta lo verifica. El contraste medido nunca baja de 4.5:1 con "Proteger legibilidad" activo.
- **Dependencias:** F1 (`ConfigStore`) y F4 (la zona del prompt la controla Smalti).

## F5.5 · Previews

- **Objetivo:** ver imágenes sin salir de la terminal.
- **Entregables:** miniatura al pasar el cursor sobre nombres de imagen locales (salida de `ls` y rutas), ⌘Y abre Quick Look, `smalti img [carpeta|archivos]` pinta una cuadrícula de miniaturas por el protocolo de kitty, y las imágenes kitty de terceros siguen funcionando (spike de 2026-11-24: libghostty las pinta en un surface embebido sin cambios). Imágenes remotas fuera (las de los agentes las cubre un plugin de Simón).
- **Spec:** `docs/specs/F5.5-previews.md` (aprobada 2026-11-24).
- **Criterio de cierre:** en una carpeta con imágenes, tras `ls` (y tras `ls carpeta/` desde la padre), pasar el cursor por un nombre muestra su miniatura y ⌘Y la abre en Quick Look; `smalti img <carpeta>` pinta la cuadrícula aprobada. Sin coste con el ratón quieto.
- **Dependencias:** F5 (temas y superposiciones). Separada de F5 por Simón (2026-11-23): no comparte nada con temas ni prompt.

## F5.6 · Resaltado del input

- **Objetivo:** que la línea de comando se coloree mientras se escribe, sin plugins de zsh (Simón quitó zsh-syntax-highlighting el 2026-11-23, enmienda 1 de F4) (idea de Simón, 2026-11-24).
- **Entregables:** resaltado nativo de la línea en el prompt del shell, pintado por zsh con `region_highlight` (como el fantasma de F4): comando existente o desconocido, subcomandos y opciones según las specs de Fig, cadenas, rutas que existen, variables y operadores. Colores de rol del tema activo, con "Proteger legibilidad"; activable en `[input]`.
- **Correcciones de la paleta ⌘K** (Simón, 2026-11-24):
  - "Instalar integración con Claude" y "Desinstalar integración con Claude" salen a la vez; debe salir solo la que aplica según el estado (instalada o no). Pensado para cuando haya más integraciones (F6), que serán un menú propio.
  - El scroll con el trackpad o la rueda solo recorre parte de la lista y obliga a usar las flechas para ver todas las opciones; debe recorrerla entera.
- **Iconos del prompt** (Simón, 2026-11-24): los de `SmaltiSymbols` (casa, rama, reloj…) se ven diminutos; pasan a la altura de las mayúsculas de JetBrains Mono o algo más, con lámina antes/después y capturas en los cuatro temas.
- **Spec:** `docs/specs/F5.6-resaltado.md` (aprobada 2026-11-24).
- **Criterio de cierre:** el resaltado llega en p99 < 16 ms de extremo a extremo y el fantasma de F4 sigue en p99 < 16 ms, con la mediana a menos de un 10 % y el p99 a menos de 2 ms de la base (enmienda 6 de la spec); ⌘K muestra solo la acción de integración que aplica y su lista se recorre entera con trackpad o rueda; lámina antes/después de los iconos aprobada.
- **Dependencias:** F4 (canal con zsh, specs de Fig, `region_highlight` con `memo=smalti`) y F5 (temas y colores de rol). Separada de F5.5: no comparte nada con las previews.

## F6 · Multi-harness y Neovim

- **Objetivo:** retomar sesiones de cualquier harness y aprobar los diffs de Claude en Neovim.
- **Entregables:** adaptadores `HarnessAdapter` de Codex, Antigravity y OpenCode (`detect`, `captureSessionId`, `listSessions`, `resumeCommand`), sin Gemini CLI (Google retiró su login individual; decidido por Simón, 2026-11-24); respaldo "continuar la última del directorio"; buscador de sesiones del disco filtrable por harness; `EditorBridge` con Neovim por socket; instalador de claudecode.nvim en NvChad; enlaces "Abrir en Neovim"; filtros por harness del Observatorio (Todas, Claude Code, OpenCode, Locales). Spec: `docs/specs/F6-multi-harness.md`.
- **Criterio de cierre:** una prueba de contrato compartida pasa para los 4 adaptadores (Claude, Codex, Antigravity, OpenCode) sobre fixtures reales. Una prueba de integración retoma una sesión de fixture de cada harness con su comando real. Un diff con el protocolo de Claude se acepta con `:w` y se rechaza con `:q`.
- **Dependencias:** F2 (puerto `HarnessAdapter` y adaptador de Claude como primera implementación). F3 suma la telemetría de OpenCode, pero no bloquea.

## F7 · Extras

- **Objetivo:** capacidades opcionales que no tocan el rendimiento base.
- **Entregables:** layouts compartibles; receptor OTLP local inyectado a los procesos hijos (telemetría de Claude Code, movido desde F3).
- **Fuera (Simón, 2026-11-25):** la predicción con API propia o `claude -p` (cuesta dinero y saca contexto de la máquina) y el daemon `smaltid` dueño de los PTY (choca con que libghostty sea dueño del PTY). Al reabrir, los procesos se siguen relanzando.
- **Criterio de cierre:** con cada extra apagado y encendido, las mediciones de F0 y F4 no empeoran más de 5 %. Nada sale de la máquina: el receptor OTLP escucha solo en `127.0.0.1`, y una prueba lo cubre.
- **Dependencias:** F2 (persistencia y layouts con nombre) y F3 (Observatorio, que recibe la telemetría OTLP).

## F7.5 · Guardas para agentes

- **Objetivo:** que un agente en un panel de Smalti no pueda leer secretos ni ejecutar un comando destructivo contra producción sin que Simón lo apruebe. Los controles viven fuera del agente: las instrucciones del prompt no bastan (incidentes de Replit, DataTalks.Club y PocketOS).
- **Entregables:**
  - **Bloqueo de lectura de secretos:** el plugin de Claude Code que Smalti ya instala suma un hook `PreToolUse` que bloquea `Read` y `Bash` sobre `.env*`, `*.pem`, `~/.ssh`, `~/.aws` y similares, y Smalti genera las reglas `permissions.deny` con la sintaxis correcta (rutas absolutas con `//`) en el proyecto que se le pida.
  - **Guardia de comandos destructivos:** el mismo hook detecta comandos de alto riesgo (`supabase db push`/`reset`, `prisma migrate reset`, `drizzle-kit push`, `npm run db:push`, `terraform destroy`/`apply`, `railway … delete`, `psql` con `DROP`/`TRUNCATE`, cualquier comando con un `DATABASE_URL` de producción) y espera la decisión de Smalti.
  - **Aprobación nativa:** Smalti muestra en el panel y en una notificación el workspace, el comando completo y el entorno detectado («rizaria: `supabase db push` contra **PROD**»), con aprobar y rechazar por teclado y en ⌘K. El canal hook → Smalti pasa de aviso a petición con respuesta por el socket de F2.
  - **Entorno detectado** por el host del `DATABASE_URL` y por una lista de hosts de producción en `config.toml`; si no se puede determinar, se asume producción (falla cerrado).
- **Criterio de cierre:** una prueba reproduce los comandos de los tres incidentes y cada uno queda bloqueado hasta la aprobación; ninguna lectura de los archivos de secretos de una lista de prueba llega al agente; sin respuesta de Smalti (app cerrada o socket caído), el hook bloquea.
- **Fuera:** el proxy SQL con `libpg_query` y el proxy HTTPS de valores de relleno (ver «Ideas evaluadas»).
- **Dependencias:** F2 (plugin de hooks, IPC, notificaciones) y F6 (catálogo de integraciones para instalar y desinstalar las reglas).

## F7.6 · Distribución y actualizaciones

- **Objetivo:** que cualquiera instale Smalti en un minuto, que macOS lo abra sin avisos de seguridad y que cada versión nueva llegue sola.
- **Entregables:**
  - **Firma Developer ID y notarización** de Apple, con «stapling» del ticket. Sustituye la firma ad hoc de `CLAUDE.md`: sin ella, Gatekeeper bloquea una app descargada y Homebrew deja de aceptar casks sin notarizar. **Cuesta dinero** (Apple Developer Program, 99 USD al año): la spec no avanza sin la aprobación explícita de Simón.
  - **Actualización automática con Sparkle 2:** firma EdDSA de cada versión, `appcast.xml` servido desde el dominio de la web (Vercel), notas de versión en la ventana de actualización, comprobación al arrancar y a demanda («Buscar actualizaciones…» en el menú Smalti y en ⌘K), opción de desactivarla. La comprobación solo pide el appcast: no envía datos de uso.
  - **Entrega:** DMG firmado en GitHub Releases; cask de Homebrew en un tap propio (`brew install --cask simonriv/tap/smalti`) con `auto_updates true`, y propuesta al tap oficial cuando cumpla sus criterios de notoriedad. Comprobar antes que el nombre `smalti` está libre en Homebrew (pregunta abierta de `PROJECT.md`).
  - **Pipeline de release** en GitHub Actions: compilar el Release, firmar, notarizar, crear el DMG, publicar la release con sus notas, actualizar el appcast y el cask. Los secretos de firma viven en los secretos del repo, nunca en el código.
  - **Compatibilidad entre versiones:** los formatos de sesión, layouts, índice del Observatorio y `config.toml` llevan versión, se migran hacia delante, y una versión vieja que encuentra datos de una nueva no los rompe.
  - **Repositorio público:** licencia elegida por Simón, `THIRD_PARTY_NOTICES` (libghostty MIT, Inter y JetBrains Mono OFL, specs de Fig ISC, Sparkle MIT), `README` de instalación y desinstalación, y el canal de feedback de F4.5 apuntando a los issues públicos.
- **Criterio de cierre:** por definir en su spec; como mínimo, un Mac limpio instala por DMG y por Homebrew sin avisos de Gatekeeper (`spctl --assess` acepta la app), y una versión instalada se actualiza a la siguiente desde un appcast de prueba sin perder sesión, layouts ni configuración.
- **Dependencias:** F4.5 (feedback, «Acerca de» con versión). Cambia la Decisión «Alcance» de `PROJECT.md` y la línea de firma de `CLAUDE.md`.

## F7.7 · Primer uso e inglés

- **Objetivo:** que alguien que no es Simón entienda y use Smalti desde el primer arranque.
- **Entregables:**
  - **Interfaz en inglés y español**, según el idioma del sistema: todos los textos de la app pasan a un catálogo de cadenas; los tableros de `docs/design/` siguen en español como referencia.
  - **Primer arranque:** pantalla breve que explica ⌘K y los atajos clave, ofrece instalar la integración con Claude Code y la de Neovim, y elige tema; se puede saltar y volver a abrir desde la ayuda.
  - **Valores por defecto neutrales:** revisar lo que asume el flujo de Simón (instalador solo para NvChad, ⌥ reservado al teclado latinoamericano, ejemplos con sus proyectos) y dejarlo configurable o documentado.
  - **Privacidad explícita:** una página en la ayuda y en la web: nada sale de la máquina salvo la comprobación de actualizaciones; la telemetría de Claude Code se queda en `127.0.0.1`.
- **Criterio de cierre:** por definir en su spec; como mínimo, con el sistema en inglés no queda ningún texto de interfaz en español (prueba que recorre ⌘K, menús, ayuda y Observatorio), y el primer arranque se completa y se salta por teclado.
- **Dependencias:** F7.6 (la app ya es pública).

## F8 · Puertos y procesos

- **Objetivo:** ver qué está escuchando y qué está consumiendo, y detenerlo, sin salir de Smalti ni abrir otra herramienta (idea de Simón, 2026-11-23).
- **Entregables:**
  - Panel de puertos en uso: puerto, protocolo, proceso, PID, directorio y, si lo lanzó un panel de Smalti, ese panel; detener un proceso (SIGTERM y, si no responde, SIGKILL con confirmación) y saltar al panel que lo lanzó.
  - Vista de procesos nativa, un htop más bonito: CPU, memoria, árbol de procesos, filtro y orden, con el mismo estado codificado del resto de la app; detener y priorizar desde ahí.
  - Todo con atajo y en ⌘K, sin botones fijos.
- **Criterio de cierre:** por definir en su spec. Como mínimo, la lista de puertos coincide con `lsof -iTCP -sTCP:LISTEN -nP` en una prueba con puertos abiertos a propósito, y detener nunca toca procesos de otro usuario ni el propio Smalti.
- **Diseño:** no hay tablero. La fase empieza con su maqueta para aprobar, en la línea del Observatorio.
- **Dependencias:** F3 (puerto `SystemMetrics`, sin sudo) y F2 (relación panel ↔ proceso).

## F8.5 · Proyectos

- **Objetivo:** abrir un proyecto tal como se trabaja en él con un atajo, sin buscar el layout guardado.
- **Entregables:** un layout compartible de F7 dentro del repo (`.smalti/layout.json`) se descubre al abrir un panel o workspace en esa carpeta y se ofrece en ⌘K como «Abrir proyecto “rizaria”»; con la misma confirmación de comandos de F7 la primera vez que cambia el archivo. Atajo para saltar entre proyectos recientes.
- **Criterio de cierre:** por definir en su spec; como mínimo, un repo con `.smalti/layout.json` se abre con su layout y sus comandos tras confirmar, y un archivo modificado vuelve a pedir confirmación.
- **Dependencias:** F7 (formato y validación del layout compartible).

## F9 · Timeline de la sesión

- **Objetivo:** recuperar lo que un agente hizo aunque ya no se vea: Claude Code usa la pantalla alternativa y su historial no queda en el scrollback.
- **Entregables:** panel lateral (con atajo y en ⌘K) que lee los transcripts y muestra los turnos con las herramientas plegadas, búsqueda en todas las sesiones del proyecto, copiar cualquier salida antigua y saltar a un turno. Adaptadores de Claude Code y Codex detrás de un puerto, reutilizando los lectores de F3 y F6.
- **Criterio de cierre:** por definir en su spec; como mínimo, sobre los fixtures reales de F3 y F6, cada turno y cada resultado de herramienta del transcript aparece en el timeline y se copia íntegro.
- **Diseño:** no hay tablero; empieza con maqueta para aprobar.
- **Dependencias:** F3 (lector de transcripts) y F6 (fixtures y adaptadores de harness).

## F10 · Revisión con Neovim

- **Objetivo:** revisar los cambios del agente en el editor real y devolverle los comentarios sin copiar y pegar.
- **Entregables:** desde los archivos editados del último turno (F6), abrir el diff en NvChad; comentarios en líneas o rangos que se convierten en un prompt estructurado y se escriben en el panel de Claude de ese workspace.
- **Criterio de cierre:** por definir en su spec; como mínimo, comentarios en dos archivos llegan al panel de Claude como un solo prompt con archivo, líneas y texto.
- **Dependencias:** F6 (`EditorBridge`, claudecode.nvim, «Editados por Claude»).

## F11 · Baúl de secretos

- **Objetivo:** que los secretos de cada proyecto vivan en el Keychain y no en `.env` que un agente pueda leer.
- **Entregables:** baúl en el Keychain de macOS con Touch ID, por workspace y entorno; migrar un `.env` a referencias; inyectar las variables en los procesos que se lancen con el comando de Smalti para ello (no en todo el shell: Smalti no sabe de antemano si en un panel correrá un agente); enmascarar los valores conocidos en el scrollback guardado en disco, en el Observatorio y en el timeline; auditoría de qué proceso usó qué secreto, sin guardar valores.
- **Fuera:** enmascarar en la pantalla (libghostty es dueño del render y del PTY: exigiría cambiar esa Decisión) y el proxy HTTPS de valores de relleno.
- **Criterio de cierre:** por definir en su spec; como mínimo, tras migrar un `.env` de prueba no queda ningún valor en disco, y ningún valor del baúl aparece en el scrollback guardado ni en los registros.
- **Dependencias:** F7.5 (bloqueo de lectura) y F9 (timeline, para enmascararlo).

## Ideas evaluadas

Evaluación de `smalti-diferenciacion.md` (Simón, 2026-11-25), contra lo ya construido en F0–F7 y las Decisiones:

| Idea | Veredicto | Dónde |
| --- | --- | --- |
| Timeline nativo de la sesión | Entra | F9 |
| Ciclo de revisión con Neovim | Entra lo que falta: comentarios → prompt al agente (los diffs con `:w`/`:q` ya están en F6) | F10 |
| Workspaces por proyecto | Entra, sobre el formato de F7 | F8.5 |
| Monitor de contexto por panel | Ya está: modelo y `ctx %` en la cabecera y la barra de estado (F3) | — |
| Diseño refinado | Ya está (F0, F5) | — |
| Notificaciones, restauración, temas, prompt, autocompletado | Ya están (F2, F4, F5, F6) | — |
| Seguro para bases de datos, etapa 1 (guardia de comandos) | Entra, primero: mayor valor por esfuerzo | F7.5 |
| Bloqueo de lectura de `.env` | Entra con la guardia | F7.5 |
| Baúl de secretos, etapa 1 | Entra sin el enmascarado en pantalla | F11 |
| Enmascarado de secretos en el render | Fuera: libghostty es dueño del PTY y del render (Decisión «Procesos al reabrir») | — |
| Proxy HTTPS de valores de relleno (etapa 2 del baúl) | Fuera: intercepta TLS con un certificado de confianza propio y depende de un proceso largo como `smaltid`, ya descartado | — |
| Proxy SQL con `libpg_query` (etapa 2) | Fuera por ahora: alto esfuerzo, no cubre PostgREST ni el MCP de Supabase, y la guardia de comandos cubre los incidentes reales | — |
| Predicción por API y `smaltid` | Ya descartados (Simón, 2026-11-25) | — |
| Publicar Smalti para otros (web en Vercel, Homebrew, actualización automática) | Entra: decisión de Simón (2026-11-25) | F7.6, F7.7 |
| Espacio de donaciones | Entra en la web, no en la app; en la app, un enlace discreto en «Acerca de» y en la ayuda | Web, F7.6 |
| Smalti para Windows y Linux | Fuera por ahora (análisis en «Multiplataforma») | — |
| Navegador, app móvil, VMs, checkpoints | Fuera (como dice el documento) | — |

### Multiplataforma (análisis, sin fase)

- **Lo que se puede reutilizar:** el dominio y los casos de uso (`SmaltiCore`, Swift puro) compilan en Linux y Windows, y varios adaptadores son portables (IPC por socket Unix, receptor OTLP, TOML, archivos de sesión, SQLite). La arquitectura hexagonal es justo lo que lo hace posible.
- **Lo que no:** la app entera (AppKit, vidrio de macOS, Metal, ventanas), las notificaciones, el Keychain, las métricas de Darwin, ImageIO, Quick Look y JavaScriptCore de las specs de Fig. Es una app nueva por plataforma sobre el mismo núcleo.
- **Linux:** viable con mucho esfuerzo. Ghostty tiene su app de GTK sobre el mismo núcleo, pero la API embebida de libghostty que usa Smalti está pensada para macOS; la interfaz habría que escribirla en GTK desde Swift, con bindings aún inmaduros. Estimación: del orden de F1–F5 otra vez.
- **Windows:** muy difícil hoy. Ghostty no soporta Windows, así que haría falta otro motor de terminal (ConPTY con otro renderer), además de reescribir la interfaz. Sería otro producto.
- **Recomendación:** quedarse en macOS. Si hubiera demanda, Linux antes que Windows, como fase propia con spec y cambio de la Decisión «Alcance».


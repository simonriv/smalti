# F0 · Spike del motor — Spec

Estado: aprobada · 2026-11-22 · Roadmap: `docs/ROADMAP.md#f0--spike-del-motor`

## Objetivo

Comprobar, con el menor código posible, que Swift + AppKit + libghostty sirven como base de Smalti:

1. libghostty compila reproduciblemente desde un commit fijado.
2. Una superficie libghostty se embebe en una ventana de vidrio sin botones.
3. Claude Code se ve y se siente igual que en Ghostty.app.
4. La frontera hexagonal (`TerminalEngine`) aguanta sin que tipos de C crucen al dominio.

El spike responde preguntas. Su código de producción se conserva solo si cumple las convenciones de `CLAUDE.md`. Lo exploratorio va en `spikes/` y se borra al cerrar.

## Alcance

- **Build del motor**
  - Ghostty como submódulo en `vendor/ghostty`, fijado al commit del tag `v1.4.0` (`ce787fc18a7782e81585beb63f0d905ccaf69284`). Es la misma versión que Ghostty.app instalado, así las comparaciones son en igualdad de condiciones.
  - Zig: el commit exige `minimum_zig_version = 0.17.0`. Se usa el de Homebrew (0.17.1); si no compila, se instala la versión exacta fuera de Homebrew.
  - Script `scripts/build-ghostty.sh` que produce `GhosttyKit.xcframework` (no versionado) y copia los recursos que necesita: terminfo `xterm-ghostty` e integración de shell.
- **Proyecto**
  - App macOS en Xcode que consume un paquete SwiftPM local `SmaltiCore` y un target de adaptador.
  - Bundle ID `dev.simonriv.smalti`, firma ad hoc local (sin Developer ID ni notarización) y macOS 27 como versión mínima.
- **Ventana** (tokens de `docs/design/README.md`)
  - Sin semáforo visible, contenido a tamaño completo, radio de 16 px, borde `rgba(255,255,255,0.09)` y sombra.
  - Fondo `rgba(13,15,21,0.62)` con desenfoque de 28 px y saturación de 150 %.
  - Franja superior de 40 px, vacía, que arrastra la ventana. Margen de 10 px al área de paneles.
- **Panel único**
  - Superficie libghostty dentro de un contenedor con fondo `rgba(6,7,10,0.34)`, borde `rgba(255,255,255,0.07)` y radio de 11 px.
  - JetBrains Mono 13 px; zsh como login shell en `$HOME`.
- **Integración de shell:** inyección automática de zsh (OSC 133 y OSC 7) sin tocar `.zshrc`; `TERM=xterm-ghostty` con terminfo empaquetado.
- **Aislamiento de configuración:** Smalti no lee `~/.config/ghostty/`. La configuración del motor se genera desde valores de Smalti, en F0 fijos en código y documentados.
- **Teclado:** layout Latin American y teclas muertas (á, é, ñ, ü, ¿). ⌥ se reserva para escribir caracteres: no actúa como Meta (equivalente a `macos-option-as-alt = false`).
- **Mediciones** contra Ghostty.app en el mismo commit o versión: rendimiento, memoria y la lista de render.
- **Informe** `docs/specs/F0-spike-report.md`.

## Fuera de alcance

Splits y tiling, workspaces, ⌘K, configuración TOML, cabeceras y barra de estado (F1). Persistencia, IPC, CLI, hooks y notificaciones (F2). Temas, ajuste de vidrio y prompt (F5). Editor de input (F4). Imágenes inline más allá de comprobar que no rompen nada. Distribución, cask y notarización.

## Diseño técnico

### Módulos

```text
SmaltiApp (target de app, Xcode)          ← composition root + adaptadores primarios AppKit
 ├─ SmaltiCore (SwiftPM, Swift puro)      ← dominio + aplicación + puertos
 └─ GhosttyAdapter (SwiftPM)              ← único que importa GhosttyKit
      └─ GhosttyKit.xcframework (binaryTarget, construido por script)
```

- `SmaltiCore` no importa AppKit, SwiftUI, GhosttyKit ni ninguna librería de C. Compila y se prueba con `swift test`, sin Xcode y sin el motor.
- La regla se protege en dos niveles. El compilador la impone, porque `SmaltiCore` no declara dependencias. Además, una prueba de guarda falla nombrando archivo y línea si aparece `import AppKit|SwiftUI|GhosttyKit` en `SmaltiCore`.

### Dominio (mínimo en F0)

- `PaneID` (valor opaco).
- `TerminalSessionSpec`: directorio de trabajo, comando (por defecto, login shell) y variables extra.
- `TerminalEvent`: `titleChanged(String)`, `workingDirectoryChanged(WorkingDirectory)`, `commandFinished(exitCode: Int?, duration: Duration)`, `bell` y `exited(code: Int?)`. Son la base de las cabeceras de F1 y del estado de F2. `commandFinished` sale del fin de comando de OSC 133 (`GHOSTTY_ACTION_COMMAND_FINISHED` en v1.4.0, que no expone un evento por cada prompt).

### Puertos (en `SmaltiCore`, con vocabulario de dominio)

```swift
protocol TerminalEngine {
    func open(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> PaneID
    func close(_ pane: PaneID)
    func events(for pane: PaneID) -> AsyncStream<TerminalEvent>
}
```

- Lo define y nombra quien lo usa: el caso de uso `OpenPane`, mínimo en F0.
- No expone punteros, `NSView` ni tipos de `ghostty_*`.
- La vista es asunto de la UI. Un segundo protocolo pequeño del lado de la app, `TerminalViewProvider.view(for: PaneID) -> NSView`, también lo implementa el adaptador de Ghostty (ISP). Así el dominio nunca ve AppKit.

### Adaptadores

- **`GhosttyTerminalEngine`** (secundario)
  - Envuelve `ghostty_app_t`, `ghostty_config_t` y `ghostty_surface_t`.
  - Implementa los callbacks del runtime embebido: wakeup, acciones, portapapeles y cierre de superficie.
  - Traduce los eventos de C a `TerminalEvent` y los errores a `TerminalEngineError` con contexto.
  - Toda llamada a C ocurre en el `MainActor` o en el hilo que exija la API. Lo documenta el informe.
- **`GhosttyConfigBuilder`:** genera la configuración del motor sin cargar archivos por defecto del usuario. La API exacta para cargarla se verifica en el spike.
- **`TerminalViewProvider` (Ghostty):** devuelve la `NSView` de la superficie (render Metal).
- **AppKit** (primario): `SmaltiWindow` (vidrio, sin semáforo, franja de arrastre) y `PaneContainerView` (fondo, borde y radio del panel).
- **Composition root:** `AppComposition` crea el motor, el proveedor de vistas y la ventana. Es el único lugar que instancia infraestructura.

### Preguntas técnicas que el spike debe cerrar (van al informe)

1. Versión de Zig que exige el commit fijado y cómo se instala (Homebrew da 0.17.1).
2. Qué APIs de `ghostty.h` usa la app de Ghostty para embeber y cuáles necesitamos (lista cerrada).
3. Cómo dar a la superficie un fondo transparente para que el vidrio se vea sin perder contraste. Coste en GPU y batería del desenfoque detrás de una capa Metal.
4. Desenfoque de radio exacto (diseño: 0–48 px) con la API privada de ventana que usa Ghostty, aprobada para uso personal. El material del sistema queda como respaldo si la API falla.
5. Si la inyección de integración de shell funciona con un `ZDOTDIR` propio sin tocar el del usuario.
6. Si libghostty expone el PTY o el PID del proceso en primer plano (necesario en F1 para la cabecera y en F7 para `smaltid`). v1.4.0 tiene `ghostty_surface_foreground_pid`; falta confirmar que funcione y si hay acceso al PTY.
7. Si es viable que Smalti dibuje sobre la zona del prompt (OSC 133) para F4 y F5. Exploración acotada a medio día; solo se documenta.

## Criterios de aceptación

Cada uno se verifica y su evidencia queda en el informe.

| # | Criterio | Verificación |
| --- | --- | --- |
| A1 | Desde un clon limpio, `scripts/bootstrap` + build de Xcode producen la app sin pasos manuales no documentados | Ejecución en un directorio nuevo; comandos copiados al informe |
| A2 | El commit de Ghostty vive en un único lugar (SHA del submódulo) y el build falla si el xcframework no corresponde a ese SHA | Cambiar el SHA sin reconstruir → error explícito |
| A3 | `SmaltiCore` compila y pasa `swift test` sin GhosttyKit; la prueba de guarda de imports está en verde | `swift test` en `Packages/SmaltiCore` |
| A4 | `OpenPane` se prueba con un `FakeTerminalEngine` en memoria | Prueba unitaria (Swift Testing) |
| A5 | La ventana coincide con los tokens: radio 16, borde, sombra, franja de 40 px, margen de 10, panel con radio 11. Sin semáforo visible; se arrastra desde la franja | Captura a 1328×820 superpuesta a `Main.dc.html` |
| A6 | zsh arranca como login shell; `echo $TERM` → `xterm-ghostty`; `infocmp xterm-ghostty` funciona dentro de Smalti | Manual, salida en el informe |
| A7 | `cd /tmp` emite `workingDirectoryChanged`; `false` emite `commandFinished(exitCode: 1, …)` | Log de eventos del adaptador |
| A8 | Cambiar `~/.config/ghostty/config` (p. ej. el tamaño de fuente) no altera Smalti | Manual |
| A9 | Lista de render de Claude Code sin artefactos, igual que en Ghostty.app lado a lado: arranque, spinner, respuesta larga en streaming, diff con colores, prompt de permiso navegado con flechas, redimensionar la ventana durante el streaming, `/help`, scroll del historial durante el streaming, salida y retorno al shell | Grabación de pantalla de ambos |
| A10 | nvim, htop, less y `vim` en pantalla alternativa; ratón en nvim; emoji y CJK con ancho correcto; pegado entre corchetes | Manual |
| A11 | Teclado: á é í ó ú ñ ü ¿ ¡ con el layout Latin American; todo carácter que produce ⌥ en ese layout (p. ej. @, \|, #) llega igual que en TextEdit | Manual |
| A12 | Rendimiento: `time cat` de un archivo de 50 MB y `seq 1 5000000` dentro de ±10 % de Ghostty.app (mediana de 5 ejecuciones) | Script en `scripts/bench/`, resultados en el informe |
| A13 | Fluidez: escribir con un streaming activo no produce bloqueos del hilo principal de más de 16 ms | Instruments (Time Profiler o Hangs), traza resumida en el informe |
| A14 | Memoria en reposo con un panel ≤ 1,2 × la de Ghostty.app con un panel | Monitor de Actividad o `footprint` |
| A15 | Contraste del texto principal `#d7dae0` sobre vidrio ≥ 4.5:1 con el fondo de escritorio por defecto y uno claro | Medición con color picker, valores en el informe |
| A16 | A/B a ciegas: Simón escribe y usa Claude 10 minutos en cada una sin saber cuál es y no las distingue | Registro en el informe |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| La API embebida de libghostty no es pública ni estable y no tiene documentación | Más tiempo leyendo la app de Ghostty y cmux; cambios rompen al actualizar | Commit fijado; el adaptador es el único que la toca; lista cerrada de funciones usadas en el informe |
| Versión de Zig distinta a la de Homebrew | El build no reproduce | El script lee `minimum_zig_version` del `build.zig.zon` y falla con un mensaje claro; si 0.17.1 no sirve, se instala la versión exacta fuera de Homebrew |
| libghostty es dueño del PTY y del proceso hijo | Limita F1 (proceso en primer plano), F4 (editor sobre el prompt) y F7 (`smaltid` dueño de los PTY) | Preguntas técnicas 6 y 7; si no hay salida, se documenta y se replantea la fase afectada en `PROJECT.md` antes de llegar |
| Vidrio detrás de una capa Metal | Más GPU y batería; texto ilegible con fondos claros | Medir en A13–A15; opacidad mínima bajo texto (adelanto de "Proteger legibilidad") |
| Desenfoque con radio exacto solo por API privada | Puede romperse con una actualización de macOS | Aprobada para uso personal; detrás de un adaptador, con respaldo a material del sistema |
| Atajos con ⌥ en el layout Latin American | ⌥ + tecla escribe caracteres (@, \|, #…) | Decidido: ⌥ no se usa para atajos ni como Meta; A11 lo verifica |
| Swift 6 con concurrencia estricta frente a callbacks de C | Avisos o carreras en los callbacks del runtime | Aislar en el adaptador con `@MainActor` y puentes explícitos; documentar el hilo de cada callback |

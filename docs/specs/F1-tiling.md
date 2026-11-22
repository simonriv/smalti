# F1 · Tiling y workspaces — Spec

Estado: aprobada (se revisa con el informe de F0 antes de empezar) · 2026-11-22 · Roadmap: `docs/ROADMAP.md#f1--tiling-y-workspaces`
Diseño: `docs/design/Main.dc.html` (ventana, layouts, cabeceras, barra de estado) y `docs/design/Paleta.dc.html` (⌘K).

## Objetivo

Que Smalti reemplace a Ghostty para trabajar con 3 sesiones de Claude: varios paneles con tiling automático, manejables por teclado, agrupados en workspaces por proyecto y con una paleta ⌘K como único centro de control.

## Alcance

- **`LayoutTree`:** árbol binario de splits, en el dominio.
- **Layouts automáticos:** Dwindle, Columnas y Maestro + pila. Cambio por atajo o ⌘K.
- **Operaciones por teclado:** nuevo panel, cerrar, foco direccional y por índice, intercambiar con el vecino, redimensionar e igualar tamaños.
- **Ratón (opcional, secundario):** clic para enfocar y arrastrar el separador para redimensionar.
- **Workspaces:** crear, renombrar, cambiar y cerrar. Cada uno tiene sus paneles, su layout y su directorio raíz, y los procesos de los workspaces ocultos siguen vivos.
- **Franja superior** (40 px): workspaces con punto de estado, botón "+" y pista `⌘K`. Es zona de arrastre.
- **Cabecera de panel** (30 px): punto, proceso, directorio y atajo.
- **Barra de estado** (28 px): `<workspace> · N paneles · <layout>`.
- **Configuración TOML** en `~/.config/smalti/config.toml`: apariencia base, layout por defecto, shell y atajos, más el comando "Recargar configuración".
- **⌘K básica:** búsqueda difusa sobre el catálogo de comandos de F1, agrupada como en `Paleta.dc.html`.

## Fuera de alcance

- Guardar y restaurar layouts con nombre, y persistencia al reabrir (F2). Los comandos "Guardar layout…" y "Restaurar layout…" del tablero llegan en F2.
- Estado de agente (trabajando, te espera, error), contadores de la franja, modelo y % de contexto en la cabecera, borde ámbar del panel que espera (F2–F3).
- Lado derecho de la barra de estado: Ollama, RAM, GPU y tokens (F3).
- Rama de git y módulos de la cabecera o del prompt (F5). Editor de input y completions (F4).
- Recarga automática de la configuración al cambiar el archivo y edición desde la UI (F5).
- Varias ventanas: F1 usa una sola ventana.

## Diseño técnico

### Módulos

Los de F0, más un adaptador nuevo:

```text
SmaltiApp ──▶ SmaltiCore ◀── GhosttyAdapter
                  ▲
                  └──────── TOMLConfigAdapter (único que importa la librería TOML)
```

### Dominio (`SmaltiCore/Domain`, Swift puro)

- **Geometría propia:** `Size`, `Point` y `Rect` en puntos. No se usa `CGRect` en el dominio.
- **`Pane`:** `id`, `workingDirectory`, `title` y `processName`. Se actualiza con los `TerminalEvent` de F0.
- **`LayoutTree`:** `indirect enum` con dos casos.
  - `leaf(PaneID)`
  - `split(axis: Axis, ratio: Ratio, first: LayoutTree, second: LayoutTree)`
  - `Ratio` se limita a 0,1–0,9.
  - Operaciones puras:
    - `frames(in: Rect, gap: 8) -> [PaneID: Rect]`
    - `resizing(_:edge:by:minimum:)`
    - `equalized()`, que pondera por número de hojas
    - `swapping(_:_:)`
    - `neighbor(of:direction:)`, calculado con `frames`
- **`LayoutStrategy`** (protocolo; una implementación por layout, sin `switch` por tipo). Construye el árbol a partir del orden de paneles: `func tree(for panes: [PaneID]) -> LayoutTree`.
  - **`DwindleLayout`:** el primer split es vertical con ratio 0,574 (1.35fr / 1fr del tablero). Cada panel siguiente divide al último, alternando el eje: horizontal, vertical… Los splits internos van a 0,5. Con 3 paneles da `a | (b / c)`, igual que `Main.dc.html`.
  - **`ColumnsLayout`:** N columnas iguales.
  - **`MasterStackLayout`:** maestro arriba a lo ancho, con ratio de alto 0,535 (1.15fr / 1fr), y la pila abajo en columnas iguales. Así lo dibujan `Main.dc.html` (`'a a' 'b c'`) y el icono de la paleta (decidido).
- **`Workspace`:** `id`, `name`, `rootDirectory`, `panes` (ordenados), `layout`, `tree` y `focusedPane`.
  - **Cambios estructurales** (abrir, cerrar, cambiar de layout): reconstruyen `tree` desde `panes` con la estrategia, y se pierden los ajustes manuales. Es una regla documentada.
  - **Cambios geométricos** (redimensionar, igualar): editan `ratio`.
  - **Intercambiar:** reordena `panes` y conserva los ratios.
  - Invariante: `tree` contiene exactamente los `panes`, y `focusedPane` pertenece a ellos.
- **`WorkspaceSet`:** workspaces ordenados y el activo. El índice de un panel (1…9) es su posición en el workspace activo.
- **`Command`:** `id`, `title`, `subtitle`, `group` y atajo. El `CommandCatalog` lista los comandos disponibles según el estado.
- **`fuzzyMatch(query, in: [Command]) -> [RankedCommand]`:** función pura.

### Aplicación: casos de uso

`OpenPane`, `ClosePane`, `FocusPane` (por dirección o índice), `SwapPane`, `ResizePane`, `EqualizePanes`, `SwitchLayout`, `CreateWorkspace`, `RenameWorkspace`, `SwitchWorkspace`, `CloseWorkspace`, `ReloadConfig` y `SearchCommands`.

- Cada uno se ejecuta desde una prueba con fakes en memoria.
- Abrir y cerrar llaman a `TerminalEngine`. Cerrar el último panel de un workspace lo deja vacío con un panel nuevo al pedirlo, no cierra la ventana.
- Un panel nuevo abre en el directorio del panel enfocado; si no se conoce, en el `rootDirectory` del workspace.
- Tamaño mínimo de panel: 240 × 120 pt. Si abrir uno violaría el mínimo, el caso de uso devuelve un error tipado y la UI lo muestra en la barra de estado.

### Puertos

| Puerto | Uso en F1 | Adaptador |
| --- | --- | --- |
| `TerminalEngine` (de F0) | Abrir y cerrar paneles; eventos de título y directorio | `GhosttyTerminalEngine` |
| `ConfigStore` | `current() throws(ConfigError) -> SmaltiConfig` y `reload()` | `TOMLConfigStore` |

- `SmaltiConfig` es un tipo de valor del dominio con valores por defecto iguales a los tokens del tema Obsidiana.
- Si el TOML no es válido, se conserva la última configuración válida y el error, con archivo, línea y clave, aparece en la barra de estado.

```toml
# ~/.config/smalti/config.toml: valores por defecto
[appearance]
accent = "#7aa2f7"
glass_opacity = 0.62
blur = 28
font_family = "JetBrains Mono"
font_size = 13
gap = 8
radius = 11

[tiling]
default_layout = "dwindle"   # dwindle | columns | master

[shell]
command = "login"            # login shell del usuario

[keys]                       # atajo → id de comando; ver tabla de atajos
```

### Adaptadores primarios (AppKit)

- **`WorkspaceStripView`:** pastillas de 26 px con radio 7. La activa lleva borde de acento al 50 % y fondo de acento al 13 %. Punto de 6 px en `#565c68` en F1 (neutral hasta F2). Botón "+" y pista `⌘K`.
- **`PaneGridView`:** coloca las vistas de terminal según `frames`.
  - Margen de 10 y separación de 8.
  - Panel enfocado: borde de acento al 50 % más `0 0 28px` de brillo al 13 %. Resto: borde `rgba(255,255,255,0.07)`.
  - Animación de reacomodo de 150 ms como máximo; se desactiva con "Reducir movimiento".
- **`PaneHeaderView`:** 30 px, Inter 11,5 px. Punto de 7 px, proceso en `#e6e9ef` 600, directorio abreviado en `#9aa0ab` y atajo en `kbd`. El atajo se muestra como `⌘1`…`⌘9`, no `⌥1` como en el tablero: es una desviación decidida por el layout Latin American.
- **`StatusBarView`:** 28 px, Inter 11 px, `#8b919c`.
- **`CommandPaletteView`:** 640 px de ancho, radio 14, fondo `rgba(20,22,30,0.82)` con desenfoque de 36 px.
  - Campo de 52 px a 16 px, filas de 38 px con icono de 16 px y título a 13,5 px.
  - Grupos en mayúsculas a 10,5 px con tracking 0,06em. Pie de 36 px con `↑↓ ↵ esc`.
  - Selección con fondo de acento al 15 %.
- **`KeyRouter`:** traduce los atajos de `SmaltiConfig.keys` a casos de uso. Lo que no es atajo de Smalti pasa intacto a la superficie de libghostty.

### Atajos por defecto (editables en TOML)

| Acción | Atajo | Origen |
| --- | --- | --- |
| Paleta | ⌘K | Diseño |
| Layout Dwindle / Columnas / Maestro | ⌥⌘D / ⌥⌘C / ⌥⌘M | Diseño (⌥⌘D es propuesta) |
| Igualar tamaños | ⇧⌘= | Diseño |
| Ir al panel N | ⌘1…⌘9 (el diseño usa ⌥1…⌥9; cambiado porque ⌥ escribe caracteres en el layout Latin American) | Decidido |
| Nuevo panel / cerrar panel | ⌘D / ⌘W | Propuesta |
| Foco direccional | ⌥⌘ + flechas | Propuesta |
| Intercambiar con el vecino | ⇧⌥⌘ + flechas | Propuesta |
| Redimensionar (5 % por pulsación) | ⌃⌥⌘ + flechas | Propuesta |
| Workspace N / nuevo workspace | ⌃1…⌃9 / ⌃⌘N | Decidido / propuesta |

## Criterios de aceptación

| # | Criterio | Verificación |
| --- | --- | --- |
| B1 | Cada estrategia produce el árbol esperado para 1…9 paneles; con 3, los rectángulos coinciden con las proporciones de `Main.dc.html` (Dwindle 1.35:1; Maestro 1.15:1 de alto; Columnas iguales) con margen de 10 y separación de 8 | Pruebas parametrizadas de dominio |
| B2 | Invariantes de `Workspace` tras cualquier secuencia de abrir, cerrar, intercambiar y cambiar de layout | Prueba con secuencias generadas (semilla fija) |
| B3 | Redimensionar respeta el mínimo de 240 × 120 y los límites de `Ratio`; igualar deja hojas del mismo tamaño en cada eje | Pruebas de dominio |
| B4 | El foco direccional elige el vecino geométrico correcto, incluidos los casos sin vecino (no hace nada) | Pruebas de dominio |
| B5 | Todos los casos de uso pasan con `FakeTerminalEngine` y `InMemoryConfigStore`; prueba de contrato compartida para `ConfigStore` (fake y TOML) | `swift test` |
| B6 | TOML: los valores por defecto se aplican sin archivo; un archivo inválido conserva la configuración previa y muestra archivo, línea y clave | Pruebas del adaptador con fixtures |
| B7 | `fuzzyMatch("lay")` devuelve los 3 layouts primero; la paleta abre en ≤ 50 ms y navega solo con teclado | Prueba de dominio; medición con signpost |
| B8 | Con 4 paneles y 3 sesiones de Claude en streaming, escribir no genera bloqueos del hilo principal de más de 16 ms y el reacomodo no deja frames en blanco | Instruments, traza en el PR |
| B9 | Los procesos de un workspace oculto siguen vivos: un `sleep 30; say listo` termina mientras otro workspace está visible | Manual |
| B10 | Capturas de la ventana con 3 paneles en los 3 layouts y de la paleta coinciden con los tableros (colores, medidas, tipografías y textos) | Captura superpuesta al tablero, adjunta al PR |
| B11 | Los atajos no rompen la escritura: con el layout Latin American, todo carácter producido con ⌥ (@, \|, #…) llega al shell y a Claude Code; ningún atajo de Smalti usa ⌥ sin ⌘ o ⌃ | Manual, lista en el PR |
| B12 | Prueba de guarda: `SmaltiCore` sigue sin importar AppKit, SwiftUI, GhosttyKit ni la librería TOML | `swift test` |

## Riesgos

| Riesgo | Efecto | Mitigación |
| --- | --- | --- |
| Conflictos de atajos con programas de terminal (nvim y Claude usan ⌃; ⌃1…⌃9 podría chocar en algún TUI) | Atajos que roban teclas al programa | `KeyRouter` con lista explícita; todo editable en TOML |
| Reconstruir el árbol en cambios estructurales borra ajustes manuales | Molestia al abrir o cerrar paneles | Regla documentada; si duele en el uso real, se guardan ratios por posición |
| Reacomodar varias superficies Metal a la vez | Parpadeo o frames en blanco al redimensionar | Reacomodo sin animar el contenido del terminal, solo el marco; B8 lo mide |
| Muchas superficies vivas en workspaces ocultos | Memoria y GPU | Medir con 9 paneles; pausar el render de superficies ocultas si la API lo permite (informe de F0) |
| Librería TOML de terceros | Dependencia y API ajena | Detrás de `ConfigStore`, con errores traducidos en la frontera; candidata TOMLKit, se elige en el plan |
| Proceso en primer plano sin acceso al PTY | La cabecera muestra solo el título OSC | Depende de la pregunta técnica 6 de F0; en ese caso se usa el título |

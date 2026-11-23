# Diseño de Smalti — fuentes del canvas aprobado

Estos seis archivos son la referencia visual obligatoria. Son mockups en HTML con estilos inline, exportados del canvas de diseño (https://claude.ai/artifact/9nZ1hJvmU1asdcEN4SLtYT). No son código de producción: léelos para sacar colores, medidas, tipografías, jerarquía y textos de la interfaz, y reprodúcelos en AppKit/SwiftUI.

## Cómo leerlos

- Cada archivo es un tablero de 1440×900 px que muestra la ventana de Smalti (1328×820) sobre un fondo de escritorio.
- El marcado visible está dentro de `<x-dc>`. Los estilos están inline en cada elemento.
- `{{nombre}}` son valores variables. Sus valores por defecto están en el bloque `<script data-dc-script>` al final de cada archivo (`renderVals()` y `data-props`). Ejemplo en `Main.dc.html`: `accent = #7aa2f7`, `glass = 0.62`, `blur = 28px`, `layout = Dwindle`.
- `<sc-if>` y `<sc-for>` son condicionales y bucles del formato del canvas; ignóralos como estructura de UI.

| Archivo | Pantalla |
| --- | --- |
| `Main.dc.html` | Ventana principal: workspaces, tiling de 3 paneles (Dwindle / Columnas / Maestro), cabeceras de panel, editor de input con completions, preview de imagen, barra de estado |
| `Observatorio.dc.html` | Observatorio de agentes (⌘⇧A) |
| `Paleta.dc.html` | Paleta de comandos (⌘K) |
| `Apariencia.dc.html` | Panel de apariencia y temas |
| `Prompt.dc.html` | Estudio de prompt |
| `Reanudar.dc.html` | Retomar sesiones al abrir |

## Tokens extraídos (tema Obsidiana)

| Token | Valor |
| --- | --- |
| Fondo de ventana | `rgba(13,15,21, 0.62)` + desenfoque 28 px, saturación 150 % |
| Borde de ventana | `rgba(255,255,255,0.09)`, radio 16 px, sombra `0 30px 90px rgba(0,0,0,0.5)` |
| Fondo de panel | `rgba(6,7,10,0.34)`, borde `rgba(255,255,255,0.07)`, radio 11 px |
| Separación entre paneles | 8 px; margen interno del área de paneles 10 px |
| Franja superior | 40 px de alto; barra de estado 28 px; cabecera de panel 30 px |
| Texto principal | `#d7dae0`; títulos `#e6e9ef` |
| Texto secundario | `#8b919c` (mínimo para texto pequeño sobre vidrio) |
| Acento (por defecto) | `#7aa2f7`; anillo de panel activo = acento al 50 %, brillo = acento al 13 % |
| Estado: trabajando | `#9ece6a` |
| Estado: te espera | `#e0af68` |
| Estado: error | `#f7768e` |
| Estado: detenido | círculo hueco `#6b717c` |
| Otros ANSI | morado `#bb9af7`, cian `#7dcfff` |
| Texto fantasma (F4) | `#5f6672`; ~3:1 sobre el vidrio, excepción al 4.5:1 aceptada hasta F5 (es un indicio, no texto) |
| Tipografía terminal | JetBrains Mono 12.5–13 px, interlineado 1.62 |
| Tipografía interfaz | Inter 11–13 px; etiquetas en mayúsculas 10.5 px con tracking 0.06em |

Paleta ANSI completa: ver `Apariencia.dc.html`.

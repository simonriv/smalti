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
| Texto fantasma (F4) | `#5f6672`; ~3:1 sobre el vidrio solo con "Proteger legibilidad" desactivada; con ella activa se aclara hasta 4.5:1 (spec F5) |
| Tipografía terminal | JetBrains Mono 12.5–13 px, interlineado 1.62 |
| Tipografía interfaz | Inter 11–13 px; etiquetas en mayúsculas 10.5 px con tracking 0.06em |

Paleta ANSI completa: ver `Apariencia.dc.html`.

**Preview de imagen de `Main.dc.html` (spec F5.5):** la tarjeta se usa sobre nombres de archivo locales, no sobre URLs, y su pie dice "⌘Y para abrir" en lugar de "espacio para abrir".

## Temas de F5 y maquetas aprobadas

Niebla, Ámbar nocturno y Bosque se completaron a partir de las muestras de `Apariencia.dc.html`: la tabla fuente es `THEMES` en `docs/specs/F5-assets/generate-mockups.py`, que comprueba que todo color protegido da ≥ 4.5:1 sobre el panel de su tema. Maquetas aprobadas con la spec F5: `mockup-themes`, `mockup-buttons`, `mockup-prompt` y `mockup-legibility` en `docs/specs/F5-assets/`.

## Resaltado del input (F5.6)

Ningún tablero cubre la línea coloreada. Su referencia es `docs/specs/F5.6-assets/mockup-highlight.png` (generada por `generate-mockups.py` de esa carpeta con las tablas de temas de F5): comando ANSI 4, desconocido en el color de error, subcomando ANSI 6, opción y variable ANSI 5, cadena ANSI 2, ruta subrayada y operador en texto secundario, con "Proteger legibilidad".

## Multi-harness (F6)

- `Reanudar.dc.html`: sin el chip ni la fila de Gemini (Gemini CLI quedó fuera). La tarjeta «Todas las sesiones de agentes» también se abre sola, centrada, con ⌘⇧O; escribir filtra y el texto sale en el lugar del subtítulo. Una fila de respaldo dice «`agy -c` · la última del directorio».
- `Observatorio.dc.html`: los filtros también se cambian con ⌘⇧F; el pie añade «base de OpenCode».

## Guardas para agentes (F7.5)

- Ningún tablero dibuja la aprobación. La tarjeta va abajo y centrada en el panel (como máximo 560 pt de ancho, 12 pt de margen), con el fondo, el radio y la sombra de la tarjeta de vista previa de `Main.dc.html` y el borde y el punto en el ámbar de «te espera». Muestra «Espera tu aprobación · <workspace>», «1 de N», «<regla> contra **PROD** · <host o causa>», el comando en mono (máximo 8 líneas, con scroll) y «⌘⇧↩ aprobar   ⌘⇧⎋ rechazar   vence en N min». «PROD» va en negrita, sin color nuevo. La cabecera del panel dice «espera tu aprobación · 2m».
- `Paleta.dc.html`: el grupo nuevo «Esperan tu aprobación» va primero, con «Aprobar “…” en <workspace>» y «Rechazar…». «Proteger secretos en “<proyecto>”» y «Actualizar integración con Claude Code» van en «Configuración», con el estilo de las integraciones.

## Extras (F7)

- `Observatorio.dc.html`: con telemetría de Claude Code recibida, el detalle añade bajo la línea de compactación, con su mismo estilo, «Telemetría · desde 10:42 · 42 peticiones · mediana 1,4 s · 2 errores de API · $3.12 según Claude Code», y el pie dice «hooks, transcripts y telemetría de Claude Code». Si la telemetría está configurada fuera de Smalti, el pie lo dice.
- `Paleta.dc.html`: el grupo «Workspaces y sesiones» añade «Exportar layout “<nombre>”…» tras cada «Restaurar layout» e «Importar layout…»; la confirmación y los paneles de archivo son los del sistema.

## Puertos y procesos (F8)

Ningún tablero los dibuja. La referencia es la maqueta `docs/specs/F8-assets/mockup.html` (`?view=processes|ports|confirm&lang=es|en`; capturas `mockup-*-{es,en}.png`), compuesta con el fondo, la franja superior, las tarjetas, las tablas y los chips de `Observatorio.dc.html` y la tarjeta de aprobación de F7.5 (en ámbar) para confirmar «Forzar». Atajos ⌘⇧M y ⌘⇧U; textos en inglés del glosario de la spec F8.

## Proyectos (F8.5)

Ningún tablero los dibuja. La referencia es la maqueta `docs/specs/F8.5-assets/mockup.html` (`?view=palette|recent|confirm|changed|replace&lang=es|en`; capturas `mockup-*-{es,en}.png`), compuesta con la caja de vidrio, las filas, los grupos y el pie de `Paleta.dc.html`, y el borde y el punto ámbar de la aprobación de F7.5 para la confirmación. Atajo ⌘O; textos en inglés del glosario de la spec F8.5.

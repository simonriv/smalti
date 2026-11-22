# Smalti · Marca

El símbolo está formado por **los tres paneles del layout Dwindle, partidos como vidrio por una junta a 15°**. El nombre *smalti* designa las teselas de vidrio de los mosaicos bizantinos: el símbolo une las dos ideas del producto, el mosaico (los paneles en tiling) y el vidrio (el corte).

![Logotipo horizontal sobre fondo oscuro](preview/smalti-horizontal-color-on-dark.png)

## Construcción

- **Retícula:** lienzo de 256 con el arte en un cuadrado de 208 (margen de 24).
- **Proporción:** panel izquierdo y columna derecha en 1,35 : 1, la misma del tablero `Main.dc.html`. La columna derecha se divide a la mitad.
- **Juntas:** la junta vertical está inclinada 15° y mide 20 de ancho (perpendicular al corte). La junta horizontal también mide 20.
- **Esquinas:** las exteriores tienen radio 18. Las de los bordes cortados quedan vivas, porque son vidrio partido.
- **Código fuente:** `source/build_symbol.py`. Todas las variantes salen de la misma construcción, así que no se edita a mano.

## Archivos

| Archivo | Uso |
| --- | --- |
| `logo/smalti-symbol.svg` | **Maestro**: símbolo en negro |
| `logo/smalti-symbol-color.svg` | Símbolo en acento `#7aa2f7` |
| `logo/smalti-symbol-white.svg` | Invertido sobre fondos oscuros; juntas de 22, ópticamente más fino |
| `logo/smalti-symbol-on-dark.svg` | Símbolo en acento sobre una pastilla `#0d0f15` |
| `logo/smalti-symbol-small.svg` | Corte para 16–24 px: juntas de 30, radio 12 |
| `logo/smalti-horizontal*.svg` | Logotipo horizontal: negro, blanco, color sobre claro y color sobre oscuro |
| `logo/smalti-stacked*.svg` | Logotipo apilado: negro y color |
| `logo/smalti-wordmark*.svg` | Solo la palabra, en negro y en blanco |
| `icons/` | Favicon (`.ico`, `.svg`, 16/32/48), íconos web 192/512, maskable, `apple-touch-icon`, `site.webmanifest`, `head-snippet.html` y las variantes negro, blanco y acento |
| `macos-icon/1-fondo.svg` · `2-teselas.svg` · `3-brillo.svg` | Capas del ícono de macOS para Icon Composer (1024 × 1024) |
| `macos-icon/preview-composed.svg` | Solo para revisar: las tres capas compuestas, con una máscara aproximada |

## Color

| Rol | HEX | RGB |
| --- | --- | --- |
| Acento (teselas) | `#7aa2f7` | 122 · 162 · 247 |
| Fondo | `#0d0f15` | 13 · 15 · 21 |
| Texto sobre fondo oscuro | `#e6e9ef` | 230 · 233 · 239 |

- **Contraste del acento sobre el fondo:** 7,6 : 1. Sobre blanco baja a 2,5 : 1, así que en fondos claros el símbolo va en negro.
- **Una sola tinta:** usa el negro o el blanco puros. El símbolo no necesita el color para leerse.
- **Lo que no se hace:** no se aplican degradados, sombras ni contornos al símbolo.

## Logotipo

- **Tipografía:** "smalti" en Inter SemiBold (600) minúscula, convertida a contornos, con un tracking de −0,01 em.
- **Licencia:** Inter usa la SIL OFL 1.1, que permite usarla en logotipos.
- **Detalle propio:** el punto de la "i" es una tesela cuadrada del ancho del trazo, en lugar del punto redondo de Inter. Una tesela inclinada se leía como tilde ("smaltí") y se descartó.
- **Horizontal:** el símbolo mide lo mismo que la altura de la "l" y la separación es 0,42 veces esa altura.
- **Apilado:** el símbolo mide 1,7 veces la altura de la "l" y va centrado.

## Espacio de protección y tamaños mínimos

- **Espacio de protección:** alrededor del símbolo o del logotipo deja libre, como mínimo, el ancho de la columna derecha del símbolo.
- **Símbolo:** 16 px como mínimo en pantalla. Por debajo de 24 px usa `smalti-symbol-small.svg`.
- **Logotipo horizontal:** 96 px de ancho como mínimo. Si hay menos espacio, usa solo el símbolo.

## Usos incorrectos

- Girar el símbolo, reflejarlo o cambiar el ángulo de la junta.
- Redondear los bordes cortados o cerrar las juntas.
- Colorear cada panel con un tono distinto. El estado de la app (verde, ámbar, rojo) no forma parte del logo.
- Agregar `>_`, destellos u otros adornos.
- Poner el símbolo en acento sobre fondos claros con poco contraste. Ahí va en negro.

## Ícono de macOS en Icon Composer

**La app ya usa el ícono:** `App/Smalti/AppIcon.icon` es un archivo de Icon Composer con las teselas (con Liquid Glass) y el brillo (al 30 %, *Plus Lighter*) sobre el fondo `#0d0f15`. El target lo compila con `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Para afinarlo, abre `AppIcon.icon` en Icon Composer y guarda: no hace falta tocar nada más. Los pasos de abajo son para rehacerlo desde las capas sueltas.


1. Crea un ícono nuevo en Icon Composer y arrastra las tres capas en este orden: `1-fondo.svg` (abajo), `2-teselas.svg` y `3-brillo.svg` (arriba).
2. **Fondo:** sin material de vidrio, color sólido.
3. **Teselas:** aplícales el material Liquid Glass. Es la capa que debe reaccionar a la luz.
4. **Brillo:** opacidad de 25–40 % y modo *Plus Lighter* o *Screen*. Si el material ya produce suficiente reflejo, desactívala.
5. Revisa las apariencias oscura, clara y tintada. En la tintada el acento se pierde, pero la forma se mantiene porque el símbolo funciona en una tinta.

## Regenerar

```bash
python3 brand/source/build_symbol.py brand/logo
python3 brand/source/build_wordmark.py "$HOME/Library/Fonts/Inter-VariableFont_opsz,wght.ttf" brand/logo   # requiere fontTools
python3 brand/source/build_macos_icon.py brand/macos-icon
# Copia las capas al ícono de la app (sin <title>, que Icon Composer no necesita):
for l in teselas brillo; do n=$([ $l = teselas ] && echo 2 || echo 3); sed '/<title>/d' brand/macos-icon/$n-$l.svg > App/Smalti/AppIcon.icon/Assets/$l.svg; done
```

Los íconos web se generaron con el `export_variants.py` de la skill `logo-design`, a partir de `smalti-symbol.svg` y con `smalti-symbol-small.svg` como fuente del favicon.

## Notas

- **Registro de marca:** no se hizo búsqueda de marcas registradas. Smalti es de uso personal, sin registro (Decisiones de `docs/PROJECT.md`).
- **Conceptos descartados:** "Tesela con cursor" y "S de teselas". Su revisión está en `preview/concepts.png`.

"""F5 mockups: themes, window buttons, prompt in the pane and "Proteger legibilidad".

Usage: python3 generate-mockups.py <out-dir>   (then render each .html at 1440x900 with headless Chrome).
The theme tables below are the proposal of the F5 spec; `check_themes()` fails if one stops passing 4.5:1.
"""

import pathlib
import sys

# ---------------------------------------------------------------- themes (spec F5, "Temas")
THEMES = {
    "Obsidiana": dict(
        dark=True, glass="#0d0f15", panel="#06070a", text="#d7dae0", title="#e6e9ef", secondary="#8b919c",
        ghost="#5f6672", accent="#7aa2f7", border="255,255,255",
        working="#9ece6a", waiting="#e0af68", failed="#f7768e", stopped="#6b717c",
        ansi="#15161e #f7768e #9ece6a #e0af68 #7aa2f7 #bb9af7 #7dcfff #a9b1d6 "
        "#414868 #ff99ad #b9f27c #ffc777 #a3bdfa #d3b8ff #a4e3ff #c0caf5",
    ),
    "Niebla": dict(
        dark=False, glass="#eef0f4", panel="#ffffff", text="#2a2e36", title="#1c1f25", secondary="#5c6370",
        ghost="#8a909b", accent="#3b5bdb", border="0,0,0",
        working="#2f9e44", waiting="#c77c02", failed="#e03131", stopped="#868e96",
        ansi="#2a2e36 #c92a2a #237a36 #9a5800 #3b5bdb #9c36b5 #0b7285 #868e96 "
        "#495057 #c2255c #1e7b34 #8f5200 #364fc7 #862e9c #0a6e6e #ced4da",
    ),
    "Ámbar nocturno": dict(
        dark=True, glass="#1a1410", panel="#0c0907", text="#e8dccb", title="#f2e8da", secondary="#a39582",
        ghost="#6e6355", accent="#e0af68", border="255,240,220",
        working="#b5c97a", waiting="#e0af68", failed="#e8826f", stopped="#7a6e60",
        ansi="#1f1914 #e8826f #b5c97a #e0af68 #8fa8c8 #c79bc0 #8cc4b8 #d8ccb9 "
        "#4a3f33 #f29c8a #c9db92 #f0c88a #a9bfdb #dab3d4 #a6d7cc #f2e8da",
    ),
    "Bosque": dict(
        dark=True, glass="#0f1714", panel="#060a08", text="#cfe0d8", title="#e2efe9", secondary="#8a9c94",
        ghost="#5a6b63", accent="#6fd3b5", border="220,255,240",
        working="#a6d86b", waiting="#e3c06f", failed="#ec7f86", stopped="#62746c",
        ansi="#141e1a #ec7f86 #a6d86b #e3c06f #74b3e0 #b99be0 #6fd3b5 #b9cbc2 "
        "#3c4f47 #f59ca2 #bde68a #eed28e #95c8ee #ceb5ee #92e2ca #e2efe9",
    ),
}
GLASS_OPACITY = 0.62
# 4.5 plus a margin: Core Animation blends without rounding each layer (spec F5, block 1 review).
SEARCH_CONTRAST = 4.55
PANEL_OPACITY = 0.34


def linear(channel):
    c = channel / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (linear(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def rgb(hex_color):
    return tuple(int(hex_color[i : i + 2], 16) for i in (1, 3, 5))


def over(top, alpha, bottom):
    return tuple(alpha * t + (1 - alpha) * b for t, b in zip(top, bottom))


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def protected_colors(theme):
    """Text tokens the 4.5:1 rule covers: text, secondary and the ANSI colors that are not the background pair."""
    ansi = theme["ansi"].split()
    background_pair = {0, 8} if theme["dark"] else {7, 15}
    return [theme["text"], theme["secondary"]] + [c for i, c in enumerate(ansi) if i not in background_pair]


def check_themes():
    for name, theme in THEMES.items():
        ground = rgb(theme["panel"])
        failing = [c for c in protected_colors(theme) if contrast(rgb(c), ground) < 4.5]
        assert not failing, f"{name}: below 4.5:1 on its opaque panel: {failing}"


def protected_panel_opacity(theme):
    """Smallest panel opacity that keeps every protected color at 4.5:1 over the worst desktop."""
    worst = (255, 255, 255) if theme["dark"] else (0, 0, 0)
    under = over(rgb(theme["glass"]), GLASS_OPACITY, worst)
    for step in range(int(PANEL_OPACITY * 100), 101):
        ground = over(rgb(theme["panel"]), step / 100, under)
        if all(contrast(rgb(c), ground) >= SEARCH_CONTRAST for c in protected_colors(theme)):
            return step / 100
    return 1.0


def protected_ghost(theme, ground):
    """The ghost moved toward the text color, in 1 % steps, until it reaches 4.5:1 on `ground`."""
    ghost, text = rgb(theme["ghost"]), rgb(theme["text"])
    for step in range(0, 101):
        mixed = over(text, step / 100, ghost)
        if contrast(mixed, ground) >= SEARCH_CONTRAST:
            return "#" + "".join(f"{round(c):02x}" for c in mixed)
    return theme["text"]


# ---------------------------------------------------------------- html
HEAD = """<!doctype html><html lang="es"><head><meta charset="utf-8"><title>{title}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
body{{margin:0;font-family:Inter,system-ui,sans-serif}}
.desk{{width:1440px;height:900px;position:relative;overflow:hidden;background-color:#0b0d12;background-image:radial-gradient(circle at 16% 20%,#284766 0,rgba(40,71,102,0) 38%),radial-gradient(circle at 84% 80%,#563663 0,rgba(86,54,99,0) 42%),radial-gradient(circle at 72% 12%,#1d5a55 0,rgba(29,90,85,0) 34%),radial-gradient(circle at 30% 92%,#5a4a2a 0,rgba(90,74,42,0) 30%)}}
.desk.white{{background:#ffffff}}
.win{{position:absolute;border-radius:16px;box-shadow:0 30px 90px rgba(0,0,0,0.5);backdrop-filter:blur(28px) saturate(150%);display:flex;flex-direction:column;overflow:hidden}}
.strip{{height:40px;flex:none;display:flex;align-items:center;gap:8px;padding:0 14px;font-size:12.5px}}
.ws{{padding:5px 12px;border-radius:7px}}
.area{{flex:1;display:grid;gap:8px;padding:10px}}
.pane{{border-radius:11px;display:flex;flex-direction:column;overflow:hidden}}
.ph{{height:30px;flex:none;display:flex;align-items:center;gap:8px;padding:0 12px;font-size:12px}}
.dot{{width:7px;height:7px;border-radius:50%;flex:none}}
.term{{padding:10px 14px;font:400 12.5px/1.62 'JetBrains Mono',monospace;white-space:pre}}
.status{{height:28px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:0 14px;font-size:11.5px}}
.lbl{{font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;margin:0}}
.sw{{width:18px;height:18px;border-radius:5px;display:inline-block;margin-right:5px}}
.note{{position:absolute;font-size:12px;color:#8b919c;line-height:1.5}}
.light{{position:absolute;top:14px;width:12px;height:12px;border-radius:50%}}
</style></head><body><div class="desk{desk}">{body}</div></body></html>"""

FOLDER = '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="{c}" stroke-width="1.4" style="vertical-align:-1px"><path d="M2 4.5h4l1.5 1.5H14v6.5H2z"/></svg>'
BRANCH = '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="{c}" stroke-width="1.4" style="vertical-align:-1px"><circle cx="5" cy="3.5" r="1.5"/><circle cx="5" cy="12.5" r="1.5"/><circle cx="11" cy="6" r="1.5"/><path d="M5 5v6M11 7.5c0 2-2 2.5-6 3.5"/></svg>'
HEX = '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="{c}" stroke-width="1.4" style="vertical-align:-1px"><path d="M8 2l5 3v6l-5 3-5-3V5z"/></svg>'


def rgba(hex_color, alpha):
    r, g, b = rgb(hex_color)
    return f"rgba({r},{g},{b},{alpha})"


def ansi(theme, index):
    return theme["ansi"].split()[index]


def sample_terminal(t):
    a = lambda i: ansi(t, i)  # noqa: E731
    return (
        f'<span style="color:{t["accent"]}">{FOLDER.format(c=t["accent"])} solen/apps/api</span> '
        f'<span style="color:{a(5)}">{BRANCH.format(c=a(5))} main</span> '
        f'<span style="color:{a(3)}">●2</span> <span style="color:{a(2)}">+1</span> '
        f'<span style="color:{t["secondary"]}">{HEX.format(c=t["secondary"])} 22.11</span>\n'
        f'<span style="color:{t["accent"]}">›</span> pnpm test\n'
        f'<span style="color:{a(2)}">✓</span> reminders (23)  <span style="color:{a(2)}">✓</span> calendar (41)  '
        f'<span style="color:{a(1)}">✗</span> sync (1)\n'
        f'<span style="color:{a(3)}">warn</span> 2 tests lentos &gt; 500ms\n'
        f'<span style="color:{a(5)}">const</span> due = event.startsAt.<span style="color:{a(4)}">minus</span>(rule.offset)\n'
        f'<span style="color:{a(6)}">info</span> <span style="color:{t["secondary"]}">compilado en 1.2 s</span>\n'
        f'<span style="color:{t["accent"]}">›</span> git sta<span style="color:{t["ghost"]}">tus</span>'
    )


def swatches(t):
    colors = t["ansi"].split()
    rows = ""
    for start in (0, 8):
        rows += '<div style="margin-top:6px">' + "".join(
            f'<span class="sw" style="background:{c}"></span>' for c in colors[start : start + 8]
        ) + "</div>"
    return rows


def window(t, left, top, width, height, name, *, panel_opacity=PANEL_OPACITY, chrome_opacity=None, body=None,
           strip_extra="", strip_lead=0):
    border = f"rgba({t['border']},0.09)"
    inner = f"rgba({t['border']},0.07)"
    line = f"rgba({t['border']},0.05)"
    chrome = rgba(t["glass"], chrome_opacity) if chrome_opacity else "transparent"
    ws_on = f'background:{rgba(t["accent"], 0.13)};border:1px solid {rgba(t["accent"], 0.5)};color:{t["title"]}'
    content = body if body is not None else sample_terminal(t)
    return f'''<div class="win" style="left:{left}px;top:{top}px;width:{width}px;height:{height}px;background:{rgba(t["glass"], GLASS_OPACITY)};border:1px solid {border};color:{t["text"]}">
{strip_extra}<div class="strip" style="border-bottom:1px solid {line};background:{chrome};padding-left:{14 + strip_lead}px"><span class="ws" style="{ws_on}">solen</span><span class="ws" style="color:{t["secondary"]}">billi</span><span style="flex:1"></span><span style="color:{t["secondary"]};font-size:11.5px">{name}</span></div>
<div class="area"><div class="pane" style="background:{rgba(t["panel"], panel_opacity)};border:1px solid {rgba(t["accent"], 0.5)};box-shadow:0 0 0 3px {rgba(t["accent"], 0.13)}">
<div class="ph" style="border-bottom:1px solid {line}"><span class="dot" style="background:{t["working"]}"></span><b style="font-weight:600;color:{t["title"]}">zsh</b><span style="color:{t["secondary"]}">~/Projects/solen</span></div>
<div class="term">{content}</div></div></div>
<div class="status" style="border-top:1px solid {line};color:{t["secondary"]};background:{chrome}"><span><span class="dot" style="display:inline-block;background:{t["working"]}"></span> 1 trabajando · <span class="dot" style="display:inline-block;background:{t["waiting"]}"></span> 1 te espera · <span class="dot" style="display:inline-block;background:{t["failed"]}"></span> 1 error · <span class="dot" style="display:inline-block;border:1.5px solid {t["stopped"]}"></span> 1 detenido</span><span>dwindle</span></div></div>'''


def page(title, body, desk=""):
    return HEAD.format(title=title, body=body, desk=desk)


def mockup_themes():
    body = ""
    for i, (name, t) in enumerate(THEMES.items()):
        left = 40 + (i % 2) * 690
        top = 30 + (i // 2) * 430
        body += window(t, left, top, 670, 410, name)
        body += f'<div style="position:absolute;left:{left + 400}px;top:{top + 250}px">{swatches(t)}</div>'
    return page("Temas de F5", body)


def traffic_lights(left, visible, hover=False):
    if not visible:
        return ""
    colors = ["#ff5f57", "#febc2e", "#28c840"]
    zoom_note = ""
    return "".join(
        f'<span class="light" style="left:{left + 14 + 20 * i}px;background:{c};{"opacity:1" if hover or visible else ""}"></span>'
        for i, c in enumerate(colors)
    ) + zoom_note


def mockup_buttons():
    t = THEMES["Obsidiana"]
    body = ""
    states = [
        ("Ocultos (por defecto)", False, "La franja arrastra la ventana; sin semáforos."),
        ("Al pasar el cursor", True, "Aparecen con el cursor sobre la franja (fundido de 150 ms; sin animación con Reducir movimiento)."),
        ("Visibles", True, "Siempre a la vista; las pastillas de workspace se corren 72 px."),
    ]
    for i, (label, visible, note) in enumerate(states):
        top = 40 + i * 280
        body += f'<p class="lbl" style="position:absolute;left:56px;top:{top - 22}px;color:#8b919c">{label}</p>'
        lights = traffic_lights(0, visible)
        body += window(t, 56, top, 900, 240, "", body="% ", strip_extra=f'<div style="position:relative">{lights}</div>',
                       strip_lead=72 if visible else 0)
        body += f'<div class="note" style="left:990px;top:{top + 10}px;width:380px">{note}</div>'
    return page("Botones de ventana", body)


def mockup_prompt():
    t = THEMES["Obsidiana"]
    a = lambda i: ansi(t, i)  # noqa: E731
    clean = (
        f'<span style="color:{t["accent"]}">{FOLDER.format(c=t["accent"])} solen/apps/api</span> '
        f'<span style="color:{a(5)}">{BRANCH.format(c=a(5))} feat/reminders</span> <span style="color:{a(3)}">●2</span> '
        f'<span style="color:{a(2)}">+1</span> <span style="color:{t["secondary"]}">{HEX.format(c=t["secondary"])} 22.11</span>\n'
        f'<span style="color:{t["accent"]}">›</span> pnpm dev\n\n'
        f'<span style="color:{t["accent"]}">{FOLDER.format(c=t["accent"])} rizaria/web</span> '
        f'<span style="color:{a(5)}">{BRANCH.format(c=a(5))} main</span> <span style="color:{t["secondary"]}">4.2s</span> '
        f'<span style="color:{t["waiting"]}">● claude te espera</span>\n'
        f'<span style="color:{t["failed"]}">›</span> exit 1'
    )
    body = window(t, 56, 60, 640, 380, "Línea limpia", body=clean)
    symbol_only = (
        f'<span style="color:{t["accent"]}">›</span> pnpm dev\n<span style="color:{t["secondary"]}">ready on :3000</span>\n'
        f'<span style="color:{t["accent"]}">›</span> '
    )
    header_ctx = (
        f'<span style="color:{t["secondary"]}">{FOLDER.format(c=t["secondary"])} solen/apps/api · '
        f'{BRANCH.format(c=t["secondary"])} feat/reminders <span style="color:{a(3)}">●2</span> '
        f'<span style="color:{a(2)}">+1</span> · {HEX.format(c=t["secondary"])} 22.11</span>'
    )
    solo = window(t, 744, 60, 640, 380, "Solo símbolo", body=symbol_only)
    solo = solo.replace(
        f'<span style="color:{t["secondary"]}">~/Projects/solen</span>', header_ctx, 1)
    body += solo
    body += ('<div class="note" style="left:56px;top:470px;width:640px">Plantilla «Línea limpia» con iconos de trazo '
             'fino (fuente propia de Smalti): contexto arriba, input abajo. El segundo bloque, después de un error '
             'con el agente esperando: el símbolo en rojo y «claude te espera» en ámbar.</div>')
    body += ('<div class="note" style="left:744px;top:470px;width:640px">Plantilla «Solo símbolo»: el contexto pasa '
             'a la cabecera del panel, en texto secundario, tras el título. Si no cabe, se recorta por la izquierda '
             'del directorio.</div>')
    return page("Prompt en el panel", body)


def mockup_legibility():
    t = THEMES["Obsidiana"]
    needed = protected_panel_opacity(t)
    body = window(t, 40, 80, 660, 420, "Proteger legibilidad: no")
    worst = over(rgb(t["glass"]), GLASS_OPACITY, (255, 255, 255))
    ground = over(rgb(t["panel"]), needed, worst)
    ghost = protected_ghost(t, ground)
    body += window(dict(t, ghost=ghost), 740, 80, 660, 420, "Proteger legibilidad: sí", panel_opacity=needed,
                   chrome_opacity=0.89)
    body += (f'<div class="note" style="left:40px;top:530px;width:1360px;color:#2a2e36">Peor caso: escritorio '
             f'blanco detrás del vidrio al 62 %. A la derecha, los paneles suben de {PANEL_OPACITY:.0%} a '
             f'{needed:.0%} y la franja y la barra de estado reciben un fondo al 89 %; los márgenes y los huecos '
             f'de 8 px conservan el vidrio. El fantasma se aclara hasta 4.5:1.</div>')
    return page("Proteger legibilidad", body, desk=" white")


def main():
    check_themes()
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, html in [
        ("mockup-themes", mockup_themes()),
        ("mockup-buttons", mockup_buttons()),
        ("mockup-prompt", mockup_prompt()),
        ("mockup-legibility", mockup_legibility()),
    ]:
        (out / f"{name}.html").write_text(html, encoding="utf-8")
    for name, theme in THEMES.items():
        print(f"{name}: panel opacity with protection {protected_panel_opacity(theme):.2f}")


if __name__ == "__main__":
    main()

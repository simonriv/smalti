"""F5.6 before/after sheet of the prompt icons (spec F5.6, C11).

Usage: python3 icons-sheet.py <before.ttf> <after.ttf> <out.html>   (then render it at 1440x900 with headless Chrome).
Each of the four themes shows the same prompt line with the old and the new SmaltiSymbols next to JetBrains Mono, and
capitals (`HM`) to compare their height. It is a generated sheet, not a capture of the app.
"""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
F5 = ROOT / "docs/specs/F5-assets/generate-mockups.py"
spec = importlib.util.spec_from_file_location("f5_mockups", F5)
f5 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f5)

FONT_SIZE = 21  # big enough to judge the height; the ratio to the text is what matters
HOME, BRANCH, CLOCK = "", "", ""


def prompt(theme, family):
    a = lambda i: f5.ansi(theme, i)  # noqa: E731
    icon = lambda glyph, color: f'<span style="font-family:{family};color:{color}">{glyph}</span>'  # noqa: E731
    return (
        f'{icon(HOME, theme["accent"])} <span style="color:{theme["accent"]}">~/Projects/solen</span>  '
        f'{icon(BRANCH, a(5))} <span style="color:{a(5)}">main</span>  '
        f'{icon(CLOCK, theme["secondary"])} <span style="color:{theme["secondary"]}">22:11</span>'
    )


def row(theme, family, label):
    return (
        f'<div class="row"><span class="tag" style="color:{theme["secondary"]}">{label}</span>'
        f'<div class="line" style="color:{theme["text"]}">{prompt(theme, family)} <span>HM</span></div></div>'
    )


def page(before, after):
    cards = ""
    for name, theme in f5.THEMES.items():
        background = f5.rgba(theme["panel"], 0.92) if theme["dark"] else theme["panel"]
        cards += (
            f'<div class="card" style="background:{background};border:1px solid rgba({theme["border"]},0.12)">'
            f'<p class="name" style="color:{theme["title"]}">{name}</p>'
            f'{row(theme, "Before", "antes")}{row(theme, "After", "después")}</div>'
        )
    return f"""<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Iconos del prompt</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono&display=swap">
<style>
@font-face{{font-family:Before;src:url("{before.as_uri()}")}}
@font-face{{font-family:After;src:url("{after.as_uri()}")}}
body{{margin:0;font-family:Inter,sans-serif;background:#0b0d12}}
.desk{{width:1440px;height:900px;display:grid;grid-template-columns:1fr 1fr;gap:24px;padding:40px;box-sizing:border-box;
background-image:radial-gradient(circle at 16% 20%,#284766 0,rgba(40,71,102,0) 38%),radial-gradient(circle at 84% 80%,#563663 0,rgba(86,54,99,0) 42%)}}
.card{{border-radius:14px;padding:22px 26px}}
.name{{font:600 15px Inter,sans-serif;margin:0 0 14px}}
.row{{display:flex;align-items:center;gap:14px;margin:10px 0}}
.tag{{width:64px;font-size:12px;text-transform:uppercase;letter-spacing:.06em}}
.line{{position:relative;font:400 {FONT_SIZE}px/1.62 'JetBrains Mono',monospace;white-space:pre}}
</style></head><body><div class="desk">{cards}</div></body></html>"""


def main():
    before, after, out = (pathlib.Path(arg).resolve() for arg in sys.argv[1:4])
    out.write_text(page(before, after), encoding="utf-8")


if __name__ == "__main__":
    main()

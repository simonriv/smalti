"""F5.6 mockup: the command line highlighted while typing, in the four themes (spec F5.6, "Colores").

Usage: python3 generate-mockups.py <out-dir>   (then render the .html at 1440x900 with headless Chrome).
Reuses the F5 theme tables and window frame, so the colors are the ones the themes already protect at 4.5:1.
"""

import importlib.util
import pathlib
import sys

F5 = pathlib.Path(__file__).resolve().parent.parent / "F5-assets" / "generate-mockups.py"
spec = importlib.util.spec_from_file_location("f5_mockups", F5)
f5 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f5)


def roles(t):
    """The approved role → color assignment (spec F5.6)."""
    a = lambda i: f5.ansi(t, i)  # noqa: E731
    return dict(
        command=a(4), unknown=t["failed"], subcommand=a(6), option=a(5), string=a(2), variable=a(5),
        operator=t["secondary"], plain=t["text"],
    )


def span(text, color, underline=False):
    deco = ";text-decoration:underline;text-underline-offset:2px" if underline else ""
    return f'<span style="color:{color}{deco}">{text}</span>'


def lines(t):
    r = roles(t)
    p = span("›", t["accent"]) + " "
    plain = lambda s: span(s, r["plain"])  # noqa: E731
    path = lambda s: span(s, r["plain"], underline=True)  # noqa: E731
    return "\n".join([
        p + span("git", r["command"]) + " " + span("checkout", r["subcommand"]) + " " + span("-b", r["option"]) + " "
        + span('"feat x"', r["string"]),
        p + span("ls", r["command"]) + " " + span("-la", r["option"]) + " " + path("src/") + " "
        + span("|", r["operator"]) + " " + span("grep", r["command"]) + " " + span("-v", r["option"]) + " "
        + plain("foo") + " " + span("&gt;", r["operator"]) + " " + plain("out.txt"),
        p + span("echo", r["command"]) + " " + span("$HOME", r["variable"]) + " " + span("&amp;&amp;", r["operator"])
        + " " + span("cd", r["command"]) + " " + path("~/Projects/solen"),
        p + span("gti", r["unknown"]) + " " + plain("status") + "   "
        + span("# desconocido: rojo al salir de la palabra", t["secondary"]),
        p + span("gti", r["plain"]) + "   " + span("# mientras el cursor sigue en la palabra, sin rojo", t["secondary"]),
        p + span("git", r["command"]) + " " + span("sta", r["subcommand"]) + span("tus", t["ghost"]) + "   "
        + span("# con el fantasma de F4 detrás", t["secondary"]),
    ])


def legend(t):
    r = roles(t)
    items = [("comando", r["command"]), ("desconocido", r["unknown"]), ("subcomando", r["subcommand"]),
             ("opción · variable", r["option"]), ("cadena", r["string"]), ("operador", r["operator"])]
    return "  ".join(span("■", c) + " " + span(n, t["secondary"]) for n, c in items) + "  " + span(
        "ruta que existe", t["text"], underline=True)


def mockup_highlight():
    body = ""
    for i, (name, t) in enumerate(f5.THEMES.items()):
        left = 40 + (i % 2) * 690
        top = 30 + (i // 2) * 430
        content = lines(t) + "\n\n" + f'<span style="font:400 11px Inter,sans-serif">{legend(t)}</span>'
        body += f5.window(t, left, top, 670, 410, name, body=content)
    return f5.page("Resaltado del input", body)


def main():
    f5.check_themes()
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    (out / "mockup-highlight.html").write_text(mockup_highlight(), encoding="utf-8")


if __name__ == "__main__":
    main()

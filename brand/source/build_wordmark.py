#!/usr/bin/env python3
"""Builds the "smalti" wordmark as outlines from Inter (SIL OFL 1.1) and the lockups with the symbol.

Usage: build_wordmark.py <inter-variable.ttf> <out-dir>
The i's round dot is replaced by a square tessera as wide as the stem (a slanted one read as an accent: "smaltí").
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

sys.path.insert(0, str(Path(__file__).parent))
from build_symbol import ACCENT, panes  # noqa: E402

WORD = "smalti"
WEIGHT = 600
TRACKING = -0.01  # em; slightly tight, like the UI labels


def outline_word(font_path: str) -> tuple[str, float, float, tuple[float, float, float, float]]:
    """Path data for WORD at 1 unit = 1 font unit (y up flipped to SVG y down), its width, the x-height,
    and the bounds of the i's dot so it can be replaced."""
    font = instantiateVariableFont(TTFont(font_path), {"wght": WEIGHT, "opsz": 32})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    x_height = font["OS/2"].sxHeight
    pen = SVGPathPen(glyphs)
    x = 0.0
    dot_box = None
    for char in WORD:
        name = cmap[ord(char)]
        glyph = glyphs[name]
        if char == "i":
            name = cmap[ord("ı")]  # dotless i; the dot is drawn as a tessera
            bounds = BoundsPen(glyphs)
            glyphs[cmap[ord("i")]].draw(bounds)
            xmin, ymin, xmax, ymax = bounds.bounds
            dot_box = (x + xmin, x_height, x + xmax, ymax)
        glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        x += glyph.width + TRACKING * upm
    return pen.getCommands(), x - TRACKING * upm, x_height, dot_box


def tessera_dot(box: tuple[float, float, float, float], x_height: float) -> str:
    """The i's dot as a square tessera: stem width, centred where Inter's round dot sits."""
    x0, _, x1, top = box
    size = x1 - x0
    bottom = top - size
    return f"M{x0:.1f} {-top:.1f} H{x1:.1f} V{-bottom:.1f} H{x0:.1f} Z"


def main() -> None:
    font_path, out = sys.argv[1], Path(sys.argv[2])
    word, width, x_height, dot_box = outline_word(font_path)
    dot = tessera_dot(dot_box, x_height)
    cap_top = dot_box[3]
    pad = 40
    # Wordmark alone, font units, baseline at y=0 → translate so the tallest point (l, dot) sits at pad.
    height = cap_top + 560  # ascender + descender room
    def wordmark(fill: str) -> str:
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-pad} {-cap_top - pad} {width + 2 * pad:.0f} '
                f'{cap_top + 2 * pad + 40:.0f}">\n  <title>Smalti</title>\n  <g fill="{fill}">\n'
                f'    <path d="{word}"/>\n    <path d="{dot}"/>\n  </g>\n</svg>\n')
    for name, fill in [("smalti-wordmark.svg", "#000000"), ("smalti-wordmark-white.svg", "#ffffff")]:
        (out / name).write_text(wordmark(fill))
        print("wrote", out / name)

    # Lockups: symbol height = 1.55 × x-height … aligned so the symbol spans from baseline to the l's top.
    symbol_size = cap_top  # symbol square from baseline to ascender
    scale = symbol_size / 208  # symbol artwork occupies 208 of its 256 box
    gap = symbol_size * 0.42
    def placed_symbol(fill: str, x: float, y_top: float) -> str:
        paths = "".join(f'<path d="{d}"/>' for d in panes(gap=20, radius=18))
        return (f'<g transform="translate({x:.1f} {y_top:.1f}) scale({scale:.4f}) translate(-24 -24)" fill="{fill}">'
                f"{paths}</g>")
    for name, sym_fill, word_fill in [
        ("smalti-horizontal.svg", "#000000", "#000000"),
        ("smalti-horizontal-white.svg", "#ffffff", "#ffffff"),
        ("smalti-horizontal-color.svg", ACCENT, "#0d0f15"),
        ("smalti-horizontal-color-on-dark.svg", ACCENT, "#e6e9ef"),
    ]:
        total = symbol_size + gap + width
        bg = '<rect x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" fill="#0d0f15"/>'.format(
            x=-cap_top * 0.5, y=-cap_top * 1.5, w=total + cap_top, h=cap_top * 2) if "on-dark" in name else ""
        m = cap_top * 0.5
        content = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-m:.0f} {-cap_top - m:.0f} {total + 2 * m:.0f} '
                   f'{cap_top + 2 * m:.0f}">\n  <title>Smalti</title>\n  {bg}\n  {placed_symbol(sym_fill, 0, -cap_top)}\n'
                   f'  <g fill="{word_fill}" transform="translate({symbol_size + gap:.1f} 0)">'
                   f'<path d="{word}"/><path d="{dot}"/></g>\n</svg>\n')
        (out / name).write_text(content)
        print("wrote", out / name)

    # Stacked: symbol centred above the wordmark.
    stack_symbol = cap_top * 1.7
    s_scale = stack_symbol / 208
    sym_x = (width - stack_symbol) / 2
    sym_top = -cap_top - stack_symbol - cap_top * 0.6
    paths = "".join(f'<path d="{d}"/>' for d in panes(gap=20, radius=18))
    for name, sym_fill, word_fill in [("smalti-stacked.svg", "#000000", "#000000"),
                                      ("smalti-stacked-color.svg", ACCENT, "#0d0f15")]:
        content = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-40 {sym_top - 40:.0f} {width + 80:.0f} '
                   f'{-sym_top + 80:.0f}">\n  <title>Smalti</title>\n'
                   f'  <g transform="translate({sym_x:.1f} {sym_top:.1f}) scale({s_scale:.4f}) translate(-24 -24)" '
                   f'fill="{sym_fill}">{paths}</g>\n'
                   f'  <g fill="{word_fill}"><path d="{word}"/><path d="{dot}"/></g>\n</svg>\n')
        (out / name).write_text(content)
        print("wrote", out / name)


if __name__ == "__main__":
    main()

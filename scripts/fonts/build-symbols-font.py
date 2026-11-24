"""Builds SmaltiSymbols.ttf (spec F5): one monospaced glyph per icon, U+E900 onward in icons.txt order.

Usage: python3 build-symbols-font.py <icons.json> <out.ttf>   (icons.json from outline-icons.swift)
The 16-unit SVG grid maps to a square of ADVANCE units centered on the text's middle; SVG's y grows down.
"""

import json
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

UNITS_PER_EM = 1000
ADVANCE = 600  # JetBrains Mono's cell at 1000 units per em
GRID = 16
SCALE = ADVANCE / GRID
CENTER_Y = 300  # middle of the lowercase body
FIRST_CODEPOINT = 0xE900
# A fixed creation date, so a rebuild is byte for byte the same (block 3 review, M11): 2026-11-23, in seconds since
# 1904-01-01 as the `head` table counts. Built with fontTools 4.60.2.
FIXED_TIMESTAMP = 3_846_960_000


def to_font(point):
    x, y = point
    return (round(x * SCALE), round(CENTER_Y + (GRID / 2 - y) * SCALE))


def glyph(contours):
    pen = TTGlyphPen(None)
    curves = Cu2QuPen(pen, max_err=1.0, reverse_direction=True)
    for contour in contours:
        open_contour = False
        for step in contour:
            points = [to_font(p) for p in step["p"]]
            if step["op"] == "move":
                curves.moveTo(points[0])
                open_contour = True
            elif step["op"] == "line":
                curves.lineTo(points[0])
            elif step["op"] == "quad":
                curves.qCurveTo(*points)
            elif step["op"] == "cubic":
                curves.curveTo(*points)
            else:
                curves.closePath()
                open_contour = False
        if open_contour:
            curves.closePath()
    return pen.glyph()


def build(icons, out_path):
    names = [icon["name"] for icon in icons]
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder([".notdef"] + names)
    builder.setupCharacterMap({FIRST_CODEPOINT + index: name for index, name in enumerate(names)})
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    glyphs.update({icon["name"]: glyph(icon["contours"]) for icon in icons})
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (ADVANCE, 0) for name in [".notdef"] + names})
    builder.setupHorizontalHeader(ascent=1020, descent=-300)
    builder.setupNameTable(
        {
            "familyName": "SmaltiSymbols",
            "styleName": "Regular",
            "fullName": "SmaltiSymbols Regular",
            "psName": "SmaltiSymbols-Regular",
        }
    )
    builder.setupOS2(sTypoAscender=1020, sTypoDescender=-300, usWinAscent=1020, usWinDescent=300)
    builder.setupPost(isFixedPitch=1)
    builder.updateHead(created=FIXED_TIMESTAMP, modified=FIXED_TIMESTAMP)
    builder.save(str(out_path))


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        build(json.load(source), sys.argv[2])

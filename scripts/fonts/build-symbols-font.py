"""Builds SmaltiSymbols.ttf (spec F5): one monospaced glyph per icon, U+E900 onward in icons.txt order.

Usage: python3 build-symbols-font.py <icons.json> <out.ttf>   (icons.json from outline-icons.swift)
Each icon is scaled to TARGET_HEIGHT on the baseline (F5.6); SVG's y grows down.
"""

import json
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

UNITS_PER_EM = 1000
ADVANCE = 600  # JetBrains Mono's cell at 1000 units per em
FIRST_CODEPOINT = 0xE900
# F5.6: every icon is scaled on its own to the height of JetBrains Mono's capitals (730) or a little more, sitting on
# the baseline like a capital. Ghostty draws a private-use glyph over two cells when a space follows it, so the
# drawing may reach past the 600-unit advance, up to MAX_WIDTH (two cells with margin).
TARGET_HEIGHT = 760
MAX_WIDTH = 900
LEFT_BEARING = 40
FIT_PASSES = 3
# A fixed creation date, so a rebuild is byte for byte the same (block 3 review, M11): 2026-11-23, in seconds since
# 1904-01-01 as the `head` table counts. Built with fontTools 4.60.2.
FIXED_TIMESTAMP = 3_846_960_000


def glyph(contours, transform=lambda point: (round(point[0]), round(-point[1]))):
    pen = TTGlyphPen(None)
    curves = Cu2QuPen(pen, max_err=1.0, reverse_direction=True)
    for contour in contours:
        open_contour = False
        for step in contour:
            points = [transform(p) for p in step["p"]]
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


def bounds(contours):
    """The outline's exact box in SVG units (y down), curves included."""
    pen = BoundsPen(None)
    for contour in contours:
        open_contour = False
        for step in contour:
            if step["op"] == "move":
                pen.moveTo(step["p"][0])
                open_contour = True
            elif step["op"] == "line":
                pen.lineTo(step["p"][0])
            elif step["op"] == "quad":
                pen.qCurveTo(*step["p"])
            elif step["op"] == "cubic":
                pen.curveTo(*step["p"])
            else:
                pen.closePath()
                open_contour = False
        if open_contour:
            pen.closePath()
    return pen.bounds


def fitted_glyph(contours):
    """TARGET_HEIGHT tall on the baseline, from LEFT_BEARING, unless MAX_WIDTH limits the scale first. The font's
    box counts the quadratic control points, which can stick out of the curve, so the fit is corrected on the built
    glyph a few times."""
    x_min, y_min, x_max, y_max = bounds(contours)
    factor = min(TARGET_HEIGHT / (y_max - y_min), MAX_WIDTH / (x_max - x_min))
    left, bottom = LEFT_BEARING, 0.0
    for _ in range(FIT_PASSES):
        built = glyph(
            contours,
            lambda p: (round(left + (p[0] - x_min) * factor), round(bottom + (y_max - p[1]) * factor)))
        built.recalcBounds(None)
        width, height = built.xMax - built.xMin, built.yMax - built.yMin
        correction = min(TARGET_HEIGHT / height, MAX_WIDTH / width)
        factor *= correction
        left = LEFT_BEARING + (left - built.xMin) * correction
        bottom = (bottom - built.yMin) * correction
    return glyph(
        contours, lambda p: (round(left + (p[0] - x_min) * factor), round(bottom + (y_max - p[1]) * factor)))


def build(icons, out_path):
    names = [icon["name"] for icon in icons]
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder([".notdef"] + names)
    builder.setupCharacterMap({FIRST_CODEPOINT + index: name for index, name in enumerate(names)})
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    glyphs.update({icon["name"]: fitted_glyph(icon["contours"]) for icon in icons})
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

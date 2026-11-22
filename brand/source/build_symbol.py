#!/usr/bin/env python3
"""Builds the Smalti symbol: the three Dwindle panes (1.35 : 1) split by a 15° glass cut.

Usage: build_symbol.py <out-dir>. Writes the master, small-size, reversed and colour symbol SVGs.
Geometry lives here so every variant comes from the same construction.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

ACCENT = "#7aa2f7"
BACKGROUND = "#0d0f15"
CUT = math.radians(15)


def panes(gap: float, radius: float, box=(24.0, 24.0, 232.0, 232.0)) -> list[str]:
    """Path data for the three panes inside `box`; outer corners rounded, cut edges sharp like split glass."""
    x0, top, x1, bot = box
    width = x1 - x0
    t = math.tan(CUT)
    centre_x = x0 + (width - gap) * 1.35 / 2.35 + gap / 2
    half = gap / 2 / math.cos(CUT)
    mid_y = (top + bot) / 2
    xl = lambda y: centre_x - half + (y - mid_y) * t
    xr = lambda y: centre_x + half + (y - mid_y) * t
    r, g = radius, gap / 2
    f = lambda v: f"{v:.2f}".rstrip("0").rstrip(".")
    left = (f"M{f(x0 + r)} {f(top)} H{f(xl(top))} L{f(xl(bot))} {f(bot)} H{f(x0 + r)} "
            f"A{f(r)} {f(r)} 0 0 1 {f(x0)} {f(bot - r)} V{f(top + r)} A{f(r)} {f(r)} 0 0 1 {f(x0 + r)} {f(top)} Z")
    upper = (f"M{f(xr(top))} {f(top)} H{f(x1 - r)} A{f(r)} {f(r)} 0 0 1 {f(x1)} {f(top + r)} "
             f"V{f(mid_y - g)} H{f(xr(mid_y - g))} Z")
    lower = (f"M{f(xr(mid_y + g))} {f(mid_y + g)} H{f(x1)} V{f(bot - r)} "
             f"A{f(r)} {f(r)} 0 0 1 {f(x1 - r)} {f(bot)} H{f(xr(bot))} Z")
    return [left, upper, lower]


def svg(paths: list[str], fill: str, title: str, background: str | None = None) -> str:
    bg = f'  <rect width="256" height="256" rx="56" fill="{background}"/>\n' if background else ""
    body = "\n".join(f'  <path d="{d}"/>' for d in paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">\n  <title>{title}</title>\n'
            f'{bg}  <g fill="{fill}">\n{body}\n  </g>\n</svg>\n')


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    master = panes(gap=20, radius=18)
    files = {
        "smalti-symbol.svg": svg(master, "#000000", "Smalti"),
        "smalti-symbol-white.svg": svg(panes(gap=22, radius=18), "#ffffff", "Smalti"),  # reversed: optically thinner
        "smalti-symbol-color.svg": svg(master, ACCENT, "Smalti"),
        "smalti-symbol-on-dark.svg": svg(panes(gap=22, radius=16, box=(56, 56, 200, 200)), ACCENT, "Smalti", BACKGROUND),
        "smalti-symbol-small.svg": svg(panes(gap=30, radius=12), "#000000", "Smalti"),  # 16–24 px cut: wider joints
    }
    for name, content in files.items():
        (out / name).write_text(content)
        print("wrote", out / name)


if __name__ == "__main__":
    main()

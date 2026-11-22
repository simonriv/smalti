#!/usr/bin/env python3
"""Builds the macOS app-icon layers for Icon Composer (1024 × 1024): background, tesserae, highlight.

Usage: build_macos_icon.py <out-dir>
Icon Composer applies the squircle mask and the Liquid Glass material; these layers only carry the artwork.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_symbol import ACCENT, BACKGROUND, CUT, panes  # noqa: E402

CANVAS = 1024
BOX = (232.0, 232.0, 792.0, 792.0)        # 560 px artwork: the symbol's 208/256 ratio scaled into the icon grid
SCALE = (BOX[2] - BOX[0]) / 208
GAP, RADIUS = 20 * SCALE, 18 * SCALE
HIGHLIGHT = 0.16                           # top band of each tessera, as a share of the pane height


def highlight_bands() -> list[str]:
    """Top band of each pane, with the same cut and corners, for a glass edge highlight."""
    x0, top, x1, bot = BOX
    t = math.tan(CUT)
    centre_x = x0 + (x1 - x0 - GAP) * 1.35 / 2.35 + GAP / 2
    half = GAP / 2 / math.cos(CUT)
    mid = (top + bot) / 2
    xl = lambda y: centre_x - half + (y - mid) * t
    xr = lambda y: centre_x + half + (y - mid) * t
    r, g = RADIUS, GAP / 2
    tall = (bot - top) * HIGHLIGHT
    short = (mid - g - top) * HIGHLIGHT * 1.6
    f = lambda v: f"{v:.1f}"
    left = (f"M{f(x0 + r)} {f(top)} H{f(xl(top))} L{f(xl(top + tall))} {f(top + tall)} H{f(x0)} V{f(top + r)} "
            f"A{f(r)} {f(r)} 0 0 1 {f(x0 + r)} {f(top)} Z")
    upper = (f"M{f(xr(top))} {f(top)} H{f(x1 - r)} A{f(r)} {f(r)} 0 0 1 {f(x1)} {f(top + r)} V{f(top + short)} "
             f"H{f(xr(top + short))} Z")
    y = mid + g
    lower = f"M{f(xr(y))} {f(y)} H{f(x1)} V{f(y + short)} H{f(xr(y + short))} Z"
    return [left, upper, lower]


def layer(body: str, title: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" width="{CANVAS}" '
            f'height="{CANVAS}">\n  <title>{title}</title>\n{body}\n</svg>\n')


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    tiles = "\n".join(f'    <path d="{d}"/>' for d in panes(gap=GAP, radius=RADIUS, box=BOX))
    bands = "\n".join(f'    <path d="{d}"/>' for d in highlight_bands())
    files = {
        "1-fondo.svg": layer(f'  <rect width="{CANVAS}" height="{CANVAS}" fill="{BACKGROUND}"/>', "Smalti icon · fondo"),
        "2-teselas.svg": layer(f'  <g fill="{ACCENT}">\n{tiles}\n  </g>', "Smalti icon · teselas"),
        "3-brillo.svg": layer(f'  <g fill="#ffffff">\n{bands}\n  </g>', "Smalti icon · brillo"),
        # Flattened preview of the three layers (highlight at 35 %), with a squircle-like mask, for checking only.
        "preview-composed.svg": layer(
            f'  <defs><clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath></defs>\n'
            f'  <g clip-path="url(#squircle)">\n    <rect width="{CANVAS}" height="{CANVAS}" fill="{BACKGROUND}"/>\n'
            f'    <g fill="{ACCENT}">\n{tiles}\n    </g>\n    <g fill="#ffffff" opacity="0.35">\n{bands}\n    </g>\n  </g>',
            "Smalti icon · preview"),
    }
    for name, content in files.items():
        (out / name).write_text(content)
        print("wrote", out / name)


if __name__ == "__main__":
    main()

"""F6: a board beside the app's capture, both scaled to the same height (side-by-side check of each UI change).

Usage: python3 compose-boards.py <board.png> <app.png> <out.png>
board.png is the .dc.html board rendered with headless Chrome (1440x900, --force-device-scale-factor=2); app.png is a
DesignCaptureTests capture.
"""

import sys

from PIL import Image

HEIGHT = 900
GAP = 24
BACKGROUND = (11, 13, 18)


def scaled(path):
    image = Image.open(path).convert("RGB")
    return image.resize((round(image.width * HEIGHT / image.height), HEIGHT))


def main(board_path, app_path, out_path):
    board, app = scaled(board_path), scaled(app_path)
    canvas = Image.new("RGB", (board.width + app.width + GAP * 3, HEIGHT + GAP * 2), BACKGROUND)
    canvas.paste(board, (GAP, GAP))
    canvas.paste(app, (board.width + GAP * 2, GAP))
    canvas.save(out_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])

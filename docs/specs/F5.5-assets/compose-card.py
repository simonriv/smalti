"""C4 of F5.5: the board's preview card beside the app's, and one over the other at 50 %.

Usage: python3 compose-card.py <board.png> <app-card.png> <out.png>
board.png is Main.dc.html rendered at 2x (headless Chrome, 1440x900, --force-device-scale-factor=2); app-card.png is
PreviewTests/testCaptureCard's capture (2x). Both are cut to the card's own box, so they line up at the top-left.
"""

import sys

from PIL import Image

BOARD_CARD = (1271, 745, 1271 + 420, 745 + 318)  # left, top, right, bottom of the card on the 2x board


def main(board_path, app_path, out_path):
    board = Image.open(board_path).convert("RGB").crop(BOARD_CARD)
    app = Image.open(app_path).convert("RGB")
    width = max(board.width, app.width)
    height = max(board.height, app.height)
    canvas = Image.new("RGB", (width * 3 + 80, height + 40), (11, 13, 18))
    canvas.paste(board, (20, 20))
    canvas.paste(app, (width + 40, 20))
    overlay = Image.blend(board.resize((width, height)), app.resize((width, height)), 0.5)
    canvas.paste(overlay, (width * 2 + 60, 20))
    canvas.save(out_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])

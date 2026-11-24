"""Tests for build-symbols-font.py: run with `cd scripts/fonts && python3 -m unittest test_build_symbols_font`."""

import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest

from fontTools.ttLib import TTFont

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("build", HERE / "build-symbols-font.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
NAMES = (HERE / "icons.txt").read_text().split()


class BuildSymbolsFontTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = pathlib.Path(tempfile.mkdtemp())
        outlines = subprocess.run(
            ["swift", str(HERE / "outline-icons.swift"), str(HERE / "icons"), str(HERE / "icons.txt")],
            check=True, capture_output=True, text=True).stdout
        cls.json = cls.work / "icons.json"
        cls.json.write_text(outlines)
        cls.font_path = cls.work / "SmaltiSymbols.ttf"
        build.build(json.loads(outlines), cls.font_path)
        cls.font = TTFont(cls.font_path)

    def test_every_icon_has_codepoint_in_range(self):
        cmap = self.font.getBestCmap()
        for index, name in enumerate(NAMES):
            self.assertEqual(cmap.get(0xE900 + index), name)
        self.assertLessEqual(0xE900 + len(NAMES) - 1, 0xE91F)

    def test_advance_matches_monospace_cell(self):
        metrics = self.font["hmtx"].metrics
        for name in NAMES:
            self.assertEqual(metrics[name][0], build.ADVANCE)
        self.assertEqual(build.ADVANCE, 600)

    def test_font_names_family_SmaltiSymbols(self):
        self.assertEqual(self.font["name"].getDebugName(1), "SmaltiSymbols")

    def test_every_glyph_has_ink(self):
        glyf = self.font["glyf"]
        for name in NAMES:
            coordinates, _, _ = glyf[name].getCoordinates(glyf)
            self.assertGreater(len(coordinates), 8, name)

    def test_glyphs_stay_inside_the_cell(self):
        glyf = self.font["glyf"]
        for name in NAMES:
            glyph = glyf[name]
            glyph.recalcBounds(glyf)
            self.assertGreaterEqual(glyph.xMin, 0, name)
            self.assertLessEqual(glyph.xMax, build.ADVANCE, name)


if __name__ == "__main__":
    unittest.main()

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

    def test_font_has_a_postscript_and_full_name(self):
        # T19: without them macOS generates a PostScript name per registration and AppKit's text views cannot use the
        # font in attributed strings (the studio's previews drew missing-glyph boxes).
        names = self.font["name"]
        self.assertEqual(names.getDebugName(6), "SmaltiSymbols-Regular")
        self.assertEqual(names.getDebugName(4), "SmaltiSymbols Regular")

    def test_every_glyph_has_ink(self):
        glyf = self.font["glyf"]
        for name in NAMES:
            coordinates, _, _ = glyf[name].getCoordinates(glyf)
            self.assertGreater(len(coordinates), 8, name)

    def test_building_twice_gives_the_same_bytes(self):
        """Block 3 review (M11): no build time inside the font, so a rebuild is byte for byte the same."""
        again = self.work / "again.ttf"
        import fontTools.fontBuilder as font_builder
        from unittest import mock

        later = font_builder.timestampNow() + 86_400
        with mock.patch.object(font_builder, "timestampNow", return_value=later):
            build.build(json.loads(self.json.read_text()), again)
        self.assertEqual(again.read_bytes(), self.font_path.read_bytes())

    def _bounds(self, name):
        glyf = self.font["glyf"]
        glyph = glyf[name]
        glyph.recalcBounds(glyf)
        return glyph.xMin, glyph.yMin, glyph.xMax, glyph.yMax

    def test_every_glyph_height_is_target(self):
        """F5.6: as tall as JetBrains Mono's capitals or a little more, unless the width limit stops it first."""
        for name in NAMES:
            x_min, y_min, x_max, y_max = self._bounds(name)
            if x_max - x_min < build.MAX_WIDTH - 2:
                self.assertAlmostEqual(y_max - y_min, build.TARGET_HEIGHT, delta=2, msg=name)
        self.assertTrue(730 <= build.TARGET_HEIGHT <= 800)

    def test_wide_glyph_limited_by_max_width(self):
        for name in NAMES:
            x_min, _, x_max, _ = self._bounds(name)
            self.assertLessEqual(x_max - x_min, build.MAX_WIDTH + 1, name)
        self.assertLessEqual(build.MAX_WIDTH, 1100)

    def test_width_limited_glyphs_are_max_width_and_not_tiny(self):
        """Spec F5.6, amendment 1 (Simón): wide icons stop at MAX_WIDTH, so they keep room before the text."""
        limited = []
        for name in NAMES:
            x_min, y_min, x_max, y_max = self._bounds(name)
            if y_max - y_min < build.TARGET_HEIGHT - 2:
                limited.append(name)
                self.assertAlmostEqual(x_max - x_min, build.MAX_WIDTH, delta=2, msg=name)
                self.assertGreaterEqual(y_max - y_min, 600, name)
        self.assertEqual(build.MAX_WIDTH, 900)
        self.assertIn("folder", limited)

    def test_glyphs_sit_on_baseline(self):
        for name in NAMES:
            _, y_min, _, _ = self._bounds(name)
            self.assertAlmostEqual(y_min, 0, delta=2, msg=name)

    def test_glyphs_start_at_left_bearing(self):
        for name in NAMES:
            x_min, _, _, _ = self._bounds(name)
            self.assertAlmostEqual(x_min, build.LEFT_BEARING, delta=2, msg=name)


if __name__ == "__main__":
    unittest.main()

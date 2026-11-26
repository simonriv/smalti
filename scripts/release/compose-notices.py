#!/usr/bin/env python3
"""Writes THIRD_PARTY_NOTICES.md from the license texts of everything linked or bundled into Smalti.app (F7.6).

Run by hand when a dependency changes; `check-notices.sh` then proves every component found in the binary has its
section. Sources: the Ghostty submodule, Zig's package cache (filled by `scripts/build-ghostty.sh`), SwiftPM
checkouts and files in the repo (Zig 0.17 keeps packages extracted in `vendor/ghostty/zig-pkg/<hash>/`; older Zig
keeps `~/.cache/zig/p/<hash>.tar.gz`, still read when the folder is missing); texts that no archive carries live in `scripts/release/notices-extra/`.
"""
import argparse
import pathlib
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
ZIG = pathlib.Path.home() / ".cache/zig/p"
ZIG_PKG = ROOT / "vendor/ghostty/zig-pkg"
EXTRA = ROOT / "scripts/release/notices-extra"
EXTRAS = {
    "simdutf": EXTRA / "simdutf-LICENSE-MIT.txt",
    "dear_bindings": EXTRA / "dear_bindings-LICENSE.txt",
    "uucode_hoehrmann": EXTRA / "uucode-LICENSE_Bjoern_Hoehrmann.txt",
    "uucode_unicode": EXTRA / "uucode-LICENSE_unicode.txt",
    "zig": EXTRA / "zig-LICENSE.txt",
    "nerd_fonts_sources": EXTRA / "nerd-fonts-glyph-sources.md",
}

# (section, version, license, homepage, source) — source: "zig:<hash>:<member>", "repo:<path>" or "extra:<name>".
COMPONENTS = [
    ("libghostty", "v1.4.0", "MIT", "https://github.com/ghostty-org/ghostty", "repo:vendor/ghostty/LICENSE"),
    ("Sparkle", "2.10.1", "MIT", "https://sparkle-project.org", "repo:Packages/SparkleUpdatesAdapter/.build/checkouts/Sparkle/LICENSE"),
    ("TOMLDecoder", "0.4.5", "MIT", "https://github.com/dduan/TOMLDecoder", "repo:Packages/TOMLConfigAdapter/.build/checkouts/TOMLDecoder/LICENSE.md"),
    ("Fig autocomplete specs", "@withfig/autocomplete", "MIT", "https://github.com/withfig/autocomplete", "repo:Packages/FigCompletionAdapter/Sources/FigCompletionAdapter/LICENSE-fig.txt"),
    ("Inter", "la de App/Smalti/Fonts", "OFL-1.1", "https://rsms.me/inter/", "repo:App/Smalti/Fonts/LICENSE-Inter.txt"),
    ("JetBrains Mono", "2.304", "OFL-1.1", "https://www.jetbrains.com/lp/mono/", "zig:N-V-__8AAIC5lwAVPJJzxnCAahSvZTIlG-HhtOvnM1uh-66x:OFL.txt"),
    ("Symbols Nerd Font", "3.4.0", "MIT", "https://www.nerdfonts.com", "zig+extra:N-V-__8AAMVLTABmYkLqhZPLXnMl-KyN38R8UVYqGrxqO26s:LICENSE+nerd_fonts_sources"),
    ("Zig standard library and compiler-rt", "la de scripts/build-ghostty.sh", "MIT", "https://ziglang.org", "extra:zig"),
    ("libxev", "819ffa1", "MIT", "https://github.com/mitchellh/libxev", "zig:libxev-0.0.0-86vtc8QQFACz0sVc7U-VDiDIgH-XfBuEY5JpABLjHNpn:LICENSE"),
    ("z2d", "0.13.0", "MPL-2.0", "https://github.com/vancluever/z2d", "zig:z2d-0.13.0-j5P_HgsRFABzZDH54gI35P0OSrg7HFyJwS2bXX5uBdU4:COPYING"),
    ("uucode", "0.2.0", "MIT", "https://github.com/jacobsandlund/uucode", "zig+extra:uucode-0.2.0-ZZjBPoGFVgCiflJNFc6Io8xzC67B6PA5bUkk4LT0kCxg:LICENSE.md+uucode_hoehrmann,uucode_unicode"),
    ("zig-objc", "3352c12", "MIT", "https://github.com/mitchellh/zig-objc", "zig:zig_objc-0.0.0-Ir_Sp_4tAQDXtPi51nW_jD9LOEzBvU9lofwO9Pzi6IB4:LICENSE"),
    ("simdutf", "la fijada por Ghostty v1.4.0", "MIT (or Apache-2.0)", "https://github.com/simdutf/simdutf", "extra:simdutf"),
    ("Highway", "66486a1", "Apache-2.0 (or BSD-3-Clause)", "https://github.com/google/highway", "zig:N-V-__8AAGmZhABbsPJLfbqrh6JTHsXhY6qCaLAQyx25e0XE:LICENSE-BSD3"),
    ("Oniguruma", "la fijada por Ghostty v1.4.0", "BSD-2-Clause", "https://github.com/kkos/oniguruma", "zig:N-V-__8AAHjwMQDBXnLq3Q2QhaivE0kE2aD138vtX2Bq1g7c:COPYING"),
    ("Wuffs", "7411f48", "MIT (or Apache-2.0)", "https://github.com/google/wuffs", "zig:N-V-__8AAP5JWgCGP_AD0teWpa4krRvE9VPZzvviGdbmN4jI:LICENSE-MIT"),
    ("libpng", "la fijada por Ghostty v1.4.0", "libpng-2.0", "http://www.libpng.org/pub/png/libpng.html", "zig:N-V-__8AAJrvXQCqAT8Mg9o_tk6m0yf5Fz-gCNEOKLyTSerD:LICENSE"),
    ("zlib", "la fijada por Ghostty v1.4.0", "Zlib", "https://zlib.net", "zig:N-V-__8AAB0eQwD-0MdOEBmz7intriBReIsIDNlukNVoNu6o:LICENSE"),
    ("FreeType", "la fijada por Ghostty v1.4.0", "FTL", "https://freetype.org", "zig:N-V-__8AAKLKpwC4H27Ps_0iL3bPkQb-z6ZVSrB-x_3EEkub:docs/FTL.TXT"),
    ("glslang", "la fijada por Ghostty v1.4.0", "BSD-3-Clause and others", "https://github.com/KhronosGroup/glslang", "zig:N-V-__8AABzkUgISeKGgXAzgtutgJsZc0-kkeqBBscJgMkvy:LICENSE.txt"),
    ("SPIRV-Cross", "la fijada por Ghostty v1.4.0", "Apache-2.0", "https://github.com/KhronosGroup/SPIRV-Cross", "zig:N-V-__8AANb6pwD7O1WG6L5nvD_rNMvnSc9Cpg1ijSlTYywv:LICENSE"),
    ("Dear ImGui", "1.92.5-docking", "MIT", "https://github.com/ocornut/imgui", "zig:N-V-__8AAEbOfQBnvcFcCX2W5z7tDaN8vaNZGamEQtNOe0UI:LICENSE.txt"),
    ("Dear Bindings", "0.17", "MIT", "https://github.com/dearimgui/dear_bindings", "extra:dear_bindings"),
    ("sentry-native", "la fijada por Ghostty v1.4.0", "MIT", "https://github.com/getsentry/sentry-native", "zig:N-V-__8AAPlZGwBEa-gxrcypGBZ2R8Bse4JYSfo_ul8i2jlG:LICENSE"),
    ("Breakpad", "b99f444", "BSD-3-Clause", "https://chromium.googlesource.com/breakpad/breakpad", "zig:N-V-__8AALw2uwF_03u4JRkZwRLc3Y9hakkYV7NKRR9-RIZJ:LICENSE"),
    ("GNU libintl (gettext-runtime)", "0.24", "LGPL-2.1-or-later", "https://www.gnu.org/software/gettext/", "zig:N-V-__8AADcZkgn4cMhTUpIz6mShCKyqqB-NBtf_S2bHaTC-:gettext-runtime/intl/COPYING.LIB"),
]

HEADER = """# Avisos de terceros

Smalti es software libre con licencia MIT (`LICENSE`). Incluye, enlazados en su binario o empaquetados en
`Smalti.app`, los componentes de abajo, cada uno con su licencia. Este archivo va también en
`Smalti.app/Contents/Resources/THIRD_PARTY_NOTICES.md`.

**GNU libintl (LGPL-2.1-or-later)** va enlazada de forma estática por libghostty en macOS. El código completo de
Smalti, de libghostty y de libintl es público, y `scripts/bootstrap` + `xcodebuild` reconstruyen la app, así que
puedes sustituir libintl por tu propia versión y volver a enlazar (LGPL-2.1, sección 6).

| Componente | Versión | Licencia | Origen |
| --- | --- | --- | --- |
"""


def text_of(source: str, extras: dict[str, pathlib.Path]) -> str:
    kind, _, rest = source.partition(":")
    if kind == "repo":
        return (ROOT / rest).read_text(encoding="utf-8", errors="replace")
    if kind == "extra":
        return "\n\n".join(extras[name].read_text(encoding="utf-8", errors="replace").strip() for name in rest.split(","))
    if kind == "zig+extra":
        archive_source, _, names = rest.rpartition("+")
        return text_of(f"zig:{archive_source}", extras) + "\n\n" + text_of(f"extra:{names}", extras)
    archive, _, member = rest.partition(":")
    extracted = ZIG_PKG / archive / member
    if extracted.is_file():
        return extracted.read_text(encoding="utf-8", errors="replace")
    with tarfile.open(ZIG / f"{archive}.tar.gz") as tar:
        handle = tar.extractfile(f"{archive}/{member}")
        if handle is None:
            raise SystemExit(f"{member} is not a file in {archive}")
        return handle.read().decode("utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "THIRD_PARTY_NOTICES.md"))
    args = parser.parse_args()
    extras = EXTRAS
    rows = [f"| {n} | {v} | {lic} | {url} |" for n, v, lic, url, _ in COMPONENTS]
    sections = [f"## {n}\n\n{url} · {lic}\n\n```text\n{text_of(src, extras).strip()}\n```\n" for n, _, lic, url, src in COMPONENTS]
    pathlib.Path(args.out).write_text(HEADER + "\n".join(rows) + "\n\n" + "\n".join(sections), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

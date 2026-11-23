#!/usr/bin/env python3
"""Copies the Fig specs Smalti bundles out of @withfig/autocomplete's build into the adapter.

Each spec is an ES module (`export{X as default,Y as named}`); JavaScriptCore evaluates plain scripts, so the export
becomes `globalThis.__smaltiSpec=X;` (and `globalThis.__smaltiExports={named:Y};`). Every `loadSpec:"name"` is
followed transitively. A listed command or a dependency without a spec fails the run.

Usage: vendor_specs.py <build-dir> <out-dir> [commands.txt]
"""
import json
import re
import shutil
import sys
from pathlib import Path

EXPORT = re.compile(r"export\{([^}]*)\};?\s*$")
LOAD_SPEC = re.compile(r'loadSpec:"([^"]+)"')
VERSION = "2.692.3"


class VendorError(Exception):
    pass


def rewrite(source: str, name: str) -> str:
    match = EXPORT.search(source)
    if not match:
        raise VendorError(f"{name}: no export at the end of the module")
    default, named = None, []
    for part in match.group(1).split(","):
        local, _, exported = part.strip().partition(" as ")
        exported = exported or local
        if exported == "default":
            default = local
        else:
            named.append(f"{exported}:{local}")
    if default is None:
        raise VendorError(f"{name}: no default export")
    tail = f"globalThis.__smaltiSpec={default};"
    if named:
        tail += "globalThis.__smaltiExports={" + ",".join(named) + "};"
    return source[: match.start()] + tail + "\n"


def vendor(build: Path, out: Path, commands: list[str]) -> None:
    pending, specs = list(commands), {}
    while pending:
        name = pending.pop()
        if name in specs:
            continue
        source_file = build / f"{name}.js"
        if not source_file.exists():
            raise VendorError(f"no Fig spec for {name!r} in {build}")
        source = source_file.read_text()
        specs[name] = rewrite(source, name)
        pending.extend(dependency for dependency in LOAD_SPEC.findall(source) if dependency not in specs)
    if out.exists():
        shutil.rmtree(out)
    for name, text in specs.items():
        target = out / f"{name}.js"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    manifest = {"version": VERSION, "commands": sorted(commands), "specs": {name: f"{name}.js" for name in sorted(specs)}}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def read_commands(path: Path) -> list[str]:
    lines = (line.strip() for line in path.read_text().splitlines())
    return [line for line in lines if line and not line.startswith("#")]


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    commands_file = Path(argv[3]) if len(argv) == 4 else Path(__file__).with_name("commands.txt")
    try:
        vendor(Path(argv[1]), Path(argv[2]), read_commands(commands_file))
    except VendorError as error:
        print(f"vendor-specs: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

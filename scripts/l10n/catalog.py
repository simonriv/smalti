#!/usr/bin/env python3
"""F7.7: keeps App/Smalti/Localizable.xcstrings in step with the code.

  catalog.py sync                 add the keys the compiler extracted in the last build (build/…/*.stringsdata)
  catalog.py translate MAP.json   set the Spanish of each key ({"english key": "texto"}) and mark both translated
  catalog.py missing              list keys without a Spanish translation
  catalog.py check                exit 1 listing compiled keys (exact, with their specifiers) not in the catalog;
                                  exit 2 when the app has not been built
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "App/Smalti/Localizable.xcstrings")


def load():
    with open(CATALOG, encoding="utf-8") as handle:
        return json.load(handle)


def save(data):
    with open(CATALOG, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def stringsdata():
    pattern = os.path.join(ROOT, "build/Build/Intermediates.noindex/**/Smalti.build/**/*.stringsdata")
    return sorted(glob.glob(pattern, recursive=True))


def sync_into(catalog, files):
    command = ["xcrun", "xcstringstool", "sync", catalog]
    for path in files:
        command += ["--stringsdata", path]
    subprocess.run(command, check=True)


def sync():
    files = stringsdata()
    if not files:
        sys.exit("no .stringsdata: build the app first")
    sync_into(CATALOG, files)


def check():
    """The compiler's keys are exact (%@ vs %lld): a key whose interpolation type changed is missing at run time."""
    files = stringsdata()
    if not files:
        print("no .stringsdata: build the app first")
        sys.exit(2)
    with tempfile.TemporaryDirectory() as work:
        copy = os.path.join(work, "Localizable.xcstrings")
        shutil.copy(CATALOG, copy)
        sync_into(copy, files)
        with open(copy, encoding="utf-8") as handle:
            synced = json.load(handle).get("strings", {})
    known = load().get("strings", {})
    new = sorted(key for key in synced if key not in known)
    print("\n".join(repr(key) for key in new))
    sys.exit(1 if new else 0)


def translate(mapping_path):
    with open(mapping_path, encoding="utf-8") as handle:
        mapping = json.load(handle)
    data = load()
    strings = data.setdefault("strings", {})
    for key, spanish in mapping.items():
        entry = strings.setdefault(key, {})
        entry.pop("extractionState", None) if entry.get("extractionState") == "stale" else None
        localizations = entry.setdefault("localizations", {})
        localizations["en"] = {"stringUnit": {"state": "translated", "value": key}}
        localizations["es"] = {"stringUnit": {"state": "translated", "value": spanish}}
    save(data)


def missing():
    data = load()
    for key, entry in sorted(data.get("strings", {}).items()):
        if entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("state") != "translated":
            print(key)


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "sync":
        sync()
    elif action == "translate" and len(sys.argv) == 3:
        translate(sys.argv[2])
    elif action == "missing":
        missing()
    elif action == "check":
        check()
    else:
        sys.exit(__doc__)

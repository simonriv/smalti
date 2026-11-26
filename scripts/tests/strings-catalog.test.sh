#!/usr/bin/env bash
# F7.7: the app's String Catalog is complete and nothing visible bypasses it.
#  (a) every key of App/Smalti/Localizable.xcstrings has `en` and `es`, both `translated`;
#  (b) every String(localized:)/SwiftUI Text key in App/Smalti is in the catalog (xcstringstool extract);
#  (c) no Swift literal with Spanish in App/Smalti outside String(localized:) and Text(;
#  (d) no Swift literal with Spanish in Packages/*/Sources outside SmaltiCore/Domain/Texts;
#  (e) after a build, every key the compiler extracted is in the catalog exactly (catalog.py check: %@ vs %lld).
# Prints "[n/total] ok|FAIL <case>" and exits with the number of failures.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
catalog="$root/App/Smalti/Localizable.xcstrings"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
total=5; n=0; failures=0

report() { # name status detail-file
  n=$((n + 1))
  if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"
  else echo "[$n/$total] FAIL $1"; sed 's/^/    /' "$3"; failures=$((failures + 1)); fi
}

python3 - "$catalog" > "$work/a.txt" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError) as error:
    print(f"unreadable catalog: {error}"); sys.exit(1)
bad = []
for key, entry in sorted(data.get("strings", {}).items()):
    if entry.get("shouldTranslate") is False:
        continue
    for language in ("en", "es"):
        unit = entry.get("localizations", {}).get(language, {}).get("stringUnit", {})
        if unit.get("state") != "translated" or not unit.get("value"):
            bad.append(f"{language}: {key!r}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
report catalog_has_both_languages $? "$work/a.txt"

find "$root/App/Smalti" -name '*.swift' -print0 > "$work/sources"
xargs -0 "${XCSTRINGSTOOL:-xcrun}" xcstringstool extract --modern-localizable-strings --SwiftUI \
  --output-format xcstrings --output-directory "$work/extracted" < "$work/sources" > "$work/extract.log" 2>&1
extracted=$?
python3 - "$catalog" "$work/extracted" "$extracted" "$work/extract.log" > "$work/b.txt" <<'PY'
import json, os, re, sys
# An extraction that failed or found nothing proves nothing: it fails the case instead of passing it.
if sys.argv[3] != "0" or not os.path.isdir(sys.argv[2]):
    print(f"xcstringstool extract failed ({sys.argv[3]}):"); print(open(sys.argv[4]).read()[-800:]); sys.exit(1)
# Without the compiler, xcstringstool writes %arg where the type decides %@ or %lld: compare without specifiers.
spec = re.compile(r"%(?:\d+\$)?(?:arg|@|lld|ld|d|f|\.\d+f)")
normal = lambda key: spec.sub("%", key)
known = {normal(key) for key in json.load(open(sys.argv[1], encoding="utf-8")).get("strings", {})}
missing, extracted = [], 0
for name in sorted(os.listdir(sys.argv[2])) if os.path.isdir(sys.argv[2]) else []:
    if name.endswith(".xcstrings"):
        for key in json.load(open(os.path.join(sys.argv[2], name), encoding="utf-8")).get("strings", {}):
            extracted += 1
            if normal(key) not in known:
                missing.append(repr(key))
if extracted == 0:
    print("xcstringstool extracted no keys"); sys.exit(1)
print("\n".join(sorted(set(missing))))
sys.exit(1 if missing else 0)
PY
report every_localized_key_is_in_the_catalog $? "$work/b.txt"

scan() { # root-relative directories… (prints offending literals)
  python3 - "$root" "$@" <<'PY'
import os, re, sys
root, folders = sys.argv[1], sys.argv[2:]
literal = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# Localized calls carry their (English) key: they are taken out of the line, the rest of it is still scanned.
localized = re.compile(r'(?:String\(localized:|Text\()\s*"(?:[^"\\\n]|\\.)*"')
spanish = re.compile(r"[áéíóúñ¿¡ÁÉÍÓÚÑ]|\b(de|del|la|las|los|en|con|sin|para|por|una|que|abrir|cerrar|buscar|"
                     r"panel|paneles|sesión|sesiones|ventana|guardar|mostrar|activar|ayuda|hoy|días|ahora|hace|línea|"
                     r"archivo|fallo|aprobar|rechazar|espera|trabajando|copiar|pegar|nuevo|nueva)\b", re.I)
skip_dirs = ("/Tests", "/TestSupport", "/Fixtures", "/.build", "SmaltiCore/Domain/Texts", "SmaltiCoreTestSupport")
found = []
for folder in folders:
    for base, _, files in os.walk(os.path.join(root, folder)):
        if any(part in base for part in skip_dirs):
            continue
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(base, name)
            multiline, previous = False, ""
            for number, line in enumerate(open(path, encoding="utf-8"), 1):
                above, previous = previous, line
                code = line.strip()
                quotes = line.count('"""')
                if multiline or quotes:
                    # Inside a multi-line literal every line is text (a keep mark on the opening line or the one above covers it).
                    if multiline and spanish.search(line) and not keep:
                        found.append(f"{os.path.relpath(path, root)}:{number}: {code[:80]}")
                    if quotes % 2:
                        multiline = not multiline
                        keep = "strings-catalog: keep" in line + above
                    if quotes and not multiline:
                        continue
                    if multiline:
                        continue
                if code.startswith("//") or "strings-catalog: keep" in code:
                    continue
                for text in literal.findall(localized.sub("", line)):
                    if len(text) > 1 and spanish.search(text):
                        found.append(f"{os.path.relpath(path, root)}:{number}: {text[:80]}")
print("\n".join(found))
sys.exit(1 if found else 0)
PY
}
scan App/Smalti > "$work/c.txt"
report no_spanish_literal_in_the_app $? "$work/c.txt"
scan $(cd "$root" && ls -d Packages/*/Sources) > "$work/d.txt"
report no_spanish_literal_in_the_packages $? "$work/d.txt"

python3 "$root/scripts/l10n/catalog.py" check > "$work/e.txt" 2>&1
checked=$?
if [[ $checked == 2 ]]; then n=$((n + 1)); echo "[$n/$total] ok compiled_keys_are_in_the_catalog (skipped: the app has not been built)"
else report compiled_keys_are_in_the_catalog "$checked" "$work/e.txt"; fi
exit "$failures"

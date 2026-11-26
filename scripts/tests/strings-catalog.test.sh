#!/usr/bin/env bash
# F7.7: the app's String Catalog is complete and nothing visible bypasses it.
#  (a) every key of App/Smalti/Localizable.xcstrings has `en` and `es`, both `translated`;
#  (b) every String(localized:)/SwiftUI Text key in App/Smalti is in the catalog (xcstringstool extract);
#  (c) no Swift literal with Spanish in App/Smalti outside String(localized:) and Text(;
#  (d) no Swift literal with Spanish in Packages/*/Sources outside SmaltiCore/Domain/Texts.
# Prints "[n/total] ok|FAIL <case>" and exits with the number of failures.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
catalog="$root/App/Smalti/Localizable.xcstrings"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
total=4; n=0; failures=0

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
xargs -0 xcrun xcstringstool extract --modern-localizable-strings --SwiftUI --output-format xcstrings \
  --output-directory "$work/extracted" < "$work/sources" > "$work/extract.log" 2>&1
python3 - "$catalog" "$work/extracted" > "$work/b.txt" <<'PY'
import json, os, sys
known = set(json.load(open(sys.argv[1], encoding="utf-8")).get("strings", {}))
missing = []
for name in sorted(os.listdir(sys.argv[2])) if os.path.isdir(sys.argv[2]) else []:
    if name.endswith(".xcstrings"):
        for key in json.load(open(os.path.join(sys.argv[2], name), encoding="utf-8")).get("strings", {}):
            if key not in known:
                missing.append(repr(key))
print("\n".join(sorted(set(missing))))
sys.exit(1 if missing else 0)
PY
report every_localized_key_is_in_the_catalog $? "$work/b.txt"

scan() { # root-relative directories… (prints offending literals)
  python3 - "$root" "$@" <<'PY'
import os, re, sys
root, folders = sys.argv[1], sys.argv[2:]
literal = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
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
            for number, line in enumerate(open(path, encoding="utf-8"), 1):
                code = line.strip()
                if code.startswith("//") or "String(localized:" in code or "Text(" in code:
                    continue
                for text in literal.findall(line):
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
exit "$failures"

#!/usr/bin/env bash
# F7.7 (privacy): the only request Smalti makes off the machine is Sparkle's appcast. Network APIs and literal URLs may
# appear only in the files allowed below; anything else fails, naming file and line.
#   network-surface.test.sh [root]   (root: a tree to scan instead of the repository, for this script's own test)
# Prints "[n/total] ok|FAIL <case>".
set -uo pipefail
root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
total=2; n=0; failures=0

report() { n=$((n + 1)); if [[ "$2" == 0 ]]; then echo "[$n/$total] ok $1"
  else echo "[$n/$total] FAIL $1"; sed 's/^/    /' "$3"; failures=$((failures + 1)); fi; }

scan() { # pattern allow-regex → offending lines
  python3 - "$root" "$1" "$2" <<'PY'
import os, re, sys
root, pattern, allow = sys.argv[1], re.compile(sys.argv[2]), re.compile(sys.argv[3])
found = []
for folder in ("App/Smalti", "Packages"):
    for base, dirs, files in os.walk(os.path.join(root, folder)):
        dirs[:] = [d for d in dirs if d not in (".build", "Tests", "Fixtures", "SmaltiCoreTestSupport")]
        for name in files:
            if not name.endswith(".swift") or name == "Package.swift":
                continue
            path = os.path.relpath(os.path.join(base, name), root)
            if allow.search(path):
                continue
            for number, line in enumerate(open(os.path.join(base, name), encoding="utf-8"), 1):
                if not line.strip().startswith("//") and pattern.search(line):
                    found.append(f"{path}:{number}: {line.strip()[:100]}")
print("\n".join(found))
sys.exit(1 if found else 0)
PY
}

out="$(mktemp)"; trap 'rm -f "$out"' EXIT
# Sockets and HTTP clients: Ollama (127.0.0.1), the OTLP receiver (loopback), the Unix sockets of the IPC and Neovim.
scan 'URLSession|NWConnection|NWListener|import Network|CFStream|getaddrinfo|socket\(AF_' \
  '^Packages/(OllamaAdapter|OTLPReceiverAdapter|IPCAdapter|NeovimAdapter|SparkleUpdatesAdapter)/' > "$out"
report network_apis_only_in_allowed_adapters $? "$out"
# Literal URLs: the site's pages the user opens, Ollama's local default and the telemetry's loopback endpoint.
scan 'https?://' '^Packages/SmaltiCore/Sources/SmaltiCore/Domain/(Support/SmaltiLinks|Config/LaunchSettings|Telemetry/TelemetryEnvironment)\.swift$' > "$out"
report literal_urls_only_in_allowed_files $? "$out"
exit "$failures"

#!/usr/bin/env bash
# F7.5 C12: start-up of `smalti guard PreToolUse` against `smalti event PreToolUse` for a harmless Bash call, with a
# fake app on a temporary Unix socket that answers at once (`{"ok":true,"decision":"allow"}` to a guard, `{"ok":true}`
# to an event). Builds the CLI in release unless a binary is given, runs each mode `runs` times under `env -i`, and
# prints the p50 and nearest-rank p95 in ms plus the p50 difference. Usage:
#   scripts/measure-guard.sh [runs] [binary] [baseline]   (default: 50 runs of the freshly built smalti)
# `baseline` is the CLI before F7.5 (built from origin/develop): the 3 ms limit is then guard against its
# `event PreToolUse`, so the phase's own slower `event` is not the reference (final review I4).
# Prints `[k/n] ok …` per line, or `[k/n] FAIL …`; exits 1 if the p50 difference is over 3 ms.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
runs="${1:-50}"
binary="${2:-}"
baseline="${3:-}"
if [[ -z "$binary" ]]; then
  swift build -c release --package-path "$root/Packages/IPCAdapter" --product smalti > /dev/null || exit 1
  binary="$(swift build -c release --package-path "$root/Packages/IPCAdapter" --show-bin-path)/smalti"
fi
python3 -I - "$binary" "$runs" "$baseline" <<'PY'
import json, math, os, socket, statistics, subprocess, sys, tempfile, threading, time
binary, runs, baseline = sys.argv[1], int(sys.argv[2]), sys.argv[3]
folder = tempfile.mkdtemp(prefix="smalti-guard-")
path = os.path.join(folder, "s.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(16)
stop = False

def serve():
    while not stop:
        try:
            client, _ = server.accept()
        except OSError:
            return
        with client:
            data = b""
            while b"\n" not in data:
                chunk = client.recv(65536)
                if not chunk:
                    break
                data += chunk
            kind = json.loads(data.split(b"\n")[0] or b"{}").get("kind")
            answer = {"ok": True, "error": None}
            if kind == "guard":
                answer["decision"] = "allow"
            client.sendall(json.dumps(answer).encode() + b"\n")

thread = threading.Thread(target=serve, daemon=True)
thread.start()
payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git status"}, "cwd": "/tmp"}).encode()
environment = ["/usr/bin/env", "-i", f"SMALTI_SOCKET={path}", "SMALTI_PANE_ID=8D8AC610-566D-4EF0-9C22-186B2A5ED793",
               "HOME=/tmp"]

def measure(mode, cli=binary):
    samples = []
    for _ in range(runs + 3):
        start = time.perf_counter_ns()
        result = subprocess.run(environment + [cli, mode, "PreToolUse"], input=payload, capture_output=True)
        samples.append((time.perf_counter_ns() - start) / 1e6)
        if result.returncode != 0 or result.stdout:
            raise SystemExit(f"{mode} answered {result.returncode} {result.stdout!r}")
    samples = sorted(samples[3:])
    return statistics.median(samples), samples[math.ceil(len(samples) * 0.95) - 1]

total = 4 if baseline else 3
event = measure("event")
print(f"[1/{total}] ok event p50 {event[0]:.2f} ms p95 {event[1]:.2f} ms", flush=True)
guard = measure("guard")
print(f"[2/{total}] ok guard p50 {guard[0]:.2f} ms p95 {guard[1]:.2f} ms", flush=True)
reference = event
if baseline:
    reference = measure("event", baseline)
    print(f"[3/{total}] ok baseline event p50 {reference[0]:.2f} ms p95 {reference[1]:.2f} ms", flush=True)
difference = guard[0] - reference[0]
stop = True
server.close()
os.unlink(path)
os.rmdir(folder)
verdict = "ok" if difference <= 3 else "FAIL"
label = "guard vs baseline event" if baseline else "guard vs event"
print(f"[{total}/{total}] {verdict} {label} p50 {difference:+.2f} ms (limit 3 ms)")
sys.exit(0 if verdict == "ok" else 1)
PY

# F6 · Spike de reanudación (T1)

2026-11-24 · Binarios: Codex 0.171.0 (cask), Antigravity 1.5.10 (cask), OpenCode 2.3.2 (fórmula), Claude Code 2.1.332, Ollama 0.40.17 + `qwen3:4b`.

## Resultados

| Pregunta | Resultado |
| --- | --- |
| ¿`claude --resume` pide login con `CLAUDE_CONFIG_DIR` temporal? | **No.** Muestra la sesión sin hacer peticiones si `.claude.json` trae `hasCompletedOnboarding`, `theme` y la carpeta como confiable (`projects.<dir>.hasTrustDialogAccepted`). Sin eso sale el selector de tema. `claude -p` sí exige login: el fixture de Claude son los transcripts reales de F3, movidos a la ruta fija |
| ¿Codex y OpenCode necesitan Ollama para retomar? | **No.** Retoman con el proveedor en un puerto muerto (`127.0.0.1:9`). Codex no deja redefinir el proveedor integrado `ollama` y exige `wire_api = "responses"`; las pruebas usan un proveedor propio |
| Proceso en primer plano (`ps -o comm=` del grupo del PTY) | `codex`, `antigravity` (ruta del cask; `agy` es un wrapper que hace `exec`), `opencode`, `claude` |
| ¿`st_birthtime` de `conversations/<id>.db` es la creación en Antigravity? | **Sí.** Coincide con `last_user_input_time` del primer mensaje (47,5 s / 47 s y 54,8 s / 54 s) |
| Títulos de Antigravity grabados con `-p` | Vacíos (el proceso sale antes de generarlos): el adaptador usa `preview` |
| Daemons al salir | `codex app-server … --managed-daemon` y `opencode serve --service`; se matan por la ruta del home temporal |
| Primeras pantallas | Codex pregunta por la confianza en la carpeta (`[projects."<dir>"] trust_level = "trusted"` la evita) y ofrece actualizar (`check_for_update_on_startup = false`) |

## Fixtures

- Grabados en rutas fijas, `/private/tmp/smalti-fx/<harness>/{home,work-a,work-b}`, porque los harnesses guardan rutas dentro de blobs protobuf. Saneados con `scripts/harnesses/sanitize_fixture.py`, que quita tokens, logs, cachés, snapshots y skills, cambia marcadores y correos, y falla si queda alguno.
- `expected.json` lo escribe el oráculo independiente `fixture_expectations.py` desde la grabación cruda (incluye `createdAt`).
- En la máquina hay un LaunchAgent del usuario, `com.<usuario>.ollama` (2026-10-22), que mantiene `ollama serve` en 11434. La grabación lo usa y no lo toca.

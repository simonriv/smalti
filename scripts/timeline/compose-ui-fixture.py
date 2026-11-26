#!/usr/bin/env python3
"""Builds App/SmaltiUITests/Fixtures/timeline-home.json for F9's UI tests from the sanitized fixtures.

Claude transcripts (F6's work-a and work-b, F9's synthetic one and a long-prompt session) get "{{root}}" in place of
their working directory, so the test puts them under the folder its panes use; Codex's F9 home goes as base64 (an
SQLite index and a rollout). Nothing personal: only the committed, sanitized fixtures.

Usage: compose-ui-fixture.py > App/SmaltiUITests/Fixtures/timeline-home.json
"""

import base64
import json
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CLAUDE = os.path.join(REPO, "Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures")
CODEX = os.path.join(REPO, "Packages/CodexHarnessAdapter/Tests/CodexHarnessAdapterTests/Fixtures/codex-timeline/home/codex")
LONG_PROMPT = "Escribe un resumen largo. " * 120


def claude_files():
    files = {}
    projects = os.path.join(CLAUDE, "claude/home/.claude/projects")
    for folder in sorted(os.listdir(projects)):
        for name in sorted(os.listdir(os.path.join(projects, folder))):
            text = open(os.path.join(projects, folder, name), encoding="utf-8").read()
            work = folder.rsplit("-", 1)[-1]
            text = text.replace(f"/private/tmp/smalti-fx/claude/work-{work}", "{{root}}")
            files[f"{work}/{name}"] = text.splitlines()
    synthetic = open(os.path.join(CLAUDE, "timeline-synthetic/image.jsonl"), encoding="utf-8").read()
    files["s/5e1f0000-0000-4000-8000-000000000001.jsonl"] = synthetic.replace("/fixture/work/s", "{{root}}").splitlines()
    files["s/5e1f0000-0000-4000-8000-000000000002.jsonl"] = long_session()
    return files


def long_session():
    base = {"sessionId": "5e1f0000-0000-4000-8000-000000000002", "cwd": "{{root}}", "version": "2.1.330"}
    lines = [
        dict(base, type="user", timestamp="2026-11-26T11:00:00.000Z", uuid="l1",
             message={"role": "user", "content": LONG_PROMPT}),
        dict(base, type="assistant", timestamp="2026-11-26T11:00:02.000Z", uuid="l2",
             message={"id": "msg_l", "model": "claude-haiku-5-5", "role": "assistant",
                      "content": [{"type": "text", "text": "Hecho."}], "usage": {"input_tokens": 1, "output_tokens": 1}}),
    ]
    return [json.dumps(line, ensure_ascii=False) for line in lines]


def codex_files():
    files = {}
    for root, _, names in os.walk(CODEX):
        for name in names:
            if name in ("state_5.sqlite",) or name.endswith(".jsonl"):
                path = os.path.join(root, name)
                files[os.path.relpath(path, CODEX)] = base64.b64encode(open(path, "rb").read()).decode()
    return files


if __name__ == "__main__":
    json.dump({"claude": claude_files(), "codex": codex_files(), "longPrompt": LONG_PROMPT}, sys.stdout,
              indent=1, ensure_ascii=False)

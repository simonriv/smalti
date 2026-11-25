#!/usr/bin/env python3
"""Gives a Claude fixture transcript a distinct, non-personal prompt text, so tests can tell sessions apart.

F3's real transcripts have every prompt redacted to "<redacted>"; F6's resume test needs to see that the right
session came back (review 1, M6). Every user prompt gets the marker: the first one is the session's title, and a
resumed Claude shows only the last turn. Tool results stay as they are.

Usage: mark_claude_prompt.py <transcript.jsonl> <marker>
"""

import json
import sys


def mark(path, marker):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    for index, line in enumerate(lines):
        record = json.loads(line)
        if record.get("type") != "user":
            continue
        message = record.get("message") or {}
        content = message.get("content")
        if isinstance(content, str):
            message["content"] = marker
        elif isinstance(content, list):
            texts = [block for block in content if isinstance(block, dict) and block.get("type") == "text"]
            if not texts:
                continue
            texts[0]["text"] = marker
        else:
            continue
        lines[index] = json.dumps(record, ensure_ascii=False)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    mark(sys.argv[1], sys.argv[2])

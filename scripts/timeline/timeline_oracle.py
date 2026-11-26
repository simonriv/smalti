#!/usr/bin/env python3
"""Independent oracle for F9's timeline: the items a transcript must show, with their whole text.

Written from the rules in docs/specs/F9-timeline.md (section 1), apart from the Swift adapters, so the contract test
compares the timeline against something it did not compute itself.

Usage: timeline_oracle.py <claude|codex> <transcript.jsonl> [--subagents <folder>]

Each item: {"kind": prompt|reply|call|output|image|compaction, "who": user|agent|system|<tool>, "scope": main|<agent>,
"text": <whole text>}. A call's text is Claude's `input` as compact JSON with sorted keys (the timeline cannot keep the
file's key order), Codex's `arguments`/`input` string untouched. An output's text is the result string, or its text
blocks joined with a newline. An image's text is its media type.
"""

import json
import os
import sys

CODEX_CONTEXT = ("<environment_context>", "<user_instructions>", "<skills_instructions>")


def item(kind, who, scope, text):
    return {"kind": kind, "who": who, "scope": scope, "text": text}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def text_blocks(blocks):
    return [b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "text"]


def images(blocks, who, scope):
    return [item("image", who, scope, (b.get("source") or {}).get("media_type", ""))
            for b in blocks if isinstance(b, dict) and b.get("type") == "image"]


def claude_lines(path, scope, tools):
    items = []
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            try:
                record = json.loads(raw)
            except ValueError:
                continue
            kind = record.get("type")
            if kind == "system" and record.get("subtype") == "compact_boundary":
                items.append(item("compaction", "system", scope, ""))
            elif kind == "assistant":
                items += claude_assistant(record, scope, tools)
            elif kind == "user" and not record.get("isMeta") and not record.get("isCompactSummary"):
                items += claude_user(record, scope, tools)
    return items


def claude_assistant(record, scope, tools):
    items = []
    for block in (record.get("message") or {}).get("content") or []:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            items.append(item("reply", "agent", scope, block.get("text", "")))
        elif block.get("type") == "tool_use":
            tools[block.get("id")] = block.get("name", "")
            items.append(item("call", block.get("name", ""), scope, canonical(block.get("input", {}))))
    return items


def claude_user(record, scope, tools):
    content = (record.get("message") or {}).get("content")
    if isinstance(content, str):
        return [item("prompt", "user", scope, content)]
    if not isinstance(content, list):
        return []
    items = []
    texts = text_blocks(content)
    if texts:
        items.append(item("prompt", "user", scope, "\n".join(texts)))
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "image":
            items += images([block], "user", scope)
        elif block.get("type") == "tool_result":
            who = tools.get(block.get("tool_use_id"), "?")
            result = block.get("content")
            if isinstance(result, list):
                items.append(item("output", who, scope, "\n".join(text_blocks(result))))
                items += images(result, who, scope)
            else:
                items.append(item("output", who, scope, result if isinstance(result, str) else ""))
    return items


def claude(path, subagents=None):
    tools = {}
    items = claude_lines(path, "main", tools)
    if subagents and os.path.isdir(subagents):
        for name in sorted(os.listdir(subagents)):
            if name.startswith("agent-") and name.endswith(".jsonl"):
                agent = name[len("agent-"):-len(".jsonl")]
                items += claude_lines(os.path.join(subagents, name), agent, tools)
    return items


def codex_texts(content, kinds):
    return [c.get("text", "") for c in content or [] if isinstance(c, dict) and c.get("type") in kinds]


def codex_output(payload):
    output = payload.get("output")
    if isinstance(output, dict):
        output = output.get("content")
    return output if isinstance(output, str) else ""


def codex(path):
    items, tools = [], {}
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            try:
                record = json.loads(raw)
            except ValueError:
                continue
            payload = record.get("payload") or {}
            if record.get("type") == "compacted":
                items.append(item("compaction", "system", "main", ""))
                continue
            if record.get("type") != "response_item":
                continue
            kind = payload.get("type")
            if kind == "message" and payload.get("role") == "user":
                texts = codex_texts(payload.get("content"), ("input_text",))
                if texts and texts[0].lstrip().startswith(CODEX_CONTEXT):
                    continue
                if texts:
                    items.append(item("prompt", "user", "main", "\n".join(texts)))
                items += [item("image", "user", "main", "") for c in payload.get("content") or []
                          if isinstance(c, dict) and c.get("type") == "input_image"]
            elif kind == "message" and payload.get("role") == "assistant":
                texts = codex_texts(payload.get("content"), ("output_text",))
                if texts:
                    items.append(item("reply", "agent", "main", "\n".join(texts)))
            elif kind in ("function_call", "custom_tool_call"):
                tools[payload.get("call_id")] = payload.get("name", "")
                text = payload.get("arguments") if kind == "function_call" else payload.get("input")
                items.append(item("call", payload.get("name", ""), "main", text if isinstance(text, str) else ""))
            elif kind in ("function_call_output", "custom_tool_call_output"):
                items.append(item("output", tools.get(payload.get("call_id"), "?"), "main", codex_output(payload)))
    return items


def main(argv):
    harness, path = argv[1], argv[2]
    subagents = argv[argv.index("--subagents") + 1] if "--subagents" in argv else None
    items = claude(path, subagents) if harness == "claude" else codex(path)
    print(json.dumps({"items": items}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv)

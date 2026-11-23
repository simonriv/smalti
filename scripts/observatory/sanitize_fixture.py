#!/usr/bin/env python3
"""Turns a real Claude Code transcript into a committable fixture for F3.

Everything that carries tokens or that the observatory reads stays as Claude wrote it: assistant replies (id,
model, usage, tool calls), tool results (error flag, short output, patch), compaction metadata, timestamps and
session ids. Everything else that can hold personal context (prompts, injected CLAUDE.md, attachments, request
blobs, thinking) is redacted. Paths of the recording directory and the home become /fixture/work and /fixture/home,
and `scan` refuses any line that still names a personal marker.

Usage: sanitize_fixture.py <in.jsonl> <out.jsonl> --work <dir> --home <dir> --marker <text>…
"""

import argparse
import json
import sys

REDACTED = "<redacted>"
KEPT_TYPES = {"assistant", "user", "system"}
COMPACT_KEYS = ("preTokens", "postTokens", "trigger")
RESULT_LIMIT = 200


class PersonalDataError(Exception):
    pass


def rewrite(text, work, home):
    return text.replace(work, "/fixture/work").replace(home, "/fixture/home")


def common(record, keys=("type", "timestamp", "sessionId", "uuid", "parentUuid", "isSidechain", "cwd", "version")):
    return {key: record[key] for key in keys if key in record}


def assistant(record):
    message = record.get("message") or {}
    content = []
    for block in message.get("content") or []:
        if block.get("type") == "thinking":
            content.append({"type": "thinking", "thinking": ""})
        elif block.get("type") in ("text", "tool_use"):
            content.append(block)
    kept = {key: message[key] for key in ("id", "model", "usage", "stop_reason") if key in message}
    return {**common(record), "message": {**kept, "role": "assistant", "content": content}}


def user_block(block):
    if block.get("type") != "tool_result":
        return {"type": block.get("type", "text"), "text": REDACTED}
    content = block.get("content")
    if isinstance(content, list):
        content = " ".join(part.get("text", "") for part in content if isinstance(part, dict))
    kept = {key: block[key] for key in ("type", "tool_use_id", "is_error") if key in block}
    return {**kept, "content": (content or "")[:RESULT_LIMIT]}


def user(record):
    content = (record.get("message") or {}).get("content")
    cleaned = REDACTED if not isinstance(content, list) else [user_block(block) for block in content]
    result = {**common(record), "message": {"role": "user", "content": cleaned}}
    patch = (record.get("toolUseResult") or {}) if isinstance(record.get("toolUseResult"), dict) else {}
    if "structuredPatch" in patch:
        result["toolUseResult"] = {"structuredPatch": patch["structuredPatch"]}
    return result


def system(record):
    result = {**common(record), "subtype": record.get("subtype")}
    metadata = record.get("compactMetadata")
    if isinstance(metadata, dict):
        result["compactMetadata"] = {key: metadata[key] for key in COMPACT_KEYS if key in metadata}
    return result


def derived_from(record):
    sessions = [{key: entry[key] for key in ("type", "id", "via") if key in entry}
                for entry in record.get("sessions") or [] if isinstance(entry, dict)]
    return {key: record[key] for key in ("type", "v", "sessionId") if key in record} | {"sessions": sessions}


def sanitize_line(line, work, home):
    record = json.loads(line)
    kind = record.get("type")
    if kind == "derived-from":
        return json.dumps(derived_from(record))
    if kind not in KEPT_TYPES:
        return json.dumps({"type": kind, "redacted": True})
    cleaned = {"assistant": assistant, "user": user, "system": system}[kind](record)
    return rewrite(json.dumps(cleaned, ensure_ascii=False), work, home)


def scan(text, markers):
    lowered = text.lower()
    for marker in markers:
        if marker.lower() in lowered:
            raise PersonalDataError(f"personal marker still present: {marker!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("--work", required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--marker", action="append", default=[])
    args = parser.parse_args()
    lines = []
    with open(args.source, errors="replace") as source:
        for line in source:
            if line.strip():
                lines.append(sanitize_line(line, args.work, args.home))
    text = "\n".join(lines) + "\n"
    scan(text, args.marker + [args.home, args.work])
    with open(args.target, "w") as target:
        target.write(text)


if __name__ == "__main__":
    try:
        main()
    except PersonalDataError as error:
        print(error, file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Independent token oracle for F3's closing criterion (C1).

Sums the tokens of Claude Code transcripts under a `projects/` directory, the way the spec defines them, without
sharing any code with Smalti's Swift adapter:

- each `message.id` counts once per session, or once overall with --global-dedupe: a fork (`--fork-session`)
  copies its source's messages, so sessions marked `derived-from` are read after their sources and the copies
  stay with the source;
- a subagent's transcript (`<session>/subagents/*.jsonl`) adds to its session;
- `<synthetic>` replies are ignored;
- without the `cache_creation` breakdown, every cache write counts as a 5-minute write.

Usage: sum_transcripts.py <projects-dir> [--since ISO] [--until ISO] [--global-dedupe]
Prints JSON: {"sessions": {<id>: totals}, "total": totals}, totals = input, output, cacheRead, cacheWrite5m,
cacheWrite1h.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

FIELDS = ("input", "output", "cacheRead", "cacheWrite5m", "cacheWrite1h")


def zero():
    return {field: 0 for field in FIELDS}


def parse_time(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def tokens(usage):
    write = usage.get("cache_creation_input_tokens", 0) or 0
    breakdown = usage.get("cache_creation")
    write_5m, write_1h = write, 0
    if isinstance(breakdown, dict):
        write_5m = breakdown.get("ephemeral_5m_input_tokens", 0) or 0
        write_1h = breakdown.get("ephemeral_1h_input_tokens", 0) or 0
    return {
        "input": usage.get("input_tokens", 0) or 0,
        "output": usage.get("output_tokens", 0) or 0,
        "cacheRead": usage.get("cache_read_input_tokens", 0) or 0,
        "cacheWrite5m": write_5m,
        "cacheWrite1h": write_1h,
    }


def is_derived(path):
    for line in path.read_text(errors="replace").splitlines():
        if '"derived-from"' in line:
            try:
                return json.loads(line).get("type") == "derived-from"
            except json.JSONDecodeError:
                continue
    return False


def transcript_files(projects):
    """(session id, path) for every main and subagent transcript: sources before the sessions derived from them."""
    mains = sorted(projects.glob("*/*.jsonl"), key=lambda path: (is_derived(path), str(path)))
    for path in mains:
        yield path.stem, path
    for path in sorted(projects.glob("*/*/subagents/*.jsonl")):
        yield path.parent.parent.name, path


def replies(path):
    for line in path.read_text(errors="replace").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if record.get("type") != "assistant":
            continue
        message = record.get("message") or {}
        if message.get("id") and message.get("usage") and message.get("model") != "<synthetic>":
            yield message["id"], record.get("timestamp", ""), message["usage"]


def summarize(projects, since=None, until=None, global_dedupe=False):
    since_time = parse_time(since) if since else None
    until_time = parse_time(until) if until else None
    sessions, total = {}, zero()
    seen_overall, seen_by_session = set(), {}
    for session, path in transcript_files(Path(projects)):
        seen = seen_overall if global_dedupe else seen_by_session.setdefault(session, set())
        for message_id, timestamp, usage in replies(path):
            if message_id in seen:
                continue
            seen.add(message_id)
            at = parse_time(timestamp)
            if (since_time and at < since_time) or (until_time and at >= until_time):
                continue
            counted = tokens(usage)
            bucket = sessions.setdefault(session, zero())
            for field in FIELDS:
                bucket[field] += counted[field]
                total[field] += counted[field]
    return {"sessions": sessions, "total": total}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("projects")
    parser.add_argument("--since")
    parser.add_argument("--until")
    parser.add_argument("--global-dedupe", action="store_true")
    args = parser.parse_args()
    json.dump(summarize(args.projects, args.since, args.until, args.global_dedupe), sys.stdout, indent=2, sort_keys=True)
    print()


if __name__ == "__main__":
    main()

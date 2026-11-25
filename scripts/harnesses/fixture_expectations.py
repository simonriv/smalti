#!/usr/bin/env python3
"""Independent oracle for F6's harness fixtures: which sessions a recorded home holds, newest first.

It reads each harness's store with Python's sqlite3 and json, apart from the Swift adapters, so the shared
contract test compares the adapters against something they did not compute themselves.

Usage: fixture_expectations.py <claude|codex|antigravity|opencode> <home> > expected.json
"""

import json
import os
import sqlite3
import sys
import urllib.parse
from datetime import datetime, timezone


def iso(seconds):
    return datetime.fromtimestamp(int(seconds), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def query(path, sql):
    with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as db:
        return db.execute(sql).fetchall()


def codex(home):
    rows = query(os.path.join(home, "codex/state_5.sqlite"),
                 "select id, cwd, title, created_at from threads where archived = 0 order by updated_at desc")
    return [{"id": i, "directory": d, "title": t, "createdAt": iso(c)} for i, d, t, c in rows]


def antigravity(home):
    root = os.path.join(home, ".gemini/antigravity-cli")
    rows = query(os.path.join(root, "conversation_summaries.db"),
                 "select conversation_id, workspace_uris, title, preview from conversation_summaries "
                 "order by last_modified_time desc")
    sessions = []
    for identifier, uris, title, preview in rows:
        files = [uri for uri in json.loads(uris or "[]") if uri.startswith("file://")]
        if files:
            born = os.stat(os.path.join(root, "conversations", identifier + ".db")).st_birthtime
            sessions.append({"id": identifier, "directory": urllib.parse.unquote(files[0][len("file://"):]),
                             "title": title or preview, "createdAt": iso(born)})
    return sessions


def opencode(home):
    rows = query(os.path.join(home, ".local/share/opencode/opencode.db"),
                 "select id, directory, title, time_created from session_v2 where coalesce(parent_id, '') = '' "
                 "and time_archived is null order by time_updated desc")
    return [{"id": i, "directory": d, "title": t, "createdAt": iso(c / 1000)} for i, d, t, c in rows]


def first_text(content):
    if isinstance(content, str):
        return content
    for block in content or []:
        if isinstance(block, dict) and block.get("type") == "text":
            return block.get("text", "")
    return ""


def claude(home):
    sessions = []
    projects = os.path.join(home, ".claude/projects")
    for project in sorted(os.listdir(projects)):
        folder = os.path.join(projects, project)
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".jsonl"):
                continue
            directory, title, first, last = None, None, None, ""
            with open(os.path.join(folder, name), encoding="utf-8") as handle:
                for line in handle:
                    record = json.loads(line)
                    directory = directory or record.get("cwd")
                    stamp = record.get("timestamp")
                    if stamp:
                        first = first or stamp
                        last = max(last, stamp)
                    if title is None and record.get("type") == "user":
                        title = first_text((record.get("message") or {}).get("content"))
            created = first[:19] + "Z" if first else None
            sessions.append({"id": name[:-len(".jsonl")], "directory": directory, "title": title or "",
                             "createdAt": created, "updatedAt": last[:19] + "Z" if last else None, "_last": last})
    sessions.sort(key=lambda session: session.pop("_last"), reverse=True)
    return sessions


READERS = {"codex": codex, "antigravity": antigravity, "opencode": opencode, "claude": claude}


def expectations(harness, home):
    return {"harness": harness, "sessions": READERS[harness](home)}


if __name__ == "__main__":
    print(json.dumps(expectations(sys.argv[1], sys.argv[2]), indent=2, ensure_ascii=False))

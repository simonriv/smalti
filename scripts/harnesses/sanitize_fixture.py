#!/usr/bin/env python3
"""Turns a recorded harness home (Codex, Antigravity, OpenCode, Claude) into a committable fixture for F6.

Recordings run under fixed paths (/private/tmp/smalti-fx/<harness>/…), so paths are not personal and stay as they
are: harnesses keep them inside protobuf blobs whose length prefixes a rewrite would break. What is personal is
removed or replaced:
- secrets and noise are not copied (login tokens, installation ids, logs, crashes, caches, daemon binaries);
- personal markers are replaced in text files and in the text columns of SQLite databases (copied with the backup
  API, so a live WAL is folded in, then vacuumed so no old page keeps them);
- any file that still holds a marker, in any case, stops the run naming the file.

Usage: sanitize_fixture.py <recorded-dir> <fixture-dir> --markers scripts/observatory/markers.local
"""

import argparse
import os
import re
import shutil
import sqlite3
import sys

DROPPED_NAMES = {"antigravity-oauth-token", "auth.json", "installation_id", "credential-user-scope",
                 "oauth_creds.json", "google_accounts.json", ".DS_Store"}
DROPPED_DIRECTORIES = {"log", "logs", "crashes", "packages", ".tmp", "marketplaces", "Library", "presence", "snapshot", "shell", "skills", "builtin"}
DROPPED_PATTERNS = [re.compile(pattern) for pattern in (r"\.log$", r"\.lock$", r"^logs_\d+\.sqlite", r"-(wal|shm)$")]
SQLITE_HEADER = b"SQLite format 3\x00"
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
FIXTURE_EMAIL = "fixture@example.invalid"


class PersonalDataError(Exception):
    pass


def replacement(marker):
    if "@" in marker:
        return "fixture@example.invalid"
    return "Fixture User" if " " in marker else "fixture"


def is_dropped(relative):
    parts = relative.split(os.sep)
    name = parts[-1]
    return (name in DROPPED_NAMES or any(part in DROPPED_DIRECTORIES for part in parts[:-1])
            or any(pattern.search(name) for pattern in DROPPED_PATTERNS))


INSTALLATION_ID = re.compile(r'(installation_(?:uuid|id)"?\s*[:=]\s*")[^"]*(")')
ZERO_UUID = "00000000-0000-4000-8000-000000000000"


def replace_markers(text, markers):
    text = INSTALLATION_ID.sub(lambda match: match.group(1) + ZERO_UUID + match.group(2), text)
    text = EMAIL.sub(lambda match: match.group(0) if match.group(0) == FIXTURE_EMAIL else FIXTURE_EMAIL, text)
    for marker in markers:
        text = re.sub(re.escape(marker), replacement(marker), text, flags=re.IGNORECASE)
    return text


def copy_sqlite(source, target, markers):
    with sqlite3.connect(f"file:{source}?mode=ro", uri=True) as reader, sqlite3.connect(target) as writer:
        reader.backup(writer)
    with sqlite3.connect(target) as db:
        db.execute("pragma journal_mode=delete")
        db.create_function("smalti_clean", 1, lambda value: replace_markers(value, markers)
                           if isinstance(value, str) else value, deterministic=True)
        tables = [row[0] for row in db.execute("select name from sqlite_master where type='table' "
                                               "and name not like 'sqlite_%'")]
        if "kv" in tables:
            db.execute("delete from kv where key like 'models-dev:%'")
        for table in tables:
            columns = [row[1] for row in db.execute(f'pragma table_info("{table}")')]
            for column in columns:
                db.execute(f'update "{table}" set "{column}" = smalti_clean("{column}") '
                           f'where typeof("{column}") = \'text\'')
    with sqlite3.connect(target) as db:
        db.execute("vacuum")


def copy_file(source, target, markers):
    with open(source, "rb") as handle:
        data = handle.read()
    if data.startswith(SQLITE_HEADER):
        copy_sqlite(source, target, markers)
        return
    if b"\x00" not in data:
        try:
            data = replace_markers(data.decode("utf-8"), markers).encode("utf-8")
        except UnicodeDecodeError:
            pass
    with open(target, "wb") as handle:
        handle.write(data)


def scan(path, relative, markers):
    with open(path, "rb") as handle:
        data = handle.read().lower()
    for marker in markers:
        if marker.lower().encode() in data:
            raise PersonalDataError(f"{relative} still holds a personal marker")
    for match in re.finditer(EMAIL.pattern.encode(), data):
        if match.group(0) != FIXTURE_EMAIL.encode():
            raise PersonalDataError(f"{relative} still holds an email address")


def sanitize_tree(source, target, markers):
    if os.path.exists(target):
        shutil.rmtree(target)
    for directory, _, files in os.walk(source):
        for name in files:
            path = os.path.join(directory, name)
            relative = os.path.relpath(path, source)
            if is_dropped(relative) or os.path.islink(path):
                continue
            destination = os.path.join(target, relative)
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            copy_file(path, destination, markers)
            scan(destination, relative, markers)


def read_markers(path):
    with open(path, encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip() and not line.startswith("#")]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("--markers", required=True)
    arguments = parser.parse_args()
    try:
        sanitize_tree(arguments.source, arguments.target, read_markers(arguments.markers))
    except PersonalDataError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

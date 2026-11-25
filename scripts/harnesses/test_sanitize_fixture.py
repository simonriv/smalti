"""Tests for scripts/harnesses/sanitize_fixture.py: a recorded harness home becomes a committable fixture."""

import os
import sqlite3
import tempfile
import unittest

from sanitize_fixture import PersonalDataError, sanitize_tree

MARKERS = ["Simon Example", "simon@example.com", "simonuser"]


class SanitizeTree(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.source = os.path.join(self.root, "in")
        self.target = os.path.join(self.root, "out")
        os.makedirs(self.source)

    def write(self, relative, content):
        path = os.path.join(self.source, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(content if isinstance(content, bytes) else content.encode())
        return path

    def read(self, relative):
        with open(os.path.join(self.target, relative), "rb") as handle:
            return handle.read()

    def test_drops_secrets_and_noise(self):
        for name in ["antigravity-cli/antigravity-oauth-token", "codex/auth.json", "codex/installation_id",
                     "antigravity-cli/log/cli.log", "codex/packages/bin/codex", "antigravity-cli/crashes/a.txt",
                     "antigravity-cli/cache/marketplaces/x.json", "codex/.tmp/plugins/a.json",
                     "opencode/snapshot/global/abc/HEAD", "opencode/shell/global/x",
                     "codex/skills/.system/a/SKILL.md", "antigravity-cli/builtin/skills/b.md"]:
            self.write(name, "x")
        self.write("codex/config.toml", "model = 'qwen3:4b'\n")
        sanitize_tree(self.source, self.target, MARKERS)
        kept = sorted(os.path.relpath(os.path.join(d, f), self.target)
                      for d, _, files in os.walk(self.target) for f in files)
        self.assertEqual(kept, ["codex/config.toml"])

    def test_replaces_markers_in_text_files(self):
        self.write("a/state.pbtxt", 'email: "simon@example.com"\nname: "Simon Example"\n')
        sanitize_tree(self.source, self.target, MARKERS)
        self.assertEqual(self.read("a/state.pbtxt"), b'email: "fixture@example.invalid"\nname: "Fixture User"\n')

    def test_replaces_markers_in_sqlite_text_columns(self):
        path = self.write("db/sessions.db", b"")
        os.remove(path)
        with sqlite3.connect(path) as db:
            db.execute("create table t (id text, title text, n integer)")
            db.execute("insert into t values ('1', 'hola simonuser', 3)")
        sanitize_tree(self.source, self.target, MARKERS)
        with sqlite3.connect(os.path.join(self.target, "db/sessions.db")) as db:
            self.assertEqual(db.execute("select title, n from t").fetchone(), ("hola fixture", 3))

    def test_fails_when_marker_remains_in_binary(self):
        self.write("b/blob.pb", b"\x00\x12\x05simon@example.com\xff")
        with self.assertRaises(PersonalDataError) as raised:
            sanitize_tree(self.source, self.target, MARKERS)
        self.assertIn("b/blob.pb", str(raised.exception))

    def test_leaves_other_bytes_untouched(self):
        payload = bytes(range(256)) * 4
        self.write("c/data.bin", payload)
        self.write("c/text.jsonl", '{"cwd":"/private/tmp/smalti-fx/work-a"}\n')
        sanitize_tree(self.source, self.target, MARKERS)
        self.assertEqual(self.read("c/data.bin"), payload)
        self.assertEqual(self.read("c/text.jsonl"), b'{"cwd":"/private/tmp/smalti-fx/work-a"}\n')

    def test_sqlite_wal_is_checkpointed_into_the_copy(self):
        path = os.path.join(self.source, "w/live.db")
        os.makedirs(os.path.dirname(path))
        db = sqlite3.connect(path)
        db.execute("pragma journal_mode=wal")
        db.execute("create table t (x text)")
        db.execute("insert into t values ('pending')")
        db.commit()
        sanitize_tree(self.source, self.target, MARKERS)
        db.close()
        self.assertFalse(os.path.exists(os.path.join(self.target, "w/live.db-wal")))
        with sqlite3.connect(os.path.join(self.target, "w/live.db")) as copy:
            self.assertEqual(copy.execute("select x from t").fetchone(), ("pending",))

    def test_any_email_is_replaced_in_text_and_sqlite(self):
        self.write("e/state.json", '{"user":"someone.else+x@mail.example.org"}')
        path = os.path.join(self.source, "e/s.db")
        with sqlite3.connect(path) as db:
            db.execute("create table t (who text)")
            db.execute("insert into t values ('Hecho por a.b@corp.example.net hoy')")
        sanitize_tree(self.source, self.target, MARKERS)
        self.assertEqual(self.read("e/state.json"), b'{"user":"fixture@example.invalid"}')
        with sqlite3.connect(os.path.join(self.target, "e/s.db")) as db:
            self.assertEqual(db.execute("select who from t").fetchone(), ("Hecho por fixture@example.invalid hoy",))

    def test_fails_when_any_email_remains_in_binary(self):
        self.write("f/blob.pb", b"\x00\x12other.person@mail.example.org\xff")
        with self.assertRaises(PersonalDataError):
            sanitize_tree(self.source, self.target, MARKERS)

    def test_drops_cached_model_catalog_rows(self):
        path = os.path.join(self.source, "o/opencode.db")
        os.makedirs(os.path.dirname(path))
        with sqlite3.connect(path) as db:
            db.execute("create table kv (key text, value text)")
            db.executemany("insert into kv values (?, ?)", [("models-dev:v2:catalog", "x" * 1000),
                                                           ("models-dev:v2:catalog:meta", "m"), ("other", "keep")])
        sanitize_tree(self.source, self.target, MARKERS)
        with sqlite3.connect(os.path.join(self.target, "o/opencode.db")) as db:
            self.assertEqual(db.execute("select key from kv").fetchall(), [("other",)])


if __name__ == "__main__":
    unittest.main()

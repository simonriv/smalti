"""Tests for fixture_expectations.py: the independent oracle of which sessions each fixture holds."""

import json
import os
import sqlite3
import tempfile
import unittest

from fixture_expectations import expectations



class Expectations(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()

    def db(self, relative, sql, rows):
        path = os.path.join(self.home, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with sqlite3.connect(path) as db:
            db.execute(sql)
            table = sql.split()[2]
            for row in rows:
                db.execute(f"insert into {table} values ({','.join('?' * len(row))})", row)

    def test_codex_lists_unarchived_threads_newest_first(self):
        self.db("codex/state_5.sqlite", "create table threads (id text, cwd text, title text, created_at integer, "
                "updated_at integer, archived integer)",
                [("a", "/w/a", "A", 5, 10, 0), ("b", "/w/b", "B", 6, 20, 0), ("c", "/w/c", "C", 7, 30, 1)])
        sessions = expectations("codex", self.home)["sessions"]
        self.assertEqual([s["id"] for s in sessions], ["b", "a"])
        self.assertEqual(sessions[0]["createdAt"], "1970-01-01T00:00:06Z")

    def test_antigravity_reads_directory_from_workspace_uri(self):
        self.db(".gemini/antigravity-cli/conversation_summaries.db", "create table conversation_summaries "
                "(conversation_id text, title text, preview text, workspace_uris text, last_modified_time text)",
                [("x", "", "hola A", json.dumps(["file:///w/a%20b"]), "2026-11-24 10:00:00+00:00")])
        conversation = os.path.join(self.home, ".gemini/antigravity-cli/conversations/x.db")
        os.makedirs(os.path.dirname(conversation))
        open(conversation, "w").close()
        session = expectations("antigravity", self.home)["sessions"][0]
        self.assertEqual((session["id"], session["directory"], session["title"]), ("x", "/w/a b", "hola A"))
        self.assertRegex(session["createdAt"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

    def test_opencode_skips_children_and_archived(self):
        self.db(".local/share/opencode/opencode.db", "create table session_v2 (id text, parent_id text, "
                "directory text, title text, time_created integer, time_updated integer, time_archived integer)",
                [("p", None, "/w/a", "P", 2000, 5, None), ("k", "p", "/w/a", "K", 1, 6, None),
                 ("z", None, "/w/a", "Z", 1, 7, 9)])
        sessions = expectations("opencode", self.home)["sessions"]
        self.assertEqual([s["id"] for s in sessions], ["p"])
        self.assertEqual(sessions[0]["createdAt"], "1970-01-01T00:00:02Z")

    def test_claude_reads_top_level_transcripts(self):
        project = os.path.join(self.home, ".claude/projects/-w-a")
        os.makedirs(os.path.join(project, "s1/subagents"))
        with open(os.path.join(project, "s1.jsonl"), "w") as handle:
            handle.write(json.dumps({"type": "user", "cwd": "/w/a", "timestamp": "2026-11-24T10:00:00Z",
                                     "message": {"content": "hola"}}) + "\n")
        with open(os.path.join(project, "s1/subagents/agent-x.jsonl"), "w") as handle:
            handle.write("{}\n")
        sessions = expectations("claude", self.home)["sessions"]
        self.assertEqual([(s["id"], s["directory"], s["title"]) for s in sessions], [("s1", "/w/a", "hola")])
        self.assertEqual(sessions[0]["createdAt"], "2026-11-24T10:00:00Z")
        self.assertEqual(sessions[0]["updatedAt"], "2026-11-24T10:00:00Z")


if __name__ == "__main__":
    unittest.main()

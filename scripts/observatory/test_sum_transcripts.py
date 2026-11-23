"""Tests for the independent token oracle of scripts/observatory/sum_transcripts.py."""

import json
import tempfile
import unittest
from pathlib import Path

from sum_transcripts import summarize


def assistant(message_id, at, output=100, inp=10, read=0, write=0, model="claude-haiku-5-5", breakdown=True):
    usage = {"input_tokens": inp, "output_tokens": output, "cache_read_input_tokens": read,
             "cache_creation_input_tokens": write}
    if breakdown:
        usage["cache_creation"] = {"ephemeral_5m_input_tokens": write, "ephemeral_1h_input_tokens": 0}
    return {"type": "assistant", "timestamp": at, "message": {"id": message_id, "model": model, "usage": usage}}


class Oracle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = Path(self.tmp.name) / "projects" / "-fixture-work"
        self.projects.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, relative, records):
        path = self.projects / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(r) + "\n" for r in records))

    def total(self, **kwargs):
        return summarize(self.projects.parent, **kwargs)["total"]

    def test_repeated_message_counts_once(self):
        self.write("s1.jsonl", [assistant("m1", "2026-11-18T10:00:00Z"), assistant("m1", "2026-11-18T10:00:01Z")])
        self.assertEqual(self.total()["output"], 100)

    def test_subagent_adds_to_parent(self):
        self.write("s1.jsonl", [assistant("m1", "2026-11-18T10:00:00Z")])
        self.write("s1/subagents/agent-a.jsonl", [assistant("m2", "2026-11-18T10:00:05Z", output=7)])
        result = summarize(self.projects.parent)
        self.assertEqual(result["sessions"]["s1"]["output"], 107)
        self.assertEqual(list(result["sessions"]), ["s1"])

    def test_synthetic_is_ignored(self):
        self.write("s1.jsonl", [assistant("m1", "2026-11-18T10:00:00Z", output=50, model="<synthetic>")])
        self.assertEqual(self.total()["output"], 0)

    def test_since_until_filter_by_timestamp(self):
        self.write("s1.jsonl", [assistant("a", "2026-11-17T23:59:00Z", output=1),
                                assistant("b", "2026-11-18T00:01:00Z", output=2)])
        self.assertEqual(self.total(since="2026-11-18T00:00:00Z")["output"], 2)
        self.assertEqual(self.total(until="2026-11-18T00:00:00Z")["output"], 1)

    def test_missing_breakdown_counts_as_5m(self):
        self.write("s1.jsonl", [assistant("a", "2026-11-18T10:00:00Z", write=40, breakdown=False)])
        total = self.total()
        self.assertEqual((total["cacheWrite5m"], total["cacheWrite1h"]), (40, 0))

    def test_global_dedupe_counts_a_copied_message_once(self):
        self.write("a.jsonl", [assistant("m1", "2026-11-18T10:00:00Z")])
        self.write("b.jsonl", [assistant("m1", "2026-11-18T10:00:00Z"), assistant("m2", "2026-11-18T10:01:00Z")])
        result = summarize(self.projects.parent, global_dedupe=True)
        self.assertEqual(result["total"]["output"], 200)

    def test_fork_leaves_copied_tokens_with_its_source(self):
        fork = {"type": "derived-from", "sessionId": "0fork",
                "sessions": [{"type": "claude_code_session", "id": "source", "via": "fork"}]}
        self.write("0fork.jsonl", [fork, assistant("m1", "2026-11-18T10:00:00Z"), assistant("m2", "2026-11-18T10:01:00Z", output=5)])
        self.write("source.jsonl", [assistant("m1", "2026-11-18T10:00:00Z")])
        sessions = summarize(self.projects.parent, global_dedupe=True)["sessions"]
        self.assertEqual((sessions["source"]["output"], sessions["0fork"]["output"]), (100, 5))

    def test_unreadable_line_is_skipped(self):
        path = self.projects / "s1.jsonl"
        path.write_text(json.dumps(assistant("a", "2026-11-18T10:00:00Z")) + "\n{broken\n")
        self.assertEqual(self.total()["output"], 100)


if __name__ == "__main__":
    unittest.main()

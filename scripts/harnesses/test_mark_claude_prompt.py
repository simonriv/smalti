"""Tests for mark_claude_prompt.py: only the first user prompt changes."""

import json
import os
import tempfile
import unittest

from mark_claude_prompt import mark


class Mark(unittest.TestCase):
    def test_marks_every_user_prompt_and_nothing_else(self):
        path = os.path.join(tempfile.mkdtemp(), "s.jsonl")
        records = [{"type": "system"}, {"type": "user", "message": {"content": "<redacted>"}},
                   {"type": "user", "message": {"content": [{"type": "text", "text": "<redacted>"}]}},
                   {"type": "user", "message": {"content": [{"type": "tool_result", "content": "out"}]}}]
        with open(path, "w") as handle:
            handle.write("\n".join(json.dumps(r) for r in records) + "\n")
        mark(path, "fixture prompt A")
        with open(path) as handle:
            lines = [json.loads(line) for line in handle]
        self.assertEqual(lines[1]["message"]["content"], "fixture prompt A")
        self.assertEqual(lines[2]["message"]["content"][0]["text"], "fixture prompt A")
        self.assertEqual(lines[3]["message"]["content"][0], {"type": "tool_result", "content": "out"})
        self.assertEqual(lines[0], {"type": "system"})


if __name__ == "__main__":
    unittest.main()

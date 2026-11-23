"""Tests for scripts/observatory/sanitize_fixture.py: real transcripts keep their tokens and lose personal text."""

import json
import unittest

from sanitize_fixture import PersonalDataError, sanitize_line, scan


WORK = "/var/folders/xy/T/rec.123"
HOME = "/Users/someone"


def clean(record):
    return json.loads(sanitize_line(json.dumps(record), work=WORK, home=HOME))


class Sanitize(unittest.TestCase):
    def test_assistant_keeps_id_model_usage_and_tool_use(self):
        record = {"type": "assistant", "timestamp": "t", "sessionId": "s", "cwd": WORK + "/a",
                  "message": {"id": "m1", "model": "claude-haiku-5-5", "usage": {"output_tokens": 7},
                              "content": [{"type": "tool_use", "id": "u1", "name": "Bash", "input": {"command": "ls"}},
                                          {"type": "thinking", "thinking": "secret"}]}}
        result = clean(record)
        self.assertEqual(result["message"]["usage"], {"output_tokens": 7})
        self.assertEqual(result["message"]["content"][0]["input"], {"command": "ls"})
        self.assertEqual(result["message"]["content"][1]["thinking"], "")
        self.assertEqual(result["cwd"], "/fixture/work/a")

    def test_user_prompt_text_is_redacted_but_tool_results_stay(self):
        record = {"type": "user", "timestamp": "t", "message": {"content": [
            {"type": "text", "text": "<system-reminder>CLAUDE.md of a person</system-reminder>"},
            {"type": "tool_result", "tool_use_id": "u1", "is_error": True, "content": "Exit code 1"}]},
            "toolUseResult": {"structuredPatch": [{"lines": ["+a"]}], "stdout": "private"}}
        result = clean(record)
        self.assertEqual(result["message"]["content"][0]["text"], "<redacted>")
        self.assertEqual(result["message"]["content"][1]["is_error"], True)
        self.assertEqual(result["toolUseResult"], {"structuredPatch": [{"lines": ["+a"]}]})

    def test_string_user_content_is_redacted(self):
        self.assertEqual(clean({"type": "user", "message": {"content": "my prompt"}})["message"]["content"], "<redacted>")

    def test_other_types_keep_only_their_type(self):
        self.assertEqual(clean({"type": "attachment", "attachment": {"content": "private"}}),
                         {"type": "attachment", "redacted": True})

    def test_compact_boundary_keeps_metadata(self):
        record = {"type": "system", "subtype": "compact_boundary", "timestamp": "t",
                  "compactMetadata": {"preTokens": 9, "postTokens": 1, "trigger": "auto", "preCompactDiscoveredTools": ["x"]}}
        self.assertEqual(clean(record)["compactMetadata"], {"preTokens": 9, "postTokens": 1, "trigger": "auto"})

    def test_home_path_is_rewritten(self):
        record = {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "u1", "content": HOME + "/notes.txt"}]}}
        self.assertEqual(clean(record)["message"]["content"][0]["content"], "/fixture/home/notes.txt")

    def test_derived_from_keeps_its_source_sessions(self):
        record = {"type": "derived-from", "v": 1, "sessionId": "fork",
                  "sessions": [{"type": "claude_code_session", "id": "source", "via": "fork"}]}
        self.assertEqual(clean(record), record)

    def test_scan_ignores_accents_and_case(self):
        with self.assertRaises(PersonalDataError):
            scan('{"text": "JOSE dijo"}', markers=["José"])
        with self.assertRaises(PersonalDataError):
            scan('{"text": "contexto de José"}', markers=["jose"])

    def test_scan_rejects_personal_markers(self):
        with self.assertRaises(PersonalDataError):
            scan('{"text": "contexto de José"}', markers=["José"])
        scan('{"text": "hola"}', markers=["José"])


if __name__ == "__main__":
    unittest.main()

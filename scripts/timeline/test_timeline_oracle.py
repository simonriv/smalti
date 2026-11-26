import json
import os
import unittest

import timeline_oracle as oracle

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CLAUDE_F6 = os.path.join(REPO, "Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/claude/home/.claude/projects")
CLAUDE_F3 = os.path.join(REPO, "Packages/ClaudeTelemetryAdapter/Tests/ClaudeTelemetryAdapterTests/Fixtures/real/projects")
SYNTHETIC = os.path.join(REPO, "Packages/ClaudeHarnessAdapter/Tests/ClaudeHarnessAdapterTests/Fixtures/timeline-synthetic/image.jsonl")
CODEX_TL = os.path.join(REPO, "Packages/CodexHarnessAdapter/Tests/CodexHarnessAdapterTests/Fixtures/codex-timeline/home/codex/sessions")


def kinds(items):
    return [(i["kind"], i["who"]) for i in items]


def only_file(folder):
    for root, _, files in os.walk(folder):
        for name in files:
            if name.endswith(".jsonl"):
                return os.path.join(root, name)
    raise AssertionError(f"no transcript in {folder}")


class ClaudeTests(unittest.TestCase):
    def test_work_b_pairs_tools_and_keeps_order(self):
        path = os.path.join(CLAUDE_F6, "-private-tmp-smalti-fx-claude-work-b", "7b1f7b2a-0c81-4aa0-8229-85de52add2e8.jsonl")
        items = oracle.claude(path)
        self.assertEqual(kinds(items), [
            ("prompt", "user"), ("call", "Bash"), ("output", "Bash"), ("call", "Bash"), ("output", "Bash"),
            ("reply", "agent"), ("prompt", "user"), ("call", "Read"), ("output", "Read"), ("reply", "agent"),
            ("prompt", "user"), ("reply", "agent")])
        self.assertEqual(items[2]["text"], "Exit code 127\n(eval):1: command not found: eza")
        self.assertEqual(items[1]["text"], '{"command":"ls","description":"List files in current directory"}')

    def test_subagent_items_carry_their_scope(self):
        folder = os.path.join(CLAUDE_F3, "-fixture-work-c")
        items = oracle.claude(os.path.join(folder, "30e70a4d-2f90-4085-be04-73997b68c564.jsonl"),
                              os.path.join(folder, "30e70a4d-2f90-4085-be04-73997b68c564", "subagents"))
        scopes = {i["scope"] for i in items}
        self.assertEqual(scopes, {"main", "a83a716973cc0ff1d"})
        sub = [i for i in items if i["scope"] != "main"]
        self.assertEqual(sub[0]["kind"], "prompt")
        self.assertIn(("output", "Bash"), kinds(sub))

    def test_synthetic_images_meta_summary_and_thinking(self):
        items = oracle.claude(SYNTHETIC)
        self.assertEqual(kinds(items), [
            ("prompt", "user"), ("image", "user"), ("call", "Read"), ("output", "Read"), ("image", "Read"),
            ("reply", "agent"), ("compaction", "system"), ("prompt", "user"), ("call", "Bash"), ("output", "Bash")])
        self.assertEqual(items[0]["text"], '¿Qué ves en la captura?\nLínea dos con "comillas" y \\barra\nSegundo bloque')
        self.assertEqual(items[1]["text"], "image/png")
        self.assertEqual(items[2]["text"], '{"file_path":"/fixture/work/s/shot.png","limit":5}')
        self.assertEqual(items[3]["text"], "Imagen leída")
        self.assertEqual(items[5]["text"], "Un píxel rojo. 🙂")
        self.assertTrue(items[7]["text"].startswith("<command-name>/clear</command-name>"))
        self.assertEqual(items[8]["text"], '{"command":"exit 3","description":"Falla"}')


class CodexTests(unittest.TestCase):
    def test_timeline_fixture_skips_context_and_pairs_calls(self):
        items = oracle.codex(only_file(CODEX_TL))
        self.assertEqual(kinds(items), [
            ("prompt", "user"), ("call", "exec_command"), ("output", "exec_command"), ("reply", "agent"),
            ("prompt", "user"), ("call", "exec_command"), ("output", "exec_command"), ("reply", "agent")])
        self.assertEqual(items[0]["text"], "Run the shell command: ls")
        self.assertIn("Process exited with code 1", items[6]["text"])
        self.assertTrue(items[1]["text"].startswith('{"cmd":"ls"'))

    def test_compacted_and_custom_tools(self):
        lines = [
            {"type": "response_item", "payload": {"type": "message", "role": "developer", "content": [{"type": "input_text", "text": "x"}]}},
            {"type": "response_item", "payload": {"type": "custom_tool_call", "name": "apply_patch", "input": "*** Begin Patch", "call_id": "c1"}},
            {"type": "response_item", "payload": {"type": "custom_tool_call_output", "call_id": "c1", "output": {"content": "Done"}}},
            {"type": "compacted", "payload": {"message": ""}},
            {"type": "event_msg", "payload": {"type": "user_message", "message": "dup"}},
        ]
        path = os.path.join(os.environ.get("TMPDIR", "."), "oracle-codex-test.jsonl")
        with open(path, "w") as handle:
            handle.write("\n".join(json.dumps(line) for line in lines) + "\n")
        try:
            items = oracle.codex(path)
        finally:
            os.remove(path)
        self.assertEqual([(i["kind"], i["who"], i["text"]) for i in items], [
            ("call", "apply_patch", "*** Begin Patch"), ("output", "apply_patch", "Done"), ("compaction", "system", "")])


if __name__ == "__main__":
    unittest.main()

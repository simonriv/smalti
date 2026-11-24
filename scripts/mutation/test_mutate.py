"""Tests for the mutant generator of scripts/mutation/mutate.py."""

import tempfile
import unittest
from pathlib import Path

from mutate import (
    kill_strays,
    run,
    Mutant,
    changed_sources,
    missing_sources_message,
    mutants_for_line,
    mutants_for_source,
    source_files,
)


def replacements(line):
    return [m.replacement for m in mutants_for_line(line, path="X.swift", line_number=1)]


class RelationalOperators(unittest.TestCase):
    def test_equality_flips_to_inequality(self):
        self.assertIn("if a != b {", replacements("if a == b {"))

    def test_inequality_flips_to_equality(self):
        self.assertIn("if a == b {", replacements("if a != b {"))

    def test_less_than_becomes_greater_or_equal(self):
        self.assertIn("x >= 1", replacements("x < 1"))

    def test_greater_or_equal_becomes_less_than(self):
        self.assertIn("x < 1", replacements("x >= 1"))

    def test_generic_angle_brackets_are_not_mutated(self):
        self.assertEqual(replacements("let s: AsyncStream<TerminalEvent> = x"), [])

    def test_return_arrow_is_not_mutated(self):
        self.assertEqual(replacements("func f() -> Pane {"), [])


class LogicalAndBoolean(unittest.TestCase):
    def test_and_becomes_or(self):
        self.assertIn("a || b", replacements("a && b"))

    def test_or_becomes_and(self):
        self.assertIn("a && b", replacements("a || b"))

    def test_true_becomes_false(self):
        self.assertIn("isRunning = false", replacements("isRunning = true"))

    def test_negation_is_removed(self):
        self.assertIn("guard path.hasPrefix(\"/\") else", replacements("guard !path.hasPrefix(\"/\") else"))

    def test_inequality_bang_is_not_treated_as_negation(self):
        self.assertNotIn("a = b", replacements("a != b"))


class Arithmetic(unittest.TestCase):
    def test_plus_becomes_minus(self):
        self.assertIn("index - 1", replacements("index + 1"))

    def test_minus_becomes_plus(self):
        self.assertIn("count + 1", replacements("count - 1"))

    def test_shift_right_becomes_shift_left(self):
        self.assertIn("value << 16", replacements("value >> 16"))


class AssignmentRemoval(unittest.TestCase):
    def test_plain_assignment_is_removed(self):
        self.assertIn("        ", replacements("        updated.title = title"))

    def test_assignment_after_case_label_becomes_break(self):
        self.assertIn(
            "        case .titleChanged(let title): break",
            replacements("        case .titleChanged(let title): updated.title = title"))

    def test_declarations_are_not_removed(self):
        self.assertEqual(replacements("        let value = other"), [])
        self.assertEqual(replacements("        var updated = self"), [])

    def test_initializer_member_copy_is_not_removed(self):
        self.assertEqual(replacements("        self.engine = engine"), [])

    def test_comparison_is_not_an_assignment(self):
        self.assertNotIn("", replacements("        isReady == done"))


class Exclusions(unittest.TestCase):
    def test_comment_lines_are_skipped(self):
        self.assertEqual(replacements("// a == b"), [])

    def test_trailing_comment_is_not_mutated(self):
        self.assertEqual(replacements("let x = 1  // a == b"), [])

    def test_string_literals_are_not_mutated(self):
        self.assertEqual(replacements('let s = "a == b && true"'), [])

    def test_import_lines_are_skipped(self):
        self.assertEqual(replacements("import Foundation"), [])


class SourceLevel(unittest.TestCase):
    def test_each_mutant_changes_exactly_one_line(self):
        source = "let a = x == y\nlet b = p && q\n"
        mutants = mutants_for_source(source, path="X.swift")
        self.assertEqual([m.line_number for m in mutants], [1, 2])
        self.assertEqual(mutants[0].apply(source), "let a = x != y\nlet b = p && q\n")

    def test_two_operators_on_one_line_give_two_mutants(self):
        mutants = mutants_for_line("a == b && c", path="X.swift", line_number=3)
        self.assertEqual(
            sorted(m.replacement for m in mutants), sorted(["a != b && c", "a == b || c"]))

    def test_mutant_describes_location_and_operator(self):
        mutant = Mutant(path="Domain/Pane.swift", line_number=7, original="a == b", replacement="a != b",
                        operator="== → !=")
        self.assertEqual(mutant.describe(), "Domain/Pane.swift:7 == → !=")


class SourceFiles(unittest.TestCase):
    def test_only_the_package_own_target_is_mutated(self):
        with tempfile.TemporaryDirectory() as scratch:
            package = Path(scratch) / "SmaltiCore"
            for relative in ("SmaltiCore/Domain/A.swift", "SmaltiCoreTestSupport/Fake.swift", "Other/B.swift"):
                file = package / "Sources" / relative
                file.parent.mkdir(parents=True)
                file.write_text("")

            found = source_files(package)

            self.assertEqual(found, [package / "Sources" / "SmaltiCore" / "Domain" / "A.swift"])


class MissingSources(unittest.TestCase):
    def test_no_files_is_an_error_naming_the_directory(self):
        message = missing_sources_message(Path("/x/SmaltiCore"), [])

        self.assertEqual(message, "no sources under Sources/SmaltiCore")

    def test_some_files_is_not_an_error(self):
        self.assertIsNone(missing_sources_message(Path("/x/SmaltiCore"), [Path("A.swift")]))


if __name__ == "__main__":
    unittest.main()


class ChangedSources(unittest.TestCase):
    """--changed-since: during a phase only the sources the branch touched are mutated."""

    def setUp(self):
        self.root = Path("/repo")
        self.package = self.root / "Packages/SmaltiCore"
        self.a = self.package / "Sources/SmaltiCore/A.swift"
        self.b = self.package / "Sources/SmaltiCore/Domain/B.swift"

    def test_keeps_only_sources_named_by_git(self):
        changed = ["Packages/SmaltiCore/Sources/SmaltiCore/Domain/B.swift", "App/Smalti/X.swift"]

        self.assertEqual(changed_sources([self.a, self.b], changed, self.root), [self.b])

    def test_nothing_changed_keeps_nothing(self):
        self.assertEqual(changed_sources([self.a, self.b], [], self.root), [])

    def test_a_test_file_change_does_not_select_a_source(self):
        changed = ["Packages/SmaltiCore/Tests/SmaltiCoreTests/A.swift"]

        self.assertEqual(changed_sources([self.a], changed, self.root), [])



class RunnerTimeout(unittest.TestCase):
    """A hung test helper is a grandchild of `swift test`: on timeout the whole group goes, never an orphan."""

    def test_timeout_kills_grandchildren(self):
        import os
        import time

        with tempfile.TemporaryDirectory() as folder:
            pid_file = Path(folder) / "grandchild.pid"
            script = f"sleep 60 & echo $! > {pid_file}; wait"

            result = run(["/bin/sh", "-c", script], Path(folder), timeout=1)

            self.assertIsNone(result)
            grandchild = int(pid_file.read_text())
            time.sleep(0.2)
            with self.assertRaises(ProcessLookupError):
                os.kill(grandchild, 0)


class StrayHelpers(unittest.TestCase):
    """swiftpm's test helper runs in a process group of its own: after a mutant, any process whose command line
    names that mutation's package copy is killed, wherever it lives."""

    def test_kill_strays_ends_processes_naming_the_package(self):
        import os
        import subprocess
        import time

        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder) / "smalti-mutation-test" / "SmaltiCore"
            stray = subprocess.Popen(
                ["/bin/sh", "-c", f"exec -a 'helper {marker}' sleep 60"], start_new_session=True)
            other = subprocess.Popen(["/bin/sleep", "60"], start_new_session=True)
            time.sleep(0.2)

            kill_strays(marker)
            time.sleep(0.2)

            self.assertIsNotNone(stray.poll())
            self.assertIsNone(other.poll())
            other.kill()
            os.waitpid(other.pid, 0)

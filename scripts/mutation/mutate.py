#!/usr/bin/env python3
"""Minimal mutation tester for Smalti's Swift packages.

Muter v16 does not apply mutations with SwiftPM + Swift Testing (muter issue #321), so this script does the
job for pure-Swift code: it copies a package to a temporary directory, applies one source mutation at a time,
and runs the package's tests. A mutant the tests catch is "killed"; one they miss "survives".

Usage:
    scripts/mutation/mutate.py [--package Packages/SmaltiCore] [--min-score 80] [--timeout 120] [--changed-since REF]

--changed-since mutates only the package sources that differ from REF (committed, uncommitted or untracked): the
quick run during a phase. The full run, without it, closes the phase.

Prints one line per mutant as "[n/total] ok|FAIL <file:line operator>" (total fixed from the first line) and
exits non-zero when the mutation score falls below --min-score. The real sources are never modified.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

# (operator label, pattern, replacement). Binary operators need surrounding spaces so generics (`Foo<Bar>`),
# return arrows (`->`) and ranges (`0..<n`) are never touched.
OPERATORS: list[tuple[str, re.Pattern[str], str]] = [
    ("== → !=", re.compile(r"(?<=\s)==(?=\s)"), "!="),
    ("!= → ==", re.compile(r"(?<=\s)!=(?=\s)"), "=="),
    ("< → >=", re.compile(r"(?<=\s)<(?=\s)"), ">="),
    ("> → <=", re.compile(r"(?<=\s)>(?=\s)"), "<="),
    ("<= → >", re.compile(r"(?<=\s)<=(?=\s)"), ">"),
    (">= → <", re.compile(r"(?<=\s)>=(?=\s)"), "<"),
    ("&& → ||", re.compile(r"(?<=\s)&&(?=\s)"), "||"),
    ("|| → &&", re.compile(r"(?<=\s)\|\|(?=\s)"), "&&"),
    ("true → false", re.compile(r"\btrue\b"), "false"),
    ("false → true", re.compile(r"\bfalse\b"), "true"),
    ("+ → -", re.compile(r"(?<=\s)\+(?=\s)"), "-"),
    ("- → +", re.compile(r"(?<=\s)-(?=\s)"), "+"),
    ("* → /", re.compile(r"(?<=\s)\*(?=\s)"), "/"),
    ("/ → *", re.compile(r"(?<=\s)/(?=\s)"), "*"),
    (">> → <<", re.compile(r"(?<=\s)>>(?=\s)"), "<<"),
    ("<< → >>", re.compile(r"(?<=\s)<<(?=\s)"), ">>"),
    # Logical negation: a `!` that starts an expression (not `!=`, not a force unwrap `x!`).
    ("remove !", re.compile(r"(?<![\w)\]!?])!(?=[\w(.])"), ""),
]

# A whole statement `target = value` (optionally after a `case …:` label). Declarations (`let`/`var`) are not
# assignments; removing one would only produce a compile error.
ASSIGNMENT = re.compile(r"^(?P<prefix>\s*(?:case [^:]+:\s*)?)(?P<target>[A-Za-z_][\w.]*)\s*=(?!=)\s*\S.*$")
# `self.name = name` in an initializer: removing it never compiles, so it is not worth a build.
MEMBER_COPY = re.compile(r"^\s*self\.(\w+)\s*=\s*\1\s*$")
DECLARATION_KEYWORDS = ("let ", "var ", "static ", "private ", "public ", "fileprivate ", "internal ")

SKIPPED_PREFIXES = ("import ", "@testable import ", "//", "///", "/*", "*")


@dataclass(frozen=True)
class Mutant:
    path: str
    line_number: int
    original: str
    replacement: str
    operator: str

    def describe(self) -> str:
        return f"{self.path}:{self.line_number} {self.operator}"

    def apply(self, source: str) -> str:
        lines = source.split("\n")
        lines[self.line_number - 1] = self.replacement
        return "\n".join(lines)


def code_spans(line: str) -> list[tuple[int, int]]:
    """Spans of the line that are code: outside string literals and before a `//` comment."""
    spans, start, index, in_string = [], 0, 0, False
    while index < len(line):
        char = line[index]
        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string, start = False, index + 1
        elif char == '"':
            spans.append((start, index))
            in_string = True
        elif line.startswith("//", index):
            spans.append((start, index))
            return [span for span in spans if span[0] < span[1]]
        index += 1
    if not in_string:
        spans.append((start, len(line)))
    return [span for span in spans if span[0] < span[1]]


def mutants_for_line(line: str, path: str, line_number: int) -> list[Mutant]:
    if line.strip().startswith(SKIPPED_PREFIXES):
        return []
    mutants = []
    for start, end in code_spans(line):
        for label, pattern, replacement in OPERATORS:
            for match in pattern.finditer(line, start, end):
                mutated = line[: match.start()] + replacement + line[match.end():]
                mutants.append(Mutant(path, line_number, line, mutated, label))
    removal = assignment_removal(line)
    if removal is not None:
        mutants.append(Mutant(path, line_number, line, removal, "remove assignment"))
    return mutants


def assignment_removal(line: str) -> str | None:
    """The line without its assignment: `break` after a case label, otherwise just the indentation."""
    match = ASSIGNMENT.match(line)
    if match is None or line.strip().startswith(DECLARATION_KEYWORDS) or MEMBER_COPY.match(line):
        return None
    prefix = match.group("prefix")
    return prefix + "break" if prefix.strip().startswith("case ") else prefix


def mutants_for_source(source: str, path: str) -> list[Mutant]:
    return [
        mutant
        for number, line in enumerate(source.split("\n"), start=1)
        for mutant in mutants_for_line(line, path, number)
    ]


# --- Runner -------------------------------------------------------------------------------------------------


def run(command: list[str], cwd: Path, timeout: int) -> subprocess.CompletedProcess[str] | None:
    """Runs `command` in its own process group; on timeout the whole group is killed, so a test helper that a
    mutant hung (a grandchild of `swift test`) never outlives its run and slows the next ones."""
    process = subprocess.Popen(
        command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        return None
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def builds(package: Path, timeout: int) -> bool:
    result = run(["swift", "build", "--build-tests", "--package-path", str(package)], package, timeout)
    return result is not None and result.returncode == 0


def kill_strays(package: Path) -> None:
    """Kills every process whose command line names `package`: swiftpm starts its test helper in a process group of
    its own, so a helper a mutant hung outlives `swift test` and slows every later mutant."""
    subprocess.run(["pkill", "-9", "-f", re.escape(str(package))], capture_output=True)


def tests_pass(package: Path, timeout: int) -> bool | None:
    """True if the suite passes, False if it fails, None on timeout (counted as killed)."""
    result = run(["swift", "test", "--skip-build", "--package-path", str(package)], package, timeout)
    kill_strays(package / ".build")
    return None if result is None else result.returncode == 0


def source_files(package: Path) -> list[Path]:
    """Swift files of the package's own target (`Sources/<package name>`); `*TestSupport` targets are not mutated."""
    return sorted((package / "Sources" / package.name).rglob("*.swift"))


def changed_sources(sources: list[Path], changed: list[str], root: Path) -> list[Path]:
    """The sources whose repository-relative path is among `changed` (as git prints them)."""
    names = set(changed)
    return [source for source in sources if str(source.relative_to(root)) in names]


def git_changes(root: Path, since: str) -> list[str]:
    """Paths that differ from `since` in the working tree, plus untracked ones, relative to `root`."""
    diff = subprocess.run(["git", "diff", "--name-only", since], cwd=root, capture_output=True, text=True, check=True)
    untracked = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"], cwd=root, capture_output=True, text=True, check=True)
    return (diff.stdout + untracked.stdout).splitlines()


def missing_sources_message(package: Path, files: list[Path]) -> str | None:
    """An error message when there is nothing to mutate; a silent 100 % score would be misleading."""
    return None if files else f"no sources under Sources/{package.name}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--package", default="Packages/SmaltiCore")
    parser.add_argument("--min-score", type=float, default=80.0)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--changed-since", metavar="REF", help="mutate only the sources changed since REF")
    args = parser.parse_args()

    source_package = Path(args.package).resolve()
    sources = source_files(source_package)
    problem = missing_sources_message(source_package, sources)
    if problem:
        print(problem, file=sys.stderr)
        return 2
    if args.changed_since:
        root = Path(subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], cwd=source_package, capture_output=True, text=True, check=True
        ).stdout.strip()).resolve()
        sources = changed_sources(sources, git_changes(root, args.changed_since), root)
        print(f"changed since {args.changed_since}: {len(sources)} source file(s)")
        if not sources:
            print("nothing to mutate: no source of the package changed")
            return 0
    mutants = [
        mutant
        for file in sources
        for mutant in mutants_for_source(file.read_text(), str(file.relative_to(source_package / "Sources")))
    ]
    total = len(mutants)

    with tempfile.TemporaryDirectory(prefix="smalti-mutation-") as scratch:
        package = Path(scratch) / source_package.name
        shutil.copytree(source_package, package, ignore=shutil.ignore_patterns(".build", ".swiftpm"))
        if not (builds(package, args.timeout) and tests_pass(package, args.timeout)):
            print("baseline: the unmutated test suite must pass first", file=sys.stderr)
            return 2

        killed, survived, invalid = 0, [], 0
        for number, mutant in enumerate(mutants, start=1):
            target = package / "Sources" / mutant.path
            original = target.read_text()
            target.write_text(mutant.apply(original))
            try:
                if not builds(package, args.timeout):
                    invalid += 1
                    status = "ok invalid (no compila)"
                elif tests_pass(package, args.timeout) is True:
                    survived.append(mutant)
                    status = "FAIL survived"
                else:
                    killed += 1
                    status = "ok killed"
            finally:
                target.write_text(original)
            print(f"[{number}/{total}] {status} {mutant.describe()}", flush=True)

    valid = killed + len(survived)
    score = 100.0 * killed / valid if valid else 100.0
    print(f"\nmutantes: {total} · muertos: {killed} · sobrevivientes: {len(survived)} · inválidos: {invalid}")
    print(f"puntuación de mutación: {score:.1f}% (mínimo {args.min_score:.0f}%)")
    for mutant in survived:
        print(f"  sobrevive {mutant.describe()}\n    - {mutant.original.strip()}\n    + {mutant.replacement.strip()}")
    return 0 if score >= args.min_score else 1


if __name__ == "__main__":
    sys.exit(main())

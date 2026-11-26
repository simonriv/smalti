import SmaltiCore
import Testing

@Suite("ToolSummary")
struct ToolSummaryTests {
    @Test func bashShowsCommand() {
        #expect(
            ToolSummary.text(name: "Bash", input: ["command": "pnpm lint --fix", "description": "x"], diff: nil)
                == "pnpm lint --fix")
    }

    @Test func editShowsFileAndDiff() {
        let text = ToolSummary.text(
            name: "Update", input: ["file_path": "/src/reminder.service.ts"], diff: DiffStat(added: 18, removed: 4))

        #expect(text == "reminder.service.ts +18 −4")
    }

    @Test func readShowsFileOnly() {
        #expect(ToolSummary.text(name: "Read", input: ["file_path": "/src/a.ts"], diff: nil) == "a.ts")
    }

    @Test func grepShowsPatternAndPath() {
        #expect(
            ToolSummary.text(name: "Grep", input: ["pattern": "scheduleReminder", "path": "src/"], diff: nil)
                == "\"scheduleReminder\" · src/")
    }

    @Test func grepWithoutPathShowsPattern() {
        #expect(ToolSummary.text(name: "Glob", input: ["pattern": "**/*.swift"], diff: nil) == "\"**/*.swift\"")
    }

    @Test func unknownToolShowsFirstValueByKey() {
        #expect(ToolSummary.text(name: "WebFetch", input: ["url": "https://x", "prompt": "p"], diff: nil) == "p")
    }

    @Test func toolWithoutInputShowsNothing() {
        #expect(ToolSummary.text(name: "Task", input: [:], diff: nil) == "")
    }

    @Test func multilineBashShowsItsFirstLine() {
        let command = "git commit -m \"$(cat <<'EOF'\nfix: x\n\nbody\nEOF\n)\""

        #expect(
            ToolSummary.text(name: "Bash", input: ["command": command], diff: nil) == "git commit -m \"$(cat <<'EOF'")
    }

    @Test func leadingBlankLinesAreSkipped() {
        #expect(ToolSummary.text(name: "Bash", input: ["command": "\n  \n  make test\nmore"], diff: nil) == "make test")
    }

    // F9: Codex's tools and the subagent call.
    @Test func codexShellToolsShowTheirCommand() {
        #expect(ToolSummary.text(name: "exec_command", input: ["cmd": "ls -la", "a_flag": "1"], diff: nil) == "ls -la")
        #expect(ToolSummary.text(name: "shell", input: ["command": "make", "a": "b"], diff: nil) == "make")
    }

    @Test func applyPatchShowsTheFirstFile() {
        let patch = "*** Begin Patch\n*** Add File: test/webhooks/refund.test.ts\n+x\n*** Update File: b.ts\n"

        #expect(ToolSummary.text(name: "apply_patch", input: ["input": patch], diff: nil) == "refund.test.ts")
    }

    @Test func agentShowsItsDescription() {
        let input = ["description": "Contar archivos", "a_model": "haiku", "subagent_type": "general"]

        #expect(ToolSummary.text(name: "Agent", input: input, diff: nil) == "Contar archivos")
        #expect(ToolSummary.text(name: "Task", input: input, diff: nil) == "Contar archivos")
    }
}

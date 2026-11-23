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
                == "\"scheduleReminder\" en src/")
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
}

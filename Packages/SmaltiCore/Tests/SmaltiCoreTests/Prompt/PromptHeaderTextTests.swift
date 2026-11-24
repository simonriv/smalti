import SmaltiCore
import Testing

/// Spec F5, "Solo símbolo": the context moves to the pane header, trimmed from the left of the directory.
@Suite("PromptHeaderText")
struct PromptHeaderTextTests {
    private let segments = [
        PromptSegment(module: .directory, icon: .folder, runs: [ColoredText("solen/apps/api", .accent)]),
        PromptSegment(module: .gitBranch, icon: .branch, runs: [ColoredText("feat/reminders", .ansi(5))]),
        PromptSegment(module: .gitStatus, icon: nil, runs: [ColoredText("●2 +1", .ansi(3))]),
        PromptSegment(module: .runtime, icon: .node, runs: [ColoredText("22.11", .secondary)]),
    ]

    @Test func joinsSegmentsWithDots() {
        #expect(PromptHeaderText.text(for: segments, maxWidth: 80) == "solen/apps/api · feat/reminders ●2 +1 · 22.11")
    }

    @Test func headerContextTrimsDirectoryFromLeft() {
        let text = PromptHeaderText.text(for: segments, maxWidth: 40)

        #expect(text == "…/api · feat/reminders ●2 +1 · 22.11")
        #expect(text.count <= 40)
    }

    @Test func emptySegmentsGiveEmptyText() {
        #expect(PromptHeaderText.text(for: [], maxWidth: 40) == "")
    }

    @Test func tooNarrowKeepsWhatFits() {
        let text = PromptHeaderText.text(for: segments, maxWidth: 10)

        #expect(text.count <= 10)
    }
}

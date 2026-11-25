import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// F5.6 T11: the highlight of a `line` goes out on its own, before and apart from the ghost, with a follow-up when
/// the first answer was missing a spec or a slow path.
@Suite("InputRouting · highlight")
struct InputRoutingHighlightTests {
    private static let git = CompletionSpec(name: ["git"], subcommands: [CompletionSpec(name: ["status"])])

    private func request(_ text: String, seq: Int = 4) -> HighlightRequest {
        HighlightRequest(
            line: InputLine(text: text, cursor: text.unicodeScalars.count), seq: seq, directory: "/w", home: "/h")
    }

    @Test func highlightMessageCarriesTheSeqAndSpans() async {
        let highlighter = HighlightLine(paths: InMemoryPathFacts(), completions: FakeCompletionProvider())

        let answer = await InputRouting.highlight(request("ls -la"), using: highlighter)

        #expect(
            answer.first
                == .highlight(
                    seq: 4,
                    [HighlightSpan(range: 0..<2, role: .command), HighlightSpan(range: 3..<6, role: .option)]))
        #expect(!answer.needsFollowUp)
    }

    @Test func unloadedSpecNeedsFollowUpWithSubcommands() async {
        let highlighter = HighlightLine(
            paths: InMemoryPathFacts(), completions: FakeCompletionProvider(specs: [Self.git], loaded: []))

        let answer = await InputRouting.highlight(request("git status"), using: highlighter)
        let followUp = await InputRouting.followUp(request("git status"), using: highlighter)

        #expect(answer.needsFollowUp)
        #expect(
            followUp
                == .highlight(
                    seq: 4,
                    [HighlightSpan(range: 0..<3, role: .command), HighlightSpan(range: 4..<10, role: .subcommand)]))
    }

    @Test(arguments: [(4, 4, true), (4, 5, false), (5, 4, false)])
    func followUpOnlyForLatestSeq(_ seq: Int, _ latest: Int, _ expected: Bool) {
        #expect(InputRouting.shouldSendFollowUp(seq: seq, latest: latest) == expected)
    }

    @Test func noLatestSeqSendsNoFollowUp() {
        #expect(!InputRouting.shouldSendFollowUp(seq: 4, latest: nil))
    }
}

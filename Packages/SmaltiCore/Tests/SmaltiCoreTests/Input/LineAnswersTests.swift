import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// F5.6 review 2 (I1): a `line` gets its ghost and its highlight each as soon as it is ready; the ghost never waits
/// for the highlight (spec, "Resaltado: flujo por tecla", step 2).
@MainActor
@Suite("LineAnswers")
struct LineAnswersTests {
    private final class Outbox {
        var messages: [SmaltiMessage] = []
    }

    private func session() async -> InputSession {
        let session = InputSession(
            ports: InputSession.Ports(
                history: InMemoryCommandHistory(entries: [historyEntry("git status", at: 999_000)]),
                project: FakeProjectContext(), completions: FakeCompletionProvider(), predictor: HeuristicPredictor()),
            settings: .standard, clock: { Date(timeIntervalSince1970: 1_000_000) })
        await session.start()
        return session
    }

    private func request(_ text: String, seq: Int = 7) -> HighlightRequest {
        HighlightRequest(
            line: InputLine(text: text, cursor: text.unicodeScalars.count), seq: seq, directory: "/w", home: "/h")
    }

    @Test func ghostDoesNotWaitForASlowHighlight() async {
        let slowDisk = HighlightLine(
            paths: InMemoryPathFacts(kinds: ["/w/s": .file], delay: .milliseconds(300)),
            completions: FakeCompletionProvider(),
            timing: HighlightTiming(budget: .seconds(1)) { Date() })
        let outbox = Outbox()
        let answers = LineAnswers(session: await session(), highlighter: slowDisk)

        await answers.answer(
            request("git s"), pane: HistoryFixture.pane,
            channel: LineChannel(send: { outbox.messages.append($0) }, isLatest: { _ in true }))

        #expect(outbox.messages.first == .suggest(seq: 7, "tatus"))
        #expect(outbox.messages.contains { if case .highlight(7, _) = $0 { true } else { false } })
    }

    @Test func withoutHighlighterOnlyTheGhostGoesOut() async {
        let outbox = Outbox()
        let answers = LineAnswers(session: await session(), highlighter: nil)

        await answers.answer(
            request("git s"), pane: HistoryFixture.pane,
            channel: LineChannel(send: { outbox.messages.append($0) }, isLatest: { _ in true }))

        #expect(outbox.messages == [.suggest(seq: 7, "tatus")])
    }

    @Test func followUpOnlyWhileTheLineIsLatest() async throws {
        let git = CompletionSpec(name: ["git"], subcommands: [CompletionSpec(name: ["status"])])
        let highlighter = HighlightLine(
            paths: InMemoryPathFacts(), completions: FakeCompletionProvider(specs: [git], loaded: []))
        let outbox = Outbox()
        let answers = LineAnswers(session: await session(), highlighter: highlighter)

        await answers.answer(
            request("git status"), pane: HistoryFixture.pane,
            channel: LineChannel(send: { outbox.messages.append($0) }, isLatest: { _ in false }))
        try await Task.sleep(for: .milliseconds(200))

        #expect(outbox.messages.filter { if case .highlight = $0 { true } else { false } }.count == 1)
    }
}

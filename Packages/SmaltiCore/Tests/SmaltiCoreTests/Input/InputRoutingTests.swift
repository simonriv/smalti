import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("InputRouting")
struct InputRoutingTests {
    private let pane = HistoryFixture.pane

    private func session(
        history: [HistoryEntry] = [], specs: [CompletionSpec] = [SpecFixtures.git],
        settings: InputSettings = .standard
    ) async -> InputSession {
        let session = InputSession(
            ports: InputSession.Ports(
                history: InMemoryCommandHistory(entries: history), project: FakeProjectContext(),
                completions: FakeCompletionProvider(specs: specs), predictor: HeuristicPredictor()),
            settings: settings, clock: { Date(timeIntervalSince1970: 1_000_000) })
        await session.start()
        return session
    }

    private func line(_ text: String) -> InputLine { InputLine(text: text, cursor: text.unicodeScalars.count) }

    @Test func helloRepliesSpecs() async {
        let reply = await InputRouting.respond(
            to: .hello(pane), pane: pane, directory: "/repo", session: await session())

        #expect(reply == .send([.specs(["git"])]))
    }

    @Test func lineRepliesSuggestion() async {
        let session = await session(history: [historyEntry("git status", at: 999_000)])

        let reply = await InputRouting.respond(
            to: .line(seq: 4, line("git s")), pane: pane, directory: "/repo", session: session)

        #expect(reply == .send([.suggest(seq: 4, "tatus")]))
    }

    @Test func lineWithInputDisabledRepliesEmpty() async {
        var settings = InputSettings.standard
        settings.isEnabled = false
        let session = await session(history: [historyEntry("git status", at: 999_000)], settings: settings)

        let reply = await InputRouting.respond(
            to: .line(seq: 4, line("git s")), pane: pane, directory: "/repo", session: session)

        #expect(reply == .send([.suggest(seq: 4, "")]))
    }

    @Test func suggestionUsesTheDirectoryGivenWithTheMessage() async {
        let session = await session(history: [
            historyEntry("make here", in: "/a", at: 999_000), historyEntry("make there", in: "/b", at: 999_000),
            historyEntry("make there", in: "/b", at: 999_000),
        ])

        let inA = await InputRouting.respond(
            to: .line(seq: 1, line("make ")), pane: pane, directory: "/a", session: session)
        let inB = await InputRouting.respond(
            to: .line(seq: 2, line("make ")), pane: pane, directory: "/b", session: session)

        #expect(inA == .send([.suggest(seq: 1, "here")]))
        #expect(inB == .send([.suggest(seq: 2, "there")]))
    }

    @Test func completeWithoutSpecRepliesFallback() async {
        let reply = await InputRouting.respond(
            to: .complete(seq: 7, line("npm r")), pane: pane, directory: "/repo", session: await session())

        #expect(reply == .send([.fallback(seq: 7)]))
    }

    @Test func completeWithNothingToOfferRepliesFallback() async {
        let reply = await InputRouting.respond(
            to: .complete(seq: 8, line("git zzz")), pane: pane, directory: "/repo", session: await session())

        #expect(reply == .send([.fallback(seq: 8)]))
    }

    @Test func completeWithSpecOpensTheMenu() async {
        let reply = await InputRouting.respond(
            to: .complete(seq: 9, line("git ch")), pane: pane, directory: "/repo", session: await session())

        guard case .openMenu(let seq, let menuLine, let result) = reply else {
            Issue.record("expected a menu, got \(reply)")
            return
        }
        #expect(seq == 9)
        #expect(menuLine == line("git ch"))
        #expect(result.items.map(\.name) == ["checkout", "cherry-pick", "check-ignore"])
    }

    @Test func historyOpensThePalette() async {
        let reply = await InputRouting.respond(
            to: .history(seq: 3, query: "swi"), pane: pane, directory: "/repo", session: await session())

        #expect(reply == .openHistory(seq: 3, query: "swi"))
    }

    @Test func execThenDoneRecordsEntry() async {
        let session = await session()

        let began = await InputRouting.respond(
            to: .exec(seq: 1, command: "make"), pane: pane, directory: "/a", session: session)
        let finished = await InputRouting.respond(
            to: .done(seq: 2, exit: 0), pane: pane, directory: "/a", session: session)

        #expect(began == .none)
        #expect(finished == .none)
        #expect(await session.search("make", scope: .directory("/a")).map(\.stats.command) == ["make"])
    }

    @Test func byeNeedsNoAnswer() async {
        #expect(await InputRouting.respond(to: .bye, pane: pane, directory: "/", session: await session()) == .none)
    }
}

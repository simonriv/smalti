import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5.5: the preview resolves names against the folders of the pane's last command (`ls shots/`).
@Suite("InputSession · last command")
struct LastCommandTests {
    private let pane = HistoryFixture.pane

    private func session() -> InputSession {
        InputSession(
            ports: InputSession.Ports(
                history: InMemoryCommandHistory(), project: FakeProjectContext(),
                completions: FakeCompletionProvider(), predictor: HeuristicPredictor()),
            settings: .standard, clock: { Date(timeIntervalSince1970: 1_000_000) })
    }

    @Test func noCommandYetIsNil() async {
        #expect(await session().lastCommand(in: pane) == nil)
    }

    @Test func finishedCommandIsTheLast() async {
        let session = session()
        await session.began("ls shots", pane: pane, directory: "/w")
        await session.finished(pane: pane, exit: 0)

        #expect(await session.lastCommand(in: pane) == "ls shots")
    }

    @Test func runningCommandIsTheLast() async {
        let session = session()
        await session.began("ls old", pane: pane, directory: "/w")
        await session.finished(pane: pane, exit: 0)
        await session.began("find shots -name '*.png'", pane: pane, directory: "/w")

        #expect(await session.lastCommand(in: pane) == "find shots -name '*.png'")
    }

    @Test func otherPaneHasItsOwn() async {
        let session = session()
        await session.began("ls shots", pane: pane, directory: "/w")

        #expect(await session.lastCommand(in: PaneID()) == nil)
    }

    @Test func secretCommandIsNeverGiven() async {
        let session = session()
        await session.began("export API_TOKEN=abc123 && ls shots", pane: pane, directory: "/w")

        #expect(await session.lastCommand(in: pane) == nil)
        await session.finished(pane: pane, exit: 0)
        #expect(await session.lastCommand(in: pane) == nil)
    }
}

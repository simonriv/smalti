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

/// F4 behavior pinned before simplifying `start()` (block 2 mutation): what ran while the history loaded is kept,
/// after what was loaded, and only once.
@Suite("InputSession · commands while loading")
struct CommandsWhileLoadingTests {
    @Test func commandsRunWhileLoadingAreKeptWithTheLoadedOnes() async {
        let history = HeldHistory(loaded: [
            HistoryEntry(
                command: "git status", directory: "/w", exit: 0, duration: 1, date: Date(timeIntervalSince1970: 1),
                pane: HistoryFixture.pane)
        ])
        let session = InputSession(
            ports: InputSession.Ports(
                history: history, project: FakeProjectContext(), completions: FakeCompletionProvider(),
                predictor: HeuristicPredictor()),
            settings: .standard, clock: { Date(timeIntervalSince1970: 1_000_000) })
        let starting = Task { await session.start() }
        await history.waitUntilLoading()

        await session.began("make build", pane: HistoryFixture.pane, directory: "/w")
        await session.finished(pane: HistoryFixture.pane, exit: 0)
        await history.release()
        await starting.value
        await session.began("make test", pane: HistoryFixture.pane, directory: "/w")
        await session.finished(pane: HistoryFixture.pane, exit: 0)

        let found = await session.search("", scope: .all).map(\.stats)
        #expect(Set(found.map(\.command)) == ["git status", "make build", "make test"])
        #expect(found.allSatisfy { $0.uses == 1 })
    }
}

private actor HeldHistory: CommandHistory {
    private let loaded: [HistoryEntry]
    private var held: CheckedContinuation<Void, Never>?
    private var loading: [CheckedContinuation<Void, Never>] = []
    private var isLoading = false

    init(loaded: [HistoryEntry]) {
        self.loaded = loaded
    }

    func load() async throws(HistoryError) -> [HistoryEntry] {
        isLoading = true
        loading.forEach { $0.resume() }
        loading = []
        await withCheckedContinuation { held = $0 }
        return loaded
    }

    func append(_ entry: HistoryEntry) async throws(HistoryError) {}

    func waitUntilLoading() async {
        guard !isLoading else { return }
        await withCheckedContinuation { loading.append($0) }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

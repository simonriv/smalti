import SmaltiCore

/// In-memory TerminalEngine for use-case tests: records calls and lets tests push events.
@MainActor
final class FakeTerminalEngine: TerminalEngine {
    private(set) var openedSpecs: [TerminalSessionSpec] = []
    private(set) var closedPanes: [PaneID] = []
    var failure: TerminalEngineError?
    private var streams:
        [PaneID: (stream: AsyncStream<TerminalEvent>, continuation: AsyncStream<TerminalEvent>.Continuation)] = [:]

    func open(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> PaneID {
        if let failure { throw failure }
        openedSpecs.append(spec)
        let id = PaneID()
        streams[id] = AsyncStream.makeStream()
        return id
    }

    func close(_ pane: PaneID) {
        closedPanes.append(pane)
        streams.removeValue(forKey: pane)?.continuation.finish()
    }

    func events(for pane: PaneID) -> AsyncStream<TerminalEvent> {
        streams[pane]?.stream ?? AsyncStream { $0.finish() }
    }

    func emit(_ event: TerminalEvent, for pane: PaneID) {
        streams[pane]?.continuation.yield(event)
    }
}

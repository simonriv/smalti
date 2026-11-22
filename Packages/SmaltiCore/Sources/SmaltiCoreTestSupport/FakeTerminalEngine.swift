import SmaltiCore

/// In-memory TerminalEngine for use-case tests: records calls and lets tests push events.
@MainActor
public final class FakeTerminalEngine: TerminalEngine {
    public private(set) var openedSpecs: [TerminalSessionSpec] = []
    public private(set) var closedPanes: [PaneID] = []
    public private(set) var shownPanes: [PaneID] = []
    public private(set) var hiddenPanes: [PaneID] = []
    public var failure: TerminalEngineError?
    private var streams:
        [PaneID: (stream: AsyncStream<TerminalEvent>, continuation: AsyncStream<TerminalEvent>.Continuation)] = [:]

    public init() {}

    public func open(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> PaneID {
        if let failure { throw failure }
        openedSpecs.append(spec)
        let id = PaneID()
        streams[id] = AsyncStream.makeStream()
        return id
    }

    public func close(_ pane: PaneID) {
        closedPanes.append(pane)
        streams.removeValue(forKey: pane)?.continuation.finish()
    }

    public func show(_ pane: PaneID) {
        shownPanes.append(pane)
    }

    public func hide(_ pane: PaneID) {
        hiddenPanes.append(pane)
    }

    public func events(for pane: PaneID) -> AsyncStream<TerminalEvent> {
        streams[pane]?.stream ?? AsyncStream { $0.finish() }
    }

    public func emit(_ event: TerminalEvent, for pane: PaneID) {
        streams[pane]?.continuation.yield(event)
    }
}

import SmaltiCore

/// In-memory TerminalEngine for use-case tests: records calls and lets tests push events.
@MainActor
public final class FakeTerminalEngine: TerminalEngine {
    public private(set) var openedSpecs: [TerminalSessionSpec] = []
    public private(set) var closedPanes: [PaneID] = []
    public private(set) var shownPanes: [PaneID] = []
    public private(set) var hiddenPanes: [PaneID] = []
    public private(set) var openedIDs: [PaneID] = []
    public var failure: TerminalEngineError?
    /// Opening in one of these paths fails as if the directory were gone.
    public var failingDirectories: Set<String> = []
    private var streams:
        [PaneID: (stream: AsyncStream<TerminalEvent>, continuation: AsyncStream<TerminalEvent>.Continuation)] = [:]

    public init() {}

    public func open(_ spec: TerminalSessionSpec, as pane: PaneID) throws(TerminalEngineError) {
        if let failure { throw failure }
        let path = spec.workingDirectory.path
        if failingDirectories.contains(path) {
            throw .surfaceCreationFailed(workingDirectory: path, reason: "no such directory")
        }
        openedSpecs.append(spec)
        openedIDs.append(pane)
        streams[pane] = AsyncStream.makeStream()
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

/// What closing would end, read again from the engine: hidden panes stop reporting their foreground process (R7), so
/// what the panes last said may be stale (final review of F4.5).
@MainActor
public struct RunningPrograms {
    private let engine: any TerminalEngine
    private let texts: TerminalTexts

    public init(engine: any TerminalEngine, texts: TerminalTexts) {
        self.engine = engine
        self.texts = texts
    }

    public func busy(in panes: [Pane]) -> [BusyPane] {
        CloseGuard.busyPanes(panes.map(current), texts: texts)
    }

    public func busy(in windows: WindowSet) -> [BusyPane] {
        busy(in: windows.allPanes)
    }

    /// The pane as the engine sees it now; as last reported when the engine cannot tell.
    private func current(_ pane: Pane) -> Pane {
        engine.foregroundProcess(of: pane.id).map { pane.applying(.foregroundProcessChanged($0)) } ?? pane
    }
}

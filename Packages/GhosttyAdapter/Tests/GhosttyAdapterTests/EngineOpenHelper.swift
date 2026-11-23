import GhosttyAdapter
import SmaltiCore

extension GhosttyTerminalEngine {
    /// Opens with a fresh id, as the tests written before `open(_:as:)` expect.
    @MainActor
    func open(_ spec: TerminalSessionSpec) throws(TerminalEngineError) -> PaneID {
        let pane = PaneID()
        try open(spec, as: pane)
        return pane
    }
}

public enum CloseWindowOutcome: Equatable, Sendable {
    case closed
    /// The only window: closing it quits the app (⌘Q), so nothing was closed here.
    case isLast
}

/// Closes a window and every pane in it. The last window is left to the app, which quits and saves it.
@MainActor
public struct CloseWindow {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(_ id: WindowID, in set: inout WindowSet) -> CloseWindowOutcome {
        guard let window = set.windows.first(where: { $0.id == id }) else { return .closed }
        do {
            set = try set.closing(id)
        } catch {
            return .isLast
        }
        window.allPanes.forEach { engine.close($0.id) }
        return .closed
    }
}

/// Which session the timeline shows for a pane (spec F9, section 2).
public enum TimelineTarget {
    public enum Resolution: Equatable, Sendable {
        case session(HarnessID, String)
        /// A harness runs (or ran) here but its session was never named: the latest one of `directory` stands in.
        case unidentified(HarnessID, directory: String)
        /// A harness whose transcript Smalti cannot read (Antigravity, OpenCode).
        case unreadable(HarnessID)
        case noAgent
    }

    /// Hooks win (they name what the pane shows now, even after leaving for the shell), then the pane's binding, then
    /// the harness running in front (`running`, detected by the caller).
    public static func resolve(pane: Pane, running: HarnessID?, readable: Set<HarnessID>) -> Resolution {
        let named: (HarnessID, String?)? =
            pane.agent.map { ($0.harness, $0.sessionID) }
            ?? pane.harnessBinding.map { ($0.harness, $0.sessionID) }
            ?? running.map { ($0, nil) }
        guard let (harness, session) = named else { return .noAgent }
        guard readable.contains(harness) else { return .unreadable(harness) }
        guard let session else { return .unidentified(harness, directory: pane.workingDirectory.path) }
        return .session(harness, session)
    }
}

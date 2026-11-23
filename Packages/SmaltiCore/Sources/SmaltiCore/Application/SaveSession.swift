import Foundation

public enum SaveOutcome: Equatable, Sendable {
    case saved
    case failed(String)
}

/// Saves the window so it can be reopened: the structure often and cheaply, the scrollback on quit and every few
/// minutes. A pane whose scrollback cannot be read does not stop the others from being saved.
@MainActor
public struct SaveSession {
    public static let scrollbackLineLimit = 10_000

    private let archive: any SessionArchive
    private let transcripts: any PaneTranscripts
    private let scrollback: any ScrollbackSource

    public init(archive: any SessionArchive, transcripts: any PaneTranscripts, scrollback: any ScrollbackSource) {
        self.archive = archive
        self.transcripts = transcripts
        self.scrollback = scrollback
    }

    /// Layout, directories and agents; line counts carry over from the last scrollback save.
    public func saveStructure(of set: WorkspaceSet, at date: Date) -> SaveOutcome {
        save(SessionSnapshot.capture(set, scrollbackLines: previousLineCounts(), at: date))
    }

    /// Also exports the scrollback of every pane that is at its shell.
    public func saveWithScrollback(of set: WorkspaceSet, at date: Date) -> SaveOutcome {
        let panes = set.workspaces.flatMap(\.panes)
        var lineCounts: [PaneID: Int] = [:]
        for pane in panes where pane.isAtShell {
            lineCounts[pane.id] = keepScrollback(of: pane.id)
        }
        transcripts.forget(allExcept: Set(panes.map(\.id)))
        return save(SessionSnapshot.capture(set, scrollbackLines: lineCounts.compactMapValues { $0 }, at: date))
    }

    /// Lines kept, or `nil` when the pane's scrollback could not be read or kept.
    private func keepScrollback(of pane: PaneID) -> Int? {
        do {
            let text = try scrollback.scrollback(of: pane, lastLines: Self.scrollbackLineLimit)
            try transcripts.keep(text, for: pane)
            return text.lineCount
        } catch {
            return nil
        }
    }

    private func previousLineCounts() -> [PaneID: Int] {
        guard case .saved(let previous) = archive.lastSession() else { return [:] }
        let panes = previous.workspaces.flatMap(\.panes)
        return Dictionary(panes.map { (PaneID(rawValue: $0.id), $0.scrollbackLines) }) { first, _ in first }
    }

    private func save(_ snapshot: SessionSnapshot) -> SaveOutcome {
        do {
            try archive.save(snapshot)
            return .saved
        } catch {
            return .failed(error.summary)
        }
    }
}

/// What to do at launch with what the last run left.
public enum StartupChoice: Equatable, Sendable {
    case startFresh
    case ask(SessionSnapshot)
    case restoreAll(SessionSnapshot)
    case startFreshAfterUnreadable(reason: String)
}

@MainActor
public struct LoadLastSession {
    private let archive: any SessionArchive
    private let preferences: any RestorePreferenceStore

    public init(archive: any SessionArchive, preferences: any RestorePreferenceStore) {
        self.archive = archive
        self.preferences = preferences
    }

    public func execute() -> StartupChoice {
        switch archive.lastSession() {
        case .none: .startFresh
        case .unreadable(let reason): .startFreshAfterUnreadable(reason: reason)
        case .saved(let snapshot): preferences.current() == .always ? .restoreAll(snapshot) : .ask(snapshot)
        }
    }
}

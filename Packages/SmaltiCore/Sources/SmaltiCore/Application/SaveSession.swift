import Foundation

public enum SaveOutcome: Equatable, Sendable {
    case saved
    case failed(SessionArchiveError)
    /// F7.6: the stored session is from a newer Smalti, so nothing was written.
    case keptNewer(version: Int)

    public func message(_ texts: SessionTexts) -> String? {
        switch self {
        case .saved: nil
        case .failed(let error): error.summary(texts)
        case .keptNewer(let version): texts.keptNewer(["version": String(version)])
        }
    }
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

    /// Layout, directories, agents and window frames; line counts carry over from the last scrollback save.
    /// F6: `editors` holds the file and line each Smalti Neovim answered with; one that did not answer saves as its
    /// process.
    public func saveStructure(of windows: WindowSet, at date: Date, editors: [PaneID: EditorPosition] = [:])
        -> SaveOutcome
    {
        if let newer = newerStoredVersion() { return .keptNewer(version: newer) }
        return save(SessionSnapshot.capture(windows, scrollbackLines: previousLineCounts(), editors: editors, at: date))
    }

    /// Also exports the scrollback of every pane that is at its shell, in every window.
    public func saveWithScrollback(of windows: WindowSet, at date: Date, editors: [PaneID: EditorPosition] = [:])
        -> SaveOutcome
    {
        if let newer = newerStoredVersion() { return .keptNewer(version: newer) }
        let panes = windows.allPanes
        var lineCounts: [PaneID: Int] = [:]
        for pane in panes where pane.isAtShell {
            lineCounts[pane.id] = keepScrollback(of: pane.id)
        }
        transcripts.forget(allExcept: Set(panes.map(\.id)))
        return save(
            SessionSnapshot.capture(
                windows, scrollbackLines: lineCounts.compactMapValues { $0 }, editors: editors, at: date))
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

    private func newerStoredVersion() -> Int? {
        guard case .newer(let version) = archive.lastSession() else { return nil }
        return version
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
            return .failed(error)
        }
    }
}

/// What to do at launch with what the last run left.
public enum StartupChoice: Equatable, Sendable {
    case startFresh
    case ask(SessionSnapshot)
    case restoreAll(SessionSnapshot)
    case startFreshAfterUnreadable(reason: String)
    /// F7.6: the last session is from a newer Smalti and stays on disk untouched.
    case startFreshKeepingNewer(version: Int)
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
        case .newer(let version): .startFreshKeepingNewer(version: version)
        case .saved(let snapshot): preferences.current() == .always ? .restoreAll(snapshot) : .ask(snapshot)
        }
    }
}

import SmaltiCore

/// In-memory `SessionArchive`, `PaneTranscripts` and `RestorePreferenceStore`, like the file adapter.
@MainActor
public final class InMemorySessionArchive: SessionArchive, PaneTranscripts, RestorePreferenceStore {
    public private(set) var saved: SessionSnapshot?
    public var transcripts: [PaneID: Scrollback] = [:]
    public var writeFailure: SessionArchiveError?
    public var unreadableReason: String?
    /// Panes whose scrollback was asked for.
    public private(set) var scrollbackLookups: [PaneID] = []
    private var preference = RestorePreference.ask

    public init() {}

    public func save(_ snapshot: SessionSnapshot) throws(SessionArchiveError) {
        if let writeFailure { throw writeFailure }
        saved = snapshot
    }

    public func lastSession() -> LastSession {
        if let unreadableReason { return .unreadable(reason: unreadableReason) }
        return saved.map(LastSession.saved) ?? .none
    }

    public func keep(_ scrollback: Scrollback, for pane: PaneID) throws(SessionArchiveError) {
        if let writeFailure { throw writeFailure }
        transcripts[pane] = scrollback
    }

    public func scrollback(of pane: PaneID) -> Scrollback? {
        scrollbackLookups.append(pane)
        return transcripts[pane]
    }

    public func forget(allExcept panes: Set<PaneID>) {
        transcripts = transcripts.filter { panes.contains($0.key) }
    }

    public func current() -> RestorePreference { preference }

    public func set(_ preference: RestorePreference) throws(SessionArchiveError) {
        self.preference = preference
    }
}

@MainActor
public final class InMemoryNamedLayouts: NamedLayouts {
    private var layouts: [LayoutName: WorkspaceSnapshot] = [:]

    public init() {}

    public func save(_ layout: WorkspaceSnapshot, as name: LayoutName) throws(SessionArchiveError) {
        layouts[name] = layout
    }

    public func layout(named name: LayoutName) throws(SessionArchiveError) -> WorkspaceSnapshot {
        guard let layout = layouts[name] else { throw .notFound(name: name.rawValue) }
        return layout
    }

    public func names() -> [LayoutName] { layouts.keys.sorted { $0.rawValue < $1.rawValue } }
}

/// Scrollback per pane; panes in `failing` cannot be read.
@MainActor
public final class FakeScrollbackSource: ScrollbackSource {
    public var contents: [PaneID: Scrollback] = [:]
    public var failing: Set<PaneID> = []
    public private(set) var requested: [PaneID] = []
    public private(set) var requestedLines: Set<Int> = []

    public init() {}

    public func scrollback(of pane: PaneID, lastLines: Int) throws(ScrollbackError) -> Scrollback {
        requested.append(pane)
        requestedLines.insert(lastLines)
        if failing.contains(pane) { throw .unavailable(pane: pane, reason: "fake failure") }
        return contents[pane] ?? Scrollback(text: "", format: .plain)
    }
}

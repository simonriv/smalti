import Foundation
import SmaltiCore
import Testing

/// Behaviour every archive (`SessionArchive` + `PaneTranscripts` + `RestorePreferenceStore`) must have.
public enum SessionArchiveContract {
    public typealias Archive = SessionArchive & PaneTranscripts & RestorePreferenceStore

    static let snapshot = SessionSnapshot(
        version: SessionSnapshot.formatVersion, savedAt: Date(timeIntervalSince1970: 1_800_000_000),
        workspaces: [
            WorkspaceSnapshot(
                name: "solen", rootDirectory: "/Users/s/dev/solen", layout: "dwindle",
                tree: .leaf(index: 0), focusedIndex: 0,
                panes: [
                    PaneSnapshot(
                        id: UUID(), workingDirectory: "/Users/s/dev/solen", title: "zsh", processName: "zsh",
                        scrollbackLines: 3, commandCount: 2, relaunch: nil,
                        agent: AgentSnapshot(harness: .claude, sessionID: "7f3a", title: "t", lastState: .waiting))
                ])
        ], activeIndex: 0)

    @MainActor
    public static func verify(_ make: () -> some Archive) throws {
        #expect(make().lastSession() == .none, "an empty archive has no session")
        let archive = make()
        try archive.save(snapshot)
        #expect(archive.lastSession() == .saved(snapshot), "saving then loading returns the snapshot")
        try transcripts(make())
        try preferences(make())
    }

    @MainActor
    private static func transcripts(_ archive: some Archive) throws {
        let kept = PaneID()
        let dropped = PaneID()
        let text = Scrollback(text: "\u{1B}[31mrojo\u{1B}[0m\nverde", format: .vt)
        try archive.keep(text, for: kept)
        try archive.keep(text, for: dropped)
        #expect(archive.scrollback(of: kept) == text, "kept scrollback comes back")
        archive.forget(allExcept: [kept])
        #expect(archive.scrollback(of: dropped) == nil, "forgotten panes lose their scrollback")
        #expect(archive.scrollback(of: kept) == text, "the others keep it")
    }

    @MainActor
    private static func preferences(_ archive: some Archive) throws {
        #expect(archive.current() == .ask, "the preference starts as ask")
        try archive.set(.always)
        #expect(archive.current() == .always, "a set preference is kept")
    }
}

public enum NamedLayoutsContract {
    @MainActor
    public static func verify(_ make: () -> some NamedLayouts) throws {
        let layouts = make()
        #expect(layouts.names().isEmpty, "no layouts at first")
        let workspace = SessionArchiveContract.snapshot.workspaces[0]
        let name = try LayoutName("solen-dev")
        try layouts.save(workspace, as: name)
        #expect(try layouts.layout(named: name) == workspace, "a saved layout comes back")
        #expect(layouts.names() == [name], "names lists saved layouts")
        #expect(throws: SessionArchiveError.self, "a missing layout throws") {
            try layouts.layout(named: try LayoutName("otro"))
        }
    }
}

public enum HarnessAdapterContract {
    public static func verify(_ adapter: some HarnessAdapter) {
        let agent = AgentSnapshot(harness: adapter.harness, sessionID: "abc123", title: nil, lastState: .working)
        let command = adapter.resumeCommand(for: agent)
        #expect(command.contains("abc123"), "the resume command names the session")
        #expect(!command.contains("\n"), "the resume command is one line; the caller adds the newline")
    }
}

import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("SaveSession and LoadLastSession")
struct SaveSessionTests {
    private let archive = InMemorySessionArchive()
    private let scrollback = FakeScrollbackSource()
    private let shell = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/Users/s/dev/solen"))
    private let editor = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/Users/s/dev/solen"))
        .applying(.foregroundProcessChanged(ForegroundProcess(name: "nvim", commandLine: ["nvim"])))

    private var set: WorkspaceSet {
        let workspace = [shell, editor].reduce(
            Workspace.empty(
                name: "solen", rootDirectory: SessionFixtures.directory("/Users/s/dev/solen"), layout: DwindleLayout())
        ) { $0.adding($1) }
        return WorkspaceSet(first: workspace)
    }

    private var save: SaveSession { SaveSession(archive: archive, transcripts: archive, scrollback: scrollback) }

    @Test func saveStructureWritesSnapshotWithoutExporting() {
        let outcome = save.saveStructure(of: set, at: SessionFixtures.savedAt)

        #expect(outcome == .saved)
        #expect(archive.saved?.workspaces.first?.panes.count == 2)
        #expect(scrollback.requested.isEmpty)
    }

    @Test func saveStructureKeepsLineCountsOfTheLastScrollbackSave() {
        scrollback.contents[shell.id] = Scrollback(text: "a\nb\nc", format: .plain)
        _ = save.saveWithScrollback(of: set, at: SessionFixtures.savedAt)

        _ = save.saveStructure(of: set, at: SessionFixtures.now)

        #expect(archive.saved?.workspaces[0].panes[0].scrollbackLines == 3)
    }

    @Test func editorPositionIsSavedForItsPane() {
        let position = EditorPosition(file: "/Users/s/dev/solen/reminder.service.ts", line: 42)

        _ = save.saveStructure(of: .single(set), at: SessionFixtures.savedAt, editors: [editor.id: position])

        #expect(archive.saved?.workspaces[0].panes.map(\.editor) == [nil, position])
        #expect(archive.saved?.workspaces[0].panes[1].relaunch == nil)
    }

    @Test func editorWithoutPositionKeepsItsProcessRelaunch() {
        _ = save.saveWithScrollback(of: .single(set), at: SessionFixtures.savedAt, editors: [:])

        #expect(archive.saved?.workspaces[0].panes[1].editor == nil)
        #expect(archive.saved?.workspaces[0].panes[1].relaunch != nil)
    }

    @Test func saveWithScrollbackExportsOnlyShellPanes() {
        scrollback.contents[shell.id] = Scrollback(text: "uno\ndos", format: .vt)

        _ = save.saveWithScrollback(of: set, at: SessionFixtures.savedAt)

        #expect(scrollback.requested == [shell.id])
        #expect(archive.scrollback(of: shell.id) == Scrollback(text: "uno\ndos", format: .vt))
        #expect(archive.saved?.workspaces[0].panes.map(\.scrollbackLines) == [2, 0])
    }

    /// F4.5: every window is saved, and a pane of a back window keeps its scrollback.
    @Test func saveWithScrollbackCoversEveryWindow() {
        let other = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/Users/s/dev/billi"))
        let back = WindowState(
            id: WindowID(),
            workspaces: WorkspaceSet(
                first: Workspace.empty(
                    name: "billi", rootDirectory: SessionFixtures.directory("/Users/s/dev/billi"),
                    layout: DwindleLayout()
                ).adding(other)),
            frame: nil, isFullScreen: false)
        let windows = WindowSet(first: back).opening(
            WindowState(id: WindowID(), workspaces: set, frame: nil, isFullScreen: false))
        scrollback.contents[other.id] = Scrollback(text: "x", format: .plain)

        _ = save.saveWithScrollback(of: windows, at: SessionFixtures.savedAt)

        #expect(archive.saved?.windows.count == 2)
        #expect(archive.saved?.frontIndex == 1)
        #expect(archive.scrollback(of: other.id) == Scrollback(text: "x", format: .plain))
    }

    @Test func saveStructureOfWindowsKeepsTheirFrames() {
        let frame = Rect(x: 1, y: 2, width: 800, height: 600)
        let windows = WindowSet(first: WindowState(id: WindowID(), workspaces: set, frame: frame, isFullScreen: true))

        _ = save.saveStructure(of: windows, at: SessionFixtures.savedAt)

        #expect(archive.saved?.windows.first?.frame == frame)
        #expect(archive.saved?.windows.first?.isFullScreen == true)
    }

    @Test func exportAsksForTheLastTenThousandLines() {
        _ = save.saveWithScrollback(of: set, at: SessionFixtures.savedAt)

        #expect(scrollback.requestedLines == [SaveSession.scrollbackLineLimit])
        #expect(SaveSession.scrollbackLineLimit == 10_000)
    }

    @Test func failingPaneExportStillSavesOthers() {
        let other = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
        let base = set
        let withTwoShells = base.updating(base.activeID) { $0.adding(other) }
        scrollback.failing = [shell.id]
        scrollback.contents[other.id] = Scrollback(text: "ok", format: .plain)

        let outcome = save.saveWithScrollback(of: withTwoShells, at: SessionFixtures.savedAt)

        #expect(outcome == .saved)
        #expect(archive.scrollback(of: other.id) != nil)
        #expect(archive.saved != nil)
    }

    @Test func saveForgetsClosedPanes() {
        let closed = PaneID()
        archive.transcripts[closed] = Scrollback(text: "old", format: .plain)

        _ = save.saveWithScrollback(of: set, at: SessionFixtures.savedAt)

        #expect(archive.scrollback(of: closed) == nil)
    }

    @Test func archiveFailureIsReported() {
        archive.writeFailure = .writeFailed(file: "session.json", reason: "disk full")

        #expect(save.saveStructure(of: set, at: SessionFixtures.savedAt) == .failed("session.json: disk full"))
    }

    @Test func loadStartsFreshWithoutSession() {
        #expect(LoadLastSession(archive: archive, preferences: archive).execute() == .startFresh)
    }

    @Test func loadAsksWhenPreferenceIsAsk() {
        _ = save.saveStructure(of: set, at: SessionFixtures.savedAt)
        let saved = archive.saved

        let choice = LoadLastSession(archive: archive, preferences: archive).execute()

        #expect(saved.map { choice == .ask($0) } == true)
    }

    @Test func loadRestoresAllWhenAlways() throws {
        _ = save.saveStructure(of: set, at: SessionFixtures.savedAt)
        try archive.set(.always)
        let saved = archive.saved

        let choice = LoadLastSession(archive: archive, preferences: archive).execute()

        #expect(saved.map { choice == .restoreAll($0) } == true)
    }

    @Test func loadReportsUnreadable() {
        archive.unreadableReason = "bad JSON"

        #expect(
            LoadLastSession(archive: archive, preferences: archive).execute()
                == .startFreshAfterUnreadable(reason: "bad JSON"))
    }
}

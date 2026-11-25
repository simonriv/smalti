import FileSessionAdapter
import Foundation
import SmaltiCore
import Testing

/// F4.5: sessions with windows (format 2), and the ones F2–F4 saved (format 1) still open.
@MainActor
@Suite("FileSessionArchive · v2")
struct FileSessionArchiveV2Tests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-archive-v2-\(UUID())")

    private func file(_ name: String) -> URL { directory.appending(path: name) }

    private func writeFixture(_ name: String) throws {
        let source = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: file("session.json"))
    }

    @Test func readsV1FixtureAsOneWindow() throws {
        try writeFixture("session-v1")

        guard case .saved(let snapshot) = FileSessionArchive(directory: directory).lastSession() else {
            Issue.record("the format-1 session was not read")
            return
        }

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].frame == nil)
        #expect(snapshot.windows[0].activeIndex == 1)
        #expect(snapshot.workspaces.map(\.name) == ["solen", "billi"])
        #expect(snapshot.workspaces[0].panes[1].agent?.sessionID == "7f3a9c21")
        #expect(snapshot.workspaces[1].panes[0].relaunch?.arguments == ["nvim", "+42"])
    }

    /// F6: what 0.5.6 saved (non-optional session id and state, no editor) still opens.
    @Test func decodesSnapshotSavedBy056() throws {
        try writeFixture("session-v2-0.5.6")

        guard case .saved(let snapshot) = FileSessionArchive(directory: directory).lastSession() else {
            Issue.record("the 0.5.6 session was not read")
            return
        }

        let panes = snapshot.workspaces[0].panes
        #expect(
            panes[0].agent
                == AgentSnapshot(
                    harness: .claude, sessionID: "7f3a9c2e-1111", title: "Agendar",
                    lastState: .waiting))
        #expect(panes.allSatisfy { $0.editor == nil })
        #expect(panes[2].relaunch?.arguments == ["pnpm", "dev"])
    }

    @Test func encodesWithoutEditorAsBefore() throws {
        try writeFixture("session-v2-0.5.6")
        let archive = FileSessionArchive(directory: directory)
        guard case .saved(let snapshot) = archive.lastSession() else {
            Issue.record("the 0.5.6 session was not read")
            return
        }

        try archive.save(snapshot)

        let saved = try String(contentsOf: file("session.json"), encoding: .utf8)
        #expect(!saved.contains("\"editor\""))
        #expect(saved.contains("\"lastState\" : \"waiting\""))
    }

    @Test func v1IsSavedBackAsV2() throws {
        try writeFixture("session-v1")
        let archive = FileSessionArchive(directory: directory)
        guard case .saved(let snapshot) = archive.lastSession() else {
            Issue.record("the format-1 session was not read")
            return
        }

        try archive.save(snapshot)

        let text = try String(contentsOf: file("session.json"), encoding: .utf8)
        #expect(text.contains("\"version\" : 2"))
        guard case .saved(let reread) = archive.lastSession() else {
            Issue.record("the session saved back was not read")
            return
        }
        #expect(reread.version == 2)
        #expect(reread.windows == snapshot.windows)
    }

    @Test func writesV2WithFrames() throws {
        let window = WindowSnapshot(
            frame: Rect(x: 10, y: 20, width: 800, height: 600), isFullScreen: true, workspaces: [], activeIndex: 0)
        let snapshot = SessionSnapshot(
            version: 2, savedAt: Date(timeIntervalSince1970: 1_800_000_000), windows: [window], frontIndex: 0)
        let archive = FileSessionArchive(directory: directory)

        try archive.save(snapshot)

        #expect(archive.lastSession() == .saved(snapshot))
    }

    /// F7.6: format 3 belongs to a newer Smalti, so it stays where it is (it used to be set aside).
    @Test func v3IsKeptAsNewer() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":3,"savedAt":"2026-11-22T00:00:00Z","windows":[],"frontIndex":0}"#.utf8)
            .write(to: file("session.json"))

        let last = FileSessionArchive(directory: directory).lastSession()

        #expect(last == .newer(version: 3))
        #expect(FileManager.default.fileExists(atPath: file("session.json").path(percentEncoded: false)))
    }
}

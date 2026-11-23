import FileSessionAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("FileSessionArchive")
struct FileSessionArchiveTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-archive-\(UUID())")
    private var path: String { directory.path(percentEncoded: false) }

    private func file(_ name: String) -> URL { directory.appending(path: name) }

    private func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            version: SessionSnapshot.formatVersion, savedAt: Date(timeIntervalSince1970: 1_800_000_000),
            workspaces: [], activeIndex: 0)
    }

    @Test func archiveSatisfiesContract() throws {
        try SessionArchiveContract.verify {
            FileSessionArchive(directory: directory.appending(path: UUID().uuidString))
        }
    }

    @Test func layoutsSatisfyContract() throws {
        try NamedLayoutsContract.verify { FileSessionArchive(directory: directory.appending(path: UUID().uuidString)) }
    }

    @Test func directoryIsCreatedWith0700() throws {
        try FileSessionArchive(directory: directory).save(snapshot())

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect(attributes[.posixPermissions] as? Int == 0o700)
    }

    @Test func snapshotIsReadableJSON() throws {
        try FileSessionArchive(directory: directory).save(snapshot())

        let text = try String(contentsOf: file("session.json"), encoding: .utf8)
        #expect(text.contains("\"version\" : 2"))
    }

    @Test func scrollbackRoundTripsCompressed() throws {
        let archive = FileSessionArchive(directory: directory)
        let line = "\u{1B}[32mverde\u{1B}[0m una línea de salida bastante repetida\n"
        let text = Scrollback(text: String(repeating: line, count: 10_000), format: .vt)
        let pane = PaneID()

        try archive.keep(text, for: pane)

        let stored = file("scrollback/\(pane).lzfse")
        let size = try FileManager.default.attributesOfItem(atPath: stored.path(percentEncoded: false))[.size] as? Int
        #expect(archive.scrollback(of: pane) == text)
        #expect((size ?? .max) < text.text.utf8.count / 4)
    }

    @Test func plainFormatSurvivesTheRoundTrip() throws {
        let archive = FileSessionArchive(directory: directory)
        let pane = PaneID()

        try archive.keep(Scrollback(text: "hola", format: .plain), for: pane)

        #expect(archive.scrollback(of: pane)?.format == .plain)
    }

    @Test func corruptSnapshotIsMovedAsideAndReported() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ no es json".utf8).write(to: file("session.json"))

        let last = FileSessionArchive(directory: directory).lastSession()

        guard case .unreadable = last else {
            Issue.record("expected unreadable, got \(last)")
            return
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: path)
        #expect(!names.contains("session.json"))
        #expect(names.contains { $0.hasPrefix("session.corrupt-") && $0.hasSuffix(".json") })
    }

    @Test func unknownVersionIsMovedAside() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":99,"savedAt":"2026-11-22T00:00:00Z","workspaces":[],"activeIndex":0}"#.utf8)
            .write(to: file("session.json"))

        let last = FileSessionArchive(directory: directory).lastSession()

        guard case .unreadable(let reason) = last else {
            Issue.record("expected unreadable, got \(last)")
            return
        }
        #expect(reason.contains("99"))
    }

    @Test func interruptedWriteKeepsPreviousSnapshot() throws {
        let archive = FileSessionArchive(directory: directory)
        let good = snapshot()
        try archive.save(good)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path) }

        #expect(throws: SessionArchiveError.self) {
            try archive.save(
                SessionSnapshot(version: 1, savedAt: .now, workspaces: [], activeIndex: 3))
        }
        #expect(archive.lastSession() == .saved(good))
    }

    @Test func forgetRemovesOrphanScrollbackAndHistory() throws {
        let archive = FileSessionArchive(directory: directory)
        let kept = PaneID()
        let orphan = PaneID()
        let files = PaneFileLocator(stateDirectory: directory)
        try archive.keep(Scrollback(text: "a", format: .plain), for: kept)
        try archive.keep(Scrollback(text: "b", format: .plain), for: orphan)
        try FileManager.default.createDirectory(at: files.historyDirectory, withIntermediateDirectories: true)
        try Data("echo hola\n".utf8).write(to: files.historyFile(for: orphan))
        try Data("ls\n".utf8).write(to: files.historyFile(for: kept))

        archive.forget(allExcept: [kept])

        #expect(!FileManager.default.fileExists(atPath: files.historyFile(for: orphan).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: files.historyFile(for: kept).path(percentEncoded: false)))
        #expect(archive.scrollback(of: orphan) == nil)
    }

    @Test func forgetTrimsLongPaneHistoriesToTheirLastLines() throws {
        let archive = FileSessionArchive(directory: directory)
        let pane = PaneID()
        let files = PaneFileLocator(stateDirectory: directory)
        try FileManager.default.createDirectory(at: files.historyDirectory, withIntermediateDirectories: true)
        let history = (1...10_005).map { "echo \($0)" }.joined(separator: "\n") + "\n"
        try Data(history.utf8).write(to: files.historyFile(for: pane))

        archive.forget(allExcept: [pane])

        let kept = try String(contentsOf: files.historyFile(for: pane), encoding: .utf8).split(separator: "\n")
        #expect(kept.count == FileSessionArchive.historyLineLimit)
        #expect(kept.first == "echo 6")
        #expect(kept.last == "echo 10005")
    }

    @Test func trimmingNeverStartsInsideAMultiLineEntry() throws {
        let archive = FileSessionArchive(directory: directory)
        let pane = PaneID()
        let files = PaneFileLocator(stateDirectory: directory)
        try FileManager.default.createDirectory(at: files.historyDirectory, withIntermediateDirectories: true)
        let head = (1...4).map { "echo \($0)" }.joined(separator: "\n")
        let multi = "for i in 1 2; do\\\necho $i\\\ndone"
        let tail = (1...(FileSessionArchive.historyLineLimit - 2)).map { "ls \($0)" }.joined(separator: "\n")
        try Data((head + "\n" + multi + "\n" + tail + "\n").utf8).write(to: files.historyFile(for: pane))

        archive.forget(allExcept: [pane])

        let kept = try String(contentsOf: files.historyFile(for: pane), encoding: .utf8)
        #expect(!kept.hasPrefix("echo $i") && !kept.hasPrefix("done"))
    }

    @Test func anUnreadableSnapshotIsReportedNotIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: file("session.json"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: file("session.json").path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: file("session.json").path(percentEncoded: false))
        }

        guard case .unreadable = FileSessionArchive(directory: directory).lastSession() else {
            Issue.record("a session.json that cannot be read must not look like no session")
            return
        }
        #expect(FileManager.default.fileExists(atPath: file("session.json").path(percentEncoded: false)))
    }

    @Test func preferenceIsStoredInPreferencesJSON() throws {
        let archive = FileSessionArchive(directory: directory)

        try archive.set(.always)

        let text = try String(contentsOf: file("preferences.json"), encoding: .utf8)
        #expect(text.contains("always"))
        #expect(FileSessionArchive(directory: directory).current() == .always)
    }

    @Test func layoutFileNameComesFromLayoutName() throws {
        let archive = FileSessionArchive(directory: directory)
        let workspace = WorkspaceSnapshot(
            name: "solen", rootDirectory: "/tmp", layout: "dwindle", tree: nil, focusedIndex: nil, panes: [])

        try archive.save(workspace, as: try LayoutName("solen dev"))

        #expect(FileManager.default.fileExists(atPath: file("layouts/solen dev.json").path(percentEncoded: false)))
    }
}

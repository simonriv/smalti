import FileSessionAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("FileCommandHistory")
struct FileCommandHistoryTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-history-\(UUID())")
    private var file: URL { directory.appending(path: "input/history.jsonl") }

    private func entry(_ command: String, at seconds: TimeInterval = 1_800_000_000) -> HistoryEntry {
        HistoryEntry(
            command: command, directory: "/repo", exit: 0, duration: 0.25, date: Date(timeIntervalSince1970: seconds),
            pane: PaneID())
    }

    @Test func fulfillsTheContract() async {
        await CommandHistoryContract.verify {
            FileCommandHistory(
                file: FileManager.default.temporaryDirectory.appending(path: "smalti-history-\(UUID())/h.jsonl"),
                limit: 100)
        }
    }

    @Test func missingFileLoadsEmpty() async throws {
        #expect(try await FileCommandHistory(file: file, limit: 10).load().isEmpty)
    }

    @Test func partialLastLineIsSkipped() async throws {
        let history = FileCommandHistory(file: file, limit: 10)
        try await history.append(entry("ls"))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"command\":\"half".utf8))
        try handle.close()

        let loaded = try await FileCommandHistory(file: file, limit: 10).load()

        #expect(loaded.map(\.command) == ["ls"])
    }

    @Test func unreadableLineDoesNotStopLoad() async throws {
        let history = FileCommandHistory(file: file, limit: 10)
        try await history.append(entry("one"))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        try await history.append(entry("two"))

        let reader = FileCommandHistory(file: file, limit: 10)
        let loaded = try await reader.load()

        #expect(loaded.map(\.command) == ["one", "two"])
        #expect(await reader.skippedLines == 1)
    }

    @Test func compactsWhenOverLimit() async throws {
        let history = FileCommandHistory(file: file, limit: 10)
        for index in 0..<13 { try await history.append(entry("cmd \(index)", at: 1_800_000_000 + Double(index))) }

        let loaded = try await FileCommandHistory(file: file, limit: 10).load()
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")

        #expect(loaded.map(\.command) == (3..<13).map { "cmd \($0)" })
        #expect(lines.count == 10)
    }

    @Test func doesNotCompactWithinTheMargin() async throws {
        let history = FileCommandHistory(file: file, limit: 10)
        for index in 0..<12 { try await history.append(entry("cmd \(index)")) }

        _ = try await FileCommandHistory(file: file, limit: 10).load()

        #expect(try String(contentsOf: file, encoding: .utf8).split(separator: "\n").count == 12)
    }

    @Test func fileIsOwnerOnly() async throws {
        try await FileCommandHistory(file: file, limit: 10).append(entry("ls"))

        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[
            .posixPermissions]
        let folderMode = try FileManager.default.attributesOfItem(
            atPath: file.deletingLastPathComponent().path(percentEncoded: false))[.posixPermissions]
        #expect(fileMode as? Int == 0o600)
        #expect(folderMode as? Int == 0o700)
    }

    @Test func appendErrorCarriesFileAndCause() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: directory.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directory.path(percentEncoded: false))
        }

        await #expect {
            try await FileCommandHistory(file: file, limit: 10).append(entry("ls"))
        } throws: { error in
            (error as? HistoryError).map { $0.operation == "append" && $0.file == file.path(percentEncoded: false) }
                ?? false
        }
    }

    // Block 2 review m1: an append after a crash mid-line starts on a line of its own.
    @Test func appendAfterACutLineKeepsTheNewEntry() async throws {
        let history = FileCommandHistory(file: file, limit: 10)
        try await history.append(entry("before"))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"comm".utf8))
        try handle.close()

        try await FileCommandHistory(file: file, limit: 10).append(entry("after crash"))
        let loaded = try await FileCommandHistory(file: file, limit: 10).load()

        #expect(loaded.map(\.command) == ["before", "after crash"])
    }
}

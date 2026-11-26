import FileSessionAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("FileWelcomeRecord")
struct FileWelcomeRecordTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "smalti-welcome-\(UUID().uuidString)")
    }

    @Test func followsTheContract() async {
        let base = folder()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(await WelcomeRecordContract.problems { FileWelcomeRecord(directory: base) }.isEmpty)
    }

    @Test func writesItsVersionedFile() async throws {
        let base = folder()
        defer { try? FileManager.default.removeItem(at: base) }

        try await FileWelcomeRecord(directory: base).markDone()

        let text = try String(contentsOf: base.appending(path: "welcome.json"), encoding: .utf8)
        #expect(text.contains("\"version\":1") || text.contains("\"version\" : 1"))
    }

    @Test func aNewerFileCountsAsDone() async throws {
        let base = folder()
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data(#"{"version":2}"#.utf8).write(to: base.appending(path: "welcome.json"))

        #expect(await FileWelcomeRecord(directory: base).isDone)
    }

    @Test func anUnwritableFolderIsReported() async throws {
        let blocker = folder()
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("x".utf8).write(to: blocker)

        await #expect(throws: WelcomeRecordError.self) {
            try await FileWelcomeRecord(directory: blocker).markDone()
        }
    }
}

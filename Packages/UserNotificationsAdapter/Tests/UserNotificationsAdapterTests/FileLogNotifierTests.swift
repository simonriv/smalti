import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing
import UserNotificationsAdapter

@MainActor
@Suite("FileLogNotifier")
struct FileLogNotifierTests {
    private let file = FileManager.default.temporaryDirectory.appending(path: "smalti-notices-\(UUID()).jsonl")

    @Test func fileLogSatisfiesTheNotifierContract() {
        let file = self.file
        NotifierContract.verify {
            (FileLogNotifier(file: file), { FileLogNotifier.read(file) })
        }
    }

    @Test func eachNoticeIsOneJSONLine() throws {
        let pane = PaneID()

        FileLogNotifier(file: file).notify(
            AttentionNotice(pane: pane, title: "rizaria/web", body: "terminó y te espera"))

        let line = try String(contentsOf: file, encoding: .utf8)
        #expect(line.hasSuffix("\n"))
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String]
        #expect(object == ["pane": pane.description, "title": "rizaria/web", "body": "terminó y te espera"])
    }
}

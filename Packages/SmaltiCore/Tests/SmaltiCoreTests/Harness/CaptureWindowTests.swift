import Foundation
import SmaltiCore
import Testing

@Suite("Capture window")
struct CaptureWindowTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String = "s", directory: String = "/tmp/w", created offset: TimeInterval)
        -> HarnessSession
    {
        let created = start.addingTimeInterval(offset)
        return HarnessSession(
            harness: .codex, id: id, directory: directory, title: "t", createdAt: created, updatedAt: created,
            detail: nil)
    }

    @Test func admitsSessionCreatedFromMarginBeforeStart() {
        let window = CaptureWindow(directory: "/private/tmp/w", processStartedAt: start, excludedIDs: [])

        #expect(window.admits(session(created: -2)))
        #expect(window.admits(session(created: 30)))
        #expect(!window.admits(session(created: -2.001)))
    }

    @Test func rejectsOtherDirectoryAndExcludedIds() {
        let window = CaptureWindow(directory: "/tmp/w", processStartedAt: start, excludedIDs: ["taken"])

        #expect(!window.admits(session(directory: "/tmp/other", created: 1)))
        #expect(!window.admits(session("taken", created: 1)))
    }

    @Test func oldestAdmittedWins() {
        let window = CaptureWindow(directory: "/tmp/w", processStartedAt: start, excludedIDs: [])

        let chosen = window.choose([session("old", created: -60), session("a", created: 1), session("b", created: 5)])

        #expect(chosen == "a")
    }

    @Test func sessionCreatedAfterALaterStartBelongsToThatPane() {
        let window = CaptureWindow(
            directory: "/tmp/w", processStartedAt: start, excludedIDs: [], laterStarts: [start.addingTimeInterval(10)])

        #expect(window.admits(session(created: 5)))
        #expect(!window.admits(session(created: 9)))
        #expect(!window.admits(session(created: 20)))
    }
}

import Foundation
import SmaltiCore
import Testing

@Suite("TimelineTarget")
struct TimelineTargetTests {
    private let readable: Set<HarnessID> = [.claude, .codex]
    private let at = Date(timeIntervalSince1970: 1_795_000_000)

    private func pane() throws -> Pane {
        Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/w/api"))
    }

    private func withHooks(_ pane: Pane, session: String = "c1") -> Pane {
        pane.applying(AgentEvent(pane: pane.id, hook: .sessionStart, at: at, sessionID: session)).0
    }

    @Test func aShellPaneHasNoAgent() throws {
        #expect(TimelineTarget.resolve(pane: try pane(), running: nil, readable: readable) == .noAgent)
    }

    @Test func hooksNameTheSession() throws {
        #expect(
            TimelineTarget.resolve(pane: withHooks(try pane()), running: .claude, readable: readable)
                == .session(.claude, "c1"))
    }

    @Test func hooksWinOverABinding() throws {
        let bound = withHooks(try pane()).binding(
            HarnessBinding(harness: .codex, sessionID: "x9", processStartedAt: at))

        #expect(TimelineTarget.resolve(pane: bound, running: nil, readable: readable) == .session(.claude, "c1"))
    }

    @Test func theSessionStaysAfterLeavingForTheShell() throws {
        #expect(
            TimelineTarget.resolve(pane: withHooks(try pane()), running: nil, readable: readable)
                == .session(.claude, "c1"))
    }

    @Test func aBindingWithIDNamesTheSession() throws {
        let bound = try pane().binding(HarnessBinding(harness: .codex, sessionID: "x9", processStartedAt: at, pid: 4))

        #expect(TimelineTarget.resolve(pane: bound, running: .codex, readable: readable) == .session(.codex, "x9"))
    }

    @Test func aRunningHarnessWithoutIDIsUnidentified() throws {
        #expect(
            TimelineTarget.resolve(pane: try pane(), running: .codex, readable: readable)
                == .unidentified(.codex, directory: "/w/api"))
    }

    @Test func aBindingWithoutIDIsUnidentified() throws {
        let bound = try pane().binding(HarnessBinding(harness: .codex, sessionID: nil, processStartedAt: at))

        #expect(
            TimelineTarget.resolve(pane: bound, running: nil, readable: readable)
                == .unidentified(.codex, directory: "/w/api"))
    }

    @Test func aHarnessWithoutReadableTranscriptIsUnreadable() throws {
        let bound = try pane().binding(HarnessBinding(harness: .antigravity, sessionID: "g1", processStartedAt: at))

        #expect(TimelineTarget.resolve(pane: bound, running: nil, readable: readable) == .unreadable(.antigravity))
        #expect(
            TimelineTarget.resolve(pane: try pane(), running: .opencode, readable: readable) == .unreadable(.opencode))
    }
}

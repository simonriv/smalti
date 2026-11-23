import Foundation
import SmaltiCore
import Testing

@Suite("ObservedSession")
struct ObservedSessionTests {
    private typealias F = ObservatoryFixtures
    private let now = F.date("2026-11-18 10:42")

    private func merged(_ snapshot: ObservatorySnapshot) -> [String: ObservedSession] {
        Dictionary(uniqueKeysWithValues: ObservedSession.merge(snapshot).map { ($0.id, $0) })
    }

    @Test func paneStateWinsOverRegistryAndRowIsNotDuplicated() {
        let start = F.date("2026-11-18 10:00")
        let snapshot = F.snapshot(
            sessions: [F.session("s1", [F.turn("a", at: start)])],
            running: [F.running("s1", status: "busy", startedAt: start)],
            panes: [
                F.paneAgent(
                    "s1", state: .waiting(since: now, reason: .turnFinished), label: "rizaria/web", startedAt: start)
            ],
            now: now)

        let sessions = ObservedSession.merge(snapshot)

        #expect(sessions.count == 1)
        #expect(sessions.first?.state == .waiting)
        #expect(sessions.first?.label == "rizaria/web")
        #expect(sessions.first?.pane != nil)
        #expect(sessions.first?.pid == 48_213)
    }

    @Test func busyIsWorkingIdleIsWaiting() {
        let start = F.date("2026-11-18 10:00")
        let snapshot = F.snapshot(
            sessions: [],
            running: [
                F.running("a", pid: 1, status: "busy", startedAt: start),
                F.running("b", pid: 2, status: "idle", startedAt: start),
            ],
            now: now)

        let sessions = merged(snapshot)

        #expect(sessions["a"]?.state == .working)
        #expect(sessions["b"]?.state == .waiting)
    }

    @Test func unknownStatusIsWorkingAndReported() {
        let snapshot = F.snapshot(sessions: [], running: [F.running("a", status: "thinking", startedAt: now)], now: now)

        #expect(merged(snapshot)["a"]?.state == .working)
        #expect(ObservedSession.unknownStatuses(in: snapshot.running) == ["thinking"])
    }

    @Test func deadSessionIsStopped() {
        let snapshot = F.snapshot(
            sessions: [F.session("gone", [F.turn("a", at: F.date("2026-11-18 07:00"))])], now: now)

        #expect(merged(snapshot)["gone"]?.state == .stopped)
        #expect(merged(snapshot)["gone"]?.pid == nil)
    }

    @Test func labelUsesLastTwoPathComponents() {
        let snapshot = F.snapshot(sessions: [F.session("a", cwd: "/Users/simon/dev/solen/api", [])], now: now)

        #expect(merged(snapshot)["a"]?.label == "solen/api")
    }

    @Test func labelUnderHomeUsesOneComponent() {
        let snapshot = F.snapshot(
            sessions: [F.session("a", cwd: "/Users/simon/termotty", []), F.session("b", cwd: "/Users/simon", [])],
            now: now)

        #expect(merged(snapshot)["a"]?.label == "termotty")
        #expect(merged(snapshot)["b"]?.label == "~")
    }

    @Test func liveSessionWithoutTurnsShowsZeroAndNoContext() {
        let snapshot = F.snapshot(sessions: [], running: [F.running("fresh", startedAt: now)], now: now)

        let session = merged(snapshot)["fresh"]

        #expect(session?.activity.buckets.isEmpty == true)
        #expect(session?.activity.contextTokens == nil)
        #expect(session?.label == "solen/api")
    }

    @Test func paneAgentWithoutProcessIsLiveUntilItStops() {
        let start = F.date("2026-11-18 10:00")
        let working = F.snapshot(sessions: [], panes: [F.paneAgent("w", state: .working, startedAt: start)], now: now)
        let stopped = F.snapshot(sessions: [], panes: [F.paneAgent("s", state: .stopped, startedAt: start)], now: now)

        #expect(merged(working)["w"]?.isLive == true)
        #expect(merged(stopped)["s"]?.isLive == false)
    }

    @Test func processWithoutPaneIsLive() {
        #expect(
            merged(F.snapshot(sessions: [], running: [F.running("p", startedAt: now)], now: now))["p"]?.isLive == true)
    }
}

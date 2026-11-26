import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("ShowTimeline")
struct ShowTimelineTests {
    private typealias F = TimelineFixtures
    private let ref = TranscriptSessionRef(harness: .claude, sessionID: "c1", file: F.file, subagentFolder: nil)

    private func session(_ id: String, _ harness: HarnessID = .claude, updated: Double = 0) -> HarnessSession {
        HarnessSession(
            harness: harness, id: id, directory: "/w", title: "t \(id)", createdAt: F.start,
            updatedAt: F.start.addingTimeInterval(updated), detail: nil)
    }

    private func make(_ transcripts: FakeSessionTranscripts, projects: [FakeProjectTranscripts] = []) -> ShowTimeline {
        ShowTimeline(sources: TranscriptSources(sessions: [transcripts], projects: projects))
    }

    private func shown(_ show: ShowTimeline) -> ShowTimeline.TimelineSession? {
        if case .session(let session) = show.state { session } else { nil }
    }

    @Test func showsTheSessionsTimeline() async throws {
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB])
        let show = make(transcripts)

        await show.show(.session(.claude, "c1"), root: "/w")

        let session = try #require(shown(show))
        #expect(session.timeline.turnCount == 3)
        #expect(session.ref == ref)
        #expect(!session.isUnidentified)
        #expect(show.isWatching)
    }

    @Test func aChangeReadsOnlyFromTheCursor() async throws {
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [Array(F.workB.prefix(6)), Array(F.workB.dropFirst(6))])
        let show = make(transcripts)
        await show.show(.session(.claude, "c1"), root: "/w")
        await waitUntil { await transcripts.watchers == 1 }

        await transcripts.change(ref)
        await waitUntil { (shown(show)?.timeline.turnCount ?? 0) == 3 }

        #expect(await transcripts.cursorsRead(ref) == [0, 1])
        #expect(shown(show)?.timeline == Timeline().appending(F.workB))
    }

    @Test func aRestartedReadRebuildsTheTimeline() async throws {
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB, [F.prompt("nuevo", at: 1)]], restartAt: 1)
        let show = make(transcripts)
        await show.show(.session(.claude, "c1"), root: "/w")
        await waitUntil { await transcripts.watchers == 1 }

        await transcripts.change(ref)
        await waitUntil { shown(show)?.timeline.turnCount == 1 }

        #expect(shown(show)?.timeline == Timeline().appending([F.prompt("nuevo", at: 1)]))
    }

    @Test func closingStopsWatchingAndForgets() async {
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB])
        let show = make(transcripts)
        await show.show(.session(.claude, "c1"), root: "/w")
        await waitUntil { await transcripts.watchers == 1 }

        show.close()
        await waitUntil { await transcripts.watchers == 0 }

        #expect(show.state == .closed)
        #expect(!show.isWatching)
        #expect(await transcripts.watchers == 0)
    }

    @Test func switchingDuringASlowReadNeverShowsTheOldSession() async throws {
        let other = TranscriptSessionRef(harness: .claude, sessionID: "c2", file: "/fx/o.jsonl", subagentFolder: nil)
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB])
        await transcripts.add(other, reads: [[F.prompt("otra", at: 1)]])
        await transcripts.slowDown(ref, .milliseconds(200))
        let show = make(transcripts)

        async let first: Void = show.show(.session(.claude, "c1"), root: "/w")
        try await Task.sleep(for: .milliseconds(20))
        await show.show(.session(.claude, "c2"), root: "/w")
        await first

        #expect(shown(show)?.ref == other)
        await waitUntil { await transcripts.watchers == 1 }
        #expect(await transcripts.watchers == 1)
    }

    /// Review 1 (M8): a session that cannot be read any more says so instead of staying painted.
    @Test func aFailedReadWhileFollowingFails() async throws {
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB])
        let show = make(transcripts)
        await show.show(.session(.claude, "c1"), root: "/w")
        await waitUntil { await transcripts.watchers == 1 }

        await transcripts.failReads(ref, with: .missing(path: F.file))
        await transcripts.change(ref)
        await waitUntil { if case .failed = show.state { true } else { false } }

        #expect(show.state == .failed(.missing(path: F.file)))
    }

    /// Review 1 (M10): switching sessions cancels the read on its way.
    @Test func switchingCancelsTheReadOnItsWay() async throws {
        let other = TranscriptSessionRef(harness: .claude, sessionID: "c2", file: "/fx/o.jsonl", subagentFolder: nil)
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB])
        await transcripts.add(other, reads: [[F.prompt("otra", at: 1)]])
        await transcripts.slowDown(ref, .seconds(1))
        let show = make(transcripts)

        async let first: Void = show.show(.session(.claude, "c1"), root: "/w")
        try await Task.sleep(for: .milliseconds(30))
        await show.show(.session(.claude, "c2"), root: "/w")
        await first

        #expect(await transcripts.cancelledReads == 1)
    }

    @Test func anUnidentifiedPaneShowsTheLatestSessionMarked() async throws {
        let codexRef = TranscriptSessionRef(harness: .codex, sessionID: "x2", file: "/fx/x2.jsonl", subagentFolder: nil)
        let transcripts = FakeSessionTranscripts(harness: .codex)
        await transcripts.add(codexRef, reads: [[F.prompt("p", at: 1)]])
        let projects = FakeProjectTranscripts(
            harness: .codex, sessions: [session("x1", .codex), session("x2", .codex, updated: 9)])
        let show = make(transcripts, projects: [projects])

        await show.show(.unidentified(.codex, directory: "/w/web"), root: "/w")

        let session = try #require(shown(show))
        #expect(session.ref == codexRef)
        #expect(session.isUnidentified)
        #expect(await projects.lastRoot == "/w/web")
    }

    @Test func noAgentListsTheProjectsRecentSessionsNewestFirst() async {
        let claude = FakeProjectTranscripts(
            harness: .claude, sessions: [session("a", updated: 1), session("b", updated: 5)])
        let codex = FakeProjectTranscripts(harness: .codex, sessions: [session("x", .codex, updated: 3)])
        let show = make(FakeSessionTranscripts(harness: .claude), projects: [claude, codex])

        await show.show(.noAgent, root: "/w")

        #expect(
            show.state
                == .empty(recent: [
                    session("b", updated: 5), session("x", .codex, updated: 3), session("a", updated: 1),
                ]))
    }

    @Test func anUnreadableHarnessSaysSoWithTheRecentSessions() async {
        let claude = FakeProjectTranscripts(harness: .claude, sessions: [session("a")])
        let show = make(FakeSessionTranscripts(harness: .claude), projects: [claude])

        await show.show(.unreadable(.antigravity), root: "/w")

        #expect(show.state == .unreadable(.antigravity, recent: [session("a")]))
    }

    @Test func aMissingOrCompressedSessionFails() async {
        let transcripts = FakeSessionTranscripts(harness: .codex)
        await transcripts.fail("old", with: .compressed(path: "/x.jsonl.zst"))
        let show = make(transcripts)

        await show.show(.session(.codex, "old"), root: "/w")

        #expect(show.state == .failed(.compressed(path: "/x.jsonl.zst")))
        #expect(!show.isWatching)
    }

    @Test func opensAChosenSession() async throws {
        let transcripts = FakeSessionTranscripts(harness: .claude)
        await transcripts.add(ref, reads: [F.workB])
        let show = make(transcripts)

        await show.open(session("c1"))

        #expect(shown(show)?.ref == ref)
    }
}

/// Polls `condition` for at most two seconds (spec rule: every wait in a test is bounded).
@MainActor
func waitUntil(_ condition: @MainActor () async -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while await !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

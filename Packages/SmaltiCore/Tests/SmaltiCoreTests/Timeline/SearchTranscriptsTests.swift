import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("SearchTranscripts")
struct SearchTranscriptsTests {
    private typealias F = TimelineFixtures

    private func hit(_ session: String, _ text: String, _ harness: HarnessID = .claude) -> TranscriptHit {
        TranscriptHit(
            session: HarnessSession(
                harness: harness, id: session, directory: "/w", title: session, createdAt: F.start,
                updatedAt: F.start, detail: nil),
            entry: F.prompt(text, at: 1), text: text)
    }

    private func make(_ projects: [FakeProjectTranscripts]) -> SearchTranscripts {
        SearchTranscripts(
            sources: TranscriptSources(sessions: [], projects: projects), debounce: .milliseconds(30))
    }

    @Test func findsAcrossHarnessesInOrder() async {
        let claude = FakeProjectTranscripts(harness: .claude, hits: [hit("s1", "reembolso parcial")])
        let codex = FakeProjectTranscripts(harness: .codex, hits: [hit("x1", "el reembolso", .codex)])
        let search = make([claude, codex])

        search.update(query: "reembolso", root: "/w")
        await waitUntil { !search.isSearching && search.results.matchCount == 2 }

        #expect(search.results.groups.map(\.session.id) == ["s1", "x1"])
        #expect(await claude.lastRoot == "/w")
        #expect(await claude.lastQuery == TimelineQuery("reembolso"))
    }

    @Test func typingQuicklySearchesOnce() async throws {
        let claude = FakeProjectTranscripts(harness: .claude, hits: [hit("s1", "abc")])
        let search = make([claude])

        search.update(query: "a", root: "/w")
        search.update(query: "ab", root: "/w")
        search.update(query: "abc", root: "/w")
        await waitUntil { !search.isSearching && search.results.matchCount == 1 }

        #expect(await claude.searches == 1)
    }

    @Test func cancellingStopsAddingResults() async throws {
        let claude = FakeProjectTranscripts(harness: .claude, hits: (0..<50).map { hit("s\($0)", "x \($0)") })
        await claude.slowDown(.milliseconds(20))
        let search = make([claude])

        search.update(query: "x", root: "/w")
        try await Task.sleep(for: .milliseconds(120))
        search.cancel()
        let count = search.results.matchCount
        try await Task.sleep(for: .milliseconds(150))

        #expect(search.results.matchCount == count)
        #expect(count < 50)
        #expect(!search.isSearching)
    }

    @Test func anEmptyQueryClearsWithoutSearching() async throws {
        let claude = FakeProjectTranscripts(harness: .claude, hits: [hit("s1", "abc")])
        let search = make([claude])

        search.update(query: "  ", root: "/w")
        try await Task.sleep(for: .milliseconds(60))

        #expect(await claude.searches == 0)
        #expect(search.results.matchCount == 0)
        #expect(!search.isSearching)
    }
}

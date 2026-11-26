import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("SearchTranscripts")
struct SearchTranscriptsTests {
    private typealias F = TimelineFixtures

    private func hit(_ session: String, _ text: String, _ harness: HarnessID = .claude, updated: Double = 0)
        -> TranscriptHit
    {
        TranscriptHit(
            session: HarnessSession(
                harness: harness, id: session, directory: "/w", title: session, createdAt: F.start,
                updatedAt: F.start.addingTimeInterval(updated), detail: nil),
            entry: F.prompt(text, at: 1), text: text)
    }

    private func make(_ projects: [FakeProjectTranscripts]) -> SearchTranscripts {
        SearchTranscripts(
            sources: TranscriptSources(sessions: [], projects: projects), policy: VerbatimText(),
            debounce: .milliseconds(30))
    }

    @Test func findsAcrossHarnessesInOrder() async {
        let claude = FakeProjectTranscripts(harness: .claude, hits: [hit("s1", "reembolso parcial", updated: 5)])
        let codex = FakeProjectTranscripts(harness: .codex, hits: [hit("x1", "el reembolso", .codex, updated: 1)])
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

    /// Review 2 (I2): closing the timeline or going back to the session leaves no query or results behind.
    @Test func clearingForgetsTheQueryAndTheResults() async {
        let claude = FakeProjectTranscripts(harness: .claude, hits: [hit("s1", "abc")])
        let search = make([claude])
        search.update(query: "abc", root: "/w")
        await waitUntil { search.results.matchCount == 1 && !search.isSearching }

        search.clear()

        #expect(search.results.matchCount == 0)
        #expect(search.query.isEmpty)
        #expect(!search.isSearching)
    }

    @Test func startsIdle() {
        #expect(!make([]).isSearching)
    }

    /// Mutation: every match of a harness counts, and the search says when it is done.
    @Test func keepsEveryMatchAndFinishes() async {
        let claude = FakeProjectTranscripts(harness: .claude, hits: (1...3).map { hit("s\($0)", "x \($0)") })
        let search = make([claude])

        search.update(query: "x", root: "/w")
        await waitUntil { !search.isSearching }

        #expect(search.results.matchCount == 3)
        #expect(!search.isSearching)
    }

    @Test func aNewQueryClearsTheOldResultsAtOnce() async {
        let claude = FakeProjectTranscripts(harness: .claude, hits: [hit("s1", "abc")])
        let search = make([claude])
        search.update(query: "abc", root: "/w")
        await waitUntil { search.results.matchCount == 1 && !search.isSearching }

        search.update(query: "zzz", root: "/w")

        #expect(search.results.matchCount == 0)
    }

    /// Mutation: once capped, the harness stops yielding (nothing more is read).
    @Test func aCappedSearchStopsReading() async {
        let claude = FakeProjectTranscripts(
            harness: .claude, hits: (0..<(SearchResults.cap + 50)).map { hit("s", "x \($0)") })
        await claude.slowDown(.milliseconds(2))
        let search = make([claude])

        search.update(query: "x", root: "/w")
        await waitUntil { !search.isSearching }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(search.results.isCapped)
        #expect(await claude.delivered < SearchResults.cap + 40)
    }

    /// Mutation: when one harness fills the cap, the other one stops reading too.
    @Test func theCapStopsEveryHarness() async {
        let claude = FakeProjectTranscripts(
            harness: .claude, hits: (0..<(SearchResults.cap + 10)).map { hit("s", "x \($0)") })
        let codex = FakeProjectTranscripts(harness: .codex, hits: (0..<60).map { hit("c", "x \($0)", .codex) })
        await codex.slowDown(.milliseconds(10))
        let search = make([claude, codex])

        search.update(query: "x", root: "/w")
        await waitUntil { !search.isSearching }
        try? await Task.sleep(for: .milliseconds(150))

        #expect(search.results.isCapped)
        #expect(await codex.delivered < 30)
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

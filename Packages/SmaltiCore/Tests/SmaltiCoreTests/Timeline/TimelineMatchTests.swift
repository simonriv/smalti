import Foundation
import SmaltiCore
import Testing

@Suite("TimelineMatch")
struct TimelineMatchTests {
    private typealias F = TimelineFixtures

    @Test func foldsCaseAndAccents() {
        #expect(TimelineQuery("Ñandú Áéí").folded == "nandu aei")
        #expect(TimelineQuery("  ").isEmpty)
    }

    @Test(arguments: [
        ("reembolso parcial", "reembolso parcial"), ("Ñandú", "nandu"), ("ab", ""), ("say \"hola\"", "say "),
        ("Canción", "cancion"), ("a\\b\\cdef", "cdef"), ("precio €", "precio €"),
    ])
    func theNeedleIsTheLongestPieceJSONKeepsAsItIs(query: String, needle: String) {
        #expect(String(decoding: TimelineQuery(query).needle, as: UTF8.self) == needle)
    }

    @Test func findsIgnoringCaseAndAccentsOnTheOriginalText() throws {
        let text = "El Reembolso PARCIAL se calcula"

        let range = try #require(TimelineMatch.find(TimelineQuery("reembolso parcial"), in: text))

        #expect(text[range] == "Reembolso PARCIAL")
        #expect(TimelineMatch.find(TimelineQuery("canción"), in: "una CANCION vieja") != nil)
        #expect(TimelineMatch.find(TimelineQuery("nada"), in: text) == nil)
    }

    @Test func theSnippetKeepsTheMatchInView() throws {
        let text = String(repeating: "x ", count: 200) + "aguja" + String(repeating: " y", count: 200)
        let range = try #require(TimelineMatch.find(TimelineQuery("aguja"), in: text))

        let (snippet, inSnippet) = TimelineMatch.snippet(text, around: range, width: 40)

        #expect(snippet[inSnippet] == "aguja")
        #expect(snippet.count <= 42)
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
    }

    private func hit(_ session: String, _ text: String) -> TranscriptHit {
        TranscriptHit(
            session: HarnessSession(
                harness: .claude, id: session, directory: "/w", title: session, createdAt: F.start, updatedAt: F.start,
                detail: nil),
            entry: F.prompt(text, at: 1), text: text)
    }

    private func hit(_ session: String, _ text: String, updated: Double = 0) -> TranscriptHit {
        TranscriptHit(
            session: HarnessSession(
                harness: .claude, id: session, directory: "/w", title: session, createdAt: F.start,
                updatedAt: F.start.addingTimeInterval(updated), detail: nil),
            entry: F.prompt(text, at: 1), text: text)
    }

    private func adding(_ hits: [TranscriptHit], _ query: String, policy: any TranscriptTextPolicy = VerbatimText())
        -> SearchResults
    {
        hits.reduce(SearchResults()) { results, hit in
            SearchResults.confirm(hit, query: TimelineQuery(query), policy: policy).map { results.adding($0) }
                ?? results
        }
    }

    @Test func resultsKeepOnlyConfirmedHitsGroupedBySession() {
        let results = adding(
            [
                hit("s1", "reembolso parcial"), hit("s1", "{\"type\":\"zzz\"} sin texto"),
                hit("s2", "Parcial otra vez"),
                hit("s1", "más parcial"),
            ], "parcial")

        #expect(results.matchCount == 3)
        #expect(results.groups.map(\.session.id) == ["s1", "s2"])
        #expect(results.groups[0].matches.count == 2)
    }

    /// Review 1 (M11): groups go newest session first, whichever harness found them first.
    @Test func groupsAreOrderedNewestFirst() {
        let results = adding(
            [hit("old", "x", updated: 1), hit("new", "x", updated: 9), hit("mid", "x", updated: 5)], "x")

        #expect(results.groups.map(\.session.id) == ["new", "mid", "old"])
    }

    @Test func resultsStopAtTheCap() {
        let results = adding((0..<(SearchResults.cap + 5)).map { hit("s", "x \($0)") }, "x")

        #expect(results.matchCount == SearchResults.cap)
        #expect(results.isCapped)
    }

    /// Review 1 (I4): what a match shows and what it is confirmed on is the policy's search snippet.
    @Test func matchesGoThroughThePolicyAndKeepOnlyASnippet() throws {
        let spy = SpyPolicy()
        let long = String(repeating: "a ", count: 5_000) + "aguja" + String(repeating: " b", count: 5_000)

        let match = try #require(SearchResults.confirm(hit("s", long), query: TimelineQuery("aguja"), policy: spy))

        #expect(spy.seen.map(\.1) == [.searchSnippet])
        #expect(match.snippet.contains("aguja"))
        #expect(match.snippet.count < 200)
        #expect(match.snippet[match.range] == "aguja")
    }

    @Test func aPolicyThatHidesTheTextHidesTheMatch() {
        struct Masking: TranscriptTextPolicy {
            func shown(_ text: String, as context: TranscriptTextContext) -> String {
                text.replacingOccurrences(of: "sk-123", with: "•••")
            }
        }

        #expect(
            SearchResults.confirm(hit("s", "token sk-123"), query: TimelineQuery("sk-123"), policy: Masking()) == nil)
    }
}

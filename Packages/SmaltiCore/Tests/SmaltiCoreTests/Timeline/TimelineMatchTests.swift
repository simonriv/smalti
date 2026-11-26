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

    @Test func resultsKeepOnlyConfirmedHitsGroupedBySession() {
        let query = TimelineQuery("parcial")

        let results = SearchResults()
            .adding(hit("s1", "reembolso parcial"), query: query)
            .adding(hit("s1", "{\"type\":\"parcial\"} sin texto"), query: TimelineQuery("zzz"))
            .adding(hit("s2", "Parcial otra vez"), query: query)
            .adding(hit("s1", "más parcial"), query: query)

        #expect(results.matchCount == 3)
        #expect(results.groups.map(\.session.id) == ["s1", "s2"])
        #expect(results.groups[0].matches.count == 2)
    }

    @Test func resultsStopAtTheCap() {
        let query = TimelineQuery("x")

        let results = (0..<(SearchResults.cap + 5)).reduce(SearchResults()) {
            $0.adding(hit("s", "x \($1)"), query: query)
        }

        #expect(results.matchCount == SearchResults.cap)
        #expect(results.isCapped)
    }
}

import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("HighlightLine")
struct HighlightLineTests {
    private static let git = CompletionSpec(name: ["git"], subcommands: [CompletionSpec(name: ["status"])])

    private final class Now: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1000)
    }

    private func line(_ text: String) -> InputLine { InputLine(text: text, cursor: text.unicodeScalars.count) }

    private func highlighter(
        paths: InMemoryPathFacts = InMemoryPathFacts(), completions: FakeCompletionProvider = FakeCompletionProvider(),
        now: Now = Now()
    ) -> HighlightLine {
        HighlightLine(
            paths: paths, completions: completions, timing: HighlightTiming(budget: .milliseconds(3)) { now.date })
    }

    private func paths(in spans: [HighlightSpan]) -> [Range<Int>] {
        spans.filter { $0.role == .path }.map(\.range)
    }

    @Test func existingPathGetsPathSpan() async {
        let facts = InMemoryPathFacts(kinds: ["/w/README.md": .file])

        let answer = await highlighter(paths: facts).firstAnswer(line("cat README.md"), directory: "/w", home: "/h")

        #expect(paths(in: answer.spans) == [4..<13])
        #expect(answer.isComplete)
    }

    @Test func missingPathGetsNoSpan() async {
        let answer = await highlighter().firstAnswer(line("cat nope"), directory: "/w", home: "/h")

        #expect(paths(in: answer.spans).isEmpty)
        #expect(answer.isComplete)
    }

    @Test func relativeTildeAndAbsoluteResolve() async {
        let facts = InMemoryPathFacts(kinds: ["/h/a": .directory, "/w/b": .file, "/c": .file])

        let answer = await highlighter(paths: facts).firstAnswer(line("ls ~/a b /c ~"), directory: "/w", home: "/h")

        #expect(paths(in: answer.spans) == [3..<6, 7..<8, 9..<11])
        #expect(Set(await facts.queried) == ["/h/a", "/w/b", "/c", "/h"])
    }

    @Test func otherUsersTildeIsNotQueried() async {
        let facts = InMemoryPathFacts()

        _ = await highlighter(paths: facts).firstAnswer(line("ls ~root/x"), directory: "/w", home: "/h")

        #expect(await facts.queried.isEmpty)
    }

    @Test func slowPathsAnswerWithoutThemAfterBudget() async {
        let facts = InMemoryPathFacts(kinds: ["/w/a": .file], delay: .milliseconds(300))
        let subject = highlighter(paths: facts)
        let start = ContinuousClock.now

        let first = await subject.firstAnswer(line("cat a"), directory: "/w", home: "/h")

        #expect(ContinuousClock.now - start < .milliseconds(150))
        #expect(paths(in: first.spans).isEmpty)
        #expect(!first.isComplete)
        let complete = await subject.completeAnswer(line("cat a"), directory: "/w", home: "/h")
        #expect(paths(in: complete) == [4..<5])
    }

    @Test func cacheAvoidsRequeryWithinTwoSeconds() async {
        let facts = InMemoryPathFacts(kinds: ["/w/a": .file])
        let now = Now()
        let subject = highlighter(paths: facts, now: now)

        _ = await subject.firstAnswer(line("cat a"), directory: "/w", home: "/h")
        _ = await subject.firstAnswer(line("cat a "), directory: "/w", home: "/h")
        #expect(await facts.queried.count == 1)
        now.date += 2.1
        _ = await subject.firstAnswer(line("cat a"), directory: "/w", home: "/h")

        #expect(await facts.queried.count == 2)
    }

    @Test func unloadedSpecGivesNoSubcommandsAndIncomplete() async {
        let completions = FakeCompletionProvider(specs: [Self.git], loaded: [])
        let subject = highlighter(completions: completions)

        let first = await subject.firstAnswer(line("git status"), directory: "/w", home: "/h")

        #expect(!first.spans.contains { $0.role == .subcommand })
        #expect(!first.isComplete)
        let complete = await subject.completeAnswer(line("git status"), directory: "/w", home: "/h")
        #expect(complete.contains(HighlightSpan(range: 4..<10, role: .subcommand)))
    }

    @Test func loadedSpecGivesSubcommandsAtOnce() async {
        let completions = FakeCompletionProvider(specs: [Self.git])

        let first = await highlighter(completions: completions).firstAnswer(
            line("git status"), directory: "/w", home: "/h")

        #expect(first.spans.contains(HighlightSpan(range: 4..<10, role: .subcommand)))
        #expect(first.isComplete)
    }

    @Test func commandWithoutAnySpecIsComplete() async {
        let answer = await highlighter().firstAnswer(line("make x"), directory: "/w", home: "/h")

        #expect(answer.isComplete)
    }

    @Test func atMost16PathQueriesPerLine() async {
        let facts = InMemoryPathFacts()
        let words = (1...20).map { "f\($0)" }.joined(separator: " ")

        _ = await highlighter(paths: facts).firstAnswer(line("ls " + words), directory: "/w", home: "/h")

        #expect(await facts.queried.count == 16)
    }

    @Test func pathSpanFollowsItsWordSpans() async {
        let facts = InMemoryPathFacts(kinds: ["/w/a b": .file])

        let answer = await highlighter(paths: facts).firstAnswer(line("cat 'a b'"), directory: "/w", home: "/h")

        #expect(
            answer.spans == [
                HighlightSpan(range: 0..<3, role: .command), HighlightSpan(range: 4..<9, role: .string),
                HighlightSpan(range: 4..<9, role: .path),
            ])
    }
}

@Suite("InMemoryPathFacts")
struct InMemoryPathFactsTests {
    @Test func honoursPathFactsContract() async throws {
        try await PathFactsContract.verify {
            let sample = PathFactsSample.standard(root: "/r")
            return (InMemoryPathFacts(kinds: sample.kinds), sample)
        }
    }
}

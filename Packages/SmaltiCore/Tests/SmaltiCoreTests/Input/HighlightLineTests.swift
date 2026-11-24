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

extension HighlightLineTests {
    private static let xargs = CompletionSpec(name: ["xargs"], args: [ArgSpec(name: "command", isCommand: true)])

    @Test func commandFromIsCommandGetsItsSpec() async {
        let completions = FakeCompletionProvider(specs: [Self.xargs, Self.git])

        let answer = await highlighter(completions: completions).firstAnswer(
            line("xargs git status"), directory: "/w", home: "/h")

        #expect(answer.spans.contains(HighlightSpan(range: 10..<16, role: .subcommand)))
        #expect(answer.isComplete)
    }

    @Test func lateLookupFillsCache() async throws {
        let facts = InMemoryPathFacts(kinds: ["/w/a": .file], delay: .milliseconds(40))
        let subject = highlighter(paths: facts)
        _ = await subject.firstAnswer(line("cat a"), directory: "/w", home: "/h")

        try await Task.sleep(for: .milliseconds(200))
        let again = await subject.firstAnswer(line("cat a"), directory: "/w", home: "/h")

        #expect(await facts.queried.count == 1)
        #expect(again.spans.contains(HighlightSpan(range: 4..<5, role: .path)))
        #expect(again.isComplete)
    }

    @Test func lateLookupIsNotReusedAfterExpiry() async throws {
        let facts = InMemoryPathFacts(kinds: ["/w/a": .file], delay: .milliseconds(40))
        let now = Now()
        let subject = highlighter(paths: facts, now: now)
        _ = await subject.firstAnswer(line("cat a"), directory: "/w", home: "/h")
        try await Task.sleep(for: .milliseconds(200))

        now.date += 3
        _ = await subject.completeAnswer(line("cat a"), directory: "/w", home: "/h")

        #expect(await facts.queried.count == 2)
    }

    @Test func completeAnswerGivesUpAfterLimit() async {
        let facts = InMemoryPathFacts(kinds: ["/w/a": .file], delay: .seconds(5))
        let subject = HighlightLine(
            paths: facts, completions: FakeCompletionProvider(),
            timing: HighlightTiming(budget: .milliseconds(3), completeLimit: .milliseconds(100)) { Date() })
        let start = ContinuousClock.now

        let spans = await subject.completeAnswer(line("cat a"), directory: "/w", home: "/h")

        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(!spans.contains { $0.role == .path })
    }
}

/// A command that is listed with a spec whose loading fails (`FigSpecs.failed`).
private actor BrokenSpecProvider: CompletionProvider {
    var commands: [String] { ["broken"] }
    func spec(for command: String) async -> CompletionSpec? { nil }
    func loadedSpec(for command: String) async -> CompletionSpec? { nil }
    func generate(_ generator: GeneratorID, tokens: [String], in directory: String) async throws(CompletionError)
        -> [Suggestion]
    { [] }
    func paths(matching prefix: String, in directory: String, foldersOnly: Bool) async -> [Suggestion] { [] }
}

@Suite("HighlightLine · broken specs")
struct HighlightLineBrokenSpecTests {
    /// Final review (M1): once loading a spec failed, the line is complete; no follow-up on every keystroke.
    @Test func failedSpecIsNotWaitedForAgain() async {
        let subject = HighlightLine(paths: InMemoryPathFacts(), completions: BrokenSpecProvider())
        let line = InputLine(text: "broken x", cursor: 8)
        let first = await subject.firstAnswer(line, directory: "/w", home: "/h")
        _ = await subject.completeAnswer(line, directory: "/w", home: "/h")

        let again = await subject.firstAnswer(line, directory: "/w", home: "/h")

        #expect(!first.isComplete)
        #expect(again.isComplete)
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

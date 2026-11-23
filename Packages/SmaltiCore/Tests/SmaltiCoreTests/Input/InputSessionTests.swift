import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Input contracts")
struct InputContractTests {
    @Test func inMemoryHistoryFulfillsTheContract() async {
        await CommandHistoryContract.verify { InMemoryCommandHistory() }
    }

    @Test func fakeProjectContextFulfillsTheContract() async {
        await ProjectContextContract.verify { _ in FakeProjectContext() }
    }
}

@Suite("InputSession")
struct InputSessionTests {
    private let pane = HistoryFixture.pane
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        history: InMemoryCommandHistory = InMemoryCommandHistory(),
        completions: FakeCompletionProvider = FakeCompletionProvider(), settings: InputSettings = .standard
    ) -> InputSession {
        let clock = now
        return InputSession(
            ports: InputSession.Ports(
                history: history, project: FakeProjectContext(), completions: completions,
                predictor: HeuristicPredictor()),
            settings: settings, clock: { clock })
    }

    private func line(_ text: String) -> InputLine { InputLine(text: text, cursor: text.unicodeScalars.count) }

    @Test func suggestUsesPredictor() async {
        let history = InMemoryCommandHistory(entries: [historyEntry("git status", at: 999_000)])
        let session = session(history: history)
        await session.start()

        #expect(await session.suggest(line("git s"), pane: pane, directory: "/repo") == "tatus")
    }

    @Test func suggestDisabledReturnsEmpty() async {
        var settings = InputSettings.standard
        settings.hasPredictions = false
        let history = InMemoryCommandHistory(entries: [historyEntry("git status", at: 999_000)])
        let session = session(history: history, settings: settings)
        await session.start()

        #expect(await session.suggest(line("git s"), pane: pane, directory: "/repo") == "")
    }

    @Test func completeWithoutSpecReturnsNil() async {
        #expect(await session().complete(line("npm r"), directory: "/repo") == nil)
    }

    @Test func completeWithInputDisabledReturnsNil() async {
        var settings = InputSettings.standard
        settings.isEnabled = false
        let completions = FakeCompletionProvider(specs: [SpecFixtures.git])

        #expect(
            await session(completions: completions, settings: settings).complete(line("git ch"), directory: "/") == nil)
    }

    @Test func completeRanksFixedSuggestions() async {
        let completions = FakeCompletionProvider(specs: [SpecFixtures.git])

        let items = await session(completions: completions).complete(line("git ch"), directory: "/repo")

        #expect(items?.map(\.name) == ["checkout", "cherry-pick", "check-ignore"])
    }

    @Test func completeAddsTemplatePaths() async {
        let completions = FakeCompletionProvider(
            specs: [SpecFixtures.cd], paths: [Suggestion(name: "Projects/"), Suggestion(name: "Public/")])

        let items = await session(completions: completions).complete(line("cd Pro"), directory: "/Users/s")

        #expect(items?.map(\.name) == ["Projects/"])
        #expect(
            await completions.pathRequests == [PathRequest(prefix: "Pro", directory: "/Users/s", foldersOnly: true)])
    }

    @Test func generatedFailureReturnsEmpty() async {
        let generator = GeneratorID(spec: "npm", path: ["run"], ordinal: 0)
        let npm = CompletionSpec(
            name: ["npm"], subcommands: [CompletionSpec(name: ["run"], args: [ArgSpec(generators: [generator])])])
        let completions = FakeCompletionProvider(specs: [npm], failing: [generator])

        let session = session(completions: completions)

        #expect(await session.generated(for: line("npm run "), directory: "/repo").isEmpty)
        #expect(await session.lastCompletionError == CompletionError(command: "npm", cause: "fake failure"))
    }

    @Test func specWithNothingToCompleteReturnsEmpty() async {
        let completions = FakeCompletionProvider(specs: [CompletionSpec(name: ["true"])])

        #expect(await session(completions: completions).complete(line("true x"), directory: "/") == [])
    }

    @Test func generatedItemsAreRankedByPrefix() async {
        let generator = GeneratorID(spec: "npm", path: ["run"], ordinal: 0)
        let npm = CompletionSpec(
            name: ["npm"], subcommands: [CompletionSpec(name: ["run"], args: [ArgSpec(generators: [generator])])])
        let completions = FakeCompletionProvider(
            specs: [npm], generated: [generator: [Suggestion(name: "dev"), Suggestion(name: "test")]])

        let items = await session(completions: completions).generated(for: line("npm run te"), directory: "/repo")

        #expect(items.map(\.name) == ["test"])
    }

    @Test func recordMeasuresDuration() async {
        let history = InMemoryCommandHistory()
        let session = session(history: history)
        await session.start()

        await session.began("swift test", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 1)

        let stored = await history.entries
        #expect(stored.map(\.command) == ["swift test"])
        #expect(stored.first?.exit == 1)
        #expect(stored.first?.duration == 0)
        #expect(stored.first?.directory == "/repo")
    }

    @Test func recordSkipsSensitive() async {
        let history = InMemoryCommandHistory()
        let session = session(history: history)
        await session.start()

        await session.began("export OPENAI_API_KEY=abc", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 0)

        #expect(await history.entries.isEmpty)
    }

    @Test func recordWithoutBeganIsIgnored() async {
        let history = InMemoryCommandHistory()
        let session = session(history: history)

        await session.finished(pane: pane, exit: 0)

        #expect(await history.entries.isEmpty)
    }

    @Test func recordedCommandFeedsTheNextPrediction() async {
        let session = session()
        await session.start()

        for _ in 0..<2 {
            await session.began("git add .", pane: pane, directory: "/repo")
            await session.finished(pane: pane, exit: 0)
            await session.began("git commit", pane: pane, directory: "/repo")
            await session.finished(pane: pane, exit: 0)
        }
        await session.began("git add .", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 0)

        #expect(await session.suggest(line(""), pane: pane, directory: "/repo") == "git commit")
    }

    @Test func searchUsesScope() async {
        let history = InMemoryCommandHistory(entries: [
            historyEntry("make", in: "/a"), historyEntry("make test", in: "/b"),
        ])
        let session = session(history: history)
        await session.start()

        let hits = await session.search("make", scope: .directory("/a"))

        #expect(hits.map(\.stats.command) == ["make"])
    }

    @Test func startLoadsHistoryOnce() async {
        let history = InMemoryCommandHistory(entries: [historyEntry("ls")])
        let session = session(history: history)

        await session.start()
        await session.start()

        #expect(await history.loads == 1)
    }

    @Test func failedLoadStartsEmptyAndKeepsTheError() async {
        let history = InMemoryCommandHistory()
        await history.failLoading(with: HistoryError(operation: "load", file: "h.jsonl", cause: "corrupt"))
        let session = session(history: history)

        await session.start()

        #expect(await session.lastError == HistoryError(operation: "load", file: "h.jsonl", cause: "corrupt"))
        #expect(await session.search("", scope: .all).isEmpty)
    }

    @Test func specCommandsComeFromTheProvider() async {
        let completions = FakeCompletionProvider(specs: [SpecFixtures.git, SpecFixtures.cd])

        #expect(await session(completions: completions).specCommands == ["cd", "git"])
    }
}

@Suite("InputSettings")
struct InputSettingsTests {
    @Test func inputSettingsDefaults() {
        let settings = InputSettings.standard

        #expect(settings.isEnabled && settings.hasPredictions && settings.hasCompletions)
        #expect(settings.historyLimit == 100_000)
        #expect(settings.generatorTimeout == .milliseconds(1_000))
    }

    @Test func rangesMatchTheSpec() {
        #expect(InputSettings.historyLimitRange == 1...1_000_000)
        #expect(InputSettings.generatorTimeoutRange == 100...10_000)
    }

    @Test func configCarriesStandardInputSettings() {
        #expect(SmaltiConfig.defaults.input == .standard)
    }
}

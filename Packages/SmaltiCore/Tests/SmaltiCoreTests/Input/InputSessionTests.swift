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

    /// Final review m10: the index is read after the project snapshot arrives, so a command that ended meanwhile
    /// already counts (and the actor never copies the whole index across that wait).
    @Test func commandEndedWhileReadingTheProjectCounts() async {
        let project = HeldProjectContext()
        let clock = now
        let session = InputSession(
            ports: InputSession.Ports(
                history: InMemoryCommandHistory(), project: project, completions: FakeCompletionProvider(),
                predictor: HeuristicPredictor()),
            settings: .standard, clock: { clock })
        await session.start()

        let suggestion = Task { await session.suggest(line("mak"), pane: pane, directory: "/repo") }
        await project.waitUntilAsked()
        await session.began("make build", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 0)
        await project.release()

        #expect(await suggestion.value == "e build")
    }

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

        #expect(items?.items.map(\.name) == ["checkout", "cherry-pick", "check-ignore"])
        #expect(items?.hasGenerators == false)
    }

    @Test func completeAddsTemplatePaths() async {
        let completions = FakeCompletionProvider(
            specs: [SpecFixtures.cd], paths: [Suggestion(name: "Projects/"), Suggestion(name: "Public/")])

        let items = await session(completions: completions).complete(line("cd Pro"), directory: "/Users/s")

        #expect(items?.items.map(\.name) == ["Projects/"])
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

        #expect(
            await session(completions: completions).complete(line("true x"), directory: "/")
                == CompletionResult(items: [], hasGenerators: false))
    }

    @Test func generatorsReceiveTheWordsOfTheCommand() async {
        let generator = GeneratorID(spec: "git", path: ["checkout"], ordinal: 0)
        let git = CompletionSpec(
            name: ["git"], subcommands: [CompletionSpec(name: ["checkout"], args: [ArgSpec(generators: [generator])])])
        let completions = FakeCompletionProvider(specs: [git])

        _ = await session(completions: completions).generated(for: line("git checkout -r ma"), directory: "/repo")

        #expect(await completions.generateRequests.first?.tokens == ["git", "checkout", "-r", "ma"])
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

    // Mutation survivor (F4 close): a command that cannot be saved still counts, and the error is kept.
    @Test func failedAppendKeepsTheError() async {
        let history = InMemoryCommandHistory()
        await history.failAppending(with: HistoryError(operation: "append", file: "h.jsonl", cause: "disk full"))
        let session = session(history: history)
        await session.start()

        await session.began("ls", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 0)

        #expect(await session.lastError == HistoryError(operation: "append", file: "h.jsonl", cause: "disk full"))
        #expect(await session.search("ls", scope: .all).map(\.stats.command) == ["ls"])
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

    // Review I7: the menu must know that generated items are coming.
    @Test func completeReportsPendingGenerators() async {
        let generator = GeneratorID(spec: "git", path: ["checkout"], ordinal: 0)
        let git = CompletionSpec(
            name: ["git"], subcommands: [CompletionSpec(name: ["checkout"], args: [ArgSpec(generators: [generator])])])
        let completions = FakeCompletionProvider(specs: [git])

        let result = await session(completions: completions).complete(line("git checkout "), directory: "/repo")

        #expect(result == CompletionResult(items: [], hasGenerators: true))
    }

    // Review m6: commands recorded while the history loads are kept.
    @Test func commandsRecordedDuringLoadAreKept() async {
        let history = InMemoryCommandHistory(entries: [historyEntry("old", at: 1)])
        await history.holdLoads()
        let session = session(history: history)

        async let started: Void = session.start()
        await history.waitUntilLoading()
        await session.began("new", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 0)
        await history.releaseLoads()
        await started

        #expect(Set(await session.search("", scope: .all).map(\.stats.command)) == ["old", "new"])
    }

    // Review m7: with completions off, zsh must not wait for Smalti on Tab.
    @Test func specCommandsAreEmptyWithCompletionsOff() async {
        var settings = InputSettings.standard
        settings.hasCompletions = false
        let completions = FakeCompletionProvider(specs: [SpecFixtures.git])

        #expect(await session(completions: completions, settings: settings).specCommands.isEmpty)
    }

    // Review m12: a command kept out of the history also stops being "the previous command".
    @Test func sensitiveCommandClearsThePreviousCommand() async {
        let history = InMemoryCommandHistory(entries: [
            historyEntry("git push", exit: 1, at: 1), historyEntry("git push -u origin main", at: 2),
        ])
        let session = session(history: history)
        await session.start()
        await session.began("git push", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 1)

        await session.began("export GH_TOKEN=abc", pane: pane, directory: "/repo")
        await session.finished(pane: pane, exit: 0)

        #expect(await session.suggest(line(""), pane: pane, directory: "/repo") == "")
    }

    // Block 4 review m6: "Historial vacío" only when there is no history at all, not when a scope has none.
    @Test func historyIsEmptyUntilACommandIsRecorded() async {
        let session = session()
        await session.start()
        #expect(await session.isHistoryEmpty)

        await session.began("make", pane: pane, directory: "/a")
        await session.finished(pane: pane, exit: 0)

        #expect(await !session.isHistoryEmpty)
        #expect(await session.search("", scope: .directory("/b")).isEmpty)
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

/// A project context whose answer waits until the test releases it.
private actor HeldProjectContext: ProjectContext {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var askers: [CheckedContinuation<Void, Never>] = []
    private var isAsked = false

    func snapshot(of directory: String) async -> ProjectSnapshot {
        isAsked = true
        askers.forEach { $0.resume() }
        askers = []
        await withCheckedContinuation { waiting.append($0) }
        return .empty
    }

    func waitUntilAsked() async {
        guard !isAsked else { return }
        await withCheckedContinuation { askers.append($0) }
    }

    func release() {
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

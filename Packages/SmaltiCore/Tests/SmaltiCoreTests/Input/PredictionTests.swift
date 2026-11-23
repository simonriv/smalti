import Foundation
import SmaltiCore
import Testing

private let day: TimeInterval = 86_400

private func context(
    _ text: String, entries: [HistoryEntry] = [], previous: HistoryEntry? = nil, project: ProjectSnapshot = .empty,
    now: TimeInterval = 30 * day, directory: String = "/repo"
) -> PredictionContext {
    PredictionContext(
        line: InputLine(text: text, cursor: text.unicodeScalars.count), directory: directory, previous: previous,
        index: HistoryIndex(entries: entries, limit: 100_000), project: project,
        now: Date(timeIntervalSince1970: now))
}

private func score(_ command: String, in candidates: [Candidate]) -> Double {
    candidates.filter { $0.command == command }.map(\.score).reduce(0, +)
}

@Suite("DirectoryFrequency")
struct DirectoryFrequencyTests {
    @Test func frequencyDecaysWithHalfLife() {
        let entries = [
            historyEntry("old", at: 23 * day), historyEntry("old", at: 23 * day), historyEntry("new", at: 30 * day),
        ]

        let candidates = DirectoryFrequency().candidates(context("", entries: entries))

        #expect(abs(score("old", in: candidates) - score("new", in: candidates)) < 0.001)
    }

    @Test func currentDirectoryOutweighsOthers() {
        let entries = [
            historyEntry("here", in: "/repo", at: 30 * day), historyEntry("there", in: "/elsewhere", at: 30 * day),
        ]

        let candidates = DirectoryFrequency().candidates(context("", entries: entries))

        #expect(score("here", in: candidates) == 4 * score("there", in: candidates))
    }
}

@Suite("LearnedSequence")
struct LearnedSequenceTests {
    @Test func sequenceSuggestsSuccessorInDirectory() {
        let entries = [historyEntry("git add .", at: 1), historyEntry("git commit", at: 2)]

        let candidates = LearnedSequence().candidates(
            context("", entries: entries, previous: historyEntry("git add .")))

        #expect(candidates.map(\.command) == ["git commit"])
    }

    @Test func noPreviousCommandSuggestsNothing() {
        let entries = [historyEntry("git add .", at: 1), historyEntry("git commit", at: 2)]

        #expect(LearnedSequence().candidates(context("", entries: entries)).isEmpty)
    }
}

@Suite("ProjectCommands")
struct ProjectCommandsTests {
    private let project = ProjectSnapshot(
        scripts: ["test", "dev"], makeTargets: ["build"], branch: "main", branches: ["main", "feature/x"])

    @Test func projectSuggestsScriptsTargetsAndBranches() {
        let commands = Set(ProjectCommands().candidates(context("", project: project)).map(\.command))

        #expect(
            commands == [
                "npm run test", "npm run dev", "make build", "git checkout feature/x", "git switch feature/x",
            ])
    }

    @Test func projectSkipsCurrentBranch() {
        let commands = ProjectCommands().candidates(context("", project: project)).map(\.command)

        #expect(!commands.contains("git checkout main"))
    }
}

@Suite("ExitRecovery")
struct ExitRecoveryTests {
    @Test func recoveryAfterFailureUsesPastFix() {
        let entries = [historyEntry("swift tset", exit: 1, at: 1), historyEntry("swift test", at: 2)]
        let failed = historyEntry("swift tset", exit: 1, at: 3)

        let candidates = ExitRecovery().candidates(context("", entries: entries, previous: failed))

        #expect(candidates.map(\.command) == ["swift test"])
    }

    @Test func recoveryGitPushWithoutUpstream() {
        let failed = historyEntry("git push", exit: 128)
        let project = ProjectSnapshot(scripts: [], makeTargets: [], branch: "feature/x", branches: [])

        let candidates = ExitRecovery().candidates(context("", previous: failed, project: project))

        #expect(candidates.map(\.command) == ["git push -u origin feature/x"])
    }

    @Test func recoveryIgnoredAfterSuccess() {
        let entries = [historyEntry("swift tset", exit: 1, at: 1), historyEntry("swift test", at: 2)]

        let candidates = ExitRecovery().candidates(
            context("", entries: entries, previous: historyEntry("swift tset", exit: 0)))

        #expect(candidates.isEmpty)
    }
}

@Suite("HeuristicPredictor")
struct HeuristicPredictorTests {
    private let predictor = HeuristicPredictor()
    private let history = [
        historyEntry("git checkout -b feat/agent-monitor", at: 29 * day),
        historyEntry("git status", at: 29 * day),
        historyEntry("git status", at: 29 * day),
    ]

    @Test func predictorOnlyCompletesTypedPrefix() {
        let prediction = predictor.predict(context("git ch", entries: history))

        #expect(prediction == Prediction(suffix: "eckout -b feat/agent-monitor"))
    }

    @Test func predictorPrefersTheHigherScore() {
        #expect(predictor.predict(context("git ", entries: history)) == Prediction(suffix: "status"))
    }

    @Test func predictorNeverChangesWhatWasTyped() {
        #expect(predictor.predict(context("git Ch", entries: history)) == nil)
    }

    @Test func emptyLineUsesSequenceAndRecoveryOnly() {
        let entries = history + [historyEntry("git add .", at: 29 * day), historyEntry("git commit", at: 29 * day)]

        let withPrevious = predictor.predict(context("", entries: entries, previous: historyEntry("git add .")))
        let withoutPrevious = predictor.predict(context("", entries: entries))

        #expect(withPrevious == Prediction(suffix: "git commit"))
        #expect(withoutPrevious == nil)
    }

    @Test func cursorNotAtEndPredictsNothing() {
        let line = PredictionContext(
            line: InputLine(text: "git ch", cursor: 2), directory: "/repo", previous: nil,
            index: HistoryIndex(entries: history, limit: 10), project: .empty,
            now: Date(timeIntervalSince1970: 30 * day))

        #expect(predictor.predict(line) == nil)
    }

    @Test func emptyHistoryPredictsNothingWithoutProject() {
        #expect(predictor.predict(context("git")) == nil)
    }

    @Test func projectCommandsCompleteWithoutHistory() {
        let project = ProjectSnapshot(scripts: ["test"], makeTargets: [], branch: nil, branches: [])

        #expect(predictor.predict(context("npm r", project: project)) == Prediction(suffix: "un test"))
    }

    @Test func tiesBreakByRecency() {
        let entries = [historyEntry("make alpha", at: 29 * day), historyEntry("make beta", at: 29 * day + 60)]

        #expect(predictor.predict(context("make ", entries: entries)) == Prediction(suffix: "beta"))
    }

    @Test func exactMatchIsNotSuggested() {
        #expect(predictor.predict(context("git status", entries: history)) == nil)
    }
}

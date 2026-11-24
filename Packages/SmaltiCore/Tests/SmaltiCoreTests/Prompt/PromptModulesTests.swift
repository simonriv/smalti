import Foundation
import SmaltiCore
import Testing

/// Spec F5, the module table: what each module shows, and when it does not appear.
@Suite("Prompt modules")
struct PromptModulesTests {
    private func context(_ change: (inout PromptContext) -> Void = { _ in }) -> PromptContext {
        var context = PromptContext(directory: "/Users/simon/dev/solen/apps/api", home: "/Users/simon")
        change(&context)
        return context
    }

    private func text(_ id: PromptModuleID, _ context: PromptContext) -> String? {
        PromptModules.module(for: id).segment(in: context)?.text
    }

    @Test func everyIdHasItsModule() {
        #expect(PromptModuleID.allCases.allSatisfy { PromptModules.module(for: $0).id == $0 })
    }

    @Test func directoryInsideRepoShowsFromRoot() {
        let shown = text(.directory, context { $0.repoRoot = "/Users/simon/dev/solen" })

        #expect(shown == "solen/apps/api")
    }

    @Test func branchShowsName() {
        #expect(text(.gitBranch, context { $0.branch = "feat/reminders" }) == "feat/reminders")
    }

    @Test func noBranchHidesModule() {
        #expect(text(.gitBranch, context()) == nil)
    }

    @Test func gitStatusShowsModifiedAndStaged() throws {
        let segment = try #require(
            PromptModules.module(for: .gitStatus).segment(
                in: context { $0.changes = GitChanges(modified: 2, staged: 1) }))

        #expect(segment.text == "●2 +1")
        #expect(segment.runs.map(\.color) == [.ansi(3), .ansi(2)])
    }

    @Test func onlyModifiedShowsOnlyDot() {
        #expect(text(.gitStatus, context { $0.changes = GitChanges(modified: 3, staged: 0) }) == "●3")
    }

    @Test func cleanRepoHidesGitStatus() {
        #expect(text(.gitStatus, context { $0.changes = GitChanges(modified: 0, staged: 0) }) == nil)
        #expect(text(.gitStatus, context()) == nil)
    }

    @Test func runtimeShowsVersionWithIcon() throws {
        let segment = try #require(
            PromptModules.module(for: .runtime).segment(
                in: context { $0.runtime = RuntimeVersion(kind: .node, version: "22.11") }))

        #expect(segment.text == "22.11")
        #expect(segment.icon == .node)
    }

    @Test(arguments: [(RuntimeKind.bun, PromptIcon.bun), (.python, .python), (.go, .go)])
    func eachRuntimeHasItsIcon(_ kind: RuntimeKind, _ icon: PromptIcon) {
        let segment = PromptModules.module(for: .runtime).segment(
            in: context { $0.runtime = RuntimeVersion(kind: kind, version: "1.0") })

        #expect(segment?.icon == icon)
    }

    @Test func durationBelowTwoSecondsHidden() {
        #expect(text(.duration, context { $0.duration = .milliseconds(1999) }) == nil)
    }

    @Test func durationAtTwoSecondsShows() {
        #expect(text(.duration, context { $0.duration = .seconds(2) }) == "2.0s")
    }

    @Test func durationShowsOneDecimal() {
        #expect(text(.duration, context { $0.duration = .milliseconds(4_249) }) == "4.2s")
    }

    @Test func longDurationShowsMinutes() {
        #expect(text(.duration, context { $0.duration = .seconds(125) }) == "2m 5s")
    }

    @Test func agentsWaitingShowsName() throws {
        let segment = try #require(
            PromptModules.module(for: .agents).segment(in: context { $0.agents = WaitingAgents(waiting: ["claude"]) }))

        #expect(segment.text == "● claude te espera")
        #expect(segment.runs.allSatisfy { $0.color == .waiting })
    }

    @Test func twoWaitingShowsCount() {
        #expect(text(.agents, context { $0.agents = WaitingAgents(waiting: ["claude", "codex"]) }) == "● 2 te esperan")
    }

    @Test func failedShowsWhenNoneWaits() throws {
        let segment = try #require(
            PromptModules.module(for: .agents).segment(in: context { $0.agents = WaitingAgents(failed: ["claude"]) }))

        #expect(segment.text == "● claude falló")
        #expect(segment.runs.allSatisfy { $0.color == .failed })
    }

    @Test func waitingWinsOverFailed() {
        let shown = text(.agents, context { $0.agents = WaitingAgents(waiting: ["codex"], failed: ["claude"]) })

        #expect(shown == "● codex te espera")
    }

    @Test func noWaitingHidesModule() {
        #expect(text(.agents, context()) == nil)
    }

    @Test func timeShowsHoursAndMinutes() throws {
        let now = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(
                    timeZone: TimeZone(identifier: "America/Bogota"), year: 2026, month: 11, day: 23,
                    hour: 9, minute: 5)))

        let shown = text(
            .time,
            context {
                $0.now = now
                $0.timeZone = TimeZone(identifier: "America/Bogota") ?? .current
            })

        #expect(shown == "09:05")
    }

    @Test func cloudShowsProfileAndContext() {
        let shown = text(
            .cloud,
            context {
                $0.awsProfile = "prod"
                $0.kubeContext = "gke-west"
            })

        #expect(shown == "aws:prod k8s:gke-west")
    }

    @Test func cloudWithNothingHides() {
        #expect(text(.cloud, context()) == nil)
    }

    @Test func moduleOrderFollowsConfig() {
        var config = PromptConfig.standard
        config.modules = [.gitBranch, .directory]
        let context = context {
            $0.branch = "main"
            $0.repoRoot = "/Users/simon/dev/solen"
        }

        let ids = PromptModules.segments(for: config, in: context).map(\.module)

        #expect(ids == [.gitBranch, .directory])
    }

    @Test func absentModulesAreDropped() {
        let ids = PromptModules.segments(for: .standard, in: context()).map(\.module)

        #expect(ids == [.directory])
    }

    @Test func localModulesAreMarked() {
        let local = PromptModuleID.allCases.filter { PromptModules.module(for: $0).isLocal }

        #expect(local == [.directory, .duration, .time])
    }
}

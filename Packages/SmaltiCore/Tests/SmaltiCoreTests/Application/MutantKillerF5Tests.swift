import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Mutation (F5 blocks 2–3): every field of a rebase, every fact of a rendered prompt, and the Starship formats.
@MainActor
@Suite("Mutant killers · F5")
struct MutantKillerF5Tests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    /// Every field of the document set away from the defaults.
    private func everythingChanged() throws -> AppearanceDocument {
        var document = AppearanceDocument(config: .defaults)
        document.appearance.theme = .bosque
        document.appearance.accent = hex("#123456")
        document.appearance.glassOpacity = 0.9
        document.appearance.blur = 3
        document.appearance.fontFamily = "Menlo"
        document.appearance.fontSize = 17
        document.appearance.gap = 2
        document.appearance.radius = 4
        document.appearance.protectLegibility = false
        document.appearance.ansiOverrides = [.bosque: try ANSIOverrides([1: hex("#ff0000")])]
        document.buttons = .visible
        document.prompt = PromptConfig(
            source: .shell, style: .pills, layout: .oneLine, modules: [.time], icons: .nerd, symbol: .lambda)
        return document
    }

    @Test func rebaseKeepsEveryFieldTheUIChanged() throws {
        let base = AppearanceDocument(config: .defaults)
        let ui = try everythingChanged()

        #expect(ui.rebased(onto: base, from: base) == ui)
    }

    @Test func rebaseTakesEveryFieldOnlyTheFileChanged() throws {
        let base = AppearanceDocument(config: .defaults)
        let external = try everythingChanged()

        #expect(base.rebased(onto: external, from: base) == external)
    }

    @Test func documentAppliesItsAppearanceToConfig() throws {
        let document = try everythingChanged()

        let config = document.applied(to: .defaults)

        #expect(config.appearance == document.appearance)
    }

    @Test func renderedPromptCarriesEveryFact() async throws {
        var config = PromptConfig.standard
        config.modules = PromptModuleID.allCases
        let facts = FakePromptFacts(
            answers: [
                "/repo/web": PromptFactsResult(
                    repoRoot: "/repo", branch: "main", changes: GitChanges(modified: 2, staged: 0),
                    runtime: RuntimeVersion(kind: .node, version: "22.11"), kubeContext: "gke")
            ])
        let utc = try #require(TimeZone(identifier: "UTC"))
        let render = RenderPrompt(
            facts: facts,
            environment: PromptEnvironment(
                settings: { (config, ThemeCatalog.apply(.obsidian)) }, agents: { _ in WaitingAgents() },
                workspace: { _ in nil }, home: "/Users/simon", now: { Date(timeIntervalSince1970: 49_500) },
                timeZone: utc))
        let context = ShellContext(
            pwd: "/repo/web", exit: 0, durationMilliseconds: 4200, awsProfile: "prod", kubeconfig: nil,
            runtimePaths: [:])

        guard case .prompt(_, let prompt) = await render.handle(context, seq: 1, pane: PaneID()) else {
            Issue.record("no prompt")
            return
        }
        let values = Set(prompt.values.values)
        #expect(values.isSuperset(of: ["repo/web", "main", "●2", "22.11", "4.2s", "13:45", "aws:prod k8s:gke"]))
    }

    @Test func timeFollowsTheContextZoneNotTheMachine() throws {
        var context = PromptContext(directory: "/tmp", home: "/Users/simon")
        context.now = Date(timeIntervalSince1970: 0)
        context.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let shown = PromptModules.module(for: .time).segment(in: context)?.text

        #expect(shown == "09:00")
    }

    @Test func noIconsKeepTheSpaceBetweenBranchAndChanges() {
        var config = PromptConfig.standard
        config.icons = .none
        config.modules = [.gitBranch, .gitStatus]
        var context = PromptContext(directory: "/tmp", home: "/Users/simon")
        context.branch = "main"
        context.changes = GitChanges(modified: 2, staged: 0)

        let lines = PromptPreview.lines(config, context: context, theme: Theme.obsidian)

        #expect(lines.first?.map(\.text).joined() == "main ●2")
    }

    @Test func starshipFormatsWrapOnlyGitStatusAsOptional() {
        let clean = StarshipPreset.make(from: .standard, theme: ThemeCatalog.apply(.obsidian))
        let pills = StarshipPreset.make(from: PromptConfig.standard.applying(.pills), theme: ThemeCatalog.apply(.obsidian))

        #expect(clean.table("directory")?.value("format") == .string("[$path]($style) "))
        #expect(pills.table("directory")?.value("format") == .string("[ $path ]($style) "))
    }
}

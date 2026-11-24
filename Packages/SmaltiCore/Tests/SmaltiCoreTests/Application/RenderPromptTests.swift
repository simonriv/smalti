import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Spec F5: `context` → facts → `prompt`; agents that start waiting re-render the quiet prompts of their workspace.
@MainActor
@Suite("RenderPrompt")
struct RenderPromptTests {
    private let paneA = PaneID()
    private let paneB = PaneID()
    private let other = PaneID()
    private let workspace = WorkspaceID()
    private let otherWorkspace = WorkspaceID()

    private final class World {
        var config = PromptConfig.standard
        var agents: [PaneID: WaitingAgents] = [:]
    }

    private func make(
        facts: FakePromptFacts = FakePromptFacts(), world: World = World()
    ) -> (RenderPrompt, World) {
        let workspaces = [paneA: workspace, paneB: workspace, other: otherWorkspace]
        let environment = PromptEnvironment(
            settings: {
                var appearance = AppearanceSettings.obsidian
                appearance.protectLegibility = false
                return (world.config, ThemeCatalog.apply(appearance))
            },
            agents: { world.agents[$0] ?? WaitingAgents() },
            workspace: { workspaces[$0] },
            home: "/Users/simon",
            now: { Date(timeIntervalSince1970: 0) })
        return (RenderPrompt(facts: facts, environment: environment), world)
    }

    private func context(pwd: String = "/Users/simon/dev/solen", exit: Int = 0) -> ShellContext {
        ShellContext(pwd: pwd, exit: exit, durationMilliseconds: 0, awsProfile: nil, kubeconfig: nil, runtimePaths: [:])
    }

    private func rendered(_ message: SmaltiMessage?) -> (seq: Int, prompt: RenderedPrompt)? {
        guard case .prompt(let seq, let prompt) = message else { return nil }
        return (seq, prompt)
    }

    @Test func renderUsesFactsAndLocalContext() async {
        let facts = FakePromptFacts(
            answers: ["/Users/simon/dev/solen": PromptFactsResult(repoRoot: "/Users/simon/dev/solen", branch: "main")])
        let (render, _) = make(facts: facts)

        let answer = rendered(await render.handle(context(), seq: 4, pane: paneA))

        #expect(answer?.seq == 4)
        #expect(answer?.prompt.values.values.contains("main") == true)
        #expect(answer?.prompt.directoryLabel == "solen")
    }

    @Test func missingFactsDropModulesNotPrompt() async {
        let (render, _) = make()

        let answer = rendered(await render.handle(context(pwd: "/tmp"), seq: 1, pane: paneA))

        #expect(answer?.prompt.values["_smalti_p_1"] == "/tmp")
        #expect(answer?.prompt.values.count == 2)
    }

    @Test func exitReachesTheSymbol() async {
        let (render, _) = make()

        let answer = rendered(await render.handle(context(exit: 2), seq: 1, pane: paneA))

        #expect(answer?.prompt.values.values.contains(" exit 2") == true)
    }

    @Test func spontaneousPromptUsesLastContextSeq() async {
        let (render, world) = make()
        _ = await render.handle(context(), seq: 5, pane: paneA)
        _ = await render.handle(context(), seq: 8, pane: paneA)
        world.agents[paneA] = WaitingAgents(waiting: ["claude"])

        let updates = render.agentsChanged(in: workspace)

        #expect(updates.count == 1)
        #expect(updates.first?.pane == paneA)
        #expect(rendered(updates.first?.message)?.seq == 8)
        #expect(rendered(updates.first?.message)?.prompt.values.values.contains("● claude te espera") == true)
    }

    @Test func noSpontaneousPromptAfterExec() async {
        let (render, _) = make()
        _ = await render.handle(context(), seq: 5, pane: paneA)

        render.commandStarted(pane: paneA)

        #expect(render.agentsChanged(in: workspace).isEmpty)
    }

    @Test func onlyPanesOfSameWorkspaceAreNotified() async {
        let (render, _) = make()
        _ = await render.handle(context(), seq: 1, pane: paneA)
        _ = await render.handle(context(), seq: 1, pane: paneB)
        _ = await render.handle(context(), seq: 1, pane: other)

        let panes = Set(render.agentsChanged(in: workspace).map(\.pane))

        #expect(panes == [paneA, paneB])
    }

    @Test func shellSourceSendsNothing() async {
        let world = World()
        world.config.source = .shell
        let (render, _) = make(world: world)

        #expect(await render.handle(context(), seq: 1, pane: paneA) == nil)
        #expect(render.styleMessage() == nil)
    }

    @Test func styleMessageCarriesImmediateAndGhost() throws {
        let (render, _) = make()

        guard case .promptStyle(let prompt, let ghost) = render.styleMessage() else {
            Issue.record("no style message")
            return
        }
        #expect(prompt.immediate.contains("${_smalti_dir}"))
        #expect(ghost == (try RGBAColor(hex: "#5f6672")))
    }

    @Test func forgottenPaneIsNotNotified() async {
        let (render, _) = make()
        _ = await render.handle(context(), seq: 1, pane: paneA)

        render.forget(pane: paneA)

        #expect(render.agentsChanged(in: workspace).isEmpty)
    }
}

@Suite("FakePromptFacts contract")
struct FakePromptFactsContractTests {
    @Test func fakeHonorsTheContract() async {
        await PromptFactsContract.verify { FakePromptFacts() }
    }
}

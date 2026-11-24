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

        #expect(answer?.prompt.values["4"] == "/tmp")
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

    /// Block 5 review (I1): a hook that leaves the waiting agents as they were re-sends nothing.
    @Test func unchangedAgentsSendNothing() async {
        let (render, world) = make()
        _ = await render.handle(context(), seq: 5, pane: paneA)
        world.agents[paneA] = WaitingAgents(waiting: ["claude"])
        _ = render.agentsChanged(in: workspace)

        let again = render.agentsChanged(in: workspace)

        #expect(again.isEmpty)
    }

    @Test func agentsSentWithThePromptCountAsSent() async {
        let (render, world) = make()
        world.agents[paneA] = WaitingAgents(waiting: ["claude"])
        _ = await render.handle(context(), seq: 5, pane: paneA)

        #expect(render.agentsChanged(in: workspace).isEmpty)
    }

    @Test func noSpontaneousPromptAfterExec() async {
        let (render, _) = make()
        _ = await render.handle(context(), seq: 5, pane: paneA)

        render.commandStarted(pane: paneA)

        #expect(render.agentsChanged(in: workspace).isEmpty)
    }

    @Test func onlyPanesOfSameWorkspaceAreNotified() async {
        let (render, world) = make()
        _ = await render.handle(context(), seq: 1, pane: paneA)
        _ = await render.handle(context(), seq: 1, pane: paneB)
        _ = await render.handle(context(), seq: 1, pane: other)
        for pane in [paneA, paneB, other] { world.agents[pane] = WaitingAgents(waiting: ["claude"]) }

        let panes = Set(render.agentsChanged(in: workspace).map(\.pane))

        #expect(panes == [paneA, paneB])
    }

    @Test func shellSourceSendsNothing() async {
        let world = World()
        world.config.source = .shell
        let (render, _) = make(world: world)

        #expect(await render.handle(context(), seq: 1, pane: paneA) == nil)
        // An empty immediate prompt tells zsh to give the user's prompt back; the ghost color still travels.
        guard case .promptStyle(let prompt, let ghost) = render.styleMessage() else {
            Issue.record("no style message")
            return
        }
        #expect(prompt.immediate.isEmpty)
        #expect(prompt.values.isEmpty)
        #expect(ghost == (try? RGBAColor(hex: "#5f6672")))
    }

    @Test func styleMessageCarriesImmediateAndGhost() throws {
        let (render, _) = make()

        guard case .promptStyle(let prompt, let ghost) = render.styleMessage() else {
            Issue.record("no style message")
            return
        }
        #expect(prompt.immediate.contains("%2v"))
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

/// Block 2 review (I1, I2): `promptstyle` carries only what the immediate prompt references, and slow facts never
/// override a newer `context` nor revive a shell that started a command.
@MainActor
@Suite("RenderPrompt · review")
struct RenderPromptReviewTests {
    /// Facts for "/slow" wait until the test opens the gate; any other directory answers at once.
    private actor Gate: PromptFacts {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func facts(for query: PromptQuery) async -> PromptFactsResult {
            if query.directory == "/slow", !isOpen {
                await withCheckedContinuation { waiting.append($0) }
            }
            return PromptFactsResult(branch: query.directory == "/slow" ? "old" : "new")
        }

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting = []
        }

        var hasWaiter: Bool { !waiting.isEmpty }
    }

    private let pane = PaneID()
    private let workspace = WorkspaceID()

    /// Agents that tests make start waiting after the prompts, so a re-send has something new to show.
    private final class Agents {
        var waiting = WaitingAgents()
    }

    private let agents = Agents()

    private func make(_ facts: any PromptFacts) -> RenderPrompt {
        let workspace = workspace
        let agents = agents
        return RenderPrompt(
            facts: facts,
            environment: PromptEnvironment(
                settings: { (PromptConfig.standard, ThemeCatalog.apply(.obsidian)) },
                agents: { _ in agents.waiting },
                workspace: { _ in workspace }, home: "/Users/simon", now: { Date(timeIntervalSince1970: 0) }))
    }

    private func context(_ pwd: String) -> ShellContext {
        ShellContext(pwd: pwd, exit: 0, durationMilliseconds: 0, awsProfile: nil, kubeconfig: nil, runtimePaths: [:])
    }

    private func seq(_ message: SmaltiMessage?) -> Int? {
        if case .prompt(let seq, _) = message { seq } else { nil }
    }

    private func waitForWaiter(_ gate: Gate) async {
        while !(await gate.hasWaiter) { await Task.yield() }
    }

    @Test func styleMessageCarriesOnlyTheSymbol() {
        guard case .promptStyle(let prompt, _) = make(FakePromptFacts()).styleMessage() else {
            Issue.record("no style message")
            return
        }
        #expect(prompt.values == ["1": "›"])
    }

    @Test func lateFactsDoNotOverrideNewerContext() async {
        let gate = Gate()
        let render = make(gate)
        let slow = Task { await render.handle(context("/slow"), seq: 5, pane: pane) }
        await waitForWaiter(gate)
        _ = await render.handle(context("/fast"), seq: 6, pane: pane)

        await gate.open()
        let late = await slow.value

        #expect(late == nil)
        agents.waiting = WaitingAgents(waiting: ["claude"])
        #expect(render.agentsChanged(in: workspace).map { seq($0.message) } == [6])
    }

    @Test func lateFactsAfterExecAreDropped() async {
        let gate = Gate()
        let render = make(gate)
        let slow = Task { await render.handle(context("/slow"), seq: 5, pane: pane) }
        await waitForWaiter(gate)
        render.commandStarted(pane: pane)

        await gate.open()
        _ = await slow.value

        #expect(render.agentsChanged(in: workspace).isEmpty)
    }

    @Test func lateFactsAfterForgetAreDropped() async {
        let gate = Gate()
        let render = make(gate)
        let slow = Task { await render.handle(context("/slow"), seq: 5, pane: pane) }
        await waitForWaiter(gate)
        render.forget(pane: pane)

        await gate.open()

        #expect(await slow.value == nil)
        #expect(render.agentsChanged(in: workspace).isEmpty)
    }
}

/// Block 2 review (M4): the full prompt's clock uses the injected time zone, like the shell's `%D{%H:%M}`.
@MainActor
@Suite("RenderPrompt · time zone")
struct RenderPromptTimeZoneTests {
    @Test func timeUsesEnvironmentTimeZone() async throws {
        var config = PromptConfig.standard
        config.modules = [.time]
        let bogota = try #require(TimeZone(identifier: "America/Bogota"))
        let render = RenderPrompt(
            facts: FakePromptFacts(),
            environment: PromptEnvironment(
                settings: { (config, ThemeCatalog.apply(.obsidian)) }, agents: { _ in WaitingAgents() },
                workspace: { _ in nil }, home: "/Users/simon", now: { Date(timeIntervalSince1970: 0) },
                timeZone: bogota))
        let context = ShellContext(
            pwd: "/tmp", exit: 0, durationMilliseconds: 0, awsProfile: nil, kubeconfig: nil, runtimePaths: [:])

        guard case .prompt(_, let prompt) = await render.handle(context, seq: 1, pane: PaneID()) else {
            Issue.record("no prompt")
            return
        }
        #expect(prompt.values.values.contains("19:00"))
    }
}

/// Spec F5, "Solo símbolo · contexto en la cabecera": the pane header shows the prompt's context.
@MainActor
@Suite("RenderPrompt header")
struct RenderPromptHeaderTests {
    private let pane = PaneID()

    private final class Settings {
        var config = PromptConfig.standard
    }

    private func make(style: PromptStyleID, settings: Settings = Settings()) -> RenderPrompt {
        settings.config.style = style
        let facts = FakePromptFacts(
            answers: ["/Users/simon/dev/solen": PromptFactsResult(repoRoot: "/Users/simon/dev/solen", branch: "main")])
        let environment = PromptEnvironment(
            settings: { (settings.config, ThemeCatalog.apply(.obsidian)) }, agents: { _ in WaitingAgents() },
            workspace: { _ in nil }, home: "/Users/simon", now: { Date(timeIntervalSince1970: 0) })
        return RenderPrompt(facts: facts, environment: environment)
    }

    private let shell = ShellContext(
        pwd: "/Users/simon/dev/solen", exit: 0, durationMilliseconds: 0, awsProfile: nil, kubeconfig: nil,
        runtimePaths: [:])

    @Test func symbolOnlyPutsTheContextInTheHeader() async {
        let render = make(style: .symbolOnly)
        _ = await render.handle(shell, seq: 1, pane: pane)

        #expect(render.headerText(for: pane) == "solen · main")
    }

    @Test func otherStylesLeaveTheHeaderAlone() async {
        let render = make(style: .clean)
        _ = await render.handle(shell, seq: 1, pane: pane)

        #expect(render.headerText(for: pane) == nil)
    }

    /// Block 5 review (M1): with the user's own prompt the header shows the directory again.
    @Test func shellPromptLeavesTheHeaderAlone() async {
        let settings = Settings()
        let render = make(style: .symbolOnly, settings: settings)
        _ = await render.handle(shell, seq: 1, pane: pane)

        settings.config.source = .shell

        #expect(render.headerText(for: pane) == nil)
    }

    @Test func noContextYetMeansNoHeaderText() {
        #expect(make(style: .symbolOnly).headerText(for: pane) == nil)
    }

    @Test func runningCommandKeepsTheLastContext() async {
        let render = make(style: .symbolOnly)
        _ = await render.handle(shell, seq: 1, pane: pane)

        render.commandStarted(pane: pane)

        #expect(render.headerText(for: pane) == "solen · main")
    }
}

/// Final review (I2, I3): a new style reaches every shell once, even one busy when it went out, and the quiet shells
/// get their full prompt again instead of being left with the immediate one.
@MainActor
@Suite("RenderPrompt · style delivery")
struct RenderPromptStyleDeliveryTests {
    private let pane = PaneID()

    private final class Settings {
        var appearance = AppearanceSettings.obsidian
    }

    private func make(_ settings: Settings) -> RenderPrompt {
        RenderPrompt(
            facts: FakePromptFacts(),
            environment: PromptEnvironment(
                settings: { (PromptConfig.standard, ThemeCatalog.apply(settings.appearance)) },
                agents: { _ in WaitingAgents() }, workspace: { _ in nil }, home: "/Users/simon",
                now: { Date(timeIntervalSince1970: 0) }))
    }

    private let shell = ShellContext(
        pwd: "/tmp", exit: 0, durationMilliseconds: 0, awsProfile: nil, kubeconfig: nil, runtimePaths: [:])

    @Test func styleNeverDeliveredIsPending() {
        let render = make(Settings())

        #expect(render.pendingStyle(for: pane) == render.styleMessage())
    }

    @Test func deliveredStyleIsNotPending() {
        let render = make(Settings())

        render.styleDelivered(render.styleMessage(), to: pane)

        #expect(render.pendingStyle(for: pane) == nil)
    }

    @Test func newThemeMakesTheStylePendingAgain() {
        let settings = Settings()
        let render = make(settings)
        render.styleDelivered(render.styleMessage(), to: pane)

        settings.appearance.theme = .niebla

        #expect(render.pendingStyle(for: pane) == render.styleMessage())
    }

    @Test func quietShellsGetTheirPromptAgain() async {
        let render = make(Settings())
        _ = await render.handle(shell, seq: 5, pane: pane)

        let prompts = render.quietPrompts()

        #expect(prompts.map(\.pane) == [pane])
        if case .prompt(let seq, _) = prompts.first?.message { #expect(seq == 5) } else { Issue.record("no prompt") }
    }

    @Test func busyShellsGetNoPrompt() async {
        let render = make(Settings())
        _ = await render.handle(shell, seq: 5, pane: pane)

        render.commandStarted(pane: pane)

        #expect(render.quietPrompts().isEmpty)
    }
}

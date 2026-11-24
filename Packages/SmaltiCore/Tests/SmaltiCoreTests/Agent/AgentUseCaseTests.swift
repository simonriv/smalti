import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Agent use cases")
struct AgentUseCaseTests {
    private let engine = FakeTerminalEngine()
    private let notifier = RecordingNotifier()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let web = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/Users/s/dev/web"))
    private let api = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/Users/s/dev/api"))

    /// `rizaria` (with `web`) is active; `solen` (with `api`) is hidden.
    private func makeSet() -> WorkspaceSet {
        let solen = Workspace.empty(
            name: "solen", rootDirectory: SessionFixtures.directory("/tmp"), layout: DwindleLayout()
        )
        .adding(api)
        let rizaria = Workspace.empty(
            name: "rizaria", rootDirectory: SessionFixtures.directory("/tmp"), layout: DwindleLayout()
        )
        .adding(web)
        return WorkspaceSet(first: solen).adding(rizaria)
    }

    private func event(_ hook: AgentHook, pane: PaneID, at seconds: TimeInterval = 0) -> AgentEvent {
        AgentEvent(
            pane: pane, hook: hook, at: t0.addingTimeInterval(seconds), sessionID: "s-\(pane)", prompt: "x",
            toolSummary: "pnpm db:migrate", message: "Claude needs you")
    }

    private func handle(_ event: AgentEvent, in set: inout WorkspaceSet, appActive: Bool = true)
        -> HandleAgentEventOutcome
    {
        HandleAgentEvent(notifier: notifier).execute(event, in: &set, isAppActive: appActive)
    }

    @Test func eventForMissingPaneIsIgnored() {
        var set = makeSet()
        let before = set

        #expect(handle(event(.stop, pane: PaneID()), in: &set) == .ignoredMissingPane)
        #expect(set == before)
        #expect(notifier.delivered.isEmpty)
    }

    @Test func eventUpdatesItsPaneEvenInAHiddenWorkspace() {
        var set = makeSet()

        #expect(handle(event(.userPromptSubmit, pane: api.id), in: &set) == .applied)
        #expect(set.workspaces[0].panes[0].agent?.state == .working)
    }

    @Test func permissionNotifiesEvenWhenVisible() {
        var set = makeSet()

        _ = handle(event(.permissionRequest, pane: web.id), in: &set)

        #expect(
            notifier.delivered
                == [AttentionNotice(pane: web.id, title: "rizaria/web", body: "pide permiso para `pnpm db:migrate`")])
    }

    @Test func stopIsQuietWhenThePaneIsVisible() {
        var set = makeSet()

        _ = handle(event(.stop, pane: web.id), in: &set)

        #expect(notifier.delivered.isEmpty)
    }

    @Test func stopNotifiesWhenTheAppIsInactive() {
        var set = makeSet()

        _ = handle(event(.stop, pane: web.id), in: &set, appActive: false)

        #expect(notifier.delivered.map(\.body) == ["terminó y te espera"])
    }

    @Test func stopNotifiesWhenTheWorkspaceIsHidden() {
        var set = makeSet()

        _ = handle(event(.stop, pane: api.id), in: &set)

        #expect(notifier.delivered.map(\.title) == ["solen/api"])
    }

    @Test func sessionStartDoesNotNotify() {
        var set = makeSet()

        _ = handle(event(.sessionStart, pane: api.id), in: &set, appActive: false)

        #expect(notifier.delivered.isEmpty)
    }

    @Test func jumpFocusesLongestWaitingAcrossWorkspaces() {
        var set = makeSet()
        _ = handle(event(.stop, pane: web.id, at: 20), in: &set)
        _ = handle(event(.permissionRequest, pane: api.id, at: 10), in: &set)

        let outcome = JumpToWaitingAgent(engine: engine).execute(in: &set)

        #expect(outcome == .focused(api.id))
        #expect(set.active.name == "solen")
        #expect(set.active.focusedPane == api.id)
        #expect(engine.hiddenPanes == [web.id])
    }

    @Test func jumpWithNobodyWaitingDoesNothing() {
        var set = makeSet()
        let before = set

        #expect(JumpToWaitingAgent(engine: engine).execute(in: &set) == .nobodyWaiting)
        #expect(set == before)
    }

    @Test func activatingAPaneInAHiddenWorkspaceShowsAndFocusesIt() {
        var set = makeSet()

        #expect(ActivatePane(engine: engine).execute(api.id, in: &set))
        #expect(set.active.name == "solen")
        #expect(set.active.focusedPane == api.id)
    }

    @Test func activatingMissingPaneOnlyActivatesApp() {
        var set = makeSet()
        let before = set

        #expect(!ActivatePane(engine: engine).execute(PaneID(), in: &set))
        #expect(set == before)
    }

    @Test func installReportsSuccess() async {
        let integration = FakeHarnessIntegration()

        #expect(
            await InstallClaudeIntegration(integration: integration).execute()
                == "Integración con Claude Code instalada")
        #expect(await integration.installState == .installed)
    }

    @Test func installReportsMissingClaude() async {
        let integration = FakeHarnessIntegration()
        integration.failure = .harnessMissing(binary: "claude")

        #expect(
            await InstallClaudeIntegration(integration: integration).execute()
                == "No se encontró `claude` en el PATH del shell de inicio")
    }

    @Test func installReportsCommandOutputOnFailure() async {
        let integration = FakeHarnessIntegration()
        integration.failure = .commandFailed(command: "claude plugin install smalti@smalti", output: "boom\nmore")

        #expect(
            await InstallClaudeIntegration(integration: integration).execute()
                == "Falló `claude plugin install smalti@smalti`: more")
    }

    @Test func uninstallReportsSuccess() async {
        let integration = FakeHarnessIntegration()
        _ = await InstallClaudeIntegration(integration: integration).execute()

        #expect(
            await UninstallClaudeIntegration(integration: integration).execute()
                == "Integración con Claude Code desinstalada")
        #expect(await integration.installState == .notInstalled)
    }
}

@MainActor
@Suite("Agent contracts (in memory)")
struct AgentContractTests {
    @Test func fakeTelemetrySatisfiesContract() async {
        await TelemetrySourceContract.verify {
            let source = FakeTelemetrySource()
            return (source, { source.send($0) })
        }
    }

    @Test func recordingNotifierSatisfiesContract() {
        NotifierContract.verify {
            let notifier = RecordingNotifier()
            return (notifier, { notifier.delivered })
        }
    }

    @Test func fakeIntegrationSatisfiesContract() async {
        await HarnessIntegrationContract.verify(FakeHarnessIntegration())
    }

    @Test func missingHarnessIsUnknownState() async {
        let integration = FakeHarnessIntegration()
        integration.isMissing = true

        #expect(await integration.installState == .unknown)
    }

    @Test func fakeHonoursIntegrationContract() async {
        await HarnessIntegrationContract.verify(FakeHarnessIntegration())
    }
}

import Foundation

public struct RestoreResult: Sendable {
    /// The rebuilt workspaces, or `nil` when nothing could be restored (the app starts as usual).
    public let set: WorkspaceSet?
    /// One line per pane that could not come back as saved.
    public let failures: [String]
}

/// Rebuilds the workspaces of a `RestorePlan`: each pane keeps its identity, gets its scrollback, history and
/// initial command, and opens even if the window is now too small for the saved layout. A pane whose directory
/// is gone opens in the workspace root, else in the home directory.
@MainActor
public struct RestoreSession {
    public struct Dependencies {
        let engine: any TerminalEngine
        let transcripts: any PaneTranscripts
        let harnesses: HarnessRegistry
        let environment: PaneEnvironment
        let clock: @Sendable () -> Date

        public init(
            engine: any TerminalEngine, transcripts: any PaneTranscripts, harnesses: HarnessRegistry,
            environment: PaneEnvironment, clock: @escaping @Sendable () -> Date
        ) {
            self.engine = engine
            self.transcripts = transcripts
            self.harnesses = harnesses
            self.environment = environment
            self.clock = clock
        }
    }

    private let deps: Dependencies

    public init(_ deps: Dependencies) {
        self.deps = deps
    }

    public func execute(_ plan: RestorePlan, savedAt: Date, home: WorkingDirectory) -> RestoreResult {
        var failures: [String] = []
        let workspaces = plan.workspaces.compactMap { planned in
            let built = restore(planned, savedAt: savedAt, home: home)
            failures += built.failures
            return built.workspace
        }
        guard let first = workspaces.first else { return RestoreResult(set: nil, failures: failures) }
        let active = workspaces[min(plan.activeIndex, workspaces.count - 1)]
        let set = workspaces.dropFirst().reduce(WorkspaceSet(first: first)) { $0.adding($1) }.activating(active.id)
        for workspace in workspaces where workspace.id != active.id {
            workspace.panes.forEach { deps.engine.hide($0.id) }
        }
        return RestoreResult(set: set, failures: failures)
    }

    func hide(_ pane: PaneID) { deps.engine.hide(pane) }

    /// One workspace, or `nil` when none of its panes could open.
    func restore(_ planned: PlannedWorkspace, savedAt: Date, home: WorkingDirectory)
        -> (workspace: Workspace?, failures: [String])
    {
        let root = (try? WorkingDirectory(path: planned.rootDirectory)) ?? home
        let layout = LayoutCatalog.standard.strategyOrDefault(for: planned.layout)
        var workspace = Workspace.empty(name: planned.name, rootDirectory: root, layout: layout)
        var failures: [String] = []
        let fallbacks = [root, home]
        for pane in planned.panes {
            let opened = open(pane, savedAt: savedAt, fallbacks: fallbacks)
            failures += opened.failures
            if let restored = opened.pane { workspace = workspace.adding(restored) }
        }
        guard !workspace.panes.isEmpty else { return (nil, failures) }
        return (arrange(workspace, as: planned), failures)
    }

    private func arrange(_ workspace: Workspace, as planned: PlannedWorkspace) -> Workspace {
        let ids = workspace.panes.map(\.id)
        var arranged = workspace
        if let tree = planned.tree?.layoutTree(ids: ids) { arranged = arranged.withSavedTree(tree) }
        if let index = planned.focusedIndex, ids.indices.contains(index) { arranged = arranged.focusing(ids[index]) }
        return arranged
    }

    private func open(_ planned: PlannedPane, savedAt: Date, fallbacks: [WorkingDirectory])
        -> (pane: Pane?, failures: [String])
    {
        let id = PaneID(rawValue: planned.id)
        let start = startup(for: planned)
        var failures = start.failures
        let scrollback = planned.restoresScrollback ? deps.transcripts.scrollback(of: id) : nil
        let restoration =
            scrollback == nil && !planned.restoresHistory
            ? nil : PaneRestoration(scrollback: scrollback, restoresHistory: planned.restoresHistory, savedAt: savedAt)
        let saved = try? WorkingDirectory(path: planned.workingDirectory)
        for directory in ([saved].compactMap { $0 } + fallbacks) {
            let spec = TerminalSessionSpec(
                workingDirectory: directory, command: .loginShell, environment: deps.environment.variables(for: id),
                restoration: restoration, initialInput: start.input)
            do {
                try deps.engine.open(spec, as: id)
                return (Pane(id: id, workingDirectory: directory).attaching(start.agent), failures)
            } catch {
                continue
            }
        }
        failures.append("\(planned.workingDirectory): no se pudo abrir el panel")
        return (nil, failures)
    }

    private func startup(for planned: PlannedPane) -> (input: String?, agent: AgentSession?, failures: [String]) {
        switch planned.launch {
        case .shell:
            return (nil, nil, [])
        case .relaunch(let command):
            return (command.displayText + "\n", nil, [])
        case .resume(let agent):
            guard let adapter = deps.harnesses.adapter(for: agent.harness) else {
                return (
                    nil, nil, ["\(agent.harness.rawValue): harness sin adaptador, no se reanuda \(agent.sessionID)"]
                )
            }
            let session = AgentSession(
                harness: agent.harness, sessionID: agent.sessionID, title: agent.title,
                state: .waiting(since: deps.clock(), reason: .turnFinished), startedAt: deps.clock())
            return (adapter.resumeCommand(for: agent) + "\n", session, [])
        }
    }
}

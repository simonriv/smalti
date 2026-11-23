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
        /// The configured shell (`[shell] command`, or the test override), as for any new pane.
        let shell: TerminalCommand
        let clock: @Sendable () -> Date

        public init(
            engine: any TerminalEngine, transcripts: any PaneTranscripts, harnesses: HarnessRegistry,
            environment: PaneEnvironment, shell: TerminalCommand, clock: @escaping @Sendable () -> Date
        ) {
            self.engine = engine
            self.transcripts = transcripts
            self.harnesses = harnesses
            self.environment = environment
            self.shell = shell
            self.clock = clock
        }
    }

    private let deps: Dependencies

    public init(_ deps: Dependencies) {
        self.deps = deps
    }

    public func execute(_ plan: RestorePlan, savedAt: Date, home: WorkingDirectory) -> RestoreResult {
        var failures: [String] = []
        var built: [(planIndex: Int, workspace: Workspace)] = []
        for (index, planned) in plan.workspaces.enumerated() {
            let restored = restore(planned, savedAt: savedAt, home: home)
            failures += restored.failures
            if let workspace = restored.workspace { built.append((index, workspace)) }
        }
        let workspaces = built.map(\.workspace)
        guard let first = workspaces.first else { return RestoreResult(set: nil, failures: failures) }
        let active = built.first { $0.planIndex == plan.activeIndex }?.workspace ?? first
        let set = workspaces.dropFirst().reduce(WorkspaceSet(first: first)) { $0.adding($1) }.activating(active.id)
        for workspace in workspaces where workspace.id != active.id {
            workspace.panes.forEach { deps.engine.hide($0.id) }
        }
        return RestoreResult(set: set, failures: failures)
    }

    func hide(_ pane: PaneID) { deps.engine.hide(pane) }

    /// One workspace, or `nil` when none of its panes could open. If the saved root could not be opened either,
    /// the home directory becomes the workspace root.
    func restore(_ planned: PlannedWorkspace, savedAt: Date, home: WorkingDirectory)
        -> (workspace: Workspace?, failures: [String])
    {
        let root = (try? WorkingDirectory(path: planned.rootDirectory)) ?? home
        var opened: [(planIndex: Int, pane: Pane)] = []
        var failures: [String] = []
        var unreachable: Set<WorkingDirectory> = []
        for (index, pane) in planned.panes.enumerated() {
            let result = open(pane, savedAt: savedAt, fallbacks: [root, home])
            failures += result.failures
            unreachable.formUnion(result.unreachable)
            if let restored = result.pane { opened.append((index, restored)) }
        }
        guard !opened.isEmpty else { return (nil, failures) }
        let workspaceRoot = unreachable.contains(root) ? home : root
        let layout = LayoutCatalog.standard.strategyOrDefault(for: planned.layout)
        let empty = Workspace.empty(name: planned.name, rootDirectory: workspaceRoot, layout: layout)
        let workspace = opened.reduce(empty) { $0.adding($1.pane) }
        return (arrange(workspace, as: planned, opened: opened), failures)
    }

    /// Saved ratios only when every planned pane opened; focus on the planned pane if it is there.
    private func arrange(
        _ workspace: Workspace, as planned: PlannedWorkspace, opened: [(planIndex: Int, pane: Pane)]
    ) -> Workspace {
        var arranged = workspace
        if opened.count == planned.panes.count, let tree = planned.tree?.layoutTree(ids: opened.map(\.pane.id)) {
            arranged = arranged.withSavedTree(tree)
        }
        if let focused = opened.first(where: { $0.planIndex == planned.focusedIndex }) {
            arranged = arranged.focusing(focused.pane.id)
        }
        return arranged
    }

    private func open(_ planned: PlannedPane, savedAt: Date, fallbacks: [WorkingDirectory])
        -> (pane: Pane?, failures: [String], unreachable: Set<WorkingDirectory>)
    {
        let id = PaneID(rawValue: planned.id)
        let start = startup(for: planned)
        let scrollback = planned.restoresScrollback ? deps.transcripts.scrollback(of: id) : nil
        let restoration =
            scrollback == nil && !planned.restoresHistory
            ? nil : PaneRestoration(scrollback: scrollback, restoresHistory: planned.restoresHistory, savedAt: savedAt)
        let saved = try? WorkingDirectory(path: planned.workingDirectory)
        var unreachable: Set<WorkingDirectory> = []
        var lastError = "invalid directory"
        for directory in ([saved].compactMap { $0 } + fallbacks) where !unreachable.contains(directory) {
            let spec = TerminalSessionSpec(
                workingDirectory: directory, command: deps.shell, environment: deps.environment.variables(for: id),
                restoration: restoration, initialInput: start.input)
            do {
                try deps.engine.open(spec, as: id)
                return (Pane(id: id, workingDirectory: directory).attaching(start.agent), start.failures, unreachable)
            } catch {
                unreachable.insert(directory)
                lastError = String(describing: error)
            }
        }
        let failure = "\(planned.workingDirectory): no se pudo abrir el panel (\(lastError))"
        return (nil, start.failures + [failure], unreachable)
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

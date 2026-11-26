public enum HandleAgentEventOutcome: Equatable, Sendable {
    case applied
    /// The pane is gone (a late hook): nothing changes.
    case ignoredMissingPane
}

/// Applies an agent's event to its pane and, when the policy says so, notifies the user. A pane is "visible" when
/// the app is active and its workspace is the one shown.
@MainActor
public struct HandleAgentEvent {
    private let notifier: any Notifier
    private let texts: StatusTexts

    public init(notifier: any Notifier, texts: StatusTexts) {
        self.notifier = notifier
        self.texts = texts
    }

    public func execute(_ event: AgentEvent, in set: inout WorkspaceSet, isAppActive: Bool) -> HandleAgentEventOutcome {
        guard let owner = set.workspace(containing: event.pane),
            let workspace = set.workspaces.first(where: { $0.id == owner })
        else { return .ignoredMissingPane }
        let (updated, attention) = workspace.applying(event)
        set = set.updating(owner) { _ in updated }
        let isVisible = isAppActive && owner == set.activeID
        if let attention, AttentionPolicy.shouldNotify(attention, paneIsVisible: isVisible),
            let pane = updated.panes.first(where: { $0.id == event.pane })
        {
            notifier.notify(
                .make(attention, at: (updated.name, pane.workingDirectory, pane.id), texts: texts))
        }
        return .applied
    }
}

public enum JumpOutcome: Equatable, Sendable {
    case focused(PaneID)
    case nobodyWaiting
}

/// ⌘J: shows and focuses the agent that has been waiting longest, switching workspace if needed.
@MainActor
public struct JumpToWaitingAgent {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(in set: inout WorkspaceSet) -> JumpOutcome {
        guard let pane = AttentionQueue.panes(in: set).first, ActivatePane(engine: engine).execute(pane, in: &set)
        else {
            return .nobodyWaiting
        }
        return .focused(pane)
    }
}

/// A click on a notification: shows the pane, switching workspace if needed. False when the pane is gone (the app
/// only comes forward).
@MainActor
public struct ActivatePane {
    private let engine: any TerminalEngine

    public init(engine: any TerminalEngine) {
        self.engine = engine
    }

    public func execute(_ pane: PaneID, in set: inout WorkspaceSet) -> Bool {
        guard let owner = set.workspace(containing: pane) else { return false }
        if owner != set.activeID { SwitchWorkspace(engine: engine).execute(.id(owner), in: &set) }
        set = set.updating(owner) { $0.focusing(pane) }
        return true
    }
}

/// "Instalar integración con Claude Code": the status bar line it ends with.
/// What installing or uninstalling an integration left, with the line the status bar shows.
public enum IntegrationOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)

    public var text: String {
        switch self {
        case .done(let text), .failed(let text): text
        }
    }
}

@MainActor
public struct InstallClaudeIntegration {
    private let integration: any HarnessIntegration
    private let id: IntegrationID
    private let texts: IntegrationTexts

    public init(integration: any HarnessIntegration, id: IntegrationID = .claudePlugin, texts: IntegrationTexts) {
        self.integration = integration
        self.id = id
        self.texts = texts
    }

    public func execute() async -> String {
        await run().text
    }

    /// The same as `execute`, saying whether it worked (the welcome card paints a failure in red).
    public func run() async -> IntegrationOutcome {
        do {
            try await integration.install()
            return .done(texts.installed[id] ?? "")
        } catch {
            return .failed(IntegrationErrorText.describe(error, texts: texts))
        }
    }
}

@MainActor
public struct UninstallClaudeIntegration {
    private let integration: any HarnessIntegration
    private let id: IntegrationID
    private let texts: IntegrationTexts

    public init(integration: any HarnessIntegration, id: IntegrationID = .claudePlugin, texts: IntegrationTexts) {
        self.integration = integration
        self.id = id
        self.texts = texts
    }

    public func execute() async -> String {
        await run().text
    }

    public func run() async -> IntegrationOutcome {
        do {
            try await integration.uninstall()
            return .done(texts.uninstalled[id] ?? "")
        } catch {
            return .failed(IntegrationErrorText.describe(error, texts: texts))
        }
    }
}

enum IntegrationErrorText {
    static func describe(_ error: IntegrationError, texts: IntegrationTexts) -> String {
        switch error {
        case .harnessMissing(let binary): texts.harnessMissing(["binary": binary])
        // The last line: a login shell's own output (rc files) comes first, the command's error last.
        case .commandFailed(let command, let output):
            texts.commandFailed([
                "command": command, "output": output.split(separator: "\n").last.map(String.init) ?? "",
            ])
        }
    }
}

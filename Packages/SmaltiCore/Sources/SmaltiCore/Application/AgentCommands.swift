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

    public init(notifier: any Notifier) {
        self.notifier = notifier
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
                .make(attention, workspace: updated.name, directory: pane.workingDirectory, pane: pane.id))
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
        guard let pane = AttentionQueue.panes(in: set).first, let owner = set.workspace(containing: pane) else {
            return .nobodyWaiting
        }
        if owner != set.activeID { SwitchWorkspace(engine: engine).execute(.id(owner), in: &set) }
        set = set.updating(owner) { $0.focusing(pane) }
        return .focused(pane)
    }
}

/// "Instalar integración con Claude Code": the status bar line it ends with.
@MainActor
public struct InstallClaudeIntegration {
    private let integration: any HarnessIntegration

    public init(integration: any HarnessIntegration) {
        self.integration = integration
    }

    public func execute() async -> String {
        do {
            try await integration.install()
            return "Integración con Claude Code instalada"
        } catch {
            return IntegrationErrorText.describe(error)
        }
    }
}

@MainActor
public struct UninstallClaudeIntegration {
    private let integration: any HarnessIntegration

    public init(integration: any HarnessIntegration) {
        self.integration = integration
    }

    public func execute() async -> String {
        do {
            try await integration.uninstall()
            return "Integración con Claude Code desinstalada"
        } catch {
            return IntegrationErrorText.describe(error)
        }
    }
}

enum IntegrationErrorText {
    static func describe(_ error: IntegrationError) -> String {
        switch error {
        case .harnessMissing(let binary): "No se encontró `\(binary)` en el PATH del shell de inicio"
        // The last line: a login shell's own output (rc files) comes first, the command's error last.
        case .commandFailed(let command, let output):
            "Falló `\(command)`: \(output.split(separator: "\n").last.map(String.init) ?? "")"
        }
    }
}

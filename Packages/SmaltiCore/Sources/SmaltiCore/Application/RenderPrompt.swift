import Foundation

/// What `RenderPrompt` needs from the app: the current prompt and theme, the agents that wait in a pane's workspace,
/// which workspace a pane is in, the home directory and the clock.
public struct PromptEnvironment: Sendable {
    public let settings: @MainActor () -> (PromptConfig, AppliedTheme)
    public let agents: @MainActor (PaneID) -> WaitingAgents
    public let workspace: @MainActor (PaneID) -> WorkspaceID?
    public let home: String
    public let now: @Sendable () -> Date
    /// The shell's zone for the clock module, so the full prompt agrees with the immediate `%D{%H:%M}`.
    public let timeZone: TimeZone

    public init(
        settings: @escaping @MainActor () -> (PromptConfig, AppliedTheme),
        agents: @escaping @MainActor (PaneID) -> WaitingAgents,
        workspace: @escaping @MainActor (PaneID) -> WorkspaceID?, home: String, now: @escaping @Sendable () -> Date,
        timeZone: TimeZone = .current
    ) {
        self.settings = settings
        self.agents = agents
        self.workspace = workspace
        self.home = home
        self.now = now
        self.timeZone = timeZone
    }
}

/// Turns zsh's `context` into the full prompt (spec F5) and re-sends it, without being asked, to the shells waiting
/// at their prompt when an agent of their workspace starts waiting or fails.
@MainActor
public final class RenderPrompt {
    private let facts: any PromptFacts
    private let environment: PromptEnvironment
    /// Shells at their prompt: the last `context`, its `seq` and the facts it got, until the next command starts.
    private var quiet: [PaneID: QuietShell] = [:]
    /// The newest `context` of each shell still waiting for its facts: a slower, older answer is dropped, and `exec`
    /// or `forget` cancel it (block 2 review, I2).
    private var pending: [PaneID: Int] = [:]

    private struct QuietShell {
        let seq: Int
        let context: ShellContext
        let facts: PromptFactsResult
    }

    public init(facts: any PromptFacts, environment: PromptEnvironment) {
        self.facts = facts
        self.environment = environment
    }

    /// `nil` when the user keeps their own prompt (`source = "shell"`).
    public func handle(_ context: ShellContext, seq: Int, pane: PaneID) async -> SmaltiMessage? {
        guard environment.settings().0.source == .smalti else { return nil }
        let query = PromptQuery(
            directory: context.pwd, runtimePaths: context.runtimePaths, kubeconfig: context.kubeconfig)
        pending[pane] = seq
        let found = await facts.facts(for: query)
        guard pending[pane] == seq else { return nil }
        pending[pane] = nil
        quiet[pane] = QuietShell(seq: seq, context: context, facts: found)
        return message(for: pane)
    }

    /// The prompts to re-send after an agent of `workspace` changed state, with each shell's last `seq`.
    public func agentsChanged(in workspace: WorkspaceID) -> [(pane: PaneID, message: SmaltiMessage)] {
        quiet.keys.filter { environment.workspace($0) == workspace }.compactMap { pane in
            message(for: pane).map { (pane, $0) }
        }
    }

    /// `exec`: the shell left its prompt; a late re-send must not reach it.
    public func commandStarted(pane: PaneID) {
        quiet[pane] = nil
        pending[pane] = nil
    }

    /// The pane or its connection is gone.
    public func forget(pane: PaneID) {
        quiet[pane] = nil
        pending[pane] = nil
    }

    /// The immediate prompt and the ghost color for every shell. With `source = "shell"` the immediate prompt is
    /// empty: zsh gives the user's prompt back, and the ghost color still arrives.
    public func styleMessage() -> SmaltiMessage {
        let (config, theme) = environment.settings()
        let ghost = theme.theme.text.ghostText
        guard config.source == .smalti else {
            return .promptStyle(RenderedPrompt(immediate: "", full: "", values: [:], directoryLabel: ""), ghost: ghost)
        }
        let base = PromptContext(directory: environment.home, home: environment.home)
        let rendered = ZshPromptRenderer.render(config, context: base, theme: theme)
        // Only what the immediate prompt references: a full prompt's values would repaint the one on screen with
        // another context's text (block 2 review, I1).
        let symbol = ZshPromptRenderer.symbolKey
        let style = RenderedPrompt(
            immediate: rendered.immediate, full: "", values: rendered.values.filter { $0.key == symbol },
            directoryLabel: "")
        return .promptStyle(style, ghost: ghost)
    }

    private func message(for pane: PaneID) -> SmaltiMessage? {
        let (config, theme) = environment.settings()
        guard config.source == .smalti, let shell = quiet[pane] else { return nil }
        let context = promptContext(shell, pane: pane)
        return .prompt(seq: shell.seq, ZshPromptRenderer.render(config, context: context, theme: theme))
    }

    private func promptContext(_ shell: QuietShell, pane: PaneID) -> PromptContext {
        var context = PromptContext(directory: shell.context.pwd, home: environment.home)
        context.repoRoot = shell.facts.repoRoot
        context.branch = shell.facts.branch
        context.changes = shell.facts.changes
        context.runtime = shell.facts.runtime
        context.kubeContext = shell.facts.kubeContext
        context.awsProfile = shell.context.awsProfile
        context.lastExit = shell.context.exit
        context.duration = .milliseconds(shell.context.durationMilliseconds)
        context.now = environment.now()
        context.timeZone = environment.timeZone
        context.agents = environment.agents(pane)
        return context
    }
}

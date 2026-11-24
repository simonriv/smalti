/// Port to what only the machine knows about a directory for the prompt (spec F5): the repository, its branch and
/// changes, the runtime version and the kube context. Never fails: a fact it cannot get in time is `nil`, and the
/// module that needs it does not appear.
public protocol PromptFacts: Sendable {
    func facts(for query: PromptQuery) async -> PromptFactsResult
}

public struct PromptQuery: Equatable, Sendable {
    public let directory: String
    public let runtimePaths: [RuntimeKind: String]
    /// `$KUBECONFIG` as zsh sees it; `nil` means the default `~/.kube/config`.
    public let kubeconfig: String?

    public init(directory: String, runtimePaths: [RuntimeKind: String], kubeconfig: String?) {
        self.directory = directory
        self.runtimePaths = runtimePaths
        self.kubeconfig = kubeconfig
    }
}

public struct PromptFactsResult: Equatable, Sendable {
    public let repoRoot: String?
    public let branch: String?
    public let changes: GitChanges?
    public let runtime: RuntimeVersion?
    public let kubeContext: String?

    public init(
        repoRoot: String? = nil, branch: String? = nil, changes: GitChanges? = nil, runtime: RuntimeVersion? = nil,
        kubeContext: String? = nil
    ) {
        self.repoRoot = repoRoot
        self.branch = branch
        self.changes = changes
        self.runtime = runtime
        self.kubeContext = kubeContext
    }

    public static let none = PromptFactsResult()
}

/// What Apariencia and the prompt studio edit, and what `theme.toml` holds (spec F5).
public struct AppearanceDocument: Equatable, Sendable {
    public var appearance: AppearanceSettings
    public var buttons: WindowButtons
    public var prompt: PromptConfig

    public init(config: SmaltiConfig) {
        appearance = config.appearance
        buttons = config.window.buttons
        prompt = config.prompt
    }

    /// `config` with this document's values; everything else (`confirm_close`, keys, shell…) stays.
    public func applied(to config: SmaltiConfig) -> SmaltiConfig {
        var updated = config
        updated.appearance = appearance
        updated.window.buttons = buttons
        updated.prompt = prompt
        return updated
    }
}

/// Port to where the UI writes (`theme.toml`). It writes the whole document; a failure leaves the file as it was.
public protocol AppearanceStore: AnyObject {
    @MainActor func save(_ document: AppearanceDocument) throws(ConfigError)
}

/// Runs only the last action scheduled within its delay (the app waits `ChangeAppearance.saveDelay`).
public protocol Debouncer: AnyObject {
    @MainActor func schedule(_ action: @escaping @MainActor () -> Void)
    /// Drops the pending action, if any.
    @MainActor func cancel()
}

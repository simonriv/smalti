/// Port to what only the machine knows about a directory for the prompt (spec F5): the repository, its branch and
/// changes, the runtime version and the kube context. Never fails: a fact it cannot get in time is `nil`, and the
/// module that needs it does not appear.
public protocol PromptFacts: Sendable {
    func facts(for query: PromptQuery) async -> PromptFactsResult
}

public struct PromptQuery: Equatable, Sendable {
    public let directory: String
    public let runtimePaths: [RuntimeKind: String]
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

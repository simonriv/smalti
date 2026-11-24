/// One prompt module (spec F5): a type per `PromptModuleID`. A module that does not apply returns `nil` and the
/// prompt leaves it out.
public protocol PromptModule: Sendable {
    var id: PromptModuleID { get }
    /// zsh paints it at once in the immediate prompt; the others arrive with Smalti's answer.
    var isLocal: Bool { get }
    func segment(in context: PromptContext) -> PromptSegment?
}

/// The modules by identifier, and the segments of a configuration.
public enum PromptModules {
    private static let all: [PromptModuleID: any PromptModule] = Dictionary(
        uniqueKeysWithValues: modules.map { ($0.id, $0) })

    private static let modules: [any PromptModule] = [
        DirectoryModule(), GitBranchModule(), GitStatusModule(), RuntimeModule(), DurationModule(), AgentsModule(),
        TimeModule(), CloudModule(),
    ]

    public static func module(for id: PromptModuleID) -> any PromptModule {
        // Every identifier has its module (`everyIdHasItsModule`); the fallback is never reached.
        all[id] ?? DirectoryModule()
    }

    /// The active modules' segments, in the configuration's order, without the ones that do not apply.
    public static func segments(for config: PromptConfig, in context: PromptContext) -> [PromptSegment] {
        config.modules.compactMap { module(for: $0).segment(in: context) }
    }
}

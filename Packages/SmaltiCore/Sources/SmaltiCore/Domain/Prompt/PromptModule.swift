/// One prompt module (spec F5): a type per `PromptModuleID`. A module that does not apply returns `nil` and the
/// prompt leaves it out.
public protocol PromptModule: Sendable {
    var id: PromptModuleID { get }
    /// zsh paints it at once in the immediate prompt; the others arrive with Smalti's answer.
    var isLocal: Bool { get }
    func segment(in context: PromptContext) -> PromptSegment?
    /// Its piece of the immediate prompt; `nil` for modules only Smalti can answer.
    var immediate: ImmediatePart? { get }
    /// What it becomes in `starship.toml`; none for what exists only in Smalti.
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable]
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

/// The `psvar` slots the script fills and the prompt shows with `%Nv` (spec F5, "Escapado"): zsh inserts a slot's
/// text as it is, with no expansion of `%`, `$` or backquotes and no option needed. Values of a full prompt start at
/// `firstValue`.
public enum PromptSlot: Int, Sendable {
    case symbol = 1
    case directory = 2
    case duration = 3

    public static let firstValue = 4
}

/// How a local module appears in the immediate prompt, with zsh's own expansions (spec F5): the script fills the
/// variables at every `precmd`, so the prompt shows them before Smalti answers.
public enum ImmediatePart: Equatable, Sendable {
    /// Always shown: `%Nv` of its slot.
    case variable(PromptSlot, icon: PromptIcon?, color: SegmentColor)
    /// Shown only when the script set it (the duration from 2 s): `%(NV.…)`.
    case optional(PromptSlot, color: SegmentColor)
    /// zsh's clock, `%D{%H:%M}`.
    case clock(icon: PromptIcon?, color: SegmentColor)
}

extension PromptModule {
    /// `nil` for modules that only Smalti can answer.
    public var immediate: ImmediatePart? { nil }
}

extension DirectoryModule {
    var immediate: ImmediatePart? { .variable(.directory, icon: .folder, color: .accent) }
}

extension DurationModule {
    var immediate: ImmediatePart? { .optional(.duration, color: .secondary) }
}

extension TimeModule {
    var immediate: ImmediatePart? { .clock(icon: .clock, color: .secondary) }
}

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
    /// Returns what was written: `document` with any edit made by hand to the file since it was read (final review,
    /// I1), which the caller adopts so its next save keeps it.
    @discardableResult
    @MainActor func save(_ document: AppearanceDocument) throws(ConfigError) -> AppearanceDocument
}

/// Runs only the last action scheduled within its delay (the app waits `ChangeAppearance.saveDelay`).
public protocol Debouncer: AnyObject {
    @MainActor func schedule(_ action: @escaping @MainActor () -> Void)
    /// Drops the pending action, if any.
    @MainActor func cancel()
}

extension AppearanceDocument {
    /// This document's changes since `base`, applied over `external` (the file as someone edited it by hand): fields
    /// the UI did not touch take the file's value, fields it did keep the UI's (spec F5, "Escritura atómica").
    public func rebased(onto external: AppearanceDocument, from base: AppearanceDocument) -> AppearanceDocument {
        var merged = external
        merged.appearance = appearance.rebased(onto: external.appearance, from: base.appearance)
        merged.buttons = pick(\.buttons, external, base)
        merged.prompt = prompt.rebased(onto: external.prompt, from: base.prompt)
        return merged
    }

    private func pick<Value: Equatable>(
        _ field: KeyPath<AppearanceDocument, Value>, _ external: AppearanceDocument, _ base: AppearanceDocument
    ) -> Value {
        self[keyPath: field] != base[keyPath: field] ? self[keyPath: field] : external[keyPath: field]
    }
}

extension AppearanceSettings {
    fileprivate func rebased(onto external: AppearanceSettings, from base: AppearanceSettings) -> AppearanceSettings {
        var merged = external
        merged.theme = theme != base.theme ? theme : external.theme
        merged.accent = accent != base.accent ? accent : external.accent
        merged.glassOpacity = glassOpacity != base.glassOpacity ? glassOpacity : external.glassOpacity
        merged.blur = blur != base.blur ? blur : external.blur
        merged.fontFamily = fontFamily != base.fontFamily ? fontFamily : external.fontFamily
        merged.fontSize = fontSize != base.fontSize ? fontSize : external.fontSize
        merged.gap = gap != base.gap ? gap : external.gap
        merged.radius = radius != base.radius ? radius : external.radius
        merged.protectLegibility =
            protectLegibility != base.protectLegibility ? protectLegibility : external.protectLegibility
        merged.ansiOverrides = ansiOverrides != base.ansiOverrides ? ansiOverrides : external.ansiOverrides
        return merged
    }
}

extension PromptConfig {
    fileprivate func rebased(onto external: PromptConfig, from base: PromptConfig) -> PromptConfig {
        var merged = external
        merged.source = source != base.source ? source : external.source
        merged.style = style != base.style ? style : external.style
        merged.layout = layout != base.layout ? layout : external.layout
        merged.modules = modules != base.modules ? modules : external.modules
        merged.icons = icons != base.icons ? icons : external.icons
        merged.symbol = symbol != base.symbol ? symbol : external.symbol
        return merged
    }
}

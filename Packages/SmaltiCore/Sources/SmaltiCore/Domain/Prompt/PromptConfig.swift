/// `[prompt]` in `theme.toml` (spec F5, "Estudio de prompt"). The raw values are the file's words.
public struct PromptConfig: Equatable, Sendable {
    public var source: PromptSource
    public var style: PromptStyleID
    public var layout: PromptLayout
    /// The active modules, in order; absent ones are off.
    public var modules: [PromptModuleID]
    public var icons: PromptIcons
    public var symbol: PromptSymbol

    public init(
        source: PromptSource, style: PromptStyleID, layout: PromptLayout, modules: [PromptModuleID],
        icons: PromptIcons, symbol: PromptSymbol
    ) {
        self.source = source
        self.style = style
        self.layout = layout
        self.modules = modules
        self.icons = icons
        self.symbol = symbol
    }

    /// The board's defaults: Línea limpia, the first six modules, thin icons and `›`.
    public static let standard = PromptConfig(
        source: .smalti, style: .clean, layout: .twoLines,
        modules: [.directory, .gitBranch, .gitStatus, .runtime, .duration, .agents], icons: .thin, symbol: .chevron)

    /// The template card that matches this style and layout; `nil` for a combination no card has.
    public var template: PromptTemplate? {
        PromptTemplate.allCases.first { $0.matches(style: style, layout: layout) }
    }

    /// The template's style and layout; modules, icons and symbol stay.
    public func applying(_ template: PromptTemplate) -> PromptConfig {
        var config = self
        config.style = template.style
        config.layout = template.layout
        return config
    }
}

public enum PromptSource: String, CaseIterable, Sendable {
    /// Smalti generates `PROMPT` (the default).
    case smalti
    /// The user's own prompt, untouched.
    case shell
}

public enum PromptStyleID: String, CaseIterable, Sendable {
    case clean
    case pills
    case symbolOnly = "symbol-only"
}

public enum PromptLayout: String, CaseIterable, Sendable {
    /// "Contexto arriba, input abajo".
    case twoLines = "two-lines"
    case oneLine = "one-line"
}

public enum PromptIcons: String, CaseIterable, Sendable {
    /// Smalti's own thin-stroke font.
    case thin
    case nerd
    case none
}

public enum PromptSymbol: String, CaseIterable, Sendable {
    case chevron = "›"
    case heavyChevron = "❯"
    case lambda = "λ"
    case dollar = "$"
}

/// The module identifiers of `theme.toml`, with the board's texts. What each one shows lives in its own
/// `PromptModule` type (OCP), not here.
public enum PromptModuleID: String, CaseIterable, Sendable {
    case directory
    case gitBranch = "git-branch"
    case gitStatus = "git-status"
    case runtime
    case duration
    /// "Agentes que esperan" (the board's "Estado del agente del panel", renamed by Simón).
    case agents
    case time
    case cloud

    public var title: String {
        switch self {
        case .directory: "Directorio"
        case .gitBranch: "Rama git"
        case .gitStatus: "Cambios git"
        case .runtime: "Runtime"
        case .duration: "Duración"
        case .agents: "Agentes que esperan"
        case .time: "Hora"
        case .cloud: "Contexto de Kubernetes / AWS"
        }
    }

    /// The grey note after the title on the board ("· últimos 2 niveles").
    public var detail: String? {
        switch self {
        case .directory: "últimos 2 niveles"
        case .gitStatus: "●2 +1"
        case .runtime: "Node, Bun, Python, Go"
        case .duration: "si pasa de 2 s"
        case .gitBranch, .agents, .time, .cloud: nil
        }
    }
}

/// The four template cards: a style and a layout each (spec F5).
public enum PromptTemplate: CaseIterable, Sendable {
    case cleanLine
    case singleLine
    case pills
    case symbolOnly

    public var title: String {
        switch self {
        case .cleanLine: "Línea limpia"
        case .singleLine: "Una sola línea"
        case .pills: "Píldoras"
        case .symbolOnly: "Solo símbolo"
        }
    }

    var style: PromptStyleID {
        switch self {
        case .cleanLine, .singleLine: .clean
        case .pills: .pills
        case .symbolOnly: .symbolOnly
        }
    }

    var layout: PromptLayout {
        switch self {
        case .cleanLine, .symbolOnly: .twoLines
        case .singleLine, .pills: .oneLine
        }
    }

    /// "Solo símbolo" has no layout: any layout matches it.
    func matches(style: PromptStyleID, layout: PromptLayout) -> Bool {
        self.style == style && (style == .symbolOnly || self.layout == layout)
    }
}

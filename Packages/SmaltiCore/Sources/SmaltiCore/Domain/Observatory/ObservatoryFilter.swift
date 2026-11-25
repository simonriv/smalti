/// The observatory's harness chips (Observatorio.dc.html, F6): every session, only Claude Code, only OpenCode, or
/// only sessions whose model runs on this Mac.
public enum ObservatoryFilter: CaseIterable, Equatable, Sendable {
    case all, claude, opencode, local

    public var title: String {
        switch self {
        case .all: "Todas"
        case .claude: "Claude Code"
        case .opencode: "OpenCode"
        case .local: "Locales"
        }
    }

    /// ⌘⇧F goes round the chips.
    public var next: ObservatoryFilter {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    /// Claude's models never run locally.
    var includesClaude: Bool { self == .all || self == .claude }

    func includes(_ usage: UsageRow) -> Bool {
        switch self {
        case .all: true
        case .claude: usage.harness == .claude
        case .opencode: usage.harness == .opencode
        case .local: usage.isLocal
        }
    }
}

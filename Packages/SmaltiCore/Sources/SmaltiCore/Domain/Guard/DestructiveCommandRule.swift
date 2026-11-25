/// What the rules know besides the command: the user's `[guards]` and the database hosts of the hook's environment
/// (`DATABASE_URL` and the like, already reduced to their host).
public struct GuardContext: Sendable {
    public let settings: GuardSettings
    public let environmentHosts: [String]

    public init(settings: GuardSettings, environmentHosts: [String]) {
        self.settings = settings
        self.environmentHosts = environmentHosts
    }
}

/// A command that needs the user's approval: which rule saw it («terraform destroy») and against what.
public struct GuardFinding: Equatable, Sendable {
    public let rule: String
    public let environment: DetectedEnvironment

    public init(rule: String, environment: DetectedEnvironment) {
        self.rule = rule
        self.environment = environment
    }
}

/// One kind of destructive command (spec F7.5, «Comandos que piden aprobación»). A new kind is a new type (OCP).
public protocol DestructiveCommandRule: Sendable {
    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding?
}

public enum DestructiveCommandRules {
    public static let all: [any DestructiveCommandRule] = [
        SupabaseRule(), PrismaRule(), DrizzleRule(), PackageScriptRule(), TerraformRule(), RailwayRule(),
        SQLClientRule(), DatabaseURLRule(), ProviderAPIRule(),
    ]

    /// Every finding in a shell line, its nested commands included, in order.
    public static func findings(in text: String, context: GuardContext, home: String) -> [GuardFinding] {
        ShellCommandLine.commands(in: text, home: home).flatMap { command in
            all.compactMap { $0.finding(for: command, context: context) }
        }
    }

    /// The environment of a database command: a URL in the command first, then the hook's environment.
    static func databaseEnvironment(
        of command: SimpleCommand, context: GuardContext, explicitHost: String? = nil
    ) -> DetectedEnvironment {
        let host = DatabaseURL.hosts(in: command.rawText).first ?? explicitHost ?? context.environmentHosts.first
        return HostEnvironment.classify(host: host, settings: context.settings)
    }

    /// The words that are not options (`-x`, `--x`, `--x=y`), in order.
    static func positional(_ arguments: [String]) -> [String] {
        arguments.filter { !$0.hasPrefix("-") }
    }
}

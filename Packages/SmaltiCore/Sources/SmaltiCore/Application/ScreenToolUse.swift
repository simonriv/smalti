/// Decides a tool call (spec F7.5): a secret read is denied, a destructive command asks, anything else is allowed.
/// The CLI runs it without settings; the app again with the user's `[guards]`.
public enum ScreenToolUse {
    /// The longest command or path screened; a longer one asks, because it cannot be reviewed.
    public static let maximumInputBytes = 65_536
    public static let oversizedRule = "comando demasiado largo para revisarlo"
    public static let nestedRule = "comando anidado demasiado para revisarlo"

    /// Review 1 (C1): what the app gets of a command the CLI had to cut; it can only ask.
    public static func truncatedSubject(_ command: String?) -> ApprovalSubject {
        ApprovalSubject(
            command: CommandRedaction.redacted(String((command ?? "").prefix(2_000))),
            findings: [GuardFinding(rule: oversizedRule, environment: .undetermined)])
    }

    private static let fileTools: Set<String> = ["Read", "Edit", "MultiEdit", "Write", "NotebookEdit"]

    public static func verdict(for use: ToolUse, context: GuardContext, home: String) -> GuardVerdict {
        let secrets = SecretPaths(home: home)
        switch use.tool {
        case let tool where fileTools.contains(tool):
            return fileVerdict(use.filePath, cwd: use.cwd, secrets: secrets)
        case "Grep":
            return grepVerdict(use, secrets: secrets)
        case "Bash":
            return use.command.map { bashVerdict($0, cwd: use.cwd, context: context, home: home) } ?? .allow
        default:
            return .allow
        }
    }

    private static func fileVerdict(_ path: String?, cwd: String?, secrets: SecretPaths) -> GuardVerdict {
        guard let path, secrets.isSecret(path, cwd: cwd) else { return .allow }
        return secretDenial(path)
    }

    private static func grepVerdict(_ use: ToolUse, secrets: SecretPaths) -> GuardVerdict {
        if let path = use.searchPath, secrets.isSecret(path, cwd: use.cwd) { return secretDenial(path) }
        if let glob = use.glob, secrets.mayMatchSecret(glob: glob) { return secretDenial(glob) }
        return .allow
    }

    private static func bashVerdict(_ command: String, cwd: String?, context: GuardContext, home: String)
        -> GuardVerdict
    {
        guard command.utf8.count <= maximumInputBytes else {
            let finding = GuardFinding(rule: oversizedRule, environment: .undetermined)
            return .ask(
                ApprovalSubject(command: CommandRedaction.redacted(String(command.prefix(2_000))), findings: [finding]))
        }
        let analysis = ShellCommandLine.analysis(in: command, home: home)
        let secrets = SecretPaths(home: home)
        if let path = analysis.commands.lazy.compactMap({ secrets.secretRead(in: $0, cwd: cwd) }).first {
            return secretDenial(path)
        }
        var findings = analysis.commands.flatMap { simple in
            DestructiveCommandRules.all.compactMap { $0.finding(for: simple, context: context) }
        }
        // Review 1: what is nested deeper than the guard reads cannot be judged, so it asks.
        if analysis.isTooDeep { findings.append(GuardFinding(rule: nestedRule, environment: .undetermined)) }
        guard !findings.isEmpty else { return .allow }
        return .ask(ApprovalSubject(command: CommandRedaction.redacted(command), findings: findings))
    }

    private static func secretDenial(_ path: String) -> GuardVerdict {
        .deny(GuardDenial(kind: .secret(path: path), reason: GuardReasons.secret(path: path)))
    }
}

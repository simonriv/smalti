/// SQL clients (`psql`, `pgcli`, `mysql`, `mariadb`) with `DROP` or `TRUNCATE`, or whose SQL cannot be seen (from a
/// file, a redirection or a pipe); `dropdb` always.
struct SQLClientRule: DestructiveCommandRule {
    private static let clients: Set<String> = ["psql", "pgcli", "mysql", "mariadb"]
    /// psql's `-e` echoes queries; only MySQL's runs SQL.
    private static let inlineSQLOptions: [String: Set<String>] = [
        "psql": ["-c", "--command"], "pgcli": ["-c", "--command"], "mysql": ["-e", "--execute"],
        "mariadb": ["-e", "--execute"],
    ]
    private static let fileOptions: Set<String> = ["-f", "--file"]
    private static let informational: Set<String> = ["--version", "-V", "--help", "-?"]
    private static let keywords = ["DROP", "TRUNCATE"]

    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard let program = command.program else { return nil }
        if program == "dropdb" { return finding("dropdb", command, context) }
        guard Self.clients.contains(program),
            !command.arguments.contains(where: { Self.informational.contains($0) })
        else { return nil }
        let text = ([command.rawText] + command.heredocs).joined(separator: "\n")
        if let keyword = Self.keywords.first(where: { Self.containsWord($0, in: text) }) {
            return finding(context.texts.withKeyword(["program": program, "keyword": keyword]), command, context)
        }
        let inline = Self.inlineSQLOptions[program] ?? []
        let showsSQL = command.arguments.contains { Self.isOption($0, in: inline) }
        let readsFile = command.arguments.contains { Self.isOption($0, in: Self.fileOptions) }
        return showsSQL && !readsFile
            ? nil : finding(context.texts.noVisibleSQL(["program": program]), command, context)
    }

    /// `-c`, `-cSQL`, `--command`, `--command=SQL`.
    private static func isOption(_ word: String, in options: Set<String>) -> Bool {
        options.contains { option in
            word == option || word.hasPrefix(option + "=") || (!option.hasPrefix("--") && word.hasPrefix(option))
        }
    }

    private func finding(_ rule: String, _ command: SimpleCommand, _ context: GuardContext) -> GuardFinding {
        GuardFinding(
            rule: rule,
            environment: DestructiveCommandRules.databaseEnvironment(
                of: command, context: context, explicitHost: Self.hostOption(command.arguments)))
    }

    private static func hostOption(_ arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if (argument == "-h" || argument == "--host"), index + 1 < arguments.count { return arguments[index + 1] }
            if argument.hasPrefix("--host=") { return String(argument.dropFirst(7)) }
        }
        return nil
    }

    /// `word` as a whole SQL word, without case: `drop table` yes, `drop_column` no.
    static func containsWord(_ word: String, in text: String) -> Bool {
        let upper = Array(text.uppercased())
        let target = Array(word)
        guard upper.count >= target.count else { return false }
        return (0...(upper.count - target.count)).contains { start in
            Array(upper[start..<start + target.count]) == target && !isWordCharacter(upper, start - 1)
                && !isWordCharacter(upper, start + target.count)
        }
    }

    private static func isWordCharacter(_ characters: [Character], _ index: Int) -> Bool {
        guard index >= 0, index < characters.count else { return false }
        return characters[index].isLetter || characters[index].isNumber || characters[index] == "_"
    }
}

/// Any command with a database URL whose host is not local nor in `non_production_hosts`.
struct DatabaseURLRule: DestructiveCommandRule {
    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        let environments = DatabaseURL.hosts(in: command.rawText).map {
            HostEnvironment.classify(host: $0, settings: context.settings)
        }
        guard let worst = DetectedEnvironment.mostSevere(environments), worst.kind == .production else { return nil }
        return GuardFinding(rule: context.texts.databaseURL, environment: worst)
    }
}

/// SQL clients (`psql`, `pgcli`, `mysql`, `mariadb`) with `DROP` or `TRUNCATE`, or whose SQL cannot be seen (from a
/// file, a redirection or a pipe); `dropdb` always.
struct SQLClientRule: DestructiveCommandRule {
    private static let clients: Set<String> = ["psql", "pgcli", "mysql", "mariadb"]
    private static let inlineSQLOptions: Set<String> = ["-c", "--command", "-e", "--execute"]
    private static let informational: Set<String> = ["--version", "-V", "--help", "-?"]
    private static let keywords = ["DROP", "TRUNCATE"]

    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard let program = command.program else { return nil }
        if program == "dropdb" { return finding("dropdb", command, context) }
        guard Self.clients.contains(program),
            !command.arguments.contains(where: { Self.informational.contains($0) })
        else { return nil }
        if let keyword = Self.keywords.first(where: { Self.containsWord($0, in: command.rawText) }) {
            return finding("\(program) con \(keyword)", command, context)
        }
        let showsSQL = command.arguments.contains { option in
            Self.inlineSQLOptions.contains(option) || Self.inlineSQLOptions.contains { option.hasPrefix($0 + "=") }
        }
        return showsSQL ? nil : finding("\(program) sin SQL visible", command, context)
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
        return GuardFinding(rule: "URL de base de datos", environment: worst)
    }
}

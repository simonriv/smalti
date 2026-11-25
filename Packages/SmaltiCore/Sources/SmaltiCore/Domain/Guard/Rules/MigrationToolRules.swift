/// `supabase db push|reset`, `supabase projects|branches delete`. `--local` is local, `--db-url` names the host,
/// anything else acts on the linked project.
struct SupabaseRule: DestructiveCommandRule {
    private static let destructive: [(String, String)] = [
        ("db", "push"), ("db", "reset"), ("projects", "delete"), ("branches", "delete"),
    ]

    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard command.program == "supabase" else { return nil }
        let words = DestructiveCommandRules.positional(command.arguments)
        // Anywhere among the words: an option's value (`--workdir app`) may come first (review 1).
        guard
            let pair = zip(words, words.dropFirst()).first(where: { pair in Self.destructive.contains { $0 == pair } })
        else { return nil }
        return GuardFinding(rule: "supabase \(pair.0) \(pair.1)", environment: environment(command, context))
    }

    private func environment(_ command: SimpleCommand, _ context: GuardContext) -> DetectedEnvironment {
        if command.arguments.contains("--local") {
            return DetectedEnvironment(kind: .local, host: nil, cause: .localFlag)
        }
        if let host = DatabaseURL.hosts(in: command.rawText).first {
            return HostEnvironment.classify(host: host, settings: context.settings)
        }
        return DetectedEnvironment(kind: .production, host: nil, cause: .linkedProject)
    }
}

/// `prisma migrate reset` and `prisma db push`.
struct PrismaRule: DestructiveCommandRule {
    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard command.program == "prisma" else { return nil }
        let words = DestructiveCommandRules.positional(command.arguments).prefix(2)
        guard words == ["migrate", "reset"] || words == ["db", "push"] else { return nil }
        return GuardFinding(
            rule: "prisma \(words.joined(separator: " "))",
            environment: DestructiveCommandRules.databaseEnvironment(of: command, context: context))
    }
}

/// `drizzle-kit push` and `drizzle-kit drop`.
struct DrizzleRule: DestructiveCommandRule {
    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard command.program == "drizzle-kit",
            let verb = DestructiveCommandRules.positional(command.arguments).first, verb == "push" || verb == "drop"
        else { return nil }
        return GuardFinding(
            rule: "drizzle-kit \(verb)",
            environment: DestructiveCommandRules.databaseEnvironment(of: command, context: context))
    }
}

/// A package script named like `db:push` (`(db|database|migrate|prisma|drizzle|supabase)[:._-](push|reset|drop|…)`),
/// run with npm, pnpm, yarn or bun.
struct PackageScriptRule: DestructiveCommandRule {
    private static let managers: Set<String> = ["npm", "pnpm", "yarn", "bun", "turbo"]
    private static let subjects: Set<Substring> = ["db", "database", "migrate", "prisma", "drizzle", "supabase"]
    private static let verbs: Set<Substring> = ["push", "reset", "drop", "destroy", "wipe"]

    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard let manager = command.program, Self.managers.contains(manager) else { return nil }
        // Any word: in a monorepo an option's value comes first (`pnpm --filter api db:push`, review 1).
        let words = DestructiveCommandRules.positional(command.arguments)
        guard let script = words.first(where: Self.isDestructive) else { return nil }
        let usesRun = words.contains("run") || words.contains("run-script")
        return GuardFinding(
            rule: ([manager] + (usesRun ? ["run"] : []) + [script]).joined(separator: " "),
            environment: DestructiveCommandRules.databaseEnvironment(of: command, context: context))
    }

    static func isDestructive(_ script: String) -> Bool {
        let parts = script.lowercased().split { ":._-".contains($0) }
        return zip(parts, parts.dropFirst()).contains { subjects.contains($0) && verbs.contains($1) }
    }
}

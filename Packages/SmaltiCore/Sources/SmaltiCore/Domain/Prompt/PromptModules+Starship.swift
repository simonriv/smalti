// Each module's Starship modules (spec F5, "Exportar como starship.toml"), in format order.

extension DirectoryModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [
            builder.module(
                "directory", "$path", .accent, icon: .folder,
                extra: [("truncation_length", .integer(2)), ("truncate_to_repo", .boolean(true))])
        ]
    }
}

extension GitBranchModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [builder.module("git_branch", "$symbol$branch", .ansi(5), symbol: .branch)]
    }
}

extension GitStatusModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [
            builder.table(
                "git_status",
                [
                    ("modified", .string("●${count}")), ("staged", .string("+${count}")),
                    ("style", .string(builder.style(.ansi(3)))),
                    ("format", .string(builder.wrap("$modified$staged", .ansi(3), optional: true))),
                ])
        ]
    }
}

extension RuntimeModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [("nodejs", PromptIcon.node), ("bun", .bun), ("python", .python), ("golang", .go)].map {
            builder.module(
                $0.0, "$symbol$version", .secondary, symbol: $0.1,
                extra: [("version_format", .string("${major}.${minor}"))])
        }
    }
}

extension DurationModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [builder.module("cmd_duration", "$duration", .secondary, extra: [("min_time", .integer(2000))])]
    }
}

extension AgentsModule {
    /// Only Smalti knows its agents: the preset carries a comment instead.
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] { [] }
}

extension TimeModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [
            builder.module(
                "time", "$time", .secondary, icon: .clock,
                extra: [("disabled", .boolean(false)), ("time_format", .string("%H:%M"))])
        ]
    }
}

extension CloudModule {
    func starshipTables(using builder: StarshipBuilder) -> [StarshipTable] {
        [
            builder.module("kubernetes", "k8s:$context", .ansi(6), extra: [("disabled", .boolean(false))]),
            builder.module("aws", "aws:$profile", .ansi(6)),
        ]
    }
}

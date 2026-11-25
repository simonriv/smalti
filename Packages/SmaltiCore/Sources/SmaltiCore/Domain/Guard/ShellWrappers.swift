/// The commands that only run another one (spec F7.5): `sudo`, `env`, `npx`, `timeout`, `pnpm dlx`, `uv run`,
/// `doppler run --`… Taking them off, and the assignments after each, leaves the program a guard rule compares.
enum ShellWrappers {
    /// Shell keywords that may start a simple command before the real program.
    private static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}",
    ]
    /// Wrappers that take options (those listed take a value), then the program.
    private static let optionWrappers: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"],
        "command": [], "exec": ["-a"], "builtin": [], "nohup": [], "time": [],
        "nice": ["-n"], "npx": ["-p", "--package", "-c", "--call"], "bunx": ["-p", "--package"],
        "xargs": ["-n", "-I", "-L", "-P", "-d", "-s", "-E", "-a", "-J", "-R"], "watch": ["-n", "--interval"],
        "caffeinate": ["-w", "-t"],
    ]
    /// Wrappers that run what follows `--`.
    private static let dashDashWrappers: Set<String> = ["dotenv", "dotenv-cli"]
    /// `<tool> <verb>` pairs that run the following program.
    private static let verbWrappers: [String: Set<String>] = [
        "pnpm": ["dlx", "exec"], "yarn": ["dlx", "exec"], "npm": ["exec"], "bun": ["x", "exec"],
        "doppler": ["run"], "op": ["run"], "infisical": ["run"], "dotenvx": ["run"], "uv": ["run"],
        "poetry": ["run"], "pipenv": ["run"], "pdm": ["run"], "bundle": ["exec"],
    ]
    /// Options of the verb wrappers that take a value (`uv run --with x`).
    private static let verbOptionsWithValue: Set<String> = [
        "--with", "--python", "-p", "--project", "--directory", "--env-file", "-f", "-C", "--cwd", "--filter", "-F",
    ]
    /// Binaries a package manager runs directly (`pnpm prisma migrate reset`).
    private static let packageManagers: Set<String> = ["pnpm", "yarn", "bun"]
    private static let packageBinaries: Set<String> = [
        "prisma", "drizzle-kit", "supabase", "terraform", "tofu", "terragrunt", "railway", "psql", "dropdb",
    ]

    static func strip(_ words: ArraySlice<String>, into assignments: inout [String: String]) -> ArraySlice<String> {
        var rest = takeAssignments(words, into: &assignments)
        while let first = rest.first {
            let name = ShellCommandLine.baseName(first)
            guard let stripped = strip(name, from: rest) else { break }
            rest = takeAssignments(stripped, into: &assignments)
        }
        return rest
    }

    private static func takeAssignments(
        _ words: ArraySlice<String>, into assignments: inout [String: String]
    ) -> ArraySlice<String> {
        var rest = words
        while let first = rest.first, let (name, value) = ShellCommandLine.assignment(first) {
            assignments[name] = value
            rest = rest.dropFirst()
        }
        return rest
    }

    private static func strip(_ name: String, from words: ArraySlice<String>) -> ArraySlice<String>? {
        if keywords.contains(name) { return words.dropFirst() }
        if name == "env" { return afterOptions(words.dropFirst(), withValue: ["-u", "-S", "-P", "-C"]) }
        if name == "timeout" {
            return afterOptions(words.dropFirst(), withValue: ["-s", "-k", "--signal", "--kill-after"]).dropFirst()
        }
        if let withValue = optionWrappers[name] { return afterOptions(words.dropFirst(), withValue: withValue) }
        if dashDashWrappers.contains(name) { return afterDashDash(words.dropFirst()) }
        if let verbs = verbWrappers[name], let verb = words.dropFirst().first, verbs.contains(verb) {
            let rest = words.dropFirst(2)
            return rest.contains("--") ? afterDashDash(rest) : afterOptions(rest, withValue: verbOptionsWithValue)
        }
        if packageManagers.contains(name), let next = words.dropFirst().first, packageBinaries.contains(next) {
            return words.dropFirst()
        }
        return nil
    }

    private static func afterOptions(_ words: ArraySlice<String>, withValue: Set<String>) -> ArraySlice<String> {
        var rest = words
        while let first = rest.first, first.hasPrefix("-") {
            rest = rest.dropFirst(withValue.contains(first) ? 2 : 1)
            if first == "--" { break }
        }
        return rest
    }

    private static func afterDashDash(_ words: ArraySlice<String>) -> ArraySlice<String> {
        guard let dashes = words.firstIndex(of: "--") else { return afterOptions(words, withValue: []) }
        return words[words.index(after: dashes)...]
    }
}

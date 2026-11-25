/// The commands that only run another one (spec F7.5): `sudo`, `env`, `npx`, `pnpm dlx`, `doppler run --`… Taking
/// them off leaves the program a guard rule compares.
enum ShellWrappers {
    /// Shell keywords that may start a simple command before the real program.
    private static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}",
    ]
    /// Wrappers that take options, then the program.
    private static let optionWrappers: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"],
        "command": [], "exec": ["-a"], "builtin": [], "nohup": [], "time": [],
        "nice": ["-n"], "npx": ["-p", "--package", "-c", "--call"], "bunx": ["-p", "--package"],
    ]
    /// Wrappers that run what follows `--`.
    private static let dashDashWrappers: Set<String> = ["dotenv", "dotenv-cli"]
    /// `<tool> <verb>` pairs that run the following program.
    private static let verbWrappers: [String: Set<String>] = [
        "pnpm": ["dlx", "exec"], "yarn": ["dlx", "exec"], "npm": ["exec"], "doppler": ["run"], "op": ["run"],
        "infisical": ["run"],
    ]

    static func strip(_ words: ArraySlice<String>, into assignments: inout [String: String]) -> ArraySlice<String> {
        var rest = words
        while let first = rest.first {
            let name = ShellCommandLine.baseName(first)
            guard let stripped = strip(name, from: rest, into: &assignments) else { break }
            rest = stripped
        }
        return rest
    }

    private static func strip(
        _ name: String, from words: ArraySlice<String>, into assignments: inout [String: String]
    ) -> ArraySlice<String>? {
        if keywords.contains(name) { return words.dropFirst() }
        if name == "env" { return afterEnv(words.dropFirst(), into: &assignments) }
        if let withValue = optionWrappers[name] { return afterOptions(words.dropFirst(), withValue: withValue) }
        if dashDashWrappers.contains(name) { return afterDashDash(words.dropFirst()) }
        if let verbs = verbWrappers[name], let verb = words.dropFirst().first, verbs.contains(verb) {
            let rest = words.dropFirst(2)
            return rest.contains("--") ? afterDashDash(rest) : afterOptions(rest, withValue: [])
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

    /// `env [-i] [-u NAME] [NAME=value…] program`.
    private static func afterEnv(
        _ words: ArraySlice<String>, into assignments: inout [String: String]
    ) -> ArraySlice<String> {
        var rest = afterOptions(words, withValue: ["-u", "-S", "-P", "-C"])
        while let first = rest.first, let (name, value) = ShellCommandLine.assignment(first) {
            assignments[name] = value
            rest = rest.dropFirst()
        }
        return rest
    }
}

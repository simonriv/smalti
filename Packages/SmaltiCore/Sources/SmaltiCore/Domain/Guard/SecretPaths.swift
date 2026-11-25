/// Which files hold secrets, and whether a shell command reads one (spec F7.5, «Qué es un secreto» and «Lectura de
/// secretos por Bash»).
public struct SecretPaths: Sendable {
    /// What `secretRead(in:)` answers for a keychain read (`security find-generic-password -w`).
    public static let keychain = "llavero"

    private let home: String

    public init(home: String) {
        self.home = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
    }

    // MARK: - Names

    private static let exampleSuffixes: Set<String> = ["example", "sample", "template", "dist", "defaults"]
    private static let extensions = [".pem", ".key", ".p12", ".pfx", ".tfstate", ".tfstate.backup"]
    private static let privateKeyPrefixes = ["id_rsa", "id_ed25519", "id_ecdsa", "id_dsa"]
    private static let dotFiles: Set<String> = [".netrc", ".pgpass", ".npmrc", ".pypirc"]
    /// Directories and files under the home, relative to it.
    static let homeDirectories = [".ssh", ".aws", ".config/gcloud", ".kube", ".config/gh", ".railway", ".supabase"]
    static let homeFiles = [".docker/config.json", ".netrc", ".pgpass", ".npmrc", ".pypirc"]
    /// Names a glob is tried against to decide whether it may reach a secret.
    private static let representativeNames = [
        ".env", ".env.local", ".env.production", "a.pem", "a.key", "a.p12", "a.pfx", "terraform.tfstate",
        "terraform.tfstate.backup", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".netrc", ".pgpass", ".npmrc",
        ".pypirc",
    ]

    /// Compared without case: the Mac's file system ignores it (`.ENV` is `.env`, review 1).
    static func isSecretName(_ original: String) -> Bool {
        let name = original.lowercased()
        if name == ".env" { return true }
        if name.hasPrefix(".env.") { return !exampleSuffixes.contains(String(name.dropFirst(5))) }
        if dotFiles.contains(name) { return true }
        if extensions.contains(where: { name.hasSuffix($0) && name.count > $0.count }) { return true }
        return privateKeyPrefixes.contains { name.hasPrefix($0) } && !name.hasSuffix(".pub")
    }

    // MARK: - Paths

    /// Whether `path` (absolute, or relative to `cwd` when given) is a secret file or lies in a secret directory.
    public func isSecret(_ path: String, cwd: String?) -> Bool {
        let absolute = GuardPathResolver.absolute(path, cwd: cwd)
        guard let name = absolute.split(separator: "/").last.map(String.init) else { return false }
        // A public key is not a secret, even inside `~/.ssh`.
        if name.lowercased().hasSuffix(".pub") { return false }
        return Self.isSecretName(name) || isInSecretHomePlace(absolute)
    }

    private func isInSecretHomePlace(_ original: String) -> Bool {
        let absolute = original.lowercased()
        let root = home.lowercased()
        let directories = Self.homeDirectories.map { "\(root)/\($0)" }
        if directories.contains(where: { absolute == $0 || absolute.hasPrefix($0 + "/") }) { return true }
        return Self.homeFiles.contains { absolute == "\(root)/\($0)" }
    }

    /// Whether a glob could name a secret: its last component matches a secret name and is not only wildcards, or
    /// its directory is a secret one (`~/.ssh/*`).
    public func mayMatchSecret(glob: String) -> Bool {
        let parts = glob.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // Splitting never yields no parts; the glob itself is only a fallback for the type checker.
        let last = parts.last ?? glob
        let directory = parts.dropLast().joined(separator: "/")
        if !directory.isEmpty && !GlobPattern.hasWildcard(directory) && isSecret(directory, cwd: nil) {
            return true
        }
        let hasLiteral = last.contains { !GlobPattern.wildcards.contains($0) && $0 != "]" }
        return hasLiteral && Self.representativeNames.contains { GlobPattern.matches(last, $0) }
    }

    // MARK: - Shell commands

    /// Programs that only look at a file's metadata, remove it, move into a folder or print their words: naming a
    /// secret does not read it (review 1 amendment: `echo .env >> .gitignore`, `cd ~/.aws`).
    private static let nonReadingPrograms: Set<String> = [
        "ls", "stat", "test", "[", "[[", "touch", "chmod", "rm", "echo", "printf", "cd", "pushd", "popd",
    ]
    private static let interpreters: Set<String> = ["node", "ruby", "perl", "deno", "bun", "tsx"]
    private static let awks: Set<String> = ["awk", "gawk", "mawk"]
    private static let codeOptions: Set<String> = ["-c", "-e", "--eval", "-p", "--print", "-E"]

    /// The secret path a command reads, as written (or `keychain`), or nil.
    public func secretRead(in command: SimpleCommand, cwd: String? = nil) -> String? {
        if let found = firstSecret(command.redirections, cwd: cwd) { return found }
        guard let program = command.program else { return nil }
        if KeychainRead.matches(program: program, arguments: command.arguments) { return Self.keychain }
        if let found = firstSecret(ReadArguments.paths(program: program, arguments: command.arguments), cwd: cwd) {
            return found
        }
        return firstSecret(code(of: program, command).flatMap(pathFragmentsExpanded), cwd: cwd)
    }

    /// The code an interpreter runs from its words or a here-document (`python3 - <<EOF`), where a path may hide.
    private func code(of program: String, _ command: SimpleCommand) -> [String] {
        if Self.awks.contains(program) {
            return Array(command.arguments.first { !$0.hasPrefix("-") }.map { [$0] } ?? []) + command.heredocs
        }
        guard Self.interpreters.contains(program) || program.hasPrefix("python") else { return [] }
        var code = command.heredocs
        for (index, word) in command.arguments.enumerated() {
            if Self.codeOptions.contains(word), index + 1 < command.arguments.count {
                code.append(command.arguments[index + 1])
            } else if let equals = word.firstIndex(of: "="), Self.codeOptions.contains(String(word[..<equals])) {
                code.append(String(word[word.index(after: equals)...]))
            }
        }
        return code
    }

    static func isNonReading(_ program: String) -> Bool {
        nonReadingPrograms.contains(program)
    }

    private func firstSecret(_ candidates: [String], cwd: String?) -> String? {
        for candidate in candidates.flatMap(Self.pathCandidates) {
            if GlobPattern.hasWildcard(candidate) ? mayMatchSecret(glob: candidate) : isSecret(candidate, cwd: cwd) {
                return candidate
            }
        }
        return nil
    }

    /// A word and the paths it may hide: the value of `--file=x`, the path of `git show REV:x`, a curl upload
    /// (`@x`, `<x`, `-d@x`, `file=@x`) and a brace expansion (`.env{,.bak}`).
    private static func pathCandidates(_ word: String) -> [String] {
        var candidates = [word] + BraceExpansion.expanded(word)
        if let equals = word.firstIndex(of: "=") { candidates.append(String(word[word.index(after: equals)...])) }
        if let colon = word.firstIndex(of: ":") { candidates.append(String(word[word.index(after: colon)...])) }
        if let at = word.firstIndex(of: "@") { candidates.append(String(word[word.index(after: at)...])) }
        if word.hasPrefix("<") { candidates.append(String(word.dropFirst())) }
        return candidates.filter { !$0.isEmpty }
    }

    /// The path-like pieces of interpreter code: `print(open('.env').read())` → `print`, `open`, `.env`, `.read`.
    private func pathFragmentsExpanded(_ code: String) -> [String] {
        Self.pathFragments(code).map { $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
    }

    private static func pathFragments(_ code: String) -> [String] {
        code.split { !($0.isLetter || $0.isNumber || "._/~-*?".contains($0)) }.map(String.init)
    }
}

/// The words of a command that may name a file it reads (spec F7.5 and review 1 amendments).
enum ReadArguments {
    /// Runners that load an env file into the program they start without showing it, unless asked to print.
    private static let envFileRunners: Set<String> = ["node", "bun", "deno", "tsx", "docker", "docker-compose"]
    private static let printingOptions: Set<String> = ["-e", "--eval", "-p", "--print"]

    static func paths(program: String, arguments: [String]) -> [String] {
        if SecretPaths.isNonReading(program) { return [] }
        if program == "git", arguments.first == "rm" { return [] }
        if program == "cp" || program == "mv" { return sources(arguments) }
        if envFileRunners.contains(program) { return withoutEnvFiles(arguments) }
        return arguments
    }

    /// `cp`/`mv` read their sources, not the destination (`cp .env.example .env`).
    private static func sources(_ arguments: [String]) -> [String] {
        // A brace word is several arguments: `cp .env{,.bak}` copies `.env` to `.env.bak`.
        let positional = arguments.filter { !$0.hasPrefix("-") }.flatMap { word in
            let expanded = BraceExpansion.expanded(word)
            return expanded.isEmpty ? [word] : expanded
        }
        return arguments.filter { $0.hasPrefix("-") } + positional.dropLast()
    }

    /// `node --env-file=.env server.js` passes; with `-e`, `-p` or `docker compose config` the values would show.
    private static func withoutEnvFiles(_ arguments: [String]) -> [String] {
        let prints = arguments.contains { word in printingOptions.contains { word == $0 || word.hasPrefix($0 + "=") } }
        guard !prints, !arguments.contains("config") else { return arguments }
        var kept: [String] = []
        var skipNext = false
        for word in arguments {
            if skipNext {
                skipNext = false
            } else if word == "--env-file" {
                skipNext = true
            } else if !word.hasPrefix("--env-file=") {
                kept.append(word)
            }
        }
        return kept
    }
}

/// One level of shell brace expansion: `.env{,.bak}` → `.env`, `.env.bak`.
enum BraceExpansion {
    static func expanded(_ word: String) -> [String] {
        guard let open = word.firstIndex(of: "{"), let close = word[open...].firstIndex(of: "}") else { return [] }
        let inner = word[word.index(after: open)..<close]
        guard inner.contains(",") else { return [] }
        let prefix = word[..<open]
        let suffix = word[word.index(after: close)...]
        return inner.split(separator: ",", omittingEmptySubsequences: false).map { "\(prefix)\($0)\(suffix)" }
    }
}

/// `security find-generic-password`, `find-internet-password` or `find-certificate` with `-w` or `-g`: prints a
/// secret from the keychain.
enum KeychainRead {
    private static let verbs: Set<String> = ["find-generic-password", "find-internet-password", "find-certificate"]

    static func matches(program: String, arguments: [String]) -> Bool {
        guard program == "security", let verb = arguments.first, verbs.contains(verb) else { return false }
        return arguments.dropFirst().contains { $0 == "-w" || $0 == "-g" || ($0.hasPrefix("-") && $0.contains("w")) }
    }
}

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

    static func isSecretName(_ name: String) -> Bool {
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
        if name.hasSuffix(".pub") { return false }
        return Self.isSecretName(name) || isInSecretHomePlace(absolute)
    }

    private func isInSecretHomePlace(_ absolute: String) -> Bool {
        let directories = Self.homeDirectories.map { "\(home)/\($0)" }
        if directories.contains(where: { absolute == $0 || absolute.hasPrefix($0 + "/") }) { return true }
        return Self.homeFiles.contains { absolute == "\(home)/\($0)" }
    }

    /// Whether a glob could name a secret: its last component matches a secret name and is not only wildcards, or
    /// its directory is a secret one (`~/.ssh/*`).
    public func mayMatchSecret(glob: String) -> Bool {
        let parts = glob.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last else { return false }
        let directory = parts.dropLast().joined(separator: "/")
        if !directory.isEmpty && !GlobPattern.hasWildcard(directory) && isSecret(directory, cwd: nil) {
            return true
        }
        let hasLiteral = last.contains { !GlobPattern.wildcards.contains($0) && $0 != "]" }
        return hasLiteral && Self.representativeNames.contains { GlobPattern.matches(last, $0) }
    }

    // MARK: - Shell commands

    /// Programs that only look at a file's metadata or remove it: naming a secret does not read it.
    private static let metadataPrograms: Set<String> = ["ls", "stat", "test", "[", "[[", "touch", "chmod", "rm"]
    private static let interpreters: Set<String> = ["node", "ruby", "perl", "awk", "gawk", "mawk", "deno", "bun"]

    /// The secret path a command reads, as written (or `keychain`), or nil.
    public func secretRead(in command: SimpleCommand, cwd: String? = nil) -> String? {
        guard let program = command.program, !Self.metadataPrograms.contains(program) else {
            return command.program == nil ? firstSecret(command.redirections, cwd: cwd) : nil
        }
        if KeychainRead.matches(program: program, arguments: command.arguments) { return Self.keychain }
        if let found = firstSecret(command.arguments + command.redirections, cwd: cwd) { return found }
        guard Self.isInterpreter(program) else { return nil }
        return firstSecret(command.arguments.flatMap(pathFragmentsExpanded), cwd: cwd)
    }

    private func firstSecret(_ candidates: [String], cwd: String?) -> String? {
        for candidate in candidates.flatMap(Self.pathCandidates) {
            if GlobPattern.hasWildcard(candidate) ? mayMatchSecret(glob: candidate) : isSecret(candidate, cwd: cwd) {
                return candidate
            }
        }
        return nil
    }

    /// A word and the paths it may hide: the value of `--file=x` and the path of `git show REV:x`.
    private static func pathCandidates(_ word: String) -> [String] {
        var candidates = [word]
        if let equals = word.firstIndex(of: "=") { candidates.append(String(word[word.index(after: equals)...])) }
        if let colon = word.firstIndex(of: ":") { candidates.append(String(word[word.index(after: colon)...])) }
        return candidates.filter { !$0.isEmpty }
    }

    private static func isInterpreter(_ program: String) -> Bool {
        interpreters.contains(program) || program.hasPrefix("python")
    }

    /// The path-like pieces of interpreter code: `print(open('.env').read())` → `print`, `open`, `.env`, `.read`.
    private func pathFragmentsExpanded(_ code: String) -> [String] {
        Self.pathFragments(code).map { $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
    }

    private static func pathFragments(_ code: String) -> [String] {
        code.split { !($0.isLetter || $0.isNumber || "._/~-*?".contains($0)) }.map(String.init)
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

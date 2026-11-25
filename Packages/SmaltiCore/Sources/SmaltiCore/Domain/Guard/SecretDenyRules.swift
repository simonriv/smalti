/// The `permissions.deny` rules Smalti writes into a project's `.claude/settings.local.json` (spec F7.5): project
/// files relative and at any depth, the home's absolute with `//`, as Claude Code's permission syntax asks.
public enum SecretDenyRules {
    private static let projectPatterns = [
        ".env", ".env.local", ".env.*.local", ".env.production", ".env.development", ".env.staging", ".env.test",
        "*.pem", "*.key", "*.p12", "*.pfx", "*.tfstate", "*.tfstate.backup",
        // Final review: what the guard also calls a secret inside a project.
        ".env.preview", ".npmrc", ".pypirc", ".netrc", ".pgpass", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
    ]

    public static func rules(home: String) -> [String] {
        let root = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
        let homeRules =
            SecretPaths.homeDirectories.map { "Read(/\(root)/\($0)/**)" }
            + SecretPaths.homeFiles.map { "Read(/\(root)/\($0))" }
        return projectPatterns.map { "Read(**/\($0))" } + homeRules
    }
}

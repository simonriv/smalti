/// ⌘K «Proteger secretos en “<proyecto>”» (spec F7.5): adds Smalti's deny rules to the project's local Claude
/// settings, keeping every other rule, and takes exactly those out again.
public struct ProtectProjectSecrets: Sendable {
    private let permissions: any ProjectPermissions
    private let rules: [String]
    private let home: String

    public init(permissions: any ProjectPermissions, home: String) {
        self.permissions = permissions
        self.home = Self.trimmed(home)
        rules = SecretDenyRules.rules(home: home)
    }

    /// Never the home folder nor one above it (review 2): their `.claude` is the user's global configuration, which
    /// Smalti does not write.
    public func canProtect(_ project: String) -> Bool {
        let folder = Self.trimmed(project)
        return !(folder == home || folder == "/" || home.hasPrefix(folder + "/"))
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    public func isProtected(_ project: String) throws(ProjectPermissionsError) -> Bool {
        let current = Set(try permissions.deniedRules(in: project))
        return rules.allSatisfy(current.contains)
    }

    public func protect(_ project: String) throws(ProjectPermissionsError) {
        guard canProtect(project) else {
            throw .unwritable(
                path: project, reason: "es tu carpeta personal: Smalti no escribe tu configuración global")
        }
        let current = try permissions.deniedRules(in: project)
        let missing = rules.filter { !current.contains($0) }
        guard !missing.isEmpty else { return }
        try permissions.setDeniedRules(current + missing, in: project)
    }

    public func unprotect(_ project: String) throws(ProjectPermissionsError) {
        let current = try permissions.deniedRules(in: project)
        let ours = Set(rules)
        let kept = current.filter { !ours.contains($0) }
        guard kept.count != current.count else { return }
        try permissions.setDeniedRules(kept, in: project)
    }
}

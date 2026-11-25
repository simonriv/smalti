/// ⌘K «Proteger secretos en “<proyecto>”» (spec F7.5): adds Smalti's deny rules to the project's local Claude
/// settings, keeping every other rule, and takes exactly those out again.
public struct ProtectProjectSecrets: Sendable {
    private let permissions: any ProjectPermissions
    private let rules: [String]

    public init(permissions: any ProjectPermissions, home: String) {
        self.permissions = permissions
        rules = SecretDenyRules.rules(home: home)
    }

    public func isProtected(_ project: String) throws(ProjectPermissionsError) -> Bool {
        let current = Set(try permissions.deniedRules(in: project))
        return rules.allSatisfy(current.contains)
    }

    public func protect(_ project: String) throws(ProjectPermissionsError) {
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

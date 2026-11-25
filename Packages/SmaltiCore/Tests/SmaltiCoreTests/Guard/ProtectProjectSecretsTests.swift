import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Protect project secrets")
struct ProtectProjectSecretsTests {
    private let project = "/p/rizaria"
    private let rules = SecretDenyRules.rules(home: "/Users/u")

    private func useCase(_ permissions: InMemoryProjectPermissions) -> ProtectProjectSecrets {
        ProtectProjectSecrets(permissions: permissions, home: "/Users/u")
    }

    @Test func protectAddsAllRulesOnce() throws {
        let permissions = InMemoryProjectPermissions()

        try useCase(permissions).protect(project)

        #expect(permissions.rules[project] == rules)
    }

    @Test func protectKeepsForeignRules() throws {
        let permissions = InMemoryProjectPermissions(rules: [project: ["Bash(rm:*)", "Read(**/.env)"]])

        try useCase(permissions).protect(project)

        #expect(permissions.rules[project] == ["Bash(rm:*)", "Read(**/.env)"] + rules.dropFirst())
    }

    @Test func protectTwiceDoesNotDuplicate() throws {
        let permissions = InMemoryProjectPermissions()

        try useCase(permissions).protect(project)
        try useCase(permissions).protect(project)

        #expect(permissions.rules[project] == rules)
    }

    @Test func unprotectRemovesOnlyOurs() throws {
        let permissions = InMemoryProjectPermissions(rules: [project: ["Bash(rm:*)"] + rules])

        try useCase(permissions).unprotect(project)

        #expect(permissions.rules[project] == ["Bash(rm:*)"])
    }

    @Test func isProtectedNeedsAll() throws {
        let partial = InMemoryProjectPermissions(rules: [project: Array(rules.dropLast())])
        let full = InMemoryProjectPermissions(rules: [project: rules])

        #expect(try !useCase(partial).isProtected(project))
        #expect(try useCase(full).isProtected(project))
        #expect(try !useCase(InMemoryProjectPermissions()).isProtected(project))
    }

    @Test func unreadableSettingsFailWithoutWriting() {
        let permissions = InMemoryProjectPermissions()
        permissions.failure = .unreadable(path: "/p/rizaria/.claude/settings.local.json", reason: "comentario")

        #expect(throws: ProjectPermissionsError.self) { try useCase(permissions).protect(project) }
        #expect(permissions.writes == 0)
    }

    @Test func errorsSayWhatFailed() {
        let error = ProjectPermissionsError.unreadable(path: "/p/.claude/settings.local.json", reason: "JSON inválido")

        #expect(error.message == "No se pudo leer /p/.claude/settings.local.json: JSON inválido")
        #expect(
            ProjectPermissionsError.unwritable(path: "/p/x", reason: "permiso denegado").message
                == "No se pudo escribir /p/x: permiso denegado")
    }
}

import SmaltiCore
import Testing

@Suite("Screen tool use")
struct ScreenToolUseTests {
    private func verdict(
        _ use: ToolUse, settings: GuardSettings = .standard, hosts: [String] = []
    ) -> GuardVerdict {
        ScreenToolUse.verdict(
            for: use, context: GuardContext(settings: settings, environmentHosts: hosts, texts: .spanish),
            home: "/Users/u")
    }

    private func bash(_ command: String) -> ToolUse {
        ToolUse(tool: "Bash", command: command, cwd: "/p")
    }

    @Test func secretBeatsDestructive() {
        guard case .deny(let denial) = verdict(bash("cat .env && terraform destroy")) else {
            Issue.record("expected deny")
            return
        }
        #expect(denial.kind == .secret(path: ".env"))
        #expect(denial.reason == GuardTexts.spanish.secretReason(["path": ".env"]))
    }

    @Test(arguments: ["Read", "Edit", "MultiEdit", "Write", "NotebookEdit"])
    func fileToolsOnSecretsAreDenied(tool: String) {
        #expect(verdict(ToolUse(tool: tool, filePath: "/p/.env", cwd: "/p")).isDenied)
        #expect(verdict(ToolUse(tool: tool, filePath: "/p/src/a.ts", cwd: "/p")) == .allow)
    }

    @Test func grepOnSecretsIsDenied() {
        #expect(verdict(ToolUse(tool: "Grep", searchPath: "/p/.env", cwd: "/p")).isDenied)
        #expect(verdict(ToolUse(tool: "Grep", glob: ".env*", cwd: "/p")).isDenied)
        #expect(verdict(ToolUse(tool: "Grep", searchPath: "/p", cwd: "/p")) == .allow)
    }

    @Test func relativeBashPathsUseTheDirectory() {
        #expect(verdict(ToolUse(tool: "Bash", command: "cat .ssh/config", cwd: "/Users/u")).isDenied)
        #expect(verdict(ToolUse(tool: "Bash", command: "cat .ssh/config", cwd: "/tmp")) == .allow)
    }

    @Test func innocentBashAllowed() {
        #expect(verdict(bash("git status")) == .allow)
    }

    @Test func incidentsAsk() {
        let replit = verdict(bash(IncidentCommands.replit), hosts: [IncidentCommands.replitEnvironmentHost])

        #expect(replit.subject?.summary(.spanish) == "npm run db:push contra PROD")
        #expect(verdict(bash(IncidentCommands.dataTalks)).subject?.summary(.spanish) == "terraform destroy contra PROD")
        #expect(
            verdict(bash(IncidentCommands.pocketOS)).subject?.summary(.spanish) == "API de Railway (POST) contra PROD")
    }

    @Test func oversizedCommandAsks() {
        let long = "echo " + String(repeating: "a", count: ScreenToolUse.maximumInputBytes)

        #expect(verdict(bash(long)).subject?.findings.map(\.rule) == ["comando demasiado largo para revisarlo"])
    }

    @Test func commandAtTheLimitIsScreenedNormally() {
        let atLimit = "echo " + String(repeating: "a", count: ScreenToolUse.maximumInputBytes - 5)

        #expect(verdict(bash(atLimit)) == .allow)
    }

    @Test func nonProductionURLAllowedButDestructiveStillAsks() {
        var settings = GuardSettings.standard
        settings.nonProductionHosts = ["*.qa.example.com"]

        #expect(verdict(bash("psql postgres://u@db.qa.example.com/x -c \"select 1\""), settings: settings) == .allow)
        let reset = verdict(bash("prisma migrate reset"), settings: settings, hosts: ["db.qa.example.com"])
        #expect(reset.subject?.environment.kind == .nonProduction)
    }

    @Test func subjectIsRedacted() {
        let subject = verdict(bash("psql postgres://u:p4ss@db.x.com/x -c 'drop table a'")).subject

        #expect(subject?.command == "psql postgres://u:•••@db.x.com/x -c 'drop table a'")
    }

    @Test func mostSevereEnvironmentWins() {
        let subject = verdict(bash("supabase db reset --local && terraform destroy")).subject

        #expect(subject?.environment.kind == .production)
        #expect(subject?.summary(.spanish) == "terraform destroy contra PROD")
        #expect(subject?.findings.count == 2)
    }

    @Test func unknownToolAllowed() {
        #expect(verdict(ToolUse(tool: "WebFetch")) == .allow)
    }

    @Test func reasonsAreTheSpecTexts() {
        #expect(
            GuardTexts.spanish.unreachable
                == "Smalti no respondió (app cerrada o socket caído): el comando queda bloqueado.")
        #expect(
            GuardReasons.expired(minutes: 10, texts: .spanish) == "Nadie aprobó el comando en Smalti en 10 minutos.")
        #expect(
            GuardTexts.spanish.outdatedIntegration
                == "Este comando necesita la aprobación de Smalti y la integración instalada es antigua: actualízala desde ⌘K."
        )
    }

    @Test func rejectedReasonNamesRuleAndEnvironment() {
        let finding = GuardFinding(rule: "terraform destroy", environment: .undetermined)
        let subject = ApprovalSubject(command: "terraform destroy", findings: [finding])

        #expect(
            GuardReasons.rejected(subject, texts: .spanish)
                == "El usuario rechazó en Smalti este comando (terraform destroy, contra PROD). No lo reintentes ni busques otra vía; pregunta qué hacer."
        )
    }
}

extension GuardVerdict {
    var isDenied: Bool {
        if case .deny = self { return true }
        return false
    }

    var subject: ApprovalSubject? {
        if case .ask(let subject) = self { return subject }
        return nil
    }
}

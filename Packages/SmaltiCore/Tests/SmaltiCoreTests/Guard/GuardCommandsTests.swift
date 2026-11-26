import Foundation
import SmaltiCore
import Testing

/// F7.5: approval and secret commands in the keymap, ⌘K, the menu and the help.
@Suite("Guard commands")
struct GuardCommandsTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func set() throws -> WorkspaceSet {
        let root = try WorkingDirectory(path: "/tmp/project")
        return WorkspaceSet(
            first: Workspace.empty(name: "rizaria", rootDirectory: root, layout: DwindleLayout())
                .adding(Pane(id: PaneID(), workingDirectory: root)))
    }

    private func approval(_ command: String, rule: String, pane: PaneID) -> PendingApproval {
        PendingApproval(
            id: UUID(), pane: pane,
            subject: ApprovalSubject(
                command: command, findings: [GuardFinding(rule: rule, environment: .undetermined)]),
            since: t0, deadline: t0)
    }

    private func commands(_ state: CatalogState) -> [Command] {
        CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard, texts: .spanish)
    }

    @Test func approvalShortcutsAreBound() throws {
        #expect(Keymap.standard.chord(for: .guardApprove) == (try KeyChord.parse("cmd+shift+enter")))
        #expect(Keymap.standard.chord(for: .guardReject) == (try KeyChord.parse("cmd+shift+escape")))
        #expect(CommandID.allStandard.contains(.guardApprove))
        #expect(CommandID.allStandard.contains(.guardReject))
    }

    @Test func paletteListsPendingApprovals() throws {
        let set = try set()
        let pane = set.active.panes[0].id
        let first = approval("terraform destroy -auto-approve", rule: "terraform destroy", pane: pane)
        let second = approval(String(repeating: "x", count: 60), rule: "psql con DROP", pane: pane)
        let state = CatalogState(
            workspaces: set,
            pendingApprovals: [
                ApprovalEntry(approval: first, workspace: "rizaria"),
                ApprovalEntry(approval: second, workspace: "rizaria"),
            ])

        let listed = commands(state).filter { $0.group == .approvals }

        #expect(
            listed.map(\.title) == [
                "Aprobar “terraform destroy -auto-approve” en rizaria",
                "Rechazar “terraform destroy -auto-approve” en rizaria",
                "Aprobar “\(String(repeating: "x", count: 40))…” en rizaria",
                "Rechazar “\(String(repeating: "x", count: 40))…” en rizaria",
            ])
        #expect(listed[0].id == .guardApprove(id: first.id))
        #expect(listed[1].id == .guardReject(id: first.id))
        #expect(listed[0].subtitle == "terraform destroy contra PROD · no determinado")
    }

    @Test func approvalsComeFirst() throws {
        let set = try set()
        let entry = ApprovalEntry(
            approval: approval("terraform destroy", rule: "terraform destroy", pane: set.active.panes[0].id),
            workspace: "rizaria")

        #expect(commands(CatalogState(workspaces: set, pendingApprovals: [entry])).first?.group == .approvals)
    }

    @Test func noApprovalsNoEntries() throws {
        #expect(!commands(CatalogState(workspaces: try set())).contains { $0.group == .approvals })
    }

    @Test func approvalCommandIDsRoundTrip() {
        let id = UUID()

        #expect(CommandID.guardApprove(id: id).approval == .approve(id))
        #expect(CommandID.guardReject(id: id).approval == .reject(id))
        #expect(CommandID.guardApprove.approval == nil)
        #expect(CommandID(rawValue: "guard.approve.nope").approval == nil)
    }

    @Test func paletteOffersProtectOrUnprotect() throws {
        let set = try set()
        let unprotected = CatalogState(
            workspaces: set, secretsProject: SecretsProjectState(name: "rizaria", isProtected: false))
        let protected = CatalogState(
            workspaces: set, secretsProject: SecretsProjectState(name: "rizaria", isProtected: true))

        #expect(commands(unprotected).first { $0.id == .secretsProtect }?.title == "Proteger secretos en “rizaria”")
        #expect(!commands(unprotected).contains { $0.id == .secretsUnprotect })
        #expect(
            commands(protected).first { $0.id == .secretsUnprotect }?.title
                == "Quitar protección de secretos en “rizaria”")
        #expect(!commands(CatalogState(workspaces: set)).contains { $0.id == .secretsProtect })
    }

    @Test func outdatedOffersUpdate() throws {
        let state = CatalogState(workspaces: try set(), integrations: [.claudePlugin: .outdated])

        let update = commands(state).first { $0.id == .claudeIntegrationInstall }

        #expect(update?.title == "Actualizar integración con Claude Code")
        #expect(!commands(state).contains { $0.id == .claudeIntegrationUninstall })
    }

    @Test func helpCoversTheNewCommands() {
        let covered = Set(HelpCatalog.sections(keymap: .standard, texts: .spanish).flatMap(\.entries).flatMap(\.covers))

        #expect(
            [CommandID.guardApprove, .guardReject, .secretsProtect, .secretsUnprotect].allSatisfy(covered.contains))
    }
}

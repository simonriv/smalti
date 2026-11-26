import Foundation
import SmaltiCore
import Testing

@Suite("Project card (F8.5)")
struct ProjectCardTests {
    private let root = "/Users/ana/dev/rizaria"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    // Safe: "rizaria" has none of what `LayoutName` rejects.
    private let name = try! LayoutName("rizaria")

    private var context: ProjectCard.OpeningContext {
        .init(
            home: "/Users/ana", now: now, texts: .spanish, session: .spanish,
            layoutNames: CommandTexts.spanish.layoutNames)
    }

    private func confirmation(
        approved: ProjectApproval?, current: [PlannedCommand], panes: Int = 3, layout: String = "dwindle"
    ) -> ProjectConfirmation {
        let snapshot = WorkspaceSnapshot(
            name: "rizaria", rootDirectory: root, layout: layout, tree: nil, focusedIndex: nil, panes: [], project: root
        )
        let prepared = PreparedProject(root: root, name: name, snapshot: snapshot, fingerprint: "f", commands: current)
        return ProjectConfirmation(
            prepared: prepared,
            changes: ProjectChanges(approved: approved, current: current, paneCount: panes, layout: layout),
            approvedAt: approved?.approvedAt)
    }

    private func approval(_ commands: [PlannedCommand], panes: Int = 3, layout: String = "dwindle") -> ProjectApproval {
        ProjectApproval(
            fingerprint: "old", approvedAt: Date(timeIntervalSince1970: 1_799_740_000), commands: commands,
            paneCount: panes, layout: layout)
    }

    @Test func firstTime() {
        let card = ProjectCard.opening(
            confirmation(approved: nil, current: [PlannedCommand(command: "npm run dev", place: "web")]),
            context: context)

        #expect(card.title == "¿Abrir el proyecto “rizaria”?")
        #expect(card.body == "Es la primera vez que abres este layout. Al abrirlo ejecutará:")
        #expect(card.lines == [ProjectCardLine(sign: "›", command: "npm run dev", place: "web", kind: .same)])
        #expect(card.extra == nil)
        #expect(card.note.hasPrefix("Viene de ~/dev/rizaria/.smalti/layout.json."))
        #expect(card.confirmLabel == "abrir y ejecutar")
        #expect(card.cancelLabel == "cancelar")
    }

    @Test func changedShowsTheDiffAndWhen() {
        let card = ProjectCard.opening(
            confirmation(
                approved: approval([PlannedCommand(command: "nvim +42 a.ts", place: nil)], panes: 3),
                current: [PlannedCommand(command: "docker compose up db", place: nil)], panes: 4, layout: "columns"),
            context: context)

        #expect(card.body.hasPrefix("El layout cambió desde que lo aprobaste ("))
        #expect(card.lines.map(\.sign) == ["+", "−"])
        #expect(card.lines.map(\.kind) == [.added, .removed])
        #expect(card.extra == "También cambió la disposición: 4 paneles en Columnas (antes 3 en Dwindle).")
    }

    @Test func onlyDetailsChanged() {
        let commands = [PlannedCommand(command: "ls", place: nil)]
        let card = ProjectCard.opening(confirmation(approved: approval(commands), current: commands), context: context)

        #expect(card.extra == "Los comandos son los mismos; cambiaron otros detalles del archivo.")
    }

    @Test func replacing() {
        let pending = PendingProjectSave(
            root: root, name: name,
            layout: SharedLayout(
                smaltiLayout: 1, name: "rizaria", root: ".", layout: "dwindle", focused: 0, tree: nil,
                panes: [SharedPane(directory: ".")]),
            commands: [])

        let card = ProjectCard.replacing(pending, context: .init(home: "/Users/ana", texts: .english))

        #expect(card.title == "Save Project Layout")
        #expect(card.body == "~/dev/rizaria already has .smalti/layout.json. Replace it with this workspace:")
        #expect(card.lines == [ProjectCardLine(sign: "›", command: "shell", place: nil, kind: .same)])
        #expect(card.confirmLabel == "replace")
    }

    @Test func saveErrorsSayWhy() {
        #expect(
            ProjectSaveError.layout(.outsideProject(pane: 2, path: "~/notes")).message(.spanish, layout: .spanish)
                == "el panel 2 está fuera del proyecto: ~/notes")
        #expect(
            ProjectSaveError.file(.missing(root: "/r")).message(.english, layout: .english)
                == "/r no longer has .smalti/layout.json")
    }
}

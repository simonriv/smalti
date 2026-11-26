import Foundation
import SmaltiCore
import Testing

@Suite("Project commands (F8.5)")
struct ProjectPaletteCommandsTests {
    private let root = "/Users/ana/dev/rizaria"

    private func set() throws -> WorkspaceSet {
        WorkspaceSet(
            first: .empty(name: "tmp", rootDirectory: try WorkingDirectory(path: "/tmp"), layout: DwindleLayout()))
    }

    private func listing(
        _ root: String, _ name: String, focused: Bool = false, openIn: OpenProjectWorkspace? = nil
    ) -> ProjectListing {
        ProjectListing(root: root, name: name, lastOpened: nil, isInFocusedPane: focused, openIn: openIn)
    }

    private func commands(_ projects: CatalogProjects?, texts: CommandTexts = .spanish) throws -> [Command] {
        var state = CatalogState(workspaces: try set())
        state.projects = projects
        return CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard, texts: texts)
    }

    @Test func eachProjectIsAnOpenRow() throws {
        let other = OpenProjectWorkspace(id: WorkspaceID(), project: "/p/acme", isInThisWindow: true, number: 2)
        let far = OpenProjectWorkspace(id: WorkspaceID(), project: "/p/far", isInThisWindow: false, number: 1)
        let projects = CatalogProjects(
            listings: [
                listing(root, "rizaria", focused: true), listing("/p/acme", "acme", openIn: other),
                listing("/p/far", "far", openIn: far), listing("/p/notes", "notes"),
            ], home: "/Users/ana", saveRoot: nil)

        let rows = try commands(projects).filter { $0.group == .projects }

        #expect(
            rows.map(\.title) == [
                "Abrir proyecto “rizaria”", "Abrir proyecto “acme”", "Abrir proyecto “far”", "Abrir proyecto “notes”",
                "Proyectos recientes…",
            ])
        #expect(
            rows.map(\.subtitle) == [
                "~/dev/rizaria · en este panel", "/p/acme · abierto en el workspace 2",
                "/p/far · abierto en otra ventana",
                "/p/notes", nil,
            ])
        #expect(rows[0].id == .projectOpen(root: root))
        #expect(rows[0].icon == .projectFolder)
        #expect(rows.allSatisfy { !$0.isCurrent }, "a project row never says «actual»")
        #expect(rows[4].shortcut?.display == "⌘O")
    }

    @Test func englishRows() throws {
        let projects = CatalogProjects(listings: [listing(root, "rizaria")], home: "/Users/ana", saveRoot: root)

        let titles = try commands(projects, texts: .english).map(\.title)

        #expect(titles.contains("Open Project “rizaria”"))
        #expect(titles.contains("Recent Projects…"))
        #expect(titles.contains("Save Project Layout"))
    }

    @Test func projectsComeRightAfterApprovalsAndBeforeTiling() throws {
        let projects = CatalogProjects(listings: [listing(root, "rizaria")], home: "/Users/ana", saveRoot: nil)

        let groups = try commands(projects).map(\.group)

        #expect(groups.first == .projects)
        #expect(groups.firstIndex(of: .tiling).map { $0 > groups.lastIndex(of: .projects) ?? 0 } == true)
    }

    @Test func saveSaysWhereItWrites() throws {
        let projects = CatalogProjects(listings: [], home: "/Users/ana", saveRoot: root)

        let save = try commands(projects).first { $0.id == .projectSave }

        #expect(save?.title == "Guardar layout del proyecto")
        #expect(save?.subtitle == "escribe .smalti/layout.json en ~/dev/rizaria")
        #expect(save?.group == .workspaces)
    }

    @Test func withoutAPaneThereIsNoSaveButRecentsStay() throws {
        let ids = try commands(CatalogProjects(listings: [], home: "/Users/ana", saveRoot: nil)).map(\.id)

        #expect(!ids.contains(.projectSave))
        #expect(ids.contains(.projectRecent))
        #expect(try commands(nil).map(\.id).contains(.projectRecent))
    }

    @Test func openIdsCarryTheRoot() {
        #expect(CommandID.projectOpen(root: root).projectRoot == root)
        #expect(CommandID.projectOpen(root: "/a b/c:d").projectRoot == "/a b/c:d")
        #expect(CommandID.projectRecent.projectRoot == nil)
        #expect(CommandID.layoutImport.projectRoot == nil)
    }

    @Test func recentIsCommandO() throws {
        #expect(Keymap.standard.chord(for: .projectRecent)?.display == "⌘O")
        #expect(Keymap.standard.chord(for: .projectRecent)?.usesOptionAlone == false)
        #expect(Keymap.standard.chord(for: .projectSave) == nil)
        #expect(CommandID.allStandard.contains(.projectRecent))
        #expect(CommandID.allStandard.contains(.projectSave))
    }

    @Test func helpListsBoth() {
        let entries = HelpCatalog.sections(keymap: .standard, texts: .english).flatMap(\.entries)

        #expect(entries.contains { $0.command == .projectRecent && $0.title == "Recent Projects…" })
        #expect(entries.contains { $0.command == .projectSave && $0.title == "Save Project Layout" })
    }

    @Test func fileMenuHasBoth() throws {
        let bar = MenuModel.bar(
            keymap: .standard, commands: [], state: MenuState(workspaces: try set(), checked: []), texts: .spanish)
        let file = bar.menus.first { $0.id == .file }?.items.compactMap(\.command) ?? []

        #expect(file.contains(.projectRecent))
        #expect(file.contains(.projectSave))
    }
}

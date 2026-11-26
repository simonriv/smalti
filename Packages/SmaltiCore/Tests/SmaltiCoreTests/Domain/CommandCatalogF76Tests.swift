import SmaltiCore
import Testing

/// F7.6: updates, documentation and support in ⌘K, the menus and the help.
@Suite("CommandCatalog · F7.6")
struct CommandCatalogF76Tests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
    }

    private func state(_ updates: UpdatesAvailability) -> CatalogState {
        var state = CatalogState(
            workspaces: WorkspaceSet(first: Workspace.empty(name: "p", rootDirectory: root, layout: DwindleLayout())))
        state.updates = updates
        return state
    }

    private func commands(_ updates: UpdatesAvailability) -> [Command] {
        CommandCatalog.commands(for: state(updates), keymap: .standard, layouts: .standard, texts: .spanish)
    }

    private func title(_ id: CommandID, _ updates: UpdatesAvailability) -> String? {
        commands(updates).first { $0.id == id }?.title
    }

    private func bar(_ updates: UpdatesAvailability) -> MenuBar {
        MenuModel.bar(
            keymap: .standard, commands: commands(updates),
            state: MenuState(workspaces: state(updates).workspaces, checked: []), texts: .spanish)
    }

    private func items(_ menu: MenuID, _ updates: UpdatesAvailability) -> [CommandID?] {
        (bar(updates).menus.first { $0.id == menu }?.items ?? []).map { $0.isSeparator ? nil : $0.command }
    }

    @Test func checkIsOfferedWhenUpdatesAreAvailable() {
        #expect(title(.updatesCheck, .available(isAutomatic: true)) == "Buscar actualizaciones…")
    }

    @Test func automaticOnOffersToTurnItOff() {
        #expect(title(.updatesAutomatic, .available(isAutomatic: true)) == "Desactivar actualizaciones automáticas")
    }

    @Test func automaticOffOffersToTurnItOn() {
        #expect(title(.updatesAutomatic, .available(isAutomatic: false)) == "Activar actualizaciones automáticas")
    }

    @Test func withoutUpdatesNeitherCommandIsOffered() {
        let ids = Set(commands(.unavailable).map(\.id))

        #expect(!ids.contains(.updatesCheck))
        #expect(!ids.contains(.updatesAutomatic))
    }

    @Test(arguments: [UpdatesAvailability.unavailable, .available(isAutomatic: true)])
    func documentationAndSupportAreAlwaysOffered(_ updates: UpdatesAvailability) {
        #expect(title(.helpDocs, updates) == "Abrir la documentación")
        #expect(title(.appSupport, updates) == "Apoyar Smalti…")
    }

    @Test func updateCommandsAreInTheHelpGroup() {
        let groups = Set(
            commands(.available(isAutomatic: true)).filter {
                [CommandID.updatesCheck, .updatesAutomatic, .helpDocs, .appSupport].contains($0.id)
            }.map(\.group))

        #expect(groups == [.help])
    }

    @Test func appMenuListsUpdatesUnderAbout() {
        let app = items(.app, .available(isAutomatic: true))

        #expect(Array(app.prefix(4)) == [.appAbout, .updatesCheck, .updatesAutomatic, nil])
    }

    @Test func appMenuTitlesFollowTheAutomaticState() {
        let off = bar(.available(isAutomatic: false)).menus.first { $0.id == .app }?.items
            .first { $0.command == .updatesAutomatic }

        #expect(off?.title == "Activar actualizaciones automáticas")
    }

    @Test func appMenuWithoutUpdatesHasNoUpdateItems() {
        let app = items(.app, .unavailable)

        #expect(Array(app.prefix(2)) == [.appAbout, nil])
    }

    @Test func helpMenuListsDocumentationAndSupport() {
        #expect(
            items(.help, .unavailable)
                == [
                    .helpShow, .helpWelcome, .helpDocs, .helpPrivacy, nil, .feedbackReport, .logsShow, nil, .appSupport,
                ])
    }

    @Test(arguments: [
        ("Buscar actualizaciones…", CommandID.updatesCheck), ("Abrir la documentación", .helpDocs),
        ("Apoyar Smalti…", .appSupport),
    ])
    func helpListsTheNewCommands(_ title: String, _ id: CommandID) {
        let entry = HelpCatalog.sections(keymap: .standard, texts: .spanish).flatMap(\.entries).first {
            $0.title == title
        }

        #expect(entry?.command == id)
    }

    @Test func helpNamesTheAutomaticToggle() {
        let titles = HelpCatalog.sections(keymap: .standard, texts: .spanish).flatMap(\.entries).map(\.title)

        #expect(titles.contains("Activar o desactivar actualizaciones automáticas"))
    }

    @Test func idsAreStable() {
        #expect(CommandID.updatesCheck.rawValue == "updates.check")
        #expect(CommandID.updatesAutomatic.rawValue == "updates.automatic")
        #expect(CommandID.helpDocs.rawValue == "help.docs")
        #expect(CommandID.appSupport.rawValue == "app.support")
    }

    @Test func newIDsCanBeBoundInTheConfig() {
        let all = Set(CommandID.allStandard)

        #expect([CommandID.updatesCheck, .updatesAutomatic, .helpDocs, .appSupport].allSatisfy(all.contains))
    }
}

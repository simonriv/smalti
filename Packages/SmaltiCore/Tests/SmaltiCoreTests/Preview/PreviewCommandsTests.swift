import SmaltiCore
import Testing

/// Spec F5.5: ⌘Y opens the previewed image in Quick Look, from ⌘K, the Ver menu and the help.
@Suite("Preview commands")
struct PreviewCommandsTests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
    }

    private var set: WorkspaceSet {
        WorkspaceSet(
            first: Workspace.empty(name: "p", rootDirectory: root, layout: DwindleLayout())
                .adding(Pane(id: PaneID(), workingDirectory: root)))
    }

    private var commands: [Command] {
        CommandCatalog.commands(for: set, keymap: .standard, layouts: .standard)
    }

    @Test func quickLookIdIsStandard() {
        #expect(CommandID.previewQuickLook.rawValue == "preview.quickLook")
        #expect(CommandID.allStandard.contains(.previewQuickLook))
    }

    @Test func quickLookIsCommandY() throws {
        #expect(Keymap.standard.command(for: try KeyChord.parse("cmd+y")) == .previewQuickLook)
        #expect(Keymap.standard.chords(for: .previewQuickLook) == [try KeyChord.parse("cmd+y")])
    }

    @Test func paletteListsQuickLookWithItsTitleAndShortcut() throws {
        let command = try #require(commands.first { $0.id == .previewQuickLook })

        #expect(command.title == "Abrir en Quick Look")
        #expect(command.group == .terminal)
        #expect(command.shortcut == (try KeyChord.parse("cmd+y")))
    }

    @Test func viewMenuHasQuickLook() throws {
        let bar = MenuModel.bar(
            keymap: .standard, commands: commands,
            state: MenuState(workspaces: set, checked: [], context: .unrestricted))
        let view = try #require(bar.menus.first { $0.title == "Ver" })

        #expect(view.items.contains { $0.title == "Abrir en Quick Look" })
    }

    @Test func helpListsQuickLookWithItsShortcut() throws {
        let entries = HelpCatalog.sections(keymap: .standard).flatMap(\.entries)
        let entry = try #require(entries.first { $0.command == .previewQuickLook })

        #expect(entry.title == "Abrir en Quick Look")
        #expect(entry.keys == "⌘Y")
    }

    @Test func keymapsBindingTheSameChordToOtherCommandsDiffer() throws {
        let y = try KeyChord.parse("cmd+y")

        let first = try Keymap.standard.overriding([y: .themeNext])
        let second = try Keymap.standard.overriding([y: .ansiReset])

        #expect(first != second)
    }

    @Test func previewDefaultsToHover() {
        #expect(PreviewSettings.standard.hover)
        #expect(SmaltiConfig.defaults.preview == .standard)
    }
}

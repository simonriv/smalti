import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Share layout")
struct ShareLayoutTests {
    private let layouts = InMemoryNamedLayouts()
    private let files = InMemoryLayoutFiles()
    private let home = "/Users/s"
    private let root = "/Users/s/dev/solen"
    private let file = URL(filePath: "/tmp/share/solen-dev.smalti-layout.json")

    private func snapshot(_ panes: [PaneSnapshot]) -> WorkspaceSnapshot {
        let tree: SnapshotTree? =
            panes.count == 1
            ? .leaf(index: 0)
            : panes.indices.dropFirst().reduce(SnapshotTree.leaf(index: 0)) {
                .split(axis: .sideBySide, ratio: 0.5, first: $0, second: .leaf(index: $1))
            }
        return WorkspaceSnapshot(
            name: "solen", rootDirectory: root, layout: "dwindle", tree: tree, focusedIndex: 0, panes: panes)
    }

    private func pane(
        _ directory: String? = nil, relaunch: [String]? = nil, agent: AgentSnapshot? = nil,
        editor: EditorPosition? = nil
    ) -> PaneSnapshot {
        PaneSnapshot(
            id: UUID(), workingDirectory: directory ?? root, title: nil, processName: nil, scrollbackLines: 0,
            commandCount: 0, relaunch: relaunch.map(RelaunchCommand.init(arguments:)), agent: agent, editor: editor)
    }

    private func importer(existing: Set<String> = []) -> ImportLayout {
        ImportLayout(
            layouts: layouts, files: files, harnesses: HarnessRegistry([FakeHarnessAdapter()]), home: home,
            directoryExists: { existing.contains($0) })
    }

    private func shared(_ panes: [PaneSnapshot], name: String = "solen-dev") throws -> SharedLayout {
        SharedLayout(exporting: snapshot(panes), named: try LayoutName(name), home: home)
    }

    // MARK: Export

    @Test func exportWritesSavedLayoutToFile() throws {
        let name = try LayoutName("solen-dev")
        let saved = snapshot([pane(relaunch: ["pnpm", "dev"])])
        try layouts.save(saved, as: name)

        try ExportLayout(layouts: layouts, files: files, home: home).execute(name, to: file)

        #expect(files.files[file] == SharedLayout(exporting: saved, named: name, home: home))
    }

    @Test func exportOfMissingLayoutThrowsNotFound() throws {
        #expect(throws: LayoutShareError.archive(.notFound(name: "nada"))) {
            try ExportLayout(layouts: layouts, files: files, home: home).execute(try LayoutName("nada"), to: file)
        }
    }

    @Test func exportWriteFailureIsTyped() throws {
        let name = try LayoutName("solen-dev")
        try layouts.save(snapshot([pane()]), as: name)
        files.failing.insert(file)

        #expect(
            throws: LayoutShareError.file(.unwritable(path: file.path(percentEncoded: false), reason: "fake failure"))
        ) {
            try ExportLayout(layouts: layouts, files: files, home: home).execute(name, to: file)
        }
    }

    // MARK: Preview

    @Test func previewListsEveryCommand() throws {
        let agent = AgentSnapshot(harness: .claude, sessionID: "s", title: nil, lastState: nil)
        files.files[file] = try shared([
            pane(relaunch: ["pnpm", "dev"]), pane(agent: agent),
            pane(editor: EditorPosition(file: root + "/src/a.ts", line: 42)), pane(),
        ])

        let preview = try importer(existing: [root]).preview(file)

        #expect(
            preview.commands.map { $0.text(.spanish) } == ["pnpm dev", "fake --continue", "nvim +42 \(root)/src/a.ts"])
    }

    @Test func previewOfShellsOnlyHasNoCommands() throws {
        files.files[file] = try shared([pane(), pane()])

        #expect(try importer(existing: [root]).preview(file).commands.isEmpty)
    }

    @Test func previewReportsRootAndWhetherItExists() throws {
        files.files[file] = try shared([pane()])

        let present = try importer(existing: [root]).preview(file)
        let missing = try importer().preview(file)

        #expect(present.root == root)
        #expect(present.isRootPresent)
        #expect(!missing.isRootPresent)
    }

    @Test func previewPropagatesValidationError() throws {
        var bad = try shared([pane()])
        bad.smaltiLayout = 7
        files.files[file] = bad

        #expect(throws: LayoutShareError.file(.invalid(.newerFormat(7)))) { try importer().preview(file) }
    }

    @Test func previewPropagatesUnreadableFile() {
        #expect(
            throws: LayoutShareError.file(.unreadable(path: file.path(percentEncoded: false), reason: "no such file"))
        ) {
            try importer().preview(file)
        }
    }

    @Test func previewCarriesWarnings() throws {
        var odd = try shared([pane()])
        odd.layout = "spiral"
        files.files[file] = odd

        #expect(try importer().preview(file).warnings == [.unknownLayout("spiral")])
    }

    // MARK: Confirm

    @Test func confirmSavesUnderInternalName() throws {
        files.files[file] = try shared([pane(relaunch: ["pnpm", "dev"])])
        let preview = try importer(existing: [root]).preview(file)

        let saved = try importer(existing: [root]).confirm(preview, root: preview.root)

        #expect(saved.rawValue == "solen-dev")
        #expect(try layouts.layout(named: saved).panes[0].relaunch == RelaunchCommand(arguments: ["pnpm", "dev"]))
    }

    @Test func importUsesInternalName() throws {
        let copy = URL(filePath: "/tmp/share/copia.smalti-layout.json")
        files.files[copy] = try shared([pane()], name: "equipo")

        let saved = try importer().confirm(try importer().preview(copy), root: root)

        #expect(saved.rawValue == "equipo")
    }

    @Test func confirmPicksFreeName() throws {
        try layouts.save(snapshot([pane()]), as: try LayoutName("solen-dev"))
        try layouts.save(snapshot([pane()]), as: try LayoutName("Solen-Dev 2"))
        files.files[file] = try shared([pane()])

        let saved = try importer().confirm(try importer().preview(file), root: root)

        #expect(saved.rawValue == "solen-dev 3")
        #expect(layouts.names().count == 3)
    }

    @Test func freeNameStaysWithinTheLengthLimit() throws {
        let long = String(repeating: "a", count: LayoutName.maximumLength)
        try layouts.save(snapshot([pane()]), as: try LayoutName(long))
        files.files[file] = try shared([pane()], name: long)

        let saved = try importer().confirm(try importer().preview(file), root: root)

        #expect(saved.rawValue.count == LayoutName.maximumLength)
        #expect(saved.rawValue.hasSuffix(" 2"))
    }

    @Test func confirmUsesChosenRoot() throws {
        files.files[file] = try shared([pane(), pane(root + "/api")])
        let preview = try importer().preview(file)

        let saved = try importer().confirm(preview, root: "/Volumes/work/solen")

        let layout = try layouts.layout(named: saved)
        #expect(layout.rootDirectory == "/Volumes/work/solen")
        #expect(layout.panes.map(\.workingDirectory) == ["/Volumes/work/solen", "/Volumes/work/solen/api"])
    }

    // MARK: Texts

    @Test func confirmationTitle() throws {
        #expect(
            ImportTexts.confirmationTitle(try LayoutName("solen-dev"), texts: .spanish)
                == "¿Importar el layout “solen-dev”?")
    }

    @Test func confirmationBodyListsCommands() throws {
        files.files[file] = try shared([pane(relaunch: ["pnpm", "dev"]), pane(relaunch: ["make"])])

        let body = ImportTexts.confirmationBody(try importer().preview(file), texts: .spanish)

        #expect(body == "Al abrirlo ejecutará: pnpm dev · make")
    }

    @Test func confirmationBodyForShellsOnly() throws {
        files.files[file] = try shared([pane()])

        #expect(
            ImportTexts.confirmationBody(try importer().preview(file), texts: .spanish)
                == "Al abrirlo solo abrirá shells.")
    }

    @Test func confirmationBodyAddsWarnings() throws {
        var odd = try shared([pane(), pane()])
        odd.layout = "spiral"
        odd.panes[1] = SharedPane(directory: ".", harness: HarnessID(rawValue: "gemini"))
        files.files[file] = odd

        let body = ImportTexts.confirmationBody(try importer().preview(file), texts: .spanish)

        #expect(
            body == """
                Al abrirlo solo abrirá shells.
                El panel 2 usa un harness desconocido (gemini): se abrirá como shell.
                Layout desconocido (spiral): se usará Dwindle.
                """)
    }

    @Test func folderPrompt() throws {
        #expect(
            ImportTexts.folderPrompt(try LayoutName("solen-dev"), texts: .spanish)
                == "Elige la carpeta de “solen-dev” en este Mac")
    }

    @Test func errorMessagesReachTheStatusBar() {
        #expect(LayoutShareError.file(.invalid(.paneCount(10))).message(.spanish) == "tiene 10 paneles; el máximo es 9")
        #expect(LayoutShareError.archive(.notFound(name: "x")).message(.spanish).contains("x"))
    }

    /// F7.6: a layout saved by a newer Smalti says so instead of "not found".
    @Test func newerLayoutMessageNamesFileAndVersion() {
        #expect(
            LayoutShareError.archive(.newerFormat(file: "solen.json", version: 2)).message(.spanish)
                == "solen.json lo guardó una versión más nueva de Smalti (formato 2)")
        #expect(
            SessionArchiveError.newerFormat(file: "session.json", version: 3).summary(.spanish)
                == "session.json: guardado por una versión más nueva de Smalti (formato 3)")
    }

    // MARK: Review 1

    @Test func previewMatchesWhatRestoreRuns() throws {
        let agent = AgentSnapshot(harness: .claude, sessionID: "s", title: nil, lastState: nil)
        let saved = snapshot([pane(agent: agent), pane(editor: EditorPosition(file: root + "/src/a.ts", line: 42))])
        files.files[file] = try shared(saved.panes)

        let preview = try importer(existing: [root]).preview(file)

        #expect(preview.commands.map { $0.text(.spanish) } == ["fake --continue", "nvim +42 \(root)/src/a.ts"])
    }

    @Test func freeNameIgnoresCase() throws {
        try layouts.save(snapshot([pane()]), as: try LayoutName("Solen-dev"))
        files.files[file] = try shared([pane()])

        let saved = try importer().confirm(try importer().preview(file), root: root)

        #expect(saved.rawValue == "solen-dev 2")
    }

    // MARK: Review 2

    @Test func previewWithChosenRootShowsItsPaths() throws {
        files.files[file] = try shared([pane(editor: EditorPosition(file: root + "/src/a.ts", line: 42))])

        let preview = try importer().preview(file, root: "/Volumes/work/solen")

        #expect(preview.root == "/Volumes/work/solen")
        #expect(preview.commands.map { $0.text(.spanish) } == ["nvim +42 /Volumes/work/solen/src/a.ts"])
        #expect(!preview.isRootPresent)
    }

    @Test func previewWithChosenExistingRootIsPresent() throws {
        files.files[file] = try shared([pane()])

        #expect(
            try importer(existing: ["/Volumes/work/solen"]).preview(file, root: "/Volumes/work/solen").isRootPresent)
    }

    // MARK: Final review

    @Test func previewNamesTheFolderOfCommandsOutsideTheRoot() throws {
        let agent = AgentSnapshot(harness: .claude, sessionID: "s", title: nil, lastState: nil)
        files.files[file] = try shared([
            pane(relaunch: ["pnpm", "dev"]), pane(root + "/api", relaunch: ["make"]),
            pane(home + "/.ssh", agent: agent),
        ])

        let preview = try importer(existing: [root]).preview(file)

        #expect(preview.commands.map { $0.text(.spanish) } == ["pnpm dev", "make en api", "fake --continue en ~/.ssh"])
        #expect(preview.commands.map { $0.text(.english) } == ["pnpm dev", "make in api", "fake --continue in ~/.ssh"])
    }
}

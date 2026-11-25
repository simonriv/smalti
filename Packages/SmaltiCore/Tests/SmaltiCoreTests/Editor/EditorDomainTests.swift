import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Editor target")
struct EditorTargetTests {
    @Test func parsesPathLineColumn() {
        #expect(EditorTarget.parse("/w/a.ts", cwd: "/x") == EditorTarget(path: "/w/a.ts", line: nil, column: nil))
        #expect(EditorTarget.parse("/w/a.ts:12", cwd: "/x") == EditorTarget(path: "/w/a.ts", line: 12, column: nil))
        #expect(EditorTarget.parse("/w/a.ts:12:3", cwd: "/x") == EditorTarget(path: "/w/a.ts", line: 12, column: 3))
        #expect(EditorTarget.parse("/w/a.ts:12:", cwd: "/x") == EditorTarget(path: "/w/a.ts", line: 12, column: nil))
    }

    @Test func relativeResolvesAgainstCwd() {
        #expect(
            EditorTarget.parse("src/a.ts:4", cwd: "/w/solen")
                == EditorTarget(
                    path: "/w/solen/src/a.ts", line: 4,
                    column: nil))
        #expect(EditorTarget.parse("./a.ts", cwd: "/w/") == EditorTarget(path: "/w/a.ts", line: nil, column: nil))
        #expect(EditorTarget.parse("~/a.ts", cwd: "/w", home: "/Users/s")?.path == "/Users/s/a.ts")
        #expect(EditorTarget.parse("~", cwd: "/w", home: "/Users/s")?.path == "/Users/s")
        #expect(EditorTarget.parse("src/a.ts", cwd: "/w", home: "/Users/s")?.path == "/w/src/a.ts")
    }

    @Test func rejectsUrlsAndEmpty() {
        #expect(EditorTarget.parse("https://x.dev/a.ts:3", cwd: "/w") == nil)
        #expect(EditorTarget.parse("file:///w/a.ts", cwd: "/w") == nil)
        #expect(EditorTarget.parse("", cwd: "/w") == nil)
        #expect(EditorTarget.parse(":12", cwd: "/w") == nil)
        #expect(EditorTarget.parse("/w/a.ts:0", cwd: "/w")?.line == nil)
    }
}

@Suite("Editor socket path")
struct EditorSocketPathTests {
    @Test func socketPathNamesThePane() throws {
        let pane = PaneID()

        let path = try EditorSocketPath.make(directory: "/tmp/smalti-501", pane: pane)

        #expect(path == "/tmp/smalti-501/nvim-\(pane.rawValue.uuidString.lowercased()).sock")
    }

    @Test func socketPathTooLongIsError() {
        let directory = "/tmp/" + String(repeating: "d", count: 60)

        #expect(throws: EditorError.self) {
            _ = try EditorSocketPath.make(directory: directory, pane: PaneID())
        }
    }
}

@Suite("Edited files")
struct EditedFilesTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func edit(_ path: String) -> FileEdit { FileEdit(tool: "Edit", path: path, newText: "x") }

    /// Final review: reads finish in any order; the newest edit still comes first.
    @Test func lateRecordOfAnOlderEditStaysBelow() {
        var files = EditedFiles()
        files.record(edit("/w/new.ts"), line: 1, at: t0.addingTimeInterval(10))

        files.record(edit("/w/old.ts"), line: 1, at: t0)

        #expect(files.recent.map(\.path) == ["/w/new.ts", "/w/old.ts"])
    }

    @Test func capsAtTwentyAndDeduplicates() {
        var files = EditedFiles()
        for index in 0..<25 {
            files.record(edit("/w/f\(index).ts"), line: index, at: t0.addingTimeInterval(TimeInterval(index)))
        }
        files.record(edit("/w/f10.ts"), line: 99, at: t0.addingTimeInterval(100))

        #expect(files.recent.count == EditedFiles.limit)
        #expect(files.recent.first == EditedFile(path: "/w/f10.ts", line: 99, at: t0.addingTimeInterval(100)))
        #expect(files.recent.filter { $0.path == "/w/f10.ts" }.count == 1)
        #expect(files.recent.last?.path == "/w/f5.ts")
    }

    @Test func lineOfFindsFirstLineOrOne() {
        let file = "import x\n\nfunc greet() {\n  print(1)\n}\n"

        #expect(TrackEditedFiles.lineOf(newText: "\n  func greet() {\n}", in: file) == 3)
        #expect(TrackEditedFiles.lineOf(newText: "absent", in: file) == 1)
        #expect(TrackEditedFiles.lineOf(newText: nil, in: file) == 1)
        #expect(TrackEditedFiles.lineOf(newText: "x", in: "") == 1)
    }

    @MainActor
    @Test func tracksOnlyTheEditsOfEachPane() async {
        let paneA = PaneID()
        let paneB = PaneID()
        let tracker = TrackEditedFiles(readFile: { _ in "a\nfunc greet() {\n" })

        await tracker.record(
            AgentEvent(
                pane: paneA, hook: .postToolUse, at: t0, sessionID: nil,
                edit: FileEdit(tool: "Edit", path: "/w/a.ts", newText: "func greet() {")))
        await tracker.record(AgentEvent(pane: paneB, hook: .stop, at: t0, sessionID: nil))

        #expect(tracker.recent(in: paneA) == [EditedFile(path: "/w/a.ts", line: 2, at: t0)])
        #expect(tracker.recent(in: paneB).isEmpty)
    }

    /// ⌘⇧E moves the focus to Neovim: from there, the workspace's agents' edits still count.
    @MainActor
    @Test func paneWithoutEditsFallsBackToItsWorkspace() async {
        let agent = PaneID()
        let nvim = PaneID()
        let elsewhere = PaneID()
        let tracker = TrackEditedFiles(readFile: { _ in "x\n" })
        await tracker.record(
            AgentEvent(
                pane: agent, hook: .postToolUse, at: t0, sessionID: nil,
                edit: FileEdit(tool: "Edit", path: "/w/a.ts", newText: "x")))
        await tracker.record(
            AgentEvent(
                pane: elsewhere, hook: .postToolUse, at: t0.addingTimeInterval(5), sessionID: nil,
                edit: FileEdit(tool: "Edit", path: "/w/b.ts", newText: "x")))

        #expect(tracker.recent(in: nvim, workspace: [agent, nvim]).map(\.path) == ["/w/a.ts"])
        #expect(tracker.recent(in: agent, workspace: [agent, nvim, elsewhere]).map(\.path) == ["/w/a.ts"])
        #expect(tracker.recent(in: nvim, workspace: [agent, elsewhere]).map(\.path) == ["/w/b.ts", "/w/a.ts"])
    }

    @Test func noEditsText() {
        #expect(EditedFiles.noneText == "Claude no ha editado archivos en este espacio")
    }

    @MainActor
    @Test func fileIsReadOffTheMainActor() async {
        let readOnMain = ThreadFlag()
        let tracker = TrackEditedFiles(readFile: { _ in
            readOnMain.set(Thread.isMainThread)
            return "x\n"
        })

        await tracker.record(
            AgentEvent(
                pane: PaneID(), hook: .postToolUse, at: t0, sessionID: nil,
                edit: FileEdit(tool: "Edit", path: "/w/a.ts", newText: "x")))

        #expect(readOnMain.value == false)
    }
}

@MainActor
@Suite("Open in editor")
struct OpenInEditorTests {
    private let origin = PaneID()
    private let target = EditorTarget(path: "/w/a b.ts", line: 12, column: nil)

    @Test func jumpsToLastFocusedNvim() async {
        let bridge = FakeEditorBridge()
        let near = PaneID()
        let far = PaneID()
        let panes = FakeEditorPanes(editors: [(near, "/s/near.sock"), (far, "/s/far.sock")])
        let open = OpenInEditor(bridge: bridge, panes: panes, socketDirectory: "/s", nvim: "nvim")

        let outcome = await open.open(target, from: origin)

        #expect(outcome == .jumped(near))
        #expect(bridge.opened == [EditorBridgeCall(target: target, socket: "/s/near.sock")])
    }

    @Test func opensBesideWhenNoNvim() async throws {
        let open = OpenInEditor(
            bridge: FakeEditorBridge(), panes: FakeEditorPanes(editors: []), socketDirectory: "/s",
            nvim: "nvim")

        let outcome = await open.open(target, from: origin)

        guard case .opened(let socket, let command, let beside) = outcome else {
            Issue.record("expected a new pane, got \(outcome)")
            return
        }
        #expect(beside == origin)
        #expect(socket.hasPrefix("/s/nvim-") && socket.hasSuffix(".sock"))
        #expect(command == "nvim --listen \(socket) +12 '/w/a b.ts'")
    }

    @Test func deadNvimFallsBackToTheNextThenANewPane() async {
        let bridge = FakeEditorBridge()
        bridge.unreachable = ["/s/near.sock"]
        let far = PaneID()
        let panes = FakeEditorPanes(editors: [(PaneID(), "/s/near.sock"), (far, "/s/far.sock")])

        let outcome = await OpenInEditor(bridge: bridge, panes: panes, socketDirectory: "/s", nvim: "nvim")
            .open(target, from: origin)

        #expect(outcome == .jumped(far))
    }

    @Test func commandUsesTheConfiguredNvim() {
        let command = EditorCommand.launch(
            nvim: "nvim --clean", socket: "/s/x.sock", target: EditorTarget(path: "/w/a.ts", line: nil, column: nil))

        #expect(command == "nvim --clean --listen /s/x.sock /w/a.ts")
    }
}

final class ThreadFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    var value: Bool? { lock.withLock { stored } }
    func set(_ flag: Bool) { lock.withLock { stored = flag } }
}

@Suite("Edited files in the palette")
struct EditedFilesPaletteTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func editedFilesAreAGroupWithLineAndAge() throws {
        let workspace = Workspace.empty(
            name: "w", rootDirectory: try WorkingDirectory(path: "/w"), layout: DwindleLayout())
        let edited = [
            EditedFile(path: "/w/src/reminder.service.ts", line: 42, at: now.addingTimeInterval(-120)),
            EditedFile(path: "/w/a b.ts", line: 1, at: now.addingTimeInterval(-10)),
        ]

        let commands = CommandCatalog.commands(
            for: CatalogState(workspaces: WorkspaceSet(first: workspace), editedFiles: edited, now: now),
            keymap: .standard, layouts: .standard
        ).filter { $0.group == .editedFiles }

        #expect(commands.map(\.title) == ["reminder.service.ts", "a b.ts"])
        #expect(commands.map(\.subtitle) == ["línea 42 · hace 2 min", "línea 1 · ahora"])
        #expect(commands.allSatisfy { !$0.isCurrent }, "an edited file is never the current item")
        #expect(
            commands.first?.id.editorTarget == EditorTarget(path: "/w/src/reminder.service.ts", line: 42, column: nil))
        #expect(CommandGroup.editedFiles.rawValue == "Editados por Claude")
    }

    @Test func editorOpenRoundTripsHostilePaths() {
        let id = CommandID.editorOpen(path: "/w/a:b 'c'.ts", line: 7)

        #expect(id.editorTarget == EditorTarget(path: "/w/a:b 'c'.ts", line: 7, column: nil))
        #expect(CommandID.paletteOpen.editorTarget == nil)
    }

    @Test func elapsedPhrases() {
        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-30), now: now) == "ahora")
        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-60), now: now) == "hace 1 min")
        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-3599), now: now) == "hace 59 min")
        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-7200), now: now) == "hace 2 h")
        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-3 * 86_400), now: now) == "hace 3 d")
    }
}

@Suite("EditorCommand.reopen")
struct EditorReopenTests {
    private let position = EditorPosition(file: "/w/reminder.service.ts", line: 42)
    private let pane = PaneID(rawValue: UUID(uuidString: "7F3A9C2E-0000-4000-8000-000000000001") ?? UUID())

    @Test func reopensListeningOnThePanesSocket() {
        #expect(
            EditorCommand.reopen(nvim: "nvim", socketDirectory: "/tmp/s", position: position, pane: pane)
                == "nvim --listen /tmp/s/nvim-7f3a9c2e-0000-4000-8000-000000000001.sock +42 /w/reminder.service.ts")
    }

    /// Final review: a Neovim saved as its process still listens on Smalti's socket after a restore.
    @Test func listenSocketIsFoundOnlyInSmaltisFolder() {
        let ours = ["nvim", "--clean", "--listen", "/tmp/s/nvim-1.sock", "+3", "a.ts"]

        #expect(EditorCommand.listenSocket(in: ours, directory: "/tmp/s") == "/tmp/s/nvim-1.sock")
        #expect(EditorCommand.listenSocket(in: ours, directory: "/tmp/other") == nil)
        #expect(EditorCommand.listenSocket(in: ["nvim", "--listen"], directory: "/tmp/s") == nil)
        #expect(EditorCommand.listenSocket(in: ["nvim", "a.ts"], directory: "/tmp/s") == nil)
    }

    @Test func tooLongSocketFallsBackToPlainCommand() {
        let deep = "/" + String(repeating: "d", count: 100)

        #expect(
            EditorCommand.reopen(nvim: "nvim", socketDirectory: deep, position: position, pane: pane)
                == position.plainCommand)
    }
}

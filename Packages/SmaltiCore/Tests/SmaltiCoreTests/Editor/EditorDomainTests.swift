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

        guard case .opened(let pane, let command, let beside) = outcome else {
            Issue.record("expected a new pane, got \(outcome)")
            return
        }
        #expect(beside == origin)
        #expect(command == "nvim --listen \(try EditorSocketPath.make(directory: "/s", pane: pane)) +12 '/w/a b.ts'")
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

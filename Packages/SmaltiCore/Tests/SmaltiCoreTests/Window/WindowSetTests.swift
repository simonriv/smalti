import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("WindowSet")
struct WindowSetTests {
    private let root: WorkingDirectory

    init() throws {
        root = try WorkingDirectory(path: "/tmp/project")
    }

    private func window(panes: Int = 0, workspaces: Int = 1) -> WindowState {
        let sets = (0..<workspaces).map { index in
            (0..<panes).reduce(Workspace.empty(name: "w\(index)", rootDirectory: root, layout: DwindleLayout())) {
                workspace, _ in workspace.adding(Pane(id: PaneID(), workingDirectory: root))
            }
        }
        let set = sets.dropFirst().reduce(WorkspaceSet(first: sets[0])) { $0.adding($1) }
        return WindowState(id: WindowID(), workspaces: set, frame: nil, isFullScreen: false)
    }

    @Test func openingPutsWindowInFront() {
        let first = window()
        let second = window()

        let set = WindowSet(first: first).opening(second)

        #expect(set.frontID == second.id)
        #expect(set.windows.map(\.id) == [first.id, second.id])
    }

    @Test func closingLastThrows() {
        let only = window()

        #expect(throws: WindowSetError.lastWindow) { try WindowSet(first: only).closing(only.id) }
    }

    @Test func closingFrontBringsPreviousToFront() throws {
        let first = window()
        let second = window()

        let set = try WindowSet(first: first).opening(second).closing(second.id)

        #expect(set.frontID == first.id)
        #expect(set.windows.count == 1)
    }

    @Test func closingABackWindowKeepsTheFront() throws {
        let first = window()
        let second = window()

        let set = try WindowSet(first: first).opening(second).closing(first.id)

        #expect(set.frontID == second.id)
    }

    @Test func bringingToFrontChangesOnlyTheFront() {
        let first = window()
        let second = window()

        let set = WindowSet(first: first).opening(second).bringingToFront(first.id)

        #expect(set.frontID == first.id)
        #expect(set.windows.map(\.id) == [first.id, second.id])
    }

    @Test func bringingAnUnknownWindowToFrontDoesNothing() {
        let first = window()

        #expect(WindowSet(first: first).bringingToFront(WindowID()).frontID == first.id)
    }

    @Test(arguments: [0, 1, 9])
    func allPanesSpansEveryWorkspaceOfEveryWindow(_ panes: Int) {
        let set = WindowSet(first: window(panes: panes, workspaces: 2)).opening(window(panes: panes))

        #expect(set.allPanes.count == panes * 3)
    }

    @Test func updatingChangesOnlyThatWindow() {
        let first = window()
        let second = window()
        let frame = Rect(x: 10, y: 20, width: 800, height: 600)

        let set = WindowSet(first: first).opening(second).updating(first.id) { $0.moved(to: frame) }

        #expect(set.windows[0].frame == frame)
        #expect(set.windows[1].frame == nil)
    }

    @Test func structureListsEveryWindowsWorkspacesWithoutFrames() {
        let first = window(panes: 1)
        let moved = WindowSet(first: first).updating(first.id) { $0.moved(to: Rect(x: 1, y: 2, width: 3, height: 4)) }

        #expect(WindowSet(first: first).structure == moved.structure)
        #expect(WindowSet(first: first).opening(window()).structure.count == 4)
    }

    @Test func frontIsTheFrontWindowState() {
        let first = window()
        let second = window()

        #expect(WindowSet(first: first).opening(second).front.id == second.id)
    }
}

/// Block 3 review: ⌘J goes to the agent that has waited longest, in whichever window.
@MainActor
@Suite("AttentionQueue · windows")
struct AttentionAcrossWindowsTests {
    private func waiting(since seconds: Double) -> Pane {
        let base = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/tmp"))
        let event = AgentEvent(
            pane: base.id, hook: .stop, at: Date(timeIntervalSince1970: seconds), sessionID: UUID().uuidString,
            prompt: "x", toolSummary: "ls", message: "m")
        return base.applying(event).0
    }

    private func window(_ panes: [Pane]) throws -> WindowState {
        let root = try WorkingDirectory(path: "/tmp")
        let workspace = panes.reduce(Workspace.empty(name: "w", rootDirectory: root, layout: DwindleLayout())) {
            $0.adding($1)
        }
        return WindowState(id: WindowID(), workspaces: WorkspaceSet(first: workspace), frame: nil, isFullScreen: false)
    }

    @Test func longestWaitingComesFirstAcrossWindows() throws {
        let recent = waiting(since: 500)
        let oldest = waiting(since: 100)
        let set = WindowSet(first: try window([recent])).opening(try window([oldest]))

        #expect(AttentionQueue.panes(in: set).first == oldest.id)
    }
}

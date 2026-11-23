import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("SessionSnapshot v2")
struct SessionSnapshotV2Tests {
    private let root: WorkingDirectory
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        root = try WorkingDirectory(path: "/Users/s/dev/solen")
    }

    private func window(_ name: String, frame: Rect?, fullScreen: Bool = false) -> WindowState {
        let workspace = Workspace.empty(name: name, rootDirectory: root, layout: DwindleLayout())
            .adding(Pane(id: PaneID(), workingDirectory: root))
        return WindowState(
            id: WindowID(), workspaces: WorkspaceSet(first: workspace), frame: frame, isFullScreen: fullScreen)
    }

    private func savedSnapshot(_ json: String) throws -> SessionSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionSnapshot.self, from: Data(json.utf8))
    }

    @Test func captureWritesVersionTwoWithEveryWindow() {
        let frame = Rect(x: 10, y: 20, width: 800, height: 600)
        let set = WindowSet(first: window("solen", frame: frame)).opening(window("billi", frame: nil, fullScreen: true))

        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)

        #expect(snapshot.version == 2)
        #expect(snapshot.windows.map(\.frame) == [frame, nil])
        #expect(snapshot.windows.map(\.isFullScreen) == [false, true])
        #expect(snapshot.windows.map { $0.workspaces.map(\.name) } == [["solen"], ["billi"]])
    }

    @Test func captureKeepsFrontIndex() {
        let first = window("solen", frame: nil)
        let set = WindowSet(first: first).opening(window("billi", frame: nil)).bringingToFront(first.id)

        #expect(SessionSnapshot.capture(set, scrollbackLines: [:], at: now).frontIndex == 0)
    }

    @Test func workspacesListsEveryWindowInOrder() {
        let set = WindowSet(first: window("solen", frame: nil)).opening(window("billi", frame: nil))

        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)

        #expect(snapshot.workspaces.map(\.name) == ["solen", "billi"])
    }

    /// A session saved by F2–F4 (format 1): its workspaces become one window without a frame.
    @Test func v1DecodesAsOneWindowWithoutFrame() throws {
        let json = """
            {"version":1,"savedAt":"2026-11-20T10:00:00Z","activeIndex":1,"workspaces":[
            {"name":"solen","rootDirectory":"/tmp","layout":"dwindle","panes":[]},
            {"name":"billi","rootDirectory":"/tmp","layout":"columns","panes":[]}]}
            """

        let snapshot = try savedSnapshot(json)

        #expect(snapshot.version == 1)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].frame == nil)
        #expect(snapshot.windows[0].isFullScreen == false)
        #expect(snapshot.windows[0].activeIndex == 1)
        #expect(snapshot.windows[0].workspaces.map(\.name) == ["solen", "billi"])
        #expect(snapshot.frontIndex == 0)
    }

    /// Block 1 review: a format-1 session read and saved again must come back readable, as format 2.
    @Test func v1SavedAgainIsWrittenAsVersionTwo() throws {
        let v1 = try savedSnapshot(
            """
            {"version":1,"savedAt":"2026-11-20T10:00:00Z","activeIndex":0,"workspaces":[
            {"name":"solen","rootDirectory":"/tmp","layout":"dwindle","panes":[]}]}
            """)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let reread = try savedSnapshot(String(decoding: try encoder.encode(v1), as: UTF8.self))

        #expect(reread.version == 2)
        #expect(reread.windows == v1.windows)
    }

    @Test func v2RoundTrips() throws {
        let set = WindowSet(first: window("solen", frame: Rect(x: 1, y: 2, width: 3, height: 4)))
            .opening(window("billi", frame: nil, fullScreen: true))
        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try savedSnapshot(String(decoding: try encoder.encode(snapshot), as: UTF8.self))

        #expect(decoded == snapshot)
    }

    @Test func singleWindowInitIsOneWindowWithoutFrame() {
        let workspace = WorkspaceSnapshot(
            name: "solen", rootDirectory: "/tmp", layout: "dwindle", tree: nil, focusedIndex: nil, panes: [])

        let snapshot = SessionSnapshot(version: 2, savedAt: now, workspaces: [workspace], activeIndex: 0)

        #expect(
            snapshot.windows == [
                WindowSnapshot(frame: nil, isFullScreen: false, workspaces: [workspace], activeIndex: 0)
            ])
        #expect(snapshot.frontIndex == 0)
    }

    @Test func restoreSelectionDefaultsSpanAllWindows() {
        let set = WindowSet(first: window("solen", frame: nil)).opening(window("billi", frame: nil))
        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)

        #expect(RestoreSelection.defaults(for: snapshot).checkedCount(in: snapshot) == 2)
    }

    @Test func restorePlanOfASessionUsesTheFrontWindow() {
        let set = WindowSet(first: window("solen", frame: nil)).opening(window("billi", frame: nil))
        let snapshot = SessionSnapshot.capture(set, scrollbackLines: [:], at: now)

        let plan = RestorePlan.make(from: snapshot, mode: .full, selection: RestoreSelection.defaults(for: snapshot))

        #expect(plan.workspaces.map(\.name) == ["billi"])
    }

    @Test func restorePlanOfAnEmptySessionIsEmpty() {
        let snapshot = SessionSnapshot(version: 2, savedAt: now, windows: [], frontIndex: 0)

        #expect(
            RestorePlan.make(from: snapshot, mode: .full, selection: RestoreSelection(unchecked: [])).workspaces.isEmpty
        )
    }
}

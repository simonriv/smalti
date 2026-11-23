import Foundation
import XCTest

/// Writes a saved session into an isolated launch's state directory, in the JSON format of `FileSessionArchive`.
enum SessionState {
    struct Pane {
        let id = UUID()
        let directory: String
        var agentSessionID: String?
        var relaunch: [String]?
        var title: String?
        var process: String?
        var lines = 0
        var commands = 0
    }

    struct Workspace {
        let name: String
        let root: String
        let layout: String
        let panes: [Pane]
    }

    /// A format-1 session (F2–F4): one window's workspaces at the top level.
    static func seed(_ workspaces: [Workspace], activeIndex: Int = 0, alwaysRestore: Bool, in app: XCUIApplication) {
        let snapshot: [String: Any] = [
            "version": 1, "savedAt": "2026-11-21T23:48:00Z", "activeIndex": activeIndex,
            "workspaces": workspaces.map(json),
        ]
        write(snapshot, alwaysRestore: alwaysRestore, in: app)
    }

    /// One saved window (format 2, F4.5): its frame in AppKit screen coordinates and its workspaces.
    struct Window {
        let frame: (x: Double, y: Double, width: Double, height: Double)?
        let workspaces: [Workspace]
        var isFullScreen = false
    }

    /// A format-2 session with several windows; `frontIndex` is the one in front.
    static func seed(windows: [Window], frontIndex: Int = 0, alwaysRestore: Bool, in app: XCUIApplication) {
        let snapshot: [String: Any] = [
            "version": 2, "savedAt": "2026-11-21T23:48:00Z", "frontIndex": frontIndex,
            "windows": windows.map { window in
                var json: [String: Any] = [
                    "isFullScreen": window.isFullScreen, "activeIndex": 0, "workspaces": window.workspaces.map(json),
                ]
                if let frame = window.frame {
                    json["frame"] = [
                        "origin": ["x": frame.x, "y": frame.y], "size": ["width": frame.width, "height": frame.height],
                    ]
                }
                return json
            },
        ]
        write(snapshot, alwaysRestore: alwaysRestore, in: app)
    }

    private static func write(_ snapshot: [String: Any], alwaysRestore: Bool, in app: XCUIApplication) {
        let directory = app.stateDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: snapshot).write(to: directory.appending(path: "session.json"))
            let preference = ["restore": alwaysRestore ? "always" : "ask"]
            try JSONSerialization.data(withJSONObject: preference).write(
                to: directory.appending(path: "preferences.json"))
        } catch {
            XCTFail("could not seed the session in \(directory.path(percentEncoded: false)): \(error)")
        }
    }

    private static func json(_ workspace: Workspace) -> [String: Any] {
        [
            "name": workspace.name, "rootDirectory": workspace.root, "layout": workspace.layout, "focusedIndex": 0,
            "panes": workspace.panes.map(json),
        ]
    }

    private static func json(_ pane: Pane) -> [String: Any] {
        var json: [String: Any] = [
            "id": pane.id.uuidString, "workingDirectory": pane.directory, "scrollbackLines": pane.lines,
            "commandCount": pane.commands,
        ]
        if let process = pane.process { json["processName"] = process }
        if let session = pane.agentSessionID {
            var agent: [String: Any] = ["harness": "claude", "sessionID": session, "lastState": "waiting"]
            if let title = pane.title { agent["title"] = title }
            json["agent"] = agent
        }
        if let relaunch = pane.relaunch { json["relaunch"] = ["arguments": relaunch] }
        return json
    }
}

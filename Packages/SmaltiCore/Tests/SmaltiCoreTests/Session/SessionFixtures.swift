import Foundation
import SmaltiCore

enum SessionFixtures {
    static let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
    static let now = Date(timeIntervalSince1970: 1_800_003_600)

    static func directory(_ path: String) -> WorkingDirectory {
        // Fixture paths are literal absolute paths.
        guard let directory = try? WorkingDirectory(path: path) else { preconditionFailure("not absolute: \(path)") }
        return directory
    }

    static func pane(_ path: String = "/Users/s/dev/solen", id: UUID = UUID()) -> PlannedPane {
        PlannedPane(id: id, workingDirectory: path, restoresScrollback: true, restoresHistory: true, launch: .shell)
    }

    static func pane(_ path: String = "/Users/s/dev/solen", launch: PaneLaunch, id: UUID = UUID()) -> PlannedPane {
        PlannedPane(id: id, workingDirectory: path, restoresScrollback: false, restoresHistory: true, launch: launch)
    }

    static func workspace(
        _ name: String, _ panes: [PlannedPane], tree: SnapshotTree? = nil, focusedIndex: Int = 0
    ) -> PlannedWorkspace {
        PlannedWorkspace(
            name: name, rootDirectory: "/Users/s/dev/\(name)", layout: .dwindle, tree: tree,
            focusedIndex: focusedIndex, panes: panes)
    }
}

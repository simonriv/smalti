import Foundation
import SmaltiCore

/// A project file with one pane per entry: `command` runs it, `nil` is a shell.
func projectLayout(name: String = "rizaria", commands: [[String]?], layout: String = "dwindle") -> SharedLayout {
    let tree = commands.indices.dropFirst().reduce(SnapshotTree.leaf(index: 0)) {
        .split(axis: .sideBySide, ratio: 0.5, first: $0, second: .leaf(index: $1))
    }
    return SharedLayout(
        smaltiLayout: 1, name: name, root: ".", layout: layout, focused: 0, tree: tree,
        panes: commands.map { SharedPane(directory: ".", command: $0) })
}

let projectDate = Date(timeIntervalSince1970: 1_800_000_000)

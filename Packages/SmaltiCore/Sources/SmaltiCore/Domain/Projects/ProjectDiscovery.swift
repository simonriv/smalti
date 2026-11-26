/// Finds the project a directory belongs to (F8.5): the nearest folder upwards with `.smalti/layout.json`. The climb
/// stops after the first folder holding `.git` (a repo, a submodule, a worktree), never looks at the home or `/`, and
/// gives up after `maximumLevels` folders. It only runs when ⌘K or ⌘O opens: nothing watches the disk.
public struct ProjectDiscovery {
    public static let maximumLevels = 32

    private let files: any ProjectFiles
    private let home: String

    public init(files: any ProjectFiles, home: String) {
        self.files = files
        self.home = Self.trimmed(home)
    }

    public func root(containing directory: String) -> String? {
        var folder = Self.trimmed(directory)
        guard folder.hasPrefix("/") else { return nil }
        for _ in 0..<Self.maximumLevels {
            guard folder != home, folder != "/" else { return nil }
            if files.hasLayout(in: folder) { return folder }
            if files.isRepositoryRoot(folder) { return nil }
            folder = Self.parent(of: folder)
        }
        return nil
    }

    private static func parent(of folder: String) -> String {
        guard let slash = folder.lastIndex(of: "/"), slash != folder.startIndex else { return "/" }
        return String(folder[..<slash])
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

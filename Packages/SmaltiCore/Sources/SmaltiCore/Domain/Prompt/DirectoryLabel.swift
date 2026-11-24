/// The directory as the prompt shows it (spec F5): inside a repository, from its root with the repository's name
/// (`solen/apps/api`); elsewhere the last two levels, as zsh's `%2~` (`~/Downloads`, `local/bin`).
public enum DirectoryLabel {
    private static let levels = 2

    public static func label(directory: String, home: String, repoRoot: String?) -> String {
        let path = trimmed(directory)
        if let root = repoRoot.map(trimmed), let inside = relative(path, to: root) {
            // A repository at the root has no name of its own: `/sub` (block 2 review, M8).
            let name = root == "/" ? "" : root.split(separator: "/").last.map(String.init) ?? root
            return inside.isEmpty ? (name.isEmpty ? "/" : name) : name + "/" + inside
        }
        return lastLevels(of: tilded(path, home: trimmed(home)))
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The part of `path` below `root`, or `nil` when `root` is not an ancestor (component by component).
    private static func relative(_ path: String, to root: String) -> String? {
        if path == root { return "" }
        let prefix = root == "/" ? "/" : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    private static func tilded(_ path: String, home: String) -> String {
        relative(path, to: home).map { $0.isEmpty ? "~" : "~/" + $0 } ?? path
    }

    private static func lastLevels(of path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > levels else { return path }
        return parts.suffix(levels).joined(separator: "/")
    }
}

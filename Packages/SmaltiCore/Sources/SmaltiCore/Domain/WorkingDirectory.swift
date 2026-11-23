/// Absolute directory a pane's shell runs in.
public struct WorkingDirectory: Hashable, Sendable {
    public let path: String

    public init(path: String) throws(WorkingDirectoryError) {
        guard path.hasPrefix("/") else { throw .notAbsolute(path: path) }
        self.path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The path with `home` written as `~`; unchanged when outside `home`.
    public func abbreviated(home: WorkingDirectory) -> String {
        if self == home { return "~" }
        if home.path == "/" { return path }
        let homePrefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        guard path.hasPrefix(homePrefix) else { return path }
        return "~/" + path.dropFirst(homePrefix.count)
    }

    /// Name of the innermost folder; `/` for the root.
    public var lastComponent: String {
        path == "/" ? path : String(path.split(separator: "/").last ?? "")
    }
}

public enum WorkingDirectoryError: Error, Equatable, Sendable {
    case notAbsolute(path: String)
}

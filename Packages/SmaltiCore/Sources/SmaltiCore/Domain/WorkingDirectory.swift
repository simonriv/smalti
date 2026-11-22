/// Absolute directory a pane's shell runs in.
public struct WorkingDirectory: Hashable, Sendable {
    public let path: String

    public init(path: String) throws(WorkingDirectoryError) {
        guard path.hasPrefix("/") else { throw .notAbsolute(path: path) }
        self.path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

public enum WorkingDirectoryError: Error, Equatable, Sendable {
    case notAbsolute(path: String)
}

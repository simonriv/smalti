import Foundation

/// A file the pane's Claude wrote, at the line its change starts.
public struct EditedFile: Equatable, Sendable {
    public let path: String
    public let line: Int
    public let at: Date

    public init(path: String, line: Int, at: Date) {
        self.path = path
        self.line = line
        self.at = at
    }

    public var fileName: String { path.split(separator: "/").last.map(String.init) ?? path }
}

/// "Editados por Claude": the last 20 files, newest first, each once (spec F6). Kept in memory only.
public struct EditedFiles: Equatable, Sendable {
    public static let limit = 20

    public private(set) var recent: [EditedFile] = []

    public init() {}

    public mutating func record(_ edit: FileEdit, line: Int, at date: Date) {
        recent.removeAll { $0.path == edit.path }
        recent.insert(EditedFile(path: edit.path, line: line, at: date), at: 0)
        if recent.count > Self.limit { recent.removeLast(recent.count - Self.limit) }
    }
}

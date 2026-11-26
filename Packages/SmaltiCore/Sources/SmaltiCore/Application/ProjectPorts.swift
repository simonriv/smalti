import Foundation

/// Why a project's file or Smalti's record of projects could not be read or written (F8.5).
public enum ProjectFileError: Error, Equatable, Sendable {
    /// The repo no longer has `.smalti/layout.json`.
    case missing(root: String)
    case unreadable(root: String, reason: String)
    /// A link, a folder or a device where the file should be: never followed (review 1).
    case notRegularFile(root: String)
    case invalid(SharedLayoutError)
    /// The folder where a pane would run its command does not exist (final review).
    case missingFolder(pane: Int, path: String)
    case unwritable(path: String, reason: String)
}

/// The repo's `.smalti/layout.json` as read once: what opens and what is approved come from the same bytes.
public struct ProjectLayoutFile: Equatable, Sendable {
    public let layout: SharedLayout
    /// The file's content hash (SHA-256, hex), computed by the adapter.
    public let fingerprint: String

    public init(layout: SharedLayout, fingerprint: String) {
        self.layout = layout
        self.fingerprint = fingerprint
    }
}

/// The repos' project files: where they are and what they say. Paths are absolute.
public protocol ProjectFiles: AnyObject {
    /// Whether `directory/.smalti/layout.json` exists.
    func hasLayout(in directory: String) -> Bool
    /// Whether `directory` holds `.git` (a folder, or the file of a submodule or worktree).
    func isRepositoryRoot(_ directory: String) -> Bool
    /// Whether `path` is an existing folder.
    func folderExists(_ path: String) -> Bool
    /// `path` with its symbolic links resolved; `path` itself when it cannot be resolved.
    func realPath(_ path: String) -> String
    /// The validated project file at `root`.
    func layout(at root: String) throws(ProjectFileError) -> ProjectLayoutFile
    /// Writes `layout` as `root/.smalti/layout.json`; returns the written file's fingerprint.
    func write(_ layout: SharedLayout, to root: String) throws(ProjectFileError) -> String
}

/// The projects Smalti remembers (recents and approvals), in Smalti's own state, never in a repo.
public protocol ProjectRecords: AnyObject {
    func all() -> [ProjectRecord]
    func replace(with records: [ProjectRecord]) throws(ProjectFileError)
}

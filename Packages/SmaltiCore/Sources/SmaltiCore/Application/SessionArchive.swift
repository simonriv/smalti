import Foundation

public enum SessionArchiveError: Error, Equatable, Sendable {
    case writeFailed(file: String, reason: String)
    case notFound(name: String)
    /// F7.6: the file was written by a newer Smalti; it is left as it is.
    case newerFormat(file: String, version: Int)

    public var summary: String {
        switch self {
        case .writeFailed(let file, let reason): "\(file): \(reason)"
        case .notFound(let name): "\(name): not found"
        case .newerFormat(let file, let version):
            "\(file): guardado por una versión más nueva de Smalti (formato \(version))"
        }
    }
}

/// What the last run left behind.
public enum LastSession: Equatable, Sendable {
    case none
    case saved(SessionSnapshot)
    /// There was one, but it could not be read; the archive already set it aside.
    case unreadable(reason: String)
    /// F7.6: saved by a newer Smalti; neither restored nor overwritten.
    case newer(version: Int)
}

/// Port: keeps the snapshot of the window between runs.
@MainActor
public protocol SessionArchive: AnyObject {
    func save(_ snapshot: SessionSnapshot) throws(SessionArchiveError)
    func lastSession() -> LastSession
}

/// Port: keeps each pane's scrollback between runs.
@MainActor
public protocol PaneTranscripts: AnyObject {
    func keep(_ scrollback: Scrollback, for pane: PaneID) throws(SessionArchiveError)
    func scrollback(of pane: PaneID) -> Scrollback?
    /// Drops what is kept for panes that no longer exist.
    func forget(allExcept panes: Set<PaneID>)
}

/// Port: layouts saved by name ("solen-dev").
@MainActor
public protocol NamedLayouts: AnyObject {
    func save(_ layout: WorkspaceSnapshot, as name: LayoutName) throws(SessionArchiveError)
    func layout(named name: LayoutName) throws(SessionArchiveError) -> WorkspaceSnapshot
    func names() -> [LayoutName]
}

/// Why a shared layout file could not be read or written (spec F7).
public enum LayoutFileError: Error, Equatable, Sendable {
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)
    case invalid(SharedLayoutError)

    public var message: String {
        switch self {
        case .unreadable(let path, let reason): "no se pudo leer \(path) (\(reason))"
        case .unwritable(let path, let reason): "no se pudo escribir \(path) (\(reason))"
        case .invalid(let error): error.message
        }
    }
}

/// Port (F7): shared layout files, wherever the user picks them.
@MainActor
public protocol LayoutFiles: AnyObject {
    func write(_ layout: SharedLayout, to file: URL) throws(LayoutFileError)
    func read(from file: URL) throws(LayoutFileError) -> SharedLayout
}

/// Whether reopening asks first ("Retomar donde quedaste") or restores everything ("Siempre restaurar").
public enum RestorePreference: String, Codable, Sendable {
    case ask, always
}

/// Port: the "Siempre restaurar" choice (in the app's state until F5 moves it to the TOML).
@MainActor
public protocol RestorePreferenceStore: AnyObject {
    func current() -> RestorePreference
    func set(_ preference: RestorePreference) throws(SessionArchiveError)
}

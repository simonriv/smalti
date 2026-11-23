import Foundation

/// Where per-pane files live inside the state directory. Shared by the panes' environment and the archive.
public struct PaneFileLocator: Sendable {
    public let stateDirectory: URL

    public init(stateDirectory: URL) {
        self.stateDirectory = stateDirectory
    }

    public var historyDirectory: URL { stateDirectory.appending(path: "history") }

    public func historyFile(for pane: PaneID) -> URL {
        historyDirectory.appending(path: "\(pane).zsh_history")
    }
}

/// How a pane's programs reach this Smalti: its socket and its CLI, put first in the pane's `PATH`.
public struct IPCEndpoints: Sendable {
    public let socket: URL
    public let cli: URL
    /// The `PATH` the app was started with.
    public let inheritedPath: String

    public init(socket: URL, cli: URL, inheritedPath: String) {
        self.socket = socket
        self.cli = cli
        self.inheritedPath = inheritedPath
    }
}

/// The variables every pane's process receives. `SMALTI` and `SMALTI_VERSION` (R1) win over `extra`.
public struct PaneEnvironment: Sendable {
    private let version: String
    private let extra: [String: String]
    private let files: PaneFileLocator?
    private let ipc: IPCEndpoints?

    public init(
        version: String, extra: [String: String] = [:], files: PaneFileLocator? = nil, ipc: IPCEndpoints? = nil
    ) {
        self.version = version
        self.extra = extra
        self.files = files
        self.ipc = ipc
    }

    public func variables(for pane: PaneID) -> [String: String] {
        var variables = extra.merging(ChildEnvironment.smalti(version: version)) { _, smalti in smalti }
        variables["SMALTI_PANE_ID"] = pane.description
        if let files { variables["SMALTI_HISTORY_FILE"] = files.historyFile(for: pane).path(percentEncoded: false) }
        if let ipc {
            variables["SMALTI_SOCKET"] = ipc.socket.path(percentEncoded: false)
            variables["SMALTI_CLI"] = ipc.cli.path(percentEncoded: false)
            var binDirectory = ipc.cli.deletingLastPathComponent().path(percentEncoded: false)
            if binDirectory.hasSuffix("/") { binDirectory.removeLast() }
            variables["PATH"] = binDirectory + ":" + ipc.inheritedPath
        }
        return variables
    }
}

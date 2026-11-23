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

/// The variables every pane's process receives. `SMALTI` and `SMALTI_VERSION` (R1) win over `extra`.
public struct PaneEnvironment: Sendable {
    private let version: String
    private let extra: [String: String]
    private let files: PaneFileLocator?

    public init(version: String, extra: [String: String] = [:], files: PaneFileLocator? = nil) {
        self.version = version
        self.extra = extra
        self.files = files
    }

    public func variables(for pane: PaneID) -> [String: String] {
        var variables = extra.merging(ChildEnvironment.smalti(version: version)) { _, smalti in smalti }
        variables["SMALTI_PANE_ID"] = pane.description
        if let files { variables["SMALTI_HISTORY_FILE"] = files.historyFile(for: pane).path(percentEncoded: false) }
        return variables
    }
}

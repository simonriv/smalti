import Foundation

/// A coding-agent session saved on disk by its harness, as the session search shows it.
public struct HarnessSession: Equatable, Sendable {
    public let harness: HarnessID
    public let id: String
    public let directory: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    /// What the row adds after the project: model or provider, when the harness keeps them.
    public let detail: String?
    /// F7.7: the tokens the harness counted, written by the search in the interface's language.
    public var tokens: Int?

    public init(
        harness: HarnessID, id: String, directory: String, title: String, createdAt: Date, updatedAt: Date,
        detail: String?
    ) {
        self.harness = harness
        self.id = id
        self.directory = directory
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.detail = detail
    }

    /// The project as the row names it: the last component of the directory.
    public var project: String { directory.split(separator: "/").last.map(String.init) ?? directory }
}

/// Why a harness's sessions could not be read. A changed format is an error, never a crash (spec F6).
public enum HarnessError: Error, Equatable, Sendable {
    case storeMissing(harness: HarnessID, path: String)
    case unreadable(harness: HarnessID, path: String, reason: String)
    case unknownSchema(harness: HarnessID, path: String, missing: String)
    case timedOut(harness: HarnessID)

    public var harness: HarnessID {
        switch self {
        case .storeMissing(let harness, _), .unreadable(let harness, _, _), .unknownSchema(let harness, _, _),
            .timedOut(let harness):
            harness
        }
    }

    /// Secondary text in the search ("No se pudo leer Codex: esquema desconocido (falta cwd)").
    public func message(_ texts: SessionTexts) -> String {
        texts.readFailed(["harness": harness.displayName, "reason": reason(texts)])
    }

    private func reason(_ texts: SessionTexts) -> String {
        switch self {
        case .storeMissing(_, let path): texts.storeMissing(["path": path])
        case .unreadable(_, _, let reason): reason
        case .unknownSchema(_, _, let missing): texts.unknownSchema(["missing": missing])
        case .timedOut: texts.timedOut
        }
    }
}

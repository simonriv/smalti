import Foundation

/// One session's token use as a harness other than Claude reports it (F6: OpenCode in the Observatory).
public struct UsageRow: Equatable, Sendable {
    public let harness: HarnessID
    public let sessionID: String
    public let directory: String
    public let model: String?
    /// The model runs on this Mac (Ollama, LM Studio): the "Locales" filter.
    public let isLocal: Bool
    /// Input tokens, cache reads included, as the Observatory counts Claude's.
    public let input: Int
    public let output: Int
    public let startedAt: Date
    public let updatedAt: Date

    public init(
        harness: HarnessID, sessionID: String, directory: String, model: String?, isLocal: Bool, input: Int,
        output: Int, startedAt: Date, updatedAt: Date
    ) {
        self.harness = harness
        self.sessionID = sessionID
        self.directory = directory
        self.model = model
        self.isLocal = isLocal
        self.input = input
        self.output = output
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

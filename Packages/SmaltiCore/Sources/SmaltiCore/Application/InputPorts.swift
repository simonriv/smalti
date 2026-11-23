/// Guesses the rest of the line being typed. The heuristic one is the default; F7 adds API-backed ones.
public protocol PredictionProvider: Sendable {
    func predict(_ context: PredictionContext) -> Prediction?
}

public struct HistoryError: Error, Equatable, Sendable {
    public let operation: String
    public let file: String
    public let cause: String

    public init(operation: String, file: String, cause: String) {
        self.operation = operation
        self.file = file
        self.cause = cause
    }
}

public struct CompletionError: Error, Equatable, Sendable {
    public let command: String
    public let cause: String

    public init(command: String, cause: String) {
        self.command = command
        self.cause = cause
    }
}

/// Smalti's own command history, oldest first.
public protocol CommandHistory: Sendable {
    func load() async throws(HistoryError) -> [HistoryEntry]
    func append(_ entry: HistoryEntry) async throws(HistoryError)
}

/// The project around a directory: what predictions offer before there is history.
public protocol ProjectContext: Sendable {
    func snapshot(of directory: String) async -> ProjectSnapshot
}

/// Completion specs and what they need from outside the domain: their generators and the file system.
public protocol CompletionProvider: Sendable {
    /// The commands that have a spec, user specs included.
    var commands: [String] { get async }
    func spec(for command: String) async -> CompletionSpec?
    func generate(_ generator: GeneratorID, in directory: String) async throws(CompletionError) -> [Suggestion]
    /// Entries of the directory named by `prefix` (relative to `directory`), folders with a trailing `/`.
    func paths(matching prefix: String, in directory: String, foldersOnly: Bool) async -> [Suggestion]
}

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
    /// The spec only if it is already loaded: never loads, so highlighting never waits for JavaScript.
    func loadedSpec(for command: String) async -> CompletionSpec?
    /// Runs a generator for the words typed so far (`tokens`, the last one possibly partial) in `directory`.
    func generate(_ generator: GeneratorID, tokens: [String], in directory: String) async throws(CompletionError)
        -> [Suggestion]
    /// Entries of the directory named by `prefix` (relative to `directory`), folders with a trailing `/`.
    func paths(matching prefix: String, in directory: String, foldersOnly: Bool) async -> [Suggestion]
}

public enum PathKind: Equatable, Sendable {
    case file
    case directory
}

/// What is at a path, for highlighting the words that name files (spec F5.6). The path is absolute; `nil` means it
/// does not exist or cannot be read. A symbolic link is followed one level only, and no file is ever opened.
public protocol PathFacts: Sendable {
    func kind(of path: String) async -> PathKind?
}

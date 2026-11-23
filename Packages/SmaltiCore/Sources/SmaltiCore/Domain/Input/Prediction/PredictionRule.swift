import Foundation

/// What Smalti knows about the project in a directory: the commands it can offer without any history.
public struct ProjectSnapshot: Equatable, Sendable {
    public let scripts: [String]
    public let makeTargets: [String]
    public let branch: String?
    public let branches: [String]

    public init(scripts: [String], makeTargets: [String], branch: String?, branches: [String]) {
        self.scripts = scripts
        self.makeTargets = makeTargets
        self.branch = branch
        self.branches = branches
    }

    public static let empty = ProjectSnapshot(scripts: [], makeTargets: [], branch: nil, branches: [])
}

/// Everything a prediction may look at for one keystroke. `previous` is the last command of the same pane.
public struct PredictionContext: Sendable {
    public let line: InputLine
    public let directory: String
    public let previous: HistoryEntry?
    public let index: HistoryIndex
    public let project: ProjectSnapshot
    public let now: Date

    public init(
        line: InputLine, directory: String, previous: HistoryEntry?, index: HistoryIndex, project: ProjectSnapshot,
        now: Date
    ) {
        self.line = line
        self.directory = directory
        self.previous = previous
        self.index = index
        self.project = project
        self.now = now
    }
}

public struct Candidate: Equatable, Sendable {
    public let command: String
    public let score: Double

    public init(command: String, score: Double) {
        self.command = command
        self.score = score
    }
}

/// One source of whole-command guesses. Each source is its own type (OCP); the predictor adds up their scores.
public protocol PredictionRule: Sendable {
    /// Whether the rule may suggest with nothing typed: only what follows from the last command does.
    var worksOnEmptyLine: Bool { get }
    func candidates(_ context: PredictionContext) -> [Candidate]
}

/// What a stretch of the command line is, which decides its color. The raw value is its letter in the
/// `highlight` message.
public enum HighlightRole: Character, Sendable, CaseIterable {
    case command = "c"
    case subcommand = "s"
    case option = "o"
    case string = "q"
    case variable = "v"
    case path = "p"
    case `operator` = "x"
}

/// A colored stretch of the line; the range counts Unicode scalars, as zsh does.
public struct HighlightSpan: Equatable, Sendable {
    public let range: Range<Int>
    public let role: HighlightRole

    public init(range: Range<Int>, role: HighlightRole) {
        self.range = range
        self.role = role
    }
}

/// A word that may name a file: the text without quotes or escapes, and where it is in the line.
public struct PathCandidate: Equatable, Hashable, Sendable {
    public let word: String
    public let range: Range<Int>

    public init(word: String, range: Range<Int>) {
        self.word = word
        self.range = range
    }
}

/// What the line says by itself: its spans, the words worth asking the disk about, and the commands whose spec
/// was not at hand (their subcommands are missing until it loads).
public struct HighlightPlan: Equatable, Sendable {
    public let spans: [HighlightSpan]
    public let pathCandidates: [PathCandidate]
    public let commandsWithoutSpec: [String]

    public init(spans: [HighlightSpan], pathCandidates: [PathCandidate], commandsWithoutSpec: [String]) {
        self.spans = spans
        self.pathCandidates = pathCandidates
        self.commandsWithoutSpec = commandsWithoutSpec
    }
}

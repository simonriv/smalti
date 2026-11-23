/// What this pane usually runs after its last command, in this directory (`git add .` → `git commit`).
public struct LearnedSequence: PredictionRule {
    public static let weight = 2.0
    public let worksOnEmptyLine = true

    public init() {}

    public func candidates(_ context: PredictionContext) -> [Candidate] {
        guard let previous = context.previous else { return [] }
        return context.index.successors(of: previous.command, in: context.directory).map {
            Candidate(command: $0.key, score: Double($0.value) * Self.weight)
        }
    }
}

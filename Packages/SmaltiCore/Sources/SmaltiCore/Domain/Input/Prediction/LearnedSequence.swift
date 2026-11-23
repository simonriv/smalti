/// What this pane usually ran after its last command, filed under the directory where that command ran (so a
/// `cd web` still predicts what follows it inside `web`).
public struct LearnedSequence: PredictionRule {
    public static let weight = 2.0
    public let worksOnEmptyLine = true

    public init() {}

    public func candidates(_ context: PredictionContext) -> [Candidate] {
        guard let previous = context.previous else { return [] }
        return context.index.successors(of: previous.command, in: previous.directory).map {
            Candidate(command: $0.key, score: Double($0.value) * Self.weight)
        }
    }
}
